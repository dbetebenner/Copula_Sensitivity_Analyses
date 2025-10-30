# Sequencing Bug Fix: Dataset ID Grouping Error

**Date:** 2025-10-24  
**Status:** ✅ FIXED  
**Impact:** Critical - Prevented script execution

## The Error

```
*** ERROR in Step 1.1: Family Selection ***
Message: The items in the 'by' or 'keyby' list have lengths [1, 252]. 
Each must be length 252; the same length as there are rows in x 
(after subsetting if i is provided).
```

## Root Cause

A sequencing error was introduced when fixing the delta AIC calculation:

### What Happened:
1. **Lines 395-401**: Code tried to group by `.(dataset_id, condition_id)`
   ```r
   results_dt[, best_aic := family[which.min(aic)], by = .(dataset_id, condition_id)]
   ```

2. **Lines 417-419**: The `dataset_id` column was ADDED (too late!)
   ```r
   results_dt[, dataset_id := current_dataset$id]
   ```

### The Bug:
- At line 395, `dataset_id` doesn't exist as a column yet
- data.table finds the **scalar variable** `dataset_id` from the environment (e.g., "dataset_1")
- This scalar has length **1**, while `condition_id` column has length **252**
- Error: "items in 'by' list have lengths [1, 252]"

## The Fix

**Reverted to using `condition_id` alone** in the individual dataset scripts:

```r
# Calculate best family for each condition
# NOTE: Within a single dataset run, condition_id is unique, so we only need to group by condition_id here.
# Multi-dataset aggregation (grouping by dataset_id + condition_id) happens later in phase1_analysis.R
# when results from all datasets are combined.
results_dt[, best_aic := family[which.min(aic)], by = condition_id]
results_dt[, best_bic := family[which.min(bic)], by = condition_id]
results_dt[, delta_aic_vs_best := aic - min(aic), by = condition_id]
results_dt[, delta_bic_vs_best := bic - min(bic), by = condition_id]
```

## Why This is Correct

### Separation of Concerns:

**Individual Dataset Scripts** (`phase1_family_selection.R`, `phase1_family_selection_parallel.R`):
- Process **ONE dataset at a time**
- Within a single dataset, `condition_id` IS unique
- Calculate within-dataset metrics using `condition_id` grouping
- Add `dataset_id` metadata after calculations

**Analysis Script** (`phase1_analysis.R`):
- Combines results from **ALL datasets**
- Recalculates delta AIC using `.(dataset_id, condition_id)` composite key
- Handles cross-dataset aggregation correctly

### Key Insight:
The composite key `(dataset_id, condition_id)` is only needed when:
1. Multiple datasets are combined in a single data.table
2. `condition_id` values can collide across datasets

Within a single dataset run, `condition_id` is sufficient and correct.

## Files Fixed

1. **`STEP_1_Family_Selection/phase1_family_selection.R`** (lines 381-390)
2. **`STEP_1_Family_Selection/phase1_family_selection_parallel.R`** (lines 395-404)

Both files now:
- Use `condition_id` alone for grouping
- Include explanatory comments about multi-dataset handling
- Allow dataset metadata to be added after calculations

## Architecture Summary

```
┌─────────────────────────────────────────────────────────┐
│ INDIVIDUAL DATASET SCRIPTS (Run 3 times, once per DS)  │
│ ─────────────────────────────────────────────────────  │
│ 1. Load ONE dataset                                     │
│ 2. Fit copulas for all conditions                       │
│ 3. Calculate metrics using: by = condition_id           │
│    (condition_id is unique within this dataset)         │
│ 4. Add dataset_id metadata                              │
│ 5. Save to dataset-specific CSV                         │
│ 6. Accumulate in ALL_DATASET_RESULTS                    │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ MASTER SCRIPT (Runs once after all datasets)           │
│ ─────────────────────────────────────────────────────  │
│ 1. Combine ALL_DATASET_RESULTS into single CSV         │
│ 2. Save to dataset_all/phase1_copula_...csv            │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ ANALYSIS SCRIPT (Reads combined CSV)                   │
│ ─────────────────────────────────────────────────────  │
│ 1. Load combined results from all datasets             │
│ 2. RECALCULATE: by = .(dataset_id, condition_id)       │
│    (now condition_id can collide across datasets)       │
│ 3. Calculate AIC weights                                │
│ 4. Generate plots and summaries                         │
│ 5. Make Phase 2 decision                                │
└─────────────────────────────────────────────────────────┘
```

## Lesson Learned

**When using composite keys:**
1. Ensure all key components exist as columns before grouping
2. Consider whether the composite key is actually needed at that stage
3. Use clear comments to explain the scoping logic
4. Separate concerns: per-dataset vs. cross-dataset operations

**In this case:** The fix was actually a **simplification** - we didn't need the composite key in the individual scripts at all, only in the final analysis stage.

---

**Status:** Fixed and documented. Scripts now run correctly through all 3 datasets.

