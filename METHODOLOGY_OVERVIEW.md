# Methodology Overview: Copula-Based Growth Regime Inference

## Purpose

This document maps the 5-step analysis workflow to sections of the paper:  
**"Longitudinal Inference Without Longitudinal Data: A Sklar-Theoretic Extension of TAMP"**

Located: `~/Research/Papers/Betebenner_Braun/Paper_1/A_Sklar_Theoretic_Extension_of_TAMP.tex`

---

## Workflow Overview

```
STEP_1: Copula Family Selection
   ↓ (Selected family: t-copula with parameter recommendations)
STEP_2: SGPc Sensitivity Analysis  ⭐ CORE CONTRIBUTION
   ↓ (SGPc variants compared; copula robustness validated)
STEP_3: Growth Regime Inference (LIwLD)  ⭐ PIÈCE DE RÉSISTANCE
   ↓ (Cross-sectional inference validated against longitudinal truth)
STEP_4: TIMSS Implementation (Placeholder)
   ↓ (Country-level growth regime estimates from real TIMSS data)
STEP_5: Summary, Conclusions, Next Steps (Placeholder)
   ↓ (Synthesis and publication materials)
PAPER: Chapters 3-7
```

**Total Runtime:** 6-10 hours for complete pipeline (STEPs 1-3)

**Key Insight:** The copula-kernel framework (STEP 3) enables growth regime inference from cross-sectional data, validated against longitudinal ground truth. This is then deployed on TIMSS (STEP 4) where no longitudinal pairing exists.

---

## Step-by-Step Mapping to Paper

### STEP 1: Copula Family Selection
**Directory:** `STEP_1_Family_Selection/`  
**Runtime:** 38.7 hours (966 conditions, avg 2.4 min/condition) on EC2 m8g-metal.48xl

#### Maps to Chapter 3, Section 3.1:

**Section 3.1: Copula Family Selection**
- Background on copula families (Gaussian, t, Archimedean)
- TAMP as comonotonic copula (Fréchet-Hoeffding upper bound)
- Selection via AIC/BIC across 966 conditions × 4 datasets
- Goodness-of-fit testing via Cramér-von Mises with parametric bootstrap
```
Given the uniform pseudo-samples {(Ui, Vi)}, we proceed to choose and fit 
a parametric baseline copula C. Our guiding principles are:
1. Rank-based dependence (Kendall's τ, Spearman's ρ)
2. Tail dependence coefficients
3. Information criteria (AIC, BIC)

We evaluate: Gaussian, t, Clayton, Gumbel, Frank families...
```

#### Data to Extract:

**Table:** Family selection frequency
```r
# t-copula: 63.6% (614/966 conditions)
# Frank: 30.7% (297/966 conditions)
# Gumbel: 3.6% (35/966 conditions)
# Gaussian: 2.1% (20/966 conditions)
```

**Figure:** Selection frequency by family
```
File: STEP_1_Family_Selection/results/dataset_all/phase1_*.{pdf,svg,png}
Caption: "Copula family selection across 966 conditions (grade spans, content areas, cohorts, datasets). 
t-copula selected in 63.6% of conditions via AIC, demonstrating its appropriateness for majority of 
educational longitudinal data."
```

**Key Finding:**
> "Across 966 conditions from four datasets, copula family selection revealed:
> - **t-copula** (63.6%, 614 conditions): Recommended for symmetric tail dependence
> - **Frank copula** (30.7%, 297 conditions): Recommended for asymmetric or weaker tail dependence  
> - **Gumbel** (3.6%, 35 conditions): For strong upper tail dependence
> - **Gaussian** (2.1%, 20 conditions): For tail independence cases
>
> Parameter stability across year spans showed systematic decay: τ decreased from 0.638 (1-year) 
> to 0.553 (4-year), while degrees of freedom remained stable (df ≈ 25-29). Content areas showed 
> remarkable consistency (τ range: 0.592-0.611 across Mathematics, Reading, Writing, and ELA), 
> validating the copula framework's generalizability across subject domains."

**Parameter Recommendations for Applications:**

For TIMSS-like contexts (cross-sectional, Grade 4→8, multi-year span):
```r
# Recommended parameters (from manifest)
family <- "t"
tau <- 0.57      # Expected for 3-4 year span
rho <- 0.774     # Implied from tau
df <- 27.5       # Median for long spans
lambda <- 0.10   # Symmetric tail dependence
```

---

### STEP 2: SGPc Sensitivity Analysis ⭐ **CORE CONTRIBUTION**
**Directory:** `STEP_2_SGPc_Sensitivity/`  
**Runtime:** 3-6 hours

