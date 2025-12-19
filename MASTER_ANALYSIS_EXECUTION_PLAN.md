# Master Analysis Execution Plan

**Generated:** 2025-12-16  
**Script:** `master_analysis.R`

---

## ✅ Current Configuration

### Datasets (Line 41)
```r
DATASETS_TO_RUN <- NULL  # Runs ALL 4 datasets
```

**Datasets that will be analyzed:**
1. ✅ `dataset_1` - Dataset 1 (Vertical Scale) - ~42 conditions
2. ✅ `dataset_2` - Dataset 2 (Non-Vertical Scale) - ~42 conditions
3. ✅ `dataset_3` - Dataset 3 (Assessment Transition) - ~85 conditions (exhaustive)
4. ✅ `dataset_4` - **Dataset 4 (Pandemic Analysis)** - ~45 conditions

**Total: ~214 conditions across all 4 datasets**

### Steps (Line 63)
```r
STEPS_TO_RUN <- 1  # Only STEP 1: Copula Family Selection
```

**STEP 1 will:**
- Test 6 copula families per condition (gaussian, t, clayton, gumbel, frank, comonotonic)
- Generate contour plots for each condition
- Calculate goodness-of-fit statistics
- Generate SGPc (copula-based Student Growth Percentiles) if enabled
- Produce ~214 × 6 = **~1,284 copula fits**

### Other Key Settings

**Goodness-of-Fit Testing (Line 91):**
```r
N_BOOTSTRAP_GOF <- 100  # Parametric bootstrap with 100 samples
```

**SGPc Calculation (Line 121):**
```r
CALCULATE_SGPC <- TRUE  # Will compute copula-based growth percentiles
```

**Plot Export (Line 76):**
```r
EXPORT_FORMATS <- c("pdf", "svg", "png")  # Multi-format export
EXPORT_DPI <- 300  # Publication quality
```

**Parallel Processing:**
- Automatically detected based on system (8+ cores → parallel enabled)

---

## Expected Runtime

### Sequential (No Parallel)
- **Dataset 1:** ~60-90 minutes (42 conditions)
- **Dataset 2:** ~60-90 minutes (42 conditions)
- **Dataset 3:** ~2-3 hours (85 conditions, exhaustive)
- **Dataset 4:** ~60-90 minutes (45 conditions, pandemic focused)
- **TOTAL: ~5-7 hours**

### Parallel (8+ cores)
- **Dataset 1:** ~10-15 minutes
- **Dataset 2:** ~10-15 minutes
- **Dataset 3:** ~20-30 minutes
- **Dataset 4:** ~10-15 minutes
- **TOTAL: ~50-75 minutes**

---

## Output Structure

```
STEP_1_Family_Selection/results/
├── dataset_1/
│   ├── phase1_copula_family_comparison.csv
│   ├── contour_plots/
│   │   ├── 2010_G4_G5_MATHEMATICS/
│   │   └── ... (42 conditions)
│   └── sgpc/
│       └── sgpc_all_conditions.rds
├── dataset_2/
│   ├── phase1_copula_family_comparison.csv
│   ├── contour_plots/
│   │   └── ... (42 conditions)
│   └── sgpc/
├── dataset_3/
│   ├── phase1_copula_family_comparison.csv
│   ├── contour_plots/
│   │   └── ... (85 conditions)
│   └── sgpc/
├── dataset_4/
│   ├── phase1_copula_family_comparison.csv
│   ├── contour_plots/
│   │   ├── 2019_G3_G5_MATHEMATICS/  # Pandemic pair
│   │   ├── 2017_G3_G5_MATHEMATICS/  # Baseline pair
│   │   └── ... (45 conditions)
│   └── sgpc/
└── dataset_all/
    ├── phase1_copula_family_comparison_all_datasets.csv  # COMBINED
    ├── phase1_decision.RData
    ├── phase1_summary.txt
    ├── phase1_*.{pdf,svg,png}  # Cross-dataset visualizations
    ├── analysis_manifest.json   # AI-consumable parameter recommendations
    └── analysis_manifest.md     # Human-readable recommendations
```

---

## Execution Command

```r
# From project root directory
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")

# Simply run:
source("master_analysis.R")
```

### Alternative: Customize Before Running

If you want to modify settings before execution:

```r
# Example: Run only datasets 1 and 4
DATASETS_TO_RUN <- c("dataset_1", "dataset_4")
STEPS_TO_RUN <- 1
source("master_analysis.R")

# Example: Run all datasets with more bootstrap iterations
DATASETS_TO_RUN <- NULL
N_BOOTSTRAP_GOF <- 1000  # Higher precision (slower)
source("master_analysis.R")

# Example: Skip GoF testing (faster)
DATASETS_TO_RUN <- NULL
N_BOOTSTRAP_GOF <- NULL
source("master_analysis.R")
```

---

## Post-Execution: Dataset 4 Pandemic Analysis

After `master_analysis.R` completes, run the pandemic-specific analysis for Dataset 4:

```r
source("STEP_1_Family_Selection/pandemic_analysis_dataset4.R")
```

This will generate:
- Parameter comparison tables (pandemic vs. baseline)
- Change visualizations (Δτ, Δdf, Δtail_dep)
- Summary report with interpretation

**Location:** `STEP_1_Family_Selection/results/dataset_4/pandemic_analysis/`

