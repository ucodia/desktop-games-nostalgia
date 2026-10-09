import { marked } from "marked";
import readme from "../../README.md?raw";

const REPO = "https://github.com/ucodia/desktop-games-nostalgia/blob/main/";

/** Notepad's client area showing the repository README, rendered, without the demo GIF. */
export function readmeNotepad(width, height) {
  const body = document.createElement("div");
  body.className = "notepad";
  body.style.width = `${width}px`;
  body.style.height = `${height}px`;
  body.innerHTML = `
    <div class="notepad-menu"><span>File</span><span>Edit</span><span>Format</span><span>View</span><span>Help</span></div>
    <div class="notepad-page"></div>`;

  const html = document.createElement("template");
  html.innerHTML = marked.parse(readme, { async: false });
  for (const img of html.content.querySelectorAll('img[src$=".gif"]')) {
    const parent = img.parentElement;
    img.remove();
    if (parent.tagName === "P" && !parent.textContent.trim()) parent.remove();
  }
  for (const a of html.content.querySelectorAll("a")) {
    a.href = new URL(a.getAttribute("href"), REPO).href;
    a.target = "_blank";
    a.rel = "noopener";
  }
  body.querySelector(".notepad-page").append(html.content);
  return body;
}
