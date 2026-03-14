############################################################################
###
### STEP 3 — Multi-Target Phase A Deep Dives
###
### Runs the Phase A pipeline for a filtered set of outlier targets from
### phase_b_systematic_summary.csv, writing each deep dive to its own folder.
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("PHASE A (MULTI): Outlier Deep-Dive Runner\n")
cat("====================================================================\n\n")

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}

# Resolve roots for standalone use
if (!exists("STEP3_ROOT", inherits = TRUE)) {
  if (grepl("STEP_3_LIwLD$", getwd())) {
    STEP3_ROOT <- normalizePath(getwd(), mustWork = TRUE)
  } else {
    STEP3_ROOT <- normalizePath(file.path(getwd(), "STEP_3_LIwLD"), mustWork = TRUE)
  }
}
if (!exists("PROJECT_ROOT", inherits = TRUE)) {
  PROJECT_ROOT <- normalizePath(dirname(STEP3_ROOT), mustWork = TRUE)
}

if (!exists("STEP3_CONFIG", inherits = TRUE)) {
  source(file.path(STEP3_ROOT, "config_step3.R"))
}
if (!exists("DATASETS", inherits = TRUE)) {
  source(file.path(PROJECT_ROOT, "dataset_configs.R"))
}
if (!exists("run_deep_dive", mode = "function")) {
  source(file.path(STEP3_ROOT, "functions", "run_deep_dive.R"))
}

if (!exists("RESULTS_DIR", inherits = TRUE)) {
  RESULTS_DIR <- file.path(STEP3_ROOT, "results")
}

cfg <- STEP3_CONFIG
md_cfg <- cfg$multi_deep_dive %||% list()

phase_b_csv <- file.path(RESULTS_DIR, "phase_b_systematic_summary.csv")
if (!file.exists(phase_b_csv)) {
  stop("Phase B summary file not found: ", phase_b_csv,
       "\nRun Phase B first (or sync results) before running multi deep dives.")
}

phase_b <- data.table::fread(
  phase_b_csv,
  colClasses = list(character = c("dataset_id", "condition_id", "subgroup_id", "content_area"))
)
if (nrow(phase_b) == 0) {
  stop("phase_b_systematic_summary.csv has no rows.")
}

targets <- data.table::copy(phase_b)
content_areas <- md_cfg$content_areas %||% NULL
if (!is.null(content_areas) && length(content_areas) > 0) {
  targets <- targets[toupper(content_area) %in% toupper(as.character(content_areas))]
}

filter_expr <- md_cfg$filter_expr %||% "abs(mean_diff) > 8"
targets <- tryCatch(
  targets[eval(parse(text = filter_expr))],
  error = function(e) stop("Invalid multi_deep_dive$filter_expr: ", filter_expr, "\n", e$message)
)

if (nrow(targets) == 0) {
  stop("No targets matched filter: ", filter_expr)
}

targets <- unique(targets[, .(
  dataset_id, condition_id, subgroup_id, year_span, content_area,
  n_subgroup, mean_diff, median_diff, wasserstein1
)])
targets <- targets[order(-abs(mean_diff), -abs(median_diff), -n_subgroup)]

max_targets <- as.integer(md_cfg$max_targets %||% nrow(targets))
if (!is.finite(max_targets) || is.na(max_targets) || max_targets <= 0) {
  max_targets <- nrow(targets)
}
if (nrow(targets) > max_targets) {
  targets <- targets[seq_len(max_targets)]
}

deep_root <- file.path(RESULTS_DIR, "deep_dives")
if (!dir.exists(deep_root)) dir.create(deep_root, recursive = TRUE)
data.table::fwrite(targets, file.path(deep_root, "selected_targets.csv"))

# --------------------------------------------------------------------------
# mirai daemon lifecycle (mirrors Phase B in step3_systematic_validation.R)
# --------------------------------------------------------------------------
use_mirai <- isTRUE(md_cfg$use_mirai)
daemons_live <- FALSE

