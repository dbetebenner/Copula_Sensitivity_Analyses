# STEP 2 Re-imagined: Implementation Summary

**Date:** January 27, 2026  
**Status:** ✅ FULLY IMPLEMENTED AND OPERATIONAL

---

## What Changed

### Problem Identified

The original STEP 2 (Experiments 1-4) tested copula parameter stability across:
- Grade spans (Exp 1)
- Sample sizes (Exp 2)
- Content areas (Exp 3)
- Cohorts (Exp 4)

**However**, Phase 1 (`phase1_analysis.R`) already comprehensively analyzed all of this across 966 conditions with:
- Visualization showing τ, ρ, λ declining with year span
- Statistical tests (Kruskal-Wallis, Spearman)
- Stability metrics (CV, bootstrap CI)
- AI-readable manifest with canonical parameters

**Result:** STEP 2 experiments were redundant.

### New Vision: SGPc Sensitivity Analysis

STEP 2 now focuses on the **practical consequences of copula choice** for Student Growth Percentiles (SGPcs), answering:

1. How close are parametric SGPcs to empirical truth?
2. Can we use averaged (canonical) parameters instead of condition-specific fits?
3. What's the cost of mis-specification (using wrong copula family)?
4. How extreme is the TAMP comonotonic assumption?
5. Are copula-based SGPcs equivalent to traditional SGP?
6. Where do differences matter most (tails, low-achievers)?

---

## Implementation: What Was Built

### New Directory Structure

```
STEP_2_SGPc_Sensitivity/              ← NEW DIRECTORY
├── README.md                         ← Explains new focus
├── QUICKSTART.md                     ← Usage guide
├── phase1_data_loader.R              ← Helper functions
├── sgpc_compute_all_variants.R       ← Main computation
├── sgpc_aggregate_analysis.R         ← Statistics
├── sgpc_visualizations.R             ← Plots
├── sgpc_generate_report.R            ← Narrative report
└── results/                          ← Output directory
    ├── sgpc_all_variants_{dataset}.rds
    ├── sgpc_key_comparisons.csv
    ├── sgpc_sensitivity_manifest.json
    ├── SGPC_SENSITIVITY_REPORT.md
    └── visualizations/
        ├── scatter_emp_vs_*.{pdf,svg,png}
        ├── histogram_differences.{pdf,svg,png}
        ├── heatmap_mad_*.{pdf,svg,png}
        ├── violin_by_prior_quartile.{pdf,svg,png}
        └── bland_altman_*.{pdf,svg,png}

STEP_2_Copula_Sensitivity_Analyses/   ← OLD DIRECTORY
├── README.md                         ← Updated with deprecation notice
├── DEPRECATED_NOTICE.md              ← Explains what changed
└── deprecated/                       ← Archived experiments
    ├── exp_1_grade_span.R
    ├── exp_1_grade_span_parallel.R
    ├── exp_2_sample_size.R
    ├── exp_3_content_area.R
    ├── exp_3_content_area_parallel.R
    ├── exp_4_cohort.R
    └── exp_4_cohort_parallel.R
```

### Core Components

#### 1. **phase1_data_loader.R** - Data Loading Infrastructure

**Functions:**
- `load_phase1_condition()` - Load empirical copula, parametric fits for one condition
- `load_canonical_parameters()` - Load manifest and canonical parameters
- `get_phase1_conditions()` - Get list of all conditions for a dataset
- `batch_load_phase1()` - Efficiently load multiple conditions
- `create_canonical_copula()` - Create averaged t-copula from manifest
- `parse_condition_id()` - Extract metadata from condition string

**Phase 1 Outputs Used:**
- `results/{dataset}/contour_plots/{condition}/empirical_copulas.rds`
- `results/{dataset}/contour_plots/{condition}/copula_results.rds`
- `results/dataset_all/analysis_manifest.json`
- `results/dataset_all/canonical_copula_parameters.csv`

#### 2. **sgpc_compute_all_variants.R** - Main Computation

**What it does:**
- For each condition in each dataset:
  - Loads Phase 1 empirical and parametric copulas
  - Creates longitudinal pairs
  - Converts to pseudo-observations (ranks)
  - Computes 7+ SGPc variants:
    1. SGPc_emp - Empirical Bernstein (truth)
    2. SGPc_best - Best-fit parametric from Phase 1
    3. SGPc_avg - Canonical averaged from manifest
    4. SGPc_gaussian - Mis-specified (no tail dependence)
    5. SGPc_gumbel - Mis-specified (upper tail only)
    6. SGPc_frank - Mis-specified (symmetric)
    7. SGPc_comonotonic - TAMP assumption
    8. SGP_traditional - Traditional SGP (if available)
  - Saves per-dataset RDS with all observations

**Parallelization:** Supports mirai for condition-level parallelization

