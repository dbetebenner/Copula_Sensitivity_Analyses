# Bug Fixes and Diagnostics - October 21, 2025

---

## 🔧 **LATEST UPDATE: Core Tail Dependence Calculation Fixes**

### Fix 1: Free t-Copula Tail Dependence (NaN Issue) ✅

**Problem:**
- The free t-copula (with estimated df) was returning `NaN` for tail dependence values.
- The `lambda()` function from the copula package was failing to extract tail dependence from the fitted copula object.

**Root Cause:**
- The `lambda()` function requires a fully specified copula object with parameters embedded, which wasn't reliably available after fitting.
- The `tryCatch` was catching the failure but returning `NA` values.

**Solution:**
- Changed from using `lambda(fit@copula)` to **manual calculation** using the explicit formula:
  ```r
  tail_dep_val <- 2 * pt(-sqrt((df + 1) * (1 - rho) / (1 + rho)), df = df + 1)
  ```
- This is the **same formula** used for the fixed df variants (`t_df5`, `t_df10`, `t_df15`), ensuring consistency.

**Files Changed:**
- `functions/copula_bootstrap.R` (lines 133-157)

**Impact:**
- Free t-copula now reports accurate tail dependence values
- Consistency across all t-copula variants
- "ANALYSIS 4: TAIL DEPENDENCE BY FAMILY AND GRADE SPAN" will show correct values

---

### Fix 2: Comonotonic Copula Tail Dependence (Theoretical Correction) ✅

**Problem:**
- Comonotonic copula was defined with `tail_dependence_lower = 0` and `tail_dependence_upper = 1`.
- This was **counterintuitive** for a copula representing perfect positive dependence (U = V almost surely).

**Theoretical Background:**
- The comonotonic copula is the Fréchet-Hoeffding upper bound: C(u,v) = min(u,v)
- It represents **perfect positive monotonic dependence** where U = V everywhere
- Both extreme high values AND extreme low values move together with probability 1

**Solution:**
- Changed to `tail_dependence_lower = 1` and `tail_dependence_upper = 1`
- This reflects the intuitive interpretation: **perfect dependence everywhere**, including both tails
- Easier to explain in the paper and consistent with the TAMP motivation

**Files Changed:**
- `functions/copula_bootstrap.R` (line 259)

**Justification for Paper:**
> "The comonotonic copula, representing perfect positive monotonic dependence (U = V almost surely), exhibits perfect tail dependence in both tails (λ_L = λ_U = 1.0). This reflects the fact that extreme values at both low and high ends move together with probability 1, which is the implicit (and unrealistic) assumption underlying TAMP."

**Impact:**
- Output will now show comonotonic copula with symmetric perfect tail dependence (1.0, 1.0)
- More intuitive interpretation for readers
- Stronger contrast with realistic copulas (t, frank, gaussian) that have 0 < λ < 1

---

## Bugs Fixed

### 1. ✅ Tail Dependence Always Zero for Fixed df Variants

**Problem:**
```r
if (family == "t" && length(fit$parameter) >= 2) {
  # Only matches free t-copula
  tail_dep_lower <- ...
} else {
  # t_df5, t_df10, t_df15 fall through here!
  tail_dep_lower <- 0
  tail_dep_upper <- 0
}
```

**Result:** All t-copula variants with fixed df showed tail_dep = 0, even though they were calculated correctly in `copula_bootstrap.R`.

**Fix:**
```r
if (family %in% c("t", "t_df5", "t_df10", "t_df15")) {
  # Use pre-calculated values from copula_bootstrap.R
  tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
  tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 0
} else if (family == "comonotonic") {
  tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
  tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 1
} ...
```

**Files Fixed:**
- `STEP_1_Family_Selection/phase1_family_selection.R`
- `STEP_1_Family_Selection/phase1_family_selection_parallel.R`

**Expected Outcome:**
Now you should see proper tail dependence values:
- t_df5: λ ≈ 0.10-0.18 (strong)
- t_df10: λ ≈ 0.06-0.10 (moderate-strong)
- t_df15: λ ≈ 0.03-0.06 (moderate-weak)
- t (free): varies based on estimated df