---

## Progress Monitoring

The script will output:

1. **Per-Dataset Progress:**
   ```
   ====================================================================
   DATASET 1 OF 4: Dataset 1 (Vertical Scale)
   ====================================================================
   ```

2. **Per-Condition Progress:**
   ```
   ====================================================================
   Condition 15 of 42
   Year span: 2 year(s) | G4 -> G6
   Years: 2010 -> 2012
   Content: MATHEMATICS
   ====================================================================
   ```

3. **Copula Fitting Progress:**
   ```
   Fitting all copula families...
   Using empirical ranks for family selection
   
   Testing 6 copula families...
   ✓ Fitted: gaussian (ρ=0.75, τ=0.68, AIC=-12345)
   ✓ Fitted: t (ρ=0.75, df=8, τ=0.68, AIC=-12525) <- BEST
   ```

4. **Dataset Completion:**
   ```
   ====================================================================
   COMPLETED ANALYSIS FOR: Dataset 1 (Vertical Scale)
   Dataset 1 of 4 complete
   ====================================================================
   ```

5. **Final Summary:**
   ```
   ====================================================================
   MASTER ANALYSIS COMPLETE
   ====================================================================
   Datasets analyzed: 4
     dataset_1
     dataset_2
     dataset_3
     dataset_4
   ```

---

## Validation Checklist

After execution completes, verify:

### Overall
- [ ] All 4 dataset directories created in `STEP_1_Family_Selection/results/`
- [ ] Combined results in `dataset_all/` directory
- [ ] No error messages in console output

### Per Dataset
- [ ] `phase1_copula_family_comparison.csv` exists and has correct row count
  - Dataset 1: ~252 rows (42 conditions × 6 families)
  - Dataset 2: ~252 rows
  - Dataset 3: ~510 rows (85 conditions × 6 families)
  - Dataset 4: ~270 rows (45 conditions × 6 families)
- [ ] `contour_plots/` has subdirectories for each condition
- [ ] `sgpc/sgpc_all_conditions.rds` exists

### Dataset 4 Specific
- [ ] 10 pandemic pairs present (2019_G*_*, 2018_G8_G11_*)
- [ ] 10 baseline pairs present (2017_G*_*, 2016_G8_G11_*)
- [ ] 25 strategic subset conditions

### Combined Results
- [ ] `dataset_all/phase1_copula_family_comparison_all_datasets.csv` has ~1,284 rows
- [ ] `dataset_all/phase1_decision.RData` exists
- [ ] `dataset_all/analysis_manifest.json` exists
- [ ] Visualizations generated (phase1_*.pdf)

---

## Quick R Validation Commands

```r
# Check dataset 1
d1 <- fread("STEP_1_Family_Selection/results/dataset_1/phase1_copula_family_comparison.csv")
nrow(d1) / 6  # Should be ~42

# Check dataset 4
d4 <- fread("STEP_1_Family_Selection/results/dataset_4/phase1_copula_family_comparison.csv")
nrow(d4) / 6  # Should be ~45
length(unique(d4[grepl("^2019_", condition_id), condition_id]))  # Should be 8 (pandemic)

# Check combined
dall <- fread("STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv")
nrow(dall) / 6  # Should be ~214
table(dall$dataset_id)  # Should show all 4 datasets

# Check t-copula dominance
dall[, .SD[which.min(aic)], by = condition_id][, .N, by = family]
# t-copula should win ~90-95% of conditions
```

---

## Troubleshooting

### Issue: "Dataset not found"
**Solution:** Verify data files exist in `Data/` directory
```bash
ls -lh Data/Copula_Sensitivity_Data_Set_*.Rdata
```

### Issue: Slow execution
**Solutions:**
1. Reduce bootstrap iterations: `N_BOOTSTRAP_GOF <- 100` or `NULL`
2. Run datasets individually: `DATASETS_TO_RUN <- "dataset_1"`
3. Use parallel processing (auto-enabled on 8+ core systems)

### Issue: Memory errors
**Solutions:**
1. Run datasets sequentially, not all at once
2. Increase R memory limit: `options(java.parameters = "-Xmx8g")`
3. Close other applications

### Issue: Contour plots not generating
**Check:**
1. GENERATE_CONTOUR_PLOTS setting (should be TRUE)
2. Sufficient disk space for plots (~500MB per dataset)

---

## Summary

✅ **Configuration Verified:**
- All 4 datasets will be analyzed (dataset_1, dataset_2, dataset_3, dataset_4)
- STEP 1 only (copula family selection)
- ~214 conditions, ~1,284 copula fits total
- Multi-format plot export enabled
- SGPc calculation enabled
- Goodness-of-fit testing with 100 bootstraps

✅ **Ready to Execute:**
```r
source("master_analysis.R")
```

✅ **Expected Outputs:**
- 4 dataset-specific results directories
- 1 combined results directory (dataset_all)
- ~214 condition subdirectories with contour plots
- Multi-dataset parameter recommendations

✅ **Follow-up:**
After completion, run pandemic analysis:
```r
source("STEP_1_Family_Selection/pandemic_analysis_dataset4.R")
```

---

**Status:** ✅ READY FOR EXECUTION  
**Estimated Total Runtime:** 50-75 minutes (parallel) or 5-7 hours (sequential)

---

**End of Execution Plan**
