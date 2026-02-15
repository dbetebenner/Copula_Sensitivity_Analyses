# Pseudo-Observations Consistency Update

**Date**: January 26, 2026  
**Component**: STEP 2 SGPc Sensitivity Analysis  
**Type**: Critical Infrastructure Improvement

---

## Summary

STEP 2 has been updated to use **Phase 1's pre-computed pseudo-observations** instead of recomputing them from scale scores. This ensures perfect consistency between copula fitting (Phase 1) and SGPc computation (STEP 2).

---

## Problem

**Previous Behavior:**
- Phase 1 computed pseudo-observations (u, v) and saved them to `pseudo_observations.rds`
- Phase 1 fitted all copula families using those specific u, v values
- STEP 2 **recomputed** pseudo-observations from scale scores using:
  ```r
  u <- rank(SCALE_SCORE_PRIOR) / (n + 1)
  v <- rank(SCALE_SCORE_CURRENT) / (n + 1)
  ```

**Why This Was Wrong:**

1. **Inconsistency**: The copulas were fitted on one set of (u, v), but SGPcs were computed on a potentially different set
2. **Numerical Differences**: Even tiny floating-point differences in ranking could lead to different pseudo-observations
3. **Methodological Issue**: Using different transformations violates the core principle that copulas describe the dependence structure of the *specific* transformed data
4. **Reproducibility**: Results wouldn't perfectly match if Phase 1 used any special handling (ties, missing values, etc.)

---

## Solution

### Implementation

**Updated Files:**

1. **`phase1_data_loader.R`** (lines 33-37, 95-106):
   - Added `pseudo_observations` field to result list
   - Loads `pseudo_observations.rds` from Phase 1 condition directory
   - Returns pseudo-observations alongside copula objects

2. **`sgpc_compute_all_variants.R`** (lines 125-153):
   - **Priority 1**: Use Phase 1's `pseudo_observations` if available and dimensions match
   - **Fallback**: Compute from scale scores if Phase 1 data unavailable (backward compatibility)
   - **Warning**: Logs when fallback occurs to alert users of potential inconsistency

3. **`README.md`** (lines 292-294, 280-291):
   - Added "Pseudo-observations" subsection in methodology
   - Added troubleshooting entry for dimension mismatch warning
   - Documented why this matters

4. **`QUICKSTART.md`** (lines 32-34):
   - Updated workflow description to emphasize Phase 1 pseudo-observation loading

### Code Changes

**Before:**
```r
# Always recompute
u <- rank(pairs$SCALE_SCORE_PRIOR, na.last = "keep") / (nrow(pairs) + 1)
v <- rank(pairs$SCALE_SCORE_CURRENT, na.last = "keep") / (nrow(pairs) + 1)
```

**After:**
```r
# Use Phase 1's pseudo-observations if available
if (!is.null(phase1_results$pseudo_observations) && 
    nrow(phase1_results$pseudo_observations) == nrow(pairs)) {
  cat(" [using Phase 1 pseudo-observations]")
  pobs <- phase1_results$pseudo_observations
  u <- pobs[, 1]
  v <- pobs[, 2]
} else {
  # Fallback: compute from scale scores
  cat(" [WARNING: Phase 1 pobs dimension mismatch, recomputing]")
  u <- rank(pairs$SCALE_SCORE_PRIOR, na.last = "keep") / (nrow(pairs) + 1)
  v <- rank(pairs$SCALE_SCORE_CURRENT, na.last = "keep") / (nrow(pairs) + 1)
}
```

---

## Impact

### Benefits

1. **Perfect Consistency**: SGPcs are now computed on the **exact same** (u, v) used to fit copulas
2. **Methodological Rigor**: Honors the fundamental copula principle (Sklar's theorem)
3. **Reproducibility**: Results are deterministic and match Phase 1's reference frame
4. **Validation**: Makes it easier to trace SGPc differences back to copula specifications (not transformation differences)
5. **Efficiency**: No redundant computation (131KB pseudo-observations file vs. recomputing)

### Risks (Mitigated)

**Risk**: What if Phase 1 pseudo-observations are missing or incompatible?  
**Mitigation**: Fallback to recomputing, with clear warning log message

**Risk**: What if data filtering differs between Phase 1 and STEP 2?  
**Mitigation**: Dimension check ensures `nrow(pobs) == nrow(pairs)` before using

---

## Testing

### Validation Checklist

- [x] Code compiles without errors
- [x] Documentation updated (README, QUICKSTART)
- [x] Fallback behavior implemented (backward compatibility)
- [x] Warning messages log dimension mismatches
- [x] **CRITICAL FIX**: Condition ID naming mismatch resolved (see `CONDITION_ID_FIX.md`)
- [x] Verified pseudo-observations load correctly for test conditions
- [ ] Test on actual dataset (user to run next)

### Expected Console Output

**When Phase 1 pseudo-observations are used:**
```
Processing condition: 2017_G3_G4_MATHEMATICS... [using Phase 1 pseudo-observations] ✓
```

**When fallback occurs (rare):**
```
Processing condition: 2017_G3_G4_MATHEMATICS... [WARNING: Phase 1 pobs dimension mismatch, recomputing] ✓
```

---

## Next Steps

1. **User Re-run**: Test on a single dataset (e.g., dataset_4) to verify:
   - Phase 1 pseudo-observations load correctly
   - No dimension mismatches occur
   - Output files generate successfully

2. **Validation** (if desired):
   - Compare old vs. new SGPc outputs to quantify impact
   - Verify correlations between variants increase (tighter coupling)

3. **Full Pipeline**: Once validated, run on all 4 datasets

---

## Technical Details

### Pseudo-Observations Storage Format

**Phase 1 saves** (in `STEP_1_Family_Selection/results/{dataset}/contour_plots/{condition}/`):
```r
# pseudo_observations.rds
# Structure: matrix or data.frame, 2 columns
# Column 1: u (ranks of SCALE_SCORE_PRIOR)
# Column 2: v (ranks of SCALE_SCORE_CURRENT)
```

**STEP 2 loads** (via `load_phase1_condition()`):
```r
phase1_results <- load_phase1_condition(dataset_id, condition_id)
# Returns list with:
#   $empirical_copula
#   $best_fit_copula
#   $copula_params
#   $original_scores
#   $pseudo_observations  # NEW!
```

### Dimension Matching

**Why check dimensions?**
- Phase 1 might have processed a different subset of data
- Ensures 1:1 correspondence between pseudo-observations and current pairs
- Prevents silent misalignment errors

**What happens on mismatch?**
- Log warning message
- Fall back to recomputing from scale scores
- Continue processing (doesn't crash)

---

## References

**Sklar's Theorem**: Any multivariate distribution can be decomposed into marginals and a copula describing their dependence. The copula is defined on *pseudo-observations* (probability-transformed marginals).

**Methodological Principle**: When computing conditional probabilities P(V ≤ v | U = u) using a copula, the (u, v) must be the same transformation used to define/fit that copula. Using different transformations invalidates the copula model.

**Phase 1 Documentation**: See `STEP_1_Family_Selection/README.md` for pseudo-observation computation details

---

## Questions?

- **Why does Phase 1 save pseudo-observations?** → For reproducibility and downstream use (exactly this scenario)
- **Is recomputing really a problem?** → In most cases, differences are negligible. But for rigorous methodology and validation studies, perfect consistency is essential.
- **What if I only want to run STEP 2 (not Phase 1)?** → The fallback ensures it still works, but results won't be perfectly consistent with any previous Phase 1 run
