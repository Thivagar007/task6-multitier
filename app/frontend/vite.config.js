import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Local dev: requests to /api go to the backend on port 3000.
// In Azure the app calls APIM instead (VITE_API_BASE_URL).
// Port 8080: 5173 is inside a Windows reserved port range on this machine.
export default defineConfig({
  plugins: [react()],
  build: { chunkSizeWarningLimit: 1000 }, // MSAL is large; that is expected
  server: {
    port: 8080,
    strictPort: true,
    host: "127.0.0.1",
    proxy: { "/api": "http://localhost:3000" },
  },
});