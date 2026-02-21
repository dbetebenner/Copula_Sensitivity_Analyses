############################################################################
### MASTER ANALYSIS SCRIPT
### Copula-Based Pseudo-Growth Simulation Framework
###
### Purpose: Orchestrate complete 4-step analysis workflow from copula
###          family selection through transformation validation to sensitivity
###          analyses and final reporting
###
### Usage: 
###   - Interactive: Run step-by-step with review pauses
###   - Batch: Set BATCH_MODE <- TRUE for unattended execution
###   - EC2: Set EC2_MODE <- TRUE for parallel execution
###   - Selective: Set STEPS_TO_RUN to run specific steps only
###
### Estimated Total Runtime: 8-14 hours for all steps
############################################################################

############################################################################
### CONFIGURATION: Multi-Dataset System
############################################################################

############################################################################
### PACKAGE DEPENDENCY CHECK
############################################################################
# Front-load all package checks to fail early rather than mid-analysis

cat("====================================================================\n")
cat("CHECKING PACKAGE DEPENDENCIES\n")
cat("====================================================================\n\n")

# Required packages (analysis will fail without these)
REQUIRED_PACKAGES <- c(
  # Core analysis
  "data.table",     # Data manipulation
  "copula",         # Copula modeling
  "splines2",       # I-spline transformations
  "parallel",       # Parallel processing
  
  # Visualization
  "ggplot2",        # Plotting
  "grid",           # Grid graphics
  "gridExtra",      # Grid arrangement
  "scales",         # Axis scaling
  
  # Analysis reporting (Step 1.2)
  "wesanderson",    # Color palettes
  "vioplot",        # Violin plots
  "ggbeeswarm"      # Beeswarm plots
)

# Optional packages (enhanced features, graceful degradation)
OPTIONAL_PACKAGES <- c(
  "ggdensity",      # Enhanced contour visualizations
  "ks"              # Kernel density estimation
)

# Check required packages
missing_required <- character(0)
for (pkg in REQUIRED_PACKAGES) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    missing_required <- c(missing_required, pkg)
  }
}

if (length(missing_required) > 0) {
  cat("❌ MISSING REQUIRED PACKAGES:\n")
  cat("   ", paste(missing_required, collapse = ", "), "\n\n")
  cat("   Install with:\n")
  cat("   install.packages(c(", paste0('"', missing_required, '"', collapse = ", "), "))\n\n")
  stop("Cannot proceed without required packages. Please install them first.")
} else {
  cat("✓ All required packages available:\n")
  cat("  ", paste(REQUIRED_PACKAGES, collapse = ", "), "\n\n")
}

# Check optional packages (warnings only, don't stop)
missing_optional <- character(0)
for (pkg in OPTIONAL_PACKAGES) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    missing_optional <- c(missing_optional, pkg)
  }
}

if (length(missing_optional) > 0) {
  cat("⚠ Optional packages not installed (will use fallback methods):\n")
  cat("  ", paste(missing_optional, collapse = ", "), "\n")
  cat("  Install with: install.packages(c(", paste0('"', missing_optional, '"', collapse = ", "), "))\n\n")
} else {
  cat("✓ All optional packages available\n\n")
}

cat("====================================================================\n\n")

# Load dataset configurations
cat("Loading dataset configurations from dataset_configs.R\n")
source("dataset_configs.R")

# Load confidential state mappings if available (git-ignored)
if (file.exists("dataset_configs_local.R")) {
  source("dataset_configs_local.R")
} else {
  cat("Note: dataset_configs_local.R not found. Using placeholder state identifiers.\n")
  cat("      Create this file locally with actual state mappings if needed.\n")
}
  
# Select which datasets to analyze
# Set to NULL to run all datasets, or specify vector of dataset IDs
# Examples:
#   DATASETS_TO_RUN <- NULL                              # Run all 4 datasets (default)
#   DATASETS_TO_RUN <- c("dataset_1", "dataset_2")       # Run only datasets 1 and 2
#   DATASETS_TO_RUN <- "dataset_4"                       # Run only dataset 4 (pandemic analysis)
# ============================================================================
# >>> CURRENT DATASET SELECTION <<<
# Targeted re-run: dataset_2 only, to pick up the 2 newly added READING G10
# grade sequences (READING span=3 G7->G10 and span=4 G6->G10).
# All other datasets (1, 3, 4) are fully covered; no changes needed there.
# ============================================================================
if (!exists("DATASETS_TO_RUN")) DATASETS_TO_RUN <- "dataset_2"
  
if (is.null(DATASETS_TO_RUN)) {
  DATASETS_TO_RUN <- names(DATASETS)
}

cat("Multi-dataset copula sensitivity analysis\n")
cat("Datasets to analyze:", paste(DATASETS_TO_RUN, collapse = ", "), "\n")
cat("Total datasets:", length(DATASETS_TO_RUN), "\n\n")

############################################################################
### CONFIGURATION: Select which steps to run
############################################################################

# STEPS TO RUN: Set to vector of step numbers, or NULL to run all
# Examples:
#   STEPS_TO_RUN <- NULL              # Run all steps (default)
#   STEPS_TO_RUN <- c(1, 2)          # Run only STEP_1 and STEP_2 (copula sensitivity)
#   STEPS_TO_RUN <- c(3)             # Run only STEP_3 (growth regime inference — LIw_LD)
#   STEPS_TO_RUN <- c(2, 3, 4)       # Run STEP_2 through STEP_4
#   STEPS_TO_RUN <- 1:5              # Run all steps (same as NULL)
#
# Step mapping:
#   STEP 1 — STEP_1_Family_Selection     (copula family selection)
#   STEP 2 — STEP_2_SGPc_Sensitivity     (SGPc sensitivity analysis)
#   STEP 3 — STEP_3_LIw_LD              (growth regime inference — Longitudinal Inference w/o LD)
#   STEP 4 — STEP_4_TIMSS_Implementation (TIMSS application — placeholder)
#   STEP 5 — STEP_5_Summary_Conclusions_Next_Steps (synthesis — placeholder)

if (!exists("STEPS_TO_RUN")) STEPS_TO_RUN <- c(1)  # Targeted re-run: STEP_1 only for new dataset_2 READING G10 conditions

# Helper function to check if step should run
should_run_step <- function(step_num) {
  if (is.null(STEPS_TO_RUN)) return(TRUE)
  return(step_num %in% STEPS_TO_RUN)
}

############################################################################
### CONFIGURATION: Performance Mode
############################################################################

# PERFORMANCE_MODE controls the trade-off between speed and output quality
# Based on diagnostic testing (test_contour_plots_sequential.R):
#   - Plot generation is the main bottleneck (56% of time)
#   - Bootstrap uncertainty overlays are particularly expensive
#   - Multi-format export adds significant I/O overhead
#
# Options:
#   "fast"   - Quick exploration (~15-20 min/condition)
#              Lower resolution, PDF only, uncertainty for best family only
#   "full"   - Publication quality (~60-70 min/condition)
#              High resolution, all formats, full uncertainty analysis
#   "custom" - Use individual settings below (no auto-configuration)
#
# ============================================================================
# >>> CURRENT SETTING <<<
# ============================================================================
PERFORMANCE_MODE <- "full"               # "fast", "full", or "custom"
# ============================================================================
#
if (!exists("PERFORMANCE_MODE")) PERFORMANCE_MODE <- "fast"

# Apply performance mode presets
if (PERFORMANCE_MODE == "fast") {
  # === FAST MODE: Optimized for bulk processing ===
  GRID_SIZE <- 150                         # vs 200 (2.25x fewer grid points)
  UNCERTAINTY_GRID_SIZE <- 100             # vs 100 (same - already optimal)
  EXPORT_FORMATS <- c("pdf")               # vs pdf,svg,png (3x less I/O)
  SKIP_COMONOTONIC <- TRUE                 # Skip comonotonic (never selected)
  N_BOOTSTRAP_UNCERTAINTY <- 50            # vs 50 (2x faster than original 100)
  BOOTSTRAP_ALL_FAMILIES <- FALSE          # Best family only (5x faster uncertainty)
  GENERATE_UNCERTAINTY_PLOTS <- TRUE       # Keep uncertainty for best family
  COMPARISON_FAMILIES <- "top3"            # Only generate full comparisons for top 3 by AIC
  
} else if (PERFORMANCE_MODE == "full") {
  # === FULL MODE: EC2-Optimized for 180+ parallel workers ===
  # Balanced configuration: maintains quality while achieving ~3-4x speedup
  # per condition, enabling ~3-hour runtime for 966 conditions on EC2
  GRID_SIZE <- 200                         # High quality (vs 300: 2.25x fewer points)
  UNCERTAINTY_GRID_SIZE <- 100             # Smooth uncertainty bands (vs 300: 9x fewer points)
  EXPORT_FORMATS <- c("pdf", "svg", "png") # All formats for publication
  SKIP_COMONOTONIC <- FALSE                # Include comonotonic for completeness
  N_BOOTSTRAP_UNCERTAINTY <- 50            # Good uncertainty estimates (vs 100: 2x faster)
  BOOTSTRAP_ALL_FAMILIES <- TRUE           # All 5 parametric families (comprehensive analysis)
  GENERATE_UNCERTAINTY_PLOTS <- TRUE       # Full uncertainty visualization
  COMPARISON_FAMILIES <- "all"             # All families for comparative analysis
  
} else {
  # === CUSTOM MODE: Use individual settings ===
  # Set these manually when PERFORMANCE_MODE <- "custom"
  if (!exists("GRID_SIZE")) GRID_SIZE <- 200
  if (!exists("UNCERTAINTY_GRID_SIZE")) UNCERTAINTY_GRID_SIZE <- 100
  if (!exists("SKIP_COMONOTONIC")) SKIP_COMONOTONIC <- TRUE
  if (!exists("COMPARISON_FAMILIES")) COMPARISON_FAMILIES <- "top3"
}

