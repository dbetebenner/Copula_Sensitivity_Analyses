# STEP 3: Longitudinal Inference without Longitudinal Data (LIw_LD)

## Overview

**Paper Section:** Chapter 4 — Growth Regime Inference from Cross-Sectional Data

**Objective:** Demonstrate that a subgroup's *growth regime* (the distribution of conditional growth percentiles) can be inferred from **independent cross-sectional samples** of prior and current scores — with no student-level linkage — using a baseline copula as a transition kernel.

**Why This Is the Centrepiece:** STEPs 1 and 2 validated the copula dependence model using actual longitudinal data. STEP 3 asks the harder question: when longitudinal pairing is unavailable (e.g., TIMSS, NAEP), can we still recover the growth signal? Because we **do** have the longitudinal pairs, we can validate the cross-sectional inference against reality — a luxury that TIMSS analysts will not have.

**Prerequisites:**
- STEP 1 complete (copula family selected, parameter recommendations in `analysis_manifest.json`)
- STEP 2 complete (SGPc sensitivity validated, publication panels generated)

---

## Conceptual Framework

### The Problem

International assessments such as TIMSS sample independent cohorts at Grade 4 and Grade 8. There is no student-level linking. Yet policymakers want to know: "How much did students grow?" The traditional TAMP approach assumes comonotonic dependence (rank preservation), but STEP 1 showed this is dramatically wrong.

### The Solution: Copula-Kernel Growth Regime Inference

Given:
- **Prior sample:** Scores {x_i} from Grade 4 (subgroup/country), mapped to reference percentiles u_i = F_X^ref(x_i)
- **Current sample:** Scores {y_j} from Grade 8 (same subgroup), mapped to v_j = F_Y^ref(y_j)
- **Baseline copula C_0** from STEP 1, defining the transition kernel F_0(v|u) = dC_0(u,v)/du

We estimate a **growth regime** H_theta — a distribution on [0,1] representing the latent conditional percentiles — such that the predicted current-grade marginal matches the observed one.

### Key Analytic Identity

If the growth-regime percentile P_theta is independent of the prior percentile U within a subgroup:

```
F_theta(v) = E[ H_theta( F_0(v | U) ) ]
           = (1/n) * sum_i  H_theta( F_0(v | u_i) )
```

This is exact (no Monte Carlo) and can be computed in milliseconds.

### What STEP 3 Estimates (and What It Does Not)

**Estimates:** A distributional summary of subgroup growth: median SGPc, dispersion, bucket membership probabilities (low/typical/high growth).

**Does not estimate:** Individual students' realised SGPc values (these are unidentified without true (x,y) pairs).

---

## Directory Structure

```
STEP_3_LIw_LD/
  README.md                              # This file
  Growth_Regime_Inference_Plan.md        # Detailed build plan (retained)
  config_step3.R                         # All tuneable parameters
  run_step3.R                            # Master runner (single entry point)
  step3_validation_deep_dive.R           # Phase A: single condition/district
  step3_systematic_validation.R          # Phase B: across conditions
  step3_publication_panels.R             # Phase C: publication figures + manifest
  functions/
    reference_marginals.R                # Weighted ECDF + inverse CDF
    copula_kernel_cache.R                # Precompute F_0(v|u) on grid
    regime_families.R                    # Beta, trunc-exp, trunc-uniform
    predict_v_cdf.R                      # Analytic predicted CDF
    distance_metrics.R                   # Wasserstein-1, CvM, KS
    optimize_theta.R                     # Grid search + local refinement
    bootstrap_uncertainty.R              # Sampling + copula uncertainty
    diagnostics_plots.R                  # Per-subgroup diagnostic plots
    manifest_export.R                    # JSON/MD manifest output
  results/                               # Generated outputs
    phase_a_deep_dive.rds                # Phase A full results
    phase_a_summary.csv                  # Phase A key metrics
    phase_b_systematic_summary.csv       # Phase B summary table
    phase_b_all_results.rds              # Phase B full results
    step3_manifest.json                  # AI-consumable manifest
    step3_manifest.md                    # Human-readable manifest
    run_metadata.json                    # Reproducibility metadata
    visualizations/                      # Publication panels
      phase_a/                           # Phase A diagnostic plots
      panel_c_recovery_by_size.*         # Phase B: accuracy vs n
      panel_d_recovery_by_span.*         # Phase B: accuracy vs year span
      panel_e_family_comparison.*        # Phase A: regime family comparison
      panel_f_bootstrap_uncertainty.*    # Phase A: bootstrap distribution
```

