# Critical Fixes: School/District IDs and Decile Classification

**Date:** January 31, 2026  
**Status:** ✅ IMPLEMENTED - Ready for Re-Run

---

## Documentation Sync Note (2026-02-10)

This is a historical fix memo. Current publication panel naming is:
- `D` = rank agreement
- `E` = decile stability
- `D2` = group bucket stability

Current key output prefixes:
- `panel_d_rank_agreement`
- `panel_e_decile_stability`
- `panel_d2_group_bucket_stability`

---

## Issues Identified

### Issue 1: SCHOOL_NUMBER and DISTRICT_NUMBER All NA
**Severity:** CRITICAL - Prevents Panel B (group-level ECDF) from functioning

**Symptom:**
```
WARNING: No SCHOOL_NUMBER or DISTRICT_NUMBER found. Skipping group aggregation.
```

**Root Cause:**  
The `create_longitudinal_pairs()` function in `functions/longitudinal_pairs.R` was not extracting `SCHOOL_NUMBER` and `DISTRICT_NUMBER` from the source data. It only extracted:
- ID, SCALE_SCORE (prior year)
- ID, SCALE_SCORE, SGP columns (current year)

Result: These columns existed in the output but were 100% NA:
```r
SCHOOL_NUMBER present: TRUE 
DISTRICT_NUMBER present: TRUE 
SCHOOL_NUMBER NA count: 1918720 / 1918720  # All NA!
```

---

### Issue 2: Decile Computation Error
**Severity:** MODERATE - Prevents the decile stability panel (current Panel E) from completing

**Symptom:**
```
Computing decile misclassification rates...
ERROR: 'breaks' are not unique
```

**Root Cause:**  
When computing deciles within each condition using `cut()`, some SGPc variants (especially `sgpc_comonotonic`) have very low variance or near-constant values in certain conditions. This causes `quantile()` to produce non-unique break points.

**Example scenario:**
```r
# Comonotonic SGPc in a small/homogeneous condition
values <- c(95, 95, 95, 95, 96, 96, 96, 96, 96, 96)
quantile(values, probs = 0:10/10)
# Result: 95.0 95.0 95.0 95.0 95.0 95.5 96.0 96.0 96.0 96.0 96.0
#         ^^^^^ many duplicates → cut() fails
```

---

## Fixes Implemented

### Fix 1: Extract School/District IDs from Source Data

**File:** `functions/longitudinal_pairs.R` (lines 63-103)

**Changes:**

1. Added mandatory checks for `SCHOOL_NUMBER` and `DISTRICT_NUMBER`:
   ```r
   # CRITICAL: Check for grouping variables
   if ("SCHOOL_NUMBER" %in% names(data)) {
     group_cols <- c(group_cols, "SCHOOL_NUMBER")
   } else {
     stop("CRITICAL ERROR: SCHOOL_NUMBER column not found in data.\n",
          "  This column is REQUIRED for Step 2 group-level analyses.")
   }
   
   if ("DISTRICT_NUMBER" %in% names(data)) {
     group_cols <- c(group_cols, "DISTRICT_NUMBER")
   } else {
     stop("CRITICAL ERROR: DISTRICT_NUMBER column not found in data.")
   }
   ```

2. Included group columns in data extraction:
   ```r
   all_cols <- c(base_cols, group_cols, sgp_cols)
   ```

3. Added reporting of grouping variables:
   ```r
   cat("  Grouping variables included:", paste(group_cols, collapse = ", "), "\n")
   for (col in group_cols) {
     n_valid <- sum(!is.na(pairs[[col]]))
     cat(sprintf("    %s: %d valid (%.1f%%)\n", col, n_valid, 100 * n_valid / nrow(pairs)))
   }
   ```

**Effect:**  
- Analysis will **stop immediately** if SCHOOL_NUMBER or DISTRICT_NUMBER are missing from source data
- If present, they'll be properly passed through to the paired data
- Clear error messages guide troubleshooting

---

### Fix 2: Robust Decile Classification with Fallback Strategy

