# STEP 2 SGPc Sensitivity: Quick Start Guide

## Overview

The new STEP 2 assesses the **practical impact of copula choice on Student Growth Percentiles (SGPcs)** by computing multiple variants and comparing them.

## Prerequisites

1. **Phase 1 Complete**: Run Phase 1 first to generate:
   - `STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json`
   - `STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv`
   - Per-condition empirical and parametric copula fits

2. **Data Available**: Dataset files in `Data/` directory

## Quick Start: Run via master_analysis.R

### Option 1: Run New STEP 2 Only

```r
# Configure which dataset(s) to process
DATASETS_TO_RUN <- c("dataset_1")  # or c("dataset_1", "dataset_2", ...)

# Configure STEP 2
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- FALSE  # Set TRUE for mirai parallel (faster)

# Run
source("master_analysis.R")
```

**What happens:**
1. master_analysis.R loads the dataset using configuration system
2. Calls `STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R`
   - Loads Phase 1's **pre-computed pseudo-observations** for consistency
   - Computes 8 SGPc variants using Phase 1 copulas
3. Calls `STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R`
4. Calls `STEP_2_SGPc_Sensitivity/sgpc_visualizations.R`
5. Calls `STEP_2_SGPc_Sensitivity/sgpc_generate_report.R`

**Outputs** in `STEP_2_SGPc_Sensitivity/results/`:
- `sgpc_all_variants_{dataset_id}.rds` - Per-observation SGPc variants
- `sgpc_key_comparisons.csv` - Summary statistics
- `sgpc_sensitivity_manifest.json` - AI-readable output
- `SGPC_SENSITIVITY_REPORT.md` - Narrative report
- `visualizations/` - Plots in PDF, SVG, PNG formats

**Runtime:**
- Sequential: 3-6 hours per dataset
- Parallel (mirai): 60-120 minutes per dataset

### Option 2: Run All Steps Sequentially

```r
# Run complete pipeline: Phase 1 → STEP 2 → STEP 3 → STEP 4
DATASETS_TO_RUN <- c("dataset_1")
STEPS_TO_RUN <- c(1, 2, 3, 4)
USE_PARALLEL <- TRUE          # Phase 1 parallel
USE_PARALLEL_STEP2 <- FALSE   # STEP 2 sequential (recommended for first run)

source("master_analysis.R")
```

## Advanced: Run Scripts Individually

### Manual Workflow (For Development/Testing)

**Step 1: Load Data and Configuration**
```r
# Load dataset configuration
source("dataset_configs.R")
DATASET_CONFIGS <- DATASETS

# Load specific dataset
dataset_config <- DATASET_CONFIGS[["dataset_1"]]
load(dataset_config$local_path)
STATE_DATA_LONG <- get(dataset_config$rdata_object_name)
```

**Step 2: Compute SGPc Variants**
```r
# Set which datasets to process
DATASETS_TO_PROCESS <- "dataset_1"

# Configure parallel mode
USE_PARALLEL <- FALSE

# Run computation
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
```

**Step 3: Aggregate Analysis**
```r
source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
```

**Step 4: Create Visualizations**
```r
source("STEP_2_SGPc_Sensitivity/sgpc_visualizations.R")
```

**Step 5: Generate Report**
```r
source("STEP_2_SGPc_Sensitivity/sgpc_generate_report.R")
```

## Configuration Options

### In master_analysis.R or environment:

```r
# Which datasets to analyze
DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")

# Parallel processing for STEP 2
USE_PARALLEL_STEP2 <- FALSE  # TRUE = mirai parallel, FALSE = sequential

# Skip completed steps (for resuming interrupted runs)
SKIP_COMPLETED_STEP2 <- FALSE

# Use SGP-augmented data (if available)
USE_SGP_DATA <- TRUE  # Loads traditional SGP values if available
```

### In sgpc_compute_all_variants.R:

```r
# Override default datasets
DATASETS_TO_PROCESS <- c("dataset_1")

# Parallel mode
USE_PARALLEL <- FALSE
N_CORES <- parallel::detectCores() - 1
```

