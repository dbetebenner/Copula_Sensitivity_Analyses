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
- **Method:** Test 5 families across 30+ conditions
- **Output:** t-copula selected (τ ≈ 0.71)
- **Runtime:** 30-60 minutes
- **Directory:** `STEP_1_Family_Selection/`

### STEP 2: Transformation Validation
- **Objective:** Validate marginal transformation methods
- **Method:** Test 15+ methods on uniformity & dependence
- **Output:** Kernel Gaussian selected (p = 0.23)
- **Runtime:** 40-60 minutes
- **Directory:** `STEP_2_Transformation_Validation/`

### STEP 3: Sensitivity Analyses
- **Objective:** Test copula robustness across conditions
- **Method:** 4 experiments (grade span, sample size, content, cohort)
- **Output:** Copula parameters stable
- **Runtime:** 3-6 hours
- **Directory:** `STEP_3_Sensitivity_Analyses/`

### STEP 4: Deep Dive & Reporting
- **Objective:** Detailed analysis + publication materials
- **Method:** t-copula analysis, comprehensive report
- **Output:** LaTeX tables, figures, text snippets
- **Runtime:** 1-2 hours
- **Directory:** `STEP_4_Deep_Dive_Reporting/`

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
│   ├── longitudinal_pairs.R
│   ├── ispline_ecdf.R
│   ├── copula_bootstrap.R
│   ├── copula_diagnostics.R
│   └── transformation_diagnostics.R
│
├── STEP_1_Family_Selection/
│   ├── README.md                  # Step 1 documentation
│   ├── phase1_family_selection.R
│   ├── phase1_analysis.R
│   └── results/                   # Step 1 outputs
│
├── STEP_2_Transformation_Validation/
│   ├── README.md                  # Step 2 documentation
│   ├── exp_5_transformation_validation.R
│   ├── exp_5_visualizations.R
│   └── results/                   # Step 2 outputs
│
├── STEP_3_Sensitivity_Analyses/
│   ├── README.md                  # Step 3 documentation
│   ├── exp_1_grade_span.R
│   ├── exp_2_sample_size.R
│   ├── exp_3_content_area.R
│   ├── exp_4_cohort.R
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

---

## Requirements

### Data
Colorado longitudinal assessment data (2003-2013):
```
/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_Data_LONG.RData
```

### R Packages
```r
install.packages(c("data.table", "copula", "splines2", "grid", "xtable"))
```

### Hardware
- Minimum: 8GB RAM, 4 cores
- Recommended: 16GB RAM, 8 cores (for faster execution)
- EC2: Set `EC2_MODE <- TRUE` for cloud execution

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
| 1 | `STEP_1_Family_Selection/results/` | `phase1_*.csv`, `phase1_*.pdf` |
| 2 | `STEP_2_Transformation_Validation/results/` | `exp5_*.csv`, `exp5_*.RData`, `figures/` |
| 3 | `STEP_3_Sensitivity_Analyses/results/` | `exp_*/*.csv`, `exp_*/*.pdf` |
| 4 | `STEP_4_Deep_Dive_Reporting/results/` | `*.RData`, `tables/*.tex`, `figures/*.pdf` |

---

## Key Findings

### Copula Family (STEP 1)
✓ **t-copula** wins across 95% of conditions  
✓ Symmetric tail dependence appropriate for educational data  
✓ Mean ΔAIC = 180 vs. Gaussian

### Transformation Method (STEP 2)
✓ **Kernel Gaussian** balances uniformity with utility  
✓ K-S p = 0.23 (acceptable given discrete data)  
✓ Validates two-stage approach (empirical ranks for selection, smoothing for applications)

### Sensitivity (STEP 3)
✓ Kendall's τ decreases with grade span (0.71 → 0.52 over 4 years)  
✓ Parameters stable across sample sizes (n ≥ 2000)  
✓ Content areas show similar dependence (±0.03)  
✓ Minimal cohort effects (<5% variation)

### t-Copula Properties (STEP 4)
✓ Degrees of freedom: ν ≈ 7-12 (depending on grade span)  
✓ Tail dependence: λ ≈ 0.15-0.25 (symmetric)  
✓ Superior to Gaussian in tails (captures extreme joint outcomes)

---

## Troubleshooting

### Issue: "Data file not found"
**Fix:** Update data path in each step's main script

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
- **STEP_1_Family_Selection/README.md** - Copula selection
- **STEP_2_Transformation_Validation/README.md** - Transformation validation
- **STEP_3_Sensitivity_Analyses/README.md** - Sensitivity analyses
- **STEP_4_Deep_Dive_Reporting/README.md** - Deep dive & reporting

### Methodological
- **STEP_1_Family_Selection/TWO_STAGE_TRANSFORMATION_METHODOLOGY.md** - Two-stage approach justification
- **STEP_1_Family_Selection/BUG_FIX_SUMMARY.txt** - Critical bug documentation
- **STEP_2_Transformation_Validation/SPLINE_CONVERSATION_ChatGPT.md** - Smoothing discussion

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
- Data: Colorado Department of Education
- Funding: [If applicable]

---

**Version:** 3.0 (Restructured for paper integration)  
**Last Updated:** October 2025  
**Status:** ✓ Production Ready
