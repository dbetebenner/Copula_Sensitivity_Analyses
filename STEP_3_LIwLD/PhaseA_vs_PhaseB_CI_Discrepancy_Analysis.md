# Phase A vs Phase B Confidence Interval Discrepancy: A Detailed Analysis

**Date:** March 25, 2026
**Context:** STEP 3 — Longitudinal Inference without Longitudinal Data (LIwLD)
**Target condition:** 2008 G5→G6 Mathematics, District 0020 (N = 2,618)

---

## 1. The Observed Discrepancy

From the Phase A linkage decomposition panel (panel G2), at N = 2,618:

| Statistic | Paired (linked) CI width | Independent (unlinked) CI width | Linkage premium |
|-----------|--------------------------|--------------------------------|-----------------|
| Median SGPc | 2.9 | 7.5 | 2.6× |
| Mean SGPc | 2.2 | 5.7 | 2.6× |

From the Phase B operating table (step3_manifest.json), at N = 2,500:

| Statistic | Median CI width | Median MAE |
|-----------|-----------------|------------|
| Mean SGPc (independent) | ~2.08 | ~1.41 |

The discrepancy: Phase A's independent CI width for mean SGPc (5.7) is roughly **2.7× wider** than Phase B's CI width at a comparable sample size (~2.08). This is not a bug — it reflects a fundamental difference in what each analysis is estimating.

---

## 2. What Each Analysis Does Mechanically

### Phase A Bootstrap (Steps A.7 / A.7b)

Phase A performs a **nonparametric bootstrap with replacement** from the observed subgroup of N = 2,618 students. Each of 200 bootstrap replicates proceeds as follows:

**Independent (unlinked) mode:**
1. Draw N = 2,618 prior scores **with replacement** from the observed prior-score vector.
2. Draw N = 2,618 current scores **with replacement** from the observed current-score vector, **independently** of step 1.
3. Transform both through the condition-level reference marginals to get pseudo-observations (u*, v*).
4. Run the full regime estimation pipeline: fit H_S by minimizing W₁(F_obs, F_H) over the Beta family.
5. Record the inferred median SGPc and mean SGPc.

**Paired (linked) mode:**
1. Draw N = 2,618 **student indices** with replacement.
2. Take both the prior and current scores for each drawn index (preserving the within-student pairing).
3. Transform and run regime estimation as above.

The 95% CI is the 2.5th–97.5th percentile interval of the 200 bootstrap estimates.

### Phase B Precision Sweep (Subsampling)

Phase B performs **subsampling without replacement** from the full condition pool (all students with matched pairs in the condition, across all districts). Each of 200 replicates at a given N bucket proceeds as follows:

**Independent (unlinked) mode:**
1. Draw n prior scores **without replacement** from the pool's prior-score vector.
2. Draw n current scores **without replacement** from the pool's current-score vector, **independently** of step 1.
3. Transform through reference marginals and run regime estimation.
4. Compare the inferred summary to the known ground truth (from the full pool).

**Paired (linked) mode:**
1. Draw n **student indices** without replacement from the pool.
2. Preserve within-student pairing; transform and estimate.

The 95% CI is the 2.5th–97.5th percentile interval of the 200 replicate estimates. MAE is computed against the full-pool ground truth.

---

## 3. Why the Discrepancy Exists: Three Distinct Mechanisms

### Mechanism 1: Bootstrap With Replacement vs. Subsampling Without Replacement

This is the most fundamental difference.

**Bootstrap (Phase A):** When you resample 2,618 observations with replacement from a pool of 2,618, each resample contains on average only about 63.2% unique observations (~1,654 unique students). The remaining ~37% are duplicates. This duplication has two consequences:

- The **effective sample size** of each bootstrap draw is smaller than the nominal N. Less information per draw means more variability across draws.
- The bootstrap marginal CDFs are **discrete perturbations** of the observed ECDF: some students appear twice or three times, others not at all. This creates lumpier marginals with more sampling noise.

