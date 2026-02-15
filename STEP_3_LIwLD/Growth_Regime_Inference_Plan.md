# STEP 3 — Growth Regime Inference Without Longitudinal Pairs (Cross-Sectional Copula/TAMP)

This document is a build plan for implementing **STEP 3** in the Copula Sensitivity Analyses project: inferring **group/subgroup growth regimes** (e.g., TIMSS countries, NAEP states) when you only have **independent samples** at Grade 4 and Grade 8 (no student-level links), using a **baseline copula-derived transition kernel**.

It is written to slot into the existing project conventions (self-contained step folder, reproducible scripts, manifests, publication panels). STEP 1 already produces recommended copula parameters and an AI-consumable manifest (including a TIMSS-like 4-year span example).【223:12†README.md†L46-L61】 STEP 2 already produces a publication panel suite and an error decomposition template you can mimic for STEP 3 outputs.【223:6†README.md†L10-L36】

---

## 0. Executive summary

### What STEP 3 estimates (and what it does *not*)
- **Estimates:** a *distributional object* summarizing how growth percentiles are allocated in a subgroup over the span (call it a **growth regime** \(H_\theta\)), plus uncertainty. Output summaries include **median SGPc**, **dispersion**, and **bucket membership probabilities** (K=3 or K=5).
- **Does not estimate:** individual students’ realized SGPc’s (unidentified without true \((x,y)\) pairs).

### Conceptual mapping
This is the copula-analytic analog of your Markov transition story:

- Markov case: \(\mu_{t+1} = \mu_t \, P\) where \(P\) is a transition matrix.
- Copula-kernel case: \(\mu_V = \mu_U \, K_\theta\) where \(K_\theta(u,\mathrm{d}v)\) is a **transition kernel** induced by a baseline copula **and** the growth regime \(H_\theta\).

STEP 3 estimates \(\theta\) so that the operator \(\mu_U K_\theta\) matches the observed grade-8 distribution.

---

## 1. Dependencies on STEP 1 and STEP 2

### 1.1 Inputs expected from STEP 1 (family selection)
Use STEP 1’s `analysis_manifest.json` for:
- recommended *baseline* copula family and parameters stratified by **year span**, e.g. “4-year span (TIMSS Grade 4 → Grade 8)” with recommended \( \rho \) and df for a t-copula.【223:12†README.md†L46-L61】
- parameter uncertainty: median/IQR (or full empirical distribution if you exported it).

### 1.2 Inputs expected from STEP 2 (SGPc sensitivity)
Use STEP 2 outputs for:
- benchmarking “how big is sampling noise vs copula choice” (your error decomposition concept).
- mirroring the **publication panel suite** structure and naming conventions (PDF/SVG/PNG) and the enhanced stats cache pattern.【223:6†README.md†L10-L36】

---

## 2. Mathematical formulation (the core of STEP 3)

### 2.1 Objects

Let:
- \(X\) = Grade 4 score (raw scale)
- \(Y\) = Grade 8 score (raw scale)
- \(F_X^{\text{ref}}\), \(F_Y^{\text{ref}}\) = **reference marginal CDFs** used to map scores into \([0,1]\)
- \(U = F_X^{\text{ref}}(X)\), \(V = F_Y^{\text{ref}}(Y)\) = *reference-percentile* pseudo-observations.

You also have a **baseline copula** \(C_0\) on \([0,1]^2\), chosen from STEP 1 recommendations.

Define the baseline conditional CDF / transition kernel:
\[
F_0(v \mid u) = \Pr(V \le v \mid U=u)
              = \frac{\partial}{\partial u} C_0(u,v).
\]

and the baseline conditional quantile function:
\[
Q_0(p \mid u) = F_0^{-1}(p \mid u).
\]

### 2.2 Growth regime
A **growth regime** is a distribution \(H_\theta\) on \([0,1]\) for latent conditional percentiles:
- \(P_\theta \sim H_\theta\)
- often (baseline) assume \(P_\theta \perp U\) within subgroup (can relax later).

