# Deep dive on Section 5.3: why SGP/SGPc and VAM can diverge — and why Gaussian misfit can look like “tight ranks, loose means”

You’re zeroing in on the *right* fault line: **conditional quantiles (SGP/SGPc)** vs **conditional means (VAM)**.  The trick is that the “Gaussian-ness” shows up in *different places* depending on what you’re trying to estimate.

Below I unpack the logic in a way that’s faithful to what your plots are actually showing:

- **Bland–Altman**: agreement on *values* (percentile points)
- **Spearman ρ**: agreement on *ordering*
- **Group mean SGPc**: a mean-of-percentiles functional (not the conditional mean of scores)

And then I connect all of that to why a Gaussian copula (or Gaussian residual assumption) can be “good enough” for some purposes but *provably miscalibrated* for others.

---

## 1) Two estimands, not two “implementations”

Let

- \(Y\) = current score (or current-year scale score)
- \(\mathbf{X}\) = prior score history (one or more prior scores, possibly other predictors)

### SGP / SGPc (quantile / CDF estimand)
A growth percentile is (up to scaling) the **conditional CDF evaluated at the realized outcome**:

\[
\text{SGP} = 100\, F_{Y \mid \mathbf{X}}\bigl(Y \mid \mathbf{X}\bigr).
\]

This is literally a **probability integral transform (PIT)**. If \(F_{Y|\mathbf{X}}\) is correct, then

\[
F_{Y \mid \mathbf{X}}(Y \mid \mathbf{X}) \sim \text{Uniform}(0,1) \quad \text{(conditional on } \mathbf{X}\text{)}.
\]

So SGP/SGPc are about getting the **entire conditional distribution** right (or at least the parts you care about).

### VAM (mean estimand)
A conventional VAM is about the **conditional mean**:

\[
\mu(\mathbf{X}) = \mathbb{E}[Y \mid \mathbf{X}],
\]

often with a group effect added (teacher/school/random effect):

\[
\mathbb{E}[Y \mid \mathbf{X}, g] = \mu(\mathbf{X}) + \delta_g.
\]

So VAM is fundamentally a **first-moment** (mean) object.

**Key point:** even if two models agree perfectly on \(\mathbb{E}[Y\mid\mathbf{X}]\), they can disagree substantially on \(F_{Y\mid\mathbf{X}}\)—and therefore on SGP/SGPc.

---

## 2) When “mean vs quantile” mostly collapses: the elliptical/Gaussian world

In the clean multivariate normal (or more generally **elliptical**) world:

- conditional distributions are symmetric,
- mean = median,
- conditional quantiles are a simple re-expression of the mean + variance,
- percentile ranks are basically a monotone transform of standardized residuals.

Concrete example for a 1-lag model:

\[
Y \mid X=x \sim \mathcal{N}(\alpha + \beta x,\; \sigma^2) \Rightarrow \text{SGP} = 100\,\Phi\left(\frac{Y-(\alpha+\beta x)}{\sigma}\right).
\]

So, under true Gaussian conditions:

- **ordering by SGP** \(\Leftrightarrow\) ordering by residuals,
- **school mean SGP** will correlate strongly with **school mean residual** (hence with a non-covariate VAM).

This is the intuition behind why “mean SGP” and mean-based VAM effects often correlate highly in practice.

---

## 3) How they diverge: the mean can stay put while the CDF shape moves

Here’s the deep reason your section 5.3 exists: **the mean is blind to many distributional changes that matter for ranks/quantiles/percentiles.**

### 3.1 Heteroskedasticity: same mean, different spread
Suppose the conditional mean is correct, but variance depends on \(x\):

\[
Y \mid X=x \sim \mathcal{D}(\mu(x),\sigma^2(x)).
\]

A mean model (VAM-ish) can be basically fine, because it targets \(\mu(x)\).

But SGP/SGPc depend on \(F_{Y|X}(\cdot|x)\), and **variance misspecification** shifts percentiles:

- If the model assumes \(\sigma\) constant while true \(\sigma(x)\) grows with \(x\), then at high \(x\) you’ll systematically see “too many” extreme outcomes relative to the assumed model.
- That translates into **percentiles that are too extreme** (more near 0/100 than should happen) *or* **compressed toward 50**, depending on the direction of misspecification.

This is exactly the kind of phenomenon that can produce:

- Bland–Altman mean difference near 0,
- but a visibly structured spread of differences as a function of the x-axis (“mean of methods”) and a larger SD.

### 3.2 Skewness / mixtures: mean ≠ median
If \(Y|X\) is skewed (or a mixture of subpopulations), the mean and median are no longer tied together.