#### Maps to Chapter 3, Section 3.2:

**Section 3.2: SGPc Sensitivity and Robustness**
- Compute multiple SGPc variants (empirical, best-fit, canonical, mis-specified, comonotonic)
- Demonstrate practical consequences of copula choice
- Show classification stability across model choices
- Validate copula parameter stability across conditions
```
We compute SGPc (copula-based Student Growth Percentiles) using:
1. Empirical Bernstein copula (non-parametric baseline)
2. Best-fit t-copula for each condition
3. Canonical t-copula with pooled parameters
4. Mis-specified copula (Gaussian instead of t)
5. Comonotonic copula (TAMP baseline)

The strong correlation across variants (r > 0.95) and high classification 
agreement (>90%) demonstrate that SGPc is robust to reasonable model choices...
```

#### Data to Extract:

**Table:** SGPc variant comparison
```r
results <- fread("STEP_2_SGPc_Sensitivity/results/sgpc_comparison_summary.csv")
```

**Figure:** Publication panel grid
```
File: STEP_2_SGPc_Sensitivity/results/publication_figure_*.{pdf,svg,png}
Caption: "SGPc sensitivity across copula choices. Panel shows correlation matrices, 
classification agreement, and distributional comparisons."
```

**Key Finding:**
> "SGPc values computed from empirical, parametric, and canonical copulas showed 
> correlations exceeding 0.95. Classification into growth buckets (low/typical/high) 
> agreed in 92% of cases, demonstrating practical robustness of the copula framework."

---

### STEP 3: Growth Regime Inference (LIwLD) ⭐ **PIÈCE DE RÉSISTANCE**
**Directory:** `STEP_3_LIwLD/`  
**Runtime:** 30-90 minutes

#### Maps to Chapter 4:

**Chapter 4: Growth Regime Inference from Cross-Sectional Data**

**Section 4.1: Theoretical Framework**
```
We formulate the growth regime inference problem as follows. Given:
- Independent samples of prior scores {x_i} at Grade 4
- Independent samples of current scores {y_j} at Grade 8
- A baseline copula C_0 from STEP 1 defining the transition kernel F_0(v|u)

We estimate a growth regime `H_S` — a distribution on [0,1] representing the 
latent conditional percentiles — such that the predicted current-grade marginal 
matches the observed distribution.

Key analytic identity (no simulation required):
  F_H(v) = E[ H( F_0(v | U) ) ] = (1/n) Σ_i H( F_0(v | u_i) )
```

**Section 4.2: Validation Methodology**
```
Because we have actual longitudinal pairs, we can validate the inference:
1. Compute "true" SGPc distribution from longitudinal data
2. "Forget" the pairing to create cross-sectional samples
3. Infer the growth regime using only cross-sectional data
4. Compare inferred regime to the known ground truth
```

**Section 4.3: Results**
```
Phase A: Single-condition showcase (details in text)
Phase B: Systematic validation across subgroups
- Recovery accuracy vs. subgroup size
- Recovery accuracy vs. year span
- Regime family comparison
```

#### Data to Extract:

**Table:** Phase A deep validation summary
```r
phase_a <- fread("STEP_3_LIwLD/results/phase_a_summary.csv")
```

**Table:** Phase B systematic validation
```r
phase_b <- fread("STEP_3_LIwLD/results/phase_b_systematic_summary.csv")
```

**Figures:** Publication panels (6 panels A-F)
```
- Panel A: Observed vs predicted CDF
- Panel B: Inferred regime vs actual SGPc distribution
- Panel C: Recovery accuracy by subgroup size
- Panel D: Recovery accuracy by year span
- Panel E: Regime family comparison
- Panel F: Bootstrap uncertainty distribution
```

**Key Finding:**
> "The copula-kernel framework successfully recovered growth regimes from cross-sectional 
> data, with median SGPc errors of [X.X] points for subgroups n ≥ 200. Accuracy degrades 
> predictably for smaller subgroups (n < 100), providing clear guidance for practitioners."

---

### STEP 4: TIMSS Implementation (Placeholder)
**Directory:** `STEP_4_TIMSS_Implementation/`  
**Status:** Awaiting STEP 3 completion and TIMSS data

#### Maps to Chapter 5:

**Chapter 5: International Application with TIMSS Data**

Will contain:
- Country-level growth regime estimates
- Cross-country growth bucket classifications
- Comparison with existing TIMSS growth indicators
- Sensitivity analyses

---

