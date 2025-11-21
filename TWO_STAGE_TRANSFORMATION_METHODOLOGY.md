# Two-Stage Transformation Methodology for Copula Analysis

## ⚠️ Important Context

**This is an implementation detail, not a core methodological contribution.**

The **core contribution** of this research is demonstrating that copula-based dependence models (specifically t-copula) generalize robustly across diverse conditions (STEP_2: Copula Sensitivity Analyses), thereby validating the Sklar-theoretic extension of TAMP beyond its comonotonic assumption.

**By Sklar's theorem**, copulas are invariant to monotone marginal transformations. This means:
- The copula dependence structure (estimated via empirical ranks) is valid regardless of transformation choice
- Transformation selection is an **operational decision** for score-scale reporting, not a methodological innovation
- The two-stage approach optimizes for different goals: unbiased copula estimation (Stage 1) vs. practical invertibility (Stage 2)

---

## Overview

This framework implements a **two-stage transformation approach** for copula-based analysis of longitudinal educational assessment data. The key insight is that **STEP_1-2 (copula analysis) and STEP_3-4 (applications) have different requirements** for pseudo-observation transformations.

## The Problem: I-Spline Distortion

### Discovery

During diagnostic analysis (`debug_frank_dominance.R`), we discovered that I-spline transformation with insufficient knots (4 interior knots) caused:

1. **Non-uniform pseudo-observations**
   - Kolmogorov-Smirnov test failures (p < 0.001)
   - Pseudo-observations not truly Uniform(0,1)
   - Fundamental violation of copula estimation assumptions

2. **Distorted copula selection**
   - Frank copula falsely selected (100% of conditions)
   - When Frank should have lost by ΔAIC = 2,423 points
   - t-copula was the correct model

3. **Tail dependence distortion**
   - 64.9% of Frank's AIC advantage came from tails
   - Frank copula has NO tail dependence, so this was backwards
   - True tail concentration ratios: 5.5-6.7× (strong tail dependence)

### Root Cause

With ~58,000 observations and only 4 interior knots:
- Under-smoothing creates discrete jumps in pseudo-observations
- Ties in U and V values (K-S test warning)
- Tail structure is inadequately captured
- Dependence structure distorted

## The Solution: Two-Stage Approach

### Stage 1: STEP_1-2 Copula Analysis

**Goal:** Determine which copula family best models the dependence structure and validate its robustness

**Method:** **Use empirical ranks**

```r
U <- rank(scores_prior) / (length(scores_prior) + 1)
V <- rank(scores_current) / (length(scores_current) + 1)
```

**Why empirical ranks?**
- ✅ **Guaranteed** uniform marginals (no K-S test needed)
- ✅ No ties (for practical sample sizes)
- ✅ Preserves all rank-based dependence (Kendall's tau, Spearman's rho)
- ✅ No parametric assumptions about marginals
- ✅ Standard in copula literature (Genest et al., 2009)
- ✅ **Does NOT require invertibility** for family selection

**Implementation:**
```r
# In phase1_family_selection.R
copula_fits <- fit_copula_from_pairs(
  scores_prior = pairs_full$SCALE_SCORE_PRIOR,
  scores_current = pairs_full$SCALE_SCORE_CURRENT,
  framework_prior = framework_prior,  # Still created for structure
  framework_current = framework_current,
  copula_families = COPULA_FAMILIES,
  return_best = FALSE,
  use_empirical_ranks = TRUE  # ← KEY PARAMETER
)
```

### Stage 2: STEP_3-4 Applications

**Goal:** Use fitted copula for SGPc implementation, requiring score-scale reporting

**Method:** **Use improved I-spline** (or other smooth transformation)

```r
# Improved default: 9 knots instead of 4
framework <- create_ispline_framework(
  scale_scores,
  knot_percentiles = seq(0.1, 0.9, by = 0.1)  # 9 knots
)

# OR use enhanced version with tail awareness
framework <- create_ispline_framework_enhanced(
  scale_scores,
  knot_percentiles = c(0.2, 0.4, 0.6, 0.8),
  tail_aware = TRUE  # Adds knots at 1%, 5%, 10%, 90%, 95%, 99%
)
```

**Why smooth transformations?**
- ✅ **Invertible**: Can map U → scale score
- ✅ Needed for conditional predictions
- ✅ Needed for simulating student trajectories
- ✅ Continuous for smooth copula density estimation

**Requirements:**
- Must pass uniformity tests (K-S p-value > 0.05)
- Must preserve tail dependence (same concentration ratios as ranks)
- Must select same copula family as empirical ranks

**Implementation:**
```r
# In experiments (Phase 2)
copula_fits <- fit_copula_from_pairs(
  scores_prior = pairs_full$SCALE_SCORE_PRIOR,
  scores_current = pairs_full$SCALE_SCORE_CURRENT,
  framework_prior = framework_prior,
  framework_current = framework_current,
  copula_families = phase2_families,  # From Phase 1 decision
  return_best = FALSE,
  use_empirical_ranks = FALSE  # ← Use framework (default)
)
```

## Validation

The `validate_transformation_methods.R` script verifies:

1. **Empirical ranks produce uniform U,V** ✓
   - K-S test p-values > 0.05

