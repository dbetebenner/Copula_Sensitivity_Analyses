############################################################################
###
### STEP 3 — Phase B Single Deep-Dive
###
### Runs Phase B's systematic validation logic on a single target
### (dataset, condition, subgroup), combining:
###
###   1. Phase A diagnostic panels (via run_deep_dive())
###   2. Phase B-style N-operating curve (via run_precision_sweep())
###      with both paired and independent linkage fractions
###
### The result is a comprehensive deep-dive that uses the NAEP/TIMSS
### population-sampling framing (subsampling without replacement from
### the condition pool) rather than Phase A's bootstrap (resampling
### with replacement from the observed subgroup).
###
### Activated by setting STEP3_PHASE_B_DEEP_DIVE <- TRUE and
### configuring STEP3_CONFIG$systematic$single_target.
###
### Output directory: results/deep_dives/{condition_id}__{subgroup_id}/phase_b_deep_dive/
###
### Author: dataimago
### Date: March 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("PHASE B DEEP-DIVE: Single-Target Systematic Validation\n")
cat("====================================================================\n\n")

phaseb_dd_start <- Sys.time()

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}

############################################################################
### 1. Validate single_target configuration
############################################################################

st <- STEP3_CONFIG$systematic$single_target

if (
  is.null(st) ||
    is.null(st$dataset_id) ||
    is.null(st$condition_id) ||
    is.null(st$subgroup_id)
) {
  stop(
    "Phase B deep-dive requires all three fields in STEP3_CONFIG$systematic$single_target:\n",
    "  dataset_id, condition_id, subgroup_id\n",
    "  Current values: dataset_id=",
    st$dataset_id %||% "NULL",
    ", condition_id=",
    st$condition_id %||% "NULL",
    ", subgroup_id=",
    st$subgroup_id %||% "NULL"
  )
}

target_dataset <- st$dataset_id
target_condition <- st$condition_id
target_subgroup <- st$subgroup_id
pool_tag <- paste0(target_condition, "__", target_subgroup)

cat("Target:\n")
cat("  Dataset:   ", target_dataset, "\n")
cat("  Condition: ", target_condition, "\n")
cat("  Subgroup:  ", target_subgroup, "\n")
cat("  Pool tag:  ", pool_tag, "\n\n")

############################################################################
### 2. Set up output directory
############################################################################

dd_output_dir <- file.path(
  RESULTS_DIR,
  "deep_dives",
  pool_tag,
  "phase_b_deep_dive"
)
if (!dir.exists(dd_output_dir)) {
  dir.create(dd_output_dir, recursive = TRUE)
}
cat("Output directory: ", dd_output_dir, "\n\n")

############################################################################
### 3. Run Phase A diagnostics via run_deep_dive()
###    This provides the full diagnostic panel set (CDF, regime density,
###    independence, bootstrap, linkage decomposition, copula comparison).
############################################################################

cat("--- Stage 1: Phase A diagnostic panels ---\n\n")

phase_a_cfg <- STEP3_CONFIG
phase_a_cfg$validation$precision_sweep <- TRUE
phase_a_cfg$validation$sweep_n_buckets <- STEP3_CONFIG$validation$sweep_n_buckets %||%
  STEP3_CONFIG$systematic$n_buckets
phase_a_cfg$validation$sweep_reps <- STEP3_CONFIG$validation$sweep_reps %||%
  200L

phase_a_results <- run_deep_dive(
  dataset_id = target_dataset,
  condition_id = target_condition,
  subgroup_id = target_subgroup,
  output_dir = dd_output_dir,
  config = phase_a_cfg,
  use_mirai = isTRUE(daemons_live),
  verbose = TRUE
)

cat("\n--- Stage 1 complete ---\n\n")

############################################################################
### 4. Run Phase B-style precision sweep on full condition pool
###    Uses run_precision_sweep() — self-contained subsampling without
###    replacement, both paired and independent.
############################################################################

cat("--- Stage 2: Phase B N-operating curve (subsampling) ---\n\n")

if (
  is.null(phase_a_results$precision_sweep) ||
    nrow(phase_a_results$precision_sweep$replicates) == 0
) {
  cat(
    "  Precision sweep was not produced by run_deep_dive() — running standalone.\n"
  )

  if (!exists("run_precision_sweep", mode = "function")) {
    stop(
      "run_precision_sweep() not loaded. Source functions/precision_sweep.R first."
    )
  }

  # Reconstruct inputs from phase_a_results
  refs <- build_pairs_reference_from_results <- NULL
  cat(
    "  WARNING: Standalone sweep requires pairs data not stored in phase_a_results.\n"
  )
  cat(
    "  Enable cfg$validation$precision_sweep=TRUE to include sweep in run_deep_dive().\n\n"
  )
} else {
  cat("  Precision sweep already completed within run_deep_dive() (A.9).\n")
  cat("  Replicates: ", nrow(phase_a_results$precision_sweep$replicates), "\n")
  cat("  Pool N:     ", phase_a_results$precision_sweep$n_pool, "\n\n")
}

############################################################################
### 5. Generate Phase B-specific summary outputs
############################################################################

cat("--- Stage 3: Generating Phase B deep-dive summary ---\n\n")

