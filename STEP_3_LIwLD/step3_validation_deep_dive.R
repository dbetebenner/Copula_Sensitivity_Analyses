############################################################################
###
### STEP 3 — Phase A: Single-Condition Deep Validation
###
### The showcase. Picks one condition and one large district, then walks
### through the complete growth-regime inference pipeline:
###
###   1. Extract longitudinal pairs  ->  "true" SGPc distribution
###   2. "Forget" the pairing        ->  independent prior/current samples
###   3. Build reference marginals   ->  state-level ECDFs
###   4. Build transition kernel     ->  F_0(v|u) from baseline copula
###   5. Estimate growth regime      ->  H_theta by minimum-distance
###   6. Compare inferred vs actual  ->  the key validation
###   7. Diagnostics + uncertainty   ->  plots + bootstrap
###
### Sourced by run_step3.R (Phase A) or can be run standalone.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIw_LD)
###
############################################################################

cat("--- Phase A: Single-Condition Deep Validation ---\n\n")

############################################################################
### A.0  Resolve configuration
############################################################################

cfg <- STEP3_CONFIG

# Determine dataset and condition
dataset_id <- cfg$validation$dataset_id
cat("Dataset:", dataset_id, "\n")

# Load dataset configuration
ds_config <- DATASETS[[dataset_id]]
if (is.null(ds_config)) stop("Dataset '", dataset_id, "' not found in DATASETS")

# Load state data (the full longitudinal dataset)
data_path <- ds_config$local_path
if (!file.exists(data_path)) {
  data_path <- ds_config$ec2_path
}
cat("Loading state data from:", data_path, "\n")
load(data_path)

# The loaded object name varies by dataset; find the data.table
state_data_name <- ds_config$rdata_object_name
if (exists(state_data_name)) {
  STATE_DATA <- get(state_data_name)
} else {
  # Fallback: find the largest data.table in the environment
  dt_names <- ls()[sapply(ls(), function(x) is.data.table(get(x)))]
  if (length(dt_names) == 0) stop("No data.table found after loading ", data_path)
  STATE_DATA <- get(dt_names[which.max(sapply(dt_names, function(x) nrow(get(x))))])
}
cat("State data loaded:", format(nrow(STATE_DATA), big.mark = ","), "rows\n")

# Select condition (auto or specified)
if (is.null(cfg$validation$condition_id)) {
  # Auto-select: pick a 1-year span condition with large n
  conditions <- get_phase1_conditions(dataset_id)
  if (length(conditions) == 0) stop("No Phase 1 conditions found for ", dataset_id)

  # Parse to find 1-year spans
  cond_meta <- lapply(conditions, parse_condition_id)
  spans <- sapply(cond_meta, `[[`, "year_span")
  one_year <- conditions[spans == 1]

  if (length(one_year) > 0) {
    condition_id <- one_year[1]  # Take first 1-year condition
  } else {
    condition_id <- conditions[1]  # Fallback to first available
  }
} else {
  condition_id <- cfg$validation$condition_id
}

cat("Condition:", condition_id, "\n")
cond <- parse_condition_id(condition_id)
cat("  Year:", cond$year_prior, "->", cond$year_current, "\n")
cat("  Grades:", cond$grade_prior, "->", cond$grade_current, "\n")
cat("  Content:", cond$content_area, "\n\n")


############################################################################
### A.1  Extract Longitudinal Pairs (Ground Truth)
############################################################################

cat("A.1  Extracting longitudinal pairs (ground truth)...\n")

pairs <- create_longitudinal_pairs(
  state_data    = STATE_DATA,
  grade_prior   = cond$grade_prior,
  grade_current = cond$grade_current,
  year_current  = cond$year_current,
  content_area  = cond$content_area
)

cat("  Total longitudinal pairs:", format(nrow(pairs), big.mark = ","), "\n")

# Identify subgroups (districts or schools)
sg_col <- cfg$validation$subgroup_col
if (!sg_col %in% names(pairs)) {
  cat("  WARNING: Column '", sg_col, "' not found. Trying SCHOOL_NUMBER.\n")
  sg_col <- "SCHOOL_NUMBER"
}

