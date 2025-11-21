# STEP 1: Copula Family Selection

## Overview

**Paper Section:** Background → TAMP and Copulas; Methodology → Copula Selection and Parameter Estimation

**Objective:** Identify which copula family consistently provides the best fit for longitudinal educational assessment data using both relative (AIC/BIC) and absolute (goodness-of-fit) measures.

**Hypothesis:** t-copula will dominate due to heavy tails, with tail dependence increasing as time between observations increases. With large sample sizes, all parametric families may show statistically significant deviations, but t-copula will be closest to empirical fit.

---

## What This Step Does

Tests 6 copula families (5 parametric: Gaussian, t, Clayton, Gumbel, Frank + comonotonic) across:
- Multiple grade spans (1, 2, 3, 4 years)
- Multiple content areas (Mathematics, Reading, Writing)
- Multiple cohorts (different years)
- Grade range: G3→G10 (includes early elementary G3→G4 and middle school transition G7→G8)
- Full factorial design: 42 conditions

For each condition:
1. Create longitudinal pairs from Colorado data  
2. Transform to pseudo-observations using **empirical ranks via `pobs(..., ties.method="random")`**  
3. Fit all 6 copula families (5 parametric + comonotonic) using maximum pseudo-likelihood  
4. **Relative fit:** Compare using AIC and BIC  
5. **Absolute fit:** Goodness-of-fit via Cramér-von Mises test with parametric bootstrap (N=1000)  
   - Parametric families: Full bootstrap with p-values  
   - Comonotonic: Observed statistic only (no bootstrap)  
6. Record selection frequencies and GoF results

**Key Methodological Decisions:**
1. **Empirical ranks** (not smoothing) ensure uniform pseudo-observations and preserve tail dependence
2. **Randomized tie-breaking** via `pobs()` prevents discrete data issues in GoF testing
3. **Statistical vs. practical significance** distinction: Large n (28,567) → high power → statistical rejection expected, but relative differences inform practical model selection

---

## Scripts

### 1. `phase1_family_selection.R`
**Runtime:** ~45-90 minutes

**What it does:**
- Loads Colorado longitudinal data
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
- Console summary of selection frequencies

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
  - **phase1_absolute_relative_fit** - Two-panel violin plot (absolute GoF + relative ΔAIC)
  - **phase1_copula_selection_by_condition** - Proportion bars showing family selection by span/content
  - **phase1_t_copula_phase_diagram** - Degrees of freedom vs tail dependence landscape
  - **phase1_aic_by_span** - Mean AIC trends by year span (to be refined)
  - **phase1_tail_dependence** - Tail dependence patterns (to be refined)
  - **phase1_mosaic_*.{pdf,svg,png}** - Mosaic plots (to be reassessed)
- `results/dataset_all/phase1_*.csv` - Summary tables
- Note: Removed redundant plots (selection_frequency, delta_aic_distributions, aic_weights, heatmap)

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

### Standalone Execution
```r
# From Copula_Sensitivity_Analyses/ directory
setwd("STEP_1_Family_Selection")
source("phase1_family_selection.R")
source("phase1_analysis.R")
```

### Via Master Script
```r
# From Copula_Sensitivity_Analyses/ directory
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

- `phase1_family_selection.R` - Main analysis script
- `phase1_analysis.R` - Results analysis and decision
- `debug_frank_dominance.R` - Diagnostic script (validates bug fix)
- `diagnostic_copula_fitting.R` - Additional diagnostics
- `TWO_STAGE_TRANSFORMATION_METHODOLOGY.md` - Methodological justification
- `TWO_STAGE_IMPLEMENTATION_SUMMARY.txt` - Implementation details
- `BUG_FIX_SUMMARY.txt` - Critical bug fixes documented
- `README.md` - This file
- `results/` - All output files

---

## Next Step

After Step 1 completes successfully (t-copula selected), proceed to:

**STEP_2_Copula_Sensitivity_Analyses/** - Test copula robustness across diverse conditions (grade span, sample size, content area, cohort) to validate the Sklar-theoretic extension of TAMP. This is the **core contribution** of the paper.

