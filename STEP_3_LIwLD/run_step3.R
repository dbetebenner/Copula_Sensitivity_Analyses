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
source(file.path(STEP3_ROOT, "functions/optimize_regime_stratified.R"))
source(file.path(STEP3_ROOT, "functions/bootstrap_uncertainty.R"))
source(file.path(STEP3_ROOT, "functions/run_deep_dive.R"))
source(file.path(STEP3_ROOT, "functions/step3_publication_style.R"))
source(file.path(STEP3_ROOT, "functions/figure_naming.R"))
source(file.path(STEP3_ROOT, "functions/diagnostics_plots.R"))
source(file.path(STEP3_ROOT, "functions/copula_metric_grid_latex.R"))
source(file.path(STEP3_ROOT, "functions/bucket_classification.R"))
source(file.path(STEP3_ROOT, "functions/build_cluster_pools.R"))
source(file.path(STEP3_ROOT, "functions/manifest_export.R"))
source(file.path(STEP3_ROOT, "functions/churn_bookkeeping.R"))
source(file.path(STEP3_ROOT, "functions/export_phase_a_figure_data.R"))
source(file.path(STEP3_ROOT, "functions/validate_output_contract.R"))

# Load configuration
source(file.path(STEP3_ROOT, "config_step3.R"))

# Apply runtime overrides (set STEP3_CONFIG_OVERRIDES before sourcing this script)
if (exists("STEP3_CONFIG_OVERRIDES") && is.list(STEP3_CONFIG_OVERRIDES)) {
  for (.sec in names(STEP3_CONFIG_OVERRIDES)) {
    if (is.list(STEP3_CONFIG_OVERRIDES[[.sec]]) && is.list(STEP3_CONFIG[[.sec]])) {
      for (.key in names(STEP3_CONFIG_OVERRIDES[[.sec]])) {
        STEP3_CONFIG[[.sec]][[.key]] <- STEP3_CONFIG_OVERRIDES[[.sec]][[.key]]
      }
    } else {
      STEP3_CONFIG[[.sec]] <- STEP3_CONFIG_OVERRIDES[[.sec]]
    }
  }
  rm(.sec, .key)
  cat("Config overrides applied from STEP3_CONFIG_OVERRIDES\n")
}

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

# Runtime methodology snapshot for uncertainty decomposition and reproducibility
unc_method_path <- file.path(RESULTS_DIR, "uncertainty_methodology.md")
unc_lines <- c(
  "# STEP 3 Uncertainty Methodology",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Sampling uncertainty",
  paste0("- resample_scheme: `", STEP3_CONFIG$uncertainty$resample_scheme, "`"),
  paste0("- n_bootstrap: ", STEP3_CONFIG$uncertainty$n_bootstrap),
  paste0("- bootstrap_grid_resolution: ", STEP3_CONFIG$uncertainty$bootstrap_grid_resolution),
  "",
  "## Copula uncertainty",
  paste0("- n_copula_draws: ", STEP3_CONFIG$uncertainty$n_copula_draws),
  paste0("- copula_family: ", STEP3_CONFIG$copula$family),
  paste0("- params_source: ", STEP3_CONFIG$copula$params_source),
  "",
  "## Regime families",
  paste0("- primary_family: ", STEP3_CONFIG$regime$primary_family),
  paste0("- sensitivity_families: ", paste(STEP3_CONFIG$regime$sensitivity_families, collapse = ", ")),
  "",
  "## Assumption diagnostics",
  paste0("- independence test: ", STEP3_CONFIG$assumptions$independence$test),
  paste0("- U bins: ", STEP3_CONFIG$assumptions$independence$u_bins),
  paste0("- alpha: ", STEP3_CONFIG$assumptions$independence$alpha)
)
writeLines(unc_lines, unc_method_path)

cat("\n--- Setup complete ---\n\n")

############################################################################
### MIRAI DAEMON LIFECYCLE (shared across Phase A bootstrap and Phase B)
############################################################################

daemons_live <- FALSE