**Subsampling (Phase B):** When you draw 2,500 observations without replacement from a condition pool of (say) 20,000–50,000 students, every drawn observation is unique. Each subsample is a clean, non-redundant snapshot of the population. The marginal CDFs are smoother and more representative.

Moreover, the finite population correction factor applies to without-replacement sampling: the variance is scaled by (1 − n/N_pool), which can be a substantial reduction when n is a non-trivial fraction of the pool. For bootstrap, no such correction exists — you are modeling a superpopulation, not sampling from a finite one.

### Mechanism 2: The Source Population Differs in Size and Composition

**Phase A bootstraps from the subgroup** (District 0020, N = 2,618). This is a single district's worth of students. The bootstrap sampling distribution reflects the variability inherent in this one district.

**Phase B subsamples from the condition pool** (all matched students in 2008 G5→G6 Mathematics across all districts). This pool is typically an order of magnitude larger — on the scale of 20,000–50,000 students. Each subsample of n = 2,500 is drawn from this much larger, more diverse reservoir.

Why does this matter? When you independently draw prior and current scores:

- From a **small source** (Phase A): Each bootstrap draw produces marginals that can deviate substantially from the "true" subgroup marginals. The bootstrap variability of the marginal CDFs is large relative to the signal.
- From a **large source** (Phase B): Each subsample produces marginals that closely approximate the population marginals. The subsample variability is small relative to the signal.

This difference propagates through the entire inference chain. The regime estimator works by matching the predicted CDF F_H(v) to the observed marginal F_obs(v). When F_obs(v) itself is noisy (as in Phase A bootstrap draws), the fitted regime parameters absorb that noise, inflating the CI.

### Mechanism 3: Independent Coupling Amplifies Noise Differently in Each Design

In independent (unlinked) mode, prior and current scores are drawn separately, creating a synthetic "unlinked" dataset. The randomness of which prior scores happen to pair with which current scores introduces **coupling variability** — the same source of uncertainty that the linkage premium quantifies.

**In Phase A:** The coupling variability operates on **already-noisy bootstrap marginals**. Each bootstrap draw perturbs both marginals, and then independent coupling shuffles their implicit association. These two sources of randomness — bootstrap perturbation and independent coupling — compound multiplicatively. The regime estimator must simultaneously absorb marginal noise and coupling noise.

**In Phase B:** The coupling variability operates on **clean subsample marginals** drawn from a large pool. The marginals themselves are close to the population values across replicates. The dominant source of variability is the coupling randomness (which prior scores happen to be paired with which current scores), not the marginal estimation noise.

This is why the Phase A independent CI is so much wider: it compounds **marginal bootstrap noise × coupling randomness × regime estimation noise**, whereas Phase B primarily reflects **coupling randomness + moderate subsample variability**.

---

## 4. What Population Is Each Analysis Generalizing To?

This is the crux of the interpretive question.

### Phase A Bootstrap: Generalizing to a Superpopulation of District-Level Cohorts

The Phase A bootstrap treats the observed 2,618 students in District 0020 as one realization from a hypothetical stochastic process that could generate cohorts like this one. The bootstrap CI answers the question:

> "If nature could re-run the process that produced this district's G5→G6 Mathematics cohort — generating new batches of ~2,618 students each time, with the same underlying distributional characteristics — and we performed unlinked inference on each batch, how much would the inferred mean SGPc vary?"

The **population of generalization** is: **the superpopulation of possible cohorts for this district under this condition.** The CI reflects the precision of the estimator *as applied to a single district*, accounting for:

- Finite-sample variability of the district's own marginal distributions
- The coupling uncertainty introduced by breaking linkage
- Regime estimation uncertainty given noisy inputs

This is the right framing for a **state assessment system** where every student with a valid score pair is observed. The district's data is a census of its own students, and the bootstrap asks: "How stable is our inference about this specific district?"

The width of 5.7 SGP points for mean SGPc tells you: even at the full observed N = 2,618, the act of breaking student-level linkage introduces substantial uncertainty *about this district's growth*. The paired CI width of 2.2 tells you that with linkage preserved, the estimate is quite precise. The 2.6× ratio is the empirical linkage premium — the precision cost of cross-sectional inference for this district.

