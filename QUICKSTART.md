# Quick Start Guide: Copula-Based Growth Regime Inference

## 🚀 Fastest Path to Results

### Complete Analysis (All 5 Steps)
```r
# Navigate to project directory
setwd("~/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")

# Run complete pipeline (STEPs 1-3 complete; 4-5 are placeholders)
source("master_analysis.R")
```

**Runtime:** 43-47 hours for STEPs 1-3 on EC2 m8g-metal.48xl (192 cores, 752GB RAM)

---

## ⚡ Run Specific Steps

### Step 1 Only (Copula Family Selection)
```r
STEPS_TO_RUN <- 1
source("master_analysis.R")
```
**Runtime:** 38.7 hours on EC2 m8g-metal.48xl (192 cores, 752GB RAM) — 966 conditions, avg 2.4 min/condition

### Steps 1-2 (Add SGPc Sensitivity - CORE CONTRIBUTION)
```r
STEPS_TO_RUN <- c(1, 2)
source("master_analysis.R")
```
**Runtime:** 42-45 hours total (STEP 1: 38.7 hours, STEP 2: 3-6 hours)

### Steps 1-3 (Add Growth Regime Inference - PIÈCE DE RÉSISTANCE)
```r
STEPS_TO_RUN <- c(1, 2, 3)
source("master_analysis.R")
```
**Runtime:** 43-47 hours total (STEP 1: 38.7 hours, STEP 2: 3-6 hours, STEP 3: 30-90 min)

### Custom Selection
```r
STEPS_TO_RUN <- c(3)  # Run only STEP 3 (growth regime inference)
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
install.packages(c("data.table", "copula", "mirai", "jsonlite", "grid"))
```

