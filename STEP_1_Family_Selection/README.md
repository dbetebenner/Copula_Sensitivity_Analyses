# STEP 1: Copula Family Selection

## Overview

**Paper Section:** Background → TAMP and Copulas; Methodology → Copula Selection and Parameter Estimation

**Objective:** Identify which copula family consistently provides the best fit for longitudinal educational assessment data using both relative (AIC/BIC) and absolute (goodness-of-fit) measures.

**Hypothesis:** t-copula will dominate due to heavy tails, with tail dependence increasing as time between observations increases. With large sample sizes, all parametric families may show statistically significant deviations, but t-copula will be closest to empirical fit.

---

## What This Step Does

Tests 6 copula families (5 parametric: Gaussian, t, Clayton, Gumbel, Frank + comonotonic) across multiple datasets:

**Dataset Coverage:**
- **Dataset 1 (Vertical Scale):** ~42 conditions, G3→G10, MATH/READ/WRITE
- **Dataset 2 (Non-Vertical Scale):** ~42 conditions, G3→G10, MATH/READ
- **Dataset 3 (Assessment Transition):** Exhaustive conditions, G3→G8, ELA/MATH/READ
- **Dataset 4 (Pandemic Analysis):** ~45 conditions, G3→G8 + G11, MATH/READ
  - **10 pandemic pairs** (2019-2021 spanning COVID gap)
  - **10 pre-pandemic baselines** (2017-2019 / 2016-2019)
  - **25 strategic subset** (pre/post-pandemic coverage)

**Test Dimensions:**
- Multiple grade spans (1, 2, 3, 4 years)
- Multiple content areas (Mathematics, Reading, Writing, ELA)
- Multiple cohorts (different years, including pandemic period)
- Grade range: G3→G11 (elementary through high school)
- Total conditions across all datasets: ~170

For each condition:
1. Create longitudinal pairs from state assessment data  
2. Transform to pseudo-observations using **empirical ranks via `pobs(..., ties.method="random")`**  
3. Fit all 6 copula families (5 parametric + comonotonic) using maximum pseudo-likelihood  
4. **Relative fit:** Compare using AIC and BIC  
5. **Absolute fit:** Goodness-of-fit via Cramér-von Mises test with parametric bootstrap (N=1000)  
   - Parametric families: Full bootstrap with p-values  
   - Comonotonic: Observed statistic only (no bootstrap)  
6. **SGPc calculation:** Compute copula-based Student Growth Percentiles for each family
   - Uses `sgpc_engine()` for efficient conditional CDF calculation
   - Compares parametric SGPc, empirical SGPc (Bernstein), and comonotonic SGPc
   - Correlates with traditional b-spline/quantile regression SGP
7. Record selection frequencies, GoF results, and SGPc comparisons

**Key Methodological Decisions:**
1. **Empirical ranks** (not smoothing) ensure uniform pseudo-observations and preserve tail dependence
2. **Randomized tie-breaking** via `pobs()` prevents discrete data issues in GoF testing
3. **Statistical vs. practical significance** distinction: Large n (28,567) → high power → statistical rejection expected, but relative differences inform practical model selection

---

## Scripts

### 1. `phase1_family_selection.R`
**Runtime:** ~45-90 minutes

**What it does:**
- Loads state longitudinal data
- Tests all 6 copula families across 42 conditions
- Uses empirical ranks for transformation (validates two-stage approach)
- Saves detailed results for each condition
- Covers grade range G3→G10 to test copula behavior across developmental stages

**Outputs:**
- `results/{dataset_id}/phase1_copula_family_comparison.csv` - Complete results table
- `results/{dataset_id}/contour_plots/{condition}/` - Visualization plots for each condition
  - Bivariate density plot (original scores)
  - Empirical copula CDF and PDF plots
  - Parametric copula plots (CDF, PDF) for each family
  - Comparison plots (empirical vs. parametric)
  - Uncertainty plots with bootstrap confidence bands
  - Summary grid combining key visualizations
  - **Per-family summary files (NEW):**
    - `{FAMILY}/{family}_summary.json` - Structured fit metrics, tail dependence, SGPc comparison
    - `{FAMILY}/{family}_summary.md` - Human-readable summary with parameter recommendations
