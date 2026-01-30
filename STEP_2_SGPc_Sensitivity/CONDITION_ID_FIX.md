# Condition ID Naming Convention Fix

**Date**: January 28, 2026  
**Issue**: Pseudo-observations not being loaded (fallback to recomputing)  
**Root Cause**: Mismatch between condition ID generation and Phase 1 directory naming

---

## Problem

STEP 2 was **not** using Phase 1's pre-computed pseudo-observations, despite the update to support them. The terminal showed:

```
[computing pseudo-observations from scale scores]
```

Instead of the expected:

```
[using Phase 1 pseudo-observations]
```

---

## Root Cause

**Phase 1 Directory Naming**: Phase 1 saved results using `year_current` in the directory name:
- Example: `2017_G3_G4_MATHEMATICS/` (year_current=2017, prior=2016)

**STEP 2 Condition ID Generation**: `get_phase1_conditions()` was constructing condition IDs using `year_prior`:
- Generated: `2016_G3_G4_MATHEMATICS`
- Expected: `2017_G3_G4_MATHEMATICS`

**Result**: Directory lookups failed → Phase 1 data (including pseudo-observations) couldn't be found → fallback to recomputing

---

## Solution

### Fix 1: Update `get_phase1_conditions()` (lines 154-167)

**Before:**
```r
unique_conds <- unique(comparison[, .(year_prior, grade_prior, grade_current, content_area)])

condition_strings <- paste0(
  unique_conds$year_prior, "_",  # <-- WRONG: used year_prior
  "G", unique_conds$grade_prior, "_",
  "G", unique_conds$grade_current, "_",
  unique_conds$content_area
)
```

**After:**
```r
unique_conds <- unique(comparison[, .(year_current, grade_prior, grade_current, content_area)])

condition_strings <- paste0(
  unique_conds$year_current, "_",  # <-- FIXED: use year_current
  "G", unique_conds$grade_prior, "_",
  "G", unique_conds$grade_current, "_",
  unique_conds$content_area
)
```

### Fix 2: Update `parse_condition_id()` (lines 237-260)

Since condition IDs now use `year_current` in the first position, the parsing logic needed to be updated:

**Before:**
```r
year_prior <- as.integer(parts[1])  # <-- Assumed first part was year_prior
grade_prior <- as.integer(gsub("G", "", parts[2]))
grade_current <- as.integer(gsub("G", "", parts[3]))
year_span <- grade_current - grade_prior
```

**After:**
```r
year_current <- as.integer(parts[1])  # <-- First part is year_current
grade_prior <- as.integer(gsub("G", "", parts[2]))
grade_current <- as.integer(gsub("G", "", parts[3]))
year_span <- grade_current - grade_prior
year_prior <- year_current - year_span  # <-- Calculate year_prior
```

---

## Verification

### Test 1: Condition ID Generation

```r
source('STEP_2_SGPc_Sensitivity/phase1_data_loader.R')
conds <- get_phase1_conditions('dataset_4')
head(conds, 3)
# [1] "2017_G3_G4_MATHEMATICS" "2017_G3_G4_READING" "2017_G4_G5_MATHEMATICS"
```

✓ **Pass**: Now generates `2017_*` conditions (matches Phase 1 directories)

### Test 2: Directory Existence

```r
for (cond in conds[1:3]) {
  dir_path <- file.path('STEP_1_Family_Selection/results/dataset_4/contour_plots', cond)
  cat(cond, ':', file.exists(dir_path), '\n')
}
# 2017_G3_G4_MATHEMATICS : TRUE 
# 2017_G3_G4_READING : TRUE 
# 2017_G4_G5_MATHEMATICS : TRUE 
```

✓ **Pass**: All directories exist

### Test 3: Pseudo-observations Loading

```r
result <- load_phase1_condition('dataset_4', '2017_G3_G4_MATHEMATICS')
cat('Pseudo-observations:', !is.null(result$pseudo_observations), '\n')
cat('  Dimensions:', dim(result$pseudo_observations), '\n')
# Pseudo-observations: TRUE 
#   Dimensions: 13749 2 
```

✓ **Pass**: Pseudo-observations loaded successfully

---

## Expected Behavior After Fix

When STEP 2 runs, you should now see:

```
Processing condition: 2017_G3_G4_MATHEMATICS... [using Phase 1 pseudo-observations] done (n= 13749 )
```

Instead of:

```
Processing condition: 2016_G3_G4_MATHEMATICS... [computing pseudo-observations from scale scores] done (n= 13749 )
```

---

## Why This Matters

1. **Methodological Consistency**: SGPcs are now computed on the *exact same* (u, v) used to fit Phase 1 copulas
2. **Reproducibility**: Results are deterministic and traceable to Phase 1
3. **Efficiency**: No redundant computation (uses pre-computed 131KB files)
4. **Validation**: Ensures any SGPc differences are due to copula choice, not transformation differences

---

## Technical Details

### Phase 1 Naming Convention

Phase 1 uses `year_current` in directory names because:
- The directory represents a *cohort tested in year_current*
- Example: `2017_G3_G4_MATHEMATICS` means "students tested in 2017 (G4) who were in G3 the prior year"
- This is the natural way to organize results by testing year

### Why This Was Confusing

The CSV file (`phase1_copula_family_comparison.csv`) contains **both** `year_prior` and `year_current` columns:
- `year_prior`: 2016 (G3 testing year)
- `year_current`: 2017 (G4 testing year)

STEP 2 was using `year_prior` (chronologically first), but Phase 1 directories were named with `year_current` (testing year of current grade).

---

## Impact on Other Code

### Files Modified
1. `STEP_2_SGPc_Sensitivity/phase1_data_loader.R` (lines 158-165, 241-260)
2. `STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R` (line 111) - Added explicit `year_current` parameter

### Why sgpc_compute_all_variants.R Needed Updating

The call to `create_longitudinal_pairs()` was only passing `year_prior` and letting the function calculate `year_current`:

```r
# OLD (fragile - relied on calculation):
create_longitudinal_pairs(
  year_prior = as.character(cond_meta$year_prior),
  # year_current not passed - calculated as year_prior + grade_span
)
```

If R cached the OLD buggy version of `parse_condition_id()`, it would pass wrong `year_prior` → wrong calculated `year_current`.

**Fixed to explicitly pass both:**
```r
# NEW (robust - no calculation needed):
create_longitudinal_pairs(
  year_prior = as.character(cond_meta$year_prior),
  year_current = as.character(cond_meta$year_current),  # EXPLICIT
)
```

---

## Next Steps

1. **Re-run STEP 2**: The analysis should now successfully load Phase 1 pseudo-observations
2. **Verify Console Output**: Look for `[using Phase 1 pseudo-observations]` messages
3. **Check Results**: Compare SGPc variants to ensure proper consistency

---

## Questions?

- **Why not just change Phase 1?** → Phase 1 is already complete and its naming convention is logical (by testing year)
- **Could this break other code?** → No, all code uses `get_phase1_conditions()` which now returns correct IDs
- **What about year_prior vs year_current in outputs?** → `parse_condition_id()` now correctly calculates both from the condition ID