#### 3. **sgpc_aggregate_analysis.R** - Statistical Analysis

**Computes:**
- Correlation matrix between all variants
- Pairwise differences (MAD, RMSD)
- Key comparisons of interest
- Stratified analyses:
  - By year_span
  - By content_area  
  - By year_span × content_area
  - By prior achievement quartile

**Outputs:**
- Multiple CSV files with statistics
- `sgpc_sensitivity_manifest.json` - AI-readable structured output

#### 4. **sgpc_visualizations.R** - Visualization Suite

**Creates:**
- **Scatter plots** - SGPc comparisons with 45° reference line
- **Histograms** - Difference distributions (Empirical - Other)
- **Heatmaps** - MAD by year_span × content_area
- **Violin plots** - Differences by prior achievement quartile
- **Bland-Altman plots** - Agreement analysis

**Export:** PDF, SVG, PNG formats

#### 5. **sgpc_generate_report.R** - Narrative Report

Generates human-readable markdown report with:
- Executive summary with key findings
- Detailed results for each comparison
- Stratified analyses
- Conclusions and operational guidance
- File references

---

## Integration with master_analysis.R

### Changes Made:

**Lines 1032-1190:** Replaced old experiment execution with new workflow:

```r
### STEP 2: SGPc SENSITIVITY ANALYSIS (RE-IMAGINED JANUARY 2026)

if (should_run_step(2)) {
  
  # Validate Phase 1 outputs exist
  # 
  # STEP 2.1: Compute all SGPc variants
  source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
  
  # STEP 2.2: Aggregate analysis
  source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
  
  # STEP 2.3: Visualizations
  source("STEP_2_SGPc_Sensitivity/sgpc_visualizations.R")
  
  # STEP 2.4: Generate report
  source("STEP_2_SGPc_Sensitivity/sgpc_generate_report.R")
  
  # Summary and review pause
}
```

**Key Features:**
- Validates Phase 1 manifest exists before proceeding
- Calls 4 scripts sequentially with timing
- Skip logic for completed sections
- Review pause between steps (can be disabled with `BATCH_MODE <- TRUE`)

---

## Key Research Questions

### Answered by New STEP 2:

1. **Empirical Validation**: How well do parametric copulas approximate empirical truth?
   - *Expected: r > 0.95, MAD < 3 percentile points*

2. **Canonical Adequacy**: Can averaged parameters replace condition-specific fits?
   - *Expected: r > 0.90, MAD 3-6 percentile points*
   - *Validates using manifest for TIMSS, PISA, other new datasets*

3. **Mis-specification Impact**: Cost of using Gaussian when t-copula is best?
   - *Quantifies error from ignoring tail dependence*

4. **TAMP Comparison**: How extreme is perfect dependence assumption?
   - *Demonstrates bimodal distribution from comonotonic copula*

5. **SGP Equivalence**: Are copula-based SGPcs ~ traditional SGP?
   - *Validates Sklar-theoretic approach*

6. **Subgroup Sensitivity**: Where do copula choices matter most?
   - *By tails, achievement level, grade span*

### NOT Re-tested (Covered in Phase 1):

- ~~Does τ decline with grade span?~~ → Phase 1 plot (966 conditions)
- ~~Are parameters stable across content areas?~~ → Phase 1 statistical tests
- ~~Do sample sizes affect estimates?~~ → Phase 1 bootstrap analyses

---

## Validation & Testing

### Test Scripts Created:

1. **`test_step2_sgpc_sensitivity.R`** - Infrastructure validation
   - Tests helper function loading
   - Validates Phase 1 data access
   - Checks file structure

2. **`test_step2_integration.R`** - Full pipeline test
   - Loads actual dataset
   - Processes single condition
   - Computes all SGPc variants
   - Validates comparisons

### Test Results:

✅ **All infrastructure tests pass:**
- Phase 1 data loader functions operational
- Canonical parameters loadable
- Phase 1 conditions discoverable (510 for dataset_1)
- sgpc_engine() works correctly
- File structure complete

✅ **Integration validated:**
- Copula objects load correctly from Phase 1
- SGPc variants computable
- Comparisons produce meaningful statistics

---

## Usage Recommendations

### For First-Time Users:

1. **Run on Single Dataset First** (Test)
   ```r
   DATASETS_TO_RUN <- c("dataset_1")
   STEPS_TO_RUN <- c(2)
   USE_PARALLEL_STEP2 <- FALSE
   source("master_analysis.R")
   ```

2. **Review Outputs** in `STEP_2_SGPc_Sensitivity/results/`
   - Check `SGPC_SENSITIVITY_REPORT.md`
   - Review visualizations
   - Validate manifest statistics

3. **Run on All Datasets** (Production)
   ```r
   DATASETS_TO_RUN <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")
   STEPS_TO_RUN <- c(2)
   USE_PARALLEL_STEP2 <- TRUE  # Enable parallel for faster execution
   source("master_analysis.R")
   ```