Then the implied outcome percentile is
\[
V_\theta = Q_0(P_\theta \mid U).
\]

### 2.3 Key analytic identity (removes Monte Carlo noise)
If \(P_\theta\) is independent of \(U\),
\[
F_\theta(v \mid u)
= \Pr(V_\theta \le v \mid U=u)
= H_\theta\!\left( F_0(v \mid u)\right).
\]

So the subgroup’s predicted marginal CDF is
\[
F_\theta(v)
= \mathbb{E}\!\left[\, H_\theta(F_0(v \mid U)) \,\right]
\approx
\frac{\sum_i w_i \, H_\theta(F_0(v \mid u_i))}{\sum_i w_i}
\]
using the grade-4 sample \(\{u_i,w_i\}\).

This is the analytic “next step” beyond simulation: you can estimate \(\theta\) by minimum distance between the observed grade-8 CDF and this predicted CDF, **without simulating \(P_\theta\)**.

---

## 3. Reference marginals (critical design choice)

### 3.1 Why reference marginals
If you compute \(U\) and \(V\) using each subgroup’s own ECDF, both become uniform and you erase distribution shift. STEP 3 needs a **fixed reference** so that a subgroup’s \(U\) and \(V\) distributions meaningfully encode achievement differences.

### 3.2 Recommended reference options (implement all; choose by config)
1. **Global-cycle reference:** pool all countries (or all states) in a cycle to estimate \(F_X^{\text{ref}}\), \(F_Y^{\text{ref}}\).
2. **Baseline-year reference:** e.g., pre-pandemic as reference to express pandemic cohorts as “baseline percentiles”.
3. **External normative reference:** stable scale transformation (if available).

### 3.3 Required technical features
- Weighted ECDF / quantile functions (survey weights, plausible values).
- Stable tails: monotone interpolation; winsorization rules; tie handling.
- Export the reference CDF objects (or spline approximations) as cached artifacts for reuse.

**Output artifact:** `results/reference_marginals/{domain}_{grade}_{year}.rds` + summary JSON.

---

## 4. Growth regime families \(H_\theta\)

Implement *at least* the following families; each yields a CDF \(H_\theta(\cdot)\) and quantile function \(H_\theta^{-1}(\cdot)\).

### 4.1 Beta family (your current direction)
Parameterize either by \((\alpha,\beta)\) or by (mean \(m\), concentration \(\kappa\)):

- \(m = \alpha / (\alpha+\beta)\)
- \(\kappa = \alpha+\beta\)
- \(\alpha = m\kappa,\ \beta=(1-m)\kappa\)

**Uniform(0,1) is Beta(1,1)** (baseline max-entropy on \([0,1]\)).

Add a degenerate limit case:
- as \(\kappa \to \infty\), Beta collapses to a point mass at \(m\) (numerically you approximate with very large \(\kappa\)).

### 4.2 Maximum entropy under mean constraint (optional but philosophically aligned)
On \([0,1]\), max-entropy with constraint \(E[P]=m\) yields a truncated exponential:
\[
f(p) \propto \exp(\lambda p),\quad p\in[0,1],
\]
with \(\lambda\) chosen to match the mean.

This gives you a principled “least-committed” regime for any mean.

### 4.3 Truncated-uniform family (your “cut off the low end” idea)
Discrete version on \(\{1,\dots,99\}\) or continuous on \([a,1]\), with \(a\) tuned to hit a target median.

Useful for stress-testing “flat but shifted” vs “peaked” regimes.

### 4.4 Mixtures (only if needed)
A two-component mixture can represent “bimodal” systems (e.g., stratified opportunity):
\[
H_\theta = \pi H_{\theta_1} + (1-\pi) H_{\theta_2}.
\]
Use only if residual diagnostics show systematic mismatch under single-family models.

---

## 5. Estimation strategy for \(\theta\)

