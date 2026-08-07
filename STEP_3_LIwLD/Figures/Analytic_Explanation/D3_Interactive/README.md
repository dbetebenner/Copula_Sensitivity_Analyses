# LIwLD Interactive

Interactive D3 visualization explaining how STEP 3 infers a latent growth regime
from unlinked cross-sectional pseudo-observations. The full design rationale,
panel-by-panel spec, and implementation roadmap are in [`PROJECT_PLAN.md`](./PROJECT_PLAN.md).

This folder is structured as a self-contained sub-project:

```
D3_Interactive/
├── PROJECT_PLAN.md             # design + roadmap (v0.2)
├── README.md                   # you are here
├── schema/
│   └── manifest.schema.json    # data contract (single source of truth)
├── R/                          # precompute pipeline (Phase 1)
│   ├── liwld_precompute.R
│   ├── induced_cdf.R
│   └── export_bundle.R
├── data/
│   └── scenarios/
│       └── <scenario_id>/      # written by the precompute script
└── app/                        # Vite + React + D3 (Phase 2, not yet)
```

## Status

- **Phase 0 — Specification & contract.** ✓ Complete. See `schema/manifest.schema.json`.
- **Phase 1 — R precompute pipeline.** ✓ Code written. Awaiting first end-to-end run.
- **Phase 2 — Static layout (Vite + React + D3).** Not started.

## Building the scenario bundle

Default mode reads the real (de-identified) Phase A payload and writes the
canonical v1 scenario:

```bash
cd Figures/Analytic_Explanation/D3_Interactive
Rscript R/liwld_precompute.R
```

Or, from R:

```r
setwd("Figures/Analytic_Explanation/D3_Interactive")
source("R/liwld_precompute.R")
```

Falls back to a synthetic scenario for development:

```bash
STEP3_EXPORT_MODE=SYNTHETIC Rscript R/liwld_precompute.R
```

Either run produces:

```
data/scenarios/liwld_phase_a_v1/
  manifest.json
  panel1_u_curves.json
  panel2_copula_contours.json
  panel3_w1_surface.bin
  panel5_v_observed.json
  panel5_v_induced.bin
```

The script will print a summary including each file's size and a SHA-256 prefix.

### Required R packages

```r
install.packages(c("copula", "jsonlite", "digest"))
```

The script also `source()`s four files from `STEP_3_LIwLD/functions/`:
`copula_kernel_cache.R`, `regime_families.R`, `predict_v_cdf.R`,
`distance_metrics.R`. These provide the inference engine (`predict_marginal_cdf`,
`regime_beta`, `observed_marginal_cdf`).

### Tunables (edit `LIWLD_PRECOMPUTE_CONFIG` in `R/liwld_precompute.R`)

| Key | Default | Effect |
|---|---|---|
| `regime_grid$m_n` | 45 | m-axis resolution |
| `regime_grid$k_n` | 30 | κ-axis resolution (log-spaced) |
| `v_n` | 200 | v-axis points per induced CDF |
| `kernel_grid_size` | 201 | Conditional copula CDF cache resolution |

Defaults give a tensor of 45 × 30 × 200 = 270,000 quantized bytes ≈ 270 KB
raw, ~120 KB gzip — comfortably under the 1 MB v1 bundle target. Bumping
`m_n × k_n` is the right knob if the heatmap looks blocky; the v-axis only
needs more points if curvature near the boundaries is undersampled.

## Data contract

Every scenario folder is self-describing via `manifest.json`. Validate against
`schema/manifest.schema.json` if you change the writer or the loader.

The manifest captures:

- Cohort metadata (`grade_prior`, `grade_current`, `year_*`, `content_area`, `subgroup_filter`)
- Counts (`n_subgroup`, `n_population`)
- Copula family + parameters (`copula.family`, `copula.rho`, `copula.df`, …)
- Regime-grid axes (`regime_grid.m_min..m_n`, `regime_grid.k_min..k_n`, `regime_grid.k_scale`)
- V-grid (`v_grid.v_min..v_n`)
- Two reference points: `argmin` (the inferred regime) and `uniform_ref` (Beta(0.5, 2))
- Per-file SHA-256 checksums (loader must verify before rendering)
- Build provenance (`build.tool`, `build.tool_version`, `build.timestamp_utc`)

Two binary artifacts are reachable only via the manifest:

- **`panel3_w1_surface.bin`** — Float32, row-major `[m_n, k_n]`. Byte
  offset `4 * (m_idx * k_n + k_idx)` decodes to the W₁ value at
  `(m_grid[m_idx], k_grid[k_idx])`.
- **`panel5_v_induced.bin`** — Uint8 quantized, `[m_n, k_n, v_n]`. Byte at
  `m_idx * k_n * v_n + k_idx * v_n + v_idx` decodes via `byte / 255` to the
  induced CDF F_G(v) at the same regime cell.  (G = growth regime;
  H is reserved for the joint CDF in Sklar's theorem.)

## Next steps (Phase 2)

- Scaffold `app/` as a Vite + React 19 + TypeScript project.
- Implement `data-loader.ts` that fetches the manifest, verifies all five
  checksums, and exposes the typed bundle to the React tree.
- Build the five panel components against the bundle, with the handle pinned
  at `argmin`. Drag interactivity arrives in Phase 3.

See `PROJECT_PLAN.md` §7 for the full phase plan.

## Embedding into the NCIEA 2026 deck

The eventual delivery target is an `<iframe>` inside
`~/Research/Papers/Betebenner_Braun/Paper_1/NCIEA_2026_Colloquium_Staff_Presentation.qmd`.
The Vite build emits a single `dist/` directory that can be copied next to
the `.qmd` and referenced via `?embed=1` for the no-chrome layout. Full
strategy in `PROJECT_PLAN.md` §12.
