# STEP 2: SGPc Sensitivity Analysis

## Overview

STEP 2 evaluates the practical impact of copula choice on Student Growth Percentiles (SGPc). It is designed to answer whether model choice changes conclusions at student, school, district, and condition levels.

This directory now supports two complementary visualization tracks:

1. Exploratory visualizations (`sgpc_visualizations.R`)
2. Publication panel pipeline (`create_publication_figure.R`)

Documentation synchronized with code as of 2026-02-10.

Source-of-truth implementation files:
- `STEP_2_SGPc_Sensitivity/create_publication_figure.R`
- `STEP_2_SGPc_Sensitivity/sgpc_publication_plots.R`
- `STEP_2_SGPc_Sensitivity/sgpc_enhanced_statistics.R`
- `STEP_2_SGPc_Sensitivity/sgpc_visualizations.R`

---

## Research Questions

STEP 2 is oriented around downstream SGPc consequences, not re-testing parameter stability:

1. How close are parametric SGPcs to empirical SGPcs?
2. Is canonical (averaged) copula performance adequate when condition-specific fitting is unavailable?
3. What is the impact of family mis-specification?
4. How extreme is the comonotonic assumption?
5. How closely do SGPc variants track traditional SGP (when available)?
6. How robust are rank and classification decisions across model choices?

---

## STEP_1 Context: What Copula Meta-Analysis Found

STEP_2 sensitivity analyses are grounded in STEP_1's comprehensive copula family selection across 966 conditions in 4 longitudinal assessment datasets. The key findings that inform STEP_2's design:

### Family Selection (AIC-based, 966 conditions)

| Family | % AIC-best | Interpretation |
|--------|-----------|----------------|
| t-copula | 63.6% | Dominant choice; symmetric tail dependence, flexible df |
| Frank | 30.7% | Significant minority; symmetric, no tail dependence |
| Gumbel | 3.6% | Upper tail dependence; rare but present |
| Gaussian | 2.1% | Special case of t (df -> infinity); rarely preferred |

### Canonical Copula Parameters (by year span)

| Year Span | Median tau | Median rho | Median df | Stability |
|-----------|-----------|-----------|----------|-----------|
| 1 year | 0.551-0.589 | 0.757-0.800 | 25.1-55.6 | HIGH |
| 2 years | 0.413-0.460 | 0.588-0.646 | 28.3-41.3 | HIGH-MEDIUM |
| 3 years | 0.344-0.382 | 0.498-0.549 | 29.1-42.4 | MEDIUM |
| 4 years | 0.288-0.363 | 0.424-0.524 | 29.2-36.4 | MEDIUM |

Key pattern: tau decays monotonically with year span (weaker dependence over longer periods).

### How STEP_2 Variants Map to STEP_1 Findings

| STEP_2 Variant | STEP_1 Finding It Tests |
|----------------|------------------------|
| `sgpc_avg` (canonical) | Whether stratum-level t-copula medians are adequate operationally |
| `sgpc_best` (per-condition) | Upper bound on parametric copula accuracy |
| `sgpc_frank` | Whether the 30.7% Frank-best conditions are meaningfully different |
| `sgpc_gaussian` | Whether ignoring tail dependence matters (Gaussian = t with df=inf) |
| `sgpc_t` (df=4) | Extreme stress test: df=4 is ~5x below observed minimum (~23) |
| `sgpc_gumbel` | Asymmetric tail dependence (upper) |
| `sgpc_clayton` | Asymmetric tail dependence (lower) |
| `sgpc_comonotonic` | Maximum-dependence bound (TAMP assumption) |

### Canonical Validation

The `canonical_validation.R` script (Step 2.1b) empirically validates whether the t-canonical is the most defensible single-family choice for each stratum, using STEP_2's computed SGPc variants. This is critical for the TIMSS deployment (year_span=4, MATHEMATICS), where the canonical copula is the only option.

---

## SGPc Variants

Core variants computed per condition, grounded in STEP_1 findings (966 conditions, 4 datasets):