## Outputs Explained

### 1. Per-Observation Variants (`sgpc_all_variants_{dataset_id}.rds`)

data.table with columns:
- `condition_id` - e.g., "2021_G4_G5_MATHEMATICS"
- `ID` - Student identifier
- `SCALE_SCORE_PRIOR`, `SCALE_SCORE_CURRENT` - Original scores
- `u`, `v` - Pseudo-observations (ranks)
- `sgpc_emp` - Empirical Bernstein copula (truth)
- `sgpc_best` - Best-fit parametric from Phase 1
- `sgpc_avg` - Canonical averaged from manifest
- `sgpc_gaussian` - Mis-specified (no tail dependence)
- `sgpc_gumbel` - Mis-specified (upper tail only)
- `sgpc_frank` - Mis-specified (symmetric)
- `sgpc_comonotonic` - TAMP assumption (perfect dependence)
- `sgp_traditional` - Traditional SGP (if available)

### 2. Key Comparisons (`sgpc_key_comparisons.csv`)

Critical pairwise statistics:
- Empirical vs Best-fit: Validates parametric approach
- Empirical vs Canonical: Validates averaged parameters
- Empirical vs Gaussian: Impact of ignoring tail dependence
- Empirical vs Comonotonic: Impact of TAMP assumption

Metrics: correlation, MAD (mean absolute difference), RMSD

### 3. Stratified Analyses

- `sgpc_by_year_span.csv` - By time between assessments
- `sgpc_by_content_area.csv` - By subject
- `sgpc_by_stratum.csv` - Cross-stratified (year_span × content_area)
- `sgpc_by_prior_quartile.csv` - By achievement level

### 4. Manifest (`sgpc_sensitivity_manifest.json`)

AI-readable structured output with:
- Metadata (n observations, conditions, datasets)
- Summary statistics (correlations, MAD, RMSD)
- Stratified results
- Key findings (programmatically generated)

### 5. Report (`SGPC_SENSITIVITY_REPORT.md`)

Human-readable narrative with:
- Executive summary
- Detailed results for each comparison
- Stratified analyses
- Conclusions and operational guidance
- References to output files

## Troubleshooting

### Error: "Phase 1 manifest not found"

**Solution:** Run Phase 1 analysis first:
```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```

### Error: "Dataset file not found"

**Issue:** Data files not in expected location

**Solution:** Use master_analysis.R (handles paths automatically) or check `dataset_configs.R` for correct paths

### Warning: "Could not load Phase 1 results for condition X"

**Cause:** Phase 1 didn't process that condition (insufficient data, etc.)

**Impact:** That condition will be skipped, others will still process

**Action:** Check Phase 1 logs; this is usually expected for edge cases

### Memory Issues (Large Datasets)

**Symptom:** R session crashes or runs out of memory

**Solutions:**
1. Process datasets one at a time (don't load all 4 simultaneously)
2. Enable parallel mode: `USE_PARALLEL_STEP2 <- TRUE` (distributes memory across cores)
3. Increase system RAM allocation to R

## Performance Tips

1. **Use Parallel Mode**: Set `USE_PARALLEL_STEP2 <- TRUE` for 3-5x speedup
2. **Process Sequentially Across Datasets**: Don't try to load all datasets at once
3. **Skip Completed Sections**: Set `SKIP_COMPLETED_STEP2 <- TRUE` to resume interrupted runs
4. **Subsample for Testing**: Modify code to process fewer conditions initially

## Integration with STEP 4

STEP 4 (Deep Dive Reporting) will use STEP 2 outputs:
- Load `sgpc_sensitivity_manifest.json` for key findings
- Reference visualizations in final report
- Provide operational recommendations based on sensitivity analyses

## Questions?

- **Technical Details**: See `README.md` in this directory
- **Phase 1 Context**: See `../STEP_1_Family_Selection/CANONICAL_COPULA_README.md`
- **Deprecated Experiments**: See `../STEP_2_Copula_Sensitivity_Analyses/DEPRECATED_NOTICE.md`
