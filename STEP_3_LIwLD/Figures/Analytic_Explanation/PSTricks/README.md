# STEP 3 PSTricks Infographic

Publication-grade 2×4 PSTricks/LaTeX infographic explaining how STEP 3 infers a latent growth regime $H_\theta$ from unlinked cross-sectional data.

## Layout

| Column | Top row (graphic) | Bottom row (text) |
|--------|-------------------|-------------------|
| **A** | Independent U & V marginal densities | Cross-sectional input context |
| **B** | Forward CDF check in v-space | Analytic identity explanation |
| **C** | Reverse-engineer θ landscape | Distance minimisation logic |
| **D** | Inferred growth regime $H_{\hat\theta}$ | Growth occupancy interpretation |

## Quick start

```bash
cd PSTricks/
Rscript step3_build_pstricks.R
```

The build takes ~5 seconds and writes deliverables to `outputs/`:
`step3_infographic_main.pdf`, `step3_infographic_main.png`, and (if a converter is installed) `step3_infographic_main.svg`.

## Prerequisites

- **R** (≥ 4.0) with the `copula` package
- **TeX Live** with PSTricks packages (`pstricks`, `pst-plot`, `pst-node`)
- **Ghostscript** (`gs`) for EPS→PDF conversion
- **XeLaTeX** (`xelatex`) for text panels and final assembly
- Access to `dataimago.sty` at `../../../../../../Papers/Betebenner_Braun/Paper_1/styles/dataimago.sty`

The analytic data RDS must exist at `../outputs/step3_growth_regime_analytic_infographic_data.rds`. If it does not, first run:

```bash
cd ..
Rscript step3_analytic_explanation.R
```

## Build pipeline

```
step3_export_data.R          # 1. Load RDS → export .dat + .tex to data/
    ↓
latex → dvips -E → gs        # 2. Compile graphic panels (PSTricks)
xelatex + dataimago          # 3. Compile text panels (Noto Sans / Noto Sans Math)
    ↓
xelatex + dataimago          # 4. Assemble 2×4 main infographic
    ↓
gs -sDEVICE=png16m           # 5. Optional PNG export
```

This mirrors the compile chain in `Betebenner_Braun/Paper_1/Figures/Copulas/copula_R_script.R`.

## File inventory

### Source files

| File | Purpose |
|------|---------|
| `step3_build_pstricks.R` | Master build orchestrator |
| `step3_export_data.R` | R→TeX data export (curves, heatmap, metrics) |
| `step3_styles.tex` | Shared colors, notation macros |
| `step3_panel_A_graphic.tex` | PSTricks: U & V density curves |
| `step3_panel_B_graphic.tex` | PSTricks: CDF comparison |
| `step3_panel_C_graphic.tex` | PSTricks: θ objective heatmap |
| `step3_panel_D_graphic.tex` | PSTricks: inferred regime density |
| `step3_panel_A_text.tex` | Text: cross-sectional inputs |
| `step3_panel_B_text.tex` | Text: analytic identity |
| `step3_panel_C_text.tex` | Text: distance minimisation |
| `step3_panel_D_text.tex` | Text: recovered growth regime |
| `step3_infographic_main.tex` | 2×4 `\includegraphics` assembler |

### Generated data (`data/`)

| File | Contents |
|------|----------|
| `panel_A_density_U.dat` | Prior density curve (x y) |
| `panel_A_density_V.dat` | Current density curve (x y) |
| `panel_B_cdf_obs.dat` | Observed CDF |
| `panel_B_cdf_uniform.dat` | Uniform-regime CDF prediction |
| `panel_B_cdf_inferred.dat` | Inferred-regime CDF prediction |
| `panel_C_heatmap_cells.tex` | R-generated `\psframe*` heatmap |
| `panel_C_optimum.tex` | θ̂ coordinates |
| `panel_D_density_*.dat` | Regime density curves |
| `summary_metrics.tex` | LaTeX macros with computed values |
| `axis_limits.tex` | LaTeX macros with axis ranges |

### Outputs (`outputs/`)

| File | Format |
|------|--------|
| `step3_infographic_main.pdf` | Final publication infographic |
| `step3_infographic_main.png` | 300 DPI raster export |
| `step3_infographic_main.svg` | Optional vector export |
| `step3_panel_*_graphic.pdf` | Individual graphic panels |
| `step3_panel_*_text.pdf` | Individual text panels |

## Color palette

Aligned with the STEP 3 Zissou-based publication style:

- **Teal** `#3B9AB2` — prior sample / inferred regime
- **Red** `#F21A00` — current sample
- **Amber** `#E1AF00` — true synthetic regime
- **Grey** — uniform baseline, annotations

## Notation

Canonical macros defined in `step3_styles.tex`:

| Macro | Renders |
|-------|---------|
| `\Htheta` | $H_\theta$ |
| `\Ftheta` | $F_\theta$ |
| `\Fobs` | $F_{\mathrm{obs}}$ |
| `\Fzero` | $F_0$ |
| `\thetahat` | $\hat{\theta}$ |
| `\SGPcFlow` | SGPcFlow |
| `\Wone` | $W_1$ |

## Font behavior

The final composite is intentionally hybrid, mirroring the Copula pipeline:

- Bottom-row explanatory text panels and master title/footer use XeLaTeX + `dataimago.sty`, which embeds `Noto Sans` and `Noto Sans Math`.
- Top-row PSTricks graphic panels remain on the classic `latex -> dvips -> gs` path and therefore keep Computer Modern / `sansmathfonts` glyphs for panel-internal labels.
