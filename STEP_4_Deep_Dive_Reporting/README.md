# STEP 4: Deep Dive and Comprehensive Reporting

## Overview

**Paper Section:** Chapter 3, Section 3.4 (Deep Dive & SGPc Analysis); Chapter 4 (TIMSS Application)

**Objective:** Conduct detailed analysis of the selected t-copula, demonstrate SGP vs SGPc concordance, and generate comprehensive publication-ready report integrating results from all previous steps. This step also introduces **SGPc** (copula-based Student Growth Percentiles) as the operational output of the methodology.

**Prerequisites:**
- STEP_1 complete (t-copula selected as best family)
- STEP_2 complete (copula sensitivity validated - CORE CONTRIBUTION)
- STEP_3 complete (transformation methods validated for applications)

---

## What This Step Does

### Part 1: t-Copula Deep Dive
Perform detailed analysis of the selected t-copula:
- Degrees of freedom (ν) estimation and interpretation across conditions
- Tail dependence structure (symmetric tail dependence coefficients)
- Comparison with Gaussian copula baseline
- Conditional distributions P(Y|X) → foundation for SGPc
- Prediction intervals and uncertainty quantification

### Part 2: SGP vs SGPc Analysis (NEW)
**SGPc** = Copula-based Student Growth Percentiles

Compare traditional SGP (using comonotonic assumption) with SGPc (using t-copula):
- Concordance analysis: How closely do SGP and SGPc track?
- Conditional percentile distributions
- Tail behavior comparisons (where differences emerge)
- Practical implications for growth classification

This demonstrates the **operational output** of the Sklar-theoretic extension of TAMP.

### Part 3: Comprehensive Report
Synthesize all results into publication-ready materials:
- Summary tables (LaTeX format) for all 4 steps
- Key figures for main text (emphasizing STEP_2 copula sensitivity)
- Supplementary materials (STEP_3 transformation details)
- Methodology text snippets
- Results text snippets
- SGPc framework documentation

---

## Scripts

### 1. `phase2_t_copula_deep_dive.R`
**Runtime:** ~30-60 minutes  
**Runs only if:** t-copula selected in STEP_1

**What it does:**
- Loads t-copula fits from STEP_1
- Estimates degrees of freedom across conditions
- Computes tail dependence coefficients
- Generates conditional distribution plots
- Creates prediction interval visualizations
- Compares t-copula vs Gaussian copula

**Key Analyses:**
1. **Degrees of Freedom Analysis**
   - Estimate ν for each condition
   - Test if ν varies by grade span, content, cohort
   - Interpret: Lower ν → heavier tails → stronger tail dependence

2. **Tail Dependence Estimation**
   - Upper/lower tail dependence coefficients
   - Compare empirical vs theoretical
   - Visualize joint tail behavior

3. **Conditional Distributions**
   - P(Y|X=x) for various x values
   - Show how future score distribution changes with prior
   - Quantify prediction uncertainty

4. **Gaussian Comparison**
   - Fit both t and Gaussian
   - Likelihood ratio test
   - Show where they differ (tails!)

**Outputs:**
- `results/t_copula_df_by_condition.csv`
- `results/t_copula_tail_dependence.csv`
- `results/t_copula_conditional_distributions.pdf`
- `results/t_copula_vs_gaussian.pdf`
- `results/phase2_t_copula_deep_dive.RData`

---

### 2. `phase2_comprehensive_report.R`
**Runtime:** ~20-40 minutes

**What it does:**
- Loads results from all STEPs
- Generates summary statistics
- Creates publication tables (LaTeX)
- Synthesizes key findings
- Generates final figures for paper
- Writes methodology text snippets

**Report Sections:**

#### A. Executive Summary
- Research questions answered
- Key findings (1-2 sentences each)
- Recommended copula and transformation

#### B. Methodology Summary
- Data: Colorado 2003-2013, Grades 3-10
- Sample sizes by analysis
- Copula families tested
- Selection criteria
- Transformation method selected

#### C. Results Integration

