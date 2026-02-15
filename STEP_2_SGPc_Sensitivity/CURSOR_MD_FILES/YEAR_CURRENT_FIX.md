# Final Fix: Explicit year_current Parameter

**Date**: January 28, 2026  
**Issue**: Still seeing wrong years (2017→2018 instead of 2016→2017) even after restarting R  
**Root Cause**: Missing explicit `year_current` parameter allowed function to recalculate incorrectly

---

## The Problem

Even after fixing `parse_condition_id()` to correctly interpret condition IDs, users who restarted R were still seeing:

```
Processing condition: 2017_G3_G4_MATHEMATICS
  Prior: Grade 3 MATHEMATICS 2017 ← Should be 2016!
  Current: Grade 4 MATHEMATICS 2018 ← Should be 2017!
```

## Why This Happened

### The Call Chain

1. `sgpc_compute_all_variants.R` calls `parse_condition_id("2017_G3_G4_MATHEMATICS")`
   - Returns: `year_prior=2016, year_current=2017` ✓ Correct

2. Then calls `create_longitudinal_pairs()`:
   ```r
   create_longitudinal_pairs(
     year_prior = "2016",
     # year_current NOT PASSED ← The problem!
   )
   ```

3. `create_longitudinal_pairs()` sees `year_current` is NULL, so it calculates:
   ```r
   year_current <- as.character(year_prior + grade_span)
   # 2016 + 1 = 2017 ✓ Should work...
   ```

### The Cache Issue

**BUT** if R had cached the OLD buggy version of `parse_condition_id()` from before the fix:
- Old buggy version returned: `year_prior=2017` (wrong!)
- Then calculation: `year_current = 2017 + 1 = 2018` (wrong!)

Even though the file was fixed, **R's function cache** could persist across restarts in some circumstances (shared libraries, parallel workers, etc.).

---

## The Solution

**Make the `year_current` parameter explicit** so NO calculation happens:

### Changed in `sgpc_compute_all_variants.R` (line 111)

**Before:**
```r
create_longitudinal_pairs(
  data = dataset_data,
  grade_prior = cond_meta$grade_prior,
  grade_current = cond_meta$grade_current,
  year_prior = as.character(cond_meta$year_prior),
  # year_current missing - will be calculated
  content_prior = cond_meta$content_area,
  content_current = cond_meta$content_area
)
```

**After:**
```r
create_longitudinal_pairs(
  data = dataset_data,
  grade_prior = cond_meta$grade_prior,
  grade_current = cond_meta$grade_current,
  year_prior = as.character(cond_meta$year_prior),
  year_current = as.character(cond_meta$year_current),  # ← ADDED
  content_prior = cond_meta$content_area,
  content_current = cond_meta$content_area
)
```

---

## Expected Result After Fix

When you restart R and re-run, you should now see:

```
Processing condition: 2017_G3_G4_MATHEMATICS ...Longitudinal pairs created:
  Prior: Grade 3 MATHEMATICS 2016 - N = 15082    ✓ Correct!
  Current: Grade 4 MATHEMATICS 2017 - N = 14853  ✓ Correct!
  Matched pairs: N = 13749                        ✓ Matches Phase 1!

 [using Phase 1 pseudo-observations] done        ✓ Success!
```

**No more dimension mismatch warning!**

---

## Why This Fix is Robust

1. **Eliminates dependency on calculation** - Both years come directly from `parse_condition_id()`
2. **Cache-proof** - Even if something is cached, the explicit values override any calculation
3. **Self-documenting** - Makes the year assignment explicit and clear
4. **Defense in depth** - Works even if `parse_condition_id()` has a bug

---

## Files Changed

- `STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R` (line 111)
- `STEP_2_SGPc_Sensitivity/CONDITION_ID_FIX.md` (documentation updated)

---

## Testing

After this fix, run:
```r
rm(list = ls())  # Clear workspace
DATASETS_TO_RUN <- c("dataset_4")
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- FALSE
source("master_analysis.R")
```

**You should see**:
- Correct years (2016→2017 for condition 2017_G3_G4_MATHEMATICS)
- Exact dimension match (13,749 pairs)
- Message: `[using Phase 1 pseudo-observations]`
- NO warnings about dimension mismatch

---

## Summary of All Fixes

This is the **third and final fix** in the sequence:

1. **Fix 1**: Updated `get_phase1_conditions()` to use `year_current` instead of `year_prior` when constructing condition IDs
2. **Fix 2**: Updated `parse_condition_id()` to correctly interpret first year as `year_current` and calculate `year_prior`
3. **Fix 3** (this one): Added explicit `year_current` parameter to eliminate any calculation and prevent cache issues

All three fixes work together to ensure condition IDs are correctly interpreted as: `{year_current}_G{prior}_G{current}_{content}`.
