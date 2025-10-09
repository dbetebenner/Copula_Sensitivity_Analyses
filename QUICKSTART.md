# Quick Start Guide: Two-Phase Copula Analysis

## Setup

Ensure you have the Colorado longitudinal data loaded:

```r
load("/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_Data_LONG.RData")
```

Required R packages:
```r
require(SGPdata)
require(data.table)
require(splines2)
require(copula)
require(grid)
```

---

## Phase 1: Copula Family Selection (30-60 minutes)

### Step 1: Run Family Selection Study

```r
setwd("/Users/conet/Research/Graphics_Visualizations/CDF_Investigations")
source("phase1_family_selection.R")
```

This will:
- Test all 5 copula families (Gaussian, t, Clayton, Gumbel, Frank)
- Across ~30-40 conditions (grade spans, content areas, cohorts)
- Save results to `results/phase1_copula_family_comparison.csv`

**Expected output**: ~200 copula fits, quick summary table

---

### Step 2: Analyze Results and Make Decision

```r
source("phase1_analysis.R")
```

This will:
- Generate selection frequency tables
- Create 5 diagnostic plots
- Apply decision criteria
- Save decision to `results/phase1_decision.RData`

**Expected output**: 
- `results/phase1_summary.txt` - Detailed findings
- `results/phase1_*.pdf` - 5 visualizations
- `results/phase1_decision.RData` - Phase 2 families

---

### Step 3: Review Phase 1 Results

```r
# Read summary
file.show("results/phase1_summary.txt")

# View selection plots
system("open results/phase1_selection_frequency.pdf")
system("open results/phase1_aic_by_span.pdf")

# Load decision
load("results/phase1_decision.RData")
cat("Phase 2 families:", paste(phase2_families, collapse = ", "), "\n")
cat("Rationale:", rationale, "\n")
```

**Decision point**: If results look good, proceed to Phase 2. Otherwise, modify Phase 1 configuration and re-run.

---

## Phase 2: Sensitivity Analysis (2-4 hours)

All Phase 2 scripts automatically load `results/phase1_decision.RData` and use the selected copula families.

### Option A: Run All Experiments

```r
# Grade span sensitivity
source("experiments/exp_1_grade_span.R")

# Sample size sensitivity
source("experiments/exp_2_sample_size.R")

# Content area sensitivity
source("experiments/exp_3_content_area.R")

# Cohort/year sensitivity
source("experiments/exp_4_cohort.R")

# Smoothing method sensitivity
source("experiments/exp_5_smoothing.R")
```

Each experiment saves results to its own `results/exp_*/` folder.

---

### Option B: Run Experiments Selectively

Pick the most relevant experiments for your research question:

**For TIMSS applications** (sample size is key):
```r
source("experiments/exp_2_sample_size.R")
```

**For multi-year growth** (grade span matters):
```r
source("experiments/exp_1_grade_span.R")
```

**For cross-content studies**:
```r
source("experiments/exp_3_content_area.R")
```

---

### T-Copula Deep Dive (if t-copula wins)

If Phase 1 selected t-copula, run detailed analysis:

```r
source("phase2_t_copula_deep_dive.R")
```

This provides:
- Degrees of freedom (ν) stability by sample size
- Tail dependence estimation precision
- Comparison with Gaussian baseline
- **Key output for TIMSS**: Expected precision at n ≈ 4,400

**Runtime**: ~1 hour (200 bootstrap iterations)

---

### Generate Final Report

After Phase 2 experiments complete:

```r
source("phase2_comprehensive_report.R")
```

This compiles:
- Phase 1 and Phase 2 results
- Summary tables (CSV)
- Final comprehensive text report
- Organized figure directory

**Outputs**:
- `results/FINAL_COMPREHENSIVE_REPORT.txt`
- `results/TABLE1_phase1_selection.csv`
- `results/TABLE2_parameters_by_span.csv`
- `results/TABLE3_parameter_stability.csv`
- `results/FINAL_FIGURES/` (all PDFs)

---

## Interpreting Results

### Phase 1 Key Questions

1. **Which family won?**
   - Check `phase1_summary.txt` → "Selection frequency by AIC"
   - Look for >75% dominance

2. **Does winner vary by grade span?**
   - Check "Selection by grade span" table
   - Hypothesis: t-copula advantage increases with time

