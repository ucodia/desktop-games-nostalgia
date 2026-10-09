import { defineConfig, searchForWorkspaceRoot } from "vite";

export default defineConfig({
  base: "./",
  publicDir: "../re/assets",
  build: { target: "es2022" },
  server: { fs: { allow: [searchForWorkspaceRoot(process.cwd()), "../README.md"] } },
});
