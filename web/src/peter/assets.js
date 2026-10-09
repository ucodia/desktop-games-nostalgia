export const pictureWidth = (p) => p.pxWidth / p.pixelsPerUnit;
export const pictureHeight = (p) => p.pxHeight / p.pixelsPerUnit;

const rgb = (c) => ({ r: c[0], g: c[1], b: c[2] });

/** Assets extracted from the original program by tools/extract.py. */
export class Assets {
  pictures = new Map();
  sprites = new Map();
  sounds = new Map();
  iconColors = [];
  palette = [];
  appIcon;

  static async load(base, audio) {
    const a = new Assets();
    const manifest = await (await fetch(`${base}/manifest.json`)).json();
    a.palette = manifest.palette.map(rgb);
    a.iconColors = manifest.icons.map((i) => rgb(i.center_color));

    const image = async (file) => createImageBitmap(await (await fetch(`${base}/${file}`)).blob());
    a.appIcon = await image("app_icon.png");

    await Promise.all([
      ...manifest.pictures.map(async (p) => {
        const img = await image(p.file);
        a.pictures.set(p.name, { image: img, pxWidth: img.width, pxHeight: img.height, pixelsPerUnit: 32 });
      }),
      ...manifest.sprites.map(async (s) => {
        const sheet = await image(s.file);
        const frames = [];
        for (let d = 0; d < s.directions; d++) {
          const row = [];
          for (let ph = 0; ph < s.phases; ph++) {
            row.push(await createImageBitmap(sheet, ph * s.width, d * s.height, s.width, s.height));
          }
          frames.push(row);
        }
        const restPhases = Math.max(1, s.rest_phases);
        a.sprites.set(s.name, {
          name: s.name,
          frames,
          width: s.width,
          height: s.height,
          phases: s.phases,
          directions: s.directions,
          restPhases,
          delayMs: s.delay_ms,
          level: s.level,
          steps: s.steps,
          delayTicks: Math.trunc((s.delay_ms + 22) / 55),
        });
      }),
      ...manifest.sounds.map(async (s) => {
        a.sounds.set(s.name, await decodeStereo(audio, await (await fetch(`${base}/${s.file}`)).arrayBuffer()));
      }),
    ]);
    return a;
  }

  picture(name) {
    const p = this.pictures.get(name);
    if (!p) throw new Error(`missing picture ${name}`);
    return p;
  }

  sprite(name) {
    const s = this.sprites.get(name);
    if (!s) throw new Error(`missing sprite ${name}`);
    return s;
  }

  sound(name) {
    const s = this.sounds.get(name);
    if (!s) throw new Error(`missing sound ${name}`);
    return s;
  }
}

/** Decode a WAV into a 2-channel buffer (the mixer pans by scaling each channel). */
async function decodeStereo(audio, data) {
  let decoded;
  try {
    decoded = await audio.decodeAudioData(data);
  } catch {
    return audio.createBuffer(2, 1, audio.sampleRate);
  }
  if (decoded.numberOfChannels === 2) return decoded;
  const stereo = audio.createBuffer(2, decoded.length, decoded.sampleRate);
  const mono = decoded.getChannelData(0);
  stereo.copyToChannel(mono, 0);
  stereo.copyToChannel(mono, 1);
  return stereo;
}
