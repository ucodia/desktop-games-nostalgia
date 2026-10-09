"""Extract Desktop Games assets from a Peter executable into PNG/WAV + manifest.json.

Usage: uv run --no-project --with pillow --with pefile python extract.py ../stress_relief.exe <out_dir>
"""

import json
import os
import re
import struct
import sys
import wave

from PIL import Image

from petprg import B, LANG_EN, Program

SHADOW_ALPHA = 0x90


class BitReader:
    """Mirror of FUN_004089f0: 16-bit LSB-first words sharing the stream with literal bytes."""

    def __init__(self, data: bytes, pos: int = 0):
        self.d = data
        self.pos = pos
        self.state = 0

    def bit(self) -> int:
        if self.state >> 1 == 0:
            w = self.d[self.pos] | (self.d[self.pos + 1] << 8)
            self.pos += 2
            self.state = (w >> 1) | 0x8000
            return w & 1
        b = self.state & 1
        self.state >>= 1
        return b

    def byte(self) -> int:
        v = self.d[self.pos]
        self.pos += 1
        return v

    def bits3(self) -> int:
        return self.bit() | (self.bit() << 1) | (self.bit() << 2)


def decompress(src: bytes, size: int, width: int) -> bytearray:
    """Mirror of FUN_00408a50: Peter's 8-bit image codec (literal / left / up predictors)."""
    if size < width or width < 2:
        width = size
    out = bytearray()
    r = BitReader(src)
    n = size
    while n >= 1:
        if not r.bit():
            out.append(r.byte())
            n -= 1
            continue
        if not r.bit():
            if not r.bit():
                out.append(out[-1])
                n -= 1
                continue
            ln = r.bits3()
            if ln == 1:
                out.append(out[-2])
                n -= 1
                continue
            if ln == 0:
                ln = 22
            n -= ln
            v = out[-1]
            out.extend([v] * ln)
            continue
        if not r.bit():
            out.append(out[-width])
            n -= 1
            continue
        ln = r.bits3()
        if ln == 1:
            out.append(out[-width + 1])
            n -= 1
            continue
        if ln == 0:
            ln = 22
        n -= ln
        for _ in range(ln):
            out.append(out[-width])
    return out[:size]


def rgba_palette(prog: Program) -> list[tuple[int, int, int, int]]:
    pal = prog.block("PALETTE").data
    out = []
    for i in range(256):
        if i < len(pal) // 4:
            b, g, r, _ = pal[i * 4:i * 4 + 4]
            out.append((r, g, b, 255))
        else:
            out.append((0, 0, 0, 255))
    out[0] = (0, 0, 0, 0)
    out[1] = (0, 0, 0, SHADOW_ALPHA)
    return out


def to_image(pixels: bytes, w: int, h: int, pal) -> Image.Image:
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        row = pixels[y * w:(y + 1) * w]
        for x, c in enumerate(row):
            px[x, h - 1 - y] = pal[c]
    return img


