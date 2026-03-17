# Proposal: Churn-as-Partial-Linkage Augmentations to STEP 3

## Context

The attached appendix (§45, "Churn as Partial Linkage") formalizes the idea that student churn — the presence of stayers (S), leavers (L), and entrants (E) — creates a partially observed coupling structure that lies between fully linked longitudinal data and fully unlinked cross-sectional data. This proposal maps that framework onto the existing STEP 3 pipeline (Phases A, B, C) and identifies concrete augmentations.

## Data Availability

The pipeline already has everything needed:

- **`STATE_DATA`** is loaded per dataset and contains ALL students tested at each grade/year/content_area, including unmatched students.
- **`create_longitudinal_pairs()`** returns only matched students (stayers by definition).
- **`build_condition_reference()`** (in `reference_marginals.R`) already computes all-student marginals from `STATE_DATA` using grade/year/content filters — these are the full-wave denominators.

Therefore, for any condition:

```
n_U = |prior wave|       = all students at grade_prior / year_prior / content_area
n_V = |current wave|     = all students at grade_current / year_current / content_area
n_S = |stayers|          = nrow(pairs)   [matched in both waves]
n_L = n_U - n_S          = leavers       [prior only]
n_E = n_V - n_S          = entrants      [current only]
α   = n_S / n_U          = prior retention rate
β   = n_S / n_V          = current retention rate
```

The same decomposition can be computed per subgroup (district/school) by filtering `STATE_DATA` on the subgroup column.

---

## Phase A: Deep Dive Augmentations

Phase A examines a single condition at observed N. Currently it runs paired and independent bootstrap on matched pairs and computes the linkage premium. The augmentations add churn bookkeeping and a diagnostic contrast.

### A.0: Churn Bookkeeping Table (new step)

Insert immediately after `create_longitudinal_pairs()` in `run_deep_dive.R` (~line 142).

**Compute:**
- Condition-level: n_S, n_L, n_E, α, β
- Subgroup-level: same quantities for the focal district/school
- Flag whether α ≈ β (symmetric churn) or α >> β or α << β (asymmetric / observability churn)

**Output:** A `churn_bookkeeping` list included in the Phase A results, containing:
```r
churn_bookkeeping <- list(
  condition_level = data.table(
    n_prior_all, n_current_all, n_stayers, n_leavers, n_entrants,
    alpha = n_stayers / n_prior_all,
    beta  = n_stayers / n_current_all,
    churn_type = classify_churn(alpha, beta)  # "symmetric", "prior_heavy", "current_heavy"
  ),
  subgroup_level = data.table(
    # same columns, one row per subgroup examined
  )
)
```

### A.1: Marginal Comparison — Stayers vs. All (new diagnostic)

**Purpose:** Test Proposition 1 from the appendix — is churn compositionally ignorable?

**Method:**
1. Build stayer-only marginals: `F_U^S`, `F_V^S` (already exist as `u_cross`, `v_cross`)
2. Build all-student marginals: `F_U^all`, `F_V^all` using `build_condition_reference(STATE_DATA, cond)`
3. Compute Wasserstein-1 distances:
   - `Γ_U = W_1(F_U^all, F_U^S)` — prior marginal shift
   - `Γ_V = W_1(F_V^all, F_V^S)` — current marginal shift
4. If `Γ_V >> Γ_U`, flag as likely observability churn (assessment-transition signal)
5. If both are small, churn is compositionally ignorable (benign)

**Visualization (new panel):** Side-by-side density plots showing stayer vs. all-student distributions for both prior and current waves, with Wasserstein distances annotated. This directly illustrates whether leavers/entrants shift the marginals.

### A.2: Regime Contrast — Stayer Regime vs. All-Student Regime (new diagnostic)

**Purpose:** Quantify `Δ_θ = Ψ(H^all) - Ψ(H^stay)` from §7 of the appendix.

**Method:**
1. The stayer regime is already computed (the main Phase A result)
2. Build all-student pseudo-observations: rank all prior-wave students against the stayer reference ECDF, rank all current-wave students against the stayer reference ECDF. This gives `u_all` and `v_all` as pseudo-observations from the full cross-section.
3. Fit the regime to the all-student marginals using the same copula/kernel
4. Compare: `Δ_median = median_sgpc_all - median_sgpc_stayer`, `Δ_mean = mean_sgpc_all - mean_sgpc_stayer`
5. Also compare regime shapes (Beta parameters, Wasserstein distance between H_S^all and H_S^stay)