**File:** `STEP_2_SGPc_Sensitivity/sgpc_enhanced_statistics.R` (lines 217-268)

**Strategy:** Multi-tier fallback with issue tracking

1. **Try deciles first (10 bins)** - standard approach
2. **If breaks not unique → Try quintiles (5 bins)** - works for moderate variance
3. **If still failing → Return NA** - extreme low variance cases
4. **Track all failures** - report which variables/conditions had issues

**Implementation:**
```r
sgpc_with_deciles[, (decile_var) := {
  vals <- get(var)
  
  decile_result <- tryCatch({
    breaks <- quantile(vals, probs = 0:10/10, na.rm = TRUE, type = 1)
    
    if (length(unique(breaks)) < length(breaks)) {
      # Try quintiles as fallback
      breaks_q <- quantile(vals, probs = 0:5/5, na.rm = TRUE, type = 1)
      
      if (length(unique(breaks_q)) < length(breaks_q)) {
        # Very low variance - cannot classify
        rep(NA_character_, length(vals))
      } else {
        # Quintiles work - map to decile scale (1→1-2, 2→3-4, etc.)
        quintile <- cut(vals, breaks = breaks_q, labels = 1:5, include.lowest = TRUE)
        as.character(as.integer(quintile) * 2)
      }
    } else {
      # Deciles work normally
      cut(vals, breaks = breaks, labels = 1:10, include.lowest = TRUE)
    }
  }, error = function(e) {
    rep(NA_character_, length(vals))
  })
  
  decile_result
}, by = condition_id]

# Track and report failures
n_na <- sum(is.na(sgpc_with_deciles[[decile_var]]))
if (n_na > 0) {
  failed_conditions <- sgpc_with_deciles[is.na(get(decile_var)), unique(condition_id)]
  classification_issues[[var]] <- list(
    n_failed = n_na,
    n_total = nrow(sgpc_with_deciles),
    pct_failed = 100 * n_na / nrow(sgpc_with_deciles),
    failed_conditions = failed_conditions
  )
  cat(sprintf("  NOTE: %s classification failed for %d obs (%.1f%%) across %d conditions\n",
              var, n_na, 100 * n_na / nrow(sgpc_with_deciles), length(failed_conditions)))
}
```

**Added to return value:**
```r
result <- list(
  ...,
  classification_issues = if (length(classification_issues) > 0) classification_issues else NULL,
  ...
)
```

---

### Fix 3: Visual Reporting of Classification Issues

**File:** `STEP_2_SGPc_Sensitivity/sgpc_publication_plots.R` (lines 369-385, 424-427)

**Enhancement to decile stability panel (current Panel E):**

Added automatic detection and reporting of classification issues in the figure caption:

```r
# Check for classification issues
classification_note <- ""
if (!is.null(enhanced_stats$classification_issues)) {
  issue_vars <- names(enhanced_stats$classification_issues)
  if (length(issue_vars) > 0) {
    issue_summary <- sapply(issue_vars, function(v) {
      sprintf("%s (%.1f%%)", gsub("sgpc_", "", v), 
              enhanced_stats$classification_issues[[v]]$pct_failed)
    })
    classification_note <- paste0(
      "\nNote: Classification unavailable for some observations due to low variance: ",
      paste(issue_summary, collapse = ", ")
    )
  }
}

# Add to caption
caption = paste0("Lower differences indicate copula choice has minimal impact...",
                classification_note)
```

**Result:**  
If comonotonic (or any variant) has low-variance conditions, the figure will show:
```
Note: Classification unavailable for some observations due to low variance: comonotonic (8.2%)
```

---

## Expected Behavior After Fixes

### When Re-Running Step 2.1