if (sg_col %in% names(pairs)) {
  sg_sizes <- pairs[, .N, by = sg_col][order(-N)]
  cat("  Available subgroups (", sg_col, "):", nrow(sg_sizes), "\n")
  cat("  Largest subgroup: n =", sg_sizes$N[1], "\n")

  # Pick the largest subgroup meeting the target
  target_n <- cfg$validation$target_subgroup_n
  big_enough <- sg_sizes[N >= cfg$validation$min_subgroup_n]
  if (nrow(big_enough) == 0) {
    cat("  WARNING: No subgroups meet min_n =", cfg$validation$min_subgroup_n, "\n")
    cat("  Using entire condition as one subgroup.\n")
    subgroup_id <- "ALL"
    pairs_sg <- pairs
  } else {
    # Pick the one closest to target_n (from above)
    best_idx <- which.min(abs(big_enough$N - target_n))
    subgroup_id <- as.character(big_enough[[sg_col]][best_idx])
    pairs_sg <- pairs[get(sg_col) == subgroup_id]
    cat("  Selected subgroup:", subgroup_id, "(n =", nrow(pairs_sg), ")\n")
  }
} else {
  cat("  No subgroup column available. Using entire condition.\n")
  subgroup_id <- "ALL"
  pairs_sg <- pairs
}

cat("\n")


############################################################################
### A.2  Compute "True" SGPc from Longitudinal Data
############################################################################

cat("A.2  Computing true SGPc distribution from longitudinal data...\n")

# Load the Phase 1 fitted copula for this condition
p1 <- load_phase1_condition(dataset_id, condition_id)

if (is.null(p1$best_fit_copula)) {
  cat("  WARNING: No Phase 1 copula found. Using canonical t-copula.\n")
  canonical <- load_canonical_parameters()
  p1_copula <- create_canonical_copula(cond$year_span, cond$content_area,
                                        canonical$canonical_params)
} else {
  p1_copula <- p1$best_fit_copula
  cat("  Loaded Phase 1 copula:", class(p1_copula)[1], "\n")
}

# Compute pseudo-observations (state-normed ranks) for the full condition
u_full <- rank(pairs$SCALE_SCORE_PRIOR) / (nrow(pairs) + 1)
v_full <- rank(pairs$SCALE_SCORE_CURRENT) / (nrow(pairs) + 1)

# Compute true SGPc for subgroup students using full-condition copula
if (subgroup_id == "ALL") {
  u_sg <- u_full
  v_sg <- v_full
} else {
  sg_idx <- which(pairs[[sg_col]] == subgroup_id)
  u_sg <- u_full[sg_idx]
  v_sg <- v_full[sg_idx]
}

true_sgpc <- sgpc_engine(u_sg, v_sg, p1_copula, scale = "percentile")
cat("  True SGPc distribution for subgroup:\n")
cat("    Mean:", round(mean(true_sgpc, na.rm = TRUE), 1), "\n")
cat("    Median:", round(median(true_sgpc, na.rm = TRUE), 1), "\n")
cat("    SD:", round(sd(true_sgpc, na.rm = TRUE), 1), "\n\n")


############################################################################
### A.3  Build Reference Marginals (State-Level ECDFs)
############################################################################

cat("A.3  Building reference marginals (state-level ECDFs)...\n")

refs <- build_condition_reference(STATE_DATA, cond)
cat("  Prior reference: n =", refs$n_prior, "\n")
cat("  Current reference: n =", refs$n_current, "\n")


############################################################################
### A.4  "Forget" the Pairing — Cross-Sectional Samples
############################################################################

cat("\nA.4  Creating cross-sectional samples (forgetting the pairing)...\n")

# District's prior scores (from the longitudinal pairs, but we only use scores)
prior_scores_sg <- pairs_sg$SCALE_SCORE_PRIOR
current_scores_sg <- pairs_sg$SCALE_SCORE_CURRENT

# Map to reference percentiles
u_cross <- reference_cdf(prior_scores_sg, refs$ref_prior)
v_cross <- reference_cdf(current_scores_sg, refs$ref_current)

cat("  Cross-sectional prior sample:  n =", length(u_cross), "\n")
cat("  Cross-sectional current sample: n =", length(v_cross), "\n")
cat("  Note: These are independent samples — no student-level linkage.\n\n")


############################################################################
### A.5  Build Transition Kernel
############################################################################

cat("A.5  Building transition kernel from baseline copula...\n")

kernel_cache <- create_kernel_cache(
  p1_copula,
  u_grid_size     = cfg$kernel$u_grid_size,
  v_grid_size     = cfg$kernel$v_grid_size,
  boundary_buffer = cfg$kernel$boundary_buffer,
  compute_quantile = cfg$kernel$compute_quantile
)
cat("  Kernel cache built:", kernel_cache$copula_family,
    "(", paste(names(kernel_cache$copula_params), "=",
    round(unlist(kernel_cache$copula_params), 3), collapse = ", "), ")\n")
cat("  Grid:", cfg$kernel$u_grid_size, "x", cfg$kernel$v_grid_size, "\n\n")


############################################################################
### A.6  Estimate Growth Regime
############################################################################

cat("A.6  Estimating growth regime...\n\n")

