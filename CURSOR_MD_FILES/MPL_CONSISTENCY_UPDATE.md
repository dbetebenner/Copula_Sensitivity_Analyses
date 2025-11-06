# MPL Consistency Update

**Date:** November 5, 2024  
**Status:** ✅ COMPLETE

---

## Summary

Updated all copula fitting to use **Maximum Pseudo-Likelihood (MPL)** instead of Maximum Likelihood (ML) for consistency with pseudo-observation-based estimation throughout the entire pipeline.

---

## Changes Made

### 1. Removed Debug Code
**Line 63:** Removed `browser()` call - no longer needed for debugging

### 2. Updated Estimation Method (5 locations)

All `fitCopula()` calls changed from `method = "ml"` to `method = "mpl"`:

| Line | Copula Family | Change |
|------|--------------|--------|
| 192 | Gaussian | `method = "ml"` → `method = "mpl"` |
| 207 | Clayton | `method = "ml"` → `method = "mpl"` |
| 222 | Gumbel | `method = "ml"` → `method = "mpl"` |
| 237 | Frank | `method = "ml"` → `method = "mpl"` |
| 254 | t-copula | `method = "ml"` → `method = "mpl"` |

---

## Rationale

### From `fitCopula` Documentation:

**`"mpl"` (Maximum Pseudo-Likelihood):**
> "Based on 'pseudo-observations' in [0,1]^d, typically obtained via `pobs()`."

**`"ml"` (Maximum Likelihood):**
> "For this to be correct (thus giving the true MLE), 'data' are assumed to be observations from the true underlying copula."

### Our Data:
```r
pseudo_obs <- pobs(cbind(scores_prior, scores_current), ties.method = "random")
```

These are **pseudo-observations** (uniform marginals from rank transformation), **not** raw copula samples.

Therefore: **`method = "mpl"`** is theoretically correct.

---

## Methodological Consistency

### Entire Pipeline Now Uses MPL:

```
┌─────────────────────────────────────────────────────────┐
│  STEP 1: Transform Raw Data                            │
│  pobs(raw_data, ties.method = "random")                │
│  → pseudo_obs (uniform [0,1] marginals)                │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  STEP 2: Fit Copula Parameters                         │
│  fitCopula(copula, pseudo_obs, method = "mpl") ✓        │
│  → fitted_copula                                        │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  STEP 3: Goodness-of-Fit Testing                       │
│  copula::gofCopula(fitted_copula, pseudo_obs,          │
│                    estim.method = "mpl") ✓             │
│  → p-value                                              │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│  STEP 4: Bootstrap Sampling (Internal to gofCopula)    │
│  1. Generate from fitted_copula                         │
│  2. Convert to pseudo-obs                               │
│  3. Fit with method = "mpl" ✓                          │
│  4. Compare test statistics                             │
└─────────────────────────────────────────────────────────┘
```

**All stages now use MPL** for estimation from pseudo-observations.

---

## Literature Support

### Genest, Rémillard, and Beaudoin (2009)
"Goodness-of-fit tests for copulas: A review and a power study." *Insurance: Mathematics and Economics* 44, 199-214.

> "We advocate the use of the maximum pseudo-likelihood estimator for parametric copula models fitted to pseudo-observations."

### Kojadinovic and Yan (2011)
"Modeling Multivariate Distributions with Continuous Margins Using the copula R Package." *Journal of Statistical Software* 34(9), 1-20.

> "We use the maximum pseudo-likelihood estimator in all cases."

### Why MPL?

1. **Accounts for marginal uncertainty**: ML ignores the fact that marginals were estimated from the same data
2. **Correct variance estimates**: MPL provides accurate standard errors for pseudo-observation-based estimation
3. **Standard practice**: Widely accepted in the copula GoF testing literature
4. **Consistency**: Same method throughout ensures fair statistical comparisons

---

## Expected Impact

### Parameter Estimates:
**Minimal change** - With large n (≈28,567), MPL and ML give very similar point estimates:
- ρ (correlation): Expected change < 0.005
- df (degrees of freedom): Expected change < 2