| Variant | Description | STEP_1 Grounding |
|---------|-------------|------------------|
| `sgpc_emp` | Empirical Bernstein copula (non-parametric truth) | Per-condition empirical copula from STEP_1 |
| `sgpc_best` | Best-fit parametric copula (condition-specific AIC winner) | t-copula 63.6%, Frank 30.7%, Gumbel 3.6%, Gaussian 2.1% |
| `sgpc_avg` | Canonical copula (t-copula with stratum-specific median rho, df) | Median parameters across year_span x content_area strata; the copula that would be used for TIMSS/NAEP |
| `sgpc_gaussian` | Gaussian copula (no tail dependence) | Gaussian was AIC-best for only 2.1% of conditions |
| `sgpc_gumbel` | Gumbel copula (upper tail dependence) | AIC-best for 3.6%; tests asymmetric tail sensitivity |
| `sgpc_frank` | Frank copula (symmetric, no tail dependence) | AIC-best for 30.7% of conditions; the primary runner-up family |
| `sgpc_clayton` | Clayton copula (lower tail dependence) | Never AIC-best; tests opposite tail asymmetry |
| `sgpc_t` | t-copula with df=4 (extreme tail dependence) | STEP_1 actual df median: 23.7-55.6 across strata; df=4 is a ~5x stress test |
| `sgpc_comonotonic` | Perfect dependence (TAMP assumption) | Upper bound; assumes prior perfectly determines current |
| `sgp_traditional` | B-spline quantile regression SGP (if available) | Independent of copula; traditional SGP methodology |

### Important Note: Comonotonic Copula Interpretation

The comonotonic copula C(u,v) = min(u,v) represents **perfect positive dependence** (V = U almost surely, meaning ranks are perfectly preserved). The conditional CDF P(V ≤ v | U = u) = ∂C/∂u is mathematically a **step function**:
- P(V ≤ v | U = u) = 1 if v ≥ u (rank maintained/improved)
- P(V ≤ v | U = u) = 0 if v < u (rank declined)

This implementation produces a **bimodal SGPc distribution** (all 1s and 99s), which effectively demonstrates how real assessment data deviates from the TAMP assumption of perfect dependence.

**Alternative Interpretation:** An alternative exists where comonotonicity yields **uniform SGPc = 50** for all students, interpreting perfect rank preservation as "exactly 1 year's growth." Both interpretations have theoretical merit:
- **Step function (current)**: Derivative-based, emphasizes rank changes, demonstrates TAMP extremity
- **Constant 50**: "Typical growth" interpretation, useful for growth regime inference

The current step function approach is mathematically grounded in copula theory and operationally effective for sensitivity analysis. Future work may implement both interpretations with a parameter flag for context-specific applications (e.g., STEP_3 growth regime inference). See `functions/sgpc_engine.R` for detailed mathematical discussion.

---

## Workflow

### Prerequisites

Run Phase 1 first so canonical parameters and condition-level fits are available:
- `STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json`
- `STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv`
- condition-level files in `STEP_1_Family_Selection/results/dataset_{1-4}/`

### Step 2.1: Compute all variants

```r
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
```

Primary output:
- `results/sgpc_all_variants_dataset_{1-4}.rds`

### Step 2.1b: Canonical copula validation

```r
source("STEP_2_SGPc_Sensitivity/canonical_validation.R")
```

Validates the canonical copula selection against empirical SGPc. Answers whether the t-canonical (used operationally for TIMSS/NAEP) is the most defensible single-family choice for each stratum. Produces per-stratum family distributions, MAD comparisons, and a decision report.

Primary outputs in `results/`:
- `canonical_family_distribution_by_stratum.csv`
- `canonical_validation_by_stratum.csv`
- `canonical_validation_by_condition.csv`
- `canonical_validation_report.md`

### Step 2.2: Aggregate analysis

```r
source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
```

Primary outputs:
- `sgpc_sensitivity_summary.csv`
- `sgpc_correlation_matrix.csv`
- `sgpc_key_comparisons.csv`
- `sgpc_pairwise_differences.csv`
- `sgpc_by_year_span.csv`
- `sgpc_by_content_area.csv`
- `sgpc_by_stratum.csv`
- `sgpc_by_prior_quartile.csv`