### 5.1 Data inputs per subgroup g
- Grade-4 sample: \(\{x_i, w_i\}\)  → \(u_i = F_X^{ref}(x_i)\)
- Grade-8 sample: \(\{y_j, w'_j\}\) → \(v_j = F_Y^{ref}(y_j)\)

No pairing needed.

### 5.2 Baseline copula / kernel
For each candidate baseline copula parameter set \(\phi\) (e.g., t-copula with \(\rho,df\)):
- define \(C_0^{(\phi)}\)
- compute \(F_0^{(\phi)}(v|u) = \partial_u C_0^{(\phi)}(u,v)\)

**Implementation tip:** precompute \(F_0(v|u)\) on a grid in \((u,v)\) and use monotone interpolation; this becomes your “kernel cache”.

**Output artifact:** `results/kernel_cache/{family}_{params_hash}.rds` + metadata JSON.

### 5.3 Objective functions (distance metrics)
Implement at least two (selectable in config):

1. **Wasserstein-1 (Earth mover) on \([0,1]\)**  
   Good interpretability (“how much percentile mass must move”).  
   Compute between observed \(F_{\text{obs}}\) and predicted \(F_\theta\).

2. **Cramér–von Mises (CvM) / integrated squared CDF error**  
   Numerically stable; works directly with CDFs:
   \[
   D_{CvM}(\theta)=\int_0^1 (F_\theta(v)-F_{\text{obs}}(v))^2\,dv.
   \]

Optional add-ons:
- tail-weighted CvM (to prioritize lower/upper tail fit),
- KS as a diagnostic (not necessarily as optimizer).

### 5.4 Optimization workflow (robust, reproducible)
Use a two-stage approach:
1. **Coarse grid search** over plausible \(\theta\) (e.g., mean in 0.25–0.75, concentration in 2–200).
2. **Local refinement** using `optim()` (Nelder–Mead or L-BFGS-B with bounds).

Return:
- \(\hat\theta\)
- objective at optimum
- Hessian-based approx SE (if stable) + bootstrap SE (preferred).

### 5.5 Uncertainty quantification
You need *at least* these two layers:

**(A) Sampling uncertainty (within subgroup)**  
- bootstrap / replicate-weight resampling of grade-4 and grade-8 samples.
- for each replicate \(b\): estimate \(\hat\theta_b\).
- summarize with percentile intervals.

**(B) Copula uncertainty (structural)**  
- sample baseline copula parameters \(\phi^{(m)}\) from STEP 1 recommendation distributions (median/IQR or empirical draws).
- for each \(\phi^{(m)}\): run (A) or at least re-optimize \(\hat\theta\).

Produce a variance decomposition analogous to STEP 2’s “comparison vs sampling” panel concept.【223:6†README.md†L29-L36】

### 5.6 Output “growth metrics”
From \(H_{\hat\theta}\), define:
- **Median SGPc:** \(100 \times \text{median}(H_{\hat\theta})\)
- **Mean SGPc** (if desired): \(100 \times E_{H_{\hat\theta}}[P]\)
- **Dispersion:** SD or IQR in SGP points
- **“Common-cause intensity” proxy:** concentration / entropy of \(H_{\hat\theta}\)

---

## 6. Diagnostics (this is where you build trust)

### 6.1 Fit diagnostics per subgroup
Produce:
- observed vs predicted CDF overlays (in \(v\)-space)
- Q–Q plot (observed vs predicted quantiles)
- residual curve \(F_{\hat\theta}(v)-F_{\text{obs}}(v)\)
- distance value(s), with bootstrap distribution

### 6.2 Model adequacy across subgroups
- distribution of minimized distances across all countries
- identify misfit clusters (e.g., consistently bad fit in lower tail)
- sensitivity to regime family choice (beta vs truncated exp vs truncated uniform)

---

## 7. Policy-facing classification (bucket assignment)

### 7.1 Buckets
Implement both:
- **K=3:** low / typical / high growth
- **K=5:** very low / low / typical / high / very high

Bucket boundaries configurable:
- fixed SGP cutpoints (e.g., 40/60, or quintiles),
- or empirical cutpoints from global posterior across countries.

### 7.2 Classification with uncertainty
For each subgroup:
- compute posterior probability of each bucket from bootstrap draws of median SGPc
- report **classification consistency** (expected stability under resampling)

Outputs:
- `country_bucket_probabilities.csv`
- `bucket_stability_summary.json`

---

## 8. Extensions (optional but powerful)

### 8.1 Growth heterogeneity by prior achievement (unidentified without extra assumptions)
You can explore sensitivity by allowing \(H_{\theta(u)}\) to vary by \(u\)-bin, but you must treat it as **scenario analysis**, not identified inference.

Implement a controlled sensitivity module:
- pick \(K\) bins of \(u\) (e.g., quintiles)
- allow mean \(m_k\) per bin with smoothness penalty
- show how many distinct \(m_k\) patterns can still match the same observed \(v\) marginal.

### 8.2 SPC overlay (process monitoring across cycles)
If you estimate \(\hat\theta_{g,t}\) for subgroup g over multiple cycles:
- use a control chart on median SGPc (or on a distance-to-baseline metric)
- interpret:
  - **common-cause** = within-control-limit fluctuation
  - **special-cause** = out-of-control signals or sustained shifts  
The common/special cause distinction and the risk of misinterpretation is central in the SPC literature.【227:0†2019_MacKenzieCameron_DistinguishingBetweenCommon.pdf†L27-L41】

---

## 9. Implementation plan (repository structure + scripts)

### 9.1 New directory (recommended)
Create:

```
STEP_3_Growth_Regime_Inference/
  README.md
  config_step3.yml
  run_step3.R
  functions/
    reference_marginals.R
    copula_kernel_cache.R
    regime_families.R
    predict_v_cdf.R
    distance_metrics.R
    optimize_theta.R
    bootstrap_uncertainty.R
    copula_uncertainty.R
    bucket_classification.R
    diagnostics_plots.R
    manifest_export.R
  results/
    (generated)
```

### 9.2 Integration with master pipeline
Follow the existing pipeline convention: run steps via `STEPS_TO_RUN` and `master_analysis.R` (as in STEP 2 guidance).【223:6†README.md†L86-L93】

You can either:
- make this the new **Step 3**, shifting existing “application implementation” to Step 4, or
- name it Step 3A and keep numbering unchanged.

### 9.3 Parallelization
- parallelize across subgroups and/or bootstrap replicates.
- mirror STEP 1’s scalable approach (mirai) if needed for large country x replicate grids.【223:12†README.md†L65-L79】

---

## 10. Outputs (files + figures)

### 10.1 Core tabular outputs
- `results/step3_country_estimates.csv`
  - subgroup_id, n4, n8, theta_hat, median_sgp, mean_sgp, dispersion, distance_min, flags
- `results/step3_uncertainty_decomposition.csv`
  - subgroup_id, var_sampling, var_copula, var_regime_family, total_var
- `results/step3_bucket_probabilities.csv`
  - subgroup_id, bucket_k3_probs…, bucket_k5_probs…

### 10.2 AI-consumable manifest (mirror STEP 1)
- `results/step3_manifest.json`
  - metadata, configs used, subgroup summaries, top outliers/misfit, recommended defaults
- `results/step3_manifest.md`
  - readable narrative + key tables + how-to-run instructions

### 10.3 Publication panels (mirror STEP 2 naming pattern)
Create in `results/visualizations/`:

- `panel_a_observed_vs_predicted_cdf.{pdf,svg,png}`
- `panel_b_growth_regime_families.{pdf,svg,png}` (show Beta shapes for low/typical/high medians)
- `panel_c_country_rank_and_buckets.{pdf,svg,png}`
- `panel_d_uncertainty_decomposition.{pdf,svg,png}`
- `panel_e_sensitivity_to_copula.{pdf,svg,png}`
- `panel_f_sensitivity_to_reference.{pdf,svg,png}`
- `panel_g_fit_residual_heatmap.{pdf,svg,png}`
- `panel_h_spc_control_chart_over_time.{pdf,svg,png}` (if multi-cycle)

(You can keep the “panel map” concept from STEP 2 for consistent figure assembly.)【223:6†README.md†L58-L73】

---

## 11. Documentation requirements (non-negotiable for STEP 3)

### 11.1 Step-level README must include
- purpose and assumptions
- math summary (kernel + regime + analytic identity)
- inputs and expected column names
- how to run (single subgroup and full batch)
- explanation of outputs + how to interpret distances and buckets
- computational notes (grid sizes, interpolation, seeds)

### 11.2 Function-level docs
- roxygen2 headers for every exported function:
  - parameters, return type, side effects
  - reproducible example (tiny synthetic case)
- internal functions: at least inline comments + input validation

### 11.3 Reproducibility + traceability
- every run writes:
  - `results/run_metadata.json` (timestamp, git hash, config hash, RNG seed, R session info)
  - `results/config_resolved.yml` (the config after defaults applied)
- every output table/figure has a corresponding “builder script” and logs.

---

## 12. Implementation order (recommended “high-wire act” sequence)

1. **Define reference marginals**
   - choose baseline reference, implement weighted ECDF and inverse CDF
   - cache + unit tests

2. **Implement baseline copula kernel**
   - given copula params, compute \(F_0(v|u)\) and \(Q_0(p|u)\)
   - grid + monotone interpolation + cache

3. **Implement regime families**
   - Beta, truncated-uniform, max-entropy truncated exponential
   - return CDF and quantile functions + sanity checks (monotone, bounds)

4. **Implement analytic predicted CDF**
   - \(F_\theta(v)=\sum w_i H_\theta(F_0(v|u_i))/\sum w_i\)
   - compare to empirical CDF of observed \(v\)

5. **Distance metrics + optimizer**
   - Wasserstein-1 and CvM
   - grid search + local refinement

6. **Bootstrap + copula uncertainty**
   - resampling framework for survey weights
   - parameter draws from STEP 1 recommendation distributions

7. **Diagnostics + panels**
   - per subgroup plots + global summaries + publication panel builder

8. **Manifest + reporting**
   - JSON + MD exports aligned to STEP 1/2 style

---

## 13. Minimal synthetic validation (must-have before TIMSS)
Create a simulation harness:
- sample \(U\) from a known distribution
- choose baseline copula \(C_0\)
- choose a known \(H_\theta\)
- generate \(V_\theta\) and then *forget the pairing* (keep only marginals)
- run STEP 3 and verify recovery of \(\theta\) under realistic sample sizes

This gives you identifiability intuition and calibrates expected error bars.

---

## 14. Notes on terminology (to keep writing consistent)
- **copula**: dependence structure on uniform marginals
- **transition kernel** \(F_0(v|u)\): conditional distribution induced by copula
- **quantile kernel** \(Q_0(p|u)\): inverse map in \(v\)
- **growth regime** \(H_\theta\): distribution over conditional percentiles \(p\)
- **induced kernel** \(F_\theta(v|u)=H_\theta(F_0(v|u))\): what you “learn” about growth from cross-sectional shift

---

## 15. Default config suggestions (first draft)

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

## 16. Assumptions made in this plan (explicit)
- You will represent subgroup achievement relative to a **fixed reference** (baseline marginals), not subgroup-specific ECDFs.
- STEP 3’s primary inferential target is **\(H_\theta\)**, summarized by median SGPc; not individual SGPc’s.
- You’ll treat baseline copula choice as **structural** and propagate its uncertainty via draws from STEP 1 recommendations.
- You’ll treat within-subgroup sample variability via bootstrap/replicate weights and report bucket *probabilities* rather than hard labels.

---

End of plan.
