/** A Windows XP-style desktop painted on a canvas, so the game can take a picture of it. */

const ICON_SIZE = 32;
const CELL_WIDTH = 76;
const TASKBAR_HEIGHT = 30;

export class Desktop {
  canvas;
  ctx;
  selected;

  icons;
  wallpaper;
  startLogo;

  constructor(icons, wallpaper, startLogo) {
    this.icons = icons;
    this.wallpaper = wallpaper;
    this.startLogo = startLogo;
    this.canvas = document.createElement("canvas");
    this.canvas.className = "desktop";
    this.ctx = this.canvas.getContext("2d");
  }

  get scale() {
    return window.devicePixelRatio || 1;
  }

  resize() {
    const s = this.scale;
    this.canvas.width = Math.round(innerWidth * s);
    this.canvas.height = Math.round(innerHeight * s);
    this.canvas.style.width = `${innerWidth}px`;
    this.canvas.style.height = `${innerHeight}px`;
    this.draw();
  }

  iconAt(x, y) {
    return this.icons.find((i) => x >= i.x && x < i.x + CELL_WIDTH && y >= i.y && y < i.y + ICON_SIZE + 34);
  }

  draw() {
    const c = this.ctx;
    const w = innerWidth, h = innerHeight;
    c.setTransform(this.scale, 0, 0, this.scale, 0, 0);
    if (this.wallpaper) this.drawImageWallpaper(this.wallpaper, w, h);
    else this.drawWallpaper(w, h - TASKBAR_HEIGHT);
    for (const icon of this.icons) this.drawIcon(icon);
    this.drawTaskbar(w, h);
  }

  drawImageWallpaper(image, w, h) {
    const c = this.ctx;
    const k = Math.max(w / image.naturalWidth, h / image.naturalHeight);
    const iw = image.naturalWidth * k, ih = image.naturalHeight * k;
    c.imageSmoothingEnabled = true;
    c.imageSmoothingQuality = "high";
    c.drawImage(image, (w - iw) / 2, (h - ih) / 2, iw, ih);
  }

  drawWallpaper(w, h) {
    const c = this.ctx;
    const sky = c.createLinearGradient(0, 0, 0, h * 0.75);
    sky.addColorStop(0, "#1f5fd1");
    sky.addColorStop(0.55, "#4f93e8");
    sky.addColorStop(1, "#a9cff3");
    c.fillStyle = sky;
    c.fillRect(0, 0, w, h);

    for (const [cx, cy, r] of [[0.18, 0.2, 0.16], [0.42, 0.12, 0.11], [0.72, 0.24, 0.2], [0.9, 0.1, 0.09]]) {
      const g = c.createRadialGradient(cx * w, cy * h, 0, cx * w, cy * h, r * w);
      g.addColorStop(0, "rgba(255,255,255,0.75)");
      g.addColorStop(1, "rgba(255,255,255,0)");
      c.fillStyle = g;
      c.beginPath();
      c.ellipse(cx * w, cy * h, r * w, r * w * 0.35, 0, 0, Math.PI * 2);
      c.fill();
    }

    const back = c.createLinearGradient(0, h * 0.55, 0, h);
    back.addColorStop(0, "#4c9a2a");
    back.addColorStop(1, "#2c6a12");
    c.fillStyle = back;
    c.beginPath();
    c.moveTo(0, h * 0.72);
    c.bezierCurveTo(w * 0.35, h * 0.5, w * 0.7, h * 0.58, w, h * 0.66);
    c.lineTo(w, h);
    c.lineTo(0, h);
    c.fill();

    const front = c.createLinearGradient(0, h * 0.6, 0, h);
    front.addColorStop(0, "#7cc242");
    front.addColorStop(0.5, "#4f9a22");
    front.addColorStop(1, "#2f6e10");
    c.fillStyle = front;
    c.beginPath();
    c.moveTo(0, h * 0.86);
    c.bezierCurveTo(w * 0.25, h * 0.6, w * 0.55, h * 0.62, w, h * 0.82);
    c.lineTo(w, h);
    c.lineTo(0, h);
    c.fill();
  }

