############################################################################
###
### STEP 3: Growth Regime Inference — Longitudinal Inference w/o LD
###
### Master runner script. Can be sourced from master_analysis.R or
### executed standalone.
###
### Phases:
###   A. Single-condition deep validation (showcase)
###   B. Systematic validation across conditions and subgroups
###   C. Publication panels and manifest export
###
### Usage:
###   # From project root
###   source("STEP_3_LIwLD/run_step3.R")
###
###   # Or via master pipeline
###   STEPS_TO_RUN <- 3
###   source("master_analysis.R")
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("STEP 3: GROWTH REGIME INFERENCE (LIwLD)\n")
cat("Longitudinal Inference without Longitudinal Data\n")
cat("====================================================================\n\n")

step3_start_time <- Sys.time()

############################################################################
### 0. SETUP: Paths, packages, functions
############################################################################

# Detect working directory and set paths
if (grepl("STEP_3_LIwLD$", getwd())) {
  STEP3_ROOT <- getwd()
  PROJECT_ROOT <- dirname(STEP3_ROOT)
} else {
  PROJECT_ROOT <- getwd()
  STEP3_ROOT <- file.path(PROJECT_ROOT, "STEP_3_LIwLD")
}

cat("Project root:", PROJECT_ROOT, "\n")
cat("STEP 3 root: ", STEP3_ROOT, "\n\n")

# Required packages
require(data.table)
require(copula)
require(jsonlite)
require(ggplot2)
require(wesanderson)
require(patchwork)

# Source shared functions
source(file.path(PROJECT_ROOT, "functions/sgpc_engine.R"))
source(file.path(PROJECT_ROOT, "functions/longitudinal_pairs.R"))
source(file.path(PROJECT_ROOT, "functions/export_plot_utils.R"))

# Source STEP 2 helpers (Phase 1 data loader)
source(file.path(PROJECT_ROOT, "STEP_2_SGPc_Sensitivity/phase1_data_loader.R"))

# Source STEP 3 functions
source(file.path(STEP3_ROOT, "functions/reference_marginals.R"))
source(file.path(STEP3_ROOT, "functions/copula_kernel_cache.R"))
source(file.path(STEP3_ROOT, "functions/regime_families.R"))
source(file.path(STEP3_ROOT, "functions/predict_v_cdf.R"))
source(file.path(STEP3_ROOT, "functions/distance_metrics.R"))
source(file.path(STEP3_ROOT, "functions/optimize_regime.R"))
source(file.path(STEP3_ROOT, "functions/bootstrap_uncertainty.R"))
source(file.path(STEP3_ROOT, "functions/step3_publication_style.R"))
source(file.path(STEP3_ROOT, "functions/diagnostics_plots.R"))
source(file.path(STEP3_ROOT, "functions/bucket_classification.R"))
source(file.path(STEP3_ROOT, "functions/manifest_export.R"))
source(file.path(STEP3_ROOT, "functions/export_phase_a_figure_data.R"))
source(file.path(STEP3_ROOT, "functions/validate_output_contract.R"))

# Load configuration
source(file.path(STEP3_ROOT, "config_step3.R"))

# Load dataset configurations (from project root)
source(file.path(PROJECT_ROOT, "dataset_configs.R"))

# Create results directory
RESULTS_DIR <- file.path(STEP3_ROOT, "results")
if (!dir.exists(RESULTS_DIR)) dir.create(RESULTS_DIR, recursive = TRUE)

VIZ_DIR <- file.path(RESULTS_DIR, "visualizations")
if (!dir.exists(VIZ_DIR)) dir.create(VIZ_DIR, recursive = TRUE)

# Set seed
set.seed(STEP3_CONFIG$seed)

# Export run metadata
export_run_metadata(STEP3_CONFIG, output_dir = RESULTS_DIR,
                    seed = STEP3_CONFIG$seed)

cat("\n--- Setup complete ---\n\n")

############################################################################
### PHASE A: Single-Condition Deep Validation
############################################################################

cat("====================================================================\n")
cat("PHASE A: Single-Condition Deep Validation\n")
cat("====================================================================\n\n")

# Allow override from master_analysis.R or interactive session
if (!exists("STEP3_PHASE_A") || STEP3_PHASE_A) {
  tryCatch({
    source(file.path(STEP3_ROOT, "step3_validation_deep_dive.R"), local = FALSE)
  }, error = function(e) {
    cat("ERROR in Phase A: ", e$message, "\n")
    cat("Continuing to Phase B...\n\n")
  })
} else {
  cat("Phase A skipped (STEP3_PHASE_A = FALSE)\n\n")
}

############################################################################
### PHASE B: Systematic Validation
############################################################################

cat("====================================================================\n")
cat("PHASE B: Systematic Validation\n")
cat("====================================================================\n\n")

if (!exists("STEP3_PHASE_B") || STEP3_PHASE_B) {
  tryCatch({
    source(file.path(STEP3_ROOT, "step3_systematic_validation.R"), local = FALSE)
  }, error = function(e) {
    cat("ERROR in Phase B: ", e$message, "\n")
    cat("Continuing to Phase C...\n\n")
  })
} else {
  cat("Phase B skipped (STEP3_PHASE_B = FALSE)\n\n")
}

############################################################################
### PHASE C: Publication Panels and Manifest
############################################################################

cat("====================================================================\n")
cat("PHASE C: Publication Panels and Manifest Export\n")
cat("====================================================================\n\n")

if (!exists("STEP3_PHASE_C") || STEP3_PHASE_C) {
  tryCatch({
    source(file.path(STEP3_ROOT, "step3_publication_panels.R"), local = FALSE)
  }, error = function(e) {
    cat("ERROR in Phase C: ", e$message, "\n")
  })
} else {
  cat("Phase C skipped (STEP3_PHASE_C = FALSE)\n\n")
}

############################################################################
### SUMMARY
############################################################################

step3_elapsed <- difftime(Sys.time(), step3_start_time, units = "mins")

cat("\n")
cat("====================================================================\n")
cat("STEP 3 COMPLETE\n")
cat("====================================================================\n")
cat("Elapsed time:", round(as.numeric(step3_elapsed), 1), "minutes\n")
cat("Results directory:", RESULTS_DIR, "\n")
cat("====================================================================\n\n")