cat("Performance Mode:", PERFORMANCE_MODE, "\n")
cat("  Grid size:", GRID_SIZE, "×", GRID_SIZE, "\n")
cat("  Uncertainty grid:", UNCERTAINTY_GRID_SIZE, "×", UNCERTAINTY_GRID_SIZE, "\n")
cat("  Export formats:", paste(EXPORT_FORMATS, collapse = ", "), "\n")
cat("  Skip comonotonic:", SKIP_COMONOTONIC, "\n")
cat("  Comparison families:", COMPARISON_FAMILIES, "\n")
cat("\n")

############################################################################
### CONFIGURATION: Multi-Format Plot Export
############################################################################

# Multi-format export configuration (may be overridden by PERFORMANCE_MODE above)
if (!exists("EXPORT_FORMATS")) EXPORT_FORMATS <- c("pdf", "svg", "png")
EXPORT_DPI <- 300                          # Publication quality
EXPORT_VERBOSE <- FALSE                    # Reduce log noise in batch mode

############################################################################
### CONFIGURATION: Goodness-of-Fit Testing
############################################################################

# Number of bootstrap samples for GoF testing
# Options:
#   N_BOOTSTRAP_GOF <- NULL  # Skip GoF testing (faster)
#   N_BOOTSTRAP_GOF <- 0     # Use asymptotic approximation (very fast, adequate for large n)
#   N_BOOTSTRAP_GOF <- 100   # Parametric bootstrap with 100 samples (moderate speed, good for testing)
#   N_BOOTSTRAP_GOF <- 1000  # Parametric bootstrap with 1000 samples (slow, high precision)

if (!exists("N_BOOTSTRAP_GOF")) N_BOOTSTRAP_GOF <- 100  # Default: 100 bootstraps for testing

if (!is.null(N_BOOTSTRAP_GOF)) {
  cat("Goodness-of-Fit Testing: ENABLED\n")
  if (N_BOOTSTRAP_GOF == 0) {
    cat("  Method: Asymptotic approximation (fast)\n")
  } else {
    cat("  Method: Parametric bootstrap\n")
    cat("  Bootstrap samples:", N_BOOTSTRAP_GOF, "\n")
  }
  cat("\n")
}

############################################################################
### CONFIGURATION: Contour Plot Generation
############################################################################

# Generate contour plots during Step 1 (comprehensive approach)
GENERATE_CONTOUR_PLOTS <- TRUE

############################################################################
### CONFIGURATION: Bootstrap Uncertainty Plots
############################################################################

# Generate bootstrap uncertainty bands on parametric copula plots
# This adds significant time per condition depending on settings:
#   - Fast mode (50 samples, best only): ~5-10 min additional per condition
#   - Full mode EC2-optimized (50 samples, all families): ~10-15 min additional per condition
#   - Original full mode (100 samples, all families): ~20-30 min additional per condition
if (!exists("GENERATE_UNCERTAINTY_PLOTS")) GENERATE_UNCERTAINTY_PLOTS <- TRUE

# Number of bootstrap samples for uncertainty quantification (visualization only, not statistical tests)
# 25 = very fast, slightly grainy bands
# 50 = fast, smooth bands (EC2-optimized: 2x speedup vs 100, imperceptible quality loss)
# 100 = original default, very smooth bands
# 200 = high precision (overkill for visualization)
if (!exists("N_BOOTSTRAP_UNCERTAINTY")) N_BOOTSTRAP_UNCERTAINTY <- 50

# Bootstrap all families or just the best?
# TRUE = all 5 parametric families (gaussian, t, clayton, gumbel, frank) - comprehensive comparison
# FALSE = best family only (5x faster uncertainty plots) - use for quick exploratory runs
if (!exists("BOOTSTRAP_ALL_FAMILIES")) BOOTSTRAP_ALL_FAMILIES <- TRUE

# Grid size for uncertainty overlay plots (can be lower than main grid)
# Lower values significantly speed up uncertainty calculation
if (!exists("UNCERTAINTY_GRID_SIZE")) UNCERTAINTY_GRID_SIZE <- GRID_SIZE

if (GENERATE_UNCERTAINTY_PLOTS && GENERATE_CONTOUR_PLOTS) {
  cat("Uncertainty Plots: ENABLED\n")
  cat("  Bootstrap samples:", N_BOOTSTRAP_UNCERTAINTY, "\n")
  cat("  Uncertainty grid:", UNCERTAINTY_GRID_SIZE, "×", UNCERTAINTY_GRID_SIZE, "\n")
  cat("  Families:", ifelse(BOOTSTRAP_ALL_FAMILIES, "ALL (5 parametric)", "BEST ONLY"), "\n")
  cat("  Note: Bootstrap runs sequentially within each parallel worker\n")
  n_families <- ifelse(BOOTSTRAP_ALL_FAMILIES, 5, 1)
  est_time_min <- (N_BOOTSTRAP_UNCERTAINTY * n_families * (UNCERTAINTY_GRID_SIZE/300)^2 * 0.5) / 60
  est_time_max <- (N_BOOTSTRAP_UNCERTAINTY * n_families * (UNCERTAINTY_GRID_SIZE/300)^2 * 0.8) / 60
  cat("  Est. additional time: ~", round(est_time_min, 1), "-", 
      round(est_time_max, 1), " min per condition\n\n")
}

############################################################################
### CONFIGURATION: SGPc (Copula-based SGP) Calculation
############################################################################

# Use SGP data files (contains traditional SGP column for comparison)
# Set to TRUE to load *_SGP.Rdata files, FALSE for base data files
if (!exists("USE_SGP_DATA")) USE_SGP_DATA <- TRUE

# Calculate SGPc (copula-based SGP) during Step 1
# Requires USE_SGP_DATA = TRUE for meaningful comparison
if (!exists("CALCULATE_SGPC")) CALCULATE_SGPC <- TRUE

if (USE_SGP_DATA) {
  cat("SGP Data: ENABLED (loading files with traditional SGP column)\n")
  if (CALCULATE_SGPC) {
    cat("SGPc Calculation: ENABLED (will compute copula-based SGPs)\n")
  }
  cat("\n")
}

############################################################################
### CONFIGURATION: Exhaustive Same-Cohort Analysis
############################################################################

# Use exhaustive conditions (all valid year/grade/content combinations) for ALL datasets
# This generates same-cohort trajectories (e.g., 2005 G3→G4, 2005 G3→G5, 2005 G3→G6, 2005 G3→G7)
# to study copula stability across time spans
#
# Options:
#   USE_EXHAUSTIVE_ALL_DATASETS <- FALSE  # Strategic subset only (default, ~16 conditions/dataset)
#   USE_EXHAUSTIVE_ALL_DATASETS <- TRUE   # Exhaustive analysis (966 total: ds1=510, ds2=194, ds3=80, ds4=182)
if (!exists("USE_EXHAUSTIVE_ALL_DATASETS")) USE_EXHAUSTIVE_ALL_DATASETS <- TRUE

# Test mode: Limit to small subset of conditions for validation
# This is useful for testing the pipeline before full EC2 run
#
# EC2 WORKFLOW:
#   1. Run with TEST_MODE=TRUE, TEST_N_CONDITIONS_PER_DATASET=2 to validate pipeline
#   2. Review results to ensure everything is working
#   3. Set TEST_MODE=FALSE for full production run on larger instance
#
# ============================================================================
# >>> CURRENT SETTINGS (EDIT THESE FOR YOUR RUN) <<<
# ============================================================================
TEST_MODE <- FALSE                     # PRODUCTION MODE: Full analysis (966 conditions)
TEST_N_CONDITIONS_PER_DATASET <- 1       # Only used if TEST_MODE=TRUE

# --- QUICK TEST MODE (for fast local validation) ---
# When enabled, overrides TEST_MODE and runs a minimal number of conditions
# from the smallest dataset for rapid pipeline validation
QUICK_TEST_MODE <- FALSE                   # DISABLED for EC2 production run
QUICK_TEST_N_CONDITIONS <- 1               # Total conditions to run (not per-dataset)
QUICK_TEST_PREFER_SMALLEST <- TRUE         # Prefer dataset_4 (smallest, ~1.6M rows)
# ============================================================================
#
if (!exists("TEST_MODE")) TEST_MODE <- FALSE
if (!exists("TEST_N_CONDITIONS_PER_DATASET")) TEST_N_CONDITIONS_PER_DATASET <- 2
if (!exists("QUICK_TEST_MODE")) QUICK_TEST_MODE <- FALSE
if (!exists("QUICK_TEST_N_CONDITIONS")) QUICK_TEST_N_CONDITIONS <- 1
if (!exists("QUICK_TEST_PREFER_SMALLEST")) QUICK_TEST_PREFER_SMALLEST <- TRUE