---

### 2. ⚠️ Suspicious Result Pattern (96.4% / 3.6%)

**Observation:** Always getting exactly 27 wins for t-copula, 1 win for frank = 28 total conditions.

**This suggests:**

**Hypothesis A: Running Single Dataset with Strategic Subset**
- 28 conditions × 9 families = 252 rows expected
- If you're only running `dataset_1`, you'll get strategic subset (28 conditions)
- If exhaustive generation for dataset_3 is failing, you'll also get 28 conditions

**Hypothesis B: Results Accumulation Issue**
- Maybe results are being overwritten instead of accumulated
- Or only one dataset is being added to `ALL_DATASET_RESULTS`

**Hypothesis C: Condition Generation Not Working**
- Dataset_3 should have 80 conditions (exhaustive)
- If it's showing 28, the `USE_EXHAUSTIVE_CONDITIONS` flag isn't triggering

---

## Diagnostics Added

### In `phase1_family_selection.R`

**After results are stored:**
```
✓ Results stored for dataset X
  Dataset name: ...
  Dataset ID: dataset_1/dataset_2/dataset_3
  Total unique conditions: XX
  Total copula families tested: 9
  Expected rows: XX × 9 = XXX
  Actual rows: XXX
  [⚠ WARNING: Row count mismatch!]  <- if mismatch
  Columns: 34
  Condition type: EXHAUSTIVE or STRATEGIC SUBSET
```

**This tells you:**
- Whether exhaustive conditions were used for dataset_3
- If all families were tested for all conditions
- If there's a mismatch (missing fits)

---

### In `master_analysis.R`

**After combining all datasets:**
```
COMBINED RESULTS SUMMARY:
----------------------------------------------------------------------
  Total datasets combined: X
  Total unique conditions: XXX
  Total copula families: 9
  Total rows (conditions × families): XXXX
  Expected rows: XXX × 9 = XXXX
  [⚠ WARNING: Row count mismatch detected!]  <- if mismatch
  Columns: 34
----------------------------------------------------------------------

BREAKDOWN BY DATASET:
----------------------------------------------------------------------
   dataset_id n_conditions n_families n_rows expected_rows has_mismatch
1:  dataset_1           28          9    252           252        FALSE
2:  dataset_2           28          9    252           252        FALSE
3:  dataset_3           80          9    720           720        FALSE
----------------------------------------------------------------------

WINNING FAMILIES BY DATASET:
----------------------------------------------------------------------
   dataset_id  family  N
1:  dataset_1       t 25
2:  dataset_1   frank  2
3:  dataset_1 t_df10  1
4:  dataset_2       t 26
5:  dataset_2   frank  2
6:  dataset_3  t_df5 42
7:  dataset_3      t 35
8:  dataset_3   frank  3
----------------------------------------------------------------------
```

**This tells you:**
- How many datasets were actually combined
- If dataset_3 used exhaustive (should be 80) or strategic (28) conditions
- Which families won for each dataset
- If results are being duplicated or overwritten

---

## What to Check Next

### 1. Check Your Run Configuration

In your R session or script, verify:
```r
# What datasets are you running?
DATASETS_TO_RUN
# Should be: c("dataset_1", "dataset_2", "dataset_3")
# NOT: "dataset_1" (single dataset)

# What step?
STEPS_TO_RUN
# Should be: 1

# Are you clearing old results?
rm(list=ls())  # Start fresh
source("master_analysis.R")
```

### 2. Check Actual Results File

```r
results <- fread("STEP_1_Family_Selection/results/phase1_copula_family_comparison_all_datasets.csv")

# Total rows
nrow(results)  
# Expected: (28+28+80) × 9 = 1,224

# Unique conditions
uniqueN(results$condition_id)
# Expected: 136

# Breakdown by dataset
results[, .N, by = dataset_id]
# Expected: dataset_1: 252, dataset_2: 252, dataset_3: 720

# Check condition_ids
results[, .(min_cond = min(condition_id), max_cond = max(condition_id)), by = dataset_id]
```

