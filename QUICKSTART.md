# Quick Start Guide: Copula-Based Pseudo-Growth Simulation

## 🚀 Fastest Path to Results

### Complete Analysis (All 4 Steps)
```r
# Navigate to project directory
setwd("~/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")

# Run complete pipeline
source("master_analysis.R")
```

**Runtime:** 8-14 hours (local) or 1-2 hours (EC2 with parallelization)

---

## ⚡ Run Specific Steps

### Step 1 Only (Copula Family Selection)
```r
STEPS_TO_RUN <- 1
source("master_analysis.R")
```
**Runtime:** 30-60 minutes (local) or 4-6 minutes (EC2)

### Steps 1-2 (Add Copula Sensitivity - CORE CONTRIBUTION)
```r
STEPS_TO_RUN <- c(1, 2)
source("master_analysis.R")
```
**Runtime:** 4-7 hours (includes core sensitivity analyses)

### Custom Selection
```r
STEPS_TO_RUN <- c(3, 4)  # Run only Steps 3 and 4
source("master_analysis.R")
```

---

## 📋 Prerequisites

### 1. Data File
Ensure the trimmed data file exists:
```bash
ls Data/Copula_Sensitivity_Test_Data_CO.Rdata
```

If missing, see `Data/README.md` for instructions.

### 2. R Packages
```r
install.packages(c("data.table", "copula", "splines2", "grid"))
```

### 3. System Requirements
- **Local:** 8GB RAM minimum (16GB recommended)
- **EC2:** c6i.4xlarge (16 cores, 32GB RAM)

---

## 🏃 Execution Modes

### Interactive Mode (Default)
```r
# Pauses between steps for review
source("master_analysis.R")
```

Press **Enter** at each checkpoint to continue.

### Batch Mode (No Pauses)
```r
# Continuous execution
BATCH_MODE <- TRUE
source("master_analysis.R")
```

### EC2 Mode (Automatic)
```r
# Auto-detects EC2, uses 15 cores for STEP 1
source("master_analysis.R")
```

---

## 📊 What Each Step Does

### STEP 1: Copula Family Selection (30-60 min)
- Tests 6 copula families (5 parametric + comonotonic) across 129 conditions
- **Output:** Best copula family identified (t-copula)
- **Location:** `STEP_1_Family_Selection/results/`
- **Paper:** Chapter 3, Section 3.1

### STEP 2: Copula Sensitivity Analyses ⭐ **CORE CONTRIBUTION** (3-6 hours)
- Tests t-copula robustness across 4 dimensions
- Experiments: grade span, sample size, content area, cohort
- **Output:** Validates Sklar-theoretic extension of TAMP
- **Location:** `STEP_2_Copula_Sensitivity_Analyses/results/`
- **Paper:** Chapter 3, Section 3.2 (Central empirical contribution)

### STEP 3: Application Implementation (40-60 min)
- Validates 15+ marginal transformation methods for invertibility
- **Output:** Method classification for score-scale reporting
- **Location:** `STEP_3_Application_Implementation/results/`
- **Paper:** Chapter 3, Section 3.3 (Implementation detail)

### STEP 4: Deep Dive & Reporting (1-2 hours)
- Detailed t-copula analysis + SGP vs SGPc concordance
- Generates publication materials
- **Output:** LaTeX tables, figures, comprehensive report
- **Location:** `STEP_4_Deep_Dive_Reporting/results/`
- **Paper:** Chapter 3, Section 3.4 + Chapter 4

---

## 🎯 Common Workflows

### Core Methodology (4-7 hours)
Run Steps 1-2 to complete the core contribution (family selection + sensitivity):
```r
STEPS_TO_RUN <- c(1, 2)
source("master_analysis.R")
```

### Full Analysis for Paper (8-14 hours)
```r
# Set to NULL to run all steps
STEPS_TO_RUN <- NULL
source("master_analysis.R")
```

### Application Implementation Only (40-60 min)
If you already have STEP 1-2 results:
```r
STEPS_TO_RUN <- 3
source("master_analysis.R")
```

---

## 📁 Where to Find Results

