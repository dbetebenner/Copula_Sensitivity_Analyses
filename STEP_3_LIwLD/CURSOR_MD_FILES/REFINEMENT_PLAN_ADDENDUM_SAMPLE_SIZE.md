# Addendum: Phase B sample-size design, district-size constraints, and precision targets

This addendum extends `STEP_3_LIwLD_refinement_plan.md` to incorporate the new empirical finding from Phase A:
even at **N ≈ 2,600**, the bootstrap uncertainty for subgroup-level summaries (e.g., median SGPc) can be
non-trivial (e.g., **SE ≈ 1.7**, implying percentile-based 95% intervals on the order of **~6–8 points**).

The practical implication: Phase B should explicitly (a) **map precision vs N**, (b) enforce a **minimum N**,
and (c) avoid requiring “one gigantic district” to study large-N buckets.

---

## A1) Precision target and implied N scaling (rule-of-thumb)

If the estimator’s standard error scales approximately like `SE(N) ≈ k / sqrt(N)` (often a decent first-order
approximation for smooth functionals), then for any baseline `(N0, SE0)`:

`k = SE0 * sqrt(N0)` and `SE(N) = SE0 * sqrt(N0 / N)`.

If Phase A yields `SE0 ≈ 1.7` at `N0 ≈ 2600`, then:

- N ≈ 5,000 → SE ≈ 1.23  → normal-approx 95% width ≈ 2 * 1.96 * 1.23 ≈ 4.8
- N ≈ 10,000 → SE ≈ 0.87 → normal-approx 95% width ≈ 3.4

These are **benchmarks**, not guarantees (percentile intervals can be wider than normal-approx under skew/heavy
tails), but they motivate the bucket choices below.

**Action:** Phase B must output empirical **CI width vs N** (not just point-estimate error), and Phase C should
surface this as a figure/table so “minimum N” is defensible rather than aesthetic.

---

## A2) Recommended N buckets and eligibility logic

### Buckets
Adopt default buckets:

- `N_bucket ∈ {1000, 2500, 5000, 10000}`

Optionally include `7500` if Phase A scaling suggests it is the “knee” where widths become tolerable.

### Eligibility (without replacement)
For a given *source pool* (district or pooled cluster), define:

- `N_pool` = total paired (longitudinal) records available for the span/content needed to compute “truth”.

A pool is eligible for bucket `N_bucket` iff:

- `N_pool ≥ N_bucket * (1 + buffer)`

Use `buffer = 0.10` by default (10%) to reduce edge effects.

If a district is only eligible up to 2,500, it still contributes to the smaller-bucket curves.

### Effective N (weights-ready)
Also compute **Kish effective sample size**:

`N_eff = (sum w)^2 / sum(w^2)`

Store both `N_raw` and `N_eff`. For unweighted state data, `N_eff = N_raw`. For TIMSS, `N_eff` can be much
smaller than `N_raw`, so Phase B should report precision in terms of `N_eff` as well.

---

## A3) Avoiding the “must have a 10k-student district” trap

Phase B’s goal is to estimate **operating characteristics as a function of N / span / content**, not to
enumerate districts. You can study large-N buckets without requiring a single mega-district by defining
**source pools** that are larger than a district but still substantively coherent.

### Pool types (in priority order)

1) **Single-district pools** (preferred when available)
   - Use only districts with `N_pool` meeting eligibility for the bucket(s).
   - Best for “district is the unit of inference” interpretations.

2) **Clustered “superdistrict” pools** (recommended for large buckets)
   - Cluster districts into K strata based on observable *marginal* features that matter for the inverse problem:
     - prior-score marginal shape (mean, SD, skew/kurtosis in score units or percentile units)
     - baseline achievement level
     - urbanicity / FRPL / demographic mix (if available and stable)
   - Pool longitudinal pairs within each stratum to form `N_pool` large enough for 5k/10k buckets.
   - Interpret as “subgroups defined by similar districts”, which is legitimate because STEP 3’s estimand is a
     **subgroup growth regime H_S**, and S need not be administrative.

