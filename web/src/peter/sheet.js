import { pictureHeight, pictureWidth } from "./assets";

export const POINTS_PER_UNIT = 32;

/**
 * The Peter "sheet": a bitmap the program paints on, addressed in Peter units with the origin
 * at the bottom-left (y grows upward). One unit is 32 CSS pixels.
 */
export class Sheet {
  canvas;
  ctx;
  cssWidth;
  cssHeight;
  scale;
  quantizer;

  constructor(cssWidth, cssHeight, scale, quantizer) {
    this.cssWidth = cssWidth;
    this.cssHeight = cssHeight;
    this.scale = scale;
    this.quantizer = quantizer;
    this.canvas = document.createElement("canvas");
    this.canvas.width = Math.round(cssWidth * scale);
    this.canvas.height = Math.round(cssHeight * scale);
    this.ctx = this.canvas.getContext("2d", { willReadFrequently: true });
    this.ctx.imageSmoothingEnabled = false;
    this.ctx.fillStyle = "#000";
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
  }

  get width() {
    return this.canvas.width;
  }

  get height() {
    return this.canvas.height;
  }

  get pixelsPerUnit() {
    return POINTS_PER_UNIT * this.scale;
  }

  get widthUnits() {
    return this.width / this.pixelsPerUnit;
  }

  get heightUnits() {
    return this.height / this.pixelsPerUnit;
  }

  /** background_disp: draw a picture with its lower-left corner at (x, y), optionally only a block of it. */
  draw(p, x, y, block) {
    let sx = 0, sy = 0, sw = p.pxWidth, sh = p.pxHeight;
    let w = pictureWidth(p), h = pictureHeight(p);
    if (block) {
      const ppu = p.pixelsPerUnit;
      sx = Math.round(block.x * ppu);
      sy = Math.round(p.pxHeight - (block.y + block.h) * ppu);
      sw = Math.round(block.w * ppu);
      sh = Math.round(block.h * ppu);
      const x0 = Math.max(0, sx), y0 = Math.max(0, sy);
      const x1 = Math.min(p.pxWidth, sx + sw), y1 = Math.min(p.pxHeight, sy + sh);
      if (x1 <= x0 || y1 <= y0) return;
      sx = x0; sy = y0; sw = x1 - x0; sh = y1 - y0;
      w = sw / ppu;
      h = sh / ppu;
    }
    const ppu = this.pixelsPerUnit;
    const dx = Math.round(x * ppu);
    const dw = Math.round(w * ppu), dh = Math.round(h * ppu);
    const dy = this.height - Math.round(y * ppu) - dh;
    this.ctx.drawImage(p.image, sx, sy, sw, sh, dx, dy, dw, dh);
  }

  /** background_get: snapshot of the whole sheet. */
  snapshot() {
    const c = document.createElement("canvas");
    c.width = this.width;
    c.height = this.height;
    c.getContext("2d").drawImage(this.canvas, 0, 0);
    return { image: c, pxWidth: c.width, pxHeight: c.height, pixelsPerUnit: this.pixelsPerUnit };
  }

  fillAll(color) {
    this.ctx.fillStyle = css(color);
    this.ctx.fillRect(0, 0, this.width, this.height);
  }

  line(color, widthPixels, x1, y1, x2, y2) {
    const ppu = this.pixelsPerUnit;
    const c = this.ctx;
    c.strokeStyle = css(color);
    c.lineWidth = Math.max(1, widthPixels * this.scale);
    c.lineCap = "round";
    c.beginPath();
    c.moveTo(x1 * ppu, this.height - y1 * ppu);
    c.lineTo(x2 * ppu, this.height - y2 * ppu);
    c.stroke();
  }

  point(color, widthPixels, x, y) {
    const ppu = this.pixelsPerUnit;
    const c = this.ctx;
    c.fillStyle = css(color);
    c.beginPath();
    c.arc(x * ppu, this.height - y * ppu, Math.max(1, widthPixels * this.scale) / 2, 0, Math.PI * 2);
    c.fill();
  }

  /** get_point: color under a unit coordinate. */
  color(x, y) {
    const px = Math.trunc(x * this.pixelsPerUnit), py = Math.trunc(y * this.pixelsPerUnit);
    if (px < 0 || py < 0 || px >= this.width || py >= this.height) return { r: 0, g: 0, b: 0 };
    const d = this.ctx.getImageData(px, this.height - 1 - py, 1, 1).data;
    return { r: d[0], g: d[1], b: d[2] };
  }

  /**
   * fill: flood fill of the area that shares the seed's color. The original runs in Peter's
   * 224-color palette, so "same color" means "maps to the same palette entry".
   */
  floodFill(color, x, y) {
    const w = this.width, h = this.height;
    const sx = Math.trunc(x * this.pixelsPerUnit), sy = h - 1 - Math.trunc(y * this.pixelsPerUnit);
    if (sx < 0 || sy < 0 || sx >= w || sy >= h) return;
    const img = this.ctx.getImageData(0, 0, w, h);
    const px = new Uint32Array(img.data.buffer);
    const q = this.quantizer;
    const target = q.index(px[sy * w + sx]);
    const fill = (255 << 24) | (color.b << 16) | (color.g << 8) | color.r;
    const visited = new Uint8Array(w * h);
    const matches = (i) => visited[i] === 0 && q.index(px[i]) === target;
    const stack = [sx, sy];
    while (stack.length) {
      const y0 = stack.pop(), x0 = stack.pop();
      const row = y0 * w;
      if (!matches(row + x0)) continue;
      let l = x0, r = x0;
      while (l > 0 && matches(row + l - 1)) l--;
      while (r < w - 1 && matches(row + r + 1)) r++;
      for (let i = l; i <= r; i++) {
        visited[row + i] = 1;
        px[row + i] = fill;
      }
      for (const ny of [y0 - 1, y0 + 1]) {
        if (ny < 0 || ny >= h) continue;
        const nrow = ny * w;
        let i = l;
        while (i <= r) {
          if (matches(nrow + i)) {
            stack.push(i, ny);
            while (i <= r && matches(nrow + i)) i++;
          }
          i++;
        }
      }
    }
    this.ctx.putImageData(img, 0, 0);
  }
}

export const css = (c) => `rgb(${c.r},${c.g},${c.b})`;

/** Maps true colors to the nearest entry of Peter's palette (through a 15-bit lookup table). */
export class PaletteQuantizer {
  table = new Uint8Array(32768);

  constructor(palette) {
    for (let key = 0; key < 32768; key++) {
      const r = (((key >> 10) & 31) << 3) | 4, g = (((key >> 5) & 31) << 3) | 4, b = ((key & 31) << 3) | 4;
      let best = 0, bestDist = Infinity;
      for (let i = 2; i < palette.length; i++) {
        const c = palette[i];
        const dr = r - c.r, dg = g - c.g, db = b - c.b;
        const dist = dr * dr * 3 + dg * dg * 4 + db * db * 2;
        if (dist < bestDist) {
          bestDist = dist;
          best = i;
        }
      }
      this.table[key] = best;
    }
  }

  /** Index for a little-endian RGBA pixel word. */
  index(pixel) {
    const r = (pixel & 0xff) >> 3, g = ((pixel >> 8) & 0xff) >> 3, b = ((pixel >> 16) & 0xff) >> 3;
    return this.table[(r << 10) | (g << 5) | b];
  }
}