# Display mode information
if (QUICK_TEST_MODE) {
  cat("====================================================================\n")
  cat("QUICK TEST MODE: ENABLED (Fast Local Validation)\n")
  cat("====================================================================\n")
  cat("  Total conditions:", QUICK_TEST_N_CONDITIONS, "\n")
  cat("  Prefer smallest dataset:", QUICK_TEST_PREFER_SMALLEST, "\n")
  if (QUICK_TEST_PREFER_SMALLEST) {
    cat("  Target dataset: dataset_4 (~1.6M rows, fastest)\n")
  }
  cat("  This mode overrides TEST_MODE for rapid pipeline validation\n")
  cat("====================================================================\n\n")
} else if (USE_EXHAUSTIVE_ALL_DATASETS) {
  cat("====================================================================\n")
  cat("EXHAUSTIVE SAME-COHORT ANALYSIS: ENABLED\n")
  cat("====================================================================\n")
  cat("  This will analyze ALL valid year/grade/content combinations\n")
  cat("  to establish copula stability across time spans (1-4 years)\n")
  cat("  Expected conditions: 966 total (dataset_1=510, dataset_2=194, dataset_3=80, dataset_4=182)\n")
  cat("  Estimated runtime on EC2 (parallel): ~3-4 hours total with 180+ workers\n")
  if (TEST_MODE) {
    cat("\n")
    cat("  TEST MODE: ACTIVE\n")
    cat("  Will analyze only", TEST_N_CONDITIONS_PER_DATASET, "condition(s) per dataset\n")
    cat("  for validation before full run\n")
  }
  cat("====================================================================\n\n")
} else {
  cat("Strategic Subset Mode: Using representative sampling (~16 conditions/dataset)\n")
  if (TEST_MODE) {
    cat("  TEST MODE: Will analyze only", TEST_N_CONDITIONS_PER_DATASET, "condition(s) per dataset\n")
  }
  cat("\n")
}

############################################################################
### EC2/LOCAL AUTO-DETECTION
############################################################################

# Default settings (only set if not already defined by calling script)
if (!exists("BATCH_MODE")) BATCH_MODE <- FALSE
if (!exists("EC2_MODE")) EC2_MODE <- FALSE
if (!exists("SKIP_COMPLETED")) SKIP_COMPLETED <- TRUE
if (!exists("USE_PARALLEL")) USE_PARALLEL <- FALSE

# Checkpoint/Resume: Skip already-completed conditions
# Critical for spot instance resilience - allows resuming after interruption
if (!exists("SKIP_COMPLETED_CONDITIONS")) SKIP_COMPLETED_CONDITIONS <- TRUE

# Enhanced EC2 detection
IS_EC2 <- grepl("ec2", Sys.info()["nodename"], ignore.case = TRUE) ||
          file.exists("/home/ec2-user") ||
          file.exists("/sys/hypervisor/uuid")  # AWS hypervisor detection

if (IS_EC2) {
  cat("====================================================================\n")
  cat("DETECTED EC2 ENVIRONMENT\n")
  cat("====================================================================\n")
  
  # Detect instance type
  instance_type <- tryCatch({
    system("ec2-metadata --instance-type 2>/dev/null | cut -d ' ' -f 2", intern = TRUE)
  }, error = function(e) "unknown")
  
  if (length(instance_type) > 0 && instance_type != "unknown") {
    cat("Instance type:", instance_type, "\n")
  }
  
  cat("Using EC2-optimized settings\n")
  cat("====================================================================\n")
  BATCH_MODE <- TRUE
  EC2_MODE <- TRUE
  SKIP_COMPLETED <- FALSE
  USE_PARALLEL <- TRUE
  SKIP_COMPLETED_CONDITIONS <- TRUE  # Critical for spot instance resilience
  cat("  Batch mode: TRUE (no pauses)\n")
  cat("  Cores:", parallel::detectCores(), "\n")
  cat("  Parallelization: mirai (scalable, cross-platform)\n")
  cat("  Skip completed conditions: TRUE (resume capability)\n")
  cat("====================================================================\n\n")
} else {
  # Local machine - check if sufficient resources for parallel processing
  n_cores_available <- parallel::detectCores()
  if (is.na(n_cores_available)) n_cores_available <- 1  # Fallback for systems where detectCores fails
  
  if (n_cores_available >= 8) {
    cat("====================================================================\n")
    cat("DETECTED HIGH-PERFORMANCE LOCAL MACHINE\n")
    cat("====================================================================\n")
    USE_PARALLEL <- TRUE
    cat("  Available cores:", n_cores_available, "\n")
    cat("  Parallel processing: ENABLED\n")
    cat("  STEP 1 speedup: 10-14x (60 min → 5-10 min)\n")
    cat("====================================================================\n\n")
  } else {
    cat("Local mode: Sequential processing (", n_cores_available, " cores)\n", sep = "")
    cat("Note: Parallel processing available with 8+ cores\n\n")
  }
}

############################################################################
### EXECUTION CONFIGURATION
############################################################################

# Computational settings
if (EC2_MODE) {
  N_BOOTSTRAP_PHASE2 <- 200  # More iterations for EC2
  N_CORES <- parallel::detectCores() - 1
  cat("EC2 MODE: Using", N_CORES, "cores for parallel processing\n\n")
} else if (USE_PARALLEL) {
  # Local parallel mode - use most cores but leave some for system
  n_cores_available <- parallel::detectCores()
  if (is.na(n_cores_available)) n_cores_available <- 1  # Fallback for systems where detectCores fails
  N_CORES <- max(1, n_cores_available - 2)  # Leave 2 cores for system
  N_BOOTSTRAP_PHASE2 <- 100
  cat("LOCAL PARALLEL MODE: Using", N_CORES, "of", n_cores_available, "cores\n")
  cat("  Bootstrap iterations:", N_BOOTSTRAP_PHASE2, "\n\n")
} else {
  N_BOOTSTRAP_PHASE2 <- 100
  N_CORES <- 1
}

############################################################################
### STEP 2 SPECIFIC CONFIGURATION
############################################################################

# STEP_1 mirai works fine and uses USE_PARALLEL flag
# STEP_2 Parallelization (separate from STEP 1)
# STEP_2 uses same mirai implementation as STEP_1 (successfully tested)
# Set to TRUE for parallel processing across all conditions
if (!exists("USE_PARALLEL_STEP2")) USE_PARALLEL_STEP2 <- TRUE

# Select which STEP 2 experiments to run
# Options:
#   NULL = run all 4 experiments (default)
#   c("exp_1_grade_span") = run only experiment 1
#   c("exp_2_sample_size") = run only experiment 2
#   c("exp_3_content_area") = run only experiment 3
#   c("exp_4_cohort") = run only experiment 4
#   c("exp_1_grade_span", "exp_3_content_area") = run experiments 1 and 3
#
# Examples:
#   EXPERIMENT_TO_RUN_STEP2 <- NULL                        # All experiments
#   EXPERIMENT_TO_RUN_STEP2 <- c("exp_1_grade_span")      # Test experiment 1 only
#   EXPERIMENT_TO_RUN_STEP2 <- c("exp_2_sample_size")     # Test experiment 2 only
if (!exists("EXPERIMENT_TO_RUN_STEP2")) EXPERIMENT_TO_RUN_STEP2 <- NULL

# STEP 2 Subset/Profiling Controls
# These are passed through to sgpc_compute_all_variants.R for local testing
# and EC2 staging before committing to the full 966-condition run.
#
# Examples:
#   STEP2_MAX_CONDITIONS <- 10                  # Smoke test: 10 stratified conditions per dataset
#   STEP2_MAX_CONDITIONS <- 50                  # Medium benchmark
#   STEP2_MAX_CONDITIONS <- NULL                # Full run (all conditions, default)
#   STEP2_SAMPLE_STRATEGY <- "stratified"       # "first", "random", or "stratified"
#   STEP2_SEED <- 42                            # Reproducible subsetting
#
# Memory controls for parallel workers:
#   STEP2_MEMORY_PER_WORKER_GB <- NULL          # Auto-estimate from dataset file size
#   STEP2_TOTAL_MEMORY_GB <- NULL               # Auto-detect system RAM
#   STEP2_MEMORY_PER_WORKER_GB <- 3.0           # Manual override (e.g., for dataset_1)
#   STEP2_TOTAL_MEMORY_GB <- 64                 # EC2 instance memory budget
#
if (!exists("STEP2_MAX_CONDITIONS"))        STEP2_MAX_CONDITIONS        <- NULL
if (!exists("STEP2_SAMPLE_STRATEGY"))       STEP2_SAMPLE_STRATEGY       <- "stratified"
if (!exists("STEP2_SEED"))                  STEP2_SEED                  <- 42
if (!exists("STEP2_MEMORY_PER_WORKER_GB"))  STEP2_MEMORY_PER_WORKER_GB  <- NULL
if (!exists("STEP2_TOTAL_MEMORY_GB"))       STEP2_TOTAL_MEMORY_GB       <- NULL

# EC2 defaults for r8g.16xlarge (64 vCPU, 512 GB RAM)
# These apply only when the user has not already set explicit overrides.
if (exists("EC2_MODE") && isTRUE(EC2_MODE)) {
  if (is.null(STEP2_MEMORY_PER_WORKER_GB)) STEP2_MEMORY_PER_WORKER_GB <- 3.0
  if (is.null(STEP2_TOTAL_MEMORY_GB)) STEP2_TOTAL_MEMORY_GB <- 512
}

if (!is.null(EXPERIMENT_TO_RUN_STEP2)) {
  cat("STEP 2 Configuration:\n")
  cat("  Selected experiments:", paste(EXPERIMENT_TO_RUN_STEP2, collapse = ", "), "\n")
  cat("  Parallel mode:", USE_PARALLEL_STEP2, "\n")
} else {
  cat("STEP 2 Configuration:\n")
  cat("  Running all experiments (1-4)\n")
  cat("  Parallel mode:", USE_PARALLEL_STEP2, "\n")
}
if (!is.null(STEP2_MAX_CONDITIONS)) {
  cat("  Subset mode:", STEP2_MAX_CONDITIONS, "conditions per dataset (", STEP2_SAMPLE_STRATEGY, ")\n")
} else {
  cat("  Subset mode: OFF (all conditions)\n")
}
cat("  Memory per worker (GB):", STEP2_MEMORY_PER_WORKER_GB, "\n")
cat("  Total memory budget (GB):", STEP2_TOTAL_MEMORY_GB, "\n")
cat("\n")

# Generic workspace object name (data gets assigned to this name regardless of source)
WORKSPACE_OBJECT_NAME <- "STATE_DATA_LONG"

# Timestamp for this run
RUN_TIMESTAMP <- format(Sys.time(), "%Y%m%d_%H%M%S")

