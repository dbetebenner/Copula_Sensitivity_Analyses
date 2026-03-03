# STEP 3: Longitudinal Inference without Longitudinal Data (LIwLD)

## Overview

**Paper Section:** Chapter 4 — Growth Regime Inference from Cross-Sectional Data

**Objective:** Demonstrate that a subgroup's *growth regime* (the distribution of conditional growth percentiles) can be inferred from **independent cross-sectional samples** of prior and current scores — with no student-level linkage — using a baseline copula as a transition kernel.

**Why This Is the Centrepiece:** STEPs 1 and 2 validated the copula dependence model using actual longitudinal data. STEP 3 asks the harder question: when longitudinal pairing is unavailable (e.g., TIMSS, NAEP), can we still recover the growth signal? Because we **do** have the longitudinal pairs, we can validate the cross-sectional inference against reality — a luxury that TIMSS analysts will not have.

**Guiding synthesis:** controlled canonical choices with quantified error.
- **Canonical choice 1 (STEP 1):** baseline copula template.
- **Canonical choice 2 (STEP 3):** stochastically fitted canonical growth regime (Beta by default).

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

We estimate a **growth regime** $H_S$ — a distribution on [0,1] representing latent conditional percentiles for subgroup $S$ — such that the predicted current-grade marginal matches the observed one.

Generative view (SGPcFlow):
- draw U from the observed Grade 4 subgroup distribution,
- draw latent percentile $P_S$ from $H_S$,
- map to current percentile using baseline quantile kernel: $V = Q_0(P_S \mid U)$.

This separates:
- dependence template (baseline copula kernel from STEP 1), and
- subgroup flow occupancy (the inferred $H_S$).

### Deterministic vs Stochastic Clarification

- **TAMP/equipercentile mapping** is the deterministic comonotonic boundary: V = U.
- "Everyone has SGPc = 50" is also deterministic, but generally follows V = Q_0(0.5 | U), which is not necessarily V = U.

So deterministic behavior does not imply TAMP unless the baseline dependence template itself is comonotonic.

### Key Analytic Identity

If the growth-regime percentile $P_S$ is independent of the prior percentile $U$ within a subgroup:

```
F_H(v) = E[ H( F_0(v | U) ) ]
       = (1/n) * sum_i  H( F_0(v | u_i) )
```

This is exact (no Monte Carlo) and can be computed in milliseconds.

### What STEP 3 Estimates (and What It Does Not)

**Estimates:** A distributional summary of subgroup growth: median SGPc, dispersion, bucket membership probabilities (low/typical/high growth).

**Does not estimate:** Individual students' realised SGPc values (these are unidentified without true (x,y) pairs).

---

## Directory Structure

```
STEP_3_LIwLD/
  README.md                              # This file
  SGPcFlow_Inference_Plan.md             # Detailed build plan (updated)
  config_step3.R                         # All tuneable parameters
  run_step3.R                            # Master runner (single entry point)
  step3_validation_deep_dive.R           # Phase A: single condition/district
  step3_systematic_validation.R          # Phase B: across conditions
  step3_publication_panels.R             # Phase C: publication figures + manifest
  functions/
    step3_publication_style.R            # Style bridge (Zissou1, theme_publication)
    reference_marginals.R                # Weighted ECDF + inverse CDF
    copula_kernel_cache.R                # Precompute F_0(v|u) on grid
    regime_families.R                    # Beta, trunc-exp, trunc-uniform (+sd/entropy)
    predict_v_cdf.R                      # Analytic predicted CDF
    distance_metrics.R                   # Wasserstein-1, CvM, KS
    optimize_regime.R                    # Grid search + local refinement
    bootstrap_uncertainty.R              # Sampling + copula uncertainty
    bucket_classification.R              # K=3/K=5 bucket probabilities
    diagnostics_plots.R                  # ggplot2 diagnostic plots
    manifest_export.R                    # JSON/MD manifest output
  results/                               # Generated outputs
    phase_a_deep_dive.rds                # Phase A full results
    phase_a_analytic_payload.rds          # Notation-aligned payload for figure assembly
    phase_a_summary.csv                  # Phase A key metrics
    phase_b_systematic_summary.csv       # Phase B summary table
    phase_b_all_results.rds              # Phase B full results
    district_summary_grade.csv            # District-level model-health scorecard
    step3_country_estimates.csv          # Unified subgroup estimates
    step3_uncertainty_decomposition.csv  # Variance decomposition
    step3_bucket_probabilities.csv       # K=3 and K=5 bucket memberships
    bucket_stability_summary.json        # Classification consistency
    step3_manifest.json                  # AI-consumable manifest
    step3_manifest.md                    # Human-readable manifest
    run_metadata.json                    # Reproducibility metadata
    output_contract_check.json            # Contract/schema validation report
    CONFORMANCE_MATRIX.md                # Audit matrix vs SGPcFlow plan
    visualizations/                      # Publication panels
      phase_a/                           # Phase A diagnostic plots
        panel_a_cdf_comparison.*         # A: observed vs inferred CDF (+ baselines)
        panel_b1_objective_surface.*     # B1: objective over (m, kappa)
        panel_b2_residual_curve.*        # B2: residual diagnostics
        panel_c_regime_comparison.*      # C: regime density comparison
        panel_d_recovery_summary.*       # Recovery summary composite
      panel_d_recovery_by_size.*         # D: Phase B accuracy vs n
      panel_e_recovery_by_span.*         # E: Phase B accuracy vs year span
      panel_f_family_comparison.*        # F: regime family comparison
      panel_g_bootstrap_uncertainty.*    # G: bootstrap distribution
      panel_g_district_summary_grade.*   # H: district summary grade panel
    exports/phase_a/                     # Tidy export bridge for figure assembly
      step3_cdf_curves.csv
      step3_objective_surface.csv
      step3_regime_density.csv
      step3_fit_metrics.csv
      step3_bootstrap_draws.csv
      step3_bootstrap_summary.csv
      step3_kernel_slices.csv
      step3_quantile_slices.csv
```

