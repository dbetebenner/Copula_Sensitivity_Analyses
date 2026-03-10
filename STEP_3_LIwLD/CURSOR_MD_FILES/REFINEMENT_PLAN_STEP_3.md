# STEP 3 (LIwLD) refinement plan for agent implementation

This document translates the conceptual goals in `README_STEP_3.md` into concrete codebase changes that tighten the validity argument and improve alignment with STEP 2 and STEP 4 (TIMSS). It is written as an **implementation brief** for an engineering agent working inside the existing repository.

---

## 0) Why change anything?

STEP 3 is already structured sensibly as:

- **Phase A**: one deep-dive validation (“showcase”)
- **Phase B**: systematic validation across subgroup size / span / content
- **Phase C**: publication panels + manifests

That structure supports the core claim (“recover a subgroup growth regime from cross-sectional samples”), but two additional scientific needs are not yet first-class:

1. **Assumption stress-testing** (especially the key identifiability assumption `P ⟂ U` inside a subgroup).
2. **Survey-design readiness** (weights + plausible values + replicate-weight variance) so STEP 4 is not a conceptual jump.

This plan keeps A/B/C, but **augments** them with explicit “operating characteristics” and “assumption sensitivity” modules.

---

## 1) Restate the estimand and what must be validated

### 1.1 Estimand
For subgroup `S`, estimate the **growth regime** `H_S` (CDF on `[0,1]`) such that the **predicted current percentile marginal** matches the observed one, given a baseline transition kernel `F_0(v|u)` derived from STEP 1 copula.

The analytic prediction identity is already used:

- `F_H(v) = E[ H( F_0(v|U) ) ]` with the sample approximation.

### 1.2 Validation targets (make these explicit in outputs)
Add explicit “acceptability thresholds” that will be used in the paper and in diagnostics:

- **Point accuracy**: |median_SGPc_hat − median_SGPc_true| (and same for mean)
- **Distribution accuracy**: W1 distance between inferred and true SGPc distributions (or between inferred density and truth)
- **Decision accuracy**: bucket classification stability (K=3 and K=5) under bootstrap and under model perturbations

Add config fields for these thresholds, and propagate them into `district_summary_grade.csv` quality flags.

---

## 2) Phase A changes (deep dive): add assumption diagnostics + decomposition clarity

### 2.1 Add explicit `P ⟂ U` diagnostic using *paired* truth (available in Phase A)
Create a new Phase A export:

- `exports/phase_a/step3_independence_diagnostics.csv`

For the Phase A district/condition (paired data available), compute:

- Spearman correlation: `cor_spearman(U, SGPc_true)`
- Mean/median SGPc by prior-achievement bins (e.g., U quintiles)
- A simple nonparametric test for equality of SGPc distributions across U bins (e.g., Kruskal–Wallis on SGPc_true)

Add a small panel (optional) or at minimum store metrics and add a `flag_independence_violation` in `phase_a_summary.csv` and `district_summary_grade.csv`.

**Files to modify**
- `STEP_3_LIwLD/step3_validation_deep_dive.R` (compute and save diagnostics)
- `STEP_3_LIwLD/functions/manifest_export.R` (include new fields in JSON)

### 2.2 Make the variance decomposition components explicit and reproducible
`step3_uncertainty_decomposition.csv` exists; ensure its methodology is encoded and reproducible:

- Sampling variance: resample `U` and `V` (with replacement; later add weights) and refit `H_S`.
- Copula variance: draw `(rho, df)` from STEP 1 parameter uncertainty (or from a user-specified distribution) and refit.
- Family variance: refit with each enabled regime family (beta / truncexp / truncunif) and take variance across family-specific estimates.

Add a small `results/uncertainty_methodology.md` written by code at runtime describing exactly which resampling and draws were used (config snapshot).

**Files**
- `functions/bootstrap_uncertainty.R` (ensure decomposition is computed from clearly separated loops)
- `run_step3.R` (write the methodology markdown file)

---

## 3) Phase B changes: split “systematic validation” into operating characteristics + assumption stress tests

Keep Phase B as one runner, but produce **three** systematic summary tables instead of one.

### 3.1 B1 — operating characteristics (already mostly there)
Existing: subgroup size × span × content.

Enhance `phase_b_systematic_summary.csv` to include:
- `w1_best`, `w1_uniform`, and `% reduction`
- `max_abs_residual`, `mean_abs_residual`
- bootstrap CI width for median/mean (optional if expensive; sample a subset)

### 3.2 B2 — baseline copula sensitivity *at the inference level*
Even if STEP 2 showed SGPc is robust, the **inverse problem** in STEP 3 can be more sensitive.

Create a new Phase B table:

- `phase_b_copula_sensitivity.csv`

For each subgroup in a selected subset (configurable), refit `H_S` under:
- baseline `t` copula with median params (default)
- baseline `t` copula with `(rho, df)` at e.g. (p25, p75) from STEP 1 manifest
- optional alternative family kernels (Gaussian, Frank) using STEP 1 “runner-up” params (if available)

Store the induced variation in median/mean SGPc and bucket assignment. Feed these deltas into the uncertainty ledger.

