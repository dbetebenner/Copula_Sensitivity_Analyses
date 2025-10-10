# Step 3 Sensitivity Analyses - Implementation Summary

## Implementation Complete ✓

**Date**: 2025-10-10  
**Status**: Ready for execution

---

## Changes Made

### 1. Path Fixes (All 4 Experiments) ✓

Fixed incorrect relative paths in all experiment scripts:

**Files Modified:**
- `exp_1_grade_span.R`
- `exp_2_sample_size.R`
- `exp_3_content_area.R`
- `exp_4_cohort.R`

**Changes:**
```r
# BEFORE (INCORRECT)
source("../functions/longitudinal_pairs.R")
data = get_state_data()

# AFTER (CORRECT)
source("functions/longitudinal_pairs.R")
data = STATE_DATA_LONG
```

**Rationale**: `master_analysis.R` sets working directory to project root, so relative paths should not use `../`. Data is loaded centrally as `STATE_DATA_LONG`.

---

### 2. Parallel Versions Created ✓

Created parallel versions of 3 experiments (Exp 2 skipped due to limited benefit):

**New Files:**
- `exp_1_grade_span_parallel.R` - Parallelizes 6 grade spans (5-6x speedup)
- `exp_3_content_area_parallel.R` - Parallelizes 6 content configurations (5-6x speedup)
- `exp_4_cohort_parallel.R` - Parallelizes 10 cohorts (8-10x speedup)