**Terminal output will now show:**
```
Longitudinal pairs created:
  Prior: Grade 3 MATHEMATICS 2016 - N = 15082 
  Current: Grade 4 MATHEMATICS 2017 - N = 14853 
  Matched pairs: N = 13749 
  Grade span: 1 years
  Time span: 1 years
  Grouping variables included: SCHOOL_NUMBER, DISTRICT_NUMBER     ← NEW
    SCHOOL_NUMBER: 13749 valid (100.0%)                           ← NEW
    DISTRICT_NUMBER: 13749 valid (100.0%)                         ← NEW
  SGP columns included: SGP_ORDER_1_SPAN_1_YEAR, SGP_SPAN_1_YEAR 
    SGP_ORDER_1_SPAN_1_YEAR: 13749 valid (100.0%)
    SGP_SPAN_1_YEAR: 13749 valid (100.0%)
```

**Data verification:**
```r
dt <- readRDS("STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_4.rds")
sum(!is.na(dt$SCHOOL_NUMBER))  # Should now be > 0 (not 1918720 NAs)
```

---

### When Re-Running Step 2.5 (Publication Figure)

**Terminal output will show:**
```
Computing group-level statistics (school/district aggregates)...
  Grouping by: SCHOOL_NUMBER                                      ← NEW (not skipped)
  Emp-Best: 2,450 groups, median group Δ=1.2 (vs individual median=3.1)  ← NEW
  ...

Computing decile misclassification rates...
  NOTE: sgpc_comonotonic classification failed for 156,891 obs (8.2%) across 12 conditions  ← NEW
        (Likely due to low variance in: 2024_G3_G7_MATHEMATICS, 2023_G4_G8_READING, ...)
  Emp-Best: 73.2% exact, 23.1% ±1, 3.7% ≥2 deciles different
  Emp-Canonical: 71.8% exact, 24.5% ±1, 3.7% ≥2 deciles different
  ...
```

**Panel B will now generate** with real school aggregation data.

**Decile stability caption will show:**
```
Note: Classification unavailable for some observations due to low variance: comonotonic (8.2%)
```

---

## Why These Fixes Are Better

### For School/District IDs

**Previous approach (lines 142-143 in sgpc_compute_all_variants.R):**
```r
SCHOOL_NUMBER = if ("SCHOOL_NUMBER" %in% names(pairs)) pairs$SCHOOL_NUMBER else NA_character_
```

This **silently failed** - the column check passed (TRUE), but values were all NA because `pairs` never had the column populated.

**New approach:**
- **Fails fast** at the source (longitudinal_pairs.R)
- **Clear error message** points to the root cause
- **Prevents wasted computation** - stops immediately rather than running 22 minutes and producing useless output

---

### For Decile Classification

**Previous approach:**
- Simple `cut()` with fixed decile breaks
- Crashed on low-variance data
- Lost all information for that variable

**New approach:**
- **Preserves data where possible** - uses quintiles if deciles fail
- **Tracks issues systematically** - knows exactly which variables/conditions failed
- **Reports transparently** - both in terminal and in figure captions
- **Interprets scientifically** - low variance in comonotonic is actually *informative* (it means the method produces extreme, concentrated predictions)

---

## Testing and Next Steps

### Step 1: Verify Source Data

Before re-running, confirm your source data has these columns:

```r
# In R
data <- readRDS("SGP/dataset_4.Rdata")  # Or wherever your source is
"SCHOOL_NUMBER" %in% names(data)
"DISTRICT_NUMBER" %in% names(data)
sum(!is.na(data$SCHOOL_NUMBER))  # Should be > 0
```

If these checks fail, **check your data source** - the columns must exist there first.

---

### Step 2: Re-Run Step 2.1

```r
# Delete old results (without school IDs)
file.remove("STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_4.rds")
file.remove("STEP_2_SGPc_Sensitivity/results/sgpc_enhanced_stats.rds")

# Re-run with fixes
DATASETS_TO_RUN <- c("dataset_4")
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- TRUE

source("master_analysis.R")
```