**Files**
- `step3_systematic_validation.R` (add copula-variant loop)
- `functions/copula_kernel_cache.R` (support multiple kernels keyed by `{family, rho, df}`)
- `functions/manifest_export.R` (export sensitivity results)

### 3.3 B3 — independence assumption sensitivity (`P ⟂ U`) via stratified regimes
Implement an optional alternative model:

- Instead of one `H_S`, estimate `H_{S,b}` for bins `b` of prior percentile `U` (e.g., quintiles or quartiles).
- Predicted marginal becomes: `F(v) = sum_b Pr(U in bin b) * E[ H_b(F0(v|U)) | U in bin b ]`.

This relaxes the key assumption while staying within the same copula-kernel framework.

Create:
- `phase_b_independence_sensitivity.csv`

For subgroups where Phase A diagnostics suggest violation (or for a configurable subset), compare:
- best single-regime fit (status quo)
- stratified-regime fit (new)

Report:
- improvement in W1/CvM
- change in inferred median/mean
- whether stratification materially changes bucket classification

**Files**
- NEW: `functions/optimize_regime_stratified.R`
- MOD: `functions/predict_v_cdf.R` (support `H` as either single regime or list-by-bin)
- MOD: `functions/optimize_regime.R` (route based on config flag `regime$stratify_by_u = TRUE/FALSE`)

---

## 4) Weight/design support: make STEP 3 “TIMSS-ready” by construction

STEP 4 requires:
- sampling weights (`TOTWGT`)
- plausible values (multiple imputations)
- (often) replicate weights for design-based SEs

Even if STEP 4 ultimately handles plausible values, STEP 3 should be weight-safe.

### 4.1 Weighted ECDF and weighted expectation are *first-class*
Verify and enforce that:
- `reference_marginals.R` accepts weights for building `F^ref` and inverse CDF.
- `predict_v_cdf.R` uses weighted averages over `u_i` when weights are present.

Add an automated check in `output_contract_check.json` that confirms weights were used when supplied.

### 4.2 Add design-based resampling hooks (minimal viable)
Implement a resampling interface that can later be swapped to TIMSS replicate-weight logic:

- `resample_scheme = "srs_bootstrap" | "weighted_bootstrap" | "replicate_weights"`

For now, implement:
- `weighted_bootstrap`: resample indices with probabilities proportional to weights
- keep outputs identical schema-wise

**Files**
- `functions/bootstrap_uncertainty.R` (add weight-aware resampling)
- `config_step3.R` (add `uncertainty$resample_scheme`)

(Replicate-weight support can be implemented in STEP 4, but this hook prevents refactoring later.)

---

## 5) Diagnostics and “model health” scorecard: make failures interpretable

The readme already anticipates “quality flags”. Strengthen them by adding explicit rules:

### 5.1 Add a `model_health` score
For each subgroup, compute:
- `w1_reduction_pct`
- `max_abs_residual`
- `cvm`
- `n_effective` (if weights)

Define:
- `health = "good" | "warn" | "bad"` using config thresholds.

Add these to:
- `district_summary_grade.csv`
- `step3_country_estimates.csv`
- manifest JSON

### 5.2 Add “predictability envelope” check
If the observed CDF is outside the envelope achievable by the regime family given the kernel (the optimizer fails), emit a structured reason:
- kernel too restrictive (copula mismatch)
- regime family too restrictive
- reference marginal mismatch

Store as `fit_failure_reason` in outputs.

---

## 6) Publication panels: add 1–2 panels that defend assumptions

Add at least one new panel for the paper:

- **Panel I**: Independence diagnostic (Phase A): SGPc_true vs U (binned means + CI)
- **Panel J**: Sensitivity summary: variance in median_SGPc across copula params / stratified regime

Implementation can be minimal (PDF + SVG + PNG) following the existing style policy.

**Files**
- `step3_publication_panels.R`
- `functions/diagnostics_plots.R`

---

## 7) Output contract updates

Update the STEP 3 output contract table in `README_STEP_3.md` to include:

New Phase A exports:
- `exports/phase_a/step3_independence_diagnostics.csv`

New Phase B tables:
- `phase_b_copula_sensitivity.csv`
- `phase_b_independence_sensitivity.csv`

Add new manifest fields:
- `assumption_diagnostics`
- `sensitivity.copula_param_range`
- `sensitivity.independence_stratified`

Update `output_contract_check.json` schema validation accordingly.

---

## 8) Implementation order (recommended)

1. **Phase A independence diagnostics** (fast, self-contained; immediately improves narrative)
2. **Weight-safe bootstrap** (small refactor, high leverage for STEP 4)
3. **Copula sensitivity loop** (Phase B2; reuses kernel cache)
4. **Stratified regime option** (Phase B3; bigger change but cleanly modular)
5. **New panels + manifest fields**
6. Update readmes + conformance matrix

---

## 9) Definition of done

- `run_step3.R` completes with Phases A+B+C enabled
- Output contract check passes
- New CSVs appear with non-empty rows
- Phase A report now includes independence diagnostic + health flags
- Phase B includes copula sensitivity and (optional) stratified regime results
- Manifests updated with new fields, and STEP 4 can reuse weight-safe functions without modification