**Key insight:** This is the diagnostic contrast from §7 of the appendix. Large `Δ_θ` with large `Γ_V` but small `Γ_U` = classic assessment-transition signature.

### A.3: Theoretical Premium Annotation

**Purpose:** Overlay the theoretical partial-linkage premium formula from §5-6 onto the empirical bootstrap results.

**Method:**
1. Using the fitted copula parameter `ρ` and observed `α` (stayer fraction), compute the theoretical SE multiplier: `Π_partial(α, ρ) = sqrt((1 - α*ρ) / (1 - ρ))`
2. Also compute the CDF-scale version using Kendall's τ
3. Annotate the existing linkage premium panel with these theoretical predictions
4. The ratio of empirical premium to theoretical premium isolates how much of the discrepancy is explained by linkage attenuation alone vs. compositional drift

### Phase A Summary Figure (new composite panel)

A single diagnostic figure with four subpanels:
1. **Churn decomposition bar chart:** Stacked bar showing S/L/E counts for prior and current waves
2. **Marginal comparison:** Stayer vs. all-student densities (prior and current), with Γ_U and Γ_V
3. **Regime contrast:** Stayer regime density vs. all-student regime density, with Δ_θ
4. **Premium decomposition:** Empirical linkage premium vs. theoretical partial-linkage prediction

---

## Phase B: Systematic Validation Augmentations

Phase B sweeps across N buckets and linkage fractions. Currently it uses simulated linkage_fraction by drawing paired vs. independent indices from the matched-pairs pool. The augmentations add empirical churn bookkeeping and an optional hybrid resampling mode.

### B.0: Churn Bookkeeping per Pool (new, lightweight)

Insert during Stage 1 pool setup.

**Compute:** For each pool (district or cluster), compute n_S, n_L, n_E, α, β from `STATE_DATA`. This requires one filter pass per pool — feasible because `STATE_DATA` is already loaded per condition.

**Output:** Add columns to `pool_registry`:
```
n_prior_all, n_current_all, n_stayers, n_leavers, n_entrants, alpha, beta
```

These flow into the manifest and provide empirical context for interpreting the linkage_fraction sweep.

### B.1: Empirical Stayer Fraction as Natural linkage_fraction

**Concept:** Currently `linkage_fraction` is a simulation parameter that we sweep across `c(1.0)` (or `c(1.0, 0.75, 0.5, 0.25, 0.0)` when expanded). But each pool has a natural empirical stayer fraction `α` (or `min(α, β)`).

**Augmentation:** After computing churn bookkeeping, automatically include each pool's empirical `α` as a linkage_fraction in the sweep for that pool. This means the precision curve passes through the pool's actual operating point, not just the endpoints.

**Implementation:** In the task grid construction (~line 1240), add the pool's empirical α to the linkage_fractions vector:
```r
pool_lf <- sort(unique(c(linkage_fractions, setup$alpha_empirical)), decreasing = TRUE)
```

This is a small addition to the task grid but gives each pool a data-anchored point on its precision curve.

### B.2: Hybrid Resampling Mode (§8 of appendix — optional, higher cost)

**Concept:** Currently the partial-linkage resampling draws `floor(lf * N)` shared indices and `N - floor(lf * N)` independent indices from the same matched-pairs pool. This simulates linkage attenuation but NOT compositional drift, because all students come from the same (stayer) distribution.

The appendix's §8 proposes a more faithful hybrid:
1. Resample stayers jointly (preserving pairing)
2. Resample leavers for the prior marginal only
3. Resample entrants for the current marginal only
4. Form hybrid marginals and refit

**Implementation consideration:** This requires access to the actual leaver and entrant score distributions, which means pushing leaver/entrant scores to daemons alongside the matched-pair scores. This is architecturally feasible (add `.PHASEB_LEAVER_SCORES` and `.PHASEB_ENTRANT_SCORES` to the `everywhere()` push) but increases memory and complexity.

