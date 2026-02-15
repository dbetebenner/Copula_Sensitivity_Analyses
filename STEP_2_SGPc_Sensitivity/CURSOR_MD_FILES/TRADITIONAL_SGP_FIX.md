# Fix: Traditional SGP Integration

**Date**: January 30, 2026  
**Issue**: `sgp_traditional` column was 100% NA, causing Step 2.2 correlation failures  
**Severity**: HIGH - Prevented aggregate analysis from completing

---

## The Problem

**Step 2.2 (Aggregate Analysis) was failing with:**
```
*** ERROR in Step 2.2: Aggregate Analysis ***
Message: no complete element pairs
```

**Root cause**: The `sgp_traditional` column had **100% NA values** (all 1.9M observations were missing).

When the correlation function tried to compute:
```r
cor(sgpc_emp, sgp_traditional, use = "complete.obs")
```

It failed because there were **zero complete observation pairs** (you can't correlate with a column of all NAs).

---

## Why This Happened

The `compute_sgpc_variants()` function was:
1. Accepting a `traditional_sgp` parameter
2. Always being called with `traditional_sgp = NULL` (lines 306, 347)
3. Setting `result[, sgp_traditional := NA_integer_]` when NULL

**But the data WAS available!** The `create_longitudinal_pairs()` function already includes traditional SGP columns in the pairs data:
- `SGP_ORDER_1_SPAN_1_YEAR` - for 1-year spans
- `SGP_ORDER_1_SPAN_2_YEAR` - for 2-year spans
- etc.

We just weren't extracting them!

---

## The Fix

### Part 1: Extract Traditional SGP from Pairs Data

**Modified `sgpc_compute_all_variants.R` (lines 201-218):**

```r
# OLD (BUGGY):
if (!is.null(traditional_sgp)) {
  result[, sgp_traditional := traditional_sgp]
} else {
  result[, sgp_traditional := NA_integer_]
}

# NEW (FIXED):
# Extract from pairs data based on year_span
sgp_col_name <- paste0("SGP_ORDER_1_SPAN_", cond_meta$year_span, "_YEAR")

if (sgp_col_name %in% names(pairs)) {
  result[, sgp_traditional := pairs[[sgp_col_name]]]
} else {
  # Try alternative naming convention
  sgp_alt_col <- paste0("SGP_SPAN_", cond_meta$year_span, "_YEAR")
  if (sgp_alt_col %in% names(pairs)) {
    result[, sgp_traditional := pairs[[sgp_alt_col]]]
  } else {
    result[, sgp_traditional := NA_integer_]
  }
}
```

**What this does:**
- Constructs the appropriate SGP column name based on `year_span`
- For 1-year span: looks for `SGP_ORDER_1_SPAN_1_YEAR`
- For 2-year span: looks for `SGP_ORDER_1_SPAN_2_YEAR`
- Falls back to alternative naming if needed
- Only sets NA if truly not available

### Part 2: Remove Unused Parameter

**Removed `traditional_sgp` parameter from function signature** (line 73):

```r
# OLD:
compute_sgpc_variants <- function(
  condition_id,
  dataset_data,
  phase1_results,
  canonical_params,
  traditional_sgp = NULL  # ← REMOVED
) {

# NEW:
compute_sgpc_variants <- function(
  condition_id,
  dataset_data,
  phase1_results,
  canonical_params
) {
```

**Updated all function calls** to remove the parameter (lines 300-305, 340-346).

### Part 3: Make Aggregate Analysis Robust

**Modified `sgpc_aggregate_analysis.R`:**

1. **`compute_correlations()` function** now filters out all-NA columns:
```r
# Filter out columns that are entirely NA
valid_cols <- character(0)
for (col in sgpc_cols) {
  if (sum(!is.na(dt[[col]])) > 0) {
    valid_cols <- c(valid_cols, col)
  }
}
```

2. **`compute_differences()` function** now:
   - Filters out all-NA columns
   - Only computes statistics for pairs with `n_complete > 0`

This makes the analysis robust even if traditional SGP is missing for some conditions (e.g., multi-year spans where traditional SGP wasn't computed).

---

## Expected Results

After this fix, when running Step 2.1:

```
Processing condition: 2017_G3_G4_MATHEMATICS ...
  ...
  Matched pairs: N = 13749
  SGP columns included: SGP_ORDER_1_SPAN_1_YEAR, SGP_SPAN_1_YEAR
    SGP_ORDER_1_SPAN_1_YEAR: 13749 valid (100.0%)  ✓
```

After running Step 2.2:

```r
dt <- readRDS('STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_4.rds')

# Check traditional SGP
sum(!is.na(dt$sgp_traditional))  # Should be >> 0
# Expected: ~1.9M valid values (or subset for conditions with traditional SGP)
```

**Step 2.2 should now complete successfully** with:
```
Key Findings:
  Empirical vs best-fit parametric: r=0.XXX, MAD=X.X percentile points
  Empirical vs canonical averaged: r=0.XXX, MAD=X.X percentile points
  Traditional vs Empirical: r=0.XXX, MAD=X.X percentile points  ✓ NEW!
  ...
```

---

## Files Changed

1. **`sgpc_compute_all_variants.R`**:
   - Lines 67-78: Updated function signature (removed parameter)
   - Lines 201-218: Extract traditional SGP from pairs data
   - Lines 300-305: Removed parameter from parallel call
   - Lines 340-346: Removed parameter from sequential call

2. **`sgpc_aggregate_analysis.R`**:
   - Lines 58-91: Updated `compute_correlations()` to filter all-NA columns
   - Lines 91-128: Updated `compute_differences()` to filter all-NA columns and check for complete pairs

---

## Verification

To verify the fix worked:

```r
# 1. Check that traditional SGP is populated
dt <- readRDS('STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_4.rds')
table(is.na(dt$sgp_traditional))
# Should show mostly FALSE (valid values)

# 2. Check correlations work
cor(dt$sgpc_emp, dt$sgp_traditional, use = "complete.obs")
# Should return a numeric value (not NA or error)

# 3. Run Step 2.2
source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
# Should complete without "no complete element pairs" error
```

---

## Why This Is Important

Traditional SGP values represent the **current operational baseline** - what's actually being reported to schools and used for accountability. Comparing copula-based SGPcs against traditional SGPs answers:

1. **Backwards compatibility**: Are copula SGPcs similar enough to traditional SGPs?
2. **Practical impact**: Would switching methods change reported growth?
3. **Validation**: Do both methods agree on who's growing vs. not growing?

Without this comparison, we couldn't assess the **operational feasibility** of transitioning to copula-based methods.

---

## Notes

- Traditional SGP may still be NA for some conditions (e.g., 4-year spans if not computed originally)
- The aggregate analysis now handles this gracefully by excluding all-NA columns
- For conditions where traditional SGP exists, it should now be included in all comparisons