  drawIcon(icon) {
    const c = this.ctx;
    const selected = this.selected === icon;
    const ix = icon.x + (CELL_WIDTH - ICON_SIZE) / 2;
    c.imageSmoothingEnabled = !!icon.smooth;
    c.drawImage(icon.image, ix, icon.y, ICON_SIZE, ICON_SIZE);
    if (selected) {
      c.fillStyle = "rgba(49,106,197,0.5)";
      c.fillRect(ix, icon.y, ICON_SIZE, ICON_SIZE);
    }
    c.font = "11px Tahoma, Verdana, sans-serif";
    c.textAlign = "center";
    c.textBaseline = "top";
    const tx = icon.x + CELL_WIDTH / 2, ty = icon.y + ICON_SIZE + 4;
    if (selected) {
      const tw = c.measureText(icon.label).width;
      c.fillStyle = "#316ac5";
      c.fillRect(tx - tw / 2 - 2, ty - 1, tw + 4, 14);
    } else {
      c.fillStyle = "rgba(0,0,0,0.85)";
      c.fillText(icon.label, tx + 1, ty + 1);
    }
    c.fillStyle = "#fff";
    c.fillText(icon.label, tx, ty);
  }

  drawTaskbar(w, h) {
    const c = this.ctx;
    const top = h - TASKBAR_HEIGHT;
    const bar = c.createLinearGradient(0, top, 0, h);
    bar.addColorStop(0, "#3c81f3");
    bar.addColorStop(0.1, "#2a6ae6");
    bar.addColorStop(0.5, "#245edb");
    bar.addColorStop(1, "#1941a5");
    c.fillStyle = bar;
    c.fillRect(0, top, w, TASKBAR_HEIGHT);

    const start = c.createLinearGradient(0, top, 0, h);
    start.addColorStop(0, "#4fa94a");
    start.addColorStop(0.5, "#378e32");
    start.addColorStop(1, "#2a7426");
    c.fillStyle = start;
    c.beginPath();
    c.moveTo(0, top);
    c.lineTo(88, top);
    c.quadraticCurveTo(102, top, 102, top + TASKBAR_HEIGHT / 2);
    c.quadraticCurveTo(102, h, 88, h);
    c.lineTo(0, h);
    c.fill();

    if (this.startLogo) {
      const lh = 19, lw = (lh * this.startLogo.naturalWidth) / this.startLogo.naturalHeight;
      c.save();
      c.imageSmoothingEnabled = true;
      c.imageSmoothingQuality = "high";
      c.shadowColor = "rgba(0,0,0,0.45)";
      c.shadowOffsetX = 1;
      c.shadowOffsetY = 1;
      c.drawImage(this.startLogo, 7, top + (TASKBAR_HEIGHT - lh) / 2, lw, lh);
      c.restore();
    } else {
      const fx = 10, fy = top + 8, s = 6;
      for (const [dx, dy, col] of [[0, 0, "#f25022"], [s + 1, 0, "#7fba00"], [0, s + 1, "#00a4ef"], [s + 1, s + 1, "#ffb900"]]) {
        c.fillStyle = col;
        c.fillRect(fx + dx, fy + dy, s, s);
      }
    }
    c.font = "italic bold 17px 'Trebuchet MS', Tahoma, sans-serif";
    c.textAlign = "left";
    c.textBaseline = "middle";
    c.fillStyle = "rgba(0,0,0,0.5)";
    c.fillText("start", 33, top + TASKBAR_HEIGHT / 2 + 1);
    c.fillStyle = "#fff";
    c.fillText("start", 32, top + TASKBAR_HEIGHT / 2);

    const trayW = 80;
    const tray = c.createLinearGradient(0, top, 0, h);
    tray.addColorStop(0, "#1c9df0");
    tray.addColorStop(1, "#0e6fcf");
    c.fillStyle = tray;
    c.fillRect(w - trayW, top, trayW, TASKBAR_HEIGHT);
    c.fillStyle = "#1a5bc4";
    c.fillRect(w - trayW, top, 1, TASKBAR_HEIGHT);
    c.font = "11px Tahoma, Verdana, sans-serif";
    c.textAlign = "center";
    c.fillStyle = "#fff";
    c.fillText(new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }), w - trayW / 2, top + TASKBAR_HEIGHT / 2);
  }
}