- `results/{dataset_id}/sgpc/{condition}/sgpc_results.rds` - SGPc results per condition
  - Contains SGPc values for all copula families (SGPc_t, SGPc_gaussian, etc.)
  - Includes traditional SGP for comparison (if available)
  - Pseudo-observations (U, V) for reference
- `results/{dataset_id}/sgpc/sgpc_all_conditions.rds` - Combined SGPc results
- Console summary of selection frequencies and SGPc correlations

### 2. `phase1_analysis.R`
**Runtime:** ~5-10 minutes

**What it does:**
- Analyzes selection patterns
- Identifies winning family
- Tests for consistency across conditions
- Generates visualizations
- Makes decision for Steps 2-4

**Outputs:**
- `results/dataset_all/phase1_decision.RData` - Decision for later steps
- `results/dataset_all/phase1_summary.txt` - Text summary
- `results/dataset_all/phase1_*.{pdf,svg,png}` - Multi-format visualizations:

### 3. `pandemic_analysis_dataset4.R` (NEW)
**Runtime:** ~2-3 minutes

**What it does:**
- Focused pandemic impact analysis for Dataset 4
- Compares 10 pandemic pairs (2019-2021) vs. 10 pre-pandemic baselines (2017-2019)
- Tests whether COVID-19 disrupted copula dependency structure
- Calculates parameter changes: Δτ (Kendall's tau), Δdf (degrees of freedom), Δtail_dep
- Generates comparison visualizations and summary report

**Usage:**
```r
# Run AFTER phase1_family_selection.R completes for dataset_4
source("STEP_1_Family_Selection/pandemic_analysis_dataset4.R")

# Or use convenience script (runs STEP 1 + pandemic analysis):
source("run_dataset4_analysis.R")
```

**Outputs:**
- `results/dataset_4/pandemic_analysis/pandemic_parameter_comparison.csv` - All parameter changes
- `results/dataset_4/pandemic_analysis/pandemic_summary_report.txt` - Interpretation
- `results/dataset_4/pandemic_analysis/pandemic_tau_change.pdf` - Δτ visualization
- `results/dataset_4/pandemic_analysis/pandemic_df_change.pdf` - Δdf visualization
- `results/dataset_4/pandemic_analysis/pandemic_tau_scatter.pdf` - Before/after scatter

**Research Question:**
Did the COVID-19 pandemic (2020 school closures) disrupt the copula dependency structure in longitudinal educational assessments?

**Matched Pairs:**
| Grade Pair | Pandemic Period | Baseline Period | Time Span |
|------------|-----------------|-----------------|-----------|
| G3→G5 | 2019→2021 | 2017→2019 | 2 years |
| G4→G6 | 2019→2021 | 2017→2019 | 2 years |
| G5→G7 | 2019→2021 | 2017→2019 | 2 years |
| G6→G8 | 2019→2021 | 2017→2019 | 2 years |
| G8→G11 | 2018→2021 | 2016→2019 | 3 years |

Each pair tested for MATHEMATICS and READING (10 pairs total).
  - **phase1_absolute_relative_fit** - Two-panel violin plot (absolute GoF + relative ΔAIC)
  - **phase1_copula_selection_by_condition** - Proportion bars showing family selection by span/content
  - **phase1_t_copula_phase_diagram** - Degrees of freedom vs tail dependence landscape
  - **phase1_aic_by_span** - Mean AIC trends by year span (to be refined)
  - **phase1_tail_dependence** - Tail dependence patterns (to be refined)
  - **phase1_mosaic_*.{pdf,svg,png}** - Mosaic plots (to be reassessed)
- `results/dataset_all/phase1_*.csv` - Summary tables
- **AI-Consumable Manifest Files (NEW):**
  - `results/dataset_all/analysis_manifest.json` - Unified JSON manifest for AI summarization
  - `results/dataset_all/analysis_manifest.md` - Human-readable parameter recommendations
- Note: Removed redundant plots (selection_frequency, delta_aic_distributions, aic_weights, heatmap)

### Archived empCopula Objects

For each condition analyzed, two standardized empirical copula objects are saved:

**File**: `results/{dataset_id}/contour_plots/{condition}/empirical_copulas.rds`

**Contents**: Named list with two `empCopula` class objects from the copula package:

1. **raw**: Deheuvels empirical copula (step function, no smoothing)
   - Purpose: Gold standard for parametric copula comparison
   - The empirical CDF of pseudo-observations
   - Used in GoF tests to evaluate parametric families
   - NOT suitable for SGPc (no smooth density)

2. **bernstein**: Bernstein polynomial smoothed copula
   - Purpose: Smooth empirical estimator for SGPc calculations
   - Uses `smoothing = "beta"` (Bernstein basis via beta distribution)
   - Excellent boundary behavior (u,v near 0 or 1)
   - Supports `pCopula()` (CDF) and `dCopula()` (density)
   - Alternative to KDE approach for SGPc

**Usage**: These objects are archived for future analyses and can be used directly with:
- `pCopula(u, copula = emp_cop)` - evaluate CDF
- `dCopula(u, copula = emp_cop)` - evaluate density (Bernstein only)
- `rCopula(n, copula = emp_cop)` - generate random samples

**SGPc Calculation Strategy**: 
- **Bernstein** (via saved empCopula objects): Primary method for SGPc calculation
- **Raw (Deheuvels)**: Used for validation and comparison
- **KDE**: **EXCLUDED** from downstream analyses (see note below)

Both Raw and Bernstein empirical copulas are compared against traditional b-spline quantile regression SGPs (SGP_ORDER_1) for sensitivity analysis.

**KDE Exclusion Note**: Kernel density estimation (KDE) is NOT used downstream for SGPc calculation. Only Raw and Bernstein smoothed copulas are used in the analysis pipeline. KDE was evaluated during development but Bernstein provides better boundary behavior and is mathematically well-suited for copula smoothing.

**Directory Structure (Updated December 2025)**:
```
EMPIRICAL/RAW/               - Raw (Deheuvels) copula plots + SGP comparison
EMPIRICAL/BERNSTEIN/         - Bernstein copula plots + SGP comparison
EMPIRICAL/comparison_raw_vs_bernstein_CDF.pdf
PARAMETRIC/{FAMILY}/         - Parametric copula comparisons (moved from condition root)
```

---

## SGPc Calculation (Copula-based Student Growth Percentiles)

### Overview

SGPc represents student growth percentiles computed from fitted copulas, providing an alternative to traditional b-spline/quantile regression SGPs. For each student, SGPc answers: "Given this student's prior score percentile (U), what percentile is their current score (V)?"

**Mathematical basis:**  
SGPc = P(V ≤ v | U = u) × 100

This is the conditional CDF of the copula, computed using the partial derivative ∂C(u,v)/∂u.

### Implementation

The `sgpc_engine.R` provides efficient SGPc calculation:

```r
# Parametric copulas: Use native cCopula() - very fast
sgpc_t <- sgpc_engine(U, V, fitted_t_copula, scale = "percentile")

# Empirical Bernstein copula: Grid interpolation - fast after setup
sgpc_emp <- sgpc_engine(U, V, emp_bernstein_copula, scale = "percentile")

# Comonotonic (TAMP assumption): SGPc = U (prior percentile persists)
sgpc_tamp <- sgpc_engine(U, V, "comonotonic", scale = "percentile")
```

### Performance

| Method | 100k observations | Notes |
|--------|-------------------|-------|
| Parametric (t, gaussian, etc.) | ~0.3s | Native `cCopula()` |
| Empirical Bernstein | ~0.02s | Grid interpolation (after ~2s setup) |
| Comonotonic | <0.01s | Vectorized formula |

### SGPc Columns in Output

After running Step 1 with `CALCULATE_SGPC = TRUE`, the data files contain:
- `SGPc_t` - t-copula SGPc
- `SGPc_gaussian` - Gaussian copula SGPc
- `SGPc_clayton` - Clayton copula SGPc
- `SGPc_gumbel` - Gumbel copula SGPc
- `SGPc_frank` - Frank copula SGPc
- `SGPc_comonotonic` - Comonotonic SGPc (demonstrates TAMP assumption)
- `SGPc_bernstein` - Bernstein empirical copula SGPc
- `SGP` - Traditional b-spline/quantile regression SGP (if available)

### Key Insights

1. **Comonotonic SGPc = U**: Under perfect positive dependence, a student's growth percentile equals their prior achievement percentile. This is what the traditional TAMP assumption implicitly produces.

2. **t-copula captures tail dependence**: Unlike Gaussian, t-copula accounts for extreme students having even more extreme growth, producing different SGPc values in the tails.

3. **Empirical vs. parametric**: Bernstein-smoothed empirical copula provides non-parametric SGPc, useful for validating parametric assumptions.

---

## AI-Consumable Manifest Export (NEW)

### Purpose

The analysis outputs are designed to be easily consumable by AI systems for:
- Summarizing results across hundreds of conditions
- Recommending optimal copula parameters for specific use cases (e.g., TIMSS-like sampled data)
- Stratifying recommendations by year span and content area

### Output Files

**Unified Manifest** (in `results/dataset_all/`):
- `analysis_manifest.json` - Structured JSON with:
  - `metadata`: Generation timestamp, total conditions analyzed
  - `parameter_recommendations.overall_best`: Best family with parameters (rho, df, tau)
  - `parameter_recommendations.by_year_span`: Stratified by 1, 2, 3, 4-year spans
  - `parameter_recommendations.by_content_area`: Stratified by MATHEMATICS, READING, etc.
  - `family_selection_summary`: Win rates and mean ΔAIC per family

- `analysis_manifest.md` - Human-readable markdown with:
  - Parameter tables by year span and content area
  - R code examples for creating t-copulas with recommended parameters
  - Usage guide for TIMSS-like applications

**Per-Family Summaries** (in each condition's contour_plots directory):
- `{family}_summary.json` - Fit metrics, parameters, tail dependence, SGPc comparison
- `{family}_summary.md` - Human-readable summary with recommendations

### Usage Example

```r
# Load manifest in R
library(jsonlite)
manifest <- fromJSON("results/dataset_all/analysis_manifest.json")

# Get parameters for 4-year span (like TIMSS Grade 4 → Grade 8)
params <- manifest$parameter_recommendations$by_year_span$year_span_4
rho <- params$rho$median    # ~0.70
df <- params$df$median      # ~8

# Create t-copula
library(copula)
my_copula <- tCopula(param = rho, df = df)
```

---

## Key Findings

### Relative Fit (AIC/BIC)
**Winner:** t-copula
- Selected in ~95% of conditions
- Strong AIC advantage over other families (ΔAIC ≈ 180 vs. Gaussian)
- Symmetric tail dependence appropriate for educational data

**Second Place:** Gaussian copula
- No tail dependence
- ΔAIC typically 100-200 behind t-copula

**Worst:** Comonotonic (TAMP assumption)
- Never selected by AIC
- Dramatically worse fit (ΔAIC > 1000)
- Perfect positive dependence assumption too restrictive

### Absolute Fit (Goodness-of-Fit)
With large sample size (n ≈ 28,567):
- **All parametric families** fail GoF tests (p < 0.05) due to high statistical power
- **t-copula closest** to empirical fit: CvM ≈ 0.84
- **Comonotonic dramatically worse**: CvM ≈ 50 (60× worse than t-copula)

**Interpretation:**
- Statistical rejection ≠ practical inadequacy
- Large n → power to detect minor deviations
- Relative CvM statistics inform practical model choice
- t-copula provides best parametric approximation despite statistical rejection

---

## Critical Methodological Notes

### Why Empirical Ranks in Step 1?

**Problem:** I-spline with insufficient knots (4-9) causes:
- Non-uniform pseudo-observations (K-S test p < 0.001)
- Tail dependence distortion
- Wrong copula selection (Frank wins instead of t)

**Solution:** Use empirical ranks in Step 1:
```r
U <- rank(scores_prior) / (n + 1)
V <- rank(scores_current) / (n + 1)
```

**Benefits:**
- ✓ Truly uniform (by construction)
- ✓ Preserves tail dependence
- ✓ Correct copula selection (t-copula)
- ✓ No smoothing artifacts

**Trade-off:** No invertibility, but not needed for family selection. By Sklar's theorem, copulas are invariant to monotone marginal transformations, so the copula dependence structure estimated here is valid regardless of which marginal transformation is later used for applications.

For transformation details and implementation methods (including invertibility for score-scale reporting), see **STEP_3_Application_Implementation**. For complete two-stage approach justification, see top-level `TWO_STAGE_TRANSFORMATION_METHODOLOGY.md`.

---

## How to Run

### Quick Start: Dataset 4 Pandemic Analysis
```r
# Recommended: Use convenience script (runs everything)
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")
source("run_dataset4_analysis.R")
```

### Standalone Execution (Single Dataset)
```r
# From Copula_Sensitivity_Analyses/ directory
setwd("STEP_1_Family_Selection")
source("phase1_family_selection.R")
source("phase1_analysis.R")

# For dataset_4, also run pandemic analysis:
source("pandemic_analysis_dataset4.R")
```

### Via Master Script (All Datasets)
```r
# From Copula_Sensitivity_Analyses/ directory
STEPS_TO_RUN <- 1
source("master_analysis.R")

# Then run pandemic analysis if dataset_4 was included:
source("STEP_1_Family_Selection/pandemic_analysis_dataset4.R")
```

### Dataset-Specific Execution
```r
# Run only Dataset 4 (pandemic analysis)
DATASETS_TO_RUN <- "dataset_4"
STEPS_TO_RUN <- 1
source("master_analysis.R")
```

---

## Validation

After running, verify:

1. **t-copula wins**
   ```r
   load("results/phase1_decision.RData")
   print(phase2_families)  # Should be "t"
   ```

2. **Frank does NOT dominate**
   ```r
   results <- fread("results/phase1_copula_family_comparison.csv")
   winners <- results[, .SD[which.min(aic)], by = condition_id]
   table(winners$family)  # Frank should be rare
   ```

3. **Figures look reasonable**
   - `phase1_selection_frequency.pdf` - t-copula dominates
   - `phase1_tail_dependence.pdf` - Shows tail dependence by family
   - `phase1_delta_aic_distributions.pdf` - t-copula consistently best

---

## Dependencies

**Data:**
- Colorado longitudinal assessment data (2003-2013, Grades 3-10)
- Trimmed dataset: `Data/Copula_Sensitivity_Test_Data_CO.Rdata`
- Auto-loaded by `master_analysis.R` as `STATE_DATA_LONG`

**Functions:**
- `../functions/longitudinal_pairs.R` - Extract paired scores
- `../functions/ispline_ecdf.R` - Framework setup (not used for transformation)
- `../functions/copula_bootstrap.R` - Copula fitting with empirical ranks
- `../functions/sgpc_engine.R` - SGPc calculation engine (copula-based growth percentiles)

**Packages:**
- `data.table` - Data manipulation
- `copula` - Copula fitting
- `splines2` - Basis functions (for framework setup)

---

## Troubleshooting

### Issue: Frank copula wins
**Cause:** Using I-spline transformation instead of empirical ranks

**Fix:** Check line ~150 in `phase1_family_selection.R`:
```r
copula_fits <- fit_copula_from_pairs(
  ...,
  use_empirical_ranks = TRUE  # Must be TRUE!
)
```

### Issue: Error loading Colorado data
**Cause:** Data file path incorrect

**Fix:** Ensure data file exists:
```bash
ls Data/Copula_Sensitivity_Test_Data_CO.Rdata
```

Data is auto-loaded by `master_analysis.R` - no manual loading needed.

### Issue: Very slow execution
**Cause:** 30+ conditions × 5 families = 150+ copula fits

**Solution:** 
- Use EC2 for faster execution
- Or reduce conditions for testing

---

## Connection to Paper

### Methodology Section Text

> "To identify the most appropriate copula family for longitudinal educational assessment data, we conducted a comprehensive family selection study using Grade 3-10 Colorado assessment data (2003-2013). We tested five copula families (Gaussian, t, Clayton, Gumbel, Frank) across 30 diverse conditions varying by grade span (1-4 years), content area (Mathematics, Reading, Writing), and cohort.
>
> For each condition, we transformed scores to pseudo-observations using empirical ranks—rank(x)/(n+1)—rather than smoothed marginals, to ensure uniform marginals and preserve tail dependence structure (see Section X for smoothing validation). We fit each copula family via maximum likelihood and compared using AIC.
>
> Results (Table X) showed t-copula selected in 95% of conditions, with mean ΔAIC = 180 over second-place Gaussian. This consistent dominance across diverse conditions validates t-copula as the appropriate model for these data, with symmetric tail dependence capturing the tendency for extreme students to remain extreme over time."

### Tables for Paper

**Table 1:** Selection frequency by family
```r
results <- fread("results/phase1_copula_family_comparison.csv")
selection_freq <- results[, .SD[which.min(aic)], by = condition_id][, .N, by = family]
```

**Table 2:** Mean AIC by family
```r
mean_aic <- results[, .(mean_aic = mean(aic)), by = family]
```

---

## Files in This Directory

- `phase1_family_selection.R` - Main analysis script (all datasets)
- `phase1_family_selection_parallel.R` - Parallel version for EC2/multi-core
- `phase1_analysis.R` - Results analysis and decision
- `pandemic_analysis_dataset4.R` - **NEW:** Pandemic impact analysis for Dataset 4
- `debug_frank_dominance.R` - Diagnostic script (validates bug fix)
- `diagnostic_copula_fitting.R` - Additional diagnostics
- `TWO_STAGE_TRANSFORMATION_METHODOLOGY.md` - Methodological justification
- `TWO_STAGE_IMPLEMENTATION_SUMMARY.txt` - Implementation details
- `BUG_FIX_SUMMARY.txt` - Critical bug fixes documented
- `README.md` - This file
- `results/` - All output files
  - `dataset_1/` - Dataset 1 results
  - `dataset_2/` - Dataset 2 results
  - `dataset_3/` - Dataset 3 results
  - `dataset_4/` - **NEW:** Dataset 4 results (includes pandemic_analysis/)
  - `dataset_all/` - Combined multi-dataset results

---

## Next Steps

### After Step 1 Completes

1. **Review Dataset 4 Pandemic Analysis** (if applicable):
   - Check `results/dataset_4/pandemic_analysis/pandemic_summary_report.txt`
   - View parameter change visualizations
   - Assess whether COVID disrupted dependency structure

2. **Proceed to STEP 2**:
   - **STEP_2_Copula_Sensitivity_Analyses/** - Test copula robustness across diverse conditions (grade span, sample size, content area, cohort) to validate the Sklar-theoretic extension of TAMP. This is the **core contribution** of the paper.

3. **Paper Integration**:
   - Dataset 1-3: Standard copula sensitivity analysis
   - Dataset 4: Natural experiment section on pandemic impact
   - Combined results: Multi-dataset parameter recommendations

