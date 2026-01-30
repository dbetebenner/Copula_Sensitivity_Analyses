# STEP 2: SGPc Sensitivity Analysis

## Overview

**New Focus (January 2026)**: STEP 2 now evaluates the **practical impact of copula choice on Student Growth Percentiles (SGPcs)**, demonstrating the Sklar-theoretic extension of TAMP (Test Assessment Mapping Procedure).

**Previous STEP 2** (Experiments 1-4: grade span, sample size, content area, cohort effects) tested copula parameter stability. However, **Phase 1 already comprehensively analyzed this** across 966 conditions. See Phase 1's visualization showing τ, ρ, and λ declining with year span.

**What Changed**: Instead of re-testing parameter stability, STEP 2 now answers: **"What happens to SGPcs when we use different copulas?"**

---

## Research Questions

### New STEP 2 Addresses:

1. **Empirical Validation**: How close are parametric SGPcs to empirical (non-parametric truth)?
2. **Canonical Adequacy**: Can we use averaged parameters (from manifest) instead of condition-specific fits?
3. **Mis-specification Impact**: What happens when we use the wrong copula family?
4. **TAMP Comparison**: How extreme is the comonotonic (perfect dependence) assumption?
5. **SGP Equivalence**: Are copula-based SGPcs practically equivalent to traditional SGP?
6. **Subgroup Sensitivity**: Where do differences matter most? (tails, low-achievers, specific grades)

### NOT Re-tested (Already in Phase 1):

- ~~Does τ decline with grade span?~~ → **YES** (Phase 1: 966 conditions)
- ~~Are parameters stable across content areas?~~ → **Mostly YES** (Phase 1 statistical tests)
- ~~Do sample sizes affect estimates?~~ → **YES** at n<500 (Phase 1 bootstrap)

---

## SGPc Variants Computed

For each observation, we compute **7+ SGPc variants**:

| Variant | Description | Purpose |
|---------|-------------|---------|
| **SGPc_emp** | Empirical Bernstein copula | Non-parametric "truth" baseline |
| **SGPc_best** | Best-fitting parametric copula | Condition-specific from Phase 1 AIC |
| **SGPc_avg** | Canonical averaged copula | From manifest (year_span × content_area) |
| **SGPc_gaussian** | Gaussian copula | Mis-specified (no tail dependence) |
| **SGPc_gumbel** | Gumbel copula | Mis-specified (upper tail only) |
| **SGPc_frank** | Frank copula | Mis-specified (symmetric, no tails) |
| **SGPc_comonotonic** | Comonotonic (perfect dependence) | TAMP assumption |
| **SGP_traditional** | B-spline quantile regression | Traditional SGP baseline (if available) |

---

## Workflow

### Prerequisites

1. **Phase 1 Complete**: Run `STEP_1_Family_Selection/phase1_family_selection_parallel.R`
2. **Phase 1 Analysis**: Run `STEP_1_Family_Selection/phase1_analysis.R`
3. **Outputs Exist**:
   - `STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json`
   - `STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv`
   - Per-dataset Phase 1 results in `STEP_1_Family_Selection/results/dataset_{1-4}/`

### Step 1: Compute All Variants

```r
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
```

**What it does:**
- Loads Phase 1 outputs (empirical copulas, parametric fits, manifest)
- For each of 966 conditions:
  - Creates longitudinal pairs
  - Computes pseudo-observations (ranks)
  - Runs `sgpc_engine()` for each of 7+ copula variants
- Saves per-dataset RDS: `results/sgpc_all_variants_dataset_{1-4}.rds`

**Runtime:** 30-60 minutes per dataset (sequential), faster with `USE_PARALLEL = TRUE`

### Step 2: Aggregate Analysis

```r
source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
```

**What it does:**
- Loads all variant datasets
- Computes aggregate statistics:
  - Correlations between variants
  - Mean absolute differences (MAD)
  - Root mean square differences (RMSD)
- Stratified analyses:
  - By year_span, content_area, year_span × content_area
  - By prior achievement quartile
- Saves CSV summaries and AI-readable JSON manifest