---

## Workflow

### Quick Start (Full Pipeline)

```r
# From project root
source("STEP_3_LIwLD/run_step3.R")
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
source("STEP_3_LIwLD/run_step3.R")

# Phase B only (systematic validation)
STEP3_PHASE_A <- FALSE; STEP3_PHASE_C <- FALSE
source("STEP_3_LIwLD/run_step3.R")

# Phase C only (publication panels, requires A and/or B results)
STEP3_PHASE_A <- FALSE; STEP3_PHASE_B <- FALSE
source("STEP_3_LIwLD/run_step3.R")
```

---

## Phase A: Single-Condition Deep Validation (The Showcase)

Picks one well-understood condition and one large district (configurable in `config_step3.R`). Walks through the complete pipeline end-to-end:

1. **Extract longitudinal pairs** for the district from the state dataset
2. **Compute true SGPc distribution** using the STEP 1 fitted copula
3. **"Forget" the pairing** — take only independent prior and current score samples
4. **Build reference marginals** using the full state-level ECDF (district scores expressed as state percentiles)
5. **Build transition kernel** F_0(v|u) from the STEP 1 baseline copula
6. **Estimate growth regime** $H_S$ via minimum Wasserstein-1 distance between predicted and observed CDFs (canonical production family: Beta)
7. **Compare inferred vs actual** — the key validation
8. **Bootstrap uncertainty** — 200 replicates for confidence intervals

### Key Outputs

- `phase_a_summary.csv` — One-row summary with inferred vs true mean/median SGPc, distances, and bootstrap CIs
- `phase_a_analytic_payload.rds` — notation-aware payload (U/V samples, `F_obs`, `F_H`, objective surface, kernel slices)
- `results/exports/phase_a/*.csv` — tidy exports for downstream plotting / assembly
- `visualizations/phase_a/` — A/B1/B2/C diagnostic panels + recovery summary

---

## Phase B: Systematic Validation

Extends Phase A across multiple conditions and subgroups to assess recovery accuracy under diverse settings:

- **Subgroup size:** n = 50, 100, 200, 500, 1000+
- **Year span:** 1-year, 2-year, 4-year gaps
- **Content area:** Mathematics, Reading, etc.

### Key Outputs

- `phase_b_systematic_summary.csv` — Full table of inferred vs true mean/median SGPc for all subgroups
- Summary statistics: median |error|, mean |error|, 90th percentile |error| for both median and mean SGPc, stratified by size and span

---

## Phase C: Publication Panels and Manifest

Generates the final publication figures and AI-consumable manifest files:

| Panel | Description | Source |
|-------|-------------|--------|
| A | Observed vs predicted CDF | Phase A |
| B1 | Objective landscape over `(m, log10(kappa))` | Phase A |
| B2 | Residual diagnostics (`F_H - F_obs`) | Phase A |
| C | Inferred regime vs actual SGPc | Phase A |
| D | Recovery accuracy by subgroup size | Phase B |
| E | Recovery accuracy by year span | Phase B |
| F | Regime family comparison | Phase A |
| G | Bootstrap uncertainty distribution | Phase A |
| H | District summary grade panel | Phase A |

---

## Growth Regime Families

Three families are implemented, each parameterising a distribution on [0,1]:

### Beta(mean, kappa) — Canonical production family

The default canonical choice for STEP 3 production runs. Parameterised by mean m in (0,1) and concentration kappa (alpha + beta). Uniform(0,1) is Beta(1,1) — the baseline "no growth signal" case.