3) **Statewide / multi-district pools with stratified sampling**
   - If clustering metadata is weak, define pools by coarse strata (e.g., achievement quintile × region).
   - When drawing subsamples, use stratified sampling over prior percentile bins to mimic plausible district
     prior distributions (optional enhancement).

**Key point:** You are validating the *method’s operating curve*, not the metaphysics of what a “district” is.

---

## A4) Phase B design change: use outer Monte Carlo replicates to estimate CI width

Nested bootstrap (bootstrap inside each subsample) can explode runtime. Phase B can estimate precision more
directly:

- For each pool × (span, content) × N_bucket:
  - Draw `R` independent pseudo-samples of size `N_bucket` from the pool’s longitudinal pairs.
  - For each pseudo-sample:
    - Compute the “truth” summaries from the paired data in the pseudo-sample (e.g., true median SGPc).
    - “Forget” pairing to create cross-sections and run the Step 3 inference to get inferred summaries.
  - Use the empirical distribution across the `R` replicates to estimate:
    - sampling SD of the inferred summary
    - empirical 90% / 95% interval width
    - point-estimate bias and absolute error vs truth

This directly answers: “At N=2500, what interval width should I expect?”

### Recommended defaults
- Outer replicates: `R = 200` (tune up/down)
- Inner bootstrap: **off by default** in Phase B; run it only on a small audit subset (e.g., 10 pools) to
  confirm that the single-sample bootstrap intervals are consistent with the outer-replicate empirical widths.

---

## A5) Concrete code changes (agent checklist)

### 1) Add N-bucket configuration
- Add to `configs/step3_phase_b.yml` (or equivalent):
  - `n_buckets: [1000, 2500, 5000, 10000]`
  - `min_n: 1000`
  - `eligibility_buffer: 0.10`
  - `outer_reps: 200`
  - `use_inner_bootstrap: false`
  - `audit_inner_bootstrap_fraction: 0.05`

### 2) Build pool registry
Create a pool registry CSV (written by a prep script), e.g.:

- `output/phase_b_pool_registry.csv`

Columns:
- `pool_id`, `pool_type` (district / cluster / statewide_stratum)
- `span`, `content`
- `N_pool_raw`, `N_pool_eff`
- `district_ids` (semicolon-delimited if pooled)
- optional: pooled covariate summaries

### 3) Extend Phase B runner to loop by pool × bucket
Modify `step3_systematic_validation.R` (or the Phase B runner) to:

- compute eligibility per pool per bucket
- for each eligible (pool, bucket):
  - run `R` outer replicates (subsample longitudinal pairs; compute truth; drop pairing; infer)
  - save replicate-level results to:
    - `output/phase_b_replicates.parquet` (preferred) or CSV

### 4) Produce new Phase B summary table(s)
Add:

- `output/phase_b_precision_by_n.csv`

At minimum:
- `pool_id`, `pool_type`, `span`, `content`, `n_bucket`
- `median_bias`, `median_mae`, `median_rmse`
- `median_ci_width_90`, `median_ci_width_95` (empirical from outer reps)
- same fields for mean SGPc if tracked
- `N_eff_bucket` (if weights used in sampling)

### 5) Phase C: add or update panels
Update Phase C panel scripts to include:

- **Precision vs N** curves (CI width and MAE vs N)
- optionally: separate lines for span/content

This becomes the empirical justification for:
- `min_n = 1000`
- why 2,500 may still be “wide”, and what improves at 5k/10k

---

## A6) Reporting language (to bake into Step 5 / paper narrative)

When presenting “minimum N”, report it as:

- “For subgroup sizes below ~1,000, uncertainty grows rapidly and estimates become unstable in our validation
  experiments. For N≈2,500, typical 95% intervals for median SGPc are on the order of several percentile points.
  Precision improves roughly with 1/sqrt(N), with materially tighter intervals at N≈5,000–10,000.”

This keeps the claim honest, empirical, and transportable to TIMSS/NAEP where **effective N** matters.

---