(Consolidated manifest is written in Step 2.6.)

### Step 2.3: Exploratory visualizations

```r
source("STEP_2_SGPc_Sensitivity/sgpc_visualizations.R")
```

Primary outputs in `results/visualizations/`:
- scatter plots (`scatter_*.{pdf,svg,png}`)
- histogram differences (`histogram_differences.{pdf,svg,png}`)
- heatmaps (`heatmap_*.{pdf,svg,png}`)
- violin (`violin_by_prior_quartile.{pdf,svg,png}`)
- bland-altman (`bland_altman_*.{pdf,svg,png}`)

### Step 2.4: Narrative report

```r
source("STEP_2_SGPc_Sensitivity/sgpc_generate_report.R")
```

Primary output:
- `results/SGPC_SENSITIVITY_REPORT.md`

### Step 2.5: Publication panel figure

```r
source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
```

This computes enhanced statistics and builds the publication panel suite.

Primary outputs in `results/visualizations/`:
- `panel_a_individual_ecdf.{pdf,svg,png}`
- `panel_b_school_ecdf.{pdf,svg,png}` (requires `SCHOOL_NUMBER`)
- `panel_b2_district_ecdf.{pdf,svg,png}` (requires `DISTRICT_NUMBER`)
- `panel_c_condition_dots.{pdf,svg,png}`
- `panel_d_rank_agreement.{pdf,svg,png}`
- `panel_e_decile_stability.{pdf,svg,png}`
- `panel_d2_group_bucket_stability.{pdf,svg,png}`
- `panel_f_prior_quartile.{pdf,svg,png}`
- `panel_g_cross_dataset.{pdf,svg,png}`
- `panel_h_multilevel_aggregation.{pdf,svg,png}` (requires group IDs)
- `panel_i_error_decomposition.{pdf,svg,png}`
- `panel_j_condition_n_vs_mad.{pdf,svg,png}`
- `panel_k_group_rank_stability.{pdf,svg,png}` (requires group IDs)
- `sgpc_summary_grid.{pdf,svg,png}`

Additional cache output:
- `results/sgpc_enhanced_stats.rds`

### Step 2.6: Consolidated manifest

After all sub-steps (2.1 through 2.5), the pipeline runs Step 2.6 to write a single consolidated manifest that aggregates sensitivity summary, canonical validation, variant rankings, and recommendations for downstream steps (STEP_3, STEP_4).

```r
source("STEP_2_SGPc_Sensitivity/write_step2_manifest.R")
```

Primary output:
- `results/sgpc_sensitivity_manifest.json`

The manifest is built from existing CSVs and optional STEP_1 manifest; it is always refreshed when STEP_2 runs (not gated by skip-completed). Use it for reporting and for STEP_3 (LIwLD) / STEP_4 (TIMSS) integration.

---

## Current Comparison Labels

Publication and enhanced-stat panels use exact labels below:

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

Note: `sgpc_visualizations.R` may use display labels with hyphen formatting for selected plots.

---

## Panel Map (Publication Figure)

- **A**: Individual-level ECDF
- **B**: School-level ECDF
- **B2**: District-level ECDF
- **C**: Condition-level MAD dots
- **D**: Individual rank agreement
- **E**: Individual classification stability (K = 3, 5, 10)
- **D2**: Group-level bucket stability (K = 3, 5, 10)
- **F**: Prior-achievement quartile sensitivity
- **G**: Cross-dataset comparison
- **H**: Multi-level aggregation
- **I**: Error decomposition (comparison vs sampling)
- **J**: Condition N vs MAD
- **K**: Group-level rank stability

---

## Notes on Group-ID Dependencies

Panels requiring school/district identifiers: `B`, `B2`, `D2`, `H`, `K`.

If `SCHOOL_NUMBER` / `DISTRICT_NUMBER` are missing or all NA, those panels may be skipped or replaced by placeholders depending on script behavior.

---

## Scaling and Performance

### Workload by dataset