**Recommendation:** Implement as a Phase B option (`churn_resampling = TRUE/FALSE` in config) but default to FALSE for the initial proof of concept. The simulated linkage_fraction approach already captures the precision effect; the hybrid adds the compositional effect but at higher cost.

### B.3: Churn Sensitivity Curves (new output, conditional on B.2)

If hybrid resampling is enabled, produce a family of curves showing how the inferred regime changes as the stayer fraction varies, holding the leaver/entrant distributions fixed at their empirical values. This directly maps the "churn sensitivity" idea from §8 of the appendix.

---

## Phase C: Publication Panels and Manifest Augmentations

Phase C generates figures and the JSON/Markdown manifest. The augmentations are primarily about surfacing the churn bookkeeping and diagnostic contrasts computed in Phase A and B.

### C.1: Churn Bookkeeping Panel (new)

A table/figure showing S/L/E decomposition across all conditions and pools.

**Format:** Heatmap or grouped bar chart with:
- Rows: conditions (year_span × content_area)
- Columns: n_S, n_L, n_E, α, β
- Color coding: green (α, β > 0.90), yellow (0.80-0.90), red (< 0.80)
- Flag column for asymmetric churn (|α - β| > threshold)

### C.2: Marginal Comparison Summary (new)

Table of Wasserstein distances Γ_U and Γ_V across all conditions/pools. Conditions where Γ_V >> Γ_U are flagged as potential observability churn.

### C.3: Regime Contrast Summary (new)

Table of Δ_θ (median and mean SGPc shift between stayer-only and all-student regime) across conditions/pools.

### C.4: Manifest Updates

Add to the JSON manifest:
- `churn_bookkeeping`: per-condition and per-pool S/L/E counts and rates
- `marginal_comparison`: Γ_U, Γ_V per condition
- `regime_contrast`: Δ_θ per condition
- `churn_classification`: per-condition label (benign / compositional / observability)
- `theoretical_premium`: predicted Π_partial(α, ρ) vs. empirical premium

Add to the Markdown manifest:
- New section: "Churn Decomposition" with the bookkeeping table
- New section: "Compositional Ignorability Test" with Γ_U, Γ_V interpretation
- Updated error taxonomy to include Error 1c (compositional drift from churn)

---

## Implementation Priority

| Item | Phase | Cost | Value | Priority |
|------|-------|------|-------|----------|
| A.0: Churn bookkeeping | A | Low | High | **P0 — do first** |
| A.1: Marginal comparison | A | Low | High | **P0 — do first** |
| A.2: Regime contrast | A | Medium | High | **P1 — do second** |
| A.3: Theoretical premium | A | Low | Medium | P1 |
| B.0: Pool-level bookkeeping | B | Low | High | **P0** |
| B.1: Empirical α in sweep | B | Low | Medium | P1 |
| C.1-C.4: Panels & manifest | C | Medium | High | **P1** |
| B.2: Hybrid resampling | B | High | Medium | P2 — defer |
| B.3: Churn sensitivity curves | B | High | Medium | P2 — defer |

**Recommended first pass:** A.0 + A.1 + B.0 + C.1 + C.4. These are all low-cost additions that produce the bookkeeping table and compositional ignorability test. They require no changes to the resampling machinery — just additional computations on data that's already loaded.

**Second pass:** A.2 + A.3 + B.1 + C.2 + C.3. These add the regime contrast and theoretical premium overlay.

**Deferred:** B.2 + B.3. The hybrid resampling is architecturally sound but adds complexity and compute cost. Worth implementing once the proof of concept establishes the value of the churn decomposition.

---

## Relationship to Existing linkage_fraction Parameter

The existing `linkage_fraction` parameter simulates the **precision effect** of partial linkage by varying the fraction of shared indices in the resampling. The churn augmentations proposed here add three things the current parameter cannot capture:

1. **Empirical bookkeeping:** What is the actual S/L/E decomposition in the data?
2. **Compositional test:** Are leavers/entrants distributionally different from stayers?
3. **Regime contrast:** Does using all-student marginals shift the inferred growth regime?

The `linkage_fraction` parameter remains the right tool for the precision decomposition (Error 1a vs 1b). The churn augmentations layer on top of it to address the substantive questions about what partial linkage means in specific datasets.
