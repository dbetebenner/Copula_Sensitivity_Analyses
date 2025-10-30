# Join Key Fix: Adding dataset_id to condition_id in phase1_analysis.R

**Date:** 2025-10-23  
**Status:** ✅ COMPLETE

## Problem

After successfully implementing multi-dataset processing, Step 1.2 (analysis and decision) was failing with a cartesian join error:

```
Error: Join results in 269 rows; more than 258 = nrow(x)+nrow(i). Check for duplicate key values in i each of which join to the same group in x over and over again.
```

### Root Cause

**`condition_id` is NOT unique across datasets!**

- Dataset 1: condition_id 1-28
- Dataset 2: condition_id 1-21  
- Dataset 3: condition_id 1-80

Each dataset reuses condition numbering starting from 1. When operations in `phase1_analysis.R` used `condition_id` alone as a grouping/join key, they created duplicates:

- Dataset 1's condition 1 grouped/joined with Dataset 2's condition 1
- Dataset 1's condition 1 grouped/joined with Dataset 3's condition 1
- Etc.

This caused cartesian products in joins and incorrect aggregations.

## Solution

**Add `dataset_id` to all grouping and join operations that use `condition_id`.**

The combination `(dataset_id, condition_id)` is guaranteed to be unique across the entire combined results dataset.

## Changes Made

### File: `STEP_1_Family_Selection/phase1_analysis.R`

#### 1. Line 39: Selection Frequency by AIC
```r
# OLD:
selection_freq_aic <- results[, .SD[which.min(aic)], by = condition_id][, .N, by = family]

# NEW:
selection_freq_aic <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id)][, .N, by = family]
```

#### 2. Line 48: Selection Frequency by BIC
```r
# OLD:
selection_freq_bic <- results[, .SD[which.min(bic)], by = condition_id][, .N, by = family]

# NEW:
selection_freq_bic <- results[, .SD[which.min(bic)], by = .(dataset_id, condition_id)][, .N, by = family]
```

#### 3. Line 77: Analysis by Grade Span
```r
# OLD:
by_span <- results[, .SD[which.min(aic)], by = .(condition_id, grade_span)][

# NEW:
by_span <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id, grade_span)][
```

#### 4. Line 94-97: T-Copula vs Gaussian Merge ⚠️ **This was causing the error**
```r
# OLD:
t_vs_gaussian <- merge(
  results[family == "t", .(condition_id, grade_span, aic_t = aic)],
  results[family == "gaussian", .(condition_id, aic_gaussian = aic)],
  by = "condition_id"
)

# NEW:
t_vs_gaussian <- merge(
  results[family == "t", .(dataset_id, condition_id, grade_span, aic_t = aic)],
  results[family == "gaussian", .(dataset_id, condition_id, aic_gaussian = aic)],
  by = c("dataset_id", "condition_id")
)
```

#### 5. Line 122: Analysis by Content Area
```r
# OLD:
by_content <- results[, .SD[which.min(aic)], by = .(condition_id, content_area)][

# NEW:
by_content <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id, content_area)][
```

#### 6. Line 302: Heatmap Data Preparation
```r
# OLD:
best_by_span_content <- results[, .SD[which.min(aic)], by = .(condition_id, grade_span, content_area)][

# NEW:
best_by_span_content <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id, grade_span, content_area)][
```

## Expected Outcome

After these fixes:

1. **No Cartesian Products**: Each condition is now uniquely identified by `(dataset_id, condition_id)`.
2. **Correct Row Counts**: The merge at line 94 should now produce exactly 129 rows (one per unique condition across all datasets), not 269.
3. **Accurate Aggregations**: All analyses by grade span, content area, etc., will correctly group conditions within their respective datasets.
4. **Step 1.2 Completion**: The `phase1_analysis.R` script should now run to completion, generating plots and the decision file for Step 2.

## Verification

To verify the fix:

```r
# Source the test script
source("run_test_multiple_datasets.R")

# After completion, check:
# 1. Step 1.2 completes without errors
# 2. Output files exist in STEP_1_Family_Selection/results/dataset_all/:
#    - phase1_heatmap.pdf
#    - phase1_aic_comparison.pdf
#    - phase1_parameter_comparison.pdf
#    - phase1_decision.RData
# 3. Console output shows correct condition counts (129 total)
```

## Related Issues

This completes the multi-dataset implementation journey:

1. ✅ Multi-dataset configuration (`dataset_configs.R`)
2. ✅ LONG-format output with metadata
3. ✅ Dataset-specific result directories
4. ✅ Global result accumulation (`ALL_DATASET_RESULTS`)
5. ✅ Combined results file (`phase1_copula_family_comparison_all_datasets.csv`)
6. ✅ Environment scoping fixes
7. ✅ Step 1.2 structural relocation (moved outside dataset loop)
8. ✅ Dataset metadata enrichment in parallel script
9. ✅ **Join key uniqueness** (this fix)

## Key Lesson

**When working with multi-dataset analyses where condition_id is reused:**
- Always use `(dataset_id, condition_id)` as the composite key
- Never use `condition_id` alone for grouping, joining, or merging operations
- This ensures uniqueness and prevents cartesian products

---

**Status**: Ready for full 3-dataset test run through Step 1 completion.

