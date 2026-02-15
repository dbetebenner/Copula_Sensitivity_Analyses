# STEP 2 Publication Figure: Implementation Notes

## Status

Current publication pipeline is operational and produces a multi-panel figure from STEP 2 outputs.

Documentation synchronized with implementation as of 2026-02-10.

---

## Core Scripts and Responsibilities

### 1) `create_publication_figure.R`

Orchestration script that:
1. loads STEP 2 variant data,
2. computes enhanced statistics,
3. builds panels,
4. assembles summary grid,
5. exports outputs.

### 2) `sgpc_enhanced_statistics.R`

Computes statistics used by publication panels, including:
- individual-level differences and ECDF-ready summaries,
- school/district aggregate stats,
- rank agreement metrics,
- decile classification stability,
- group bucket stability (`K = 3, 5, 10` for school/district),
- sampling sensitivity and decomposition-support stats.

### 3) `sgpc_publication_plots.R`

Defines panel plotting functions and save helper:
- `plot_individual_ecdf()` (A)
- `plot_group_ecdf()` (B, B2)
- `plot_condition_dots()` (C)
- `plot_rank_agreement()` (D)
- `plot_decile_stability()` (E)
- `plot_group_bucket_stability()` (D2)
- `plot_prior_quartile_sensitivity()` (F)
- `plot_cross_dataset_comparison()` (G)
- `plot_multilevel_aggregation()` (H)
- `plot_error_decomposition()` (I)
- `plot_condition_n_vs_mad()` (J)
- `plot_group_rank_stability()` (K)
- `save_plot_multi()`

### 4) `generate_sgpc_summary_grid.R`

Builds the LaTeX summary grid and exports PDF/SVG/PNG with dynamic layout selection.

---

## Current Panel and File Mapping

| Panel | Function | Output prefix |
|---|---|---|
| A | `plot_individual_ecdf()` | `panel_a_individual_ecdf` |
| B | `plot_group_ecdf(..., "school")` | `panel_b_school_ecdf` |
| B2 | `plot_group_ecdf(..., "district")` | `panel_b2_district_ecdf` |
| C | `plot_condition_dots()` | `panel_c_condition_dots` |
| D | `plot_rank_agreement()` | `panel_d_rank_agreement` |
| E | `plot_decile_stability()` | `panel_e_decile_stability` |
| D2 | `plot_group_bucket_stability()` | `panel_d2_group_bucket_stability` |
| F | `plot_prior_quartile_sensitivity()` | `panel_f_prior_quartile` |
| G | `plot_cross_dataset_comparison()` | `panel_g_cross_dataset` |
| H | `plot_multilevel_aggregation()` | `panel_h_multilevel_aggregation` |
| I | `plot_error_decomposition()` | `panel_i_error_decomposition` |
| J | `plot_condition_n_vs_mad()` | `panel_j_condition_n_vs_mad` |
| K | `plot_group_rank_stability()` | `panel_k_group_rank_stability` |

Assembled grid output:
- `sgpc_summary_grid.{tex,pdf,svg,png}`

---

## Comparison Label Contract

Publication pipeline relies on exact label strings:

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

## Layout Logic

Grid layout is selected by panel count:
- 12+ panels -> `6x2`
- 10+ panels -> `5x2`
- 8+ panels -> `4x2`
- 6+ panels -> `3x2`
- otherwise -> `2x3`

---

## Group-Dependency Behavior

Panels requiring group identifiers:
- `B`, `B2`, `D2`, `H`, `K`

If group identifiers are unavailable or invalid, dependent panels may be skipped/placeholdered to allow the rest of the figure pipeline to complete.

---

## Typical Execution Paths

### Integrated (recommended)

```r
DATASETS_TO_RUN <- c("dataset_1")
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- FALSE
source("master_analysis.R")
```

### Standalone publication refresh

```r
source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
```

---

## Validation Targets

When validating docs/code alignment, confirm:
1. panel names and file prefixes match exactly,
2. panel letter mapping uses `D`, `E`, and `D2` semantics,
3. comparison labels match runtime strings,
4. output inventory reflects all panel files plus grid files.

---

## Historical Note

Older references to:
- `panel_d1_rank_agreement` and
- `panel_d2_decile_stability`

are legacy naming. Current pipeline uses:
- `panel_d_rank_agreement`
- `panel_e_decile_stability`
- `panel_d2_group_bucket_stability`
