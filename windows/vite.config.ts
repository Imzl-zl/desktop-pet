import { defineConfig } from "vite";
import { resolve } from "path";

// HTML entry points: the transparent always-on-top pet overlay (index.html),
// the Settings window (settings.html), the popover (popover.html), and the
// floating ball (floating-ball.html). Tauri serves these in separate windows.
export default defineConfig({
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        settings: resolve(__dirname, "settings.html"),
        popover: resolve(__dirname, "popover.html"),
        ball: resolve(__dirname, "floating-ball.html"),
      },
    },
  },
});
