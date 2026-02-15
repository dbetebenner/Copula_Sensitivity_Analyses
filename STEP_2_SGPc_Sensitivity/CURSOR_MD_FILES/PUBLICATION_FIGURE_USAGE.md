# STEP 2 Publication Figure: Usage Guide

## Overview

`create_publication_figure.R` generates a publication-ready multi-panel figure from STEP 2 variant outputs, plus individual panel files in PDF/SVG/PNG.

Synchronized with current implementation as of 2026-02-10.

---

## Quick Start

From the parent project directory:

```r
source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
```

Inputs required:
- `STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_*.rds`

Optional cache used/generated:
- `STEP_2_SGPc_Sensitivity/results/sgpc_enhanced_stats.rds`

---

## What Gets Generated

All files are written to:
- `STEP_2_SGPc_Sensitivity/results/visualizations/`

### Individual panel outputs

- `panel_a_individual_ecdf.{pdf,svg,png}`
- `panel_b_school_ecdf.{pdf,svg,png}`
- `panel_b2_district_ecdf.{pdf,svg,png}`
- `panel_c_condition_dots.{pdf,svg,png}`
- `panel_d_rank_agreement.{pdf,svg,png}`
- `panel_e_decile_stability.{pdf,svg,png}`
- `panel_d2_group_bucket_stability.{pdf,svg,png}`
- `panel_f_prior_quartile.{pdf,svg,png}`
- `panel_g_cross_dataset.{pdf,svg,png}`
- `panel_h_multilevel_aggregation.{pdf,svg,png}`
- `panel_i_error_decomposition.{pdf,svg,png}`
- `panel_j_condition_n_vs_mad.{pdf,svg,png}`
- `panel_k_group_rank_stability.{pdf,svg,png}`

### Assembled summary grid

- `sgpc_summary_grid.tex`
- `sgpc_summary_grid.pdf`
- `sgpc_summary_grid.svg`
- `sgpc_summary_grid.png`

---

## Panel Map

- **A**: Individual-level ECDF
- **B**: School-level ECDF
- **B2**: District-level ECDF
- **C**: Condition-level MAD dots
- **D**: Individual rank agreement
- **E**: Decile classification stability
- **D2**: Group-level bucket stability (K = 3, 5, 10)
- **F**: Prior-achievement quartile sensitivity
- **G**: Cross-dataset comparison
- **H**: Multi-level aggregation
- **I**: Error decomposition (comparison vs sampling)
- **J**: Condition N vs MAD
- **K**: Group-level rank stability

---

## Comparison Labels (Current)

Publication panels use exact labels from `sgpc_publication_plots.R`:

- `Empirical – Best-Fit Parametric`
- `Empirical – Canonical (averaged)`
- `Best-Fit – Canonical`
- `Empirical – Gaussian`
- `Empirical – Gumbel`
- `Empirical – Frank`
- `Empirical – Clayton`
- `Empirical – t (Student)`
- `Empirical – Comonotonic`
- `Empirical – Traditional (B-spline SGP)`

---

## Layout Behavior

The grid layout is dynamic and selected by panel count in `create_publication_figure.R`:

- `6x2` for 12+ panels
- `5x2` for 10+ panels
- `4x2` for 8+ panels
- `3x2` for 6+ panels
- `2x3` otherwise

---

## Group-ID Dependencies

The following panels require group identifiers (`SCHOOL_NUMBER` and/or `DISTRICT_NUMBER`):
- `B`, `B2`, `D2`, `H`, `K`

If group identifiers are missing, these panels can be skipped or replaced with placeholders depending on script logic.

---

## Practical Workflow

1. Run STEP 2.1-2.4 via `master_analysis.R` or manually.
2. Run `create_publication_figure.R`.
3. Review individual panel PDFs.
4. Use `sgpc_summary_grid.pdf` as the assembled figure.

---

## Troubleshooting

### Missing panel files

Check that variant files exist:

```r
list.files("STEP_2_SGPc_Sensitivity/results", pattern = "sgpc_all_variants", full.names = TRUE)
```

### Group-level panels missing

```r
dt <- readRDS("STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_1.rds")
sum(!is.na(dt$SCHOOL_NUMBER))
sum(!is.na(dt$DISTRICT_NUMBER))
```

### Grid export dependencies

`generate_sgpc_summary_grid.R` attempts LaTeX compilation and format conversion; PDF/SVG/PNG export availability depends on installed system tools.

---

## Related Docs

- `STEP_2_SGPc_Sensitivity/README.md`
- `STEP_2_SGPc_Sensitivity/QUICKSTART.md`
- `STEP_2_SGPc_Sensitivity/PUBLICATION_FIGURE_IMPLEMENTATION.md`