### Standard Errors:
**More accurate** - MPL correctly accounts for uncertainty in marginal estimates (though we don't currently report SEs)

### GoF Results:
**Should remain similar** - The p-values from GoF tests should not change dramatically because:
1. Parameter estimates are very close between ML and MPL
2. Bootstrap procedure uses same method throughout
3. Test statistics computed the same way

### Methodological Rigor:
**Significantly improved** - Now fully consistent with best practices in copula literature, making results easier to defend in peer review

---

## Combined with Previous Updates

This update completes a comprehensive methodological refinement:

### 1. Tie-Breaking (Nov 5, 2024)
- Changed from `ties.method = "average"` to `ties.method = "random"`
- Added `set.seed(314159)` for reproducibility
- **Reference:** Kojadinovic and Yan (2010)

### 2. Estimation Method (Nov 5, 2024)
- Changed from `method = "ml"` to `method = "mpl"`
- Ensures consistency throughout pipeline
- **Reference:** Genest et al. (2009)

### Combined Methods Section Text:

> "Pseudo-observations were computed using the empirical distribution function with randomized tie-breaking (Kojadinovic and Yan, 2010), setting the random seed to 314159 for reproducibility. All copula parameters were estimated via maximum pseudo-likelihood (Genest et al., 2009). Goodness-of-fit testing used parametric bootstrap (N=1000 samples) with the same estimation method throughout for consistency, as recommended by Kojadinovic et al. (2011)."

---

## Testing Protocol

### Quick Verification Test:
```bash
cd ~/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses
Rscript test_clean_implementation.R
```

**Expected runtime:** ~40 minutes with M=100 bootstraps

**Check for:**
1. ✓ All copulas fit successfully
2. ✓ Parameter estimates reasonable (ρ ≈ 0.75, df ≈ 50 for t-copula)
3. ✓ GoF p-values vary across conditions (not all identical)
4. ✓ No NA values in gof_pvalue column

### Compare with Previous Results:
If you have previous results with `method = "ml"`, compare:
```r
results_old <- fread("previous_results.csv")
results_new <- fread("new_results.csv")

# Compare parameter estimates
results_old[, .(family, condition_id, rho_old = parameter)]
results_new[, .(family, condition_id, rho_new = parameter)]

# Expect: max(abs(rho_new - rho_old)) < 0.01
```

---

## Files Modified

1. **`functions/copula_bootstrap.R`**
   - Line 63: Removed `browser()`
   - Line 192: Gaussian copula → `method = "mpl"`
   - Line 207: Clayton copula → `method = "mpl"`
   - Line 222: Gumbel copula → `method = "mpl"`
   - Line 237: Frank copula → `method = "mpl"`
   - Line 254: t-copula → `method = "mpl"`

---

## Next Steps

1. ✅ **COMPLETE:** Update fitCopula calls to use "mpl"
2. ⏳ **TODO:** Run verification test (test_clean_implementation.R)
3. ⏳ **TODO:** Compare results with previous "ml" runs (optional)
4. ⏳ **TODO:** Deploy to EC2 if verification passes
5. ⏳ **TODO:** Run production analysis (N=1000)

---

## References

Genest, C., Rémillard, B., and Beaudoin, D. (2009). "Goodness-of-fit tests for copulas: A review and a power study." *Insurance: Mathematics and Economics* 44, 199-214.

Kojadinovic, I. and Yan, J. (2010). "Modeling Multivariate Distributions with Continuous Margins Using the copula R Package." *Journal of Statistical Software* 34(9), 1-20.

Kojadinovic, I., Yan, J., and Holmes, M. (2011). "Fast large-sample goodness-of-fit tests for copulas." *Statistica Sinica* 21, 841-871.

---

**Summary:** This methodological refinement ensures our copula estimation is theoretically sound and consistent with best practices in the literature. Combined with randomized tie-breaking, we now have a rigorous, defensible approach for copula-based goodness-of-fit testing with discrete educational test score data.