**Outputs:**
- `sgpc_sensitivity_summary.csv` - Overall statistics
- `sgpc_correlation_matrix.csv` - Pairwise correlations
- `sgpc_key_comparisons.csv` - Key pairing statistics
- `sgpc_by_year_span.csv` - Stratified by span
- `sgpc_by_content_area.csv` - Stratified by content
- `sgpc_by_stratum.csv` - Cross-stratified
- `sgpc_by_prior_quartile.csv` - By achievement level
- `sgpc_sensitivity_manifest.json` - AI-readable structured output

### Step 3: Visualizations

```r
source("STEP_2_SGPc_Sensitivity/sgpc_visualizations.R")
```

**What it does:**
- Creates comprehensive visualization suite:
  - **Scatter plots**: SGPc comparisons with 45° reference lines
  - **Histograms**: Difference distributions
  - **Heatmaps**: MAD by year_span × content_area
  - **Violin plots**: Differences by prior achievement quartile
  - **Bland-Altman plots**: Agreement analysis
- Exports in PDF, SVG, PNG formats

**Outputs in `results/visualizations/`:**
- `scatter_emp_vs_best.{pdf,svg,png}`
- `scatter_emp_vs_canonical.{pdf,svg,png}`
- `scatter_emp_vs_gaussian.{pdf,svg,png}`
- `scatter_emp_vs_comonotonic.{pdf,svg,png}`
- `histogram_differences.{pdf,svg,png}`
- `heatmap_mad_emp_vs_best.{pdf,svg,png}`
- `heatmap_mad_emp_vs_canonical.{pdf,svg,png}`
- `violin_by_prior_quartile.{pdf,svg,png}`
- `bland_altman_emp_vs_best.{pdf,svg,png}`

---

## Key Comparisons

### 1. Empirical vs Best-Fit Parametric

**Question**: How well do condition-specific parametric copulas approximate the empirical truth?

**Expected**: Very high correlation (r > 0.95), low MAD (< 3 percentile points)

**Interpretation**: If close, parametric copulas are adequate for practical use.

### 2. Empirical vs Canonical Averaged

**Question**: Can we use averaged parameters from the manifest instead of fitting condition-specific copulas?

**Expected**: High correlation (r > 0.90), moderate MAD (3-6 percentile points)

**Interpretation**: Assesses the adequacy of canonical copulas for new datasets (e.g., TIMSS, PISA).

### 3. Empirical vs Gaussian (Mis-specified)

**Question**: What's the cost of using Gaussian copula (no tail dependence) when t-copula is best?

**Expected**: Moderate correlation (r ~ 0.85-0.90), higher MAD (5-10 percentile points)

**Interpretation**: Quantifies the impact of ignoring tail dependence.

### 4. Empirical vs Comonotonic (TAMP)

**Question**: How extreme is the perfect dependence assumption?

**Expected**: Lower correlation, bimodal distribution (SGPc = 1 or 99 for many students)

**Interpretation**: Demonstrates the value of moving beyond TAMP's comonotonic assumption.

### 5. Traditional SGP vs SGPc Variants

**Question**: Are copula-based SGPcs equivalent to traditional b-spline quantile regression?

**Expected**: High correlation if SGP is well-implemented

**Interpretation**: Validates that SGPc provides an alternative to traditional SGP.

---

## Interpreting Results

### Correlation Thresholds

| r Value | Interpretation |
|---------|----------------|
| r > 0.95 | **Excellent**: Methods nearly interchangeable |
| r 0.90-0.95 | **Good**: Methods mostly agree, minor differences |
| r 0.85-0.90 | **Moderate**: Systematic differences, caution needed |
| r < 0.85 | **Poor**: Methods disagree substantially |

### MAD Thresholds (Percentile Points)

| MAD | Practical Impact |
|-----|------------------|
| MAD < 3 | **Negligible**: Differences unlikely to affect decisions |
| MAD 3-5 | **Small**: Noticeable but acceptable in most contexts |
| MAD 5-10 | **Moderate**: May affect student-level inferences |
| MAD > 10 | **Large**: Substantial impact on growth classifications |

---

## Configuration Options

### In `sgpc_compute_all_variants.R`:

```r
# Which datasets to process
DATASETS_TO_PROCESS <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")

# Parallel processing (requires mirai package)
USE_PARALLEL <- FALSE  # Set TRUE for faster execution
N_CORES <- parallel::detectCores() - 1
```

