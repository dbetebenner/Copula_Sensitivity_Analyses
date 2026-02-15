# STEP 2 SGPc Sensitivity: Quick Start

## Purpose

Run STEP 2 end-to-end and generate both:
1. exploratory sensitivity visuals, and
2. publication-ready panel figures.

Documentation synchronized with implementation as of 2026-02-10.

---

## Prerequisites

1. Phase 1 outputs exist:
   - `STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json`
   - `STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv`
2. Dataset config and source data are available.

---

## Recommended: Run through `master_analysis.R`

```r
DATASETS_TO_RUN <- c("dataset_1")   # or multiple datasets
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- FALSE

source("master_analysis.R")
```

What this runs for STEP 2:
1. `sgpc_compute_all_variants.R` (Step 2.1)
2. `sgpc_aggregate_analysis.R` (Step 2.2)
3. `sgpc_visualizations.R` (Step 2.3)
4. `sgpc_generate_report.R` (Step 2.4)
5. `create_publication_figure.R` (Step 2.5)

---

## Local Subset Benchmarking (dataset_1 profiling)

Before committing to the full 966-condition run on EC2, profile locally
with small subsets of the largest dataset:

```r
# --- Quick smoke test (5 stratified conditions) ---
DATASETS_TO_RUN        <- "dataset_1"
STEPS_TO_RUN           <- c(2)
USE_PARALLEL_STEP2     <- TRUE
STEP2_MAX_CONDITIONS   <- 5
STEP2_SAMPLE_STRATEGY  <- "stratified"   # "first", "random", or "stratified"
STEP2_SEED             <- 42

source("master_analysis.R")
# Timing artifacts written to: STEP_2_SGPc_Sensitivity/results/perf/

# --- Medium benchmark (25 conditions) ---
STEP2_MAX_CONDITIONS <- 25
source("master_analysis.R")

# --- Full run (all conditions; omit or set NULL) ---
STEP2_MAX_CONDITIONS <- NULL
source("master_analysis.R")
```

Or run the dedicated benchmark script:

```r
source("STEP_2_SGPc_Sensitivity/benchmark_step2.R")
# Outputs: results/perf/benchmark_summary.csv, results/perf/ec2_projections.txt
```

### Memory controls for parallel workers

When running `dataset_1` in parallel, workers each load the full dataset
(~2-3 GB in memory). The system auto-estimates a safe worker count from
CPU cores and available RAM. Override for EC2 if needed:

```r
STEP2_MEMORY_PER_WORKER_GB <- 3.0    # Manual per-worker estimate (GB)
STEP2_TOTAL_MEMORY_GB      <- 384    # Total EC2 instance RAM (GB)
```

---

## EC2 Execution

### Recommended staging sequence

1. **Smoke test** (5 conditions per dataset, ~2-5 min):

```r
STEP2_MAX_CONDITIONS <- 5
DATASETS_TO_RUN <- c("dataset_1", "dataset_4")
```

2. **Medium validation** (25-50 conditions, ~30-60 min):

```r
STEP2_MAX_CONDITIONS <- 50
DATASETS_TO_RUN <- c("dataset_1")
```

3. **Full run** (all 966 conditions across 4 datasets):

```r
STEP2_MAX_CONDITIONS <- NULL
DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")
```

### Recommended EC2 instance types

| Instance | vCPU | RAM | Notes |
|----------|------|-----|-------|
| `r8g.12xlarge` | 48 | 384 GB | Adequate for all datasets |
| `r8g.24xlarge` | 96 | 768 GB | Recommended for full run |
| `m8g.metal-48xl` | 192 | 768 GB | Fastest (same as STEP_1 run) |

### Performance log location

After each run, timing data is written to:

```
STEP_2_SGPc_Sensitivity/results/perf/step2_perf_{dataset_id}.json
```

Fields: `phase1_load_secs`, `compute_secs`, `save_secs`, `total_secs`,
`n_workers`, `mem_per_worker_gb`, `worker_limit`, `n_conditions`, `n_obs`.

---

## Fast Path: Regenerate publication panels only

Use this when `sgpc_all_variants_dataset_*.rds` already exist and you only want updated panel outputs.

```r
source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
```

---

## Manual Script-by-Script Workflow

```r
# Step 2.1
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")

# Step 2.2
source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")

# Step 2.3
source("STEP_2_SGPc_Sensitivity/sgpc_visualizations.R")

# Step 2.4
source("STEP_2_SGPc_Sensitivity/sgpc_generate_report.R")

# Step 2.5
source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
```

---

## Output Checklist

### Core STEP 2 outputs (`results/`)

- `sgpc_all_variants_dataset_{1-4}.rds`
- `sgpc_sensitivity_summary.csv`
- `sgpc_correlation_matrix.csv`
- `sgpc_key_comparisons.csv`
- `sgpc_pairwise_differences.csv`
- `sgpc_by_year_span.csv`
- `sgpc_by_content_area.csv`
- `sgpc_by_stratum.csv`
- `sgpc_by_prior_quartile.csv`
- `sgpc_sensitivity_manifest.json`
- `SGPC_SENSITIVITY_REPORT.md`
- `sgpc_enhanced_stats.rds` (from publication figure path)

### Exploratory visualization outputs (`results/visualizations/`)

- `scatter_*.{pdf,svg,png}`
- `histogram_differences.{pdf,svg,png}`
- `heatmap_*.{pdf,svg,png}`
- `violin_by_prior_quartile.{pdf,svg,png}`
- `bland_altman_*.{pdf,svg,png}`

### Publication panel outputs (`results/visualizations/`)

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
- `sgpc_summary_grid.{pdf,svg,png}`

---

## Group-ID Requirement (Important)

Panels `B`, `B2`, `D2`, `H`, and `K` require valid `SCHOOL_NUMBER` and/or `DISTRICT_NUMBER`.

Quick check:

```r
dt <- readRDS("STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_1.rds")
sum(!is.na(dt$SCHOOL_NUMBER))
sum(!is.na(dt$DISTRICT_NUMBER))
```

If these are zero, regenerate Step 2.1 from source data that includes group identifiers.

---

## Comparison Label Conventions

Publication/enhanced-statistics panels use these exact labels:
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

## Common Issues

### Missing manifest/canonical files

```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```

### Missing variant results

```r
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
```

### Publication figure missing group-level panels

Verify group IDs in variant RDS and rerun Step 2.1 if needed.

---

## Where to Go Next

- Detailed methodology: `STEP_2_SGPc_Sensitivity/README.md`
- Publication panel details: `STEP_2_SGPc_Sensitivity/PUBLICATION_FIGURE_USAGE.md`