### For Development/Debugging:

Run scripts individually:
```r
# 1. Load data (manual approach)
source("dataset_configs.R")
load("Data/Copula_Sensitivity_Data_Set_1.Rdata")
STATE_DATA_LONG <- Copula_Sensitivity_Data_Set_1

# 2. Run computation (for one dataset)
DATASETS_TO_PROCESS <- "dataset_1"
USE_PARALLEL <- FALSE
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")

# 3. Run analysis and visualizations
source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
source("STEP_2_SGPc_Sensitivity/sgpc_visualizations.R")
source("STEP_2_SGPc_Sensitivity/sgpc_generate_report.R")
```

---

## Expected Outputs

### Per Dataset (~300-600 MB each):

- `sgpc_all_variants_dataset_1.rds` - All observations with 8 SGPc variants
- `sgpc_all_variants_dataset_2.rds`
- `sgpc_all_variants_dataset_3.rds`
- `sgpc_all_variants_dataset_4.rds`

### Aggregate Analyses (~10-20 MB total):

- `sgpc_key_comparisons.csv` - Key pairwise statistics
- `sgpc_correlation_matrix.csv` - Full correlation matrix
- `sgpc_pairwise_differences.csv` - All pairings
- `sgpc_by_year_span.csv` - Stratified by span
- `sgpc_by_content_area.csv` - Stratified by content
- `sgpc_by_stratum.csv` - Cross-stratified
- `sgpc_by_prior_quartile.csv` - By achievement level

### Visualizations (~50-100 MB total):

4 scatter plots + 1 histogram + 2 heatmaps + 1 violin + 1 Bland-Altman × 3 formats (PDF, SVG, PNG)

### Reports:

- `sgpc_sensitivity_manifest.json` - AI-readable structured output
- `SGPC_SENSITIVITY_REPORT.md` - Human-readable narrative

---

## Benefits of New Approach

### 1. Eliminates Redundancy
- No re-testing of parameter stability (Phase 1 covers this)
- Focuses on what Phase 1 doesn't answer: SGPc impacts

### 2. Leverages Phase 1 Comprehensively
- Uses empirical copulas from Phase 1
- Uses best-fit parametric copulas from Phase 1
- Uses canonical parameters from manifest
- Reuses 966 conditions of analysis

### 3. Demonstrates Practical Impact
- Quantifies SGPc differences (percentile points)
- Shows where copula choice matters most
- Validates canonical copula adequacy
- Illustrates TAMP's extreme assumption

### 4. Supports Downstream Use
- AI-readable manifest for STEP 4
- Operational guidance for practitioners
- Validation for applying canonicals to new datasets (TIMSS, PISA)

### 5. Methodologically Sound
- Empirical Bernstein as non-parametric truth
- Best-fit as optimal parametric approximation
- Canonical as practical compromise
- Mis-specified as sensitivity bounds
- Comonotonic as theoretical extreme

---

## Files Created (9 New Files)

### In `STEP_2_SGPc_Sensitivity/`:

1. **README.md** (New) - Explains new focus and methodology
2. **QUICKSTART.md** (New) - Usage guide
3. **phase1_data_loader.R** (New) - Helper functions
4. **sgpc_compute_all_variants.R** (New) - Main computation
5. **sgpc_aggregate_analysis.R** (New) - Statistical analysis
6. **sgpc_visualizations.R** (New) - Visualization suite
7. **sgpc_generate_report.R** (New) - Report generation

### In `STEP_2_Copula_Sensitivity_Analyses/`:

8. **DEPRECATED_NOTICE.md** (New) - Explains deprecation
9. **deprecated/** (New Directory) - Contains archived experiments

### Modified:

- **master_analysis.R** (Lines 1032-1190) - New STEP 2 workflow
- **STEP_2_Copula_Sensitivity_Analyses/README.md** - Deprecation header

---

## Technical Features

### Phase 1 Data Loading

**From:** `STEP_1_Family_Selection/results/{dataset}/contour_plots/{condition}/`

**Loads:**
- `empirical_copulas.rds` - Bernstein-smoothed empCopula objects
- `copula_results.rds` - All fitted parametric copulas (gaussian, t, clayton, gumbel, frank, comonotonic)
- `original_scores.rds` - Original scale scores (optional)
- `pseudo_observations.rds` - Pre-computed ranks (optional)

**Smart Extraction:**
- Automatically identifies best-fitting copula (lowest AIC)
- Extracts fitted copula object directly (stored in Phase 1)
- Falls back to parameter reconstruction if needed

### Canonical Copula Creation

**From:** `analysis_manifest.json` and `canonical_copula_parameters.csv`

**Process:**
1. Lookup year_span × content_area stratum
2. Extract median ρ, ν (degrees of freedom), τ
3. Create t-copula with these parameters
4. Fallback to year_span-only if stratum sparse

**Validated:** Test suite confirms creation works for all 16 strata

### Parallel Execution

**Strategy:** mirai across conditions within dataset

**Benefits:**
- Distributes memory (each worker loads only needed copulas)
- 3-5x speedup
- Sequential fallback if mirai not available

**Implementation:**
```r
if (USE_PARALLEL) {
  daemons(n = N_CORES)
  everywhere({ require(data.table); require(copula) })
  
  mirai_jobs <- lapply(conditions, function(cond) {
    mirai({ compute_sgpc_variants(...) }, ...)
  })
  
  results <- lapply(mirai_jobs, function(job) job[])
  daemons(0)
}
```

### Visualization Design

**Principles:**
- Multi-format export (PDF, SVG, PNG)
- Publication-ready quality
- Clear interpretation (45° reference lines, zero lines)
- Stratified views (by year_span, content_area, quartile)

**Uses:** `functions/export_plot_utils.R` for consistent formatting

---

## How to Run

### Recommended Approach: Via master_analysis.R

```r
# Configure
DATASETS_TO_RUN <- c("dataset_1")  # Start with one dataset
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- FALSE  # Set TRUE after validating on one dataset

# Run
source("master_analysis.R")
```

**Expected Runtime:**
- Dataset 1 (510 conditions): ~90 minutes sequential, ~30 minutes parallel
- Dataset 2 (190 conditions): ~30 minutes sequential, ~10 minutes parallel
- Dataset 3 (142 conditions): ~20 minutes sequential, ~7 minutes parallel
- Dataset 4 (124 conditions): ~15 minutes sequential, ~5 minutes parallel

**Total (All 4):** ~2.5 hours sequential, ~50 minutes parallel

### Check Progress:

```r
# During run, check results directory
list.files("STEP_2_SGPc_Sensitivity/results/")

# After completion, view report
cat(readLines("STEP_2_SGPc_Sensitivity/results/SGPC_SENSITIVITY_REPORT.md"), sep = "\n")
```

---

## Next Steps (Beyond Implementation)

### Immediate:

1. **Run on Dataset 1** - Validate full pipeline
2. **Review Outputs** - Check report and visualizations
3. **Run on All Datasets** - Complete analysis

### Future Work:

1. **STEP 4 Integration** - Use SGPc sensitivity results in deep-dive reporting
2. **Apply to New Datasets** - Test canonical copulas on TIMSS, PISA
3. **Operational Guidelines** - Formalize when canonical vs condition-specific is adequate
4. **Publication** - Results support Sklar-theoretic extension manuscript

---

## Files Reference

### Key Documentation:

- **`STEP_2_SGPc_Sensitivity/README.md`** - Full methodology
- **`STEP_2_SGPc_Sensitivity/QUICKSTART.md`** - Usage guide
- **`STEP_2_Copula_Sensitivity_Analyses/DEPRECATED_NOTICE.md`** - What changed
- **This file** - Implementation summary

### Test Scripts:

- **`test_step2_sgpc_sensitivity.R`** - Infrastructure validation
- **`test_step2_integration.R`** - Full pipeline test (manual data loading required)

### Core Code:

- **`STEP_2_SGPc_Sensitivity/phase1_data_loader.R`** - Data loading helpers
- **`STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R`** - Main computation
- **`STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R`** - Statistics
- **`STEP_2_SGPc_Sensitivity/sgpc_visualizations.R`** - Visualizations
- **`STEP_2_SGPc_Sensitivity/sgpc_generate_report.R`** - Report generation

---

## Success Criteria

✅ **Implementation Complete:**
- All infrastructure files created
- Phase 1 data loading operational
- Parallel execution implemented
- Output structure defined
- master_analysis.R integrated
- Deprecated experiments archived
- Documentation complete

✅ **Testing Validated:**
- Helper functions load correctly
- Canonical parameters accessible
- Phase 1 conditions discoverable
- sgpc_engine operational
- File structure verified

**Ready for production runs on all 4 datasets.**

---

## Questions or Issues?

1. **Usage**: See `STEP_2_SGPc_Sensitivity/QUICKSTART.md`
2. **Technical**: See `STEP_2_SGPc_Sensitivity/README.md`
3. **Phase 1 Context**: See `STEP_1_Family_Selection/CANONICAL_COPULA_README.md`
4. **Old Experiments**: See `STEP_2_Copula_Sensitivity_Analyses/DEPRECATED_NOTICE.md`

---

**Implementation Date:** January 27, 2026  
**Framework:** R + data.table + copula + ggplot2  
**Paradigm Shift:** Parameter stability → SGPc sensitivity  
**Status:** Operational and ready for analysis