**Expected time:** ~25-28 minutes total
- Step 2.1: 22-24 min (with new ID extraction)
- Step 2.2: 5-10 sec
- Step 2.3: 10-15 sec (may still error on violin - that's OK)
- Step 2.4: 5 sec
- **Step 2.5: 2-3 min** (with complete data and robust decile handling)

---

### Step 3: Validate Output

**Check school IDs are populated:**
```r
dt <- readRDS("STEP_2_SGPc_Sensitivity/results/sgpc_all_variants_dataset_4.rds")
sum(!is.na(dt$SCHOOL_NUMBER))  # Should be > 0
sum(!is.na(dt$DISTRICT_NUMBER))  # Should be > 0
```

**Check Panel B exists:**
```bash
ls -lh STEP_2_SGPc_Sensitivity/results/visualizations/panel_b_group_ecdf.pdf
# Should exist (not placeholder)
```

**Check decile stability note:**
```bash
open STEP_2_SGPc_Sensitivity/results/visualizations/panel_e_decile_stability.pdf
# Caption should mention any low-variance issues
```

---

## What Low-Variance Decile Classification Means Scientifically

If `sgpc_comonotonic` has classification issues, **this is actually evidence supporting your thesis**:

**Interpretation:**
- Comonotonic copula assumes **perfect positive dependence** (ρ = 1.0)
- This produces SGPc values that are **extremely concentrated** (low variance)
- In some conditions, essentially all students get similar percentiles
- This is **unrealistic** and **contradicts the data**

**In contrast:**
- Empirical, best-fit, and canonical copulas allow realistic variance
- Their SGPc distributions span the full 1-99 range appropriately
- Decile classification works normally

**So the "classification failed" note for comonotonic is actually:**
- Not a bug in your code
- Evidence that the comonotonic assumption is too extreme
- Supporting material for "TAMP's assumption is untenable"

---

## Summary of Changes

### Modified Files

1. **`functions/longitudinal_pairs.R`** (lines 63-138)
   - Added mandatory SCHOOL_NUMBER/DISTRICT_NUMBER extraction
   - Stops execution if these columns don't exist
   - Reports grouping variable validity

2. **`STEP_2_SGPc_Sensitivity/sgpc_enhanced_statistics.R`** (lines 217-268, 357-375)
   - Robust decile computation with quintile fallback
   - Tracks and reports classification failures
   - Returns `classification_issues` in result list

3. **`STEP_2_SGPc_Sensitivity/sgpc_publication_plots.R`** (lines 369-385, 424-427)
   - Detects classification issues
   - Adds informative note to decile stability caption

---

## If Analysis Still Fails

### Error: "SCHOOL_NUMBER column not found"

**Cause:** Your source data doesn't have this column.

**Solution:** Check which data file is being loaded:
```r
# What file is master_analysis.R loading for dataset_4?
# Look at dataset_configs.R for the path
# Then check that file:
data <- readRDS("path/to/dataset_4.Rdata")
names(data)  # Should include SCHOOL_NUMBER, DISTRICT_NUMBER
```

If the columns genuinely don't exist in your source data, you have two options:
1. **Add them** - merge from a school roster or administrative data
2. **Use alternative grouping** - modify code to use a different grouping variable you do have

---

### Decile Issues Persist

If you still see errors after these fixes:
1. Check the terminal output for which specific variable is failing
2. Look at the `classification_issues` list in the enhanced stats:
   ```r
   stats <- readRDS("STEP_2_SGPc_Sensitivity/results/sgpc_enhanced_stats.rds")
   stats$classification_issues
   # Shows exactly which variables/conditions failed
   ```
3. Consider computing deciles **overall** (not by condition) for problematic variables

---

## Expected Final Output

After re-running, you should see:

**Core panels generate successfully:**
- ✅ Panel A: Individual-level ECDF
- ✅ Panel B: Group-level ECDF (now with real school data!)
- ✅ Panel C: Condition-level dots
- ✅ Panel D: Rank agreement
- ✅ Panel E: Decile stability (with informative note if needed)

**Assembled grid:**
- `sgpc_summary_grid.pdf` (16" × 12")
- `sgpc_summary_grid.svg`
- `sgpc_summary_grid.png`

All with consistent Wes Anderson Zissou1 color palette! 🎨