**Table 1:** Copula family selection (from STEP_1)
- Selection frequency by family
- Mean AIC by family
- Winner: t-copula

**Table 2:** Copula sensitivity analyses (from STEP_2) ⭐ **CORE CONTRIBUTION**
- Grade span effects (τ: 0.71 → 0.52 over 4 years)
- Sample size effects (stable by n≈2,000)
- Content area consistency (τ = 0.71 ± 0.03)
- Cohort stability (<5% variation)

**Table 3:** Application implementation (from STEP_3)
- Transformation methods tested (brief summary)
- Selected method: Kernel Gaussian
- Note: Details in Appendix

**Table 4:** t-Copula properties & SGPc (from STEP_4)
- Degrees of freedom by condition (ν ≈ 7-12)
- Tail dependence coefficients (λ ≈ 0.15-0.25)
- Comparison with Gaussian
- SGP vs SGPc concordance metrics

#### D. Key Figures

**Figure 1:** Copula surfaces (conceptual)
- Independence, Gaussian, t, Comonotonic
- From paper background section

**Figure 2:** Family selection results (STEP_1)
- Bar chart of selection frequency
- ΔAIC distributions

**Figure 3:** Copula sensitivity analyses (STEP_2) ⭐ **CORE CONTRIBUTION**
- 2×2 panel: Grade span, Sample size, Content, Cohort
- Demonstrates robustness of Sklar-theoretic extension

**Figure 4:** t-Copula deep dive & SGPc (STEP_4)
- Conditional distributions P(Y|X)
- SGP vs SGPc comparison
- Tail dependence illustration

**Figure 5:** Application implementation (STEP_3) - Optional/Appendix
- Transformation method comparison
- Uniformity validation

**Outputs:**
- `results/comprehensive_report.pdf` - Full PDF report
- `results/tables/` - LaTeX tables (*.tex)
- `results/figures/` - Publication figures (*.pdf)
- `results/methodology_text.txt` - Text for paper methods
- `results/results_text.txt` - Text for paper results
- `results/phase2_comprehensive_report.RData`

---

## How to Run

### Run Full Step 4
```r
# From Copula_Sensitivity_Analyses/ directory
STEPS_TO_RUN <- 4
source("master_analysis.R")
```

### Run Individual Scripts
```r
# From Copula_Sensitivity_Analyses/ directory
setwd("STEP_4_Deep_Dive_Reporting")

# Deep dive (if t-copula selected)
source("phase2_t_copula_deep_dive.R")

# Comprehensive report
source("phase2_comprehensive_report.R")
```

---

## Expected Outputs

### Degrees of Freedom (ν)

**By Grade Span:**
- 1 year: ν ≈ 12 (moderate tails)
- 2 years: ν ≈ 10 (slightly heavier)
- 3 years: ν ≈ 8 (heavier tails)
- 4 years: ν ≈ 7 (heavy tails)

**Interpretation:** Longer time spans → more extreme joint outcomes → heavier tails

### Tail Dependence

**Symmetric (t-copula):**
- Upper tail (λU): 0.15-0.25 (high scorers stay high)
- Lower tail (λL): 0.15-0.25 (low scorers stay low)

**Comparison:**
- Gaussian: λU = λL = 0 (no tail dependence)
- t-copula: λU = λL > 0 (symmetric tail dependence)

### Prediction Intervals

For a student at 90th percentile (X):
- Median prediction: ~85th percentile (regression to mean)
- 95% interval: 60th-95th percentile (wide due to uncertainty)
- t-copula: Slightly wider intervals than Gaussian (accounts for extreme joint outcomes)

---

## Validation

After running, verify:

1. **t-Copula results exist** (if t selected)
   ```r
   load("results/phase2_t_copula_deep_dive.RData")
   names(t_copula_results)
   ```

2. **Comprehensive report generated**
   ```r
   file.exists("results/comprehensive_report.pdf")
   list.files("results/tables/", pattern = "*.tex")
   ```

