# STEP 2 Migration Guide

## For Users of the Old STEP 2 Experiments

If you were using the original STEP 2 experiments (Exp 1-4), this guide explains what changed and how to adapt.

---

## Quick Summary

**Old STEP 2:** Tested copula parameter stability (τ, ρ, ν) across grade spans, sample sizes, content areas, and cohorts

**New STEP 2:** Tests SGPc sensitivity - how copula choice affects Student Growth Percentiles

**Why Changed:** Phase 1 already comprehensively analyzed parameter stability across 966 conditions

---

## Publication Pipeline Update (Current)

In addition to Step 2.1-2.4, current STEP 2 includes Step 2.5 publication figure generation via:

```r
source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
```

Current panel naming uses:
- `D` (rank agreement),
- `E` (decile stability),
- `D2` (group bucket stability).

See:
- `STEP_2_SGPc_Sensitivity/PUBLICATION_FIGURE_USAGE.md`
- `STEP_2_SGPc_Sensitivity/PUBLICATION_FIGURE_IMPLEMENTATION.md`

---

## Mapping: Old Questions → New Answers

### Old Experiment 1: Grade Span Sensitivity

**Question:** Does Kendall's τ decline with grade span?

**Old Approach:** Fit copulas for spans 1-4, bootstrap CI, compare τ estimates

**Now Covered By:** 
- **Phase 1 Analysis**: `phase1_analysis.R` lines 850-1100
- **Visualization**: `phase1_copula_selection_by_condition.pdf` shows τ, ρ, λ by span
- **Data**: 966 conditions (not just 7-10 configs)

**If You Need This:** View Phase 1 results in `STEP_1_Family_Selection/results/dataset_all/`

---

### Old Experiment 2: Sample Size Effects

**Question:** Are copula parameters stable across sample sizes?

**Old Approach:** Test n=500, 1000, 2000, full dataset

**Now Covered By:**
- **Phase 1 Bootstrap**: Already uses n=100 bootstrap samples per condition
- **Phase 1 CV Metrics**: Coefficient of variation quantifies stability
- **Canonical Parameters**: CI bounds show uncertainty

**If You Need This:** 
- Review `canonical_copula_parameters.csv` columns: `rho_cv`, `tau_cv`, `df_cv`
- Check `phase1_parameter_stability_heatmap.pdf`

---

### Old Experiment 3: Content Area Comparison

**Question:** Do Math, Reading, etc. show similar dependence patterns?

**Old Approach:** Fit copulas for each content area, compare parameters

**Now Covered By:**
- **Phase 1 Statistical Tests**: Kruskal-Wallis test for content area effect
- **Phase 1 Effect Sizes**: η² for content area variance
- **Phase 1 Visualization**: Faceted by content area

**If You Need This:**
- Review `statistical_tests.csv` → content_area row
- View facets in `phase1_copula_selection_by_condition.pdf`

---

### Old Experiment 4: Cohort Effects

**Question:** Are copula parameters stable across different years?

**Old Approach:** Compare 2005 vs 2009 vs 2013 cohorts

**Now Covered By:**
- **Phase 1 Temporal Coverage**: 966 conditions span multiple years/cohorts
- **Phase 1 CV Metrics**: Within-stratum stability includes temporal variation

**If You Need This:** Review Phase 1 results by stratum (includes all years)

---

## What New STEP 2 Adds (Not in Phase 1)

### 1. SGPc Empirical Validation

**Question:** How close are parametric SGPcs to empirical truth?

**Method:** Compare `SGPc_best` (parametric) vs `SGPc_emp` (empirical Bernstein)

**Output:** Correlation, MAD, RMSD

**Why This Matters:** Validates that parametric copulas are adequate

---

### 2. Canonical Adequacy Assessment

**Question:** Can we use averaged parameters instead of condition-specific fits?

**Method:** Compare `SGPc_avg` (canonical from manifest) vs `SGPc_emp`

**Output:** Stratified by year_span × content_area

**Why This Matters:** Validates using manifest for TIMSS, PISA, other new datasets

---

### 3. Mis-specification Impact

**Question:** What happens when we use the wrong copula?

**Method:** Compare `SGPc_gaussian`, `SGPc_gumbel`, `SGPc_frank` vs `SGPc_emp`

