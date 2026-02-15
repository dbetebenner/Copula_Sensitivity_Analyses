# Critical Fix: Duplicate parse_condition_id() Function

**Date**: January 28, 2026, 18:59  
**Issue**: Inline function definition overriding the corrected version  
**Severity**: HIGH - Caused all year assignments to be wrong

---

## The Problem

There were **TWO definitions** of `parse_condition_id()`:

1. **Correct version** in `phase1_data_loader.R` (lines 242-260)
   - Uses `year_current` from condition ID
   - Calculates `year_prior = year_current - year_span`
   - Returns both `year_prior` and `year_current`

2. **OLD buggy version** inline in `sgpc_compute_all_variants.R` (lines 63-82)
   - Used `year_prior` from condition ID (WRONG!)
   - Did NOT return `year_current` at all
   - This **overrode** the correct version from `phase1_data_loader.R`

---

## Why This Happened

In R, when you source a file and then define a function with the same name, **the later definition wins**. 

Execution order:
1. Line 27: `source("STEP_2_SGPc_Sensitivity/phase1_data_loader.R")` ✓ Correct version loaded
2. Lines 66-82: `parse_condition_id <- function(...)` ✗ **Overrode with OLD buggy version**

So even though we fixed `phase1_data_loader.R`, the inline definition was **silently overriding** it every time.

---

## Why Restarting R Didn't Help

The user correctly quit and restarted R multiple times, but the problem persisted because:
- The bug wasn't in cached functions
- The bug was in the **SOURCE CODE** itself (duplicate definition)
- Every time R loaded the file, it would:
  1. Load correct version
  2. Immediately overwrite it with buggy version

---

## The Fix

**Removed the duplicate inline definition** from `sgpc_compute_all_variants.R` (lines 63-82).

**Before (BUGGY):**
```r
# In sgpc_compute_all_variants.R
parse_condition_id <- function(condition_id) {
  parts <- strsplit(condition_id, "_")[[1]]
  year_prior <- as.integer(parts[1])  # WRONG!
  # ... no year_current returned
}
```

**After (FIXED):**
```r
# In sgpc_compute_all_variants.R
# NOTE: parse_condition_id() is now sourced from phase1_data_loader.R (line 27)
# DO NOT define it inline here as it will override the correct version
```

Now the only definition is the **correct one** in `phase1_data_loader.R`.

---

## Expected Result

After this fix, when you restart and run:

```r
DATASETS_TO_RUN <- c("dataset_4")
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- FALSE
source("master_analysis.R")
```

**You should see:**
```
Processing condition: 2017_G3_G4_MATHEMATICS ...Longitudinal pairs created:
  Prior: Grade 3 MATHEMATICS 2016 - N = 15082    ✓ Correct!
  Current: Grade 4 MATHEMATICS 2017 - N = 14853  ✓ Correct!
  Matched pairs: N = 13749                        ✓ Matches Phase 1!

 [using Phase 1 pseudo-observations] done        ✓ Success!
```

For multi-year spans like `2023_G3_G7_READING`:
```
  Prior: Grade 3 READING 2019 - N = 12812    ✓ (2023 - 4 = 2019)
  Current: Grade 7 READING 2023 - N = xxxxx  ✓
```

---

## Lessons Learned

1. **Never define helper functions inline** when they're also defined in sourced files
2. **Function name conflicts** silently override without warnings
3. **Debugging tools helped**: Adding explicit version markers (`[FIXED VERSION v2]`) proved no debug messages appeared, confirming override
4. **`browser()` was critical**: Showed the function was returning wrong structure (no `year_current`)

---

## Files Changed

1. **`sgpc_compute_all_variants.R`** (lines 63-82 removed)
   - Deleted duplicate buggy `parse_condition_id()` definition
   - Added comment noting function is sourced from `phase1_data_loader.R`

2. **`phase1_data_loader.R`** (cleanup)
   - Removed temporary debug statements

---

## Complete Fix Timeline

1. **Fix 1**: Updated `get_phase1_conditions()` to use `year_current` in condition IDs
2. **Fix 2**: Updated `parse_condition_id()` in `phase1_data_loader.R` to parse `year_current` correctly
3. **Fix 3**: Added explicit `year_current` parameter to `create_longitudinal_pairs()` call
4. **Fix 4** (THIS ONE): Removed duplicate inline definition that was overriding everything

**All four fixes are now in place and the code should work correctly.**

---

## Verification

To verify the fix worked, check the console output:
- ✓ Years are correct (e.g., 2016→2017 for condition `2017_G3_G4_MATHEMATICS`)
- ✓ Dimensions match Phase 1 (e.g., 13,749 pairs)
- ✓ Message shows `[using Phase 1 pseudo-observations]`
- ✓ NO warnings about dimension mismatch
