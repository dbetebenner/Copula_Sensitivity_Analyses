# Experiment 5: Transformation Method Validation

## Overview

**Experiment 5 is the methodological centerpiece of the copula sensitivity investigation.** It is no longer "just another sensitivity analysis" - it validates the entire two-stage transformation approach and identifies which smoothing methods are suitable for Phase 2+ applications.

## Why This Experiment is Critical

### The Problem We Discovered

During Phase 1 (copula family selection), we discovered that:

1. **I-spline with 4 knots** caused Frank copula to falsely win over t-copula (ΔAIC = 2,423)
2. **Pseudo-observations were non-uniform** (K-S test p < 0.001)
3. **Tail dependence was distorted** (64.9% of Frank's AIC advantage came from tails)

This led to the **two-stage transformation approach**:
- **Phase 1 (family selection)**: Use empirical ranks to ensure uniformity and preserve tail dependence
- **Phase 2+ (applications)**: Use carefully validated smoothing methods that provide invertibility

### What This Experiment Does

Experiment 5 systematically tests **15+ transformation methods** across three criteria:

#### Tier 1: Critical (Must Pass)
1. ✓ Selects correct copula family (same as empirical ranks)
2. ✓ Kendall's tau within ±5% of empirical
3. ✓ Tail concentration ratios within ±20% of empirical

#### Tier 2: Important (Should Pass)
4. ✓ K-S test p-value > 0.01 for uniformity
5. ✓ Cramér-von Mises statistic < 0.05
6. ✓ No excessive discretization (< 5% ties)

#### Tier 3: Nice to Have
7. ✓ K-S test p-value > 0.05 (standard threshold)
8. ✓ Provides invertibility (for simulations)
9. ✓ Computationally efficient

## Methods Tested

### Group A: Empirical Baseline (Gold Standard)
- **Empirical ranks (n+1 denominator)** - Primary gold standard
- **Empirical ranks (n denominator)** - Alternative
- **Mid-ranks** - (rank - 0.5) / n

### Group B: I-Spline Variations (Find Breaking Point)
- **I-spline (4 knots)** - KNOWN BAD, included for validation
- **I-spline (9 knots)** - Current default after bug fix
- **I-spline (19 knots)** - More flexible
- **I-spline (49 knots)** - Very flexible
- **I-spline (Tail-Aware, 4 core + 6 tail)** - 10 total knots
- **I-spline (Tail-Aware, 9 core + 6 tail)** - 15 total knots

### Group C: Alternative Spline Methods
- **Q-spline (Quantile Function)** - Direct inverse mapping
- **Hyman Monotone Cubic** - Classic approach
- **Bernstein CDF (Empirical-Beta)** - Shape-safe smoothing with excellent boundary behavior

### Group D: Non-Parametric Methods
- **Kernel (Gaussian)** - Rule-of-thumb bandwidth

### Group E: Parametric Benchmarks (Expected to Fail)
- **Normal CDF** - Demonstrates why parametric fails
- **Logistic CDF** - Alternative parametric

## Running the Experiment

### Quick Start

**From workspace root** (recommended):
```r
# Run validation (estimates 30-45 minutes)
source("STEP_2_Transformation_Validation/exp_5_transformation_validation.R")

# Generate visualizations (5-10 minutes)
source("STEP_2_Transformation_Validation/exp_5_visualizations.R")

# Test new enhancements
source("STEP_2_Transformation_Validation/test_enhancements.R")

# Run operational fitness testing
source("STEP_2_Transformation_Validation/exp_6_operational_fitness.R")
```

**OR from STEP_2_Transformation_Validation directory**:
```r
setwd("STEP_2_Transformation_Validation")
source("exp_5_transformation_validation.R")
source("test_enhancements.R")
```

All scripts automatically detect the working directory and adjust paths accordingly.

### What to Expect

#### Console Output
The script will print progress for each method:
```
--------------------------------------------------------------------
Method 1 of 15: Empirical Ranks (n+1)
--------------------------------------------------------------------

Computing diagnostics...
Fitting copulas...

RESULTS SUMMARY:
  Classification: EXCELLENT
  Suitable for Phase 2: TRUE
  K-S p-value (combined): 0.6234
  Best copula: t (CORRECT)
  Tau bias: 0.0000
  Tail distortion (lower): 0.0000
  Tail distortion (upper): 0.0000
```

#### Output Files

**CSV Summary** (`results/exp5_transformation_validation_summary.csv`):
- Compact table with all key metrics
- Can be imported into LaTeX for paper

**Full Results** (`results/exp5_transformation_validation_full.RData`):
- Complete diagnostic objects
- Pseudo-observations (U, V) for each method
- Copula fits for all families
- Use for deep-dive analysis

**Figures** (`figures/exp5_transformation_validation/`):
1. `uniformity_forest_plot.pdf` - K-S test results for all methods
2. `tail_concentration_comparison.pdf` - Lower/upper tail preservation
3. `copula_selection_results.pdf` - Which copula each method selects
4. `tradeoff_space.pdf` - Uniformity vs. copula correctness scatter
5. `key_methods_comparison.pdf` - Side-by-side comparison of top methods
6. `{method}_dashboard.pdf` - 4×4 diagnostic grid for each key method

## Interpreting Results

### Expected Findings

#### Methods That Should PASS (Tier 1+2+3)
- Empirical ranks (n+1) [GOLD STANDARD]
- I-spline with 49 knots
- I-spline tail-aware (15 knots)
- Q-spline
- Kernel smoothing

#### Methods That Should FAIL (Select Frank)
- I-spline with 4 knots (KNOWN BAD)
- I-spline with 9 knots (still insufficient)
- Normal CDF
- Logistic CDF

#### Methods That Are MARGINAL
- I-spline with 19 knots (borderline)
- Hyman spline (may lack flexibility)

### Key Diagnostic Plots

#### 1. Uniformity Forest Plot
**What it shows**: K-S test p-values for all methods

**How to interpret**:
- Green (p > 0.05): PASS - Pseudo-observations are uniform
- Orange (0.01 < p < 0.05): MARGINAL - Borderline uniformity
- Red (p < 0.01): FAIL - Pseudo-observations NOT uniform

**Action**: Only use methods in green zone for Phase 2

#### 2. Trade-off Space
**What it shows**: Uniformity (x-axis) vs. Copula correctness (y-axis)

**Four quadrants**:
- **Top-right (ideal)**: Good uniformity + Correct copula ✓
- **Bottom-right (acceptable)**: Borderline uniformity but correct copula
- **Top-left (concerning)**: Good uniformity but WRONG copula
- **Bottom-left (terrible)**: Bad uniformity + Wrong copula ✗

**Action**: Only use methods in top-right quadrant

#### 3. Method Dashboards
**What they show**: 4×4 grid of diagnostics for a single method
- Panel 1: Histogram of U (should be flat)
- Panel 2: Q-Q plot vs Uniform(0,1) (should follow red line)
- Panel 3: Scatter U vs V with empirical overlay (should match)
- Panel 4: Chi-plot for tail dependence (should match empirical)

**Action**: Use to diagnose WHY a method fails

## Using Results for Phase 2

After running Experiment 5, check the "PHASE 2 RECOMMENDATIONS" section:

```
====================================================================
PHASE 2 RECOMMENDATIONS:
====================================================================

The following 5 methods are SUITABLE for Phase 2:

  - Empirical Ranks (n+1)
  - I-spline (49 knots)
  - I-spline (Tail-Aware, 15 knots)
  - Q-spline (Quantile Function)
  - Kernel (Gaussian, rule-of-thumb)
```

### Choosing a Method for Phase 2

**If you need invertibility** (for simulations, predictions):
- Use **Q-spline** (provides direct inverse)
- Or **I-spline (49 knots)** with numerical inversion

**If you want maximum accuracy**:
- Use **Empirical ranks** (but no analytic inverse)
- Or **I-spline (Tail-Aware, 15 knots)** with numerical inversion

**If you need computational efficiency**:
- Use **I-spline (19 knots)** if it passes Tier 1+2
- Fast evaluation, reasonable accuracy

## For Your Paper

### Methods Section Text

Use `summary_table` to generate LaTeX tables:

```r
library(xtable)
load("results/exp5_transformation_validation_full.RData")

# Table 1: Method classification
table1 <- summary_table[, .(label, classification, ks_pvalue, 
                            copula_correct, tau_bias)]
print(xtable(table1), include.rownames = FALSE)

# Table 2: Tail preservation
table2 <- summary_table[, .(label, tail_dist_lower, tail_dist_upper)]
print(xtable(table2), include.rownames = FALSE)
```

### Key Finding Statement

> "We tested 15 marginal transformation methods and found that insufficient 
> smoothing flexibility (< 20 interior knots for I-splines) led to non-uniform 
> pseudo-observations (K-S test p < 0.001) and incorrect copula selection 
> (Frank vs. t-copula, ΔAIC = 2,423). This validates our two-stage approach: 
> empirical ranks for family selection (Phase 1) and carefully validated 
> smoothing methods for applications requiring invertibility (Phase 2)."

## Troubleshooting

### Issue: All methods fail Tier 1

**Possible causes**:
1. Data quality issues (check for ties, outliers)
2. Sample size too small (< 1000 pairs)
3. Wrong empirical baseline

**Action**: Review raw data diagnostics and empirical copula fits

### Issue: Computation too slow

**Solutions**:
1. Reduce number of methods tested (comment out parametric benchmarks)
2. Test on smaller sample first (n = 5000)
3. Run on EC2 instance with more cores

### Issue: Unexpected method passes/fails

**Action**: 
1. Review method dashboard for that method
2. Check `all_results[[method_name]]$classification$details`
3. Compare to empirical baseline values

## Next Steps

After completing Experiment 5:

1. **Review results** - Check which methods passed
2. **Select Phase 2 method** - Choose from recommended list
3. **Update Phase 2 experiments** - Use selected method for experiments 1-4
4. **Generate paper figures** - Use exp_5_visualizations.R output
5. **Write methods section** - Use validation as justification

## Timeline

- **Validation run**: 30-45 minutes (depends on number of methods)
- **Visualization generation**: 5-10 minutes
- **Results review**: 30-60 minutes
- **Total**: ~2 hours for complete Experiment 5

## Enhanced Copula-Aware Diagnostics (NEW)

### Phase 2 Enhancements

The validation framework now includes advanced diagnostics specifically designed for copula applications:

#### 1. Tail Rank-Weight Calibration

Compares empirical vs. smoothed PIT tail mass using conditional exceedance curves. This is **CRITICAL** for copulas with tail dependence (t, Clayton, Gumbel).

**Metric**: L1 distance between P(U ≤ q) curves for q ∈ [0.001, 0.20]  
**Thresholds**:
- Tier 1 (PASS): tail_error < 0.02 (2% average deviation)
- Tier 2 (MARGINAL): tail_error < 0.05 (5% average deviation)
- FAIL: tail_error ≥ 0.05

**Why it matters**: Standard uniformity tests (K-S, CvM) may miss localized tail distortions that dramatically affect copula parameter estimates.

#### 2. Bootstrap Parameter Stability

Re-estimates copula on 100-200 bootstrap resamples to measure parameter dispersion.

**Metrics**: CV(τ) and CV(ν) - coefficient of variation for Kendall's τ and degrees of freedom  
**Thresholds**:
- Tier 1 (PASS): CV < 5% (very stable)
- Tier 2 (MARGINAL): CV < 10% (stable)
- FAIL: CV ≥ 10%

#### 3. Operational Fitness Testing (Step 2.5)

Computational performance testing:
- **Forward speed**: > 10k evaluations/sec
- **Inverse speed**: > 1k evaluations/sec
- **Inversion accuracy**: MAE < 0.01 × score_range
- **Memory**: < 100 MB

Run separately: `source("exp_6_operational_fitness.R")`

### New Methods

#### Bernstein CDF
Shape-safe smoothing using Bernstein polynomials with:
- Monotonicity guaranteed by construction
- Excellent boundary behavior
- Auto-tuned degree parameter

#### CSEM-Aware Smoothing
For discrete/heaped scores, treats observations as intervals [x ± CSEM]:
```r
source("methods/csem_aware_smoother.R")
diagnosis <- needs_csem_smoothing(your_scores)
```

## Questions?

If results don't match expectations:
1. Check Phase 1 results (should show t-copula winning with empirical ranks)
2. Review `debug_frank_dominance.R` output (Checkpoint 7)
3. Verify Colorado data loaded correctly
4. Check for package version issues (copula, splines2)
5. If new diagnostics fail, check for extreme discretization