| Step | Results Directory | Key Files |
|------|-------------------|-----------|
| 1 | `STEP_1_Family_Selection/results/` | `phase1_decision.RData`, `phase1_*.pdf` |
| 2 | `STEP_2_Transformation_Validation/results/` | `exp5_transformation_validation_summary.csv` |
| 3 | `STEP_3_Sensitivity_Analyses/results/` | `exp_*/` subdirectories with CSV and PDFs |
| 4 | `STEP_4_Deep_Dive_Reporting/results/` | `tables/*.tex`, `figures/*.pdf` |

---

## 🔧 Troubleshooting

### "Data file not found"
```bash
# Check if file exists
ls Data/Copula_Sensitivity_Test_Data_CO.Rdata

# If missing, see Data/README.md
```

### "Functions not found"
```r
# Ensure you're in project root
getwd()  # Should end in "Copula_Sensitivity_Analyses"
```

### Slow execution on EC2
```r
# Check if parallel mode is active
# Should see "Using parallel implementation (15 cores)" in logs
```

### Out of memory
```r
# Reduce bootstrap iterations for testing
N_BOOTSTRAP_PHASE2 <- 50  # Instead of default 100/200
```

---

## 🚀 EC2 Quick Start

### 1. Setup EC2 Instance
```bash
# Run setup script (installs R and dependencies)
./setup_ec2.sh
```

### 2. Clone and Upload Data
```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/Copula_Sensitivity_Analyses.git
cd Copula_Sensitivity_Analyses

# Upload data from local machine
scp Data/Copula_Sensitivity_Test_Data_CO.Rdata ec2-user@<instance>:~/Copula_Sensitivity_Analyses/Data/
```

### 3. Run Analysis
```bash
# Start analysis in background
nohup Rscript -e "source('master_analysis.R')" > output.log 2>&1 &

# Monitor progress
tail -f output.log
```

### 4. Expected Runtime (EC2 c6i.4xlarge)
- STEP 1: ~5 minutes (parallel)
- STEP 2: ~2-3 hours (copula sensitivity - CORE)
- STEP 3: ~40 minutes (transformation implementation)
- STEP 4: ~1 hour
- **Total: ~4-5 hours**

---

## 📚 Next Steps

### Review Results
1. Check `STEP_*/results/` directories
2. Read `METHODOLOGY_OVERVIEW.md` for paper integration
3. View comprehensive report (if STEP 4 completed)

### Generate Paper Materials
```bash
# Sync results to paper directory
./sync_to_paper.sh
```

### Customize Analysis
- Edit `state_config.R` for different states
- Modify `STEPS_TO_RUN` for selective execution
- Adjust bootstrap iterations in `master_analysis.R`

---

## 📖 Documentation

- **README.md** - Complete project overview
- **METHODOLOGY_OVERVIEW.md** - Maps analyses to paper sections
- **GENERIC_DATA_SYSTEM.md** - Multi-state configuration guide
- **Data/README.md** - Data file documentation
- **STEP_*/README.md** - Step-specific documentation

---

## 🆘 Getting Help

### Check Logs
```r
# View most recent log file
log_files <- list.files(pattern = "master_analysis_log.*txt")
file.show(tail(log_files, 1))
```

### Validate Installation
```r
# Check packages
required_pkgs <- c("data.table", "copula", "splines2", "grid")
missing <- setdiff(required_pkgs, rownames(installed.packages()))
if (length(missing) > 0) {
  cat("Missing packages:", paste(missing, collapse = ", "), "\n")
}
```

### Test Parallel Setup (EC2)
```r
source("master_analysis.R")
source("STEP_1_Family_Selection/test_parallel_subset.R")
```

---

## ✅ Success Criteria

After running, you should see:

**STEP 1:**
- ✓ `phase1_decision.RData` exists
- ✓ Selected copula family printed in summary
- ✓ 5 PDF visualizations created

**STEP 2:** ⭐ **CORE CONTRIBUTION**
- ✓ 4 experiment subdirectories with results
- ✓ CSV files with copula parameter estimates
- ✓ PDF visualizations showing robustness

**STEP 3:**
- ✓ `exp5_transformation_validation_summary.csv` exists
- ✓ Method classifications available
- ✓ Figures directory created

**STEP 4:**
- ✓ LaTeX tables in `tables/` subdirectory
- ✓ Publication figures in `figures/` subdirectory
- ✓ Comprehensive report generated

---

**Version:** 4.0 (Reorganized to emphasize copula sensitivity as core contribution)  
**Last Updated:** November 2025  
**Status:** ✓ Current and Tested