**Output:** Quantified error (MAD) for each mis-specification

**Why This Matters:** Demonstrates cost of ignoring tail dependence

---

### 4. TAMP Comparison

**Question:** How extreme is perfect dependence assumption?

**Method:** Compare `SGPc_comonotonic` vs `SGPc_emp`

**Output:** Shows bimodal distribution (SGPc = 1 or 99 for many students)

**Why This Matters:** Justifies moving beyond TAMP's comonotonic copula

---

### 5. SGP Equivalence

**Question:** Are copula-based SGPcs ~ traditional SGP?

**Method:** Compare `SGPc_*` vs `SGP_traditional` (if available)

**Output:** Validates Sklar-theoretic approach

**Why This Matters:** Shows copula-based method is equivalent to established approach

---

## Code Migration

### If You Were Running Old Experiments:

**Before:**
```r
# Old STEP 2
STEPS_TO_RUN <- c(2)
EXPERIMENT_TO_RUN_STEP2 <- c("exp_1_grade_span")
USE_PARALLEL_STEP2 <- FALSE
source("master_analysis.R")
```

**After:**
```r
# New STEP 2 (no experiment selection needed)
STEPS_TO_RUN <- c(2)
USE_PARALLEL_STEP2 <- FALSE
source("master_analysis.R")
```

### If You Were Calling Scripts Directly:

**Before:**
```r
source("STEP_2_Copula_Sensitivity_Analyses/exp_1_grade_span.R")
```

**After:**
```r
# For parameter stability questions → Use Phase 1 results
# No need to re-run; view Phase 1 outputs:
list.files("STEP_1_Family_Selection/results/dataset_all/")

# For SGPc sensitivity → Use new STEP 2
DATASETS_TO_PROCESS <- "dataset_1"
source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
```

---

## Accessing Old Experiments (If Needed)

Old code is preserved in `deprecated/`:

```r
# Access archived experiments (not recommended)
source("STEP_2_Copula_Sensitivity_Analyses/deprecated/exp_1_grade_span.R")
```

**However**, we strongly recommend using Phase 1 results instead. They're more comprehensive (966 conditions vs 7-10), better documented, and AI-readable (manifest).

---

## Expected Benefits

### For Your Workflow:

1. **Faster Analysis**: No redundant parameter stability re-testing
2. **Better Insights**: Focus on practical SGPc impacts
3. **Richer Outputs**: 8 SGPc variants per observation
4. **Operational Guidance**: When to use canonical vs condition-specific copulas

### For Your Manuscript:

1. **Stronger Claims**: "966 conditions demonstrate τ decline" > "7 configs suggest τ decline"
2. **Novel Contribution**: SGPc sensitivity is unique (not in Phase 1)
3. **Practical Validation**: Demonstrates Sklar-theoretic extension works in practice
4. **TAMP Comparison**: Quantifies improvement over comonotonic assumption

---

## Troubleshooting

### "I need exact results from Experiment 1"

**Solution:** Old code is preserved in `deprecated/`. You can still run it.

**Better Alternative:** Use Phase 1 results - they already include grade span analyses across all conditions.

### "My downstream code expects exp_1_grade_span results"

**Options:**
1. Update downstream code to use Phase 1 outputs
2. Temporarily source from `deprecated/` directory
3. Adapt downstream code to new SGPc sensitivity outputs

### "I don't understand the new structure"

**Resources:**
- **Overview**: `STEP_2_SGPc_Sensitivity/README.md`
- **Usage**: `STEP_2_SGPc_Sensitivity/QUICKSTART.md`
- **Implementation**: `STEP_2_REIMAGINED_SUMMARY.md` (this document)
- **Deprecation**: `STEP_2_Copula_Sensitivity_Analyses/DEPRECATED_NOTICE.md`

---

## Support

**Questions about:**
- **Parameter stability** → Review Phase 1 results
- **SGPc sensitivity** → See new STEP 2 documentation
- **Migration** → Contact maintainer or review this guide

**Key Insight:** The old experiments weren't wrong - they're just redundant now that Phase 1 is comprehensive.

---

**Migration Date:** January 27, 2026  
**Backward Compatibility:** Old experiments preserved in `deprecated/`  
**Breaking Changes:** None (new directory, old code still accessible)
