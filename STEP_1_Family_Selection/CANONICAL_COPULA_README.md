# Canonical Copula Meta-Analysis Results

**Generated:** Option B - Comprehensive Meta-Analysis  
**Purpose:** Empirically-justified canonical copula parameters for new datasets (e.g., TIMSS, PISA)

---

## Output Files

After running `phase1_analysis.R`, you'll find these files in `results/dataset_all/`:

### 1. **Primary Outputs**

| File | Description | Format | Use Case |
|------|-------------|---------|----------|
| `analysis_manifest.json` | Complete structured manifest with all statistics | JSON | AI/programmatic access |
| `analysis_manifest.md` | Human-readable parameter recommendations | Markdown | Documentation |
| `canonical_copula_parameters.csv` | **Main lookup table** for canonical copulas | CSV | R/Python scripts |
| `lookup_canonical_copula.R` | Helper functions for easy parameter lookup | R script | Source in R sessions |

### 2. **Statistical Analysis Outputs**

| File | Description |
|------|-------------|
| `grade_level_analysis.csv` | Grade band effects (elementary/middle/high) |
| `statistical_tests.csv` | Hypothesis test results (content area, year span, grade level effects) |

### 3. **Visualizations** (PDF, SVG, PNG)

| File | Description |
|------|-------------|
| `phase1_parameter_stability_heatmap.*` | CV heatmap across strata (identifies stable vs. variable parameters) |
| `phase1_cv_distribution.*` | Distribution of stability metrics |
| `phase1_absolute_relative_fit.*` | GoF and AIC-based model comparison |
| `phase1_copula_selection_by_condition.*` | Family selection patterns with parameter distributions |
| `phase1_t_copula_phase_diagram.*` | t-copula parameter landscape (ν vs. ρ) |

---

## Quick Start: Looking Up Canonical Copulas

### Option A: Use R Helper Functions (Easiest)

```r
# Load helper functions
source("STEP_1_Family_Selection/results/dataset_all/lookup_canonical_copula.R")

# Show all available canonicals
show_available_canonicals("HIGH")  # Only show highly stable strata

# Create canonical copula for 1-year Mathematics
cop <- create_canonical_copula(year_span = 1, content_area = "MATHEMATICS")

# Get raw parameters
params <- lookup_canonical(year_span = 2, content_area = "ELA")
print(params)  # Shows median, CV, CI, stability classification
```

### Option B: Direct CSV Lookup

```r
library(data.table)

canonicals <- fread("STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv")

# Filter to desired stratum
params <- canonicals[year_span == 1 & content_area == "MATHEMATICS"]

# Create copula
library(copula)
cop <- tCopula(param = params$rho_median, df = params$df_median, dispstr = "un")
```

---

## Understanding the Canonical Lookup Table

### Key Columns in `canonical_copula_parameters.csv`