- A VAM targets \(\mathbb{E}[Y|X]\).
- The “50th percentile growth” targets the conditional median \(Q_{0.5}(Y|X)\).

In a skewed distribution, you can move the median around without moving the mean much (or vice versa). Quantile regression (B-splines) is designed to flexibly capture these shifts.

### 3.3 Tail dependence: a *copula-level* mismatch
This is the big one for your Gaussian copula concern.

A Gaussian copula implies **zero tail dependence** (extremes don’t “stick together” the way they do under many real processes). A t-copula has symmetric tail dependence; Clayton/Gumbel have asymmetric tail dependence.

If real score processes have more joint extremity than the Gaussian copula allows, then the Gaussian copula will misrepresent:

- \(P(Y \text{ very high} \mid X \text{ very high})\),
- \(P(Y \text{ very low} \mid X \text{ very low})\),

which means it misrepresents the *tails* of \(F_{Y|X}\)—and SGP/SGPc live and die by those tails.

This kind of misspecification can show up even when the center of the conditional distribution looks fine.

---

## 4) Correlation is not agreement: why Spearman ρ can stay high while Bland–Altman looks ugly

This is the part that resolves a lot of the “wait, but ranks are high…” tension.

### Spearman ρ answers:
> “Are these two outputs mostly a monotone function of each other?”

### Bland–Altman answers:
> “Do these two outputs give (nearly) the same values, in the same units?”

If

\[
\text{SGPc}^{(G)} \approx g\bigl(\text{SGPc}^{(emp)}\bigr)
\]

for some monotone but non-identity function \(g\), then:

- Spearman ρ can be very high,
- but Bland–Altman differences can be large (and structured), because \(g(u)-u\neq 0\) except at special points.

That’s not a contradiction. It’s the normal (sorry) geometry of monotone transformations.

**Translation into your plots:** Gaussian copula output can track the “general ordering” while being miscalibrated in percentile points.

---

## 5) Why your Gaussian pattern is *exactly* what dependence misfit would produce

Let me interpret your stated pattern in a way that matches your diagnostics:

1. **Empirical vs Gaussian Bland–Altman has much larger SD** than empirical vs best-fit.
   - That says: the Gaussian copula is not just “off by a constant bias,” it’s off in a way that varies across the scale.

2. **Individual-level Spearman ρ is still high** (often ~0.9+), but Gaussian is among the worst.
   - That says: the Gaussian model is “mostly monotone” relative to empirical, but it causes enough local reshuffling to matter.

3. **Group-level (school/district) Spearman ρ drops more for Gaussian** (again second-worst after comonotonic).
   - This is *very consistent* with dependence misfit becoming consequential when you aggregate.

### Why aggregation can make Gaussian misfit *more visible*
A useful mental model is:

\[
\text{SGPc}^{(G)}_{i} = \text{SGPc}^{(emp)}_{i} + b(\mathbf{X}_i) + \epsilon_i,
\]

where:

- \(b(\mathbf{X})\) is a systematic calibration bias that depends on prior achievement (or the “position” in the joint distribution),
- \(\epsilon\) is noise.

When you average within a group \(g\):

\[
\overline{\text{SGPc}}^{(G)}_g - \overline{\text{SGPc}}^{(emp)}_g
= \overline{b(\mathbf{X})}_g + \overline{\epsilon}_g.
\]

As group size grows:

- \(\overline{\epsilon}_g\) shrinks toward 0,
- but \(\overline{b(\mathbf{X})}_g\) **does not**.

So bigger groups can *reveal* systematic model bias more sharply.

Now note the punchline:

- groups differ in their \(\mathbf{X}\) composition (prior score distributions),
- so \(\overline{b(\mathbf{X})}_g\) differs across groups,
- so group rank orderings can change.

That is a very clean mechanism by which **copula misfit (shape/tail dependence)** propagates into **mean SGPc ranking instability**.

### Why mean-of-percentiles is especially sensitive to tail misfit
If Gaussian misfit mostly distorts the tails (which is common), then **mean SGPc** will move more than **median SGPc**, because the mean responds to changes in extreme values.

That matters because:

- median SGP is what many SGP accountability systems use,
- mean SGPc is what you’re using as a proxy for mean-based VAM-like aggregation.

So the very thing that makes mean SGPc a “better proxy” for a mean-based VAM also makes it *more sensitive* to tail calibration errors.

---

## 6) “VAM and mean SGP correlate highly” is not in conflict with “Gaussian SGPc is misfitting”

These statements can be simultaneously true:

- **VAM vs mean SGP** correlations can be very high because both are driven by the central tendency of conditional performance (and because percentiles are monotone transforms of residual-like quantities under broad conditions).