### Truncated Exponential (max-entropy) — Sensitivity family

On [0,1], the maximum-entropy distribution with constraint E[P] = m. Philosophically aligned with a "least-committed" stance. Mean = 0.5 gives Uniform.

### Truncated Uniform(lower, upper) — Sensitivity/stress-test family

Flat distribution on a subinterval of [0,1]. Useful for stress-testing "shifted but unpeaked" regimes; typically slower and more likely to produce near-tie objective wins that are not best on true-median recovery.

**Selection policy:** default runs use Beta only (`regime$families = c("beta")`).  
When multiple families are enabled, near-ties are resolved with a configurable tolerance and preferred family (default preferred: Beta).

---

## Configuration

All tuneable parameters live in `config_step3.R`. Key settings:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `regime$families` | `c("beta")` | Canonical production family set |
| `regime$sensitivity_families` | `c("truncexp", "truncunif")` | Optional sensitivity families |
| `regime$preferred_family` | `"beta"` | Tie-break preferred family |
| `regime$tie_tolerance` | `1e-4` | Distance tie window for preferred-family selection |
| `regime$primary_family` | `"beta"` | Single-family default for fast estimation |
| `distance$primary` | `"wasserstein1"` | Optimiser objective |
| `kernel$u_grid_size` | 201 | Transition kernel grid resolution |
| `uncertainty$n_bootstrap` | 200 | Bootstrap replicates |
| `buckets$k3` | `c(45, 55)` | K=3 bucket cutpoints (SGPc scale) |
| `buckets$k5` | `c(40, 45, 55, 60)` | K=5 bucket cutpoints (SGPc scale) |
| `validation$dataset_id` | `"dataset_1"` | Phase A dataset |
| `validation$content_area` | `"MATHEMATICS"` | Preferred Phase A content area |
| `validation$min_subgroup_n` | 500 | Minimum subgroup size |
| `validation$target_subgroup_n` | 2500 | Preferred Phase A subgroup size |
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
- **Visual style bridge:** STEP 3 panels reuse the same Zissou1 palette, `theme_publication()`, and `save_plot_multi()` conventions as STEP 2 via `functions/step3_publication_style.R`

### Shared Functions

- `functions/sgpc_engine.R` — SGPc computation (ground truth)
- `functions/longitudinal_pairs.R` — Data extraction
- `functions/export_plot_utils.R` — Multi-format plot export
- `STEP_2_SGPc_Sensitivity/phase1_data_loader.R` — Phase 1 data loading utilities

### R Package Dependencies

- `data.table`, `copula`, `jsonlite` (core analytics)
- `ggplot2`, `wesanderson`, `patchwork` (publication visualisations)

---

## Output Contract

After a complete run of Phases A + B + C, the following files are guaranteed in `results/`:

### Tabular Outputs

| File | Columns | Source |
|------|---------|--------|
| `district_summary_grade.csv` | subgroup metadata, inferred/true means and medians, W1 vs uniform, residual metrics, CI width, buckets, quality flags | Phase A |
| `step3_country_estimates.csv` | subgroup_id, dataset_id, condition_id, n, regime_family, regime_param_1, regime_param_2, m_hat, kappa_hat, median_sgpc, mean_sgpc, dispersion_sd, dispersion_iqr, entropy, concentration, distance_min, wasserstein1, cvm | Phases A + B |
| `step3_uncertainty_decomposition.csv` | subgroup_id, var_sampling, var_copula, var_family, total_var, se_sampling, n_boot, n_converged | Phase A |
| `step3_bucket_probabilities.csv` | subgroup_id, median_sgpc, k3_{Low,Typical,High}, k3_assigned, k3_consistency, k5_{VeryLow,...,VeryHigh}, k5_assigned, k5_consistency | Phase A |
| `exports/phase_a/step3_cdf_curves.csv` | subgroup_id, v, F_obs, F_pred, F_uniform, F_tamp, residual | Phase A |
| `exports/phase_a/step3_objective_surface.csv` | subgroup_id, m, kappa, log10_kappa, distance_w1, is_optimum | Phase A |
| `exports/phase_a/step3_regime_density.csv` | subgroup_id, p, density_hat, density_uniform, density_true | Phase A |
| `exports/phase_a/step3_fit_metrics.csv` | subgroup_id, w1_uniform, w1_best, w1_reduction_pct, cvm, max_abs_residual, mean_abs_residual | Phase A |
| `exports/phase_a/step3_bootstrap_draws.csv` | subgroup_id, boot_id, m_hat, kappa_hat, median_sgpc, mean_sgpc, converged | Phase A |
| `exports/phase_a/step3_bootstrap_summary.csv` | subgroup_id, ci95_median_lo, ci95_median_hi, ci95_mean_lo, ci95_mean_hi, se_median, n_boot, n_converged | Phase A |

