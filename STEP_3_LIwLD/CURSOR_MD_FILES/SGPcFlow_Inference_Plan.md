# STEP 3 - SGPcFlow Inference Plan

This document is the implementation plan for STEP 3 in the Copula Sensitivity Analyses project: infer subgroup growth regimes from independent Grade 4 and Grade 8 samples (no student-level pairs) by combining a baseline copula-derived transition kernel with a learnable flow distribution on conditional percentiles.

---

## 0) Executive Summary

### What STEP 3 estimates
- A subgroup-level growth regime distribution `H_S` on latent conditional percentiles `P in [0,1]`.
- Derived summaries: median SGPc, mean SGPc, dispersion, entropy/concentration, and bucket probabilities.

### What STEP 3 does not estimate
- Individual realized SGPc values (not identified without true longitudinal `(x, y)` pairing).

### Core operator view
- Markov matrix analogy: `mu_{t+1} = mu_t P`.
- Copula-kernel analog: `mu_V = mu_U K_H`.
- STEP 3 estimates the subgroup regime so `mu_U K_H` reproduces the observed Grade 8 marginal.

---

## 1) Conceptual Upgrades from the SGP Growth Methods Discussion

### 1.1 Deterministic vs stochastic growth regimes
On percentile scale:
- `U = F_X^ref(X)` prior percentile.
- `V = F_Y^ref(Y)` current percentile.

Deterministic regime:
- `V = g(U)` almost surely.
- Equivalent to a point-mass conditional distribution at each `u`.

Stochastic regime:
- `V | U = u ~ K(u, .)` with non-degenerate spread.

### 1.2 Copula as transition kernel
Given baseline copula `C_0`:

`F_0(v|u) = d/du C_0(u,v)` defines the conditional CDF and therefore the transition kernel.

So STEP 3 separates:
- Dependence template (from STEP 1): `C_0` / `F_0`.
- Flow occupancy rule (to estimate): `H_S`.

### 1.3 Deterministic boundary cases and TAMP
- Comonotonic copula (`C^+(u,v) = min(u,v)`) implies rank-preserving deterministic mapping `V = U`.
- Countermonotonic copula (`C^-(u,v) = max(u+v-1, 0)`) implies deterministic `V = 1-U`.

Operationally, TAMP/equipercentile mapping aligns with the comonotonic deterministic boundary (`V = U`).

### 1.4 Important clarification: "all SGPc = 50" is deterministic, but not necessarily TAMP
Because `SGPc(u,v) = 100 * F_{V|U=u}(v)`, the condition "SGPc = 50 for everyone" means:
- `v = Q_{V|U=u}(0.5)`, the conditional median curve.

That is deterministic for any kernel, but generally not identical to `V = U` unless the dependence template itself is comonotonic.

### 1.5 Anchor definition of SGPcFlow

`sgpcFlow_S: U -> V, with V = Q_0(P_S | U), P_S ~ H_S`

where `Q_0` is induced by baseline kernel `F_0(v|u) = d/du C_0(u,v)`.

Point-mass `H_S` gives deterministic trajectories; dispersed `H_S` gives stochastic flow.

---

## 2) Dependencies on STEP 1 and STEP 2

### 2.1 Inputs from STEP 1
- `analysis_manifest.json`: recommended baseline copula family and parameter sets by year span.
- Parameter uncertainty objects (median/IQR or empirical draws).

### 2.2 Inputs from STEP 2
- Error decomposition pattern (sampling vs model structure).
- Publication panel structure and export conventions.

---

## 3) Mathematical Formulation

### 3.1 Objects
- `X`: Grade 4 raw score.
- `Y`: Grade 8 raw score.
- `F_X^ref`, `F_Y^ref`: fixed reference marginal CDFs.
- `U = F_X^ref(X)`, `V = F_Y^ref(Y)`.
- Baseline copula from STEP 1: `C_0`.

### 3.2 Baseline kernel and quantile kernel
- `F_0(v|u) = Pr(V <= v | U=u) = d/du C_0(u,v)`.
- `Q_0(p|u) = F_0^{-1}(p|u)`.