- **Gaussian copula vs empirical SGPc** can show worse stability because Gaussian copula is a statement about *the full dependence structure*, not just \(\mathbb{E}[Y|X]\).

Put differently:

- A VAM can be “mostly okay” for ranking mean shifts even if the distributional shape is wrong.
- But a percentile-based measure is *definitionally* a distribution-shape object.

### Where the Gaussian assumption really bites VAM-style models
Even for mean-based models, Gaussian assumptions can matter in at least three ways:

1. **Inference / uncertainty** (SEs, confidence intervals, shrinkage calibration) can be wrong under non-normality.
2. **Extreme tail behavior** (who gets tagged as exceptional growth/decline) can be very wrong.
3. If the conditional mean model itself is misspecified (nonlinearity, interactions, heteroskedastic random effects), then even ranking can shift.

But it does **not** follow that “all regression-based VAMs are unstable” just because Gaussian copula misfit is visible.

What your results do imply is sharper and more actionable:

> Any method that tries to get *percentiles* out of a Gaussian-shaped conditional model is vulnerable to the kind of calibration/rank instability you’re directly observing.

---

## 7) How to test your hypothesis directly with your current pipeline

If you want to nail down whether the Gaussian instability is “dependence-structure misfit leaking into percentiles,” here are diagnostics that go straight at that claim.

### 7.1 PIT / conditional uniformity checks
For each model \(m\), compute

\[
U_i^{(m)} = \hat F^{(m)}_{Y|\mathbf{X}}(Y_i|\mathbf{X}_i).
\]

If the model is well calibrated, then conditional on \(\mathbf{X}\), \(U\) should be Uniform(0,1).

Practical version:

- plot histograms of \(U\) (overall and by prior quartile),
- look for U-shapes (under/over dispersion) and skew (systematic bias),
- compare Gaussian vs t-canonical vs empirical.

This is basically “Bland–Altman, but for calibration.”

### 7.2 Regress the *difference* on prior score / prior rank
Model

\[
\Delta_i = \text{SGPc}^{(emp)}_i - \text{SGPc}^{(gauss)}_i
\]

as a function of prior score (or prior percentile), possibly with interactions. If you see strong structure:

- you’ve identified the axis along which Gaussian is miscalibrated,
- and you can explain why group composition shifts group means.

### 7.3 Mean vs median aggregation sensitivity
Compute group stability using:

- mean SGPc,
- median SGPc.

If Gaussian instability is tail-driven, mean-based aggregation will look worse.

### 7.4 Tail-focused rank stability
Compute rank stability separately for:

- bottom 10% of prior achievement,
- top 10% of prior achievement.

Gaussian copula should underperform more in those regimes if tail dependence is the culprit.

---

## 8) A tighter, more precise rewrite of Section 5.3

Here’s a version of your text that (i) keeps the core message, (ii) avoids the “mean is stable” overgeneralization, and (iii) ties directly to your diagnostics:

> **Why SGP/SGPc and VAM may diverge more than expected.**
> SGP-type methods estimate **conditional percentiles**: \(\text{SGP} = 100 F_{Y|X}(Y|X)\), which depends on the *full conditional distribution* of current achievement given prior achievement. Traditional VAMs target **conditional means**: \(\mathbb{E}[Y|X]\), often with a group effect on that mean. These estimands coincide only under restrictive conditions (e.g., symmetric/elliptical conditional distributions with correctly specified variance).
>
> In realistic settings with heteroskedasticity, skewness, mixture structure, or tail dependence, two models can agree closely on \(\mathbb{E}[Y|X]\) while disagreeing meaningfully on \(F_{Y|X}\). Consequently, it is coherent to observe high rank correlations (monotone agreement) alongside moderate Bland–Altman dispersion (poor value agreement), and to see aggregation-level instability when model miscalibration interacts with group composition (e.g., differing prior-score distributions across schools/districts). These patterns indicate that mean-based and percentile-based growth summaries are not interchangeable, and that distributional assumptions (including Gaussian dependence) matter most when decisions depend on tail behavior or categorical cutpoints.

---

## Bottom line

Your intuition is basically right, but it’s worth phrasing it precisely:

- **Gaussian copula misfit doesn’t condemn all regression-based VAMs.**
- It *does* say that **Gaussian-shaped conditional distributions are risky as a basis for percentile/rank growth measures**, because percentiles depend on distributional shape and tail behavior.
- The pattern “high ρ but larger Bland–Altman SD” is a classic signature of **monotone-but-miscalibrated mapping**, which is exactly what you’d expect when the dependence structure is misspecified.