# Log file
LOG_FILE <- paste0("master_analysis_log_", RUN_TIMESTAMP, ".txt")
sink(LOG_FILE, split = TRUE)

############################################################################
### PATH MANAGEMENT AND WORKING DIRECTORY SETUP
############################################################################

# Set working directory to project root (where master_analysis.R is located)
# Use tryCatch to handle both source() (interactive) and Rscript (command line)
PROJECT_ROOT <- tryCatch({
  # Works when using source() interactively
  dirname(normalizePath(sys.frame(1)$ofile))
}, error = function(e) {
  # Fallback for Rscript: use current working directory
  # (assumes you're running from the project root)
  getwd()
})

if (is.null(PROJECT_ROOT) || PROJECT_ROOT == "") {
  # Final fallback: assume we're in the project root
  PROJECT_ROOT <- getwd()
}

# Set working directory to project root
setwd(PROJECT_ROOT)

# Define key directories relative to project root
FUNCTIONS_DIR <- "functions"
DATA_DIR <- "Data"
RESULTS_DIR <- "results"

# Validate that we're in the correct directory
if (!dir.exists(FUNCTIONS_DIR)) {
  stop("ERROR: functions/ directory not found. Are you running from the project root?")
}

cat("Project root:", PROJECT_ROOT, "\n")
cat("Functions directory:", FUNCTIONS_DIR, "\n")
cat("Working directory:", getwd(), "\n\n")

############################################################################
### HELPER FUNCTIONS (DEFINED EARLY)
############################################################################

# Helper function to source files with proper path handling
source_with_path <- function(file_path, description = NULL) {
  if (is.null(description)) {
    description <- basename(file_path)
  }
  
  # Check if file exists
  if (!file.exists(file_path)) {
    stop("ERROR: File not found: ", file_path, "\n",
         "Description: ", description, "\n",
         "Current working directory: ", getwd())
  }
  
  cat("Sourcing:", description, "\n")
  source(file_path, local = FALSE)
}

# Helper function to source all function files
source_all_functions <- function() {
  function_files <- c(
    "longitudinal_pairs.R",
    "ispline_ecdf.R", 
    "copula_bootstrap.R",
    "copula_contour_plots.R",
    "copula_diagnostics.R",
    "transformation_diagnostics.R",
    "sgpc_engine.R",          # SGPc calculation engine
    "checkpoint_utils.R"      # Checkpoint/resume for spot instances
  )
  
  for (func_file in function_files) {
    func_path <- file.path(FUNCTIONS_DIR, func_file)
    source_with_path(func_path, paste("function:", func_file))
  }
}

# Helper function to get the state data (cleaner than get("STATE_DATA_LONG"))
get_state_data <- function() {
  if (!exists(WORKSPACE_OBJECT_NAME)) {
    stop("ERROR: State data not loaded. Run master_analysis.R first.")
  }
  return(get(WORKSPACE_OBJECT_NAME))
}

# Load all function files
cat("Loading function files...\n")
source_all_functions()
cat("All functions loaded successfully.\n\n")

############################################################################
### INITIALIZATION
############################################################################

# Load required libraries
require(data.table)
require(splines2)
require(copula)
require(grid)