if (use_mirai) {
  n_cores_total <- parallel::detectCores(logical = TRUE)
  n_workers_cfg <- md_cfg$n_workers
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
    init_ok <- tryCatch({
      STEP3_ROOT_ABS <- normalizePath(STEP3_ROOT, mustWork = TRUE)
      PROJECT_ROOT_ABS <- normalizePath(
        if (exists("PROJECT_ROOT", inherits = TRUE))
          get("PROJECT_ROOT", inherits = TRUE)
        else dirname(STEP3_ROOT_ABS),
        mustWork = TRUE)

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
            cat("[DAEMON", Sys.getpid(), "] ERROR sourcing", ff, ":", conditionMessage(e), "\n")
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

    daemons_live <- isTRUE(init_ok)
    if (!daemons_live) {
      cat("  Falling back to sequential bootstrap.\n")
      tryCatch(mirai::daemons(0), error = function(e) NULL)
    }
  }
}

on.exit({
  if (daemons_live) {
    tryCatch(mirai::daemons(0), error = function(e) NULL)
    cat("mirai daemons shut down.\n")
  }
}, add = TRUE)

cat("Target filter: ", filter_expr, "\n", sep = "")
cat("Targets selected: ", nrow(targets), "\n", sep = "")
cat("mirai parallelisation: ", daemons_live, "\n\n", sep = "")

summary_rows <- vector("list", nrow(targets))

for (i in seq_len(nrow(targets))) {
  tgt <- targets[i]
  target_tag <- paste(tgt$dataset_id, tgt$condition_id, tgt$subgroup_id, sep = "__")
  safe_tag <- gsub("[^A-Za-z0-9_\\-]", "_", target_tag)
  out_dir <- file.path(deep_root, safe_tag)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  cat("--------------------------------------------------------------------\n")
  cat(sprintf("[%d/%d] %s\n", i, nrow(targets), target_tag))
  cat("--------------------------------------------------------------------\n")

  t0 <- Sys.time()
  res <- tryCatch(
    run_deep_dive(
      dataset_id = tgt$dataset_id,
      condition_id = tgt$condition_id,
      subgroup_id = tgt$subgroup_id,
      output_dir = out_dir,
      config = cfg,
      subgroup_col = cfg$validation$subgroup_col %||% "DISTRICT_NUMBER",
      use_mirai = daemons_live,
      verbose = TRUE
    ),
    error = function(e) e
  )
  elapsed_min <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)

  if (inherits(res, "error")) {
    cat("  ERROR:", res$message, "\n\n")
    summary_rows[[i]] <- data.table::data.table(
      dataset_id = tgt$dataset_id,
      condition_id = tgt$condition_id,
      subgroup_id = tgt$subgroup_id,
      status = "ERROR",
      error_message = res$message,
      duration_minutes = elapsed_min,
      output_dir = out_dir
    )
    next
  }

  mean_diff <- round(res$best_estimate$regime$mean * 100 - mean(res$true_sgpc, na.rm = TRUE), 2)
  median_diff <- round(res$best_estimate$regime$median * 100 - median(res$true_sgpc, na.rm = TRUE), 2)
  summary_rows[[i]] <- data.table::data.table(
    dataset_id = res$dataset_id,
    condition_id = res$condition_id,
    subgroup_id = res$subgroup_id,
    n_subgroup = res$n_subgroup,
    regime_family = res$best_family,
    mean_diff = mean_diff,
    median_diff = median_diff,
    wasserstein1 = round(res$best_estimate$all_distances$wasserstein1, 6),
    linkage_ci_ratio_mean = res$linkage_premium$mean$ci_ratio,
    linkage_ci_ratio_median = res$linkage_premium$median$ci_ratio,
    flag_independence_violation = isTRUE(res$flag_independence_violation),
    bootstrap_n_converged_independent = res$bootstrap$n_converged,
    bootstrap_n_converged_paired = res$bootstrap_paired$n_converged,
    status = "OK",
    error_message = NA_character_,
    duration_minutes = elapsed_min,
    output_dir = out_dir
  )
  cat("  OK in ", elapsed_min, " minutes\n\n", sep = "")
}

multi_summary <- data.table::rbindlist(summary_rows, fill = TRUE)
summary_file <- file.path(deep_root, "multi_deep_dive_summary.csv")
data.table::fwrite(multi_summary, summary_file)

cat("====================================================================\n")
cat("Multi-target deep dives complete\n")
cat("====================================================================\n")
cat("Summary file:", summary_file, "\n")
cat("Targets run:", nrow(multi_summary), "\n")
cat("Succeeded:", sum(multi_summary$status == "OK", na.rm = TRUE), "\n")
cat("Failed:", sum(multi_summary$status == "ERROR", na.rm = TRUE), "\n")
cat("====================================================================\n\n")
