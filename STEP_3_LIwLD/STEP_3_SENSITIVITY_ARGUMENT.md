# STEP 3 Sensitivity Argument: What the Bridge Costs

## Purpose of this note

This document clarifies the sensitivity argument in `STEP_3_LIwLD` with a direct answer to:

- What is the error cost of inferring subgroup growth from **unidentified** (unlinked) cross-sectional samples?
- What additional error comes from finite sample size (for example, `N ≈ 3,000`)?
- How should these two costs be combined for NAEP/TIMSS-style interpretation?

The analysis uses outputs from:

- `STEP_3_LIwLD/results/phase_a_manifest.json`
- `STEP_3_LIwLD/results/step3_manifest.json`
- `STEP_3_LIwLD/results/phase_b_precision_by_n.csv`
- `STEP_3_LIwLD/results/phase_b_copula_sensitivity.csv`
- `STEP_3_LIwLD/results/phase_b_independence_sensitivity.csv`
- `STEP_3_LIwLD/results/uncertainty_methodology.md`
- `STEP_3_LIwLD/results/step3_uncertainty_decomposition.csv`

---

## 1) What STEP 3 is identifying

STEP 3 does **not** identify student-level realised SGPc without longitudinal pairs.  
Instead, it identifies a subgroup-level latent growth regime `H_S` by matching:

- observed current-score percentile distribution (`F_obs(v)`) and
- model-predicted distribution under the copula kernel plus regime (`F_H(v)`).

Operationally, the bridge has three ingredients:

1. Canonical baseline copula kernel from STEP 1 (here, `t` copula)
2. Regime family (production default here: `beta`)
3. Identification assumption `P_S ⊥ U` within subgroup

So the total STEP 3 error is naturally decomposed as:

- **Error 2 (Inference/Bridge Cost):** cost of unlinked inference + canonical model choices
- **Error 1 (Sampling Cost):** cost of finite cross-sectional sample size

---

## 2) Error 2: Inference/Bridge cost (Phase A evidence)

Phase A uses one subgroup with known longitudinal truth, then "forgets" linkage and re-infers from unlinked marginals.  
For `2008_G5_G6_MATHEMATICS`, subgroup `0020`, `n = 2618`:

- inferred median SGPc: `45.74`
- true median SGPc: `45.00`
- **median error:** `+0.74`
- inferred mean SGPc: `46.73`
- true mean SGPc: `46.60`
- **mean error:** `+0.13`

Interpretation: at full observed subgroup size, the bridge itself introduces a modest point-estimate bias in this showcase condition.

### What this bridge cost includes

This Phase A delta jointly reflects:

- unidentification (no pair-level linkage)
- canonical copula kernel usage
- regime parameterisation and fitting
- independence assumption

In other words, `+0.74` median points is an empirical estimate of the net bridge cost in the validation condition.

---

## 3) Error 1: Sampling cost (Phase B evidence)

Phase B estimates precision vs sample size using 200 outer replicates per eligible cell.

From `step3_manifest.json` operating table (mean across eligible cells):

| N bucket | Median MAE | Median 95% CI width |
|---|---:|---:|
| 1,000 | 1.5322 | 4.0362 |
| 2,500 | 1.4060 | 2.0818 |
| 5,000 | 1.0731 | 1.4481 |
| 7,500 | 1.0918 | 1.2275 |
| 10,000 | 1.0781 | 1.0024 |

Interpretation: sampling error drops substantially from `N=1,000` to `N=5,000`, then flattens.

---

## 4) Explicit NAEP/TIMSS-style scenario: `N ≈ 3,000` unlinked at two time points

`N=3,000` sits between the 2,500 and 5,000 buckets.

Using linear interpolation of the Phase B operating table:

- **sampling median MAE at N≈3,000:** about `1.34`
- **sampling median 95% CI width at N≈3,000:** about `1.96`
  - half-width is about `±0.98`

Now combine with Phase A bridge cost (`0.74` median points):

- **Typical combined error (RSS approximation):**  
  `sqrt(1.34^2 + 0.74^2) ≈ 1.53` SGP points
- **Conservative additive envelope:**  
  `1.34 + 0.74 ≈ 2.08` SGP points

Practical reading:

- a reasonable expected total median-error scale is about `1.5` points
- a conservative planning envelope is about `2.1` points
- with sampling uncertainty around `±1.0` points at 95% for the sampling component

---

## 5) Sensitivity beyond the primary decomposition

Phase B also includes two stress checks that help interpret model-choice risk:

### Copula-parameter sensitivity (`phase_b_copula_sensitivity.csv`, n=25)

- mean absolute `delta_median_vs_base`: `1.967`
- max absolute `delta_median_vs_base`: `5.654`

Interpretation: some subgroups are materially more sensitive to copula parameter movement than others.

### Independence sensitivity (`phase_b_independence_sensitivity.csv`, n=25)

- mean `delta_median`: `-0.654`
- mean absolute `delta_median`: `1.626`
- max absolute `delta_median`: `4.164`
- bucket label changed in `5/25` cases (`k3` and `k5`)

Interpretation: relaxing strict `P_S ⊥ U` can shift subgroup estimates non-trivially in a subset of cases.

---

## 6) Important limitation in this run

`step3_uncertainty_decomposition.csv` reports:

- `var_sampling = 5.047`
- `se_sampling = 2.25`
- `var_copula` is not populated in this run

So this run provides strong empirical quantification for sampling and net bridge error, but not a complete numeric split of copula-parameter variance in the decomposition table.

---

## 7) What "1% sampled from population" implies

For STEP 3 precision, **absolute subgroup sample size `N`** is the dominant driver in current outputs.  
Whether that `N=3,000` is 1% of a large population or 2% of a smaller one is secondary unless finite-population correction is explicitly modeled.

So for current operational use, the right lookup key is the Phase B `N` operating curve, not sampling fraction alone.

---

## 8) Bottom-line answer

For an unlinked two-time-point subgroup with about `N=3,000`:

- inference bridge cost (Phase A-like): about `0.74` median SGP points in the validated showcase
- additional sampling cost (Phase B): about `1.34` median MAE, with about `1.96` CI width
- combined total error expectation: roughly `1.5` points typical, `~2.1` points conservative

This is exactly the STEP 3 sensitivity argument:  
**Error 2 (bridge/inference) + Error 1 (sample size) = quantified total uncertainty for cold-start longitudinal inference from unlinked cross-sections.**