cat("====================================================================\n")
cat("COPULA-BASED PSEUDO-GROWTH SIMULATION FRAMEWORK\n")
cat("Master Analysis Script - 4-Step Sequential Workflow\n")
cat("====================================================================\n")
cat("Version: 3.0 (Restructured)\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("====================================================================\n\n")

cat("Configuration:\n")
cat("  Steps to run:", ifelse(is.null(STEPS_TO_RUN), "ALL (1, 2, 3, 4)", 
                              paste(STEPS_TO_RUN, collapse = ", ")), "\n")
cat("  Batch mode:", BATCH_MODE, "\n")
cat("  EC2 mode:", EC2_MODE, "\n")
cat("  Skip completed:", SKIP_COMPLETED, "\n")
cat("  Skip completed conditions:", SKIP_COMPLETED_CONDITIONS, "\n")
cat("  Bootstrap iterations:", N_BOOTSTRAP_PHASE2, "\n")
cat("  Log file:", LOG_FILE, "\n\n")

############################################################################
### DATA LOADING AND DATASET LOOP
############################################################################

# Determine datasets to loop over
datasets_to_analyze <- DATASETS_TO_RUN

cat("Beginning analysis...\n")
cat("Number of datasets:", length(datasets_to_analyze), "\n\n")

# Initialize accumulation lists for multi-dataset results
ALL_DATASET_RESULTS <- list(
  step1 = list(),
  step2 = list(),
  step3 = list(),
  step4 = list()
)
cat("Results accumulation lists initialized\n\n")

############################################################################
### DATASET LOADING STRATEGY (Per-Task On-Demand Loading)
############################################################################
# 
# CURRENT IMPLEMENTATION: Datasets are NOT loaded upfront in the host process.
# Instead, mirai workers load datasets on-demand per task (see below).
#
# This approach was changed from the original "load all upfront" strategy to:
# - Reduce host memory pressure (~3.74 GB saved)
# - Enable Step 2 per-dataset processing without combined dataset resident
# - Allow workers to load only what they need
#
# For Step 1 (all datasets): Workers load specific datasets as needed
# For Step 2-4 (per-dataset): Host loads one dataset at a time in loop below
############################################################################

# Mirai daemons load datasets on-demand per task (see phase1_family_selection_parallel.R)
# No upfront data loading needed - saves ~60 seconds startup and ~3.74 GB host RAM
cat(paste(rep("=", 80), collapse=""), "\n", sep="")
cat("DATA LOADING: Deferred to mirai workers\n")
cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
cat("Mirai workers will load specific datasets on-demand per task.\n")
cat("This approach:\n")
cat("  - Saves host startup time (~60 seconds)\n")
cat("  - Saves host memory (~3.74 GB)\n")
cat("  - Loads only what each worker needs\n")
cat("  - Workers cache loaded datasets for efficiency\n\n")

# Keep DATASET_CONFIGS for worker reference
DATASET_CONFIGS <- DATASETS

cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

################################################################################
### HELPER FUNCTIONS (for all steps)
################################################################################

pause_for_review <- function(message, phase_name) {
  if (!BATCH_MODE) {
    cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
    cat("REVIEW CHECKPOINT:", phase_name, "\n")
    cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
    cat(message, "\n\n")
    cat("Press Enter to continue or Ctrl+C to stop...\n")
    readline()
  }
}

check_results_exist <- function(file_path, description) {
  if (file.exists(file_path)) {
    cat("✓ Found existing:", description, "\n")
    cat("  Location:", file_path, "\n")
    return(TRUE)
  }
  return(FALSE)
}

time_phase <- function(phase_name, code) {
  cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
  cat("STARTING:", phase_name, "\n")
  cat("Time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
  
  start_time <- Sys.time()
  
  result <- tryCatch({
    code
    list(success = TRUE, error = NULL)
  }, error = function(e) {
    cat("\n*** ERROR in", phase_name, "***\n")
    cat("Message:", e$message, "\n\n")
    list(success = FALSE, error = e$message)
  })
  
  end_time <- Sys.time()
  duration <- difftime(end_time, start_time, units = "mins")
  
  cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
  if (result$success) {
    cat("✓ COMPLETED:", phase_name, "\n")
  } else {
    cat("✗ FAILED:", phase_name, "\n")
    cat("Error:", result$error, "\n")
  }
  cat("Duration:", round(duration, 2), "minutes\n")
  cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
  
  return(result)
}

############################################################################
### STEP 1: COPULA FAMILY SELECTION (ALL DATASETS IN PARALLEL)
############################################################################
# 
# This runs BEFORE the per-dataset loop. All conditions from all datasets
# are processed in a single parallel batch for maximum CPU utilization.
############################################################################

if (should_run_step(1)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 1: COPULA FAMILY SELECTION (ALL DATASETS)\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Background → TAMP and Copulas; Methodology → Copula Selection\n")
  cat("Objective: Identify which copula family best fits longitudinal education data\n")
  cat("Hypothesis: t-copula will dominate due to heavy tails\n")
  cat("Processing: ALL conditions from ALL datasets in single parallel batch\n")
  cat("Estimated time: 30-60 minutes (parallel across all datasets)\n\n")
  
  # Show checkpoint status before processing
  if (SKIP_COMPLETED_CONDITIONS) {
    cat("Checking for previously completed conditions...\n")
    print_checkpoint_summary("STEP_1_Family_Selection/results")
  }
  
  # Export settings to .GlobalEnv for parallel script access
  assign("SKIP_COMPLETED_CONDITIONS", SKIP_COMPLETED_CONDITIONS, envir = .GlobalEnv)
  
  ## Step 1.1: Family Selection (All Datasets)
  phase1_results_file <- "STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv"
  
  if (SKIP_COMPLETED && check_results_exist(phase1_results_file, "Step 1 family comparison (all datasets)")) {
    cat("Skipping Step 1.1 (already completed)\n\n")
  } else {
    result_1_1 <- time_phase("Step 1.1: Family Selection (All Datasets)", {
      # Pass ALL dataset configs to parallel script via .GlobalEnv
      # The parallel script checks exists("ALL_DATASET_CONFIGS", envir = .GlobalEnv)
      # CRITICAL: Must assign to .GlobalEnv, not local environment
      assign("ALL_DATASET_CONFIGS", DATASET_CONFIGS, envir = .GlobalEnv)
      
      if (USE_PARALLEL) {
        cat("Using parallel implementation (all datasets in single batch)\n")
        source_with_path("STEP_1_Family_Selection/phase1_family_selection_parallel.R", "Step 1.1: Family Selection (Parallel)")
      } else {
        cat("Using sequential implementation\n")
        source_with_path("STEP_1_Family_Selection/phase1_family_selection.R", "Step 1.1: Family Selection")
      }
    })
    
    if (!result_1_1$success) {
      stop("Step 1.1 failed. Cannot continue.")
    }
  }
  
  # Note: Step 1.2 (Analysis and Decision) runs at the end after all processing
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 1: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

############################################################################
### MAIN DATASET LOOP - Steps 2, 3, 4 (Per-Dataset Processing)
############################################################################
# 
# Steps 2, 3, 4 may have per-dataset dependencies and are processed
# sequentially per dataset. Step 1 has already been processed above.
############################################################################

cat("\n")
cat(paste(rep("=", 80), collapse=""), "\n", sep="")
cat("BEGINNING PER-DATASET PROCESSING (Steps 2-4)\n")
cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

for (dataset_idx in seq_along(datasets_to_analyze)) {
  
  dataset_id <- datasets_to_analyze[dataset_idx]
  
  ###########################################################################
  # DATASET-SPECIFIC CONFIGURATION
  ###########################################################################
  
  # Load configuration for this dataset
  current_dataset <- DATASET_CONFIGS[[dataset_id]]
  
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("DATASET ", dataset_idx, " OF ", length(datasets_to_analyze), ": ", current_dataset$name, "\n", sep="")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("ID: ", current_dataset$id, "\n", sep="")
  cat("Scaling types: ", paste(unique(current_dataset$scaling_by_year$scaling_type), collapse = " / "), "\n", sep="")
  cat("Has transition: ", current_dataset$has_transition, "\n", sep="")
  if (current_dataset$has_transition) {
    cat("Transition year: ", current_dataset$transition_year, "\n", sep="")
  }
  cat("Content areas: ", paste(current_dataset$content_areas, collapse = ", "), "\n", sep="")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
  
  # Set dataset-specific paths and names (use EC2 path if on EC2)
  # Use SGP data files if enabled and available
  if (USE_SGP_DATA && !is.null(current_dataset$local_path_sgp)) {
    CURRENT_DATA_PATH <- if (IS_EC2) current_dataset$ec2_path_sgp else current_dataset$local_path_sgp
    CURRENT_RDATA_OBJECT <- current_dataset$rdata_object_name_sgp
    cat("  Using SGP data file (includes traditional SGP column)\n")
  } else {
    CURRENT_DATA_PATH <- if (IS_EC2) current_dataset$ec2_path else current_dataset$local_path
    CURRENT_RDATA_OBJECT <- current_dataset$rdata_object_name
    if (USE_SGP_DATA) {
      cat("  WARNING: SGP data file not configured, using base data\n")
    }
  }
  CURRENT_DATASET_NAME <- current_dataset$name
  
  # Results suffix for this dataset (used in all output files)
  RESULTS_SUFFIX <- paste0("_", dataset_id)
  
  ###########################################################################
  # FILTER COMBINED DATA FOR CURRENT DATASET
  ###########################################################################
  
  cat("Filtering combined data for:", CURRENT_DATASET_NAME, "\n")
  
  # Filter the combined dataset to just this dataset if available,
  # otherwise load the dataset file directly for Steps 2-4.
  # 
  # NOTE: As of current implementation (lines 611-621), ALL_DATASETS_COMBINED
  # is NEVER created - data loading is deferred to mirai workers. This means
  # for Step 2-only runs, the else branch below will ALWAYS be taken,
  # loading data directly from disk into host memory for the per-dataset loop.
  # This is correct and avoids keeping ~3.74GB resident in host memory.
  if (exists("ALL_DATASETS_COMBINED")) {
    dataset_data <- ALL_DATASETS_COMBINED[DATASET == dataset_id]
  } else {
    cat("Combined dataset not found. Loading dataset file directly.\n")
    if (!file.exists(CURRENT_DATA_PATH)) {
      stop("ERROR: Data file not found: ", CURRENT_DATA_PATH)
    }
    load(CURRENT_DATA_PATH)
    if (!exists(CURRENT_RDATA_OBJECT)) {
      stop("ERROR: Expected object '", CURRENT_RDATA_OBJECT, "' not found in ", CURRENT_DATA_PATH)
    }
    dataset_data <- get(CURRENT_RDATA_OBJECT)
    data.table::setDT(dataset_data)
    if (!"DATASET" %in% names(dataset_data)) {
      dataset_data[, DATASET := dataset_id]
    }
  }

  # STATE_DATA_LONG will contain just this dataset's data for Steps 2-4
  assign(WORKSPACE_OBJECT_NAME, dataset_data)
  
  # Validate that data was loaded successfully
  if (!exists(WORKSPACE_OBJECT_NAME)) {
    stop("CRITICAL ERROR: Failed to load dataset for ", dataset_id)
  }
  
  cat("✓ Dataset loaded and validated\n")
  cat("  Workspace object:", WORKSPACE_OBJECT_NAME, "\n")
  cat("  Rows:", format(nrow(dataset_data), big.mark = ","), "\n")
  cat("  Columns:", ncol(dataset_data), "\n")
  cat("  Memory:", format(object.size(dataset_data), units = "MB"), "\n")
  cat("  Results suffix:", ifelse(RESULTS_SUFFIX == "", "(none)", RESULTS_SUFFIX), "\n\n")

################################################################################
### STEP 3: GROWTH REGIME INFERENCE — LIw_LD (Per-Dataset)
################################################################################
# Note: Step 1 has already been processed for ALL datasets above.
# Per-dataset: Steps 2.1/2.1b and 3 run here; Steps 2.2-2.6 run once after loop.
#
# STEP 3 (LIw_LD) validates growth regime inference from cross-sectional
# data against ground truth from longitudinal pairs. This is the "piece
# de resistance" — demonstrating that group-level growth distributions
# can be recovered without student-level linkage.
################################################################################

if (should_run_step(3)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 3: GROWTH REGIME INFERENCE (LIw_LD)\n")
  cat("### Longitudinal Inference without Longitudinal Data\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Chapter 4 — Growth Regime Inference from Cross-Sectional Data\n")
  cat("Objective: Validate copula-kernel growth regime inference against longitudinal truth\n")
  cat("Estimated time: 30-90 minutes\n\n")
  
  step3_results_dir <- "STEP_3_LIw_LD/results"
  step3_summary <- file.path(step3_results_dir, "phase_a_summary.csv")
  
  if (SKIP_COMPLETED && file.exists(step3_summary)) {
    cat("Skipping Step 3 (already completed)\n")
    cat("  Results:", step3_results_dir, "\n\n")
  } else {
    result_3 <- time_phase("Step 3: Growth Regime Inference (LIw_LD)", {
      source("STEP_3_LIw_LD/run_step3.R")
    })
    
    if (!result_3$success) {
      cat("\n*** WARNING: Step 3 (LIw_LD) failed ***\n")
      cat("This is the core growth regime inference validation.\n")
      cat("Recommend investigating before proceeding to TIMSS application.\n\n")
      
      if (!BATCH_MODE) {
        cat("Continue anyway? (y/n): ")
        response <- readline()
        if (tolower(response) != "y") {
          stop("Stopping due to Step 3 failure.")
        }
      }
    }
  }
  
  ## Review Step 3 Results
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 3 RESULTS SUMMARY\n")
  cat("####################################################################\n\n")
  
  if (file.exists(step3_summary)) {
    s3_summary <- fread(step3_summary)
    cat("Phase A (Deep Validation):\n")
    cat("  Condition:", s3_summary$condition_id[1], "\n")
    cat("  Subgroup:", s3_summary$subgroup_id[1],
        "(n =", s3_summary$n_subgroup[1], ")\n")
    cat("  Inferred median SGPc:", s3_summary$median_sgpc_inferred[1], "\n")
    cat("  True median SGPc:    ", s3_summary$median_sgpc_true[1], "\n")
    cat("  Difference:          ", s3_summary$median_diff[1], "SGP points\n")
    cat("  Bootstrap 95% CI:    [", s3_summary$boot_ci_lo[1], ",",
        s3_summary$boot_ci_hi[1], "]\n\n")
  }
  
  phase_b_file <- file.path(step3_results_dir, "phase_b_systematic_summary.csv")
  if (file.exists(phase_b_file)) {
    s3_sys <- fread(phase_b_file)
    cat("Phase B (Systematic Validation):\n")
    cat("  Subgroups:", nrow(s3_sys), "\n")
    cat("  Median |error|:", round(median(abs(s3_sys$median_diff)), 2), "SGP points\n")
    cat("  Mean |error|:  ", round(mean(abs(s3_sys$median_diff)), 2), "SGP points\n\n")
  }
  
  pause_for_review(
    paste0("Review Step 3 results (Growth Regime Inference):\n",
           "  - STEP_3_LIw_LD/results/\n",
           "  - STEP_3_LIw_LD/results/visualizations/\n\n",
           "If validation passed, proceed to Step 4 (TIMSS application)."),
    "Step 3 Complete"
  )
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 3: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### STEP 2: SGPc SENSITIVITY ANALYSIS (RE-IMAGINED JANUARY 2026)
################################################################################
###
### NEW FOCUS: Assess practical impact of copula choice on SGPc values
### 
### Previous STEP_2 tested parameter stability (grade span, sample size, etc.)
### but Phase 1 already comprehensively analyzed this across 966 conditions.
###
### New STEP_2 computes multiple SGPc variants (empirical, best-fit, canonical,
### mis-specified, TAMP comonotonic) to demonstrate practical consequences of
### Sklar-theoretic extension.
###
### See: STEP_2_SGPc_Sensitivity/README.md for details
### Deprecated experiments in: STEP_2_Copula_Sensitivity_Analyses/deprecated/
###
################################################################################

if (should_run_step(2)) {

  if (!exists("SKIP_COMPLETED_STEP2")) SKIP_COMPLETED_STEP2 <- FALSE
  if (!exists("USE_PARALLEL_STEP2")) USE_PARALLEL_STEP2 <- FALSE
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 2: SGPc SENSITIVITY ANALYSIS\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Application → SGPc Sensitivity (Sklar-Theoretic Extension)\n")
  cat("Objective: Quantify practical impact of copula choice on SGPcs\n")
  cat("Mode:", if (USE_PARALLEL_STEP2) "PARALLEL (mirai)" else "SEQUENTIAL", "\n")
  cat("Estimated time:", if (USE_PARALLEL_STEP2) "60-120 minutes" else "3-6 hours", "\n\n")
  
  cat("NOTE: Parameter stability (grade span, sample size, content area, cohort)\n")
  cat("      already analyzed in Phase 1 across 966 conditions.\n")
  cat("      Old experiments archived in: STEP_2_Copula_Sensitivity_Analyses/deprecated/\n\n")
  
  ############################################################################
  ### VALIDATE PHASE 1 OUTPUTS EXIST
  ############################################################################
  
  manifest_file <- "STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json"
  if (!file.exists(manifest_file)) {
    stop("Phase 1 manifest not found: ", manifest_file, "\n",
         "       Run Phase 1 analysis first:\n",
         "       source('STEP_1_Family_Selection/phase1_analysis.R')")
  }
  
  cat("✓ Phase 1 outputs validated\n")
  cat("  Manifest:", manifest_file, "\n\n")
  
  ############################################################################
  ### STEP 2.1: COMPUTE ALL SGPc VARIANTS
  ############################################################################
  
  variants_complete <- file.exists(
    file.path("STEP_2_SGPc_Sensitivity/results", 
              paste0("sgpc_all_variants_", dataset_id, ".rds"))
  )
  
  if (SKIP_COMPLETED_STEP2 && variants_complete) {
    cat("✓ Skipping Step 2.1 (SGPc variants already computed)\n\n")
  } else {
    cat("Running Step 2.1: Computing SGPc variants...\n\n")
    
    result_2_1 <- time_phase("Step 2.1: Compute SGPc Variants", {
      # Export dataset configurations to global env (for lazy loading)
      assign("DATASETS", DATASETS, envir = .GlobalEnv)
      assign("IS_EC2", IS_EC2, envir = .GlobalEnv)
      # Set environment variables for the computation script
      assign("USE_PARALLEL", USE_PARALLEL_STEP2, envir = .GlobalEnv)
      assign("DATASETS_TO_PROCESS", dataset_id, envir = .GlobalEnv)
      # Export STEP_2 subset and memory controls
      assign("STEP2_MAX_CONDITIONS",       STEP2_MAX_CONDITIONS,       envir = .GlobalEnv)
      assign("STEP2_SAMPLE_STRATEGY",      STEP2_SAMPLE_STRATEGY,      envir = .GlobalEnv)
      assign("STEP2_SEED",                 STEP2_SEED,                 envir = .GlobalEnv)
      assign("STEP2_MEMORY_PER_WORKER_GB", STEP2_MEMORY_PER_WORKER_GB, envir = .GlobalEnv)
      assign("STEP2_TOTAL_MEMORY_GB",      STEP2_TOTAL_MEMORY_GB,      envir = .GlobalEnv)
      source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
    })
    
    if (!result_2_1$success) {
      cat("ERROR in Step 2.1: SGPc variant computation failed\n\n")
      stop("Cannot proceed with Step 2 without variant computations")
    }
  }
  
  ############################################################################
  ### STEP 2.1b: CANONICAL COPULA VALIDATION
  ############################################################################
  
  canonical_val_complete <- file.exists("STEP_2_SGPc_Sensitivity/results/canonical_validation_report.md")
  
  if (SKIP_COMPLETED_STEP2 && canonical_val_complete) {
    cat("✓ Skipping Step 2.1b (canonical validation already done)\n\n")
  } else {
    cat("Running Step 2.1b: Canonical copula validation...\n\n")
    
    result_2_1b <- time_phase("Step 2.1b: Canonical Copula Validation", {
      source("STEP_2_SGPc_Sensitivity/canonical_validation.R")
    })
    
    if (!result_2_1b$success) {
      cat("Warning: Canonical validation failed (non-fatal, continuing)\n\n")
    }
  }
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 2: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### STEP 4: TIMSS IMPLEMENTATION
################################################################################
# Applies the copula-kernel growth regime inference framework (validated
# in STEP 3) to actual TIMSS data (independent Grade 4 and Grade 8 samples).
# Currently a placeholder — awaiting TIMSS data acquisition.
################################################################################

if (should_run_step(4)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 4: TIMSS IMPLEMENTATION\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Chapter 5 — International Application\n")
  cat("Objective: Deploy copula-kernel growth regime inference on TIMSS data\n")
  cat("Status: PLACEHOLDER — awaiting TIMSS data and STEP 3 completion\n\n")
  
  step4_runner <- "STEP_4_TIMSS_Implementation/run_step4.R"
  if (file.exists(step4_runner)) {
    result_4 <- time_phase("Step 4: TIMSS Implementation", {
      source(step4_runner)
    })
    
    if (!result_4$success) {
      cat("Warning: Step 4 (TIMSS) failed but continuing.\n\n")
    }
  } else {
    cat("Step 4 runner not yet implemented.\n")
    cat("See STEP_4_TIMSS_Implementation/README.md for planned workflow.\n\n")
  }
  
  pause_for_review(
    paste0("Review Step 4 status:\n",
           "  - STEP_4_TIMSS_Implementation/README.md\n\n",
           "Step 4 is a placeholder. Proceed to Step 5 (summary)."),
    "Step 4 Complete"
  )
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 4: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### STEP 5: SUMMARY, CONCLUSIONS, AND NEXT STEPS
################################################################################
# Final synthesis of all results. Currently a placeholder.
################################################################################

if (should_run_step(5)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 5: SUMMARY, CONCLUSIONS, AND NEXT STEPS\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Chapter 6 — Discussion; Chapter 7 — Conclusions\n")
  cat("Objective: Synthesise findings, generate publication materials\n")
  cat("Status: PLACEHOLDER — awaiting upstream step completion\n\n")
  
  step5_runner <- "STEP_5_Summary_Conclusions_Next_Steps/step5_comprehensive_report.R"
  if (file.exists(step5_runner)) {
    result_5 <- time_phase("Step 5: Summary and Conclusions", {
      source(step5_runner)
    })
    
    if (!result_5$success) {
      cat("Warning: Step 5 (summary) failed.\n\n")
    }
  } else {
    cat("Step 5 runner not yet implemented.\n")
    cat("See STEP_5_Summary_Conclusions_Next_Steps/README.md for planned content.\n\n")
  }
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 5: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### SGPc AGGREGATION AND SAVE (Per Dataset)
################################################################################

  if (exists("CALCULATE_SGPC", envir = .GlobalEnv) && 
      get("CALCULATE_SGPC", envir = .GlobalEnv, inherits = FALSE) &&
      should_run_step(1)) {
    
    cat("\n")
    cat("####################################################################\n")
    cat("### AGGREGATING SGPc RESULTS FOR DATASET\n")
    cat("####################################################################\n\n")
    
    # Find all SGPc result files for this dataset
    # SGPc files are saved in: contour_plots/CONDITION/sgpc_results/sgpc_values.rds
    dataset_id <- current_dataset$id
    dataset_results_dir <- file.path("STEP_1_Family_Selection/results", dataset_id)
    
    # Search recursively for sgpc_values.rds files in the contour_plots subdirectories
    sgpc_files <- list.files(
      path = dataset_results_dir,
      pattern = "sgpc_values\\.rds$",
      recursive = TRUE,
      full.names = TRUE
    )
    
    if (length(sgpc_files) > 0) {
        cat("Found", length(sgpc_files), "SGPc result files\n")
        
        # Load and combine all SGPc results
        sgpc_list <- lapply(sgpc_files, function(f) {
          tryCatch(readRDS(f), error = function(e) NULL)
        })
        sgpc_list <- sgpc_list[!sapply(sgpc_list, is.null)]
        
        if (length(sgpc_list) > 0) {
          # Combine all condition SGPc results
          all_sgpc <- rbindlist(sgpc_list, fill = TRUE)
          
          cat("Combined SGPc results:", nrow(all_sgpc), "rows\n")
          
          # Save combined SGPc file in dataset results directory
          combined_sgpc_file <- file.path(dataset_results_dir, "sgpc_all_conditions.rds")
          saveRDS(all_sgpc, combined_sgpc_file)
          cat("✓ Combined SGPc saved:", combined_sgpc_file, "\n")
          
          # Try to merge back into main data file
          state_data <- get_state_data()
          
          # Get SGPc columns
          sgpc_cols <- grep("^SGPc_", names(all_sgpc), value = TRUE)
          
          if (length(sgpc_cols) > 0) {
            cat("\nMerging SGPc columns into main data...\n")
            cat("  Columns:", paste(sgpc_cols, collapse = ", "), "\n")
            
            # Create unique key for merging: ID + YEAR + GRADE + CONTENT_AREA
            # Note: SGPc results have YEAR/GRADE columns (current year/grade when score was measured)
            all_sgpc[, merge_key := paste(ID, YEAR, GRADE, CONTENT_AREA, sep = "_")]
            state_data[, merge_key := paste(ID, YEAR, GRADE, CONTENT_AREA, sep = "_")]
            
            # Get mean SGPc per student/year/grade/content (in case of multiple priors)
            # This handles cases where a student might have multiple prior configurations
            sgpc_to_merge <- all_sgpc[, c(list(merge_key = merge_key[1]), 
                                         lapply(.SD, function(x) as.integer(round(mean(x, na.rm = TRUE))))), 
                                     by = merge_key, 
                                     .SDcols = sgpc_cols]
            sgpc_to_merge[, merge_key := NULL]  # Remove duplicate
            setnames(sgpc_to_merge, "merge_key", "merge_key_drop")
            sgpc_to_merge[, merge_key := merge_key_drop][, merge_key_drop := NULL]
            
            # Remove any existing SGPc columns from state_data
            existing_sgpc_cols <- grep("^SGPc_", names(state_data), value = TRUE)
            if (length(existing_sgpc_cols) > 0) {
              state_data[, (existing_sgpc_cols) := NULL]
            }
            
            # Merge
            state_data <- merge(state_data, sgpc_to_merge, by = "merge_key", all.x = TRUE)
            state_data[, merge_key := NULL]
            
            # Count merged rows
            n_merged <- sum(!is.na(state_data[[sgpc_cols[1]]]))
            cat("  Merged rows with SGPc:", format(n_merged, big.mark = ","), "\n")
            
            # Update the workspace object
            assign(WORKSPACE_OBJECT_NAME, state_data)
            
            # Save updated data file
            if (USE_SGP_DATA && !is.null(current_dataset$local_path_sgp)) {
              output_path <- current_dataset$local_path_sgp
              rdata_object_name <- current_dataset$rdata_object_name_sgp
              
              # Create object with correct name and save
              assign(rdata_object_name, state_data)
              save(list = rdata_object_name, file = output_path)
              
              cat("✓ Updated data file saved:", output_path, "\n")
              cat("  Total observations:", format(nrow(state_data), big.mark = ","), "\n")
              cat("  SGPc columns added:", paste(sgpc_cols, collapse = ", "), "\n")
            }
            
            # Generate summary statistics
            cat("\nSGPc Summary by Copula Family:\n")
            cat(paste(rep("-", 60), collapse = ""), "\n")
            
            for (col in sgpc_cols) {
              valid_vals <- state_data[[col]][!is.na(state_data[[col]])]
              if (length(valid_vals) > 0) {
                cat(sprintf("  %-20s: n=%s, mean=%.1f, sd=%.1f\n", 
                            col, format(length(valid_vals), big.mark = ","),
                            mean(valid_vals), sd(valid_vals)))
              }
            }
            
            # Correlations with traditional SGP
            if ("SGP" %in% names(state_data)) {
              cat("\nCorrelations with Traditional SGP:\n")
              cat(paste(rep("-", 60), collapse = ""), "\n")
              
              for (col in sgpc_cols) {
                valid_idx <- !is.na(state_data[[col]]) & !is.na(state_data$SGP)
                if (sum(valid_idx) > 100) {
                  corr <- cor(state_data[[col]][valid_idx], state_data$SGP[valid_idx])
                  cat(sprintf("  %-20s: r=%.4f (n=%s)\n", col, corr, 
                              format(sum(valid_idx), big.mark = ",")))
                }
              }
            }
            
            cat("\n")
          }
        }
      } else {
      cat("No SGPc result files found for dataset:", dataset_id, "\n")
      cat("  (Searched in:", dataset_results_dir, ")\n")
    }
  }

################################################################################
### FINAL SUMMARY
################################################################################

  ###########################################################################
  # END OF DATASET LOOP ITERATION
  ###########################################################################
  
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("COMPLETED ANALYSIS FOR: ", CURRENT_DATASET_NAME, "\n", sep="")
  cat("Dataset ", dataset_idx, " of ", length(datasets_to_analyze), " complete\n", sep="")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
  
} # END DATASET LOOP

################################################################################
### STEP 2.2–2.6: CROSS-DATASET ANALYSIS, REPORTING & PUBLICATION FIGURES
################################################################################
# These steps combine results from ALL datasets and must run once, after
# the per-dataset loop has produced sgpc_all_variants_*.rds for every dataset.
################################################################################

if (should_run_step(2)) {

  if (!exists("SKIP_COMPLETED_STEP2")) SKIP_COMPLETED_STEP2 <- FALSE

  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 2 (continued): CROSS-DATASET ANALYSIS\n")
  cat("####################################################################\n\n")

  ############################################################################
  ### STEP 2.2: AGGREGATE ANALYSIS
  ############################################################################

  aggregate_complete <- file.exists("STEP_2_SGPc_Sensitivity/results/sgpc_key_comparisons.csv")

  if (SKIP_COMPLETED_STEP2 && aggregate_complete) {
    cat("✓ Skipping Step 2.2 (aggregate analysis already done)\n\n")
  } else {
    cat("Running Step 2.2: Aggregate analysis...\n\n")

    result_2_2 <- time_phase("Step 2.2: Aggregate Analysis", {
      source("STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R")
    })

    if (!result_2_2$success) {
      cat("Warning: Aggregate analysis failed\n\n")
    }
  }

  ############################################################################
  ### STEP 2.3: VISUALIZATIONS
  ############################################################################

  vis_complete <- file.exists("STEP_2_SGPc_Sensitivity/results/visualizations/scatter_emp_vs_best.pdf")

  if (SKIP_COMPLETED_STEP2 && vis_complete) {
    cat("✓ Skipping Step 2.3 (visualizations already created)\n\n")
  } else {
    cat("Running Step 2.3: Creating visualizations...\n\n")

    result_2_3 <- time_phase("Step 2.3: Visualizations", {
      source("STEP_2_SGPc_Sensitivity/sgpc_visualizations.R")
    })

    if (!result_2_3$success) {
      cat("Warning: Visualization creation failed\n\n")
    }
  }

  ############################################################################
  ### STEP 2.4: GENERATE REPORT
  ############################################################################

  report_complete <- file.exists("STEP_2_SGPc_Sensitivity/results/SGPC_SENSITIVITY_REPORT.md")

  if (SKIP_COMPLETED_STEP2 && report_complete) {
    cat("✓ Skipping Step 2.4 (report already generated)\n\n")
  } else {
    cat("Running Step 2.4: Generating narrative report...\n\n")

    result_2_4 <- time_phase("Step 2.4: Generate Report", {
      source("STEP_2_SGPc_Sensitivity/sgpc_generate_report.R")
    })

    if (!result_2_4$success) {
      cat("Warning: Report generation failed\n\n")
    }
  }

  ############################################################################
  ### STEP 2.5: PUBLICATION FIGURE
  ############################################################################

  pub_fig_complete <- file.exists("STEP_2_SGPc_Sensitivity/results/visualizations/sgpc_summary_grid.pdf")

  if (SKIP_COMPLETED_STEP2 && pub_fig_complete) {
    cat("✓ Skipping Step 2.5 (publication figure already created)\n\n")
  } else if (file.exists("STEP_2_SGPc_Sensitivity/create_publication_figure.R")) {
    cat("Running Step 2.5: Creating publication figure...\n\n")

    result_2_5 <- time_phase("Step 2.5: Publication Figure", {
      tryCatch({
        source("STEP_2_SGPc_Sensitivity/create_publication_figure.R")
        TRUE
      }, error = function(e) {
        cat(sprintf("ERROR: %s\n", e$message))
        FALSE
      })
    })

    if (!result_2_5$success || !isTRUE(result_2_5$result)) {
      cat("Warning: Publication figure generation encountered issues\n\n")
    }
  } else {
    cat("Skipping Step 2.5: create_publication_figure.R not found\n\n")
  }

  ############################################################################
  ### STEP 2.6: WRITE CONSOLIDATED MANIFEST
  ############################################################################

  cat("Running Step 2.6: Write STEP_2 manifest...\n\n")
  result_2_6 <- time_phase("Step 2.6: Write STEP_2 manifest", {
    tryCatch({
      source("STEP_2_SGPc_Sensitivity/write_step2_manifest.R")
      TRUE
    }, error = function(e) {
      cat(sprintf("Warning: Manifest write failed: %s\n", e$message))
      FALSE
    })
  })
  if (!result_2_6$success || !isTRUE(result_2_6$result)) {
    cat("Warning: Step 2.6 (manifest) failed (non-fatal, continuing)\n\n")
  }

  ## Step 2 Summary
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 2: SGPc SENSITIVITY COMPLETE\n")
  cat("####################################################################\n\n")

  cat("Results saved in: STEP_2_SGPc_Sensitivity/results/\n")
  cat("  - Per-dataset SGPc variants: sgpc_all_variants_{dataset_id}.rds\n")
  cat("  - Summary statistics: sgpc_key_comparisons.csv\n")
  cat("  - Manifest: sgpc_sensitivity_manifest.json\n")
  cat("  - Report: SGPC_SENSITIVITY_REPORT.md\n")
  cat("  - Visualizations: visualizations/*.{pdf,svg,png}\n")
  cat("  - Publication figure: visualizations/sgpc_summary_grid.{pdf,svg,png}\n\n")

  pause_for_review(
    paste0("Review Step 2 SGPc sensitivity results:\n",
           "  - STEP_2_SGPc_Sensitivity/results/SGPC_SENSITIVITY_REPORT.md\n",
           "  - STEP_2_SGPc_Sensitivity/results/visualizations/\n",
           "  - STEP_2_SGPc_Sensitivity/results/visualizations/sgpc_summary_grid.pdf (Publication Figure)\n\n",
           "Key outputs: Quantified impact of copula choice on SGPcs.\n",
           "If analysis completed successfully, we'll proceed to Step 3."),
    "Step 2 Complete"
  )

} # END STEP 2 cross-dataset block

###############################################################################
# COMBINE RESULTS FROM ALL DATASETS
###############################################################################

require(data.table)

cat("\n")
cat(paste(rep("=", 80), collapse=""), "\n", sep="")
cat("COMBINING RESULTS FROM ALL DATASETS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

# Combine STEP 1 results
if (should_run_step(1)) {
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("COMBINING STEP 1 RESULTS FROM ALL DATASETS\n")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
  
  combined_results_dir <- "STEP_1_Family_Selection/results/dataset_all"
  output_file <- paste0(combined_results_dir, "/phase1_copula_family_comparison_all_datasets.csv")
  
  # Check if combined results already exist (saved by parallel script in multi-dataset mode)
  if (file.exists(output_file)) {
    cat("Loading existing combined results from:", output_file, "\n")
    step1_combined <- fread(output_file)
  } else if (length(ALL_DATASET_RESULTS$step1) > 0) {
    # Combine from per-dataset results (backwards compatibility)
    cat("Combining results from", length(ALL_DATASET_RESULTS$step1), "datasets...\n")
    step1_combined <- rbindlist(ALL_DATASET_RESULTS$step1, fill = TRUE)
    
    # Save combined results
    dir.create(combined_results_dir, showWarnings = FALSE, recursive = TRUE)
    fwrite(step1_combined, output_file)
    cat("✓ Combined STEP 1 results saved to:", output_file, "\n\n")
  } else {
    cat("No STEP 1 results found to combine.\n\n")
    step1_combined <- NULL
  }
  
  if (!is.null(step1_combined) && nrow(step1_combined) > 0) {
    cat("COMBINED RESULTS SUMMARY:\n")
    cat(paste(rep("-", 70), collapse=""), "\n", sep="")
    n_datasets <- uniqueN(step1_combined$dataset_id)
    cat("  Total datasets:", n_datasets, "\n")
    # Count unique dataset+condition combinations (condition_id is not globally unique)
    n_unique_conditions <- uniqueN(step1_combined[, paste(dataset_id, condition_id, sep = "_")])
    n_unique_families <- uniqueN(step1_combined$family)
    expected_rows <- n_unique_conditions * n_unique_families
    cat("  Total unique conditions (across all datasets):", n_unique_conditions, "\n")
    cat("  Total copula families:", n_unique_families, "\n")
    cat("  Total rows (conditions × families):", nrow(step1_combined), "\n")
    cat("  Expected rows:", n_unique_conditions, "×", n_unique_families, "=", expected_rows, "\n")
    if (nrow(step1_combined) != expected_rows) {
      cat("  ⚠ WARNING: Row count mismatch detected!\n")
    }
    cat("  Columns:", ncol(step1_combined), "\n")
    cat(paste(rep("-", 70), collapse=""), "\n\n", sep="")
    
    # Detailed summary by dataset
    cat("BREAKDOWN BY DATASET:\n")
    cat(paste(rep("-", 70), collapse=""), "\n", sep="")
    summary_table <- step1_combined[, .(
      n_conditions = uniqueN(condition_id),
      n_families = length(unique(family)),
      n_rows = .N,
      expected_rows = uniqueN(condition_id) * length(unique(family)),
      has_mismatch = .N != (uniqueN(condition_id) * length(unique(family)))
    ), by = dataset_id]
    print(summary_table)
    cat("\n")
    
    # Winners by dataset
    cat("WINNING FAMILIES BY DATASET:\n")
    cat(paste(rep("-", 70), collapse=""), "\n", sep="")
    winners_table <- step1_combined[, is_winner := (family == best_aic)
    ][is_winner == TRUE, .N, by = .(dataset_id, family)]
    setorder(winners_table, dataset_id, -N)
    print(winners_table)
    cat("\n")
    
    ###########################################################################
    # STEP 1.2: ANALYSIS AND DECISION (on combined data)
    ###########################################################################
    
    cat("\n")
    cat(paste(rep("=", 80), collapse=""), "\n", sep="")
    cat("STEP 1.2: ANALYSIS AND DECISION\n")
    cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
    
    phase1_decision_file <- "STEP_1_Family_Selection/results/dataset_all/phase1_decision.RData"
    
    if (SKIP_COMPLETED && check_results_exist(phase1_decision_file, "Step 1 decision")) {
      cat("Skipping Step 1.2 (already completed)\n\n")
    } else {
      result_1_2 <- time_phase("Step 1.2: Analysis and Decision", {
        source_with_path("STEP_1_Family_Selection/phase1_analysis.R", "Step 1.2: Analysis and Decision")
      })
      
      if (!result_1_2$success) {
        stop("Step 1.2 failed. Cannot continue.")
      }
    }
    
    ## Review Step 1 Results
    cat("\n")
    cat("####################################################################\n")
    cat("### STEP 1 RESULTS SUMMARY\n")
    cat("####################################################################\n\n")
    
    if (file.exists(phase1_decision_file)) {
      load(phase1_decision_file)
      
      cat("DECISION:", decision, "\n")
      cat("Selected families for Step 2+:", paste(phase2_families, collapse = ", "), "\n\n")
      cat("RATIONALE:\n", rationale, "\n\n")
      
      if (file.exists("STEP_1_Family_Selection/results/dataset_all/phase1_selection_table.csv")) {
        selection_table <- fread("STEP_1_Family_Selection/results/dataset_all/phase1_selection_table.csv")
        cat("SELECTION FREQUENCY:\n")
        print(selection_table)
        cat("\n")
      }
      
      pause_for_review(
        paste0("Review Step 1 combined results:\n",
               "  - STEP_1_Family_Selection/results/dataset_all/phase1_summary.txt\n",
               "  - STEP_1_Family_Selection/results/dataset_all/phase1_*.pdf\n",
               "  - Individual dataset results in dataset_1/, dataset_2/, dataset_3/\n\n",
               "If results look good, we'll proceed to Step 2 (copula sensitivity analyses)."),
        "Step 1 Complete"
      )
    } else {
      cat("WARNING: Step 1 decision file not found.\n")
      cat("Later steps may not have copula family information.\n\n")
    }
  } # End of: if (!is.null(step1_combined) && nrow(step1_combined) > 0)
} # End of: if (should_run_step(1))

# Combine STEP 2 results (if applicable)
if (should_run_step(2) && length(ALL_DATASET_RESULTS$step2) > 0) {
  cat("Combining STEP 2 results from", length(ALL_DATASET_RESULTS$step2), "datasets...\n")
  step2_combined <- rbindlist(ALL_DATASET_RESULTS$step2, fill = TRUE)
  output_file <- "STEP_2_Copula_Sensitivity_Analyses/results/sensitivity_analyses_all_datasets.csv"
  dir.create("STEP_2_Copula_Sensitivity_Analyses/results", showWarnings = FALSE, recursive = TRUE)
  fwrite(step2_combined, output_file)
  cat("✓ Combined STEP 2 results saved to:", output_file, "\n\n")
}

# Combine STEP 3 results (if applicable)
if (should_run_step(3) && length(ALL_DATASET_RESULTS$step3) > 0) {
  cat("Combining STEP 3 results from", length(ALL_DATASET_RESULTS$step3), "datasets...\n")
  step3_combined <- rbindlist(ALL_DATASET_RESULTS$step3, fill = TRUE)
  output_file <- "STEP_3_Application_Implementation/results/exp5_transformation_validation_all_datasets.csv"
  dir.create("STEP_3_Application_Implementation/results", showWarnings = FALSE, recursive = TRUE)
  fwrite(step3_combined, output_file)
  cat("✓ Combined STEP 3 results saved to:", output_file, "\n\n")
}

# Combine STEP 4 results (if applicable)
if (should_run_step(4) && length(ALL_DATASET_RESULTS$step4) > 0) {
  cat("Combining STEP 4 results from", length(ALL_DATASET_RESULTS$step4), "datasets...\n")
  step4_combined <- rbindlist(ALL_DATASET_RESULTS$step4, fill = TRUE)
  output_file <- "STEP_4_Deep_Dive_Reporting/results/deep_dive_all_datasets.csv"
  dir.create("STEP_4_Deep_Dive_Reporting/results", showWarnings = FALSE, recursive = TRUE)
  fwrite(step4_combined, output_file)
  cat("✓ Combined STEP 4 results saved to:", output_file, "\n\n")
}

cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

###############################################################################
# ALL DATASETS COMPLETE
###############################################################################

cat("\n")
cat("====================================================================\n")
cat("MASTER ANALYSIS COMPLETE\n")
cat("====================================================================\n\n")

cat("Datasets analyzed:", length(datasets_to_analyze), "\n")
cat("  ", paste(datasets_to_analyze, collapse = "\n   "), "\n\n", sep="")

cat("Execution Summary:\n")
cat("-----------------\n")
cat("  Steps run:", ifelse(is.null(STEPS_TO_RUN), "ALL", paste(STEPS_TO_RUN, collapse = ", ")), "\n")
cat("  Batch mode:", BATCH_MODE, "\n")
cat("  Log file:", LOG_FILE, "\n\n")

cat("Output Locations:\n")
cat("-----------------\n")
if (should_run_step(1)) cat("  Step 1: STEP_1_Family_Selection/results/\n")
if (should_run_step(2)) cat("  Step 2: STEP_2_Copula_Sensitivity_Analyses/results/ (CORE)\n")
if (should_run_step(3)) cat("  Step 3: STEP_3_Application_Implementation/results/\n")
if (should_run_step(4)) cat("  Step 4: STEP_4_Deep_Dive_Reporting/results/\n")
cat("\n")

cat("Next Steps:\n")
cat("-----------\n")
cat("1. Review results in each STEP_*/results/ directory\n")
cat("2. Consult METHODOLOGY_OVERVIEW.md for paper integration guidance\n")
cat("3. Use STEP_*/README.md files to understand each analysis\n")
cat("4. Generate final paper figures and tables from results\n\n")

cat("For paper draft, see:\n")
cat("  ~/Research/Papers/Betebenner_Braun/Paper_1/A_Sklar_Theoretic_Extension_of_TAMP.tex\n\n")

# Close log
sink()

cat("====================================================================\n")
cat("Master analysis log saved to:", LOG_FILE, "\n")
cat("====================================================================\n\n")
