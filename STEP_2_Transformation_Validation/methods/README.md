# Step 2 Transformation Methods

This directory contains additional transformation methods that extend the core functionality in `../functions/ispline_ecdf.R`.

## Files

### `bernstein_cdf.R`
**Bernstein CDF (Empirical-Beta) Smoother**

Fits smooth, monotone CDF using Bernstein polynomials with constrained optimization.

**Key Functions**:
- `fit_bernstein_cdf(scores, degree = NULL, tune_by_cv = TRUE)` - Main fitting function
- `tune_bernstein_degree(scores_norm, n)` - Auto-tune polynomial degree by CV
- `diagnose_bernstein_fit(scores, bernstein_fit)` - Quality diagnostics

**Features**:
- Shape-safe: Monotonicity guaranteed by construction
- Boundary exact: Natural [0,1] normalization
- Auto-tuned: Degree selected by cross-validation minimizing PIT uniformity
- Fast: Pre-computed lookup tables for evaluation

**When to use**:
- Need guaranteed monotonicity
- Want excellent boundary behavior
- Scores have complex tail shapes
- Alternative to I-splines when more flexibility needed

**Example**:
```r
source("methods/bernstein_cdf.R")

fit <- fit_bernstein_cdf(scores, degree = NULL, tune_by_cv = TRUE)
U <- fit$F(scores)          # Forward: scores → [0,1]
X <- fit$F_inv(U)           # Inverse: [0,1] → scores

# Diagnostics
diag <- diagnose_bernstein_fit(scores, fit)
print(diag$mae)             # Mean absolute error vs empirical CDF
print(diag$is_monotone)     # Should be TRUE
```

---

### `csem_aware_smoother.R`
**CSEM-Aware Smoother for Discrete/Heaped Scores**

Treats discrete scores as latent intervals [x ± CSEM] to handle heaping, clipping, and rounding effects.

**Key Functions**:
- `fit_csem_aware(scores, csem = 1.0, method = "pool_adjacent")` - Main fitting function
- `needs_csem_smoothing(scores)` - Detect if data has severe discretization
- `estimate_csem(scores, method = "mad")` - Estimate CSEM from data
- `compare_csem_smoothing(scores, csem = NULL)` - Compare to standard smoothing

**Features**:
- Interval-aware: Treats observations as [x - csem, x + csem]
- Auto-detection: Identifies heaping, boundary effects, large gaps
- Isotonic: Guaranteed monotonicity via PAV or Hyman spline
- Diagnostic: Built-in comparison to standard methods

**When to use**:
- Scores have large gaps (e.g., 10-point increments)
- Ceiling/floor effects (>5% at boundaries)
- Visible heaping at round numbers
- Standard methods fail tail calibration

**When NOT to use**:
- Continuous or near-continuous scores
- Mild discretization (<30% ties)
- When computational cost is concern
- Standard methods already pass diagnostics

**Example**:
```r
source("methods/csem_aware_smoother.R")

# Check if needed
diagnosis <- needs_csem_smoothing(scores)
print(diagnosis$needs_csem)              # TRUE/FALSE
print(diagnosis$diagnostics$flags)       # What triggered the flag

# Fit if needed
if (diagnosis$needs_csem) {
  csem <- estimate_csem(scores)
  fit <- fit_csem_aware(scores, csem = csem)
  
  # Compare to standard
  comparison <- compare_csem_smoothing(scores, csem)
  print(comparison$recommendation)       # "Use CSEM-aware" or "Use standard"
}
```

---

## Integration with Experiment 5

### Bernstein CDF
Already integrated:
- Added to `TRANSFORMATION_METHODS` list in `exp_5_transformation_validation.R`
- Transformation code in main loop (line ~312)
- Results included in CSV summary

### CSEM-Aware Smoother
**Not yet integrated** (optional):
- Use as diagnostic/fallback for problematic datasets
- Can be added to Experiment 5 conditionally:

```r
# In exp_5_transformation_validation.R, after loading data:
source("methods/csem_aware_smoother.R")

if (needs_csem_smoothing(pairs_full$SCALE_SCORE_PRIOR)$needs_csem) {
  # Add CSEM-aware variant to methods list
  TRANSFORMATION_METHODS <- c(TRANSFORMATION_METHODS, list(
    list(name = "csem_aware",
         label = "CSEM-Aware Isotonic",
         type = "csem",
         params = list(csem = NULL))  # Will be auto-estimated
  ))
}
```

---

## Testing

Run the test script to verify all methods work correctly:

```r
source("STEP_2_Transformation_Validation/test_enhancements.R")
```

This will test:
1. Bernstein CDF fitting and inversion
2. Tail calibration diagnostic
3. Bootstrap stability diagnostic
4. CSEM-aware smoother

Expected output: "ALL TESTS PASSED! ✓✓✓"

---

## Dependencies

Both methods use existing packages:
- `stats`: Core R functions (ecdf, isoreg, splinefun)
- `splines2`: I-spline basis (via existing infrastructure, for Bernstein)
- No new dependencies required

---

## Performance Notes

### Bernstein CDF
- **Fitting time**: 5-15 seconds (with CV tuning)
- **Evaluation speed**: ~50k-100k/sec (lookup table)
- **Memory**: ~0.5-2 MB per fit

### CSEM-Aware
- **Fitting time**: 2-5 seconds
- **Evaluation speed**: ~10k-50k/sec (approxfun)
- **Memory**: ~0.1-0.5 MB per fit

Both are suitable for operational use (meet Experiment 6 criteria).

---

## Troubleshooting

### Bernstein CDF

**Problem**: Degree auto-tuning takes too long  
**Solution**: Set `degree` manually or reduce `n_eval`

**Problem**: Poor boundary behavior (F(min) not near 0)  
**Solution**: Check for outliers; boundaries are set to min/max of data

**Problem**: Non-monotone after fitting  
**Solution**: Should not happen; check `diagnose_bernstein_fit()$is_monotone`

### CSEM-Aware

**Problem**: `needs_csem_smoothing()` flags data unnecessarily  
**Solution**: Adjust thresholds in function (currently: 30% discretization, 5% boundary)

**Problem**: CSEM estimate seems wrong  
**Solution**: Manually specify `csem` based on domain knowledge (e.g., measurement error from test documentation)

**Problem**: Worse than standard smoothing  
**Solution**: Check `compare_csem_smoothing()$recommendation`; may not be needed

---

## References

### Bernstein Polynomials
- Lorentz, G. G. (1986). *Bernstein Polynomials*. Chelsea Publishing.
- Shape-preserving approximation theory

### CSEM (Conditional Standard Error of Measurement)
- Psychometric theory: measurement error varies by score level
- Classical Test Theory (CTT) and Item Response Theory (IRT) frameworks

### Isotonic Regression
- Barlow, R. E., et al. (1972). *Statistical Inference Under Order Restrictions*.
- Pool Adjacent Violators (PAV) algorithm

---

## Contributing

To add a new transformation method:

1. Create `method_name.R` in this directory
2. Implement functions following the pattern:
   ```r
   fit_method_name <- function(scores, ...) {
     # Fit logic here
     return(list(
       method = "Method Name",
       F = forward_function,        # x → [0,1]
       F_inv = inverse_function,    # [0,1] → x
       # ... other metadata
     ))
   }
   ```
3. Add to `TRANSFORMATION_METHODS` in `exp_5_transformation_validation.R`
4. Add transformation code in main loop
5. Update documentation
6. Run `test_enhancements.R` to verify

---

**Last updated**: 2025-10-11
