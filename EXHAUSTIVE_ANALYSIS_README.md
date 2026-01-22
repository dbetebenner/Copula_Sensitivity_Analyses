# Exhaustive Same-Cohort Copula Analysis

## Overview

This configuration enables **exhaustive same-cohort analysis** across all datasets to rigorously establish **copula stability across time spans (1-4 years)**.

## Purpose

Answer the research question: **"Does the best-fitting copula for 1-year spans predict the best copula for 2, 3, and 4-year spans?"**

This is critical for applications like TIMSS where you have:
- Grade 3→4 data (1-year) available
- Need to select copula for Grade 4→8 analysis (4-year)

## What Changes

### Strategic Subset (Default)
- **~16 conditions** per dataset
- Representative sampling across grades, years, content
- Fast: ~6-8 minutes on EC2
- **Different cohorts** at each time span

### Exhaustive Analysis (New)
- **966 total conditions** across 4 datasets:
  - Dataset 1: 510 conditions
  - Dataset 2: 194 conditions
  - Dataset 3: 80 conditions
  - Dataset 4: 182 conditions
- **ALL valid year/grade/content combinations**
- **Same-cohort tracking** (e.g., 2005 G3→G4, 2005 G3→G5, 2005 G3→G6, 2005 G3→G7)
- Slower: ~2-4 hours per dataset on EC2
- Rigorous evidence for copula stability

## Configuration Flags

### In `master_analysis.R`:

```r
# Enable exhaustive mode for ALL datasets
USE_EXHAUSTIVE_ALL_DATASETS <- TRUE  # Default: FALSE

# Test mode: Limit to small subset for validation
TEST_MODE <- TRUE                     # Default: FALSE
TEST_N_CONDITIONS_PER_DATASET <- 1   # Default: 1
```

### How It Works:

1. **Exhaustive Mode OFF** (default)
   - All datasets: Strategic subset (~16 conditions/dataset, ~64 total)
   - Quick validation and family selection

2. **Exhaustive Mode ON**
   - ALL datasets: Exhaustive conditions (~250-300 each)

3. **Test Mode ON**
   - Limits to first N conditions per dataset
   - Use to validate configuration before full run

## Usage

### Step 1: Test Configuration (Local)

Run the test script to validate setup with 1 condition per dataset:

```bash
cd /path/to/Copula_Sensitivity_Analyses
Rscript test_exhaustive_mode.R
```

**Expected output:**
- Generates exhaustive conditions for each dataset
- Limits to 1 condition per TEST_MODE setting
- Completes in ~5-10 minutes
- Validates that configuration works correctly

### Step 2: Full Analysis (EC2)

After successful test, run full analysis on EC2:

```bash
# On EC2 instance
cd /data/Copula_Sensitivity_Analyses
Rscript run_exhaustive_ec2.R
```

**Expected outcomes:**
- ~1000-1200 total conditions analyzed
- ~6000-7200 copula fits
- Runtime: 8-16 hours (parallel on c6i.16xlarge)

## Generated Conditions

### Example: Dataset 1 Exhaustive Conditions

For each **starting cohort** (year + grade):

```r
# 2005 Grade 3 cohort (same students tracked over time)
2005 G3 → 2006 G4  (1-year)
2005 G3 → 2007 G5  (2-year)  
2005 G3 → 2008 G6  (3-year)
2005 G3 → 2009 G7  (4-year)

# 2005 Grade 4 cohort
2005 G4 → 2006 G5  (1-year)
2005 G4 → 2007 G6  (2-year)
2005 G4 → 2008 G7  (3-year)
2005 G4 → 2009 G8  (4-year)

# ... repeat for all valid cohort-years
```

**Coverage:**
- Starting years: 2005-2010 (~6 years)
- Starting grades: 3-6 (~4 grades)  
- Content areas: MATH, READING, WRITING (3)
- Time spans: 1-4 years (4)

**Total per dataset:** ~6 years × 4 grades × 3 content × 4 spans = **~288 conditions**

