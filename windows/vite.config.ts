import { defineConfig } from "vite";
import { resolve } from "path";

// HTML entry points: the single transparent stage window and the Settings
// window. The stage hosts the pet, bubble, floating ball, popover and all
// extra/project pets in one composited layer.
export default defineConfig({
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: {
    rollupOptions: {
      input: {
        stage: resolve(__dirname, "stage.html"),
        settings: resolve(__dirname, "settings.html"),
      },
    },
  },
});
