import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// LIwLD Interactive — Vite config.
//
// Key choices:
//  - `base: './'`  — emits relative URLs in `dist/` so the build can be opened
//    from `file://` (RevealJS embed) or any subpath without rebuilding.
//  - `assetsInlineLimit: 0` — keep the panel binary files as separate cacheable
//    assets, never inlined as base64 (which would defeat the SHA-256 contract
//    and bloat the JS).
export default defineConfig({
  base: './',
  plugins: [react()],
  build: {
    outDir: 'dist',
    target: 'es2022',
    sourcemap: true,
    assetsInlineLimit: 0,
  },
  server: {
    port: 5173,
    strictPort: false,
    open: false,
  },
});