3. **Key findings documented**
   ```r
   readLines("results/methodology_text.txt")
   readLines("results/results_text.txt")
   ```

---

## Dependencies

**Data:**
- Colorado longitudinal data

**Functions:**
- `../functions/longitudinal_pairs.R`
- `../functions/copula_bootstrap.R`
- `../functions/copula_diagnostics.R`

**From Previous Steps:**
- `../STEP_1_Family_Selection/results/phase1_*.RData` - t-copula selection
- `../STEP_2_Copula_Sensitivity_Analyses/results/exp_*/*.csv` - Sensitivity analyses (CORE)
- `../STEP_3_Application_Implementation/results/exp5_*.RData` - Transformation validation

**Packages:**
- `data.table`, `copula`, `grid`
- `xtable` (for LaTeX tables)
- `gridExtra` (for multi-panel figures)

---

## Troubleshooting

### Issue: "t-copula not selected, skipping deep dive"
**Cause:** STEP_1 selected a different copula

**Expected:** If Frank or another copula won, deep dive script skips automatically.

**Action:** Review STEP_1 results to understand why.

### Issue: Missing results from previous steps
**Cause:** STEP_1-3 not run or results in wrong location

**Fix:**
```r
# Check what's available
file.exists("../STEP_1_Family_Selection/results/phase1_decision.RData")
file.exists("../STEP_2_Transformation_Validation/results/exp5_*.RData")
dir.exists("../STEP_3_Sensitivity_Analyses/results/")

# If missing, run previous steps
STEPS_TO_RUN <- 1:3
source("../master_analysis.R")
```

---

## Connection to Paper

### Application Section Text

This step provides the bulk of content for:

**Section 5.1: Data Sources and Preparation**
- Pull from methodology_text.txt

**Section 5.3: Case Studies**
- National assessment example (Colorado)
- Grade 4→8 mathematics
- t-Copula with ν≈8, τ≈0.71

**Section 5.4: Copula Sensitivity Analyses** ⭐ **CORE CONTRIBUTION**
- Pull from STEP_2 results (NOT STEP_3)
- Demonstrates robustness of Sklar-theoretic extension
- Validates moving beyond TAMP's comonotonic assumption

**Section 5.5: SGP vs SGPc Analysis**
- Concordance between traditional and copula-based growth percentiles
- Practical implications for educational accountability

**Section 6: Conclusion**
- Summary: Sklar-theoretic extension provides stable, generalizable framework
- SGPc as operational output
- Chapter 4 preview: TIMSS application for international benchmarking
- Limitations and future directions

### LaTeX Integration

Tables in `results/tables/` are ready to insert:
```latex
\input{tables/table1_copula_selection.tex}
\input{tables/table2_transformation_validation.tex}
\input{tables/table3_sensitivity_summary.tex}
\input{tables/table4_t_copula_parameters.tex}
```

Figures in `results/figures/` for inclusion:
```latex
\includegraphics{figures/fig2_family_selection.pdf}
\includegraphics{figures/fig3_transformation_validation.pdf}
\includegraphics{figures/fig4_sensitivity_analyses.pdf}
\includegraphics{figures/fig5_t_copula_deep_dive.pdf}
```

---

## Files in This Directory

- `phase2_t_copula_deep_dive.R` - Detailed t-copula analysis
- `phase2_comprehensive_report.R` - Full report generation
- `README.md` - This file
- `results/` - All outputs (created by scripts)
  - `*.RData` - Analysis objects
  - `*.pdf` - Figures
  - `*.csv` - Data tables
  - `tables/` - LaTeX tables
  - `figures/` - Publication figures

---

## Final Step

After STEP_4 completes:

1. Review `results/comprehensive_report.pdf`
2. Integrate tables and figures into paper
3. Use methodology/results text snippets as starting points
4. Cite specific result files in paper (e.g., "See STEP_4_Deep_Dive_Reporting/results/...")

**Paper location:**
`~/Research/Papers/Betebenner_Braun/Paper_1/A_Sklar_Theoretic_Extension_of_TAMP.tex`