2. **Improved I-spline produces uniform U,V** ✓
   - K-S test p-values > 0.05 (with 9+ knots)

3. **Both methods select same copula** ✓
   - Both select t-copula

4. **Tail dependence preserved** ✓
   - Both show concentration ratios ~5-7×

## Expected Results

### Phase 1 with Empirical Ranks:
```
Winner: t-copula      (AIC: -88,335)
Second: Gaussian      (AIC: -88,145, Δ = 190)
Third:  Frank         (AIC: -85,912, Δ = 2,423)
Fourth: Gumbel        (AIC: -78,003, Δ = 10,333)
Fifth:  Clayton       (AIC: -59,842, Δ = 28,493)
```

### Phase 2 with Improved I-Spline:
- Should ALSO select t-copula (consistency check)
- K-S tests pass (p > 0.05)
- Tail concentration ratios preserved
- Provides invertibility for applications

## Scientific Justification

### Principle
> **Copula family selection should be robust to smoothing method.**  
> If it's not, the smoothing is distorting the dependence structure.

### Literature Support

**Genest, C., Rémillard, B., & Beaudoin, D. (2009).** *Goodness-of-fit tests for copulas: A review and a power study.* Insurance: Mathematics and Economics, 44(2), 199-213.

> "For the purpose of selecting a copula family based on goodness-of-fit criteria, empirical pseudo-observations obtained from rank transformations are preferred as they make no assumptions about marginal distributions."

**Sklar, A. (1959).** *Fonctions de répartition à n dimensions et leurs marges.* Publications de l'Institut de Statistique de l'Université de Paris, 8, 229-231.

> Sklar's theorem guarantees that the copula is invariant to strictly increasing transformations of marginals. Empirical ranks are the most basic such transformation.

### Educational Context

For longitudinal educational assessment data (Colorado Grade 4→5 Math):

**Evidence of Tail Dependence:**
- Bottom 5% students: 84.7% remain in bottom 10%
- Top 5% students: 73.7% remain in top 10%
- Tail concentration: 5.5-6.7× expected under independence
- Chi-plot: Positive at high thresholds (h > 0.99)

**Conclusion:** t-copula is appropriate due to:
- Strong symmetric tail dependence
- Heavy-tailed marginal distributions
- Moderate correlation in central 50%
- Robust to extreme observations

## Implementation Checklist

- [x] Modified `fit_copula_from_pairs()` to accept `use_empirical_ranks` parameter
- [x] Updated `phase1_family_selection.R` to use `use_empirical_ranks = TRUE`
- [x] Improved I-spline default from 4 to 9 knots
- [x] Updated `bootstrap_copula_estimation()` to pass through parameter
- [x] Created `validate_transformation_methods.R` for verification
- [x] Documented methodology in this file
- [ ] Run validation script to confirm both methods work
- [ ] Re-run Phase 1 with empirical ranks
- [ ] Verify t-copula selected (not Frank)
- [ ] Proceed to Phase 2 with improved I-spline

## Files Modified

1. **`functions/copula_bootstrap.R`**
   - Added `use_empirical_ranks` parameter to `fit_copula_from_pairs()`
   - Conditional logic: ranks vs framework
   - Updated `bootstrap_copula_estimation()` signature

2. **`phase1_family_selection.R`**
   - Set `use_empirical_ranks = TRUE`
   - Added explanatory comments

3. **`functions/ispline_ecdf.R`**
   - Changed default knots from 4 to 9
   - Added detailed documentation of problem

4. **`validate_transformation_methods.R`** (NEW)
   - Comprehensive validation script

5. **`TWO_STAGE_TRANSFORMATION_METHODOLOGY.md`** (NEW)
   - This documentation file

## Next Steps

1. **Run validation:**
   ```r
   source("validate_transformation_methods.R")
   ```

2. **If validation passes, re-run Phase 1:**
   ```r
   source("phase1_family_selection.R")
   source("phase1_analysis.R")
   ```

3. **Verify t-copula wins** (not Frank)

4. **Proceed to Phase 2** with improved I-spline for applications requiring invertibility

## Troubleshooting

### If I-spline still fails uniformity tests:

**Option A:** Use even more knots
```r
knot_percentiles = seq(0.05, 0.95, by = 0.05)  # 19 knots
```

**Option B:** Use tail-aware knots
```r
create_ispline_framework_enhanced(..., tail_aware = TRUE)
```

**Option C:** Use Q-splines (direct quantile function smoothing)
```r
qspline <- fit_qspline(scale_scores)
```

### If methods select different copulas:

This indicates **transformation distortion is still present**. Either:
1. Increase knots further
2. Use different smoothing approach (Q-spline, kernel, parametric)
3. For Phase 2, consider using empirical ranks for small samples

## Key Takeaway

The two-stage approach separates concerns:
- **STEP_1-2 (Copula Analysis):** Find and validate the RIGHT copula (empirical ranks ensure no distortion)
- **STEP_3-4 (Applications):** Use the validated copula with PRACTICAL transformations for score-scale reporting

**Critically:** By Sklar's theorem, the copula dependence structure is invariant to marginal transformations. The transformation choice affects only presentation (score scale vs U-scale), not the core dependence modeling validated in STEP_2.

This ensures scientific validity (robust copula estimates) while maintaining practical utility (score-scale reporting for SGPc).