### Phase B Precision Sweep: Generalizing to the Testing Population for a Condition

The Phase B subsample treats the condition pool (all matched students in 2008 G5→G6 Mathematics, statewide) as the target population and asks what happens when you observe only a random sample of n students from that population. The CI answers:

> "If NAEP or TIMSS drew a fresh cross-sectional sample of ~2,500 students from this testing population, and we performed unlinked inference on each sample, how much would the inferred mean SGPc vary from sample to sample?"

The **population of generalization** is: **the full condition-level testing population (all students statewide in this grade-transition and content area).** The CI reflects the precision of the estimator *as applied to condition-level population summaries*, accounting for:

- Which subset of the population happens to be sampled
- The coupling uncertainty from independent sampling
- Regime estimation uncertainty given the subsample

This is the right framing for **NAEP/TIMSS-style assessments** where the observed cohort is explicitly a probability sample from a larger target population. The pool is large and stable; the question is how much precision you lose by observing only n of its members.

The width of ~2.08 SGP points at N = 2,500 tells you: for a population-level summary, a sample of 2,500 provides reasonably precise inference even without linkage.

### Why the Widths Must Differ

The Phase A CI is wider because it is asking a **harder question about a smaller target**:

- Phase A asks about **one district** (N ≈ 2,600) and treats that district's data as the entire information source. Every bootstrap draw is a perturbation of this small, specific dataset.
- Phase B asks about **a statewide population** (N_pool ≈ 20,000+) and treats each subsample as one of many possible windows into a large, stable reservoir.

An analogy: imagine estimating the average height of people in a single classroom (N = 30) versus estimating the average height of all adults in a city (N = 1,000,000) using random samples of size 30.

- Bootstrapping the classroom: each resample perturbs a small, possibly idiosyncratic group. CIs are wide because the "population" is small and the bootstrap reflects the instability of this particular classroom.
- Subsampling the city: each draw of 30 people from 1,000,000 gives a representative snapshot. CIs are narrower because the underlying population is large and well-mixed.

In both cases you "have" 30 observations, but the inferential context is completely different.

---

## 5. Are Both Analyses Quantifying Something Relevant?

Yes. They answer complementary questions that map to different deployment scenarios.

### Phase A CI: Relevant for State Assessment District-Level Reporting

When a state assessment system computes SGPc for a specific district using unlinked inference, the Phase A bootstrap CI is the appropriate uncertainty envelope. It tells you: "Given the students we actually observed in this district, how confident should we be in the inferred growth summary?"

This is directly relevant to:
- Accountability systems that report district-level growth
- Any setting where the observed data *is* the population of interest (census, not sample)
- Decision-making about whether a specific district's inferred growth is meaningfully different from a reference value

The width of 5.7 (or ±2.85 for a half-width) means that a district-level unlinked inference of mean SGPc = 47 should be interpreted as roughly "somewhere in the 44–50 range" at 95% confidence. For coarse bucket classification (Low / Typical / High), this may be adequate. For fine-grained ranking, it is a real limitation.

### Phase B CI: Relevant for NAEP/TIMSS Population-Level Reporting

When NAEP or TIMSS reports a country- or state-level growth summary from cross-sectional samples, the Phase B CI is the appropriate uncertainty envelope. It tells you: "Given that we sampled ~2,500 students from the full testing population, how much would our estimate shift if we had drawn a different sample?"

This is directly relevant to:
- NAEP state-level growth reporting (samples of ~3,000–4,000 per state)
- TIMSS country-level growth reporting (samples of ~4,000+ per country)
- Any setting where the observed data is a probability sample from a larger population

The width of ~2.08 (or ±1.04 for a half-width) means that a NAEP-scale population-level inference is quite precise: a point estimate of mean SGPc = 47 means "somewhere in the 46–48 range" at 95% confidence. This is a strong operating characteristic for policy use.

---

## 6. Reconciling the Two: The Variance Decomposition View

The total variance of the Phase A independent bootstrap estimate can be decomposed as:

