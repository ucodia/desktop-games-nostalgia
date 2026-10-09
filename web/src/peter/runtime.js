import { POINTS_PER_UNIT, PaletteQuantizer, Sheet } from "./sheet";
import { Sprite } from "./sprite";

export class ExitProgram extends Error {}

let quantizer;

/**
 * The subset of the Peter runtime that Desktop Games relies on: a 55 ms timer tick that drives
 * sprites and resumes the program after `wait`, mouse/keyboard state and the display.
 */
export class Runtime {
  static tickMs = 55;

  quantizer;
  sprites = [];
  waiters = [];
  timer;
  exiting = false;
  ctx;
  detachInput = () => {};

  mouseX = 0;
  mouseY = 0;
  mouseLeft = false;
  mouseRight = false;
  leftClickFlag = false;
  rightClickFlag = false;
  keys = [];

  sheet;
  display;

  assets;
  audio;

  constructor(assets, audio, display, cssWidth, cssHeight, scale) {
    this.assets = assets;
    this.audio = audio;
    quantizer ??= new PaletteQuantizer(assets.palette);
    this.quantizer = quantizer;
    this.present(this.makeSheet(cssWidth, cssHeight, scale), display);
    this.timer = window.setInterval(() => this.tick(), Runtime.tickMs);
  }

  get mapWidth() {
    return this.sheet.widthUnits;
  }

  get mapHeight() {
    return this.sheet.heightUnits;
  }

  makeSheet(cssWidth, cssHeight, scale) {
    return new Sheet(cssWidth, cssHeight, scale, this.quantizer);
  }

  /** Show `sheet` (and the sprites) on `display`, which also becomes the input surface. */
  present(sheet, display) {
    this.sheet = sheet;
    this.display = display;
    display.width = sheet.width;
    display.height = sheet.height;
    display.style.width = `${sheet.cssWidth}px`;
    display.style.height = `${sheet.cssHeight}px`;
    this.ctx = display.getContext("2d");
    this.ctx.imageSmoothingEnabled = false;
    this.attachInput(display);
    this.render();
  }

  makeSprite(def) {
    const s = new Sprite(def);
    this.sprites.push(s);
    return s;
  }

  tick() {
    if (this.exiting) return;
    for (const s of this.sprites) s.tick();
    this.render();
    const ready = this.waiters.filter((w) => --w.ticks <= 0);
    this.waiters = this.waiters.filter((w) => w.ticks > 0);
    for (const w of ready) w.resolve();
  }

  render() {
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(this.sheet.canvas, 0, 0);
    ctx.setTransform(this.sheet.scale, 0, 0, this.sheet.scale, 0, 0);
    for (const s of [...this.sprites].sort((a, b) => a.z - b.z)) s.render(ctx, this.sheet.cssHeight);
  }

  // Program services

  /** wait: suspend the program for a number of timer ticks. */
  wait(ticks = 1) {
    if (this.exiting) return Promise.reject(new ExitProgram());
    return new Promise((resolve, reject) => this.waiters.push({ ticks: Math.max(1, ticks), resolve, reject }));
  }

  waitSeconds(seconds) {
    return this.wait(Math.round((seconds * 1000) / Runtime.tickMs));
  }

  /** exit: end the program. */
  exit() {
    throw new ExitProgram();
  }

  shutdown() {
    this.exiting = true;
    window.clearInterval(this.timer);
    this.audio.stop();
    this.detachInput();
    this.setCursorVisible(true);
    for (const w of this.waiters) w.reject(new ExitProgram());
    this.waiters = [];
  }

  setCursorVisible(visible) {
    this.display.style.cursor = visible ? "" : "none";
  }

  // Input

  /** mouse_l_click / mouse_r_click: true once per click, reading clears the flag. */
  leftClick() {
    const v = this.leftClickFlag;
    this.leftClickFlag = false;
    return v;
  }

  rightClick() {
    const v = this.rightClickFlag;
    this.rightClickFlag = false;
    return v;
  }

  /** key_vkey: next key from the keyboard buffer. */
  readKey() {
    return this.keys.shift();
  }

  mouseInRegion(x, y, w, h) {
    return this.mouseX >= x && this.mouseX < x + w && this.mouseY >= y && this.mouseY < y + h;
  }

  attachInput(el) {
    this.detachInput();
    const move = (e) => {
      const r = el.getBoundingClientRect();
      this.mouseX = (e.clientX - r.left) / POINTS_PER_UNIT;
      this.mouseY = (r.bottom - e.clientY) / POINTS_PER_UNIT;
    };
    const down = (e) => {
      move(e);
      if (e.button === 0) {
        this.mouseLeft = true;
        this.leftClickFlag = true;
      } else if (e.button === 2) {
        this.mouseRight = true;
        this.rightClickFlag = true;
      }
      el.setPointerCapture(e.pointerId);
    };
    const up = (e) => {
      if (e.button === 0) this.mouseLeft = false;
      else if (e.button === 2) this.mouseRight = false;
    };
    const menu = (e) => e.preventDefault();
    const key = (e) => {
      const k = toKey(e);
      if (!k) return;
      e.preventDefault();
      this.keys.push(k);
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerdown", down);
    el.addEventListener("pointerup", up);
    el.addEventListener("contextmenu", menu);
    window.addEventListener("keydown", key);
    this.detachInput = () => {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerdown", down);
      el.removeEventListener("pointerup", up);
      el.removeEventListener("contextmenu", menu);
      window.removeEventListener("keydown", key);
    };
  }
}

function toKey(e) {
  if (e.repeat) return undefined;
  if (e.key === "Escape") return { kind: "escape" };
  const f = /^F([1-9])$/.exec(e.key);
  if (f) return { kind: "tool", n: Number(f[1]) - 1 };
  const d = /^(?:Digit|Numpad)([1-9])$/.exec(e.code);
  if (d) return { kind: "tool", n: Number(d[1]) - 1 };
  if (["Shift", "Control", "Alt", "Meta", "CapsLock"].includes(e.key)) return undefined;
  return { kind: "other" };
}