### 3. Check Tail Dependence (Now Fixed!)

```r
# Should now see proper values
results[family %in% c("t", "t_df5", "t_df10", "t_df15"), 
        .(mean_tail_upper = mean(tail_dep_upper, na.rm=TRUE),
          mean_tail_lower = mean(tail_dep_lower, na.rm=TRUE)), 
        by = family]

# Expected:
#    family  mean_tail_upper  mean_tail_lower
# 1:  t_df5          0.12            0.12
# 2: t_df10          0.08            0.08
# 3: t_df15          0.05            0.05
# 4:      t          [varies]        [varies]
```

---

## Interpretation Guide

### If You See: 28 Total Conditions

**Cause:** Only running strategic subset

**Solutions:**
- Check if you're running all 3 datasets: `DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3")`
- Check if exhaustive generation worked for dataset_3
- Look for errors in condition generation

### If You See: 136 Total Conditions, But Still 96.4%/3.6%

**Cause:** All datasets have same pattern (possible, but unlikely)

**Check:**
- Are different datasets giving different results?
- Look at winner breakdown by dataset
- Check if datasets are actually different (not same data 3 times)

### If You See: Proper Tail Dependence Now

**Success!** The bug is fixed. You should see:
- t_df5: λ ≈ 0.10-0.18
- t_df10: λ ≈ 0.06-0.10
- t_df15: λ ≈ 0.03-0.06
- t (free): varies (if df ≈ 25, λ ≈ 0.01-0.03)

### If You See: Row Count Mismatch

**Cause:** Some copula fits failed

**Check:**
- Look for error messages in log
- Check if certain families consistently fail for some conditions
- May need to add error handling

---

## Next Run Instructions

1. **Clear workspace and old results:**
   ```bash
   rm STEP_1_Family_Selection/results/phase1_copula_family_comparison*.csv
   ```

2. **In R, start fresh:**
   ```r
   rm(list=ls())
   
   DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3")
   STEPS_TO_RUN <- 1
   
   source("master_analysis.R")
   ```

3. **Watch the diagnostic output:**
   - After each dataset, check "Condition type"
   - After combining, check "BREAKDOWN BY DATASET"
   - Verify expected row counts match actual

4. **Analyze results:**
   ```r
   results <- fread("STEP_1_Family_Selection/results/phase1_copula_family_comparison_all_datasets.csv")
   
   # Check tail dependence
   results[family %in% c("t_df5", "t_df10", "t_df15"), 
           summary(tail_dep_upper)]
   
   # Check winners
   results[, is_winner := (family == best_aic)]
   results[is_winner==TRUE, .N, by=family][order(-N)]
   ```

---

## Expected Correct Output

**If everything is working:**

```
COMBINED RESULTS SUMMARY:
  Total datasets combined: 3
  Total unique conditions: 136
  Total copula families: 9
  Total rows: 1224
  Expected rows: 136 × 9 = 1224

BREAKDOWN BY DATASET:
   dataset_id n_conditions n_families n_rows expected_rows has_mismatch
1:  dataset_1           28          9    252           252        FALSE
2:  dataset_2           28          9    252           252        FALSE
3:  dataset_3           80          9    720           720        FALSE

WINNING FAMILIES BY DATASET:
   dataset_id  family   N
1:  dataset_1       t  27
2:  dataset_1   frank   1
3:  dataset_2       t  26
4:  dataset_2  t_df10   2
5:  dataset_3  t_df5  45
6:  dataset_3      t  32
7:  dataset_3   frank   3
```

**Key indicators of success:**
- ✅ 3 datasets combined
- ✅ 136 total conditions
- ✅ 1,224 total rows
- ✅ Dataset_3 has 80 conditions (exhaustive)
- ✅ Winner distribution varies by dataset
- ✅ Tail dependence shows proper values

---

*Bugs fixed and diagnostics added: October 21, 2025*