---

## Workflow

### Quick Start (Full Pipeline)

```r
# From project root
source("STEP_3_LIw_LD/run_step3.R")
```

### Via Master Pipeline

```r
STEPS_TO_RUN <- 3
source("master_analysis.R")
```

### Run Individual Phases

```r
# Phase A only (single-condition deep validation)
STEP3_PHASE_B <- FALSE; STEP3_PHASE_C <- FALSE
source("STEP_3_LIw_LD/run_step3.R")

# Phase B only (systematic validation)
STEP3_PHASE_A <- FALSE; STEP3_PHASE_C <- FALSE
source("STEP_3_LIw_LD/run_step3.R")

# Phase C only (publication panels, requires A and/or B results)
STEP3_PHASE_A <- FALSE; STEP3_PHASE_B <- FALSE
source("STEP_3_LIw_LD/run_step3.R")
```

---

## Phase A: Single-Condition Deep Validation (The Showcase)

Picks one well-understood condition and one large district (configurable in `config_step3.R`). Walks through the complete pipeline end-to-end:

1. **Extract longitudinal pairs** for the district from the state dataset
2. **Compute true SGPc distribution** using the STEP 1 fitted copula
3. **"Forget" the pairing** — take only independent prior and current score samples
4. **Build reference marginals** using the full state-level ECDF (district scores expressed as state percentiles)
5. **Build transition kernel** F_0(v|u) from the STEP 1 baseline copula
6. **Estimate growth regime** H_theta via minimum Wasserstein-1 distance between predicted and observed CDFs
7. **Compare inferred vs actual** — the key validation
8. **Bootstrap uncertainty** — 200 replicates for confidence intervals

### Key Outputs

- `phase_a_summary.csv` — One-row summary with inferred vs true median SGPc, distances, and bootstrap CIs
- `visualizations/phase_a/` — Four diagnostic panels (CDF comparison, regime shape, residual, recovery summary)

---

## Phase B: Systematic Validation

Extends Phase A across multiple conditions and subgroups to assess recovery accuracy under diverse settings:

- **Subgroup size:** n = 50, 100, 200, 500, 1000+
- **Year span:** 1-year, 2-year, 4-year gaps
- **Content area:** Mathematics, Reading, etc.

### Key Outputs

- `phase_b_systematic_summary.csv` — Full table of inferred vs true median SGPc for all subgroups
- Summary statistics: median |error|, mean |error|, 90th percentile |error|, stratified by size and span

---

## Phase C: Publication Panels and Manifest

Generates the final publication figures and AI-consumable manifest files:

| Panel | Description | Source |
|-------|-------------|--------|
| A | Observed vs predicted CDF | Phase A |
| B | Inferred regime vs actual SGPc | Phase A |
| C | Recovery accuracy by subgroup size | Phase B |
| D | Recovery accuracy by year span | Phase B |
| E | Regime family comparison | Phase A |
| F | Bootstrap uncertainty distribution | Phase A |

---

## Growth Regime Families

Three families are implemented, each parameterising a distribution on [0,1]:

### Beta(mean, kappa)

The default. Parameterised by mean m in (0,1) and concentration kappa (alpha + beta). Uniform(0,1) is Beta(0.5, 2) — the baseline "no growth signal" case.

### Truncated Exponential (max-entropy)

On [0,1], the maximum-entropy distribution with constraint E[P] = m. Philosophically aligned with a "least-committed" stance. Mean = 0.5 gives Uniform.

### Truncated Uniform(lower, upper)

Flat distribution on a subinterval of [0,1]. Useful for stress-testing "shifted but unpeaked" regimes.

---

## Configuration