**Key Features:**
- Automatic core detection (uses `N_CORES` from `master_analysis.R`)
- Sequential fallback if parallel disabled
- Per-condition error handling (failures don't crash entire experiment)
- Progress reporting and timing
- Clean cluster management

**Architecture:**
```r
# 1. Setup cluster
cl <- makeCluster(n_cores_use)
clusterExport(cl, c("STATE_DATA_LONG", "N_BOOTSTRAP", "COPULA_FAMILIES", ...))
clusterEvalQ(cl, { source functions... })

# 2. Define processor function
process_condition <- function(config) {
  # Create pairs
  # Fit copula
  # Bootstrap across sample sizes
  # Return results
}

# 3. Run in parallel
all_results_raw <- parLapply(cl, CONFIGS, process_condition)

# 4. Post-process and save
stopCluster(cl)
```

---

### 3. Master Analysis Integration ✓

Updated `master_analysis.R` to intelligently select parallel vs sequential scripts:

**Location**: Lines 567-602

**Logic:**
```r
if (USE_PARALLEL && exp$name != "exp_2_sample_size") {
  # Try parallel version first
  exp_file <- file.path("STEP_3_Sensitivity_Analyses", 
                       paste0(exp$name, "_parallel.R"))
  
  # Fall back to sequential if not found
  if (!file.exists(exp_file)) {
    exp_file <- file.path("STEP_3_Sensitivity_Analyses", 
                         paste0(exp$name, ".R"))
  }
} else {
  # Use sequential version
  exp_file <- file.path("STEP_3_Sensitivity_Analyses", 
                       paste0(exp$name, ".R"))
}
```

**Runtime Estimate Display:**
```r
if (USE_PARALLEL) {
  cat("Estimated time: 30-60 minutes (parallel)\n\n")
} else {
  cat("Estimated time: 3-6 hours (sequential)\n\n")
}
```

---

## Parallelization Strategy

### Why Parallelize Conditions (Not Sample Sizes)?

**Decision**: Parallelize across experimental conditions (grade spans, cohorts, content areas)

**Rationale:**
1. **Larger tasks** = Better efficiency (less overhead)
2. **Clean separation** = Each worker processes complete condition
3. **Bootstrap already efficient** = Within-fit parallelization in `fit_copula_from_pairs`
4. **Easy aggregation** = Combine independent results at the end

### Speedup Analysis

| Experiment | Conditions | Sequential Time | Parallel Time (10 cores) | Speedup |
|------------|-----------|----------------|-------------------------|---------|
| Exp 1: Grade Span | 6 spans | ~60 min | ~10-12 min | 5-6x |
| Exp 2: Sample Size | 2 configs | ~40 min | ~40 min (no parallel) | 1x |
| Exp 3: Content Area | 6 content pairs | ~60 min | ~10-12 min | 5-6x |
| Exp 4: Cohort | 10 cohorts | ~100 min | ~10-15 min | 8-10x |
| **Total** | | **~4-5 hours** | **~30-45 min** | **~6x** |

---

## Usage Instructions

### Option 1: Run Full Step 3 (Recommended)

```r
# In R console
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")

# Configure
USE_PARALLEL <- TRUE
N_CORES <- 10  # Or use: detectCores() - 1
STEPS_TO_RUN <- 3
SKIP_COMPLETED <- TRUE

# Run
source("master_analysis.R")
```

**Expected Output:**
```
####################################################################
### STEP 3: SENSITIVITY ANALYSES
####################################################################

Paper Section: Application → Sensitivity Analyses
Objective: Test copula parameter stability across conditions
Estimated time: 30-60 minutes (parallel)

====================================================================
PARALLEL PROCESSING ENABLED
====================================================================
Using 10 cores
Expected speedup: 5-6x

✓ Cluster initialized

Processing 6 conditions in parallel...

✓ Parallel processing complete
  Runtime: 10.34 minutes

[... detailed results ...]
```

---

### Option 2: Run Individual Experiment

```r
# Load data first
STATE_DATA_LONG <- fread("data/STATE_DATA_LONG.csv")

# Configure
USE_PARALLEL <- TRUE
N_CORES <- 10
N_BOOTSTRAP <- 100

# Run specific experiment
source("STEP_3_Sensitivity_Analyses/exp_1_grade_span_parallel.R")
```

---

### Option 3: Sequential Mode (No Parallel)

```r
# Configure
USE_PARALLEL <- FALSE  # Or just omit N_CORES
STEPS_TO_RUN <- 3

# Run
source("master_analysis.R")
```

**Automatic Fallback:**
- If `USE_PARALLEL = FALSE`, sequential versions used
- If parallel file missing, falls back to sequential
- If `N_CORES = 1`, runs sequentially

---

## Expected Outputs

After successful execution:

```
STEP_3_Sensitivity_Analyses/results/
├── exp_1_grade_span/
│   ├── grade_span_comparison.csv          # Summary table
│   ├── grade_span_comparison.pdf          # Comparison plots
│   ├── grade_span_experiment.RData        # Full workspace
│   ├── G4toG5_span1/
│   │   ├── n500_bootstrap_summary.csv
│   │   ├── n500_parameter_distributions.pdf
│   │   ├── n1000_*.csv/pdf
│   │   ├── n2000_*.csv/pdf
│   │   └── stability.pdf
│   ├── G4toG6_span2/
│   ├── G4toG7_span3/
│   ├── G4toG8_span4/
│   ├── G5toG6_span1/
│   └── G5toG8_span3/
│
├── exp_2_sample_size/
│   ├── G4to5_1yr/
│   │   ├── sample_size_sensitivity_summary.csv
│   │   ├── sample_size_experiment.RData
│   │   └── stability_symmetric.pdf
│   └── G4to8_4yr/
│       └── [same structure]
│
├── exp_3_content_area/
│   ├── content_area_comparison.csv
│   ├── content_area_comparison.pdf
│   ├── content_area_experiment.RData
│   ├── Math_G4to8/
│   ├── Reading_G4to8/
│   ├── Writing_G4to8/
│   ├── MathToReading_G4to8/
│   ├── ReadingToMath_G4to8/
│   └── MathToWriting_G4to8/
│
└── exp_4_cohort/
    ├── cohort_comparison.csv
    ├── cohort_comparison.pdf
    ├── cohort_experiment.RData
    ├── G4to5_2007to2008/
    ├── G4to5_2008to2009/
    ├── G4to5_2009to2010/
    ├── G4to5_2010to2011/
    ├── G4to5_2011to2012/
    ├── G4to5_2012to2013/
    ├── G5to6_2009to2010/
    ├── G5to6_2010to2011/
    ├── G5to6_2011to2012/
    └── G5to6_2012to2013/
```

**File Descriptions:**
- `*_comparison.csv` - Cross-condition summary statistics
- `*_comparison.pdf` - Comparison plots (tau by condition, CI widths, etc.)
- `*_experiment.RData` - Full R workspace for post-analysis
- Individual condition folders contain bootstrap results and diagnostics

---

## Key Findings (Expected)

Based on plan documentation:

### Experiment 1: Grade Span Effects
- **Finding**: Kendall's τ decreases with longer grade spans
  - 1 year: τ ≈ 0.71
  - 4 years: τ ≈ 0.52
- **Implication**: Dependence weakens over time (regression to mean)

### Experiment 2: Sample Size Effects
- **Finding**: Parameters stable by n ≈ 2,000
- **Implication**: Minimum sample size for reliable estimation

### Experiment 3: Content Area Generalizability
- **Finding**: Similar dependence across subjects
  - Math: τ ≈ 0.71 ± 0.03
  - Reading: τ ≈ 0.68 ± 0.03
  - Writing: τ ≈ 0.70 ± 0.03
- **Implication**: Copula structure generalizes across content areas

### Experiment 4: Temporal Stability / Cohort Effects
- **Finding**: < 5% variation across cohorts
- **Implication**: Copulas stable over time; can pool data across years

**Maps to Paper**: Section 5.3 (Sensitivity Analyses)

---

## Error Handling

### Robust Features:
1. **Per-condition try-catch** - One failure doesn't crash experiment
2. **Data availability checks** - Skip conditions with insufficient data
3. **Sequential fallback** - Automatically uses sequential if parallel unavailable
4. **Progress reporting** - Shows which conditions succeeded/failed
5. **Detailed error messages** - Logged for debugging

### Example Error Handling:
```r
process_condition <- function(config) {
  tryCatch({
    # Main processing logic
    return(list(success = TRUE, ...))
  }, error = function(e) {
    return(list(
      config = config,
      success = FALSE,
      error = e$message
    ))
  })
}

# Post-processing separates successes from failures
for (result in all_results_raw) {
  if (result$success) {
    all_results[[result$name]] <- result
  } else {
    failed_conditions[[length(failed_conditions) + 1]] <- result
    cat("✗ FAILED:", result$name, "- Error:", result$error, "\n")
  }
}
```

---

## Testing Checklist

### Before Full Run:
- [ ] Verify `STATE_DATA_LONG` is loaded
- [ ] Check Phase 1 decision exists (`STEP_1_Family_Selection/results/phase1_decision.RData`)
- [ ] Confirm parallel files exist (`.R` vs `_parallel.R`)
- [ ] Test with small config (1 condition, N_BOOTSTRAP=10)

### Small Test Run:
```r
# Quick test (5-10 minutes)
STATE_DATA_LONG <- fread("data/STATE_DATA_LONG.csv")
USE_PARALLEL <- TRUE
N_CORES <- 3
N_BOOTSTRAP <- 10  # Reduced for testing

# Modify exp_1_grade_span_parallel.R temporarily:
GRADE_SPANS <- list(
  list(grade_prior = 4, grade_current = 5, year_prior = "2010", span = 1)
)
SAMPLE_SIZES <- c(500)

source("STEP_3_Sensitivity_Analyses/exp_1_grade_span_parallel.R")
```

### Full Run Checklist:
- [ ] Results from Step 1 available
- [ ] `USE_PARALLEL = TRUE`
- [ ] `N_CORES = 10` (or appropriate)
- [ ] `N_BOOTSTRAP = 100`
- [ ] Sufficient disk space (~500 MB for results)
- [ ] ~45-60 minutes available for execution

---

## Troubleshooting

### Issue: "Error: object 'STATE_DATA_LONG' not found"
**Solution**: Data not loaded by master_analysis.R. Run:
```r
STATE_DATA_LONG <- fread("data/STATE_DATA_LONG.csv")
```

### Issue: "Phase 1 decision not found"
**Impact**: Uses all copula families (slower but still works)
**Solution**: Run Step 1 first, or continue with warning

### Issue: Parallel version not working
**Solution**: Falls back to sequential automatically. Check:
```r
file.exists("STEP_3_Sensitivity_Analyses/exp_1_grade_span_parallel.R")
```

### Issue: "Insufficient data for this configuration"
**Expected**: Some conditions may lack data (e.g., early cohorts)
**Action**: Check failed_conditions list; not a critical error

### Issue: Very slow execution
**Check**:
1. Is `USE_PARALLEL = TRUE`?
2. Is parallel version being used? (Check console output)
3. Are workers idle? (Activity Monitor / Task Manager)
4. Reduce `N_BOOTSTRAP` for testing

---

## File Versions

### Sequential Versions (Original):
- `exp_1_grade_span.R` - Fixed paths ✓
- `exp_2_sample_size.R` - Fixed paths ✓
- `exp_3_content_area.R` - Fixed paths ✓
- `exp_4_cohort.R` - Fixed paths ✓

### Parallel Versions (New):
- `exp_1_grade_span_parallel.R` - Created ✓
- `exp_2_sample_size.R` - No parallel version (use sequential)
- `exp_3_content_area_parallel.R` - Created ✓
- `exp_4_cohort_parallel.R` - Created ✓

**Note**: Exp 2 uses sequential version in both modes (limited parallelization benefit).

---

## Maintenance

### To Add New Experiment:
1. Create sequential version in `STEP_3_Sensitivity_Analyses/`
2. If ≥3 conditions, create parallel version
3. Add to `EXPERIMENTS_TO_RUN` in `master_analysis.R`

### To Modify Existing Experiment:
- **Sequential only**: Update both `.R` and `_parallel.R`
- **Parallel changes**: Update `_parallel.R` only
- **Both**: Ensure logic consistency

### To Change Parallelization:
- Modify `n_cores_use` detection logic in each `*_parallel.R`
- Or set `N_CORES` globally in `master_analysis.R`

---

## Performance Benchmarks

### System Specs (Example):
- MacBook Pro M1 Max
- 10 cores (8 performance + 2 efficiency)
- 32 GB RAM

### Expected Times:
| Configuration | Time |
|--------------|------|
| Sequential (1 core) | 3-6 hours |
| Parallel (3 cores) | 60-90 min |
| Parallel (6 cores) | 30-45 min |
| Parallel (10 cores) | 20-30 min |

**Note**: Speedup not perfectly linear due to:
- Bootstrap overhead
- Data loading/copying
- I/O operations (saving plots)
- Cluster setup time

---

## Next Steps

1. ✅ **Path fixes complete** - All experiments can access functions correctly
2. ✅ **Parallel versions created** - 3 experiments parallelized
3. ✅ **Master integration done** - Automatic selection logic in place
4. ⏭️ **Ready to run** - Execute with `source("master_analysis.R")`
5. ⏭️ **Validate results** - Check output directories and summary tables
6. ⏭️ **Proceed to Step 4** - Deep dive analysis on validated copulas

---

## Contact / Questions

For issues or questions about this implementation:
1. Check troubleshooting section above
2. Review error messages in console output
3. Inspect `failed_conditions` list for per-condition errors
4. Verify data availability with `table(STATE_DATA_LONG$GRADE, STATE_DATA_LONG$YEAR)`

---

**Implementation Date**: 2025-10-10  
**Status**: ✓ COMPLETE - Ready for Execution  
**Estimated Runtime**: 30-60 minutes (parallel) | 3-6 hours (sequential)
