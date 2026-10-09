"""Reader for Gemtree Peter programs embedded in the `.petprg` PE section."""

import struct
from dataclasses import dataclass, field

BLOCK_NAMES = [
    "IMPORT", "CLASS", "GLOBAL", "LOCAL", "PROGRAM", "STRUC", "REAL", "TEXT",
    "BOOL", "PICTURE", "MAP", "BACKGRND", "SPRITE", "SOUND", "MUSIC", "PALETTE",
]
B = {name: i for i, name in enumerate(BLOCK_NAMES)}

FLAG_CHILDS = 0x01
FLAG_NEXT = 0x02

LANG_EN = 9
LANG_CZ = 5


@dataclass
class Node:
    block: int
    index: int
    flags: int
    ref_block: int
    ref_index: int
    dat_block: int
    dat_index: int
    icon: int
    name: int
    func: int
    children: list = field(default_factory=list)
    parent: "Node | None" = None


@dataclass
class Block:
    name: str
    size: int
    count: int
    extra: tuple
    data: bytes


def petprg_section(exe: bytes) -> bytes:
    pe = struct.unpack_from("<I", exe, 0x3C)[0]
    nsec = struct.unpack_from("<H", exe, pe + 6)[0]
    opt = struct.unpack_from("<H", exe, pe + 20)[0]
    so = pe + 24 + opt
    for i in range(nsec):
        name, vsize, _va, _rsize, raw = struct.unpack_from("<8sIIII", exe, so + i * 40)
        if name.rstrip(b"\0") == b".petprg":
            return exe[raw:raw + vsize]
    raise ValueError("no .petprg section")


class Program:
    def __init__(self, exe_path: str):
        self.raw = petprg_section(open(exe_path, "rb").read())
        if self.raw[:3] != b"PET":
            raise ValueError("bad PET header")
        self.editor_version = struct.unpack_from("<H", self.raw, 4)[0]
        data_off, count = struct.unpack_from("<II", self.raw, 8)
        self.blocks: list[Block] = []
        pos = data_off
        for i in range(count):
            size, n, name = struct.unpack_from("<II8s", self.raw, 16 + i * 32)
            extra = struct.unpack_from("<4I", self.raw, 16 + i * 32 + 16)
            self.blocks.append(Block(name.decode().strip(), size, n, extra, self.raw[pos:pos + size]))
            pos += size
        self.imports = self._parse_imports()
        self.texts = self._parse_texts()
        self.reals = struct.unpack_from("<%dd" % self.blocks[B["REAL"]].count, self.blocks[B["REAL"]].data)
        self.bools = list(self.blocks[B["BOOL"]].data)
        self.nodes: dict[int, list[Node]] = {}
        self.roots: dict[int, list[Node]] = {}
        for blk in ("CLASS", "GLOBAL", "LOCAL", "PROGRAM"):
            self._parse_tree(B[blk])

    def block(self, name: str) -> Block:
        return self.blocks[B[name]]

    def _parse_imports(self) -> list[str]:
        d = self.block("IMPORT").data
        out, i = [], 0
        while i < len(d):
            n = d[i]
            out.append(d[i + 1:i + 1 + n].decode("latin1"))
            i += 1 + n
        return out

    def _parse_texts(self) -> dict[int, list[str]]:
        blk = self.block("TEXT")
        d, p, langs = blk.data, 0, {}
        while p < len(d):
            lang, cp = struct.unpack_from("<ii", d, p)
            p += 8
            strings = []
            for _ in range(blk.count):
                n = struct.unpack_from("<i", d, p)[0]
                strings.append(d[p + 4:p + 4 + n].decode("cp%d" % cp, errors="replace"))
                p += 4 + n
            langs[lang] = strings
        return langs

    def text(self, index: int, lang: int = LANG_EN) -> str:
        if index < 0:
            return ""
        return self.texts.get(lang, [""] * (index + 1))[index] or self.texts[LANG_CZ][index]

    def _parse_tree(self, block: int):
        d = self.blocks[block].data
        flat = [Node(block, k, *struct.unpack_from("<8i", d, k * 32)) for k in range(len(d) // 32)]
        self.nodes[block] = flat
        roots: list[Node] = []
        pos = 0

        def walk(parent):
            nonlocal pos
            siblings = []
            while pos < len(flat):
                n = flat[pos]
                pos += 1
                n.parent = parent
                siblings.append(n)
                if n.flags & FLAG_CHILDS:
                    n.children = walk(n)
                if not n.flags & FLAG_NEXT:
                    break
            return siblings

        while pos < len(flat):
            roots.extend(walk(None))
        self.roots[block] = roots

    def ref(self, node: Node) -> "Node | str | None":
        if node.ref_block == B["IMPORT"]:
            return self.imports[node.ref_index]
        if node.ref_block in self.nodes and node.ref_index >= 0:
            return self.nodes[node.ref_block][node.ref_index]
        return None

    def base_func(self, node: Node) -> str:
        r = self.ref(node)
        while isinstance(r, Node):
            r = self.ref(r)
        return r or "?"

    def label(self, node: Node, lang: int = LANG_EN) -> str:
        if node.name >= 0:
            return self.text(node.name, lang)
        r = self.ref(node)
        if isinstance(r, Node):
            return self.label(r, lang)
        return r or "?"