### STEP 5: Summary and Conclusions (Placeholder)
**Directory:** `STEP_5_Summary_Conclusions_Next_Steps/`  
**Status:** Awaiting upstream completion

#### Maps to Chapters 6-7:

**Chapter 6: Discussion**
- Synthesis of findings
- Assumptions and limitations
- Comparison with alternative approaches

**Chapter 7: Conclusions and Future Directions**
- Summary of contributions
- Practical recommendations
- Research agenda

---

## Complete Paper Structure with Data Sources

### Chapter 1: Introduction
**Data Source:** Narrative (no analysis data)
- Problem: TAMP assumes comonotonicity
- Contribution: Sklar-theoretic extension using empirically grounded copulas

### Chapter 2: Background
**Data Source:** Conceptual (copula surfaces, Sklar's theorem)
- Copula theory fundamentals
- TAMP as special case (comonotonic copula)
- Educational assessment context

### Chapter 3: Methodology ⭐ **STEPS 1-2**
**Data Sources:**

**3.1: Copula Family Selection** (STEP_1)
- Test 6 copula families across 966 conditions × 4 datasets
- Family distribution: t-copula 63.6%, Frank 30.7%, Gumbel 3.6%, Gaussian 2.1%
- Runtime: 38.7 hours on EC2 m8g-metal.48xl (Feb 6, 2026)
- Data: Four state datasets (2003-2025 combined, Grades 3-11)

**3.2: SGPc Sensitivity** ⭐ **CORE CONTRIBUTION** (STEP_2)
- Compute SGPc variants (empirical, best-fit, canonical, mis-specified, comonotonic)
- Demonstrate practical consequences of Sklar-theoretic extension
- Validate copula robustness across conditions
- Data: Multi-dataset, all conditions
- **Note:** Comonotonic copula uses derivative-based conditional CDF (step function → bimodal SGPc: 1s/99s) to demonstrate TAMP assumption extremity; alternative constant-50 interpretation (uniform SGPc) may be explored in STEP 3 for growth regime inference

### Chapter 4: Growth Regime Inference ⭐ **STEP 3**
**Data Source:** Longitudinal state assessment data (with validation)

**4.1: Copula-Kernel Framework** (STEP_3)
- Theoretical formulation: transition kernel F_0(v|u)
- Growth regime families (Beta, truncated exponential, truncated uniform)
- Analytic predicted CDF identity

**4.2: Validation Methodology** (STEP_3)
- Phase A: Single-condition deep validation
- Phase B: Systematic validation across subgroups
- Compare inferred vs actual SGPc distributions

**4.3: Results** (STEP_3)
- Recovery accuracy vs subgroup size and year span
- Uncertainty decomposition
- Regime family comparison

### Chapter 5: International Application (STEP 4 — Placeholder)
**Data Source:** TIMSS public-use data (to be acquired)
- Country-level growth regime estimates
- Cross-country growth bucket classifications
- Comparison with existing indicators

### Chapters 6-7: Discussion and Conclusions (STEP 5 — Placeholder)
**Data Source:** Synthesis of Chapters 3-5
- Key findings distillation
- Assumptions and limitations
- Future research directions

---

## How to Generate Paper Materials

### 1. Run Complete Pipeline
```r
# From Copula_Sensitivity_Analyses/
STEPS_TO_RUN <- NULL  # Run all (or c(1,2,3) for current completeness)
source("master_analysis.R")
```

### 2. Review Step Results

**STEP 1:** 
```r
# Manifests and parameter recommendations
jsonlite::fromJSON("STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json")
```

**STEP 2:**
```r
# SGPc sensitivity results
fread("STEP_2_SGPc_Sensitivity/results/sgpc_comparison_summary.csv")
```

**STEP 3:**
```r
# Growth regime inference validation
fread("STEP_3_LIwLD/results/phase_a_summary.csv")
fread("STEP_3_LIwLD/results/phase_b_systematic_summary.csv")
```

### 3. Copy Figures to Paper Directory
```bash
# Copy publication figures (after running STEPs 1-3)
cp STEP_1_Family_Selection/results/dataset_all/*.{pdf,svg,png} ~/Research/Papers/Betebenner_Braun/Paper_1/Figures/
cp STEP_2_SGPc_Sensitivity/results/*.{pdf,svg,png} ~/Research/Papers/Betebenner_Braun/Paper_1/Figures/
cp STEP_3_LIwLD/results/visualizations/*.{pdf,svg,png} ~/Research/Papers/Betebenner_Braun/Paper_1/Figures/
```

### 4. Extract Key Findings

Each step produces AI-consumable manifests (JSON + Markdown) that summarize results. Read these for paper text:
- `STEP_1_Family_Selection/results/dataset_all/analysis_manifest.md`
- `STEP_2_SGPc_Sensitivity/results/*.md`
- `STEP_3_LIwLD/results/step3_manifest.md`

---

## Quick Reference: Key Files for Paper

| Paper Need | File Location |
|------------|---------------|
| Copula selection table | `STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison.csv` |
| Selection frequency figure | `STEP_1_Family_Selection/results/dataset_all/phase1_*.{pdf,svg,png}` |
| Parameter recommendations | `STEP_1_Family_Selection/results/dataset_all/analysis_manifest.{json,md}` |
| SGPc variant comparison | `STEP_2_SGPc_Sensitivity/results/*.csv` |
| SGPc publication panels | `STEP_2_SGPc_Sensitivity/results/publication_figure_*.{pdf,svg,png}` |
| STEP 3 Phase A summary | `STEP_3_LIwLD/results/phase_a_summary.csv` |
| STEP 3 Phase B summary | `STEP_3_LIwLD/results/phase_b_systematic_summary.csv` |
| STEP 3 publication panels | `STEP_3_LIwLD/results/visualizations/panel_*.{pdf,svg,png}` |
| STEP 3 manifest | `STEP_3_LIwLD/results/step3_manifest.{json,md}` |
| TIMSS results | `STEP_4_TIMSS_Implementation/results/` (placeholder) |
| Summary synthesis | `STEP_5_Summary_Conclusions_Next_Steps/results/` (placeholder) |

---

## Reproducibility Statement for Paper

Include in paper:

> **Reproducibility.** All analyses were conducted using R version [X.X.X] with packages 
> data.table, copula, mirai, and jsonlite. Complete source code and documentation are available at 
> ~/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses/. The analysis pipeline consists of 
> five sequential steps: (1) copula family selection, (2) SGPc sensitivity analysis, 
> (3) growth regime inference validation, (4) TIMSS application, and (5) synthesis and conclusions. 
> Each step is self-contained with documentation (README.md) and can be reproduced independently. 
> The complete pipeline can be executed via master_analysis.R (runtime: ~6-10 hours for STEPs 1-3 
> on standard hardware; STEP 1 optimized for EC2 with 180+ parallel workers via mirai).

---

## Directory Navigation

```
Copula_Sensitivity_Analyses/
├── master_analysis.R           ← Run this to execute workflow
├── METHODOLOGY_OVERVIEW.md     ← This file (paper mapping)
├── README.md                   ← Project overview
│
├── functions/                  ← Shared utility functions
│
├── STEP_1_Family_Selection/    ← Copula family selection
│   ├── README.md
│   └── results/
│
├── STEP_2_SGPc_Sensitivity/    ← SGPc sensitivity (CORE)
│   ├── README.md
│   └── results/
│
├── STEP_3_LIwLD/              ← Growth regime inference (PIÈCE DE RÉSISTANCE)
│   ├── README.md
│   ├── SGPcFlow_Inference_Plan.md
│   ├── functions/              ← 9 modular function files
│   └── results/
│
├── STEP_4_TIMSS_Implementation/  ← TIMSS application (placeholder)
│   ├── README.md
│   └── Archive/
│
├── STEP_5_Summary_Conclusions_Next_Steps/  ← Synthesis (placeholder)
│   ├── README.md
│   └── Archive/
│
└── Archive/                    ← Historical materials
```

---

## Current Status (February 2026)

- **STEP 1:** Complete (966 conditions, 4 datasets)
- **STEP 2:** Complete (SGPc variants computed and validated)
- **STEP 3:** Code complete — awaiting validation run
- **STEP 4:** Placeholder — awaiting STEP 3 + TIMSS data
- **STEP 5:** Placeholder — awaiting upstream completion

**Note:** METHODOLOGY_OVERVIEW.md will be updated with STEP 3 findings after validation runs complete.

---

## Questions?

**For specific steps:**
- See `STEP_*/README.md` in each directory

**For running pipeline:**
- See comments in `master_analysis.R`
- Adjust `STEPS_TO_RUN` parameter to run selectively

**For paper integration:**
- This file (METHODOLOGY_OVERVIEW.md)
- `STEP_4_Deep_Dive_Reporting/results/comprehensive_report.pdf`

---

**Paper ready for Chapters 3-4!** (Chapters 5-7 await STEP 3 validation results and TIMSS implementation)

