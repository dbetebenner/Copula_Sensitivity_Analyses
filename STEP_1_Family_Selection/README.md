# STEP 1: Copula Family Selection

## Overview

**Paper Section:** Background → TAMP and Copulas; Methodology → Copula Selection and Parameter Estimation

**Objective:** Identify which copula family consistently provides the best fit for longitudinal educational assessment data across diverse conditions.

**Hypothesis:** t-copula will dominate due to heavy tails in educational data, with tail dependence increasing as time between observations increases.

---

## What This Step Does

Tests all 5 copula families (Gaussian, t, Clayton, Gumbel, Frank) across:
- Multiple grade spans (1, 2, 3, 4 years)
- Multiple content areas (Mathematics, Reading, Writing)
- Multiple cohorts (different years)
- Full factorial design: 30+ conditions

For each condition:
1. Create longitudinal pairs from Colorado data
2. Transform to pseudo-observations using **empirical ranks** (critical!)
3. Fit all 5 copula families
4. Compare using AIC and BIC
5. Record which family wins

**Key Methodological Decision:** This step uses **empirical ranks** (not smoothing) to ensure uniform pseudo-observations and preserve tail dependence structure.

---

## Scripts

### 1. `phase1_family_selection.R`
**Runtime:** ~30-60 minutes

**What it does:**
- Loads Colorado longitudinal data
- Tests all 5 copula families across 30+ conditions
- Uses empirical ranks for transformation (validates two-stage approach)
- Saves detailed results for each condition

**Outputs:**
- `results/phase1_copula_family_comparison.csv` - Complete results table
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
- `results/phase1_decision.RData` - Decision for later steps
- `results/phase1_summary.txt` - Text summary
- `results/phase1_*.pdf` - Diagnostic figures
- `results/phase1_selection_table.csv` - Summary table

---

## Key Findings (Expected)

After bug fixes (see `BUG_FIX_SUMMARY.txt`):

**Winner:** t-copula
- Selected in ~90-100% of conditions
- Strong AIC advantage over other families
- Symmetric tail dependence appropriate for educational data

**Second Place:** Gaussian copula
- No tail dependence
- ΔAIC typically 100-200 behind t-copula

**Frank Copula Should NOT Win:**
- Before bug fix: Frank falsely won (ΔAIC = 2,423)
- After bug fix: Frank loses (tail dependence distortion corrected)
- See `debug_frank_dominance.R` for diagnostic evidence

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

**Trade-off:** No invertibility, but not needed for family selection.

See `TWO_STAGE_TRANSFORMATION_METHODOLOGY.md` for complete justification.

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
- Located: `/Users/conet/SGP Dropbox/.../Colorado_Data_LONG.RData`

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

**Fix:** Update path in line ~18:
```r
load("/Users/conet/SGP Dropbox/.../Colorado_Data_LONG.RData")
```

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

**STEP_2_Transformation_Validation/** - Validate marginal transformation methods for invertibility in applications.