### 3.3 Regime distribution
- `P_S ~ H_S` on `[0,1]`.
- Baseline identification assumption: `P_S` independent of `U` within subgroup.
- Generated percentile:
  - `V = Q_0(P_S | U)`.

### 3.4 Key analytic identity
Under `P_S independent U`:
- `F_H(v|u) = H(F_0(v|u))`.
- `F_H(v) = E[H(F_0(v|U))]`.
- Sample analog with weights:
  - `F_H(v) ~= sum_i w_i H(F_0(v|u_i)) / sum_i w_i`.

This identity removes Monte Carlo noise in prediction and enables fast optimization over regime parameters.

---

## 4) Identification and Assumptions

### 4.1 Primary identifying assumption
`P_S independent U` within subgroup is the central tractability condition for unpaired marginals.

### 4.2 What is identified
- A low-dimensional subgroup-level regime summary `H_S`.
- Not heterogeneous latent regimes `H_{S}(u)` without additional constraints/data.

### 4.3 Sensitivity extensions
Allow `H_{S}(u)` by `u` bins only as scenario analysis:
- smoothness penalties,
- monotonicity constraints,
- explicit "non-identified" labeling in outputs.

---

## 5) Reference Marginals (Critical)

### 5.1 Why fixed references are required
Subgroup-specific ECDF mapping forces both marginals toward uniform and erases the distribution shift signal STEP 3 needs.

### 5.2 Supported reference strategies
1. Global-cycle reference.
2. Baseline-year reference.
3. External normative reference.

### 5.3 Technical requirements
- Weighted ECDF and weighted inverse CDF.
- Stable tail interpolation and tie handling.
- Cached reusable artifacts.

Outputs:
- `results/reference_marginals/{domain}_{grade}_{year}.rds`
- Companion summary metadata.

---

## 6) Regime Families `H_S`

Implement at least:

### 6.1 Beta family (default)
- Parameterizations: `(alpha, beta)` or `(mean m, concentration kappa)`.
- `alpha = m*kappa`, `beta = (1-m)*kappa`.
- Uniform baseline is `Beta(1,1)`.
- Large-`kappa` limit approximates deterministic point mass at `m`.

### 6.2 Maximum-entropy family under mean constraint
- Truncated exponential on `[0,1]` with parameter chosen to match `E[P]=m`.

### 6.3 Truncated-uniform family
- Continuous `[a,b]` or discrete percentile-grid version.
- Useful to test "shifted but not peaked" alternatives.

### 6.4 Optional mixtures
- Two-component mixtures for bimodal regimes only when diagnostics show persistent single-family misfit.

---

## 7) Estimation Strategy

### 7.1 Inputs per subgroup
- Grade 4 sample `(x_i, w_i)` -> `u_i`.
- Grade 8 sample `(y_j, w'_j)` -> `v_j`.

### 7.2 Kernel cache
For each baseline copula draw `phi`:
- compute `F_0^{(phi)}(v|u)`,
- cache on `(u,v)` grid with monotone interpolation.

Outputs:
- `results/kernel_cache/{family}_{params_hash}.rds`
- Metadata JSON.

### 7.3 Distance objectives
Implement at least:
1. Wasserstein-1 (primary, interpretable percentile-mass displacement).
2. Cramer-von Mises integrated CDF error.

Optional diagnostics:
- KS statistic,
- tail-weighted CvM.

### 7.4 Optimization workflow
1. Coarse grid search over regime parameters.
2. Local refinement (`optim()` with box constraints).
3. Return best-fit parameters, objective minimum, convergence flags.

---

## 8) Uncertainty Decomposition

### 8.1 Sampling uncertainty
- Bootstrap or replicate-weight resampling of Grade 4 and Grade 8 samples.
- Estimate best-fit parameters per replicate.

### 8.2 Copula structural uncertainty
- Draw baseline parameters `phi^(m)` from STEP 1 uncertainty objects.
- Re-optimize over each draw.

### 8.3 Optional regime-family uncertainty
- Compare selected family to alternatives.
- Report contribution to total variance when materially different.

Output table:
- `results/step3_uncertainty_decomposition.csv`

---

## 9) Diagnostics and Trust Checks