### 2. System Requirements
- **Local:** 8GB RAM minimum (16GB recommended)
- **EC2 Production:** m8g-metal.48xl (192 vCPUs, 752 GB RAM) for full parallelization
  - Mirai scales across all available cores
  - Per-task data loading minimizes memory overhead
  - Latest run: Feb 6, 2026 — 38.7 hours, 966 conditions, 100% success

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
# Continuous execution (recommended for EC2)
BATCH_MODE <- TRUE
source("master_analysis.R")
```

### EC2 Mode (Automatic)
```r
# Auto-detects EC2 environment
# - Enables batch mode (no pauses)
# - Uses mirai with all available cores (192 on m8g-metal.48xl)
# - Per-task data loading (minimizes memory overhead)
# - Thread management prevents CPU oversubscription
# - Latest production run: Feb 6, 2026 (38.7 hours, 966 conditions, 100% success)
source("master_analysis.R")
```

### Local Testing Mode
```r
# Test with 1 condition per dataset (fast validation)
TEST_MODE <- TRUE
source("master_analysis.R")
```

**Runtime:** ~10-15 minutes for 4 conditions total

---

## 📊 What Each Step Does

### STEP 1: Copula Family Selection (38.7 hours EC2, avg 2.4 min/condition)
- Tests 6 copula families (5 parametric + comonotonic) across 966 conditions (4 datasets)
- Uses mirai parallelization for scalability on EC2 m8g-metal.48xl (192 cores)
- **Output:** Family distribution: t-copula 63.6%, Frank 30.7%, Gumbel 3.6%, Gaussian 2.1%
- **Output:** Parameter recommendations, contour plots, AI-consumable manifests
- **Location:** `STEP_1_Family_Selection/results/`
- **Paper:** Chapter 3, Section 3.1

### STEP 2: SGPc Sensitivity ⭐ **CORE CONTRIBUTION** (3-6 hours)
- Computes multiple SGPc variants (empirical, best-fit, canonical, mis-specified, comonotonic)
- Demonstrates practical consequences of copula choice
- **Output:** Correlation matrices, classification agreement, publication panels
- **Location:** `STEP_2_SGPc_Sensitivity/results/`
- **Paper:** Chapter 3, Section 3.2 (Central empirical contribution)
- **Note:** Comonotonic uses step function (bimodal 1s/99s); alternative constant-50 interpretation may be explored for STEP 3

### STEP 3: Growth Regime Inference (LIw_LD) ⭐ **PIÈCE DE RÉSISTANCE** (30-90 min)
- Validates copula-kernel growth regime inference from cross-sectional data
- Compares inferred growth regimes to longitudinal ground truth
- **Output:** Recovery accuracy tables, publication panels (6 panels A-F), manifests
- **Location:** `STEP_3_LIw_LD/results/`
- **Paper:** Chapter 4 (Growth Regime Inference)

### STEP 4: TIMSS Implementation (Placeholder)
- Applies STEP 3 machinery to actual TIMSS cross-sectional data
- **Status:** Awaiting STEP 3 validation and TIMSS data acquisition
- **Location:** `STEP_4_TIMSS_Implementation/`
- **Paper:** Chapter 5 (International Application)

### STEP 5: Summary and Conclusions (Placeholder)
- Synthesises findings, generates publication materials
- **Status:** Awaiting upstream completion
- **Location:** `STEP_5_Summary_Conclusions_Next_Steps/`
- **Paper:** Chapters 6-7 (Discussion, Conclusions)

---

## 🎯 Common Workflows

### Core Methodology (42-45 hours)
Run Steps 1-2 to complete the core contribution (family selection + SGPc sensitivity):
```r
STEPS_TO_RUN <- c(1, 2)
source("master_analysis.R")
```

### Full Implemented Analysis (43-47 hours)
Run Steps 1-3 (includes growth regime inference validation):
```r
STEPS_TO_RUN <- c(1, 2, 3)
source("master_analysis.R")
```

### Growth Regime Inference Only (30-90 min)
If you already have STEP 1-2 results:
```r
STEPS_TO_RUN <- 3
source("master_analysis.R")
```

---

## 📁 Where to Find Results

| Step | Results Directory | Key Files |
|------|-------------------|-----------|
| 1 | `STEP_1_Family_Selection/results/dataset_all/` | `analysis_manifest.{json,md}`, `phase1_*.{pdf,svg,png}` |
| 2 | `STEP_2_SGPc_Sensitivity/results/` | SGPc comparison CSVs, publication panels |
| 3 | `STEP_3_LIw_LD/results/` | `phase_a_summary.csv`, `phase_b_systematic_summary.csv`, `step3_manifest.{json,md}` |
| 4 | `STEP_4_TIMSS_Implementation/results/` | (Placeholder — awaiting implementation) |
| 5 | `STEP_5_Summary_Conclusions_Next_Steps/results/` | (Placeholder — awaiting implementation) |

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
# Check if mirai parallelization is active
# Should see "Initializing mirai daemons..." and worker count in logs
# Expected: 180+ daemons on r8g.24xlarge or c8g.24xlarge
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

### 4. Expected Runtime (EC2 m8g-metal.48xl with mirai, 192 cores)
- STEP 1: 38.7 hours (966 conditions, mirai parallelized, completed Feb 6, 2026)
- STEP 2: 3-6 hours (SGPc sensitivity - CORE)
- STEP 3: 30-90 minutes (growth regime inference - LIw_LD)
- STEP 4: Placeholder (TIMSS implementation)
- STEP 5: Placeholder (summary/conclusions)
- **Total (Steps 1-3): 43-47 hours**

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

### Test Mirai Setup (Local)
```r
# Test with reduced conditions locally
TEST_MODE <- TRUE
source("master_analysis.R")
# Should see mirai daemon initialization and per-task data loading
```

---

## ✅ Success Criteria

After running, you should see:

**STEP 1:**
- ✓ `analysis_manifest.{json,md}` exists in `results/dataset_all/`
- ✓ Family distribution: t-copula 63.6%, Frank 30.7%, Gumbel 3.6%, Gaussian 2.1%
- ✓ Contour plots for each condition with bootstrap uncertainty
- ✓ 100% success rate (966/966 conditions)

**STEP 2:** ⭐ **CORE CONTRIBUTION**
- ✓ SGPc variant comparison CSV files
- ✓ Publication panel figures (PDF/SVG/PNG)
- ✓ High correlation across variants (r > 0.95)

**STEP 3:** ⭐ **PIÈCE DE RÉSISTANCE**
- ✓ `phase_a_summary.csv` with single-condition validation
- ✓ `phase_b_systematic_summary.csv` with multi-subgroup validation
- ✓ Publication panels A-F in `results/visualizations/`
- ✓ `step3_manifest.{json,md}` with AI-consumable results

**STEP 4:** (Placeholder)
- Awaiting STEP 3 validation and TIMSS data

**STEP 5:** (Placeholder)
- Awaiting upstream completion

---

**Version:** 5.0 (5-step structure with growth regime inference)  
**Last Updated:** February 2026  
**Status:** ✓ Steps 1-3 Implemented; Steps 4-5 Placeholders