### Adding Custom Variants

To add additional SGPc variants, modify `compute_sgpc_variants()`:

```r
# Example: Add Clayton copula
clayton_param <- iTau(claytonCopula(), tau)
clayton_cop <- claytonCopula(param = clayton_param)
result[, sgpc_clayton := sgpc_engine(u, v, clayton_cop, scale = "percentile")]
```

---

## Integration with Phase 1

STEP 2 leverages Phase 1 outputs:

1. **Canonical Parameters**: From `analysis_manifest.json` - used for SGPc_avg
2. **Best-Fit Copulas**: From per-condition Phase 1 fits - used for SGPc_best
3. **Empirical Copulas**: From Phase 1 Bernstein smoothing - used for SGPc_emp (truth)
4. **Pseudo-observations**: Recomputed from longitudinal pairs

**Note**: If Phase 1 empirical copulas are not saved, `sgpc_compute_all_variants.R` will create them on-the-fly using `empCopula()` with beta smoothing.

---

## Relation to STEP 4

**STEP 4** (Deep Dive Reporting) will use STEP 2 outputs for:
- Comprehensive comparison of SGP vs SGPc methods
- Identification of conditions where copula choice matters most
- Operational recommendations for when canonical vs condition-specific copulas are adequate

**STEP 2 provides the empirical evidence; STEP 4 synthesizes it into actionable insights.**

---

## Troubleshooting

### Error: "Manifest file not found"

**Solution**: Run Phase 1 analysis first:
```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```

### Error: "No variant results found"

**Solution**: Run computation script first:
```r
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
```

### Warning: "Empirical copula creation failed"

**Cause**: Insufficient data for condition or numerical issues

**Impact**: SGPc_emp will be NA for that condition

**Action**: Check data availability and condition configuration

### Slow Performance

**Options**:
1. Set `USE_PARALLEL = TRUE` in `sgpc_compute_all_variants.R`
2. Process fewer datasets
3. Subsample conditions for exploratory analysis

### Warning: "Phase 1 pobs dimension mismatch, recomputing"

**Cause**: The number of observations in Phase 1's pseudo-observations doesn't match current dataset

**Impact**: STEP 2 falls back to computing pseudo-observations from scale scores (may cause slight inconsistencies with Phase 1)

**Solution**: 
1. Verify Phase 1 completed successfully for that condition
2. Check that `pseudo_observations.rds` exists in the condition directory
3. Ensure no data filtering occurred between Phase 1 and STEP 2

**Why It Matters**: Using Phase 1's pseudo-observations ensures that SGPcs are computed on the **exact same transformed data** used to fit the copulas. Recomputing them may introduce tiny numerical differences.

---

## Citations & Methodology

**Phase 1 Foundation**: 966 conditions across 4 longitudinal assessment datasets

**Copula Families**: t, Gaussian, Frank, Clayton, Gumbel, Comonotonic, Empirical Bernstein

**Selection Criterion**: AIC (Akaike Information Criterion) - Phase 1

**SGPc Computation**: `sgpc_engine()` - vectorized conditional CDF: P(V ≤ v | U = u)

**Canonical Parameters**: Median ρ, ν, τ by year_span × content_area - Phase 1 manifest

**Pseudo-observations**: STEP 2 uses the **exact same pseudo-observations (u, v)** that Phase 1 used to fit copulas. These are loaded from `pseudo_observations.rds` in each condition's Phase 1 results directory. This ensures perfect consistency between copula fitting and SGPc computation—we're computing conditional CDFs on the same transformed data that defined the copulas.

---

## For More Information

- **Phase 1 README**: `STEP_1_Family_Selection/README.md` - Family selection methodology
- **Canonical Copulas**: `STEP_1_Family_Selection/CANONICAL_COPULA_README.md` - Using averaged parameters
- **SGPc Engine**: `functions/sgpc_engine.R` - Technical implementation
- **Original STEP 2**: `STEP_2_Copula_Sensitivity_Analyses/deprecated/` - Old parameter stability experiments

---

**Status**: Operational framework implemented (January 2026)

**Next Steps**: 
1. Integrate Phase 1 empirical copula loading
2. Test on all 4 datasets
3. Validate results
4. Generate final visualizations and report