### Machine-Readable Manifests

| File | Purpose |
|------|---------|
| `step3_manifest.json` | AI-consumable manifest with subgroup estimates (includes dispersion, entropy, concentration) |
| `step3_manifest.md` | Human-readable manifest with output file table |
| `bucket_stability_summary.json` | Classification consistency by subgroup |
| `run_metadata.json` | Timestamp, config snapshot, R session info |
| `output_contract_check.json` | File-contract and schema-consistency validation report |

### Validation Checks

- All bucket probabilities sum to ~1 per subgroup (tolerance: 0.001)
- Uncertainty decomposition fields are populated (NA only when source data is unavailable)
- Every publication panel is exported as PDF + SVG + PNG
- Output contract check (`output_contract_check.json`) passes required file and manifest integrity checks

---

## Visualization Style Policy

STEP 3 panels follow the same visual conventions as STEP 2, enforced via `functions/step3_publication_style.R`:

| Convention | Specification |
|---|---|
| **Colour palette** | Wes Anderson "Zissou1" — teal (#3B9AB2), light blue (#78B7C5), gold (#EBCC2A), amber (#E1AF00), red (#F21A00) |
| **Theme** | `theme_publication(base_size = 10)` — bold titles, gray30 subtitles, no minor grid, gray80 panel border |
| **Export** | PDF (cairo_pdf) + SVG + PNG @ 300 dpi via `save_plot_multi()` |
| **Dimensions** | 10 x 7 (standard panels), adjusted per panel as needed |
| **Panel naming** | `panel_{letter}_{description}.{pdf,svg,png}` |
| **Legend** | Alpha-blended white background, bold title, positioned contextually |

### STEP 3 Semantic Colours

| Role | Colour | Hex |
|------|--------|-----|
| Observed/actual | grey30 | — |
| Predicted/inferred | Zissou teal | #3B9AB2 |
| True/longitudinal | Zissou amber | #E1AF00 |
| Residual/trend | Zissou red | #F21A00 |
| Beta family | teal | #3B9AB2 |
| Truncated exponential | amber | #E1AF00 |
| Truncated uniform | gold | #EBCC2A |

---

## Troubleshooting

### Issue: "No Phase 1 conditions found"

**Cause:** STEP 1 has not been run, or results are in a different location.

**Fix:** Run STEP 1 first, or check that `STEP_1_Family_Selection/results/{dataset_id}/` contains `phase1_copula_family_comparison.csv`.

### Issue: "No subgroups meet min_n"

**Cause:** The dataset does not contain `DISTRICT_NUMBER` or all districts are too small.

**Fix:** Try `SCHOOL_NUMBER` instead (set `validation$subgroup_col` in config), or lower `min_subgroup_n`.

### Issue: "Estimation failed" for a subgroup

**Cause:** The grid search found no valid parameter candidate (e.g., observed CDF is outside the predictable range for all regimes).

**Fix:** Check that reference marginals are built from the full state population, not the subgroup. The subgroup's U and V distributions should *not* be uniform.

### Issue: Large recovery error (|diff| > 10 SGP points)

**Possible causes:**
- Subgroup too small (n < 50): sampling noise dominates
- Independence assumption violated: H_S actually depends on U
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
| `SGPcFlow_Inference_Plan.md` | Detailed mathematical plan |
| `config_step3.R` | Configuration (incl. bucket cutpoints) |
| `run_step3.R` | Master runner |
| `step3_validation_deep_dive.R` | Phase A: single-condition showcase |
| `step3_systematic_validation.R` | Phase B: multi-condition validation |
| `step3_publication_panels.R` | Phase C: figures + manifests + CSV outputs |
| `functions/step3_publication_style.R` | Zissou1 style bridge (shared with STEP 2) |
| `functions/reference_marginals.R` | Weighted ECDF + inverse CDF |
| `functions/copula_kernel_cache.R` | Precompute F_0(v\|u) |
| `functions/regime_families.R` | Beta, trunc-exp, trunc-uniform (sd, IQR, entropy) |
| `functions/predict_v_cdf.R` | Analytic predicted CDF |
| `functions/distance_metrics.R` | W1, CvM, KS |
| `functions/optimize_regime.R` | Grid search + optim() |
| `functions/bootstrap_uncertainty.R` | Sampling + copula uncertainty |
| `functions/bucket_classification.R` | K=3/K=5 bucket probabilities + stability |
| `functions/diagnostics_plots.R` | ggplot2 diagnostic visualisations |
| `functions/manifest_export.R` | JSON/MD export (incl. output file table) |
