# STEP 3: Longitudinal Inference without Longitudinal Data (LIwLD)

## Overview

**Paper Section:** Chapter 4 — Growth Regime Inference from Cross-Sectional Data

**Objective:** Demonstrate that a subgroup's *growth regime* (the distribution of conditional
growth percentiles) can be inferred from **independent cross-sectional samples** of prior and
current scores — with no student-level linkage — using a baseline copula as a transition kernel.

**Why This Is the Centrepiece:** STEPs 1 and 2 validated the copula dependence model using actual
longitudinal data. STEP 3 asks the harder question: when longitudinal pairing is unavailable
(e.g., TIMSS, NAEP), can we still recover the growth signal? Because we **do** have the
longitudinal pairs, we can validate the cross-sectional inference against reality — a luxury
that TIMSS analysts will not have.

**Guiding synthesis:** controlled canonical choices with quantified error.
- **Canonical choice 1 (STEP 1):** baseline copula template.
- **Canonical choice 2 (STEP 3):** stochastically fitted canonical growth regime (Beta by default).

**Prerequisites:**
- STEP 1 complete (copula family selected, parameter recommendations in `analysis_manifest.json`)
- STEP 2 complete (SGPc sensitivity validated, publication panels generated)

---

## Conceptual Framework

### The Problem

International assessments such as TIMSS sample independent cohorts at Grade 4 and Grade 8.
There is no student-level linking. Yet policymakers want to know: "How much did students grow?"
The traditional TAMP approach assumes **comonotonic** dependence (rank preservation: V = U on
the percentile scale), but STEP 1 showed this assumption is dramatically inconsistent with the
observed dependence structure.

### Formal Objects

Work throughout on the pseudo-observation (reference-percentile) scale:

| Symbol | Definition |
|--------|-----------|
| X, Y | Prior (Grade 4) and current (Grade 8) raw scores |
| F_X^ref, F_Y^ref | Fixed reference marginal CDFs (full state population, not subgroup-specific) |
| U = F_X^ref(X) | Prior reference percentile ∈ (0, 1) |
| V = F_Y^ref(Y) | Current reference percentile ∈ (0, 1) |
| C_0 | Baseline copula from STEP 1 |
| F_0(v\|u) = ∂C_0(u,v)/∂u | Conditional CDF (transition kernel) |
| Q_0(p\|u) = F_0^{-1}(p\|u) | Conditional quantile kernel |
| P_S ~ H_S | Latent conditional percentile drawn from subgroup growth regime |
| SGPc(u, v) = 100·F_0(v\|u) | Student Growth Percentile (copula scale) |

**Note on reference marginals:** Using subgroup-specific ECDF mapping would force both U and V
toward Uniform(0,1), erasing the distributional shift signal that STEP 3 needs to recover H_S.
Fixed population-level references are therefore required.

### SGPcFlow: The Core Generative Model

**SGPcFlow** defines a stochastic map from prior to current percentile:

```
sgpcFlow_S:   U  →  V = Q_0(P_S | U),   P_S ~ H_S
```

where Q_0 is induced by the baseline copula C_0 via F_0(v|u) = ∂C_0(u,v)/∂u.

Generative view — to simulate the current-grade percentile distribution of subgroup S:
1. Draw U from the observed Grade 4 subgroup distribution.
2. Draw a latent conditional percentile P_S from H_S (the growth regime).
3. Map to current percentile: V = Q_0(P_S | U).

This **separates** the inference problem into two components:
- **Dependence template** (baseline copula kernel, established in STEP 1): F_0(v|u)
- **Flow occupancy rule** (the object STEP 3 estimates): H_S

### Deterministic Boundary Cases and TAMP

The copula space has two deterministic extremes (Fréchet bounds):

- **Comonotonic copula** C⁺(u,v) = min(u,v): transition kernel is the point mass V = U.
  This is exactly **TAMP** (rank-preserving equipercentile mapping). SGPc = 50 for all students
  under this kernel if and only if the subgroup lies at the population median.

