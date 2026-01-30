# DEPRECATED: Parameter Stability Experiments

**Date Deprecated:** January 27, 2026

**Reason:** Phase 1 (`phase1_analysis.R`) already comprehensively analyzed copula parameter stability across 966 conditions, including:
- Grade span effects (τ, ρ, λ declining with time)
- Sample size effects (bootstrap uncertainty quantification)
- Content area differences (statistical tests and effect sizes)
- Cohort/temporal stability

**What Replaced This:**

STEP 2 has been re-imagined to focus on **SGPc sensitivity** - the practical impact of copula choice on Student Growth Percentiles.

**New Location:** `../STEP_2_SGPc_Sensitivity/`

**New Scripts:**
- `sgpc_compute_all_variants.R` - Compute 7+ SGPc variants per observation
- `sgpc_aggregate_analysis.R` - Aggregate statistics and comparisons
- `sgpc_visualizations.R` - Comprehensive visualization suite
- `sgpc_generate_report.R` - Narrative report generation

**See:** `../STEP_2_SGPc_Sensitivity/README.md` for details

---

## Deprecated Experiments (Archived in `deprecated/`)

These experiments tested copula parameter stability but are now redundant:

1. **`exp_1_grade_span.R`** - Grade span sensitivity
   - **Question:** Does τ decline with grade span?
   - **Answer:** YES (Phase 1 plot shows clear decline across 966 conditions)
   
2. **`exp_2_sample_size.R`** - Sample size effects
   - **Question:** Are parameters stable across sample sizes?
   - **Answer:** YES at n>500 (Phase 1 bootstrap analysis)
   
3. **`exp_3_content_area.R`** - Content area comparison
   - **Question:** Do content areas show similar dependence?
   - **Answer:** Similar patterns, quantified in Phase 1 statistical tests
   
4. **`exp_4_cohort.R`** - Cohort effects
   - **Question:** Are results stable across cohorts?
   - **Answer:** YES (Phase 1 temporal consistency analysis)

---

## Historical Context

These experiments were originally designed to validate copula robustness before Phase 1 was enhanced with:
- Cross-stratified canonical parameters (year_span × content_area)
- Comprehensive statistical testing (Kruskal-Wallis, Spearman)
- Stability metrics (CV, bootstrap CI) for 966 conditions
- AI-readable manifest with parameter recommendations

With Phase 1's comprehensive coverage, re-testing parameter stability in STEP 2 became redundant.

---

## If You Need to Run Old Experiments

The old code is preserved in `deprecated/` and can still be run:

```r
# Run old experiment (not recommended)
source("STEP_2_Copula_Sensitivity_Analyses/deprecated/exp_1_grade_span.R")
```

**However**, we strongly recommend:
1. Review Phase 1 results: `STEP_1_Family_Selection/results/dataset_all/`
2. Use new STEP 2: `STEP_2_SGPc_Sensitivity/`
3. Cite Phase 1's comprehensive analysis for parameter stability questions

---

**For Questions:** See `../STEP_2_SGPc_Sensitivity/README.md` or Phase 1 documentation
