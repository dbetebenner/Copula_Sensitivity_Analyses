# Error Budget Infographic (V1)

## Figure Theme

**Inference Error Budget for Copula-Based Stochastic Growth Regimes**

Companion to the Overview Figure ("Longitudinal Inference Without Longitudinal Data"). While the Overview explains the mechanism (how the bridge works), this figure explains the error budget (what kinds of uncertainty the bridge introduces, how large they are, and which of them matter for action).

## Conceptual structure

The visual grammar shifts from "how the bridge works" to "what kinds of uncertainty the bridge introduces." The protagonist is the estimand

$$\theta_S = 100\,\mathbb{E}(P_S)$$

and the question is:

1. What is the true subgroup quantity under linked data?
2. How far does the unlinked bridge move us from that truth?
3. How much extra wobble do we get from finite samples?
4. How much do modeling choices perturb the answer?

## Active panel layout

2×5 grid on a 20in × 24in page:

| Panel | Top row (graphic) | Bottom row (text) | Theme |
|-------|-------------------|-------------------|-------|
| **A** | True P_S density from linked data | `step3_panel_A_text.tex` | Truth benchmark |
| **B** | Truth-vs-bridge accuracy scatter | `step3_panel_B_text.tex` | Bridge accuracy |
| **C** | Paired vs independent schematic | `step3_panel_C_text.tex` | Sampling worlds |
| **D** | Precision operating curve by N | `step3_panel_D_text.tex` | Precision |
| **E** | Nested uncertainty bands | `step3_panel_E_text.tex` | Total uncertainty |

## Workflow

1. **Panel A:** Define the linked-data truth benchmark: $\theta_S^{\text{true}} = 100\,\mathbb{E}(P_S)$.
2. **Panel B:** Erase linkage, re-infer, measure bridge accuracy: $\hat{\theta}_S^{\text{bridge}} - \theta_S^{\text{true}}$.
3. **Panel C:** Distinguish paired subsampling (optimistic) from independent cross-sectional resampling (operational).
4. **Panel D:** Show 95% CI width vs $N$ under both designs.
5. **Panel E:** Combine bridge bias, sampling precision, and stress-test sensitivity into an action-ready uncertainty display.

## Quick start

```bash
cd Error_Figure/
Rscript step3_build_pstricks.R
```

The build writes deliverables to `outputs/`:
`step3_infographic_main.pdf`, `Inference_Error_Budget_Copula_Growth_Regimes_v<version>.pdf`, `step3_infographic_main.png`.

### Troubleshooting

Set `VERBOSE <- TRUE` near the top of `step3_build_pstricks.R` to show full LaTeX/XeLaTeX output. When any panel fails, the build script automatically surfaces the first few error lines from the `.log` file and preserves `.log` files in the working directory for manual inspection.

### Python fallback for data generation

If R is not available, `generate_data.py` produces identical data files:
```bash
python3 generate_data.py
```

## Prerequisites

- **R** (>= 4.0)
- **TeX Live** with PSTricks packages (`pstricks`, `pst-plot`, `pst-node`)
- **Ghostscript** (`gs`) for EPS->PDF conversion
- **XeLaTeX** (`xelatex`) for text panels and final assembly
- Access to `dataimago.sty` at `../../../../../../Papers/Betebenner_Braun/Paper_1/styles/dataimago.sty`

## Build pipeline

```
step3_export_data.R          # 1. Generate synthetic data -> export .dat + .tex to data/
    ↓
latex -> dvips -E -> gs      # 2. Compile graphic panels (PSTricks)
xelatex + dataimago          # 3. Compile text panels (A, B, C, D, E)
    ↓
xelatex + dataimago          # 4. Compile header band
    ↓
xelatex + dataimago          # 5. Assemble 2x5 main infographic
    ↓
gs -sDEVICE=png16m           # 6. Optional PNG export
```

## File inventory

### Source files

| File | Purpose |
|------|---------|
| `step3_build_pstricks.R` | Master figure build orchestrator |
| `step3_export_data.R` | Synthetic data generation (self-contained, R) |
| `generate_data.py` | Python fallback for data generation |
| `step3_styles.tex` | Shared colors and notation macros |
| `step3_panel_A_graphic.tex` | PSTricks: truth benchmark density |
| `step3_panel_B_graphic.tex` | PSTricks: bridge accuracy scatter |
| `step3_panel_C_graphic.tex` | PSTricks: paired vs independent schematic |
| `step3_panel_D_graphic.tex` | PSTricks: precision operating curves |
| `step3_panel_E_graphic.tex` | PSTricks: total uncertainty bands |
| `step3_panel_A_text.tex` | Text: linked-data benchmark |
| `step3_panel_B_text.tex` | Text: bridge accuracy |
| `step3_panel_C_text.tex` | Text: sampling worlds |
| `step3_panel_D_text.tex` | Text: precision by N |
| `step3_panel_E_text.tex` | Text: total uncertainty |
| `step3_header_band.tex` | XeLaTeX 5-column header band |
| `step3_infographic_main.tex` | Main 2×5 assembler |

### Generated data (`data/`)

| File | Contents |
|------|----------|
| `panel_A_density_true.dat` | True regime density (p × 100, density) |
| `panel_A_density_uniform.dat` | Uniform reference density |
| `panel_A_density_bridge.dat` | Bridge-recovered density |
| `panel_B_accuracy_pairs.dat` | (true_mean, bridge_estimate) pairs |
| `panel_B_error_density.dat` | Bridge error density curve |
| `panel_B_accuracy_markers.tex` | PSTricks accuracy arrows |
| `panel_C_paired_sample.dat` | Paired illustration data |
| `panel_C_independent_sample.dat` | Independent illustration data |
| `panel_D_precision_paired.dat` | Paired CI width vs N |
| `panel_D_precision_indep.dat` | Independent CI width vs N |
| `panel_D_mae_paired.dat` | Paired MAE vs N |
| `panel_D_mae_indep.dat` | Independent MAE vs N |
| `panel_E_uncertainty_budget.dat` | Per-subgroup uncertainty layers |
| `summary_metrics.tex` | LaTeX macros with computed values |
| `axis_limits.tex` | LaTeX macros with axis ranges |

## Color palette

Extended Zissou palette for the error/precision theme:

- **Amber** `#E1AF00` — truth benchmark
- **Black** `#000000` — bridge estimates
- **Teal** `#3B9AB2` — paired subsampling
- **Red** `#F21A00` — independent resampling / bridge bias arrows
- **Blue** `#4A90D9` — sampling precision bands
- **Orange** `#F5A623` — stress-test sensitivity bands
- **Grey** — uniform baseline and annotations

## Key design principle

The infographic separates **how the estimate is produced** (Overview Figure) from **how the estimate is evaluated** (this figure):

$$\hat\theta_S \;\text{vs truth},\qquad
\hat\theta_S \;\text{across repeated samples},\qquad
\hat\theta_S \;\text{under perturbations}.$$