Per subgroup:
- observed vs predicted CDF overlay,
- QQ plot,
- residual curve `F_hat(v) - F_obs(v)`,
- bootstrap distribution of fit distances.

Across subgroups:
- distribution of minimized distances,
- persistent-misfit clustering,
- sensitivity to reference choice and baseline copula draw.

---

## 10) Policy-Facing Classification

Implement both:
- K=3 buckets (low, typical, high),
- K=5 buckets (very low to very high).

For each subgroup:
- posterior bucket probabilities,
- classification stability under uncertainty draws.

Outputs:
- `results/step3_bucket_probabilities.csv`
- `results/bucket_stability_summary.json`

---

## 11) Repository Implementation Plan

Recommended STEP 3 directory:

```text
STEP_3_LIwLD/
  README.md
  SGPcFlow_Inference_Plan.md
  config_step3.R
  run_step3.R
  step3_validation_deep_dive.R
  step3_systematic_validation.R
  step3_publication_panels.R
  functions/
    reference_marginals.R
    copula_kernel_cache.R
    regime_families.R
    predict_v_cdf.R
    distance_metrics.R
    optimize_regime.R
    bootstrap_uncertainty.R
    diagnostics_plots.R
    manifest_export.R
  results/
    (generated)
```

Pipeline integration:
- runnable standalone via `run_step3.R`,
- runnable from `master_analysis.R` using project step controls.

---

## 12) Output Contract

Core outputs:
- `results/step3_country_estimates.csv`
- `results/step3_uncertainty_decomposition.csv`
- `results/step3_bucket_probabilities.csv`
- `results/step3_manifest.json`
- `results/step3_manifest.md`
- `results/run_metadata.json`

Publication panels:
- observed-vs-predicted,
- regime family comparison,
- uncertainty decomposition,
- subgroup ranking/buckets,
- copula/reference sensitivity,
- residual heatmaps.

---

## 13) Minimal Synthetic Validation (Required)

Before deployment:
1. Simulate `U`.
2. Choose baseline `C_0`.
3. Choose known `H_S`.
4. Generate `V` then discard pairing.
5. Re-estimate with STEP 3.
6. Quantify recovery vs sample size and year span.

This calibrates expected error bars and failure modes.

---

## 14) Recommended Implementation Sequence

1. Reference marginal builders + tests.
2. Baseline kernel cache + interpolation tests.
3. Regime family APIs (`cdf`, `quantile`, moments).
4. Analytic predicted CDF engine.
5. Distance metrics + optimizer.
6. Sampling and copula uncertainty loops.
7. Diagnostics and panel generation.
8. Manifest export and reproducibility metadata.

---

## 15) Default Configuration (Initial Draft)

```yaml
reference:
  type: baseline_year
  grade4_ref_year: 2019
  grade8_ref_year: 2019
copula:
  family: t
  params_source: STEP_1_manifest
  year_span: 4
  n_param_draws: 25
kernel:
  u_grid: 201
  v_grid: 201
regime:
  family: beta
  grid:
    mean_seq: [0.30, 0.70, 0.01]
    kappa_seq: [2, 200, 2]
distance:
  primary: wasserstein1
  secondary: cvm
uncertainty:
  n_bootstrap: 200
buckets:
  k3: [0.45, 0.55]
  k5: [0.40, 0.45, 0.55, 0.60]
outputs:
  make_publication_panels: true
  make_country_reports: true
```

---

## 16) Terminology Lock

- Copula: dependence structure on uniform marginals.
- Baseline kernel `F_0(v|u)`: conditional CDF induced by baseline copula.
- Quantile kernel `Q_0(p|u)`: inverse conditional map.
- Growth regime `H_S`: subgroup distribution over latent conditional percentiles.
- SGPcFlow: generated map `V = Q_0(P_S|U)` with `P_S ~ H_S`.

---

## 17) Explicit Assumptions

- Fixed-reference percentile mapping is used.
- Primary target is subgroup regime `H_S`, not individual SGPc.
- Baseline copula uncertainty is propagated from STEP 1 recommendations.
- Report probabilistic bucket assignments instead of deterministic labels.
- Heterogeneous-by-prior regimes are treated as sensitivity scenarios unless additional identification structure is introduced.

---

End of plan.