All tuneable parameters live in `config_step3.R`. Key settings:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `regime$primary_family` | `"beta"` | Default regime family |
| `distance$primary` | `"wasserstein1"` | Optimiser objective |
| `kernel$u_grid_size` | 201 | Transition kernel grid resolution |
| `uncertainty$n_bootstrap` | 200 | Bootstrap replicates |
| `validation$dataset_id` | `"dataset_1"` | Phase A dataset |
| `validation$min_subgroup_n` | 100 | Minimum subgroup size |
| `systematic$n_conditions_per_dataset` | 10 | Conditions for Phase B |
| `seed` | 20260210 | RNG seed for reproducibility |

---

## Dependencies on STEP 1 and STEP 2

### From STEP 1 (Family Selection)

- `analysis_manifest.json` — Recommended copula parameters (rho, df) by year span
- `canonical_copula_parameters.csv` — Canonical averaged parameters
- `contour_plots/{condition}/copula_results.rds` — Per-condition fitted copulas

### From STEP 2 (SGPc Sensitivity)

- Panel naming conventions and multi-format export patterns
- Error decomposition concept (adapted for sampling vs copula uncertainty)

### Shared Functions

- `functions/sgpc_engine.R` — SGPc computation (ground truth)
- `functions/longitudinal_pairs.R` — Data extraction
- `functions/export_plot_utils.R` — Multi-format plot export
- `STEP_2_SGPc_Sensitivity/phase1_data_loader.R` — Phase 1 data loading utilities

---

## Troubleshooting

### Issue: "No Phase 1 conditions found"

**Cause:** STEP 1 has not been run, or results are in a different location.

**Fix:** Run STEP 1 first, or check that `STEP_1_Family_Selection/results/{dataset_id}/` contains `phase1_copula_family_comparison.csv`.

### Issue: "No subgroups meet min_n"

**Cause:** The dataset does not contain `DISTRICT_NUMBER` or all districts are too small.

**Fix:** Try `SCHOOL_NUMBER` instead (set `validation$subgroup_col` in config), or lower `min_subgroup_n`.

### Issue: "Estimation failed" for a subgroup

**Cause:** The grid search found no valid theta (e.g., observed CDF is outside the predictable range for all regimes).

**Fix:** Check that reference marginals are built from the full state population, not the subgroup. The subgroup's U and V distributions should *not* be uniform.

### Issue: Large recovery error (|diff| > 10 SGP points)

**Possible causes:**
- Subgroup too small (n < 50): sampling noise dominates
- Independence assumption violated: H_theta actually depends on U
- Copula mismatch: baseline copula does not match this subgroup's dependency

---

## Connection to Paper

### Chapter 4: Growth Regime Inference

STEP 3 provides the main content for Chapter 4 of the paper. Key elements:

- **Methodology:** The copula-kernel growth regime framework (Section 4.1)
- **Validation:** Recovery of known growth regimes from cross-sectional data (Section 4.2)
- **Results:** Accuracy as a function of sample size and year span (Section 4.3)
- **Discussion:** Assumptions, limitations, and conditions for reliable inference (Section 4.4)

### Transition to STEP 4 (TIMSS Application)

STEP 3 validates the inference machinery on data where ground truth is available. STEP 4 deploys the same machinery on actual TIMSS data (Grade 4 and Grade 8, independent samples) where no longitudinal pairing exists — the real-world use case.

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `README.md` | This documentation |
| `Growth_Regime_Inference_Plan.md` | Detailed mathematical plan |
| `config_step3.R` | Configuration |
| `run_step3.R` | Master runner |
| `step3_validation_deep_dive.R` | Phase A: single-condition showcase |
| `step3_systematic_validation.R` | Phase B: multi-condition validation |
| `step3_publication_panels.R` | Phase C: figures + manifest |
| `functions/reference_marginals.R` | Weighted ECDF + inverse CDF |
| `functions/copula_kernel_cache.R` | Precompute F_0(v\|u) |
| `functions/regime_families.R` | Beta, trunc-exp, trunc-uniform |
| `functions/predict_v_cdf.R` | Analytic predicted CDF |
| `functions/distance_metrics.R` | W1, CvM, KS |
| `functions/optimize_theta.R` | Grid search + optim() |
| `functions/bootstrap_uncertainty.R` | Sampling + copula uncertainty |
| `functions/diagnostics_plots.R` | Diagnostic visualisations |
| `functions/manifest_export.R` | JSON/MD export |
