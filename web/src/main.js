import "xp.css/dist/XP.css";
import "./style.css";
import { Desktop } from "./desktop";
import { CAPTION, DesktopGames } from "./game";
import { readmeNotepad } from "./notepad";
import { Assets } from "./peter/assets";
import { AudioMixer } from "./peter/audio";
import { ExitProgram, Runtime } from "./peter/runtime";

const REPO_URL = "https://github.com/ucodia/desktop-games-nostalgia";
const DMG_URL = `${REPO_URL}/releases/download/v1.0.0/Desktop-Games-1.0.0.dmg`;

const audioContext = new AudioContext();
const assets = await Assets.load(".", audioContext);
const mixer = new AudioMixer(audioContext);

const optional = (p) => p.catch(() => undefined);
const [wallpaper, startLogo, notepadIcon, macIcon, githubIcon] = await Promise.all([
  optional(loadImage(new URL("./images/bliss.jpg", import.meta.url).href)),
  optional(loadImage(new URL("./images/start-logo.png", import.meta.url).href)),
  loadImage(new URL("./images/notepad.png", import.meta.url).href),
  loadImage(new URL("./images/happy-mac.png", import.meta.url).href),
  loadImage(new URL("./images/github.png", import.meta.url).href),
]);

const stress = { label: "stress.exe", image: assets.appIcon, x: 12, y: 12 };
const readme = { label: "README.md", image: notepadIcon, x: 12, y: 87, smooth: true };
const macDownload = { label: "macOS Download", image: macIcon, x: 12, y: 162 };
const github = { label: "GitHub", image: githubIcon, x: 12, y: 237, smooth: true };
const desktop = new Desktop([stress, readme, macDownload, github], wallpaper, startLogo);
document.body.append(desktop.canvas);
desktop.resize();
addEventListener("resize", () => desktop.resize());
setInterval(() => desktop.draw(), 30_000);

let running = false;
let notepad;
let topZ = 5;

desktop.canvas.addEventListener("pointerdown", (e) => {
  desktop.selected = desktop.iconAt(e.clientX, e.clientY);
  desktop.draw();
});

desktop.canvas.addEventListener("dblclick", (e) => {
  const icon = desktop.iconAt(e.clientX, e.clientY);
  if (icon === stress) launch();
  else if (icon === readme) openReadme();
  else if (icon === macDownload) location.assign(DMG_URL);
  else if (icon === github) window.open(REPO_URL, "_blank", "noopener");
});

function launch() {
  if (running) return;
  running = true;
  void audioContext.resume();

  const canvas = document.createElement("canvas");
  const { element, close } = openWindow(CAPTION, assets.appIcon, canvas, 480, 352, "game-window");
  const scale = window.devicePixelRatio || 1;
  const rt = new Runtime(assets, mixer, canvas, 480, 352, scale);
  let overlay;

  const host = {
    takeOverDesktop() {
      element.remove();
      overlay = document.createElement("canvas");
      overlay.className = "overlay";
      document.body.append(overlay);
      return { shot: desktop.canvas, cssWidth: innerWidth, cssHeight: innerHeight, scale: desktop.scale, display: overlay };
    },
  };

  const end = () => {
    rt.shutdown();
    element.remove();
    overlay?.remove();
    desktop.selected = undefined;
    desktop.draw();
    running = false;
  };
  close.addEventListener("click", end);

  new DesktopGames(rt, host).run().then(end, (e) => {
    if (!(e instanceof ExitProgram)) console.error(e);
    end();
  });
}

function openReadme() {
  if (notepad) return raise(notepad);
  const width = Math.min(720, innerWidth - 40), height = Math.min(540, innerHeight - 110);
  const { element, close } = openWindow("README.md - Notepad", notepadIcon, readmeNotepad(width, height), width, height, "notepad-window");
  notepad = element;
  close.addEventListener("click", () => {
    element.remove();
    notepad = undefined;
  });
}

async function loadImage(src) {
  const image = new Image();
  image.src = src;
  await image.decode();
  return image;
}

function raise(element) {
  element.style.zIndex = String(++topZ);
}

/** An XP window (XP.css) around `body`, centered like Peter's window. */
function openWindow(title, iconImage, body, width, height, className) {
  const element = document.createElement("div");
  element.className = `window app-window ${className}`;
  element.innerHTML = `
    <div class="title-bar">
      <div class="title-bar-text"><canvas class="title-icon" width="16" height="16"></canvas><span></span></div>
      <div class="title-bar-controls"><button aria-label="Close"></button></div>
    </div>
    <div class="window-body"></div>`;
  element.querySelector(".title-bar-text span").textContent = title;
  const icon = element.querySelector(".title-icon").getContext("2d");
  icon.drawImage(iconImage, 0, 0, 16, 16);
  element.querySelector(".window-body").append(body);
  document.body.append(element);
  raise(element);
  element.addEventListener("pointerdown", () => raise(element));
  element.style.left = `${Math.round((innerWidth - width) / 2)}px`;
  element.style.top = `${Math.round((innerHeight - height) / 2) - 20}px`;

  const bar = element.querySelector(".title-bar");
  bar.addEventListener("pointerdown", (e) => {
    if (e.target.closest(".title-bar-controls")) return;
    const ox = e.clientX - element.offsetLeft, oy = e.clientY - element.offsetTop;
    const move = (m) => {
      element.style.left = `${m.clientX - ox}px`;
      element.style.top = `${m.clientY - oy}px`;
    };
    bar.setPointerCapture(e.pointerId);
    bar.addEventListener("pointermove", move);
    bar.addEventListener("pointerup", () => bar.removeEventListener("pointermove", move), { once: true });
  });

  return { element, close: element.querySelector('[aria-label="Close"]') };
}