phaseb_dd_summary <- list(
  target = list(
    dataset_id = target_dataset,
    condition_id = target_condition,
    subgroup_id = target_subgroup,
    pool_tag = pool_tag
  ),
  phase_a = list(
    condition_meta = phase_a_results$condition_meta,
    n_subgroup = phase_a_results$n_subgroup,
    best_family = phase_a_results$best_family,
    copula_mode = phase_a_results$copula_mode,
    primary_copula_label = phase_a_results$primary_copula_label,
    median_sgpc_inferred = round(
      phase_a_results$best_estimate$regime$median * 100,
      2
    ),
    mean_sgpc_inferred = round(
      phase_a_results$best_estimate$regime$mean * 100,
      2
    ),
    median_sgpc_true = round(
      median(phase_a_results$true_sgpc, na.rm = TRUE),
      2
    ),
    mean_sgpc_true = round(mean(phase_a_results$true_sgpc, na.rm = TRUE), 2),
    bootstrap_linkage_premium = phase_a_results$linkage_premium
  ),
  precision_sweep = if (!is.null(phase_a_results$precision_sweep)) {
    list(
      n_pool = phase_a_results$precision_sweep$n_pool,
      n_replicates = nrow(phase_a_results$precision_sweep$replicates),
      summary = phase_a_results$precision_sweep$summary
    )
  } else {
    NULL
  },
  sampling_context = list(
    bootstrap_frame = "State census / superpopulation — resampling with replacement from observed N",
    subsample_frame = "NAEP/TIMSS population sampling — subsampling without replacement from condition pool"
  ),
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

# Write JSON manifest
manifest_path <- file.path(dd_output_dir, "phase_b_deep_dive_manifest.json")
jsonlite::write_json(
  phaseb_dd_summary,
  manifest_path,
  auto_unbox = TRUE,
  pretty = TRUE
)
cat("  Saved: ", manifest_path, "\n")

# Write markdown summary
md_lines <- c(
  paste0("# Phase B Deep-Dive: ", pool_tag),
  "",
  paste0("Generated: ", phaseb_dd_summary$timestamp),
  "",
  "## Target",
  paste0("- Dataset: ", target_dataset),
  paste0("- Condition: ", target_condition),
  paste0("- Subgroup: ", target_subgroup),
  paste0("- Subgroup N: ", phase_a_results$n_subgroup),
  "",
  "## Phase A Diagnostics (Bootstrap — State Census Frame)",
  paste0("- Regime family: ", phase_a_results$best_family),
  paste0("- Copula: ", phase_a_results$primary_copula_label),
  paste0(
    "- Inferred median SGPc: ",
    round(phase_a_results$best_estimate$regime$median * 100, 1)
  ),
  paste0(
    "- True median SGPc: ",
    round(median(phase_a_results$true_sgpc, na.rm = TRUE), 1)
  ),
  paste0(
    "- Inferred mean SGPc: ",
    round(phase_a_results$best_estimate$regime$mean * 100, 1)
  ),
  paste0(
    "- True mean SGPc: ",
    round(mean(phase_a_results$true_sgpc, na.rm = TRUE), 1)
  ),
  "",
  "### Bootstrap Uncertainty (with replacement, N = subgroup)",
  paste0(
    "- Independent 95% CI width (median): ",
    phase_a_results$linkage_premium$median$ci_width_independent
  ),
  paste0(
    "- Paired 95% CI width (median): ",
    phase_a_results$linkage_premium$median$ci_width_paired
  ),
  paste0(
    "- Linkage premium (median): ",
    phase_a_results$linkage_premium$median$ci_ratio,
    "x"
  ),
  paste0(
    "- Independent 95% CI width (mean): ",
    phase_a_results$linkage_premium$mean$ci_width_independent
  ),
  paste0(
    "- Paired 95% CI width (mean): ",
    phase_a_results$linkage_premium$mean$ci_width_paired
  ),
  paste0(
    "- Linkage premium (mean): ",
    phase_a_results$linkage_premium$mean$ci_ratio,
    "x"
  )
)

if (
  !is.null(phase_a_results$precision_sweep) &&
    nrow(phase_a_results$precision_sweep$summary) > 0
) {
  sweep_s <- phase_a_results$precision_sweep$summary
  md_lines <- c(
    md_lines,
    "",
    "## Precision Sweep (Subsampling — NAEP/TIMSS Frame)",
    paste0("- Pool N: ", phase_a_results$precision_sweep$n_pool),
    paste0("- Replicates: ", nrow(phase_a_results$precision_sweep$replicates)),
    "",
    "### Summary by N-bucket and Linkage Fraction",
    "",
    "| N | Linkage | Mode | Mean CI Width | Median CI Width | Mean MAE | Median MAE |",
    "|----|---------|------|---------------|-----------------|----------|------------|"
  )
  for (i in seq_len(nrow(sweep_s))) {
    r <- sweep_s[i]
    md_lines <- c(
      md_lines,
      sprintf(
        "| %s | %.1f | %s | %.2f | %.2f | %.2f | %.2f |",
        format(r$n_bucket, big.mark = ","),
        r$linkage_fraction,
        r$sampling_mode,
        r$mean_ci_width_95,
        r$median_ci_width_95,
        r$mean_mae,
        r$median_mae
      )
    )
  }
}

writeLines(md_lines, file.path(dd_output_dir, "phase_b_deep_dive_summary.md"))
cat("  Saved: phase_b_deep_dive_summary.md\n")

############################################################################
### 6. Summary
############################################################################

phaseb_dd_elapsed <- as.numeric(difftime(
  Sys.time(),
  phaseb_dd_start,
  units = "mins"
))
cat("\n")
cat("====================================================================\n")
cat("PHASE B DEEP-DIVE COMPLETE\n")
cat("====================================================================\n")
cat("Target: ", pool_tag, "\n")
cat("Elapsed: ", round(phaseb_dd_elapsed, 1), " minutes\n")
cat("Output: ", dd_output_dir, "\n")
cat("====================================================================\n\n")