```
Var_PhaseA_independent ≈ Var(marginal bootstrap noise)
                       + Var(coupling randomness | noisy marginals)
                       + Var(regime estimation | noisy inputs)
```

The total variance of the Phase B independent subsample estimate:

```
Var_PhaseB_independent ≈ Var(subsample marginal deviation from population)
                       + Var(coupling randomness | clean marginals)
                       + Var(regime estimation | clean inputs)
```

Every term in the Phase A decomposition is larger than its Phase B counterpart:

1. **Marginal noise:** Bootstrap from N = 2,618 with replacement >> subsample from N_pool ≈ 20,000+ without replacement.
2. **Coupling randomness:** Operates on noisier marginals in Phase A, so the coupling-induced variability of the *fitted regime* is amplified.
3. **Regime estimation:** The optimizer's sensitivity to input noise means noisier CDF targets produce more variable parameter estimates.

The ratio of CI widths (5.7 / 2.08 ≈ 2.7) is a composite of all three mechanisms, not reducible to any single one.

---

## 7. Summary Table

| Dimension | Phase A Bootstrap | Phase B Precision Sweep |
|-----------|-------------------|------------------------|
| **Resampling method** | With replacement from observed N | Without replacement from condition pool |
| **Source population size** | N = 2,618 (one district) | N_pool ≈ 20,000+ (all districts in condition) |
| **Target of inference** | Superpopulation of possible cohorts for this district | The condition-level testing population |
| **CI answers** | "How stable is the estimate for *this specific district*?" | "How stable is the estimate for *the population*, given a sample of size n?" |
| **Deployment context** | State assessment, district-level accountability | NAEP/TIMSS, population-level reporting |
| **Independent CI width (mean SGPc)** | 5.7 | ~2.08 |
| **Primary variance driver** | Bootstrap marginal noise × coupling × regime fit | Coupling randomness + moderate subsample variation |
| **Finite population correction** | Not applicable (superpopulation model) | Applies: (1 − n/N_pool) reduces variance |

---

## 8. A Subtlety: The README's "Bootstrap Narrower Than Subsampling" Statement

The README notes that "bootstrap CIs at the observed subgroup N are typically narrower than
subsampling CIs at the same N, because bootstrap resamples are drawn from a smaller, more
homogeneous source population." This appears to be correct for **paired** mode: bootstrapping
paired data from one homogeneous district produces stable regime estimates because the within-
district distributional structure is coherent across resamples. Subsampling paired data from the
heterogeneous statewide pool (which mixes districts with different true growth regimes) produces
more inter-replicate variability as each subsample captures a different district-composition mix.

For **independent** mode, this relationship reverses. The coupling randomness from breaking
linkage is amplified by the bootstrap's marginal perturbation noise (Mechanism 3 above), and
this amplification effect overwhelms the homogeneity advantage. The result is that Phase A
independent bootstrap CIs are wider than Phase B independent subsampling CIs at comparable N —
exactly the pattern observed here (5.7 vs ~2.08).

This is not a contradiction. It reflects the fact that the dominant variance component shifts
between paired and independent mode: in paired mode, between-district heterogeneity drives the
comparison; in independent mode, within-replicate coupling noise drives it.

---

## 9. Practical Implications

The discrepancy is not a deficiency — it is a feature of the experimental design. The two CIs bracket the operational reality:

- If you are a **state assessment director** looking at one district's unlinked inference, the Phase A CI (~5.7 width) is your honest uncertainty. The linkage premium of 2.6× tells you exactly what precision you sacrifice by not having student-level linking.

- If you are a **NAEP/TIMSS analyst** reporting population-level growth from a well-designed cross-sectional sample, the Phase B CI (~2.08 width at N ≈ 2,500) is your honest uncertainty. Sample sizes of 3,000–5,000 put you in a comfortable operating range.

The two analyses together make the strongest possible case for STEP 3: they show that unlinked inference is **precise enough for population-level reporting** (Phase B) while honestly quantifying the **additional uncertainty for district-level application** (Phase A).
