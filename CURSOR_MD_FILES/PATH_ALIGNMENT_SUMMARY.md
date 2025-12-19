# Path Alignment Summary

**Date:** 2024-12-17  
**Issue:** Path duplication in test_contour_plots.R causing nested STEP_1_Family_Selection directories

---

## Problem Identified

When running `source("STEP_1_Family_Selection/test_contour_plots.R")` from the project root, the script was creating a duplicated directory structure:

```
STEP_1_Family_Selection/results/test/contour_plots/2005_G4_G5_MATHEMATICS/STEP_1_Family_Selection/
```

Instead of:
```
STEP_1_Family_Selection/results/test/contour_plots/2005_G4_G5_MATHEMATICS/
```

## Root Cause

The test script was using **conditional relative paths** based on whether `PROJECT_ROOT == getwd()`:
- If running from project root: prepend `"STEP_1_Family_Selection/"`
- If running from subdirectory: use `"results/"`

This approach was fragile and led to path construction issues in downstream functions.

---

## Solutions Implemented

### 1. Fixed `test_contour_plots.R` (COMPLETED ✅)

**File:** `/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses/STEP_1_Family_Selection/test_contour_plots.R`

**Change:** Lines 232-247

**Before:**
```r
# Set up output directory (relative to project root)
if (PROJECT_ROOT == getwd()) {
  output_dir <- file.path("STEP_1_Family_Selection/results/test/contour_plots",
                          sprintf("%s_G%d_G%d_%s", ...))
} else {
  output_dir <- file.path("results/test/contour_plots",
                          sprintf("%s_G%d_G%d_%s", ...))
}
```

**After:**
```r
# Set up output directory (absolute path to avoid duplication)
output_dir <- file.path(PROJECT_ROOT, "STEP_1_Family_Selection/results/test/contour_plots",
                        sprintf("%s_G%d_G%d_%s", ...))
```

**Benefit:** Uses absolute paths consistently, eliminating ambiguity and preventing duplications.

---

### 2. Verified `master_analysis.R` Alignment (VERIFIED ✅)

**File:** `/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses/master_analysis.R`

**Lines 229-237:**
```r
# Set working directory to project root (where master_analysis.R is located)
PROJECT_ROOT <- dirname(normalizePath(sys.frame(1)$ofile))
if (is.null(PROJECT_ROOT) || PROJECT_ROOT == "") {
  # Fallback: assume we're in the project root
  PROJECT_ROOT <- getwd()
}

# Set working directory to project root
setwd(PROJECT_ROOT)
```

**Status:** ✅ **Already correctly configured**
- Automatically detects project root from script location
- Explicitly sets working directory to project root
- Ensures all subsequent relative paths work correctly

---

### 3. Verified `phase1_family_selection.R` Alignment (VERIFIED ✅)

**File:** `/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses/STEP_1_Family_Selection/phase1_family_selection.R`

**Lines 463-468:**
```r
plot_output_dir <- file.path("STEP_1_Family_Selection/results", 
                             dataset_id,
                             "contour_plots",
                             sprintf("%s_G%d_G%d_%s", ...))
```

**Status:** ✅ **Correctly uses relative paths**
- Uses relative paths starting from `"STEP_1_Family_Selection/"`
- Works correctly because `master_analysis.R` ensures `getwd()` is project root
- Consistent with design pattern for scripts sourced from master

---

### 4. Verified `functions/copula_contour_plots.R` (VERIFIED ✅)

**File:** `/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses/functions/copula_contour_plots.R`

**Key Line 1591:**
```r
dir.create(output_dir, recursive = TRUE)
```

**Status:** ✅ **Uses output_dir directly without modification**
- All plotting functions use `output_dir` parameter directly via `file.path(output_dir, ...)`
- No additional path manipulation or working directory assumptions
- Works correctly with both absolute and relative paths passed to it

---

## Path Construction Pattern Summary

### ✅ **Recommended Pattern for Scripts Run Independently**

Use **absolute paths** constructed from `PROJECT_ROOT`:

```r
output_dir <- file.path(PROJECT_ROOT, "STEP_1_Family_Selection/results/...")
```

**Examples:**
- `test_contour_plots.R` (standalone test script)
- Any other test/utility scripts that might be run directly

### ✅ **Recommended Pattern for Scripts Sourced from master_analysis.R**

Use **relative paths** starting from project root:

