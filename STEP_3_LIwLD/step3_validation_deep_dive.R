############################################################################
###
### STEP 3 — Phase A: Deep Validation (Unified Runner)
###
### Handles three modes via the `validation` config section:
###
###   Mode 1 (single target): validation$targets and validation$filter_expr
###     are both NULL. Uses dataset_id / condition_id / subgroup_id from
###     config. Output goes to RESULTS_DIR directly.
###
###   Mode 2 (explicit targets): validation$targets is a data.frame with
###     columns dataset_id, condition_id, subgroup_id. Each target writes
###     to results/deep_dives/{tag}/.
###
###   Mode 3 (Phase B filter): validation$filter_expr is a string expression
###     evaluated against phase_b_systematic_summary.csv. Matching rows
###     become targets. Each writes to results/deep_dives/{tag}/.
###
### mirai daemons are expected to be started by run_step3.R; the global
### `daemons_live` flag is read from the parent environment.
###
############################################################################

cat("--- Phase A: Deep Validation ---\n\n")

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
if (!exists("PROJECT_ROOT", inherits = TRUE)) {
  PROJECT_ROOT <- dirname(STEP3_ROOT)
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
if (!exists("daemons_live", inherits = TRUE)) {
  daemons_live <- FALSE
}

cfg <- STEP3_CONFIG
vcfg <- cfg$validation %||% list()

# --------------------------------------------------------------------------
# Build target list
# --------------------------------------------------------------------------

targets <- NULL

# Mode 2: explicit targets list
if (!is.null(vcfg$targets)) {
  targets <- data.table::as.data.table(vcfg$targets)
  required_cols <- c("dataset_id", "condition_id", "subgroup_id")
  missing <- setdiff(required_cols, names(targets))
  if (length(missing) > 0) {
    stop("validation$targets must have columns: ",
         paste(required_cols, collapse = ", "),
         ". Missing: ", paste(missing, collapse = ", "))
  }
  cat("Mode: explicit target list (", nrow(targets), " targets)\n\n", sep = "")
}

# Mode 3: filter from Phase B summary
if (is.null(targets) && !is.null(vcfg$filter_expr)) {
  phase_b_csv <- file.path(RESULTS_DIR, "phase_b_systematic_summary.csv")
  if (!file.exists(phase_b_csv)) {
    stop("filter_expr is set but Phase B summary not found: ", phase_b_csv,
         "\nRun Phase B first (or sync results).")
  }

  phase_b <- data.table::fread(
    phase_b_csv,
    colClasses = list(character = c("dataset_id", "condition_id",
                                    "subgroup_id", "content_area"))
  )
  if (nrow(phase_b) == 0) stop("phase_b_systematic_summary.csv has no rows.")

  targets <- data.table::copy(phase_b)

  content_areas <- vcfg$content_areas %||% NULL
  if (!is.null(content_areas) && length(content_areas) > 0) {
    targets <- targets[toupper(content_area) %in% toupper(as.character(content_areas))]
  }

  filter_expr <- vcfg$filter_expr
  targets <- tryCatch(
    targets[eval(parse(text = filter_expr))],
    error = function(e) stop("Invalid filter_expr: ", filter_expr, "\n", e$message)
  )

  if (nrow(targets) == 0) stop("No targets matched filter: ", filter_expr)

  keep_cols <- intersect(
    c("dataset_id", "condition_id", "subgroup_id", "year_span",
      "content_area", "n_subgroup", "mean_diff", "median_diff", "wasserstein1"),
    names(targets)
  )
  targets <- unique(targets[, ..keep_cols])
  targets <- targets[order(-abs(mean_diff), -abs(median_diff))]

  max_targets <- as.integer(vcfg$max_targets %||% nrow(targets))
  if (!is.finite(max_targets) || max_targets <= 0) max_targets <- nrow(targets)
  if (nrow(targets) > max_targets) targets <- targets[seq_len(max_targets)]

  cat("Mode: Phase B filter (", filter_expr, ")\n", sep = "")
  cat("Targets matched: ", nrow(targets), "\n\n", sep = "")
}

# Mode 1: single target from config fields
if (is.null(targets)) {
  targets <- data.table::data.table(
    dataset_id   = vcfg$dataset_id %||% "dataset_1",
    condition_id = vcfg$condition_id %||% NA_character_,
    subgroup_id  = vcfg$subgroup_id %||% NA_character_
  )
  cat("Mode: single target (", targets$dataset_id, ")\n\n", sep = "")
}

n_targets <- nrow(targets)
is_multi <- n_targets > 1L

if (is_multi) {
  deep_root <- file.path(RESULTS_DIR, "deep_dives")
  if (!dir.exists(deep_root)) dir.create(deep_root, recursive = TRUE)
  data.table::fwrite(targets, file.path(deep_root, "selected_targets.csv"))
}

cat("Targets: ", n_targets, "\n", sep = "")
cat("mirai:   ", daemons_live, "\n\n", sep = "")

# --------------------------------------------------------------------------
# Run targets
# --------------------------------------------------------------------------

summary_rows <- vector("list", n_targets)

for (i in seq_len(n_targets)) {
  tgt <- targets[i]

  ds_id   <- as.character(tgt$dataset_id)
  cond_id <- if ("condition_id" %in% names(tgt) && !is.na(tgt$condition_id))
               as.character(tgt$condition_id) else NULL
  sg_id   <- if ("subgroup_id" %in% names(tgt) && !is.na(tgt$subgroup_id))
               as.character(tgt$subgroup_id) else NULL

  if (is_multi) {
    target_tag <- paste(ds_id, cond_id %||% "auto", sg_id %||% "auto", sep = "__")
    safe_tag   <- gsub("[^A-Za-z0-9_\\-]", "_", target_tag)
    out_dir    <- file.path(deep_root, safe_tag)
    if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

    cat("--------------------------------------------------------------------\n")
    cat(sprintf("[%d/%d] %s\n", i, n_targets, target_tag))
    cat("--------------------------------------------------------------------\n")
  } else {
    out_dir <- RESULTS_DIR
  }

  t0 <- Sys.time()
  res <- tryCatch(
    run_deep_dive(
      dataset_id   = ds_id,
      condition_id = cond_id,
      subgroup_id  = sg_id,
      output_dir   = out_dir,
      config       = cfg,
      subgroup_col = vcfg$subgroup_col %||% "DISTRICT_NUMBER",
      use_mirai    = daemons_live,
      verbose      = TRUE
    ),
    error = function(e) e
  )
  elapsed_min <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)

  if (inherits(res, "error")) {
    cat("  ERROR:", res$message, "\n\n")
    summary_rows[[i]] <- data.table::data.table(
      dataset_id   = ds_id,
      condition_id = cond_id %||% NA_character_,
      subgroup_id  = sg_id %||% NA_character_,
      status       = "ERROR",
      error_message = res$message,
      duration_minutes = elapsed_min,
      output_dir   = out_dir
    )
    if (is_multi) next else break
  }

  if (is_multi || n_targets == 1L) {
    mean_diff   <- round(res$best_estimate$regime$mean * 100 -
                         mean(res$true_sgpc, na.rm = TRUE), 2)
    median_diff <- round(res$best_estimate$regime$median * 100 -
                         median(res$true_sgpc, na.rm = TRUE), 2)
    summary_rows[[i]] <- data.table::data.table(
      dataset_id   = res$dataset_id,
      condition_id = res$condition_id,
      subgroup_id  = res$subgroup_id,
      n_subgroup   = res$n_subgroup,
      regime_family = res$best_family,
      mean_diff    = mean_diff,
      median_diff  = median_diff,
      wasserstein1 = round(res$best_estimate$all_distances$wasserstein1, 6),
      linkage_ci_ratio_mean   = res$linkage_premium$mean$ci_ratio,
      linkage_ci_ratio_median = res$linkage_premium$median$ci_ratio,
      flag_independence_violation = isTRUE(res$flag_independence_violation),
      bootstrap_n_converged_independent = res$bootstrap$n_converged,
      bootstrap_n_converged_paired      = res$bootstrap_paired$n_converged,
      status       = "OK",
      error_message = NA_character_,
      duration_minutes = elapsed_min,
      output_dir   = out_dir
    )
  }

  if (is_multi) {
    cat("  OK in ", elapsed_min, " minutes\n\n", sep = "")
  }
}

# Keep result accessible for downstream phases / interactive use
if (!inherits(res, "error")) {
  phase_a_results <- res
}

# --------------------------------------------------------------------------
# Write combined summary (multi-target or single)
# --------------------------------------------------------------------------

phase_a_summary <- data.table::rbindlist(summary_rows, fill = TRUE)
if (is_multi && nrow(phase_a_summary) > 0) {
  summary_file <- file.path(deep_root, "deep_dive_summary.csv")
  data.table::fwrite(phase_a_summary, summary_file)
  cat("====================================================================\n")
  cat("Phase A deep dives complete\n")
  cat("====================================================================\n")
  cat("Summary file: ", summary_file, "\n", sep = "")
  cat("Targets run:  ", nrow(phase_a_summary), "\n", sep = "")
  cat("Succeeded:    ", sum(phase_a_summary$status == "OK", na.rm = TRUE), "\n", sep = "")
  cat("Failed:       ", sum(phase_a_summary$status == "ERROR", na.rm = TRUE), "\n", sep = "")
  cat("====================================================================\n\n")
}

cat("--- Phase A complete ---\n\n")