def ms_adpcm_decode(data: bytes, channels: int, block_align: int, coefs: list) -> list[int]:
    adapt = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]
    out: list[int] = []
    c = channels
    for bstart in range(0, len(data), block_align):
        blk = data[bstart:bstart + block_align]
        if len(blk) < 7 * c:
            break
        pred = list(blk[0:c])
        delta = list(struct.unpack_from("<%dh" % c, blk, c))
        s1 = list(struct.unpack_from("<%dh" % c, blk, 3 * c))
        s2 = list(struct.unpack_from("<%dh" % c, blk, 5 * c))
        out += s2 + s1
        ch = 0
        for byte in blk[7 * c:]:
            for nib in (byte >> 4, byte & 0x0F):
                c1, c2 = coefs[pred[ch]]
                signed = nib - 16 if nib & 8 else nib
                p = ((s1[ch] * c1) + (s2[ch] * c2)) // 256 + signed * delta[ch]
                p = max(-32768, min(32767, p))
                out.append(p)
                s2[ch], s1[ch] = s1[ch], p
                delta[ch] = max(16, (adapt[nib] * delta[ch]) // 256)
                ch = (ch + 1) % c
    return out


def extract_app_icon(exe: str, out_png: str):
    """Save the executable's main icon (RT_GROUP_ICON 1) as a PNG."""
    import io

    import pefile

    pe = pefile.PE(exe)
    icons, groups = {}, {}
    for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        for e in t.directory.entries:
            for lang in e.directory.entries:
                data = pe.get_data(lang.data.struct.OffsetToData, lang.data.struct.Size)
                if t.id == pefile.RESOURCE_TYPE["RT_ICON"]:
                    icons[e.id] = data
                elif t.id == pefile.RESOURCE_TYPE["RT_GROUP_ICON"]:
                    groups[e.id] = data
    group = groups[min(groups)]
    count = struct.unpack_from("<H", group, 4)[0]
    entries = [struct.unpack_from("<BBBBHHIH", group, 6 + k * 14) for k in range(count)]
    best = max(entries, key=lambda e: ((e[0] or 256), e[5]))
    w, h, colors, res, planes, bpp, _size, icon_id = best
    data = icons[icon_id]
    ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", w, h, colors, res, planes, bpp, len(data), 22) + data
    Image.open(io.BytesIO(ico)).convert("RGBA").save(out_png)


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def main(exe: str, out: str):
    prog = Program(exe)
    pal = rgba_palette(prog)
    os.makedirs(out, exist_ok=True)
    manifest: dict = {"icons": [], "pictures": [], "sprites": [], "sounds": [], "palette": [list(c) for c in pal[:224]]}

    names: dict[tuple[int, int], str] = {}
    for g in prog.nodes[B["GLOBAL"]] + prog.nodes[B["LOCAL"]]:
        if g.dat_block in (B["PICTURE"], B["BACKGRND"], B["SPRITE"], B["SOUND"]) and g.dat_index >= 0:
            names.setdefault((g.dat_block, g.dat_index), prog.label(g, LANG_EN))

    def name_for(block: int, idx: int, prefix: str) -> str:
        return slug(names.get((block, idx), f"{prefix}_{idx}")) or f"{prefix}_{idx}"

    used: set[str] = set()

    def unique(n: str) -> str:
        base, k = n, 2
        while n in used:
            n = f"{base}_{k}"
            k += 1
        used.add(n)
        return n

    d = prog.block("PICTURE").data
    p = 0
    os.makedirs(f"{out}/icons", exist_ok=True)
    for i in range(prog.block("PICTURE").count):
        size = struct.unpack_from("<i", d, p)[0]
        px = decompress(d[p + 4:p + 4 + size], 32 * 32, 32)
        p += 4 + size
        center = px[16 * 32 + 16]
        to_image(px, 32, 32, pal).save(f"{out}/icons/icon_{i}.png")
        manifest["icons"].append({"index": i, "file": f"icons/icon_{i}.png", "center_color": list(pal[center])})

    d = prog.block("BACKGRND").data
    p = 0
    os.makedirs(f"{out}/pictures", exist_ok=True)
    for i in range(prog.block("BACKGRND").count):
        w, h, size = struct.unpack_from("<iii", d, p)
        px = decompress(d[p + 12:p + 12 + size], w * h, w)
        p += 12 + size
        n = unique(name_for(B["BACKGRND"], i, "picture"))
        to_image(px, w, h, pal).save(f"{out}/pictures/{n}.png")
        manifest["pictures"].append({"index": i, "name": n, "file": f"pictures/{n}.png", "width": w, "height": h})

    d = prog.block("SPRITE").data
    p = 0
    os.makedirs(f"{out}/sprites", exist_ok=True)
    for i in range(prog.block("SPRITE").count):
        phases, dirs, rest = struct.unpack_from("<iii", d, p)
        w, h = struct.unpack_from("<HH", d, p + 12)
        delay, level = struct.unpack_from("<ii", d, p + 16)
        steps = struct.unpack_from("<d", d, p + 24)[0]
        p += 32
        n = unique(name_for(B["SPRITE"], i, "sprite"))
        sheet = Image.new("RGBA", (w * phases, h * dirs))
        for k in range(phases * dirs):
            size = struct.unpack_from("<i", d, p)[0]
            px = decompress(d[p + 4:p + 4 + size], w * h, w)
            p += 4 + size
            dir_, ph = divmod(k, phases)
            sheet.paste(to_image(px, w, h, pal), (ph * w, dir_ * h))
        sheet.save(f"{out}/sprites/{n}.png")
        manifest["sprites"].append({
            "index": i, "name": n, "file": f"sprites/{n}.png", "width": w, "height": h,
            "phases": phases, "directions": dirs, "rest_phases": min(rest, phases),
            "delay_ms": delay, "level": level, "steps": steps,
        })

    d = prog.block("SOUND").data
    p = 0
    os.makedirs(f"{out}/sounds", exist_ok=True)
    for i in range(prog.block("SOUND").count):
        size, rate = struct.unpack_from("<ii", d, p)
        fmt, ch, bits = struct.unpack_from("<HBB", d, p + 8)
        body = d[p + 12:p + 12 + size]
        p += 12 + size
        n = unique(name_for(B["SOUND"], i, "sound"))
        if fmt == 1:
            pcm, out_rate, out_ch, out_bits = body, rate, ch, bits // 8
        elif fmt == 2:
            wtag, wch, wrate, _avg, walign, wbits, cb = struct.unpack_from("<HHIIHHH", body, 0)
            spb, ncoef = struct.unpack_from("<HH", body, 18)
            coefs = [struct.unpack_from("<hh", body, 22 + 4 * c) for c in range(ncoef)]
            samples = ms_adpcm_decode(body[18 + cb:], wch, walign, coefs)
            pcm = struct.pack("<%dh" % len(samples), *samples)
            out_rate, out_ch, out_bits = wrate, wch, 2
        else:
            raise ValueError(f"sound {i}: unsupported format {fmt}")
        with wave.open(f"{out}/sounds/{n}.wav", "wb") as wf:
            wf.setnchannels(out_ch)
            wf.setsampwidth(out_bits)
            wf.setframerate(out_rate)
            wf.writeframes(pcm)
        manifest["sounds"].append({"index": i, "name": n, "file": f"sounds/{n}.wav", "format": fmt, "rate": out_rate})

    extract_app_icon(exe, f"{out}/app_icon.png")

    with open(f"{out}/manifest.json", "w") as f:
        json.dump(manifest, f, indent=1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