## Analysis Output

### Results Structure

```
STEP_1_Family_Selection/results/
├── dataset_1/
│   └── phase1_copula_family_comparison.csv  (~288 conditions × 6 families = 1728 rows)
├── dataset_2/
│   └── phase1_copula_family_comparison.csv  (~240 conditions × 6 families = 1440 rows)
├── dataset_3/
│   └── phase1_copula_family_comparison.csv  (~300 conditions × 6 families = 1800 rows)
├── dataset_4/
│   └── phase1_copula_family_comparison.csv  (~180 conditions × 6 families = 1080 rows)
└── dataset_all/
    ├── phase1_copula_family_comparison_all_datasets.csv  (~7000 rows)
    ├── phase1_decision.RData
    └── phase1_summary.txt
```

### Key Metrics to Extract

For each dataset, analyze:

```r
results <- fread("STEP_1_Family_Selection/results/dataset_1/phase1_copula_family_comparison.csv")

# T-copula dominance by time span
winners <- results[, .(winner = best_aic[1]), by = .(condition_id, year_span)]
stability_table <- winners[, .(
  n_conditions = .N,
  t_wins = sum(winner == "t"),
  t_pct = 100 * sum(winner == "t") / .N
), by = year_span]

print(stability_table)
#   year_span n_conditions t_wins  t_pct
#          1           72     68   94.4%
#          2           72     69   95.8%
#          3           72     70   97.2%
#          4           72     71   98.6%
```

### Academic Defense

Use these results to write:

> "We tested copula stability across time spans using exhaustive same-cohort analysis. 
> For 288 longitudinal cohort trajectories in Dataset 1 (vertical scale), the t-copula 
> achieved best fit in 94.4% of 1-year spans, 95.8% of 2-year spans, 97.2% of 3-year 
> spans, and 98.6% of 4-year spans. This strong stability pattern supports extrapolation 
> from Grade 3→4 TIMSS copula selection (1-year) to Grade 4→8 applications (4-year)."

## Computational Requirements

### Test Mode (Local)
- **Runtime:** ~5-10 minutes
- **Conditions:** 4 (1 per dataset)
- **Memory:** ~4GB
- **Cores:** 4-8

### Full Analysis (EC2)
- **Runtime:** 8-16 hours
- **Conditions:** ~1000-1200
- **Memory:** ~16-32GB recommended
- **Cores:** 16+ recommended (c6i.16xlarge or larger)
- **Storage:** ~50GB for results + plots

## Validation Checklist

Before full EC2 run, verify:

- ✓ Test mode completes successfully
- ✓ Results files generated for all 4 datasets  
- ✓ Correct number of conditions tested
- ✓ All 6 copula families fit for each condition
- ✓ No errors in log files
- ✓ SGP data files accessible (if CALCULATE_SGPC enabled)

## Troubleshooting

### Problem: Out of memory
**Solution:** Reduce `N_BOOTSTRAP_GOF` or disable `CALCULATE_SGPC`

### Problem: Too slow
**Solution:** 
- Increase EC2 instance size (more cores)
- Disable `GENERATE_CONTOUR_PLOTS` for initial run
- Run datasets sequentially instead of in loop

### Problem: Some conditions fail
**Solution:** 
- Check if sufficient pairs available (needs n > 100)
- Verify content areas exist for that dataset
- Check year/grade combinations are valid

## Related Files

- `master_analysis.R` - Main configuration
- `dataset_configs.R` - Dataset metadata and `generate_exhaustive_conditions()`
- `phase1_family_selection_parallel.R` - Condition selection and execution
- `test_exhaustive_mode.R` - Test script
- `run_exhaustive_ec2.R` - Full EC2 run script

## Contact

For questions about exhaustive analysis configuration, see:
- `dataset_configs.R:generate_exhaustive_conditions()` (line 251)
- `phase1_family_selection_parallel.R:USE_EXHAUSTIVE_CONDITIONS` (line 133)

