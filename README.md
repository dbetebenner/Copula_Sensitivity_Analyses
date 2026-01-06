# Copula-Based Pseudo-Growth Simulation Framework

## Purpose

This repository contains a complete, reproducible analysis pipeline for the paper:

**"Longitudinal Inference Without Longitudinal Data: A Sklar-Theoretic Extension of TAMP"**  
by Damian W. Betebenner and Henry I. Braun

---

## Quick Start

### Run Complete Analysis
```r
# Navigate to directory
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")

# Run all 4 steps
source("master_analysis.R")
```

**Runtime:** 8-14 hours for complete pipeline

### Run Specific Steps
```r
# Run only Steps 1 and 2
STEPS_TO_RUN <- c(1, 2)
source("master_analysis.R")
```

---

## Framework Overview

This analysis proceeds in **4 sequential steps**:

### STEP 1: Copula Family Selection
- **Objective:** Identify best copula family for educational data
- **Method:** Test 6 families (5 parametric + comonotonic) across 129 conditions × 3 datasets
- **Metrics:** Relative fit (AIC/BIC) + absolute fit (GoF via Cramér-von Mises with parametric bootstrap)
- **Output:** t-copula selected (τ ≈ 0.71); all parametric copulas show statistically significant deviations with large n
- **Runtime:** 24 hours (EC2 c8g.12xlarge, N=1000 bootstrap) or 2 hours (local, N=50 bootstrap)
- **Directory:** `STEP_1_Family_Selection/`
- **Paper Section:** Chapter 3, Section 3.1

### STEP 2: Copula Sensitivity Analyses ⭐ **CORE CONTRIBUTION**
- **Objective:** Test copula robustness across conditions to validate Sklar-theoretic extension of TAMP
- **Method:** 4 experiments (grade span, sample size, content, cohort) using selected t-copula
- **Output:** Copula parameters stable; dependence structure generalizes across diverse conditions
- **Runtime:** 3-6 hours
- **Directory:** `STEP_2_Copula_Sensitivity_Analyses/`
- **Paper Section:** Chapter 3, Section 3.2

### STEP 3: Application Implementation
- **Objective:** Validate operational methods for copula-based SGPc implementation
- **Method:** Test 15+ marginal transformation methods for invertibility and uniformity
- **Output:** Kernel Gaussian selected (p = 0.23); validates two-stage transformation approach
- **Runtime:** 40-60 minutes
- **Directory:** `STEP_3_Application_Implementation/`
- **Paper Section:** Chapter 3, Section 3.3 (implementation details)

### STEP 4: Deep Dive & Reporting
- **Objective:** Detailed analysis + publication materials including SGP vs SGPc concordance
- **Method:** t-copula deep dive, SGPc percentiles, comprehensive report
- **Output:** LaTeX tables, figures, text snippets, SGP-SGPc comparison
- **Runtime:** 1-2 hours
- **Directory:** `STEP_4_Deep_Dive_Reporting/`
- **Paper Section:** Chapter 3, Section 3.4

---

## Directory Structure

