# STEP 4: TIMSS Implementation

## Overview

**Paper Section:** Chapter 5 — International Application: Growth Regime Inference with TIMSS Data

**Objective:** Deploy the copula-kernel growth regime inference framework (validated in STEP 3) on actual TIMSS public-use data, where independent Grade 4 and Grade 8 samples exist with no student-level linkage.

**Prerequisites:**
- STEP 1 complete (copula family selected, parameter recommendations)
- STEP 2 complete (SGPc sensitivity validated)
- STEP 3 complete (inference machinery validated against longitudinal ground truth)

---

## Purpose

TIMSS (Trends in International Mathematics and Science Study) assesses students at Grades 4 and 8 in mathematics and science across 60+ countries. Because TIMSS samples independent cohorts at each grade, there is **no student-level linking** between Grade 4 and Grade 8.

This is the real-world use case that STEPs 1-3 have been building toward:

1. **STEP 1** identified the t-copula as the best dependency model for educational data
2. **STEP 2** showed that copula parameters are stable across diverse conditions
3. **STEP 3** validated that growth regimes can be recovered from cross-sectional data alone

STEP 4 applies this validated machinery to TIMSS, estimating **country-level growth regimes** that answer: "Given how students in Country X scored at Grade 4, and how students scored at Grade 8, what can we infer about the distribution of growth in that country?"

---

## Data Requirements

### TIMSS Public-Use Files

TIMSS public-use data files are freely available from the IEA Data Repository (https://www.iea.nl/data-tools/repository).

Required files for each assessment cycle:
- **Grade 4 achievement data:** Student-level plausible values (5 PVs per student)
- **Grade 8 achievement data:** Student-level plausible values (5 PVs per student)
- **Sampling weights:** Student-level total weights (`TOTWGT`)
- **Country identifiers:** ISO country codes or IEA country IDs

### Assessment Cycles

| Cycle | Grade 4 Year | Grade 8 Year | Span |
|-------|-------------|-------------|------|
| TIMSS 2019 | 2019 | 2019 | Cross-sectional (not longitudinal) |
| TIMSS 2023 | 2023 | 2023 | Cross-sectional |

**Note:** TIMSS Grade 4 and Grade 8 are assessed in the same year but on different students. The 4-year span comes from the grade difference (Grade 4 -> Grade 8), matching the "4-year span" copula parameters from STEP 1.

---

## Planned Workflow

### Step 4.1: Data Preparation

- Load TIMSS public-use files
- Extract plausible values and sampling weights by country
- Build global reference marginals (pooled across all countries)
- Map country scores to reference percentiles

### Step 4.2: Growth Regime Estimation

For each country:
- Apply STEP 3 inference pipeline using 4-year-span copula parameters
- Estimate growth regime `H_S` using Beta family
- Compute median SGPc, dispersion, and bucket probabilities
- Quantify uncertainty (bootstrap + copula parameter uncertainty)

### Step 4.3: Cross-Country Comparison

- Rank countries by estimated median SGPc
- Classify into growth buckets (K=3: low/typical/high)
- Compare with official TIMSS reporting and existing growth indicators
- Assess classification stability with uncertainty

### Step 4.4: Sensitivity Analysis

- Sensitivity to reference marginal choice (global vs cycle-specific)
- Sensitivity to copula parameters (median vs IQR draws from STEP 1)
- Sensitivity to regime family (Beta vs alternatives)
- Comparison with TAMP-based analysis (comonotonic assumption)

---

## Expected Directory Structure

```
STEP_4_TIMSS_Implementation/
  README.md                              # This file
  config_step4.R                         # TIMSS-specific configuration
  run_step4.R                            # Master runner
  step4_data_preparation.R               # Load and prepare TIMSS data
  step4_country_estimation.R             # Per-country growth regime estimation
  step4_cross_country_comparison.R       # Rankings and classifications
  step4_sensitivity.R                    # Sensitivity analyses
  step4_publication_panels.R             # Publication figures
  data/                                  # TIMSS data files (not tracked)
  results/                               # Generated outputs
    country_estimates.csv                # Main results table
    country_bucket_probabilities.csv     # Classification with uncertainty
    step4_manifest.json                  # AI-consumable manifest
    step4_manifest.md                    # Human-readable manifest
    visualizations/                      # Publication panels
  Archive/                               # Legacy files from prior directory purpose
```

---

## Inputs from Previous Steps

### From STEP 1 (via manifest)

```r
# Load recommended 4-year-span copula parameters
manifest <- jsonlite::fromJSON("STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json")
params_4yr <- manifest$parameter_recommendations$by_year_span$year_span_4
# params_4yr$rho$median  ~  0.70
# params_4yr$df$median   ~  8
```

### From STEP 3 (machinery)

All STEP 3 function modules are reused directly:
- `reference_marginals.R` — For TIMSS reference ECDFs
- `copula_kernel_cache.R` — Transition kernel
- `regime_families.R` — Growth regime families
- `predict_v_cdf.R` — Predicted CDF
- `distance_metrics.R` — Fitting metrics
- Optimizer module — Estimation
- `bootstrap_uncertainty.R` — Uncertainty quantification

---

## Connection to Paper

### Chapter 5: International Application

This step provides the content for the TIMSS application chapter:

- **Section 5.1:** Data and methods (TIMSS setup, reference marginals)
- **Section 5.2:** Country-level growth regime estimates (main results)
- **Section 5.3:** Cross-country rankings and growth buckets
- **Section 5.4:** Sensitivity and robustness
- **Section 5.5:** Comparison with existing approaches

---

## Current Status

**Status:** Placeholder — awaiting STEP 3 completion and TIMSS data acquisition.

The directory structure and documentation are in place. Implementation will proceed after STEP 3 validation confirms the inference machinery works reliably.

---

## Archive

Legacy files from a prior directory purpose (transformation validation, which has been incorporated into earlier steps) are preserved in `Archive/` for reference.