- **Countermonotonic copula** C⁻(u,v) = max(u+v−1, 0): kernel is V = 1−U.

The interior of copula space (e.g., a t-copula from STEP 1) gives genuinely stochastic kernels
with non-degenerate spread around the conditional median.

**Critical subtlety:** "Everyone has SGPc = 50" means V = Q_0(0.5 | U) — each student lies on
the conditional median curve. This is *deterministic* (point-mass H_S at p = 0.5), but is
generally **not** equal to V = U. It is the comonotonic (TAMP) special case only when the
baseline kernel itself is the identity. Under a t-copula kernel, the conditional median curve
diverges from the diagonal, so a regime with point-mass H_S = δ(0.5) differs materially from TAMP.

### The Key Analytic Identity

The primary identifying assumption is **P_S ⊥ U** within subgroup (latent conditional percentile
independent of prior rank). Under this assumption:

```
F_H(v)  =  E[ H_S( F_0(v | U) ) ]
         ≈  (1/n) * Σ_i  H_S( F_0(v | u_i) )
```

This is **exact** (no Monte Carlo) and evaluates in milliseconds. It is the computational core
of all STEP 3 estimation.

**Why P_S ⊥ U is the right assumption:** It is the minimal structure that lets you identify a
low-dimensional summary H_S from two unlinked marginal samples. It does *not* by itself identify
differential opportunity effects (e.g., low-percentile students systematically receiving lower P).
Stratified-by-U sensitivity analysis (Phase B3) probes how much the estimates change if this
assumption is relaxed.

### What STEP 3 Estimates (and What It Does Not)

**Estimates:**
- H_S: the subgroup-level distribution over latent conditional percentiles
- Derived summaries: median SGPc, mean SGPc, dispersion (SD, IQR), entropy/concentration
- Bucket membership probabilities: K=3 (Low/Typical/High) and K=5

**Does not estimate:** Individual students' realised SGPc values — these are unidentified without
true (x, y) pairs.

### The Two Error Sources

STEP 3 characterises two independent sources of error in cross-sectional growth inference:

| Error | Source | Phase | Size |
|-------|--------|-------|------|
| **Error 1 — Sampling** | Cross-sectional sample of size N substitutes for full subgroup | Phase B | Degrades precision below ~5,000 students |
| **Error 2 — Inference** | Canonical copula + Beta family may not match true DGP | Phase A | Bias at full N; characterised by inferred-vs-true comparison |

Phase A provides a full diagnostic at the observed subgroup size. Phase B maps how Error 1
degrades as N falls to NAEP-scale (~3,000–4,000 per state) and TIMSS-scale (~4,000+ per country).

---

## Directory Structure