| Column | Description | Interpretation |
|--------|-------------|----------------|
| `stratum_id` | Unique identifier (e.g., `year_1_mathematics`) | Use for lookup |
| `year_span` | Years between assessments (1-4) | **Primary stratification** |
| `content_area` | MATHEMATICS, ELA, READING, WRITING | **Secondary stratification** |
| `n_conditions` | Number of empirical conditions in stratum | **Sample size** (prefer n ≥ 10) |
| `best_family` | Recommended copula family | Usually "t" |
| **Tau (Kendall's τ)** | | |
| `tau_median` | Median dependence strength | **Use this for predictions** |
| `tau_cv` | Coefficient of variation | Stability metric (lower = more stable) |
| `tau_ci_lower/upper` | 95% bootstrap confidence interval | Uncertainty bounds |
| **Rho (ρ, correlation parameter)** | | |
| `rho_median` | Median correlation parameter for t-copula | **Use this to create copula** |
| `rho_cv` | Coefficient of variation | Stability metric |
| `rho_ci_lower/upper` | 95% bootstrap CI | Uncertainty |
| **Degrees of Freedom (ν)** | | |
| `df_median` | Median degrees of freedom for t-copula | **Use this to create copula** |
| `df_cv` | Coefficient of variation | Stability metric |
| `df_ci_lower/upper` | 95% bootstrap CI | Uncertainty |
| **Stability Assessment** | | |
| `overall_stability` | HIGH, MEDIUM, or LOW | Based on CV across all parameters |

---

## Stability Classification

### What the Stability Metrics Mean

| Stability | Coefficient of Variation (CV) | Interpretation | Action |
|-----------|------------------------------|----------------|--------|
| **HIGH** | CV < 10% | Parameters are highly consistent across conditions | ✅ Safe to use single canonical copula |
| **MEDIUM** | CV 10-20% | Moderate variability | ⚠️ Use canonical, but acknowledge uncertainty |
| **LOW** | CV > 20% | High variability | ⚠️ Consider finer stratification or use CI bounds |

**Example:**
- If `year_1_mathematics` has `overall_stability = "HIGH"` and `rho_cv = 0.08` (8%), the correlation parameter is very stable across all 1-year Math conditions.
- If you use `rho_median = 0.83` for a new TIMSS 1-year Math condition, you can be confident this is representative.

---

## Fallback Hierarchy (Sparse Strata)

When a specific stratum has insufficient data (n < 10), use this hierarchy:

### Level 1: Cross-Stratified (Preferred)
**Query:** `year_span × content_area`  
**Example:** 1-year Mathematics  
**Condition:** n ≥ 10

### Level 2: Year Span Only
**Query:** `year_span` (aggregate across content areas)  
**Example:** All 1-year progressions  
**Condition:** n ≥ 5

### Level 3: Global Median
**Query:** Use `analysis_manifest.json` → `parameter_recommendations` → `by_year_span`  
**Fallback:** When no specific stratum has sufficient data

**Implementation in R:**
```r
lookup_canonical(year_span = 1, content_area = "MATHEMATICS", 
                 min_n = 10, fallback_to_year_span = TRUE)
```

---

## Statistical Hypothesis Tests

Results in `statistical_tests.csv`:

### 1. Content Area Effect
**Hypothesis:** Does Kendall's τ differ across content areas?  
**Test:** Kruskal-Wallis (non-parametric ANOVA)  
**Interpretation:** 
- If **significant** (p < 0.05): Content area matters, use content-specific canonicals
- If **not significant**: Can simplify to year_span-only lookup

### 2. Year Span Trend
**Hypothesis:** Does τ decline monotonically with longer time spans?  
**Test:** Spearman correlation  
**Interpretation:**
- **Negative correlation**: Dependence weakens over time (expected)
- **No correlation**: Unexpected, investigate dataset characteristics

### 3. Grade Level Effect
**Hypothesis:** Does τ differ across elementary/middle/high?  
**Test:** Kruskal-Wallis  
**Interpretation:**
- If **significant**: Add grade_band to stratification
- If **not significant**: Year span and content area are sufficient

---

## Effect Sizes

Results in `analysis_manifest.json` → `effect_sizes`:

### Eta-Squared (η²) for Categorical Factors

| Value | Interpretation | Practical Meaning |
|-------|----------------|-------------------|
| < 0.01 | Negligible | Factor doesn't meaningfully affect parameters |
| 0.01-0.06 | Small | Accounts for 1-6% of variance |
| 0.06-0.14 | Medium | Accounts for 6-14% of variance |
| > 0.14 | Large | Factor is a major source of variability |

**Example:**
- If `content_area` has η² = 0.03 (small), content area explains only 3% of variance in τ.
- This suggests year_span is more important than content_area for canonical selection.

---

## Grade-Level Analysis

Results in `grade_level_analysis.csv`:

### Grade Bands

| Band | Grade Range | Typical Use Case |
|------|-------------|------------------|
| **Elementary** | G3-G5 | Early academic development |
| **Middle** | G6-G8 | Transition to abstract reasoning |
| **High** | G9-G12 | Advanced coursework |

### What to Look For

- **Consistent τ across bands**: Grade level doesn't matter, use year_span × content_area only
- **Declining τ with grade**: Older students show weaker year-to-year correlation (retention effects)
- **Increasing τ with grade**: Older students show stronger correlation (cumulative knowledge)

---

## Example Workflows

### Workflow 1: TIMSS Longitudinal Analysis (No Empirical Copula Available)

**Scenario:** You have TIMSS 4th and 8th grade Math scores from 2019 and 2023 (4-year span), but no empirical copula.

**Steps:**
1. Load helper functions:
   ```r
   source("STEP_1_Family_Selection/results/dataset_all/lookup_canonical_copula.R")
   ```

2. Lookup canonical copula:
   ```r
   params <- lookup_canonical(year_span = 4, content_area = "MATHEMATICS")
   ```

3. Check stability:
   ```r
   if (params$overall_stability == "HIGH") {
     cat("Stable parameters - safe to use canonical\n")
   } else {
     cat("Use with caution - check CI bounds\n")
   }
   ```

4. Create copula:
   ```r
   cop <- tCopula(param = params$rho_median, df = params$df_median, dispstr = "un")
   ```

5. Use in SGP/sgpFlow:
   ```r
   # Your SGP code here, using `cop` as the copula specification
   ```

---

### Workflow 2: Sensitivity Analysis (Test Impact of Canonical Choice)

**Scenario:** You want to test how sensitive SGPc estimates are to copula parameter uncertainty.

**Steps:**
1. Get canonical parameters with CI:
   ```r
   params <- lookup_canonical(year_span = 1, content_area = "MATHEMATICS")
   ```

2. Create three copulas (conservative, median, liberal):
   ```r
   cop_conservative <- tCopula(param = params$rho_ci_lower, 
                                df = params$df_ci_lower, dispstr = "un")
   cop_median <- tCopula(param = params$rho_median, 
                         df = params$df_median, dispstr = "un")
   cop_liberal <- tCopula(param = params$rho_ci_upper, 
                          df = params$df_ci_upper, dispstr = "un")
   ```

3. Run SGPc with each:
   ```r
   sgpc_conservative <- calculate_sgpc(data, cop_conservative)
   sgpc_median <- calculate_sgpc(data, cop_median)
   sgpc_liberal <- calculate_sgpc(data, cop_liberal)
   ```

4. Quantify sensitivity:
   ```r
   sgpc_range <- sgpc_liberal - sgpc_conservative
   cat(sprintf("SGPc range due to copula uncertainty: %.2f\n", median(sgpc_range)))
   ```

---

## Validation: Comparing Canonical vs. Empirical

**Best Practice:** When you have both empirical copula and canonical available:

```r
# Get canonical parameters
params <- lookup_canonical(year_span = 1, content_area = "MATHEMATICS")

# Fit empirical copula (your actual data)
empirical_cop <- fit_copula(your_data)

# Compare Kendall's tau
empirical_tau <- cor(your_data, method = "kendall")
canonical_tau <- params$tau_median

cat(sprintf("Empirical τ: %.3f\n", empirical_tau))
cat(sprintf("Canonical τ: %.3f (95%% CI: [%.3f, %.3f])\n", 
           params$tau_median, params$tau_ci_lower, params$tau_ci_upper))

# Is empirical within canonical CI?
if (empirical_tau >= params$tau_ci_lower && empirical_tau <= params$tau_ci_upper) {
  cat("✅ Empirical copula falls within canonical CI\n")
} else {
  cat("⚠️ Empirical copula outside canonical CI - investigate\n")
}
```

---

## Interpreting Visualizations

### 1. `phase1_parameter_stability_heatmap.pdf`

**What it shows:** CV for τ, ρ, ν across all strata  
**Colors:** GREEN = stable (CV < 10%), ORANGE = moderate (CV 10-20%), RED = variable (CV > 20%)

**How to use:**
- **All green for a stratum?** → Safe to use that canonical copula
- **Any red cells?** → Use cautiously, check CI bounds, consider subset stratification

### 2. `phase1_cv_distribution.pdf`

**What it shows:** Distribution of CV across all parameters and strata  
**Vertical lines:** GREEN = 10% (HIGH threshold), ORANGE = 20% (MEDIUM threshold)

**How to use:**
- **Most CVs < 10%?** → Your canonical copulas are highly reliable
- **Many CVs > 20%?** → High heterogeneity, may need finer stratification

---

## For STEP_2 Sensitivity Analyses

When running STEP_2 experiments, you can:

### 1. Use Canonical Copulas as Baselines
Compare empirical copulas to canonical copulas to quantify dataset-specific effects.

### 2. Test Canonical Robustness
Use the CI bounds to perform sensitivity analyses:
- How much do SGPc estimates change if you use `rho_ci_lower` vs. `rho_ci_upper`?

### 3. Identify Outlier Conditions
Flag conditions where empirical τ falls outside the canonical CI → investigate why.

---

## Citation & Methodology

**Data Source:** 966 conditions across 4 longitudinal assessment datasets  
**Conditions:** Year span (1-4 years) × Content area (Math, ELA, Reading) × Grade levels (G3-G12)  
**Families Tested:** t, Gaussian, Frank, Clayton, Gumbel, Comonotonic  
**Selection Criterion:** AIC (Akaike Information Criterion)  
**Stability Metrics:** 
- Coefficient of Variation (CV = SD / mean)
- Bootstrap 95% confidence intervals (1,000 resamples)
- Inter-quartile range (IQR)
- Median absolute deviation (MAD)

**Statistical Tests:**
- Kruskal-Wallis H-test (non-parametric ANOVA) for categorical factors
- Spearman rank correlation for ordinal trends
- Eta-squared (η²) for effect size quantification

---

## Support & Questions

For questions about using canonical copulas:
1. Check the `analysis_manifest.md` for human-readable summaries
2. Run `show_available_canonicals()` to see all options
3. Consult the visualizations to assess stability
4. Review `statistical_tests.csv` to understand which factors matter most

**Recommendation:** Start with cross-stratified lookup (year_span × content_area) and only fall back to broader strata if n < 10.