if (isTRUE(STEP3_CONFIG$validation$use_mirai)) {
  mirai_available <- requireNamespace("mirai", quietly = TRUE)
  if (!mirai_available) {
    cat("WARNING: use_mirai=TRUE but `mirai` package not available; bootstrap will run sequentially.\n\n")
  } else {
    n_cores_total <- parallel::detectCores(logical = TRUE)
    n_workers_cfg <- STEP3_CONFIG$validation$n_workers
    if (!is.null(n_workers_cfg) && is.finite(as.integer(n_workers_cfg)) &&
        as.integer(n_workers_cfg) >= 2L) {
      n_workers <- as.integer(n_workers_cfg)
    } else {
      n_workers <- max(2L, if (n_cores_total <= 48L) n_cores_total - 2L
                           else n_cores_total - 4L)
    }

    cat("Initialising ", n_workers, " mirai daemons (",
        n_cores_total, " CPUs available)...\n", sep = "")

    daemon_ok <- tryCatch({
      mirai::daemons(n = n_workers, output = TRUE, retry = FALSE)
      TRUE
    }, error = function(e) {
      cat("  WARNING: daemon creation failed: ", e$message, "\n")
      FALSE
    })

    if (daemon_ok) {
      STEP3_ROOT_ABS   <- normalizePath(STEP3_ROOT, mustWork = TRUE)
      PROJECT_ROOT_ABS <- normalizePath(PROJECT_ROOT, mustWork = TRUE)

      init_ok <- tryCatch({
        init_push <- mirai::everywhere({
          tryCatch(setwd(proj_root_push), error = function(e) NULL)
          suppressPackageStartupMessages({
            library(data.table)
            library(copula)
          })
          data.table::setDTthreads(1L)
          Sys.setenv(
            OMP_NUM_THREADS        = "1",
            MKL_NUM_THREADS        = "1",
            OPENBLAS_NUM_THREADS   = "1",
            VECLIB_MAXIMUM_THREADS = "1",
            NUMEXPR_NUM_THREADS    = "1"
          )
          for (ff in c(
            file.path(proj_root_push, "functions/sgpc_engine.R"),
            file.path(s3_root_push,   "functions/reference_marginals.R"),
            file.path(s3_root_push,   "functions/copula_kernel_cache.R"),
            file.path(s3_root_push,   "functions/regime_families.R"),
            file.path(s3_root_push,   "functions/predict_v_cdf.R"),
            file.path(s3_root_push,   "functions/distance_metrics.R"),
            file.path(s3_root_push,   "functions/optimize_regime.R"),
            file.path(s3_root_push,   "functions/optimize_regime_stratified.R")
          )) {
            tryCatch(source(ff), error = function(e) {
              cat("[DAEMON", Sys.getpid(), "] ERROR sourcing", ff, ":",
                  conditionMessage(e), "\n")
              stop(e)
            })
          }
          TRUE
        },
        proj_root_push = PROJECT_ROOT_ABS,
        s3_root_push   = STEP3_ROOT_ABS)

        init_vals <- init_push[]
        n_ok <- sum(vapply(init_vals, isTRUE, logical(1)))
        cat("  Daemons initialised: ", n_ok, "/", n_workers, " ready\n", sep = "")
        n_ok == n_workers
      }, error = function(e) {
        cat("  WARNING: daemon init failed: ", e$message, "\n")
        FALSE
      })

      if (isTRUE(init_ok)) {
        daemons_live <- TRUE
      } else {
        cat("  Falling back to sequential bootstrap.\n")
        tryCatch(mirai::daemons(0), error = function(e) NULL)
      }
    }
  }
}

############################################################################
### PHASE A: Deep Validation
############################################################################

cat("====================================================================\n")
cat("PHASE A: Deep Validation\n")
cat("====================================================================\n\n")

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

############################################################################
### CLEANUP: Shut down mirai daemons
############################################################################

if (daemons_live) {
  tryCatch(mirai::daemons(0), error = function(e) NULL)
  daemons_live <- FALSE
  cat("mirai daemons shut down.\n")
}