```
STEP_3_LIwLD/
  README.md                              # This file
  SGPcFlow_Inference_Plan.md             # Detailed mathematical plan
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
    predict_v_cdf.R                      # Analytic predicted CDF via identity
    distance_metrics.R                   # Wasserstein-1, CvM, KS
    optimize_regime.R                    # Grid search + local refinement
    bootstrap_uncertainty.R              # Sampling + copula uncertainty loops
    bucket_classification.R              # K=3/K=5 bucket probabilities + stability
    build_cluster_pools.R                # Growth-stratified super-district pools
    diagnostics_plots.R                  # ggplot2 diagnostic plots
    manifest_export.R                    # JSON/MD manifest output
  results/                               # Generated outputs
    phase_a_deep_dive.rds                # Phase A full results
    phase_a_analytic_payload.rds         # Notation-aligned payload for figure assembly
    phase_a_summary.csv                  # Phase A key metrics
    phase_b_systematic_summary.csv       # Phase B per-subgroup condition summaries
    phase_b_pool_registry.csv            # Phase B pool registry + eligibility
    phase_b_precision_by_n.csv           # Phase B precision operating table by N bucket
    phase_b_replicates.RData             # Phase B replicate-level artifact
    phase_b_all_results.rds              # Phase B full results
    district_summary_grade.csv           # District-level model-health scorecard
    step3_country_estimates.csv          # Unified subgroup estimates
    step3_uncertainty_decomposition.csv  # Variance decomposition
    step3_bucket_probabilities.csv       # K=3 and K=5 bucket memberships
    bucket_stability_summary.json        # Classification consistency
    step3_manifest.json                  # AI-consumable manifest
    step3_manifest.md                    # Human-readable manifest
    run_metadata.json                    # Reproducibility metadata
    output_contract_check.json           # Contract/schema validation report
    CONFORMANCE_MATRIX.md                # Audit matrix vs SGPcFlow plan
    visualizations/                      # Publication panels
      phase_a/                           # Phase A diagnostic plots
        panel_a_cdf_comparison.*         # A: observed vs inferred CDF (+ baselines)
        panel_b1_objective_surface.*     # B1: objective over (m, kappa)
        panel_b2_residual_curve.*        # B2: residual diagnostics
        panel_c_regime_comparison.*      # C: regime density comparison
        panel_d_recovery_summary.*       # Recovery summary composite
      panel_d_recovery_by_size.*         # D: Phase B precision vs N buckets
      panel_e_recovery_by_span.*         # E: Phase B accuracy vs year span
      panel_f_family_comparison.*        # F: regime family comparison
      panel_g_bootstrap_uncertainty.*    # G: bootstrap distribution
      panel_h_district_summary_grade.*   # H: district summary grade panel
      panel_i_independence_diagnostic.*  # I: independence diagnostic (P ⊥ U check)
      panel_j_sensitivity_summary.*      # J: sensitivity summary (B2/B3)
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

Picks one well-understood condition and one large district (configurable in `config_step3.R`).
Walks through the complete pipeline end-to-end and validates the cross-sectional inference
against known longitudinal ground truth:

1. **Extract longitudinal pairs** for the district from the state dataset
2. **Compute true SGPc distribution** using the STEP 1 fitted copula and actual (u, v) pairs
3. **"Forget" the pairing** — take only independent prior and current score samples
4. **Build reference marginals** using the full state-level ECDF (district scores expressed as
   state percentiles; subgroup-specific ECDF is deliberately avoided)
5. **Build transition kernel** F_0(v|u) = ∂C_0(u,v)/∂u from the STEP 1 baseline copula
6. **Estimate growth regime** H_S via minimum Wasserstein-1 distance:
   H_hat_S = argmin_{H ∈ H_Beta} W_1( F_obs_V, F_H )
   where F_H(v) = (1/n) * Σ_i H(F_0(v|u_i))
7. **Compare inferred vs actual** — the key validation against longitudinal ground truth
8. **Bootstrap uncertainty** — 200 replicates for confidence intervals and SE estimates
9. **Independence diagnostic** — tests P_S ⊥ U via Spearman ρ(U, SGPc_true) and Kruskal-Wallis
10. **Regime family comparison** — Beta vs truncated-exponential vs truncated-uniform sensitivity

### Key Outputs

- `phase_a_summary.csv` — One-row summary: inferred vs true mean/median SGPc, distances,
  bootstrap CIs, independence diagnostics
- `phase_a_analytic_payload.rds` — notation-aware payload (U/V samples, F_obs, F_H, objective
  surface, kernel slices) for downstream figure assembly
- `results/exports/phase_a/*.csv` — tidy exports for plotting
- `visualizations/phase_a/` — A/B1/B2/C diagnostic panels + recovery summary

---

## Phase B: Systematic Validation

Extends Phase A across multiple conditions and subgroups to assess **precision operating
characteristics** under diverse settings — directly addressing the NAEP and TIMSS use cases.

- **N buckets:** 1,000 / 2,500 / 5,000 / 7,500 / 10,000
  (NAEP state-level: ~3,000–4,000; TIMSS country-level: ~4,000+)
- **Eligibility:** N_pool ≥ N_bucket × (1 + 0.10)
- **Outer reps:** 200 per eligible `pool × N` cell
- **Pool design:** district pools + growth-stratified cluster pools (Low/Typical/High)
- **Year spans:** 1-year, 2-year, 4-year gaps
- **Content areas:** all available (Mathematics, Reading/Writing, etc.)
- **Execution:** Two-stage `mirai` parallelization (see below)

### Key Outputs

- `phase_b_systematic_summary.csv` — Full table of inferred vs true mean/median SGPc for all
  subgroup-condition pairs (all pools × all conditions run)
- `phase_b_pool_registry.csv` — Pool definitions and eligibility metadata
- `phase_b_replicates.RData` — Replicate-level outputs for `pool × n_bucket × outer_rep`
- `phase_b_precision_by_n.csv` — Precision-by-N metrics (`bias`, `MAE`, `RMSE`, empirical
  CI widths), aggregated by (pool, n_bucket, year_span)
- Summary statistics: median |error|, mean |error|, 90th-percentile |error| for both median
  and mean SGPc, stratified by N bucket and year span

### Phase B Parallelization Architecture

Phase B uses a **two-stage design** that enables full utilisation of large EC2 instances
(tested up to 192 vCPUs):

**Stage 1 — Pool setup (sequential, main process)**
For each condition, runs full-pool regime estimation, copula sensitivity (B2), independence
sensitivity (B3), and builds the pool registry. Generates summary rows immediately. Cannot
currently be parallelised without data refactoring; this is the bottleneck on large instances.

**Stage 2 — Replicate batches (parallel, `mirai_map()`)**
Builds a flat task list by expanding `pool × bucket × rep_batch`. Tasks are sorted **slowest-first**
(descending by N bucket) to ensure the most time-consuming draws are dispatched at t=0, preventing
idle workers at the end. Each task calls `process_replicate_batch()` and returns a `data.table`
of replicate rows.

**Daemon lifecycle**
- Daemons created **once** before all datasets/conditions: `daemons(n_workers, output=TRUE)`
- **Init `everywhere()`**: loads packages (`data.table`, `copula`), sources all function files,
  sets single-threaded mode (`OMP_NUM_THREADS=1`, `data.table::setDTthreads(1)`)
- **Per-condition `everywhere()`**: pushes condition data to all daemons as globals (prefixed `.PHASEB_*`):
  `.PHASEB_U_FULL`, `.PHASEB_V_FULL`, `.PHASEB_SS_PRIOR`, `.PHASEB_SS_CURRENT`,
  `.PHASEB_REFS`, `.PHASEB_KERNEL_CACHE`, `.PHASEB_P1_COPULA`, `.PHASEB_POOL_DEFS`,
  `.PHASEB_CFG_REG`, `.PHASEB_CFG_DIST`, `.PHASEB_TRUE_SGPC_FULL`
  **Uses `<<-` (not `<-`) for all assignments** to reach daemon `.GlobalEnv` rather than
  the local `everywhere()` task frame.
- **`worker_lambda` environment**: set to `globalenv()` so that worker function lookup
  walks to daemon `.GlobalEnv` where functions were sourced (not `baseenv()`, which would
  not find them).
- Daemons destroyed **once** at the end: `daemons(0)`

**EC2 worker sizing**
```r
if (n_cores <= 48) n_workers <- n_cores - 2  # e.g. 14 on r8g.4xlarge
else               n_workers <- n_cores - 4  # e.g. 188 on r8g.48xlarge (192 vCPU)
```

**Performance estimates** (200 reps, 10 conditions, 8 pools, 5 N buckets, `rep_grid_resolution=10`):

| Instance | vCPUs | Workers | Stage 1 (sequential) | Stage 2 (parallel) | Approx. total |
|----------|-------|---------|----------------------|---------------------|---------------|
| r8g.4xlarge | 16 | 14 | ~100 min/condition × 10 | ~870–3600 s/batch ÷ 14 workers | ~60–100 hours |
| r8g.48xlarge | 192 | 188 | ~59 min/condition × 10 | ~22 min/condition × 10 | ~13–14 hours |

Stage 1 dominates on large instances; parallelising it further requires refactoring the
per-condition kernel cache and pool setup.

**`rep_batch_size` tuning** — this is the most critical parameter for large instances:

| Instance | `rep_batch_size` | Total tasks | Notes |
|----------|-----------------|-------------|-------|
| r8g.4xlarge (14 workers) | 25 | ~192 | 2 rounds; acceptable |
| r8g.12xlarge (46 workers) | 10 | ~480 | ~5 rounds |
| r8g.48xlarge (188 workers) | **5** | ~960 | ~5 rounds; required to avoid 184 idle workers |

**Progress monitoring**
A tail-able progress file is written to `results/.phase_b_progress.txt`:
```bash
tail -f ~/Copula_Sensitivity_Analyses/STEP_3_LIwLD/results/.phase_b_progress.txt
```
Each completed batch also logs `[W<pid>] pool= bkt= reps= | <elapsed>s` to daemon stdout
(captured via `output=TRUE`).

---

## Phase C: Publication Panels and Manifest

Generates the final publication figures and manifests from Phase A and B results:

| Panel | Description | Source |
|-------|-------------|--------|
| A | Observed vs predicted CDF (+ TAMP and uniform baselines) | Phase A |
| B1 | Objective landscape over `(m, log10(kappa))` | Phase A |
| B2 | Residual diagnostics (`F_H − F_obs`) in v-space | Phase A |
| C | Inferred regime density vs actual SGPc distribution | Phase A |
| D | Recovery precision by N bucket (95% CI width + MAE curves) | Phase B |
| E | Recovery accuracy by year span (|inferred − true median SGPc|) | Phase B |
| F | Regime family comparison (Beta vs truncated-exp vs truncated-uniform) | Phase A |
| G | Bootstrap uncertainty distribution of median SGPc | Phase A |
| H | District summary grade panel | Phase A |
| I | Independence diagnostic (P ⊥ U check by U-quintile bin) | Phase A |
| J | Sensitivity summary (copula-param sensitivity + stratified-by-U regimes) | Phase B2/B3 |

---

## Growth Regime Families

Three families are implemented, each parameterising a distribution on [0, 1]:

### Beta(mean m, concentration κ) — Canonical production family

The default. Parameterised by mean m ∈ (0,1) and concentration κ = α + β. The uniform baseline
"no growth signal" case is Beta(1,1), i.e., m = 0.5, κ = 2. Large κ approximates a point mass
at m (deterministic regime limit).

Internal parameterisation: α = m·κ, β = (1−m)·κ.

### Truncated Exponential (max-entropy) — Sensitivity family

On [0,1], the maximum-entropy distribution with constraint E[P] = m. Philosophically aligned
with a "least-committed" stance given only a mean constraint. Mean = 0.5 gives Uniform.

### Truncated Uniform(lower, upper) — Sensitivity/stress-test family

Flat distribution on a sub-interval of [0,1]. Tests "shifted but unpeaked" regimes; typically
slower and more prone to near-tie objective wins that do not improve true-median recovery.

**Selection policy:** production runs use Beta only (`regime$families = c("beta")`).
When multiple families are enabled, near-ties (within `tie_tolerance = 1e-4`) are resolved by
preferring Beta. Family comparison results are always reported in the Phase A manifest.

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
| `regime$grid_resolution` | `30` | Grid points per dimension for Phase A estimation |
| `regime$rep_grid_resolution` | `10` | Grid points per dimension for Phase B replicate batches (2.25× speedup; individual-replicate precision matters less than 200-draw aggregate) |
| `distance$primary` | `"wasserstein1"` | Optimiser objective |
| `kernel$u_grid_size` | `201` | Transition kernel grid resolution |
| `uncertainty$n_bootstrap` | `200` | Bootstrap replicates |
| `buckets$k3` | `c(45, 55)` | K=3 bucket cutpoints (SGPc scale) |
| `buckets$k5` | `c(40, 45, 55, 60)` | K=5 bucket cutpoints (SGPc scale) |
| `validation$dataset_id` | `"dataset_1"` | Phase A dataset |
| `validation$content_area` | `"MATHEMATICS"` | Preferred Phase A content area |
| `validation$min_subgroup_n` | `500` | Minimum subgroup size |
| `validation$target_subgroup_n` | `2500` | Preferred Phase A subgroup size |
| `systematic$n_conditions_per_dataset` | `10` | Conditions for Phase B |
| `systematic$n_buckets` | `c(1000, 2500, 5000, 7500, 10000)` | Phase B sample-size buckets |
| `systematic$eligibility_buffer` | `0.10` | Eligibility margin for bucket sampling |
| `systematic$outer_reps` | `200` | Outer Monte Carlo replicates per eligible cell |
| `systematic$allow_cluster_pools` | `TRUE` | Enable growth-stratified super-district pools |
| `systematic$n_growth_strata` | `3` | Number of growth strata for cluster pooling |
| `systematic$cluster_min_pool_n` | `500` | Minimum pooled N required for a cluster stratum |
| `systematic$use_parallel` | `TRUE` | Run Phase B Stage 2 with `mirai` |
| `systematic$rep_batch_size` | `5L` | Replicates per parallel task; **set 5 for r8g.48xlarge, 25 for r8g.4xlarge** |
| `seed` | `20260210` | RNG seed for reproducibility |

---

## Dependencies on STEP 1 and STEP 2

### From STEP 1 (Family Selection)

- `analysis_manifest.json` — Recommended copula parameters (ρ, df) by year span
- `canonical_copula_parameters.csv` — Canonical averaged parameters
- `contour_plots/{condition}/copula_results.rds` — Per-condition fitted copulas

### From STEP 2 (SGPc Sensitivity)

- Panel naming conventions and multi-format export patterns
- Error decomposition concept (adapted for sampling vs copula uncertainty in STEP 3)
- **Visual style bridge:** STEP 3 panels reuse the same Zissou1 palette, `theme_publication()`,
  and `save_plot_multi()` conventions as STEP 2 via `functions/step3_publication_style.R`

### Shared Functions

- `functions/sgpc_engine.R` — SGPc computation (ground truth)
- `functions/longitudinal_pairs.R` — Data extraction
- `functions/export_plot_utils.R` — Multi-format plot export
- `STEP_2_SGPc_Sensitivity/phase1_data_loader.R` — Phase 1 data loading utilities

### R Package Dependencies

- `data.table`, `copula`, `jsonlite` (core analytics)
- `ggplot2`, `wesanderson`, `patchwork` (publication visualisations)
- `mirai` (Phase B parallel execution)

---

## Output Contract

After a complete run of Phases A + B + C, the following files are guaranteed in `results/`:

### Tabular Outputs

| File | Columns | Source |
|------|---------|--------|
| `district_summary_grade.csv` | subgroup metadata, inferred/true means and medians, W1 vs uniform, residual metrics, CI width, buckets, quality flags | Phase A |
| `phase_b_systematic_summary.csv` | dataset_id, condition_id, year_span, content_area, subgroup_id, n_subgroup, regime_family, median/mean SGPc inferred and true, diff, wasserstein1, CI widths, convergence | Phase B |
| `phase_b_precision_by_n.csv` | pool_id, pool_type, span, content, n_bucket, n_reps, n_converged, N_eff_bucket, median_bias, median_mae, median_rmse, CI widths (90/95) for median and mean | Phase B |
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
| `step3_manifest.json` | AI-consumable manifest: subgroup estimates, Phase B precision operating table by (year_span × N bucket), error source decomposition, bucket classification |
| `step3_manifest.md` | Human-readable manifest with STEP 3 framework summary and output file table |
| `phase_a_manifest.json` | Phase A deep-dive manifest: condition, estimation, inferred vs true SGPc, independence diagnostics, family comparison, bootstrap CIs |
| `phase_a_manifest.md` | Human-readable Phase A manifest |
| `bucket_stability_summary.json` | Classification consistency by subgroup |
| `run_metadata.json` | Timestamp, config snapshot, R session info, git hash |
| `output_contract_check.json` | File-contract and schema-consistency validation report |

### Validation Checks

- All bucket probabilities sum to ~1 per subgroup (tolerance: 0.001)
- Uncertainty decomposition fields are populated (NA only when source data is unavailable)
- Every publication panel exported as PDF + SVG + PNG
- Output contract check (`output_contract_check.json`) passes required file and manifest
  integrity checks

---

## Visualization Style Policy

STEP 3 panels follow the same visual conventions as STEP 2, enforced via
`functions/step3_publication_style.R`:

| Convention | Specification |
|---|---|
| **Colour palette** | Wes Anderson "Zissou1" — teal (#3B9AB2), light blue (#78B7C5), gold (#EBCC2A), amber (#E1AF00), red (#F21A00) |
| **Theme** | `theme_publication(base_size = 10)` — bold titles, gray30 subtitles, no minor grid, gray80 panel border |
| **Export** | PDF (cairo_pdf) + SVG + PNG @ 300 dpi via `save_plot_multi()` |
| **Dimensions** | 10 × 7 (standard panels), adjusted per panel as needed |
| **Panel naming** | `panel_{letter}_{description}.{pdf,svg,png}` |

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

## Canonical Terminology

| Term | Definition |
|------|-----------|
| **Copula** C_0 | Dependence structure on uniform marginals; from STEP 1 |
| **Baseline kernel** F_0(v\|u) | Conditional CDF ∂C_0(u,v)/∂u; the dependence template |
| **Quantile kernel** Q_0(p\|u) | Inverse conditional map F_0^{-1}(p\|u) |
| **Growth regime** H_S | Subgroup distribution over latent conditional percentiles P ∈ [0,1] |
| **SGPcFlow** | Generated map V = Q_0(P_S\|U), P_S ~ H_S |
| **SGPc** | Student Growth Percentile = 100·F_0(v\|u); conditional rank within the reference population |
| **TAMP** | Traditional NAEP/TIMSS assumption: comonotonic dependence, V = U (rank preservation) |
| **P_S ⊥ U** | Primary identifying assumption: latent conditional percentile independent of prior rank within subgroup |
| **Error 1** | Sampling error from cross-sectional N; characterised by Phase B |
| **Error 2** | Inference/model error from canonical choices; characterised by Phase A |

---

## Troubleshooting

### Issue: "No Phase 1 conditions found"

**Cause:** STEP 1 has not been run, or results are in a different location.

**Fix:** Run STEP 1 first, or verify that
`STEP_1_Family_Selection/results/{dataset_id}/` contains `phase1_copula_family_comparison.csv`.

### Issue: "No subgroups meet min_n"

**Cause:** The dataset does not contain `DISTRICT_NUMBER` or all districts are too small.

**Fix:** Try `SCHOOL_NUMBER` (set `validation$subgroup_col` in config), or lower
`min_subgroup_n`.

### Issue: "Estimation failed" for a subgroup

**Cause:** The grid search found no valid parameter candidate (observed CDF is outside the
predictable range for all regime candidates).

**Fix:** Verify that reference marginals are built from the full state population, not the
subgroup. The subgroup's U and V distributions should *not* be uniform when expressed in
state-reference percentiles.

### Issue: "could not find function process_replicate_batch" (Phase B daemon error)

**Cause:** `environment(worker_lambda) <- baseenv()` — base environment cannot see functions
sourced into daemon `.GlobalEnv`.

**Fix:** Use `environment(worker_lambda) <- globalenv()`. R serialises `globalenv()` as
`GLOBALENV_SXP`, which each daemon resolves to its own `.GlobalEnv` where functions are present.

### Issue: "object '.PHASEB_POOL_DEFS' not found"

**Cause:** Per-condition `everywhere()` block used `<-` instead of `<<-` for `.PHASEB_*`
assignments. `<-` creates local bindings that evaporate; `<<-` walks up to daemon `.GlobalEnv`.

**Fix:** All 11 `.PHASEB_*` assignments must use `<<-`.

### Issue: Large recovery error (|diff| > 10 SGP points)

**Possible causes:**
- Subgroup too small (n < 50): sampling noise dominates
- P_S ⊥ U assumption violated: H_S actually depends on U; check independence diagnostic output
- Copula mismatch: baseline copula does not capture this subgroup's dependence structure

---

## Connection to Paper

### Chapter 4: Growth Regime Inference

STEP 3 provides the main content for Chapter 4. Key elements:

- **Methodology:** The copula-kernel growth regime framework, SGPcFlow, and the analytic
  identity (Section 4.1)
- **Validation:** Recovery of known growth regimes from cross-sectional data; Phase A
  inferred-vs-true comparison (Section 4.2)
- **Results:** Precision as a function of sample size and year span; Phase B operating
  curves directly relevant to NAEP and TIMSS (Section 4.3)
- **Discussion:** Assumptions (P_S ⊥ U), limitations, and conditions for reliable inference
  (Section 4.4)

### Transition to STEP 4 (TIMSS Application)

STEP 3 validates the inference machinery on data where longitudinal ground truth is available.
STEP 4 deploys the same machinery on actual TIMSS data (independent Grade 4 and Grade 8 samples)
where no longitudinal pairing exists — the real-world use case that STEP 3 is designed to
support.

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `README.md` | This documentation |
| `SGPcFlow_Inference_Plan.md` | Detailed mathematical implementation plan |
| `config_step3.R` | Configuration (incl. bucket cutpoints, grid resolution, parallel tuning) |
| `run_step3.R` | Master runner |
| `step3_validation_deep_dive.R` | Phase A: single-condition showcase + ground-truth comparison |
| `step3_systematic_validation.R` | Phase B: multi-condition validation with `mirai` parallelisation |
| `step3_publication_panels.R` | Phase C: figures + manifests + CSV exports |
| `functions/step3_publication_style.R` | Zissou1 style bridge (shared with STEP 2) |
| `functions/reference_marginals.R` | Weighted ECDF + inverse CDF (population-level) |
| `functions/copula_kernel_cache.R` | Precompute F_0(v\|u) on (u,v) grid |
| `functions/regime_families.R` | Beta, trunc-exp, trunc-uniform (sd, IQR, entropy) |
| `functions/predict_v_cdf.R` | Analytic predicted CDF via F_H identity |
| `functions/distance_metrics.R` | W1, CvM, KS |
| `functions/optimize_regime.R` | Grid search + optim() |
| `functions/bootstrap_uncertainty.R` | Sampling + copula uncertainty |
| `functions/bucket_classification.R` | K=3/K=5 bucket probabilities + stability |
| `functions/build_cluster_pools.R` | Growth-stratified super-district pool construction |
| `functions/diagnostics_plots.R` | ggplot2 diagnostic visualisations |
| `functions/manifest_export.R` | JSON/MD export (phase_b_systematic, error sources, bucket classification) |
| `Figures/Analytic_Explanation/` | Synthetic infographic illustrating the LIwLD workflow |
