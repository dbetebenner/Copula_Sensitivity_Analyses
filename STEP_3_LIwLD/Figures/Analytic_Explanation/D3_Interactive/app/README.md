# LIwLD Interactive — App (Vite + React + D3)

Phase 2a status: **scaffold + boot diagnostic**. No panels rendered yet; this
is the data-contract eval gate. See `../PROJECT_PLAN.md` §7 for the broader
phase plan.

## Prerequisites

- Node ≥ 20.10
- pnpm ≥ 9 (or npm/yarn — pnpm is what the dataimago context uses)
- A built scenario bundle in `../data/scenarios/liwld_phase_a_v1/` (run
  `Rscript ../R/liwld_precompute.R` if missing)

## First run

```bash
cd Figures/Analytic_Explanation/D3_Interactive/app
pnpm install
pnpm dev
```

Visit the URL Vite prints (default `http://localhost:5173/`). You should see:

1. The page title.
2. A "Bundle loaded ✓" card showing scenario metadata, copula params, regime
   grid, argmin / uniform_ref, and a collapsible SHA-256 panel.
3. All five files loaded in well under a second.

Visit `?embed=1` to preview the embed layout (Phase 2b — currently a no-op).

## Production build

```bash
pnpm build
```

Emits `dist/`. Open `dist/index.html` directly from disk (`file://`) — it
will load the bundle relatively, which is the embed-into-RevealJS path.

## Scripts

- `pnpm copy-data` — manually mirror `../data/scenarios/` into
  `public/data/scenarios/`. Runs automatically before `dev` and `build`.
- `pnpm typecheck` — strict TS check, no emit.

## Layout

```
app/
├── package.json
├── vite.config.ts
├── tsconfig*.json
├── index.html
├── scripts/copy-data.mjs
└── src/
    ├── main.tsx          ← entry point
    ├── App.tsx           ← Phase 2a boot diagnostic
    ├── types.ts          ← TS mirror of manifest.schema.json
    ├── data-loader.ts    ← fetch + sha256 verify + decode
    ├── lib/
    │   ├── sha256.ts     ← WebCrypto wrapper
    │   ├── binary.ts     ← Float32 + Uint8 decoders, grid axes
    │   └── url.ts        ← ?embed=1 / ?scenario=… parsing
    └── styles/
        ├── tokens.css    ← three-tier design tokens
        └── global.css    ← reset + body baseline
```

## Phase 2a eval gate

Before continuing to Phase 2b (cross layout shell):

- `pnpm dev` boots without compile errors.
- The boot diagnostic card displays correctly with non-zero values for every
  field.
- The relative readout reports the argmin as **34% of baseline**
  (= 0.0050 / 0.0147 from the canonical Phase A scenario).
- Browser DevTools Network tab confirms 6 successful requests
  (manifest.json + 5 panel files), all with 200 status.
- Toggle the SHA-256 details — every checksum should match what
  `liwld_precompute.R` printed.