```
Copula_Sensitivity_Analyses/
│
├── master_analysis.R              # Main execution script
├── METHODOLOGY_OVERVIEW.md        # Maps analyses to paper sections
├── README.md                      # This file
│
├── functions/                     # Shared utility functions
│   ├── longitudinal_pairs.R       # Extract paired longitudinal scores
│   ├── ispline_ecdf.R             # I-spline ECDF framework
│   ├── copula_bootstrap.R         # Copula fitting with bootstrap
│   ├── copula_contour_plots.R     # Visualization + manifest export
│   ├── copula_diagnostics.R       # Diagnostic utilities
│   ├── sgpc_engine.R              # SGPc (copula-based SGP) calculation
│   ├── export_plot_utils.R        # Multi-format plot export (PDF/SVG/PNG)
│   ├── gofCopula_parallel.R       # Parallel goodness-of-fit testing
│   └── transformation_diagnostics.R
│
├── STEP_1_Family_Selection/
│   ├── README.md                  # Step 1 documentation
│   ├── phase1_family_selection.R
│   ├── phase1_analysis.R
│   └── results/                   # Step 1 outputs
│
├── STEP_2_Copula_Sensitivity_Analyses/  # ⭐ CORE CONTRIBUTION
│   ├── README.md                  # Step 2 documentation
│   ├── exp_1_grade_span.R
│   ├── exp_2_sample_size.R
│   ├── exp_3_content_area.R
│   ├── exp_4_cohort.R
│   └── results/                   # Step 2 outputs
│
├── STEP_3_Application_Implementation/
│   ├── README.md                  # Step 3 documentation
│   ├── exp_5_transformation_validation.R
│   ├── exp_5_visualizations.R
│   └── results/                   # Step 3 outputs
│
├── STEP_4_Deep_Dive_Reporting/
│   ├── README.md                  # Step 4 documentation
│   ├── phase2_t_copula_deep_dive.R
│   ├── phase2_comprehensive_report.R
│   └── results/                   # Step 4 outputs
│       ├── tables/                # LaTeX tables for paper
│       └── figures/               # Publication figures
│
├── Archive/                       # Historical materials
├── Data/                          # Data directory
└── development/                   # Scratch/exploratory files
```

### Condition Output Structure (NEW)

Each analyzed condition (e.g., `2010_G5_G6_MATHEMATICS/`) now follows this structure:

```
{condition}/
├── PARAMETRIC/                    # Parametric copula outputs
│   ├── CLAYTON/
│   ├── COMONOTONIC/
│   ├── FRANK/
│   ├── GAUSSIAN/
│   ├── GUMBEL/
│   └── T/
│       ├── t_copula_CDF.pdf
│       ├── t_copula_PDF.pdf
│       ├── t_copula_with_uncertainty_CDF.pdf
│       ├── comparison_empirical_vs_t_CDF.pdf
│       ├── comparison_empirical_vs_t_full.pdf
│       └── comparison_empirical_vs_t_summary.{json,md}
│           # Includes tail_behaviour section with λ_L, λ_U
├── EMPIRICAL/                     # Empirical copula outputs
│   ├── RAW/                       # Deheuvels empirical copula
│   │   ├── raw_copula_CDF.pdf
│   │   └── raw_vs_SGP_ORDER_1_comparison.pdf
│   ├── BERNSTEIN/                 # Bernstein smoothed copula
│   │   ├── bernstein_copula_CDF.pdf
│   │   └── bernstein_vs_SGP_ORDER_1_comparison.pdf
│   └── comparison_raw_vs_bernstein_CDF.pdf
├── summary_grid.pdf               # 15x15 summary visualization
├── condition_summary.json
└── condition_summary.md
```

**Note:** KDE (kernel density) empirical copula is excluded from downstream analyses. Only **Raw (Deheuvels)** and **Bernstein** smoothed copulas are used for SGPc calculation and traditional SGP comparison. See the Step 1 README for details on this methodological decision.

---

## Key Features

### 1. **Configurable Execution**
Run all steps or select specific ones:
```r
STEPS_TO_RUN <- NULL        # Run all (default)
STEPS_TO_RUN <- c(1, 2)    # Run Steps 1-2 only
STEPS_TO_RUN <- 3          # Run Step 3 only
```

### 2. **Self-Contained Steps**
Each step has:
- Dedicated directory
- README.md with documentation
- Independent execution capability
- Results subdirectory

### 3. **Paper Integration**
See `METHODOLOGY_OVERVIEW.md` for:
- Mapping steps → paper sections
- Table/figure extraction
- Text snippet locations
- LaTeX integration

### 4. **Reproducibility**
- All paths relative to project root
- Shared utility functions in `functions/`
- Complete documentation per step
- Validated end-to-end workflow

### 5. **AI-Consumable Output (NEW)**
Analysis results are exported in AI-friendly formats for automated summarization and parameter recommendations:

**JSON Manifest** (`analysis_manifest.json`):
```json
{
  "metadata": { "generated_at": "...", "n_conditions": 129 },
  "parameter_recommendations": {
    "overall_best": { "family": "t", "rho": 0.85, "df": 8 },
    "by_year_span": { "1": {...}, "2": {...}, "4": {...} },
    "by_content_area": { "MATHEMATICS": {...}, "READING": {...} }
  },
  "family_selection_summary": [...]
}
```

