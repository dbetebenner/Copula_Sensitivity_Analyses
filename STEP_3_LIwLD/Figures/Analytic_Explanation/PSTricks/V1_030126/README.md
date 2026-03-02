# STEP 3 PSTricks Infographic

Publication-grade 2×4 PSTricks/LaTeX infographic explaining how STEP 3 infers a latent growth regime $\widehat{H}_S$ from unlinked cross-sectional data.

Framing used in STEP 3: **controlled canonical choices with quantified error**:
- Canonical baseline copula (from STEP 1),
- Canonical stochastically fitted growth regime (Beta family in STEP 3 production runs).

## Layout

| Column | Top row (graphic) | Bottom row (text) |
|--------|-------------------|-------------------|
| **A** | Independent U & V marginal densities (no student-level pairs) | Cross-sectional input context |
| **B** | Forward CDF check in v-space | Analytic identity explanation |
| **C** | Reverse-engineer regime landscape over $(m,\kappa)$ | Distance minimisation logic |
| **D** | Inferred growth regime density $f_S(p)$ | Growth occupancy interpretation |

## Workflow

1. **Panel A:** Observe unlinked marginals $F_U(u)$ and $F_V(v)$ (no student-level pairs).
2. **Panel B:** Forward map with baseline kernel and candidate regime:
   $F_H(v)=\mathbb{E}_{U}\!\left[H\!\left(F_0(v\mid U)\right)\right]$.
3. **Panel C:** Estimate subgroup regime by minimum distance over canonical Beta family:
   $\widehat{H}_S=\arg\min_{H\in\mathcal{H}_{\mathrm{Beta}}}\,W_1(F^{\mathrm{obs}}_{V,S},F_H)$.
4. **Panel D:** Display recovered density $f_S(p)=H_S'(p)$ and summary mean SGPc.

Key identifying assumption in this infographic: $P\perp U$ within subgroup.

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
| `step3_panel_C_graphic.tex` | PSTricks: objective heatmap over $(m,\kappa)$ |
| `step3_panel_D_graphic.tex` | PSTricks: inferred regime density |
| `step3_panel_A_text.tex` | Text: cross-sectional inputs |
| `step3_panel_B_text.tex` | Text: analytic identity |
| `step3_panel_C_text.tex` | Text: distance minimisation and Beta family search |
| `step3_panel_D_text.tex` | Text: recovered growth regime density interpretation |
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
| `panel_C_optimum.tex` | Best-fit $(\hat m,\hat\kappa)$ coordinates |
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
| `\HS` | $H_S$ |
| `\HShat` | $\widehat{H}_S$ |
| `\FH` | $F_H$ |
| `\FHhat` | $\widehat{F}_H$ |
| `\Fobs` | $F_{\mathrm{obs}}$ |
| `\Fzero` | $F_0$ |
| `\SGPcFlow` | SGPcFlow |
| `\Wone` | $W_1$ |

### Mathematical notation

- $U,V$: prior/current reference quantiles (pseudo-observations)
- $P,P_S$: latent conditional percentile (SGPc on $[0,1]$)
- $H_S(p)=\Pr(P_S\le p)$: subgroup growth-regime CDF
- $F_0(v\mid u)=\frac{\partial}{\partial u}C_0(u,v)$: baseline conditional CDF kernel
- $Q_0(p\mid u)=F_0^{-1}(p\mid u)$: baseline conditional quantile kernel
- $F_H(v)=\mathbb{E}_{U}[H(F_0(v\mid U))]$: predicted current marginal under regime $H$
- $\mathcal{H}_{\mathrm{Beta}}=\{H_{m,\kappa}:P\sim\mathrm{Beta}(\kappa m,\kappa(1-m))\}$: candidate family
- $\widehat{H}_S=\arg\min_{H\in\mathcal{H}_{\mathrm{Beta}}}W_1(F^{\mathrm{obs}}_{V,S},F_H)$

Uniform baseline in this parameterization is $H(p)=p$ at $(m,\kappa)=(0.5,2)$, i.e. $\mathrm{Beta}(1,1)$.

## Font behavior

The final composite is intentionally hybrid, mirroring the Copula pipeline:

- Bottom-row explanatory text panels and master title/footer use XeLaTeX + `dataimago.sty`, which embeds `Noto Sans` and `Noto Sans Math`.
- Top-row PSTricks graphic panels remain on the classic `latex -> dvips -> gs` path and therefore keep Computer Modern / `sansmathfonts` glyphs for panel-internal labels.