| Dataset | Conditions | Median n_pairs | Workload proxy | File (SGP) |
|---------|-----------|---------------|----------------|-----------|
| dataset_1 | 510 | ~51,900 | 26.5 M | 333 MB |
| dataset_2 | 194 | ~18,700 | 3.6 M | 61 MB |
| dataset_3 | 80 | ~37,700 | 3.0 M | 70 MB |
| dataset_4 | 182 | ~10,900 | 2.0 M | 34 MB |
| **Total** | **966** | | **35.1 M** | |

### Key bottleneck: empirical copula (`sgpc_emp`)

The empirical Bernstein copula computation dominates per-condition time,
scaling super-linearly with `n_pairs`. From local benchmarks:

- dataset_4 (~10K pairs): ~9 s/condition (total 28 min for 182 conditions)
- dataset_1 (~50K pairs): ~700-800 s/condition

This means `sgpc_emp` takes ~92% of per-condition wall time for large cohorts.
Parametric copulas (Gaussian, Frank, etc.) are 1-2 orders of magnitude faster.

### Parallel dispatch architecture

Workers are launched via `mirai` daemons. Each worker:

1. Loads the dataset once (lazy, cached via `STATE_DATA_LONG`)
2. Loads its own Phase 1 results from disk per condition (low-memory dispatch)
3. Computes all 10 SGPc variants
4. Returns the result `data.table`

The **low-memory dispatch** design avoids shipping the full `phase1_batch` to
every worker. Instead, only condition IDs and lightweight config are serialized.

### Memory-aware worker capping

The system auto-estimates a safe worker count from both CPU cores and available
RAM. The formula:

```
per_worker_gb = (dataset_file_gb × 7) + 0.5   # decompression + overhead
mem_cap       = floor(system_ram × 0.80 / per_worker_gb)
n_workers     = min(cpu_cap, mem_cap)
```

Override with `STEP2_MEMORY_PER_WORKER_GB` and `STEP2_TOTAL_MEMORY_GB`.

### Performance instrumentation

Every Step 2.1 run writes a JSON log to:

```
STEP_2_SGPc_Sensitivity/results/perf/step2_perf_{dataset_id}.json
```

Fields include: `phase1_load_secs`, `compute_secs`, `save_secs`, `total_secs`,
`n_workers`, `mem_per_worker_gb`, `worker_limit`, throughput metrics.

### Subset profiling

Test locally before committing to full EC2 runs:

```r
STEP2_MAX_CONDITIONS  <- 10          # Cap per dataset
STEP2_SAMPLE_STRATEGY <- "stratified" # Proportional across strata
STEP2_SEED            <- 42          # Reproducible
```

Or use the dedicated benchmark script:

```r
source("STEP_2_SGPc_Sensitivity/benchmark_step2.R")
```

---

## Recommended Execution

### Through master pipeline

```r
DATASETS_TO_RUN <- c("dataset_1")
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- TRUE
source("master_analysis.R")
```

### Subset benchmark (local profiling)

```r
DATASETS_TO_RUN        <- "dataset_1"
STEPS_TO_RUN           <- c(2)
STEP2_MAX_CONDITIONS   <- 10
STEP2_SAMPLE_STRATEGY  <- "stratified"
USE_PARALLEL_STEP2     <- TRUE
source("master_analysis.R")
```

### Publication-only refresh (when STEP 2 outputs already exist)

```r
source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
```

---

## Troubleshooting

### Missing Phase 1 artifacts

Run:

```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```

### Missing STEP 2 variant files

Run:

```r
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
```

### Publication figure panels skipped

Check whether group identifiers are present in variant files:

```r
dt <- readRDS("STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_1.rds")
"SCHOOL_NUMBER" %in% names(dt)
"DISTRICT_NUMBER" %in% names(dt)
```

---

## Related Documentation

- `STEP_2_SGPc_Sensitivity/QUICKSTART.md`
- `STEP_2_SGPc_Sensitivity/PUBLICATION_FIGURE_USAGE.md`
- `STEP_2_SGPc_Sensitivity/PUBLICATION_FIGURE_IMPLEMENTATION.md`
- `STEP_1_Family_Selection/README.md`