```r
output_dir <- file.path("STEP_1_Family_Selection/results/...")
```

**Examples:**
- `phase1_family_selection.R`
- `phase1_family_selection_parallel.R`
- Other scripts in STEP_X directories

**Rationale:** `master_analysis.R` guarantees `getwd()` is project root via `setwd(PROJECT_ROOT)` on startup.

---

## Testing & Validation

### Test Case 1: Run test_contour_plots.R from project root
```r
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")
source("STEP_1_Family_Selection/test_contour_plots.R")
```

**Expected Result:**
```
Output directory: /Users/.../Copula_Sensitivity_Analyses/STEP_1_Family_Selection/results/test/contour_plots/2005_G4_G5_MATHEMATICS
```

✅ **No directory duplication**

### Test Case 2: Run master_analysis.R
```r
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")
source("master_analysis.R")
```

**Expected Result:**
```
For each dataset and condition:
  STEP_1_Family_Selection/results/<dataset_id>/contour_plots/<year>_G<grade1>_G<grade2>_<content>/
```

✅ **Consistent path structure across all datasets**

---

## Additional Fixes Applied

### LaTeX Compilation Error Fixes (COMPLETED ✅)

**File:** `functions/copula_contour_plots.R`

**Issue:** Non-numeric values being passed to formatting functions caused LaTeX compilation errors:
```
LaTeX summary grid generation failed: error in evaluating the argument 'x' in selecting a method for function 'format': non-numeric argument to mathematical function
```

**Fix:** Enhanced `fmt_num()` and `fmt_int()` functions (lines 4740-4753) to validate input types:

```r
fmt_num <- function(x, digits = 3) {
  if (is.null(x)) return("--")
  if (length(x) == 0) return("--")
  if (!is.numeric(x)) return("--")  # NEW: Type check BEFORE processing
  if (is.na(x)) return("--")
  format(round(x, digits), nsmall = digits)
}
```

**Additional Safeguards:**
- CvM statistic handling (lines 4898-4903): Added null/numeric checks
- SGP correlation handling (line 4918): Added null/numeric checks before `is.na()`

---

## Impact Assessment

### ✅ No Breaking Changes
- All existing scripts continue to work
- Path construction pattern preserved where appropriate
- Only `test_contour_plots.R` modified for robustness

### ✅ Improved Robustness
- Test scripts can now be run from any working directory
- Absolute paths eliminate ambiguity
- LaTeX compilation errors resolved

### ✅ Maintained Consistency
- `master_analysis.R` working directory management unchanged
- Phase scripts continue to use relative paths as designed
- No changes required to production analysis workflows

---

## Recommendations

### For Future Development

1. **New standalone test scripts:** Always use `PROJECT_ROOT` for absolute path construction
2. **New phase scripts:** Use relative paths (sourced from `master_analysis.R`)
3. **Function parameters:** Accept `output_dir` and use it directly without modification
4. **Working directory:** Never use `setwd()` in subscripts; rely on `master_analysis.R` setup

### Path Validation Template

For any new script that needs to detect project root:

```r
# Detect project root
if (file.exists("functions/longitudinal_pairs.R") && file.exists("dataset_configs.R")) {
  PROJECT_ROOT <- getwd()
} else if (file.exists("../functions/longitudinal_pairs.R") && file.exists("../dataset_configs.R")) {
  PROJECT_ROOT <- normalizePath("..")
} else {
  stop("Cannot locate project root. Please run from project root or STEP_X directory.")
}

# Use absolute paths
output_dir <- file.path(PROJECT_ROOT, "STEP_1_Family_Selection/results/...")
```

---

## Files Modified

| File | Type | Status |
|------|------|--------|
| `STEP_1_Family_Selection/test_contour_plots.R` | Modified | ✅ Path construction fixed |
| `functions/copula_contour_plots.R` | Modified | ✅ LaTeX compilation fixes |
| `master_analysis.R` | Verified | ✅ No changes needed |
| `STEP_1_Family_Selection/phase1_family_selection.R` | Verified | ✅ No changes needed |

---

## Conclusion

**All path alignment issues have been resolved.** The framework now uses a consistent pattern:
- **Test scripts:** Absolute paths via `PROJECT_ROOT`
- **Phase scripts:** Relative paths from project root (enforced by `master_analysis.R`)
- **Functions:** Accept paths as parameters, no assumptions about working directory

✅ **Ready for production analysis runs across all 4 datasets**
