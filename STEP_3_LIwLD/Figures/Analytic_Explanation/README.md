# STEP 3 Analytic Explanation Figure

This folder contains a synthetic, horizontal multi-panel infographic that explains
how STEP 3 infers a latent growth regime `H_theta` (SGPcFlow) from unlinked
cross-sectional pseudo-observations.

The default layout is intentionally wide (`16 x 7` inches), with a left-to-right
causal story:

`A -> B -> C -> D` = observe marginals -> forward check -> invert theta -> infer regime.

## Build

From project root:

```r
source("STEP_3_LIwLD/Figures/Analytic_Explanation/step3_analytic_explanation.R")
```

The script auto-runs by default and writes outputs to:

- `STEP_3_LIwLD/Figures/Analytic_Explanation/outputs/`

## What the figure shows

- **A:** observed unlinked `U` and `V` marginal distributions
- **B:** observed `F_obs(v)` vs prediction under a uniform growth regime and inferred regime, using  
  `F_theta(v) = E_U[H_theta(F_0(v|U))]`
- **C:** reverse-engineering of regime parameters (`mean`, `kappa`) via minimum-distance search
- **D:** inferred growth regime density `H_theta(p)` vs uniform baseline (and true synthetic regime)

## Main tuning knobs

Edit `STEP3_ANALYTIC_EXPLANATION_CONFIG` in the script:

- `true_regime_mean` (set low/high growth target)
- `n_students` (sample size)
- `copula_rho`, `copula_df` (baseline kernel)
- `figure_width`, `figure_height` (layout proportions)

## Default synthetic scenario

- Low-growth country illustration with true mean SGPc near `39`
- Several thousand students (`n = 3500`)
- Baseline transition kernel from a t-copula (`rho = 0.72`, `df = 8`)
- Inferred regime is fit by minimizing Wasserstein-1 distance between observed and predicted `v` CDFs
- Colour palette is aligned with STEP 2/STEP 3 publication conventions (Zissou anchors)

## Output files

- `*_summary.csv`
- `*_grid_search.csv`
- `*_data.rds`
- `*.pdf` (always)
- `*.svg` (if `svglite` installed)
- `*@2x.png` (if `ragg` installed)

## PSTricks publication version

A publication-grade PSTricks/LaTeX version of this infographic is in the `PSTricks/` subfolder.
It renders the same 4-panel story as a 2x4 layout (top: graphic panels, bottom: text explanations)
with crisp mathematical typesetting. Build with:

```bash
cd PSTricks/
Rscript step3_build_pstricks.R
```

See `PSTricks/README.md` for full details.
