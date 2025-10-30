# Column Name Consistency Fix: grade_span → year_span

**Date:** 2025-10-25  
**Status:** ✅ FIXED  
**Impact:** Critical - Analysis script error resolved

## The Error

After adding metadata enrichment to the parallel script, Step 1.2 (analysis) failed:

```
*** ERROR in Step 1.2: Analysis and Decision ***
Message: object 'grade_span' not found
```

## Root Cause

When we added metadata enrichment to the parallel script, we standardized column naming:
- Changed `grade_span` → `year_span` (more accurate terminology)
- Changed `cohort_year` → `year_prior` (clearer meaning)

However, `phase1_analysis.R` still referenced the old column names, causing it to fail when trying to access `grade_span`.

## The Fix

Updated `phase1_analysis.R` to use the new standardized column name `year_span` throughout.

### Changes Made:
- **19 occurrences** of `grade_span` replaced with `year_span`
- Updated all sections:
  - Analysis by year span (grouping)
  - Tail dependence analysis
  - Plotting code
  - Heatmap generation
  - Decision logic

### Files Modified:
1. **`STEP_1_Family_Selection/phase1_analysis.R`**
   - Global find-and-replace: `grade_span` → `year_span`
   - Updated comments to reference "year span" instead of "grade span"

## Why "year_span" is Better

The term "year span" is more accurate than "grade span" because:

1. **Temporal clarity**: It's the number of **years** between assessments (1, 2, 3, or 4)
2. **Avoids confusion**: "Grade span" could be misinterpreted as grade difference
3. **Consistent with metadata**: Pairs nicely with `year_prior` and `year_current`
4. **Multi-grade tracking**: A student might skip a grade or be retained, so year is the true measure

**Example:**
- Grade 4 (2020) → Grade 6 (2022)
- `year_span = 2` (2 years elapsed) ✓
- "grade span = 2" (could mean "grades 4-6" or "2 grade levels") ✗

## Standardized Column Naming

### Temporal Columns:
- ✅ `year_span` - Number of years between assessments (1-4)
- ✅ `year_prior` - Year of prior assessment (e.g., "2020")
- ✅ `year_current` - Year of current assessment (e.g., "2022")

### Grade Columns:
- ✅ `grade_prior` - Grade at prior assessment (e.g., 4)
- ✅ `grade_current` - Grade at current assessment (e.g., 6)

### Old Names (Deprecated):
- ❌ `grade_span` - Now `year_span`
- ❌ `cohort_year` - Now `year_prior`
- ❌ `span` - Now `year_span` (parallel script had this inconsistency)

## Verification

After the fix, the analysis script should:
1. ✅ Load data successfully
2. ✅ Group by `year_span` correctly
3. ✅ Generate plots with year span labels
4. ✅ Complete without "object not found" errors

Check:
```r
# Load results
results <- fread("STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv")

# Verify column exists
"year_span" %in% names(results)  # Should be TRUE
"grade_span" %in% names(results)  # Should be FALSE

# Check valid values
unique(results$year_span)  # Should be: 1, 2, 3, 4
```

## Related Fixes

This is part of a series of naming standardization fixes:

1. ✅ **Dataset ID grouping** - Use `(dataset_id, condition_id)` composite key
2. ✅ **Metadata enrichment** - Add 9 missing columns to parallel script
3. ✅ **Column naming** - Standardize `year_span`, `year_prior`, `year_current`

All three were needed to make the multi-dataset analysis work correctly.

## Impact on Documentation

Any documentation or plot labels that referenced "grade span" should be updated to "year span" for clarity, though both terms are technically correct in this context (where students progress one grade per year).

---

**Status:** Fixed. Analysis script now compatible with standardized column names from data generation scripts.