3. **Is tail dependence significant?**
   - Check "Tail dependence patterns" table
   - t-copula: symmetric tail dependence
   - Clayton: lower tail only
   - Gumbel: upper tail only

### Phase 2 Key Questions

1. **What sample size is adequate?**
   - Check parameter stability plots
   - Look for CI width convergence
   - TIMSS benchmark: n ≈ 4,400

2. **Are results consistent across cohorts?**
   - Check exp_4 results
   - Look for systematic trends vs. noise

3. **Is ECDF smoothing robust?**
   - Check exp_5 results
   - I-spline should be stable default

---

## Typical Results (Expected)

Based on preliminary analyses:

### Phase 1
- **Winner**: t-copula (80-90% of conditions)
- **AIC advantage**: 10-20 points over Gaussian
- **Pattern**: Advantage increases with grade span

### Phase 2 (t-copula)
- **ν range**: 5-15 (moderate to heavy tails)
- **Tail dependence**: 0.10-0.25 (significant)
- **Sample size**: 
  - n = 500: SD(τ) ≈ 0.02
  - n = 1,000: SD(τ) ≈ 0.01
  - n = 4,000: SD(τ) ≈ 0.005

---

## Troubleshooting

### "Phase 1 decision not found"

If experiments show this warning:
```r
# Re-run Phase 1
source("phase1_family_selection.R")
source("phase1_analysis.R")
```

### "Insufficient data for this configuration"

Some grade/year combinations have missing data:
- Math grades 3-4 in 2003-2004 not administered
- This is normal, analyses skip these

### Long runtime

Phase 1: 30-60 min is normal (200+ copula fits)
Phase 2: 2-4 hours total for all experiments

To speed up:
- Reduce `N_BOOTSTRAP` (e.g., 50 instead of 100)
- Run subset of sample sizes
- Run experiments in parallel on different cores

---

## Minimal Analysis (30 minutes)

If time is limited:

```r
# Phase 1 only (identify winner)
source("phase1_family_selection.R")
source("phase1_analysis.R")
file.show("results/phase1_summary.txt")

# Phase 2: Just sample size experiment
source("experiments/exp_2_sample_size.R")

# Done! Check key results:
list.files("results/exp_G4to8_4yr/", pattern = "*.pdf")
```

---

## Complete Analysis (1 day)

For comprehensive investigation:

```r
# Day 1 Morning: Phase 1
source("phase1_family_selection.R")     # 30-60 min
source("phase1_analysis.R")             # 5 min

# Review at lunch
file.show("results/phase1_summary.txt")

# Day 1 Afternoon: Phase 2 Experiments
source("experiments/exp_1_grade_span.R")    # 30 min
source("experiments/exp_2_sample_size.R")   # 45 min
source("experiments/exp_3_content_area.R")  # 30 min
source("experiments/exp_4_cohort.R")        # 45 min
source("experiments/exp_5_smoothing.R")     # 30 min

# Day 1 Evening: Deep Dive (if needed)
source("phase2_t_copula_deep_dive.R")       # 60 min

# Day 2 Morning: Final Report
source("phase2_comprehensive_report.R")     # 5 min
file.show("results/FINAL_COMPREHENSIVE_REPORT.txt")
```

---

## Next Steps After Analysis

1. **Manuscript**:
   - Use `FINAL_COMPREHENSIVE_REPORT.txt` for methods/results
   - Tables ready in `TABLE*.csv`
   - Figures in `FINAL_FIGURES/`

2. **Presentation**:
   - Phase 1: Selection frequency plot
   - Phase 2: Parameter stability plot
   - Key table: Parameter precision by sample size

3. **Further Analysis**:
   - Modify experiment configurations for specific questions
   - Add new experiments following existing templates
   - Test on different datasets

---

## Getting Help

- **README.md**: Full documentation
- **Code comments**: Each script is heavily documented
- **Phase 1 summary**: Interpretation guidance
- **Function files**: See `functions/` for technical details

---

## Citation

When using this framework in publications:

```
Two-phase copula sensitivity analysis framework for longitudinal
educational assessment data. Colorado Department of Education
longitudinal data (2003-2013). Analysis framework developed
October 2025.
```

