############################################################################
###
### STEP 3 — Phase A: Single-Condition Deep Validation (Wrapper)
###
### Backward-compatible entrypoint sourced by run_step3.R.
### The reusable implementation now lives in:
###   STEP_3_LIwLD/functions/run_deep_dive.R
###
############################################################################

cat("--- Phase A: Single-Condition Deep Validation ---\n\n")

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}

if (!exists("STEP3_ROOT", inherits = TRUE)) {
  if (grepl("STEP_3_LIwLD$", getwd())) {
    STEP3_ROOT <- getwd()
  } else {
    STEP3_ROOT <- file.path(getwd(), "STEP_3_LIwLD")
  }
}

run_deep_dive_file <- file.path(STEP3_ROOT, "functions", "run_deep_dive.R")
if (!exists("run_deep_dive", mode = "function")) {
  source(run_deep_dive_file)
}

cfg <- STEP3_CONFIG
use_mirai <- isTRUE(cfg$validation$use_mirai)
daemons_started <- FALSE

if (use_mirai) {
  n_cores_total <- parallel::detectCores(logical = TRUE)
  n_workers_cfg <- cfg$validation$n_workers
  if (!is.null(n_workers_cfg) && is.finite(as.integer(n_workers_cfg)) &&
      as.integer(n_workers_cfg) >= 2L) {
    n_workers <- as.integer(n_workers_cfg)
  } else {
    n_workers <- max(2L, if (n_cores_total <= 48L) n_cores_total - 2L
                         else n_cores_total - 4L)
  }

  cat("Initialising ", n_workers, " mirai daemons for Phase A bootstrap...\n", sep = "")
  daemon_ok <- tryCatch({
    mirai::daemons(n = n_workers, output = TRUE, retry = FALSE)
    TRUE
  }, error = function(e) {
    cat("  WARNING: daemon creation failed: ", e$message, "\n")
    FALSE
  })

  if (daemon_ok) {
    STEP3_ROOT_ABS <- normalizePath(STEP3_ROOT, mustWork = TRUE)
    PROJECT_ROOT_ABS <- normalizePath(
      if (exists("PROJECT_ROOT", inherits = TRUE))
        get("PROJECT_ROOT", inherits = TRUE)
      else dirname(STEP3_ROOT_ABS),
      mustWork = TRUE)

    init_ok <- tryCatch({
      init_push <- mirai::everywhere({
        tryCatch(setwd(proj_root_push), error = function(e) NULL)
        suppressPackageStartupMessages({
          library(data.table)
          library(copula)
        })
        data.table::setDTthreads(1L)
        Sys.setenv(
          OMP_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
          OPENBLAS_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1",
          NUMEXPR_NUM_THREADS = "1"
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
            cat("[DAEMON", Sys.getpid(), "] ERROR sourcing", ff, ":", conditionMessage(e), "\n")
            stop(e)
          })
        }
        TRUE
      },
      proj_root_push = PROJECT_ROOT_ABS,
      s3_root_push   = STEP3_ROOT_ABS)

      init_vals <- init_push[]
      all(vapply(init_vals, isTRUE, logical(1)))
    }, error = function(e) {
      cat("  WARNING: daemon init failed: ", e$message, "\n")
      FALSE
    })

    if (isTRUE(init_ok)) {
      daemons_started <- TRUE
      cat("  Daemons ready.\n")
    } else {
      cat("  Falling back to sequential bootstrap.\n")
      tryCatch(mirai::daemons(0), error = function(e) NULL)
    }
  }
}

phase_a_results <- run_deep_dive(
  dataset_id = cfg$validation$dataset_id %||% NULL,
  condition_id = cfg$validation$condition_id %||% NULL,
  subgroup_id = cfg$validation$subgroup_id %||% NULL,
  output_dir = RESULTS_DIR,
  config = cfg,
  subgroup_col = cfg$validation$subgroup_col %||% NULL,
  use_mirai = daemons_started,
  verbose = TRUE
)

if (daemons_started) {
  tryCatch(mirai::daemons(0), error = function(e) NULL)
  cat("mirai daemons shut down.\n")
}

cat("--- Phase A wrapper complete ---\n\n")