**Markdown Summary** (`analysis_manifest.md`):
- Human-readable parameter recommendations
- Stratified by year span and content area
- Usage guide with R code examples for TIMSS-like applications

**Per-Family Summaries** (in each condition's output):
- `{family}_summary.json` - Structured fit metrics, tail dependence, SGPc comparison
- `{family}_summary.md` - Human-readable summary with parameter recommendations

### 6. **Tail Dependence Statistics (NEW - January 2026)**
Copula difference plots and exports now include tail behaviour metrics:

- **Lower Tail Dependence (λ_L)**: Measures joint extreme low outcomes
- **Upper Tail Dependence (λ_U)**: Measures joint extreme high outcomes
- **Tail Region RMSE**: Fit quality in corners (u,v ≤ 0.10 or ≥ 0.90)

These appear in:
- Copula difference plot annotation boxes
- `{family}_summary.json` under `copula_cdf_diff.tail_behaviour`
- `{family}_summary.md` under "Tail Behaviour" section
- Summary grid statistics box (λ_L, λ_U line)

---

## Current Status (December 2025)

**Implementation Phase:** Ready for EC2 production run

### Recent Updates
1. **Goodness-of-Fit Testing** (Nov 2025)
   - Parametric bootstrap (N=1000) using `copula::gofCopula()` with Cramér-von Mises statistic
   - Comonotonic copula: observed statistic only (no bootstrap)
   - All pseudo-observations via `pobs(..., ties.method="random")` for proper tie-breaking
   - Maximum pseudo-likelihood (`method="mpl"`) for consistency

2. **Multi-Dataset Analysis** (Nov 2025)
   - 4 datasets (varied content/grades/time periods): ~170 conditions total
   - Combined output: `STEP_1_Family_Selection/results/dataset_all/`
   - Individual datasets in `dataset_1/`, `dataset_2/`, `dataset_3/`, `dataset_4/`
   - Dataset 4 includes pandemic analysis: `dataset_4/pandemic_analysis/`

3. **EC2 Optimization** (Nov 2025, updated Jan 2026)
   - PSOCK cluster (socket-based) for cross-platform parallelization
   - Safe with macOS Accelerate BLAS (avoids fork-related segfaults)
   - Auto-detects EC2 environment, configures core allocation
   - Recommended: c8g.12xlarge (48 vCPUs, 96 GB RAM, Graviton3)
   - Expected runtime: 18-24 hours for N=1000 bootstrap

4. **Statistical Power Analysis** (Nov 2025)
   - Demonstrated that large n (28,567) → very high power → all copulas fail GoF
   - P-values interpretable as relative evidence against model fit
   - Practical significance vs. statistical significance distinction critical

5. **AI-Consumable Manifest Export** (Dec 2025)
   - `analysis_manifest.json` - Unified JSON manifest for AI summarization
   - `analysis_manifest.md` - Human-readable parameter recommendations
   - Per-family `{family}_summary.json` and `{family}_summary.md` files
   - Stratified recommendations by year span and content area
   - Usage guide for TIMSS-like sampled data applications

6. **Pandemic Impact Analysis** (Dec 2025)
   - Dataset 4: COVID-19 as natural experiment (2019-2021 vs pre-pandemic baselines)
   - 10 matched pandemic-baseline pairs across grade levels
   - Tests whether COVID disrupted copula dependency structure
   - Automated pandemic comparison script: `STEP_1_Family_Selection/pandemic_analysis_dataset4.R`
   - Convenience execution script: `run_dataset4_analysis.R`

### Next Steps
- Run Dataset 4 pandemic analysis: `source("run_dataset4_analysis.R")`
- Run `run_production_ec2.R` on EC2 for final results (all datasets)
- Generate GoF visualizations via `phase1_analysis.R`
- Review AI-generated parameter recommendations from manifest files
- Review pandemic analysis results: `STEP_1_Family_Selection/results/dataset_4/pandemic_analysis/`
- Document findings in paper (statistical vs. practical significance + pandemic effects)

---

## Requirements

### Data
Four anonymized state assessment datasets for copula sensitivity analysis:
```
Data/Copula_Sensitivity_Data_Set_1.Rdata  # Dataset 1 (Vertical Scale)
Data/Copula_Sensitivity_Data_Set_2.Rdata  # Dataset 2 (Non-Vertical Scale)
Data/Copula_Sensitivity_Data_Set_3.Rdata  # Dataset 3 (Assessment Transition)
Data/Copula_Sensitivity_Data_Set_4.Rdata  # Dataset 4 (Vertical Scale with COVID-19 gap)
```

Each dataset contains 9 variables (7 core variables for copula analysis + 2 secondary variables for sensitivity analyses). See `Data/README.md` for complete specifications.

**Dataset 4 Special Features:**
- Years: 2016-2019, 2021-2025 (2020 excluded due to COVID-19 testing interruption)
- Grades: 3-8, 11 (includes high school)
- Enables pandemic impact analysis: comparing 2019-2021 dependency structures to pre-pandemic baselines
- See `DATASET_4_CONDITIONS_LIST.md` for complete condition specifications

### R Packages
```r
install.packages(c("data.table", "copula", "splines2", "grid", "xtable"))
```

### Hardware
- **Local**: 8GB RAM minimum, 16GB recommended
- **EC2**: c6i.4xlarge (16 cores, 32 GB RAM)
  - Auto-detects EC2 environment
  - Uses parallel processing (15 cores)
  - STEP 1 speedup: 14-15x (60-90 min → 4-6 min)

---

## Execution Modes

### Interactive Mode (Default)
```r
BATCH_MODE <- FALSE  # Pauses for review between steps
source("master_analysis.R")
```

**Best for:** Initial runs, debugging, understanding results

### Batch Mode
```r
BATCH_MODE <- TRUE  # No pauses, continuous execution
source("master_analysis.R")
```

**Best for:** EC2, overnight runs, final production

### EC2 Mode
```r
EC2_MODE <- TRUE    # More bootstrap iterations, parallel processing
source("master_analysis.R")
```

**Best for:** Cloud execution, high-performance computing

---

## Output Locations

| Step | Results Directory | Key Files |
|------|-------------------|-----------|
| 1 | `STEP_1_Family_Selection/results/dataset_all/` | `phase1_*.csv`, `phase1_*.{pdf,svg,png}`, `analysis_manifest.{json,md}` |
| 1 | `STEP_1_Family_Selection/results/dataset_*/` | Per-dataset results + contour plots |
| 2 | `STEP_2_Copula_Sensitivity_Analyses/results/` | `exp_*/*.csv`, `exp_*/*.pdf` |
| 3 | `STEP_3_Application_Implementation/results/` | `exp5_*.csv`, `exp5_*.RData`, `figures/` |
| 4 | `STEP_4_Deep_Dive_Reporting/results/` | `*.RData`, `tables/*.tex`, `figures/*.pdf` |

**AI-Consumable Files (Step 1):**
- `analysis_manifest.json` - Unified manifest with parameter recommendations
- `analysis_manifest.md` - Human-readable summary for TIMSS-like applications
- `{family}_summary.json` - Per-family structured summaries (in contour_plots subdirs)

---

## Key Findings

### Copula Family Selection (STEP 1)
✓ **t-copula** wins across 95% of conditions (relative fit via AIC)  
✓ Symmetric tail dependence appropriate for educational data  
✓ Mean ΔAIC = 180 vs. Gaussian  
✓ **Absolute fit**: All parametric families fail GoF (p < 0.05) with large n (28,567), but t-copula closest (CvM ≈ 0.84)  
✓ **Comonotonic** (TAMP assumption) dramatically worse (CvM ≈ 50, 60× worse than t-copula)

### Copula Sensitivity Analyses (STEP 2) ⭐ **CORE CONTRIBUTION**
✓ Kendall's τ decreases with grade span (0.71 → 0.52 over 4 years)  
✓ Parameters stable across sample sizes (n ≥ 2000)  
✓ Content areas show similar dependence (±0.03)  
✓ Minimal cohort effects (<5% variation)  
✓ **Validates Sklar-theoretic extension:** t-copula generalizes across diverse conditions, demonstrating robustness beyond TAMP's comonotonic assumption

### Application Implementation (STEP 3)
✓ **Kernel Gaussian** balances uniformity with utility  
✓ K-S p = 0.23 (acceptable given discrete data)  
✓ Validates two-stage approach (empirical ranks for selection, smoothing for applications)  
✓ Transformation is implementation detail; copula dependence modeling invariant to marginal transforms

### t-Copula Properties & SGPc (STEP 4)
✓ Degrees of freedom: ν ≈ 7-12 (depending on grade span)  
✓ Tail dependence: λ ≈ 0.15-0.25 (symmetric)  
✓ Superior to Gaussian in tails (captures extreme joint outcomes)  
✓ **SGPc**: Copula-based Student Growth Percentiles track closely with traditional SGP

---

## Troubleshooting

### Issue: "Data file not found"
**Fix:** Ensure `Data/Copula_Sensitivity_Test_Data_CO.Rdata` exists. The file should be in the `Data/` subdirectory of the project root.

### Issue: "Functions not found"
**Fix:** Ensure you're running from project root, or paths use `../functions/`

### Issue: "Previous step results missing"
**Fix:** Run previous steps first, or set `SKIP_COMPLETED <- FALSE`

### Issue: Slow execution
**Solutions:**
- Use EC2 with more cores
- Reduce bootstrap iterations for testing
- Run steps individually (not all at once)

---

## Documentation

### Start Here
- **README.md** (this file) - Project overview
- **METHODOLOGY_OVERVIEW.md** - Maps to paper sections

### Step-Specific
- **STEP_1_Family_Selection/README.md** - Copula family selection
- **STEP_2_Copula_Sensitivity_Analyses/README.md** - Sensitivity analyses (CORE CONTRIBUTION)
- **STEP_3_Application_Implementation/README.md** - Implementation details
- **STEP_4_Deep_Dive_Reporting/README.md** - Deep dive, SGPc analysis & reporting

### Methodological
- **TWO_STAGE_TRANSFORMATION_METHODOLOGY.md** - Two-stage approach justification (implementation detail)
- **STEP_1_Family_Selection/BUG_FIX_SUMMARY.txt** - Critical bug documentation
- **STEP_3_Application_Implementation/SPLINE_CONVERSATION_ChatGPT.md** - Smoothing discussion

---

## Paper Integration

The paper draft is located at:
```
~/Research/Papers/Betebenner_Braun/Paper_1/A_Sklar_Theoretic_Extension_of_TAMP.tex
```

### To Generate Paper Materials:
1. Run complete pipeline: `source("master_analysis.R")`
2. Review comprehensive report: `STEP_4_Deep_Dive_Reporting/results/comprehensive_report.pdf`
3. Copy LaTeX tables: `STEP_4_Deep_Dive_Reporting/results/tables/*.tex`
4. Copy figures: `STEP_4_Deep_Dive_Reporting/results/figures/*.pdf`
5. Extract text snippets: See `METHODOLOGY_OVERVIEW.md` for locations

### Quick Table/Figure Reference:
See `METHODOLOGY_OVERVIEW.md` "Quick Reference: Key Files for Paper" section

---

## Citation

If using this code/framework, cite:

> Betebenner, D. W., & Braun, H. I. (2025). Longitudinal Inference Without Longitudinal Data: 
> A Sklar-Theoretic Extension of TAMP. *[Journal Name]*, *Volume*(Issue), pages.

---

## Contact

**Damian W. Betebenner**  
The National Center for the Improvement of Educational Assessment  
Dover, New Hampshire

**Henry I. Braun**  
Lynch School of Education, Boston College  
Chestnut Hill, Massachusetts

---

## License

[Specify license if applicable]

---

## Acknowledgments

- AI contribution: OpenAI GPT and Anthropic Claude models
- Data: Three anonymized state education agencies (identities withheld for research purposes)
- Funding: [If applicable]

---

**Version:** 4.1 (Added AI-consumable manifest export for parameter recommendations)  
**Last Updated:** December 2025  
**Status:** ✓ Production Ready