# Run comparison across all three families
family_comparison <- compare_regime_families(
  u_sample       = u_cross,
  v_sample       = v_cross,
  kernel_cache   = kernel_cache,
  families       = cfg$regime$families,
  distance_fn    = cfg$distance$primary,
  grid_resolution = cfg$regime$grid_resolution,
  verbose        = TRUE
)

best_family <- family_comparison$best_family
best_est <- family_comparison$results[[best_family]]

cat("\n  Best regime family:", best_family, "\n")
cat("  Estimated median SGPc:", round(best_est$regime$median * 100, 1), "\n")
cat("  True median SGPc:     ", round(median(true_sgpc, na.rm = TRUE), 1), "\n")
cat("  Difference:           ",
    round(best_est$regime$median * 100 - median(true_sgpc, na.rm = TRUE), 1),
    " SGP points\n\n")


############################################################################
### A.7  Uncertainty Quantification
############################################################################

cat("A.7  Bootstrap uncertainty quantification...\n\n")

boot_results <- bootstrap_regime(
  u_sample       = u_cross,
  v_sample       = v_cross,
  kernel_cache   = kernel_cache,
  regime_family  = best_family,
  distance_fn    = cfg$distance$primary,
  n_boot         = cfg$uncertainty$n_bootstrap,
  grid_resolution = cfg$uncertainty$bootstrap_grid_resolution,
  seed           = cfg$seed,
  verbose        = TRUE
)


############################################################################
### A.8  Diagnostic Plots
############################################################################

cat("\nA.8  Generating diagnostic plots...\n")

viz_dir <- file.path(RESULTS_DIR, "visualizations", "phase_a")
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE)

sg_label <- paste0(condition_id, " / ", sg_col, " = ", subgroup_id)

# CDF comparison
plot_observed_vs_predicted_cdf(
  best_est,
  title = paste0("CDF Comparison — ", sg_label),
  output_dir = viz_dir,
  filename = "panel_a_cdf_comparison"
)

# Regime shape vs true SGPc
plot_regime_shape(
  best_est$regime, true_sgpc,
  title = paste0("Growth Regime Recovery — ", sg_label),
  output_dir = viz_dir,
  filename = "panel_b_regime_comparison"
)

# Residual curve
plot_residual_curve(
  best_est,
  output_dir = viz_dir,
  filename = "panel_c_residual_curve"
)

# Multi-panel recovery summary
plot_recovery_summary(
  best_est, true_sgpc,
  title = paste0("Recovery Summary — ", sg_label),
  output_dir = viz_dir,
  filename = "panel_d_recovery_summary"
)

cat("  Plots saved to:", viz_dir, "\n\n")


############################################################################
### A.9  Save Phase A Results
############################################################################

cat("A.9  Saving Phase A results...\n")

phase_a_results <- list(
  condition_id       = condition_id,
  condition_meta     = cond,
  dataset_id         = dataset_id,
  subgroup_id        = subgroup_id,
  subgroup_col       = sg_col,
  n_subgroup         = nrow(pairs_sg),
  true_sgpc          = true_sgpc,
  family_comparison  = family_comparison,
  best_family        = best_family,
  best_estimate      = best_est,
  bootstrap          = boot_results,
  references         = list(n_prior = refs$n_prior, n_current = refs$n_current),
  copula_used        = list(family = kernel_cache$copula_family,
                            params = kernel_cache$copula_params),
  config             = cfg
)

saveRDS(phase_a_results, file.path(RESULTS_DIR, "phase_a_deep_dive.rds"))

# Also write a quick summary CSV
summary_row <- data.frame(
  condition_id    = condition_id,
  subgroup_id     = subgroup_id,
  n_subgroup      = nrow(pairs_sg),
  regime_family   = best_family,
  median_sgpc_inferred = round(best_est$regime$median * 100, 2),
  median_sgpc_true     = round(median(true_sgpc, na.rm = TRUE), 2),
  median_diff          = round(best_est$regime$median * 100 -
                               median(true_sgpc, na.rm = TRUE), 2),
  wasserstein1    = round(best_est$all_distances$wasserstein1, 6),
  cvm             = round(best_est$all_distances$cramer_von_mises, 6),
  boot_ci_lo      = round(boot_results$ci_median_sgpc[1], 1),
  boot_ci_hi      = round(boot_results$ci_median_sgpc[2], 1),
  boot_se         = round(boot_results$se_median_sgpc, 2),
  stringsAsFactors = FALSE
)
fwrite(summary_row, file.path(RESULTS_DIR, "phase_a_summary.csv"))

cat("  Saved: phase_a_deep_dive.rds, phase_a_summary.csv\n")

cat("\n--- Phase A complete ---\n\n")
