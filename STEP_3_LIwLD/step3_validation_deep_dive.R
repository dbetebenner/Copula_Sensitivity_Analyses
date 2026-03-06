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
###   5. Estimate growth regime      ->  H_S by minimum-distance
###   6. Compare inferred vs actual  ->  the key validation
###   7. Diagnostics + uncertainty   ->  plots + bootstrap
###
### Sourced by run_step3.R (Phase A) or can be run standalone.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
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
  # Auto-select: prioritize 1-year span + preferred content area
  conditions <- get_phase1_conditions(dataset_id)
  if (length(conditions) == 0) stop("No Phase 1 conditions found for ", dataset_id)

  preferred_content <- ""
  if (!is.null(cfg$validation$content_area)) {
    preferred_content <- toupper(as.character(cfg$validation$content_area))
  }

  # Parse condition metadata
  cond_meta <- lapply(conditions, parse_condition_id)
  spans <- sapply(cond_meta, `[[`, "year_span")
  contents <- toupper(sapply(cond_meta, `[[`, "content_area"))

  one_year <- conditions[spans == 1]
  one_year_contents <- contents[spans == 1]

  one_year_preferred <- one_year[one_year_contents == preferred_content]

  if (length(one_year_preferred) > 0) {
    condition_id <- one_year_preferred[1]
    cat("Auto-selected 1-year preferred content condition:", condition_id, "\n")
  } else if (length(one_year) > 0) {
    condition_id <- one_year[1]
    cat("Preferred content not found in 1-year spans; using first 1-year condition:", condition_id, "\n")
  } else {
    condition_id <- conditions[1]
    cat("No 1-year conditions available; using first available condition:", condition_id, "\n")
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

# Calculate year_prior from condition metadata
year_prior <- as.character(as.numeric(cond$year_current) - cond$year_span)

pairs <- create_longitudinal_pairs(
  data          = STATE_DATA,
  grade_prior   = cond$grade_prior,
  grade_current = cond$grade_current,
  year_prior    = year_prior,
  year_current  = cond$year_current,
  content_prior = cond$content_area
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

# Independence diagnostics for key assumption P ⟂ U within subgroup
assump_cfg <- cfg$assumptions$independence
u_bins <- as.integer(assump_cfg$u_bins)
u_bins <- ifelse(is.na(u_bins) || u_bins < 3, 5L, u_bins)
u_cut <- cut(
  u_sg,
  breaks = unique(as.numeric(quantile(u_sg, probs = seq(0, 1, length.out = u_bins + 1), na.rm = TRUE))),
  include.lowest = TRUE
)

spearman_rho <- suppressWarnings(cor(u_sg, true_sgpc, method = "spearman", use = "complete.obs"))
kw_test <- tryCatch(
  kruskal.test(true_sgpc ~ u_cut),
  error = function(e) NULL
)
kw_p <- if (!is.null(kw_test)) as.numeric(kw_test$p.value) else NA_real_

flag_independence_violation <- (
  (is.finite(spearman_rho) && abs(spearman_rho) > assump_cfg$max_abs_spearman) ||
    (is.finite(kw_p) && kw_p < assump_cfg$alpha)
)

diag_summary <- data.table::data.table(
  subgroup_id = subgroup_id,
  metric = c("spearman_rho", "kruskal_p_value", "n_bins", "flag_independence_violation"),
  value = c(spearman_rho, kw_p, u_bins, as.numeric(flag_independence_violation))
)
diag_bins <- data.table::data.table(
  subgroup_id = subgroup_id,
  u_bin = as.character(u_cut),
  u_bin_n = 1L,
  mean_sgpc = true_sgpc,
  median_sgpc = true_sgpc
)[, .(
  u_bin_n = .N,
  mean_sgpc = mean(mean_sgpc, na.rm = TRUE),
  median_sgpc = median(median_sgpc, na.rm = TRUE)
), by = .(subgroup_id, u_bin)]
independence_diagnostics <- data.table::rbindlist(
  list(
    data.table::data.table(
      subgroup_id = subgroup_id,
      u_bin = NA_character_,
      u_bin_n = NA_integer_,
      mean_sgpc = NA_real_,
      median_sgpc = NA_real_,
      metric = diag_summary$metric,
      value = diag_summary$value
    ),
    data.table::data.table(
      subgroup_id = diag_bins$subgroup_id,
      u_bin = diag_bins$u_bin,
      u_bin_n = diag_bins$u_bin_n,
      mean_sgpc = diag_bins$mean_sgpc,
      median_sgpc = diag_bins$median_sgpc,
      metric = "bin_summary",
      value = NA_real_
    )
  ),
  fill = TRUE
)
cat("  Independence diagnostics:\n")
cat("    Spearman rho(U,SGPc_true):", round(spearman_rho, 4), "\n")
cat("    Kruskal-Wallis p-value:", signif(kw_p, 4), "\n")
cat("    Flag violation:", flag_independence_violation, "\n\n")


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
  tie_tolerance  = cfg$regime$tie_tolerance,
  preferred_family = cfg$regime$preferred_family,
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
cat("  Estimated mean SGPc:  ", round(best_est$regime$mean * 100, 1), "\n")
cat("  True mean SGPc:       ", round(mean(true_sgpc, na.rm = TRUE), 1), "\n")
cat("  Difference:           ",
    round(best_est$regime$mean * 100 - mean(true_sgpc, na.rm = TRUE), 1),
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
  resample_scheme = cfg$uncertainty$resample_scheme,
  seed           = cfg$seed,
  verbose        = TRUE
)
cat("  Bootstrap median SGPc 95% CI:",
    paste0("[", round(boot_results$ci_median_sgpc[1], 1), ", ",
           round(boot_results$ci_median_sgpc[2], 1), "]"), "\n")
cat("  Bootstrap mean SGPc 95% CI:  ",
    paste0("[", round(boot_results$ci_mean_sgpc[1], 1), ", ",
           round(boot_results$ci_mean_sgpc[2], 1), "]"), "\n\n")


############################################################################
### A.8  Diagnostic Plots
############################################################################

cat("\nA.8  Generating diagnostic plots...\n")

viz_dir <- file.path(RESULTS_DIR, "visualizations", "phase_a")
if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE)

sg_label <- paste0(condition_id, " / ", sg_col, " = ", subgroup_id)
phasea_fig <- if (exists("get_phasea_figure_map", mode = "function")) {
  get_phasea_figure_map()
} else {
  list(
    marginal_uv_density = "phasea_01_marginals_uv_density",
    objective_surface = "phasea_02a_objective_surface",
    forward_cdf_check = "phasea_02b_forward_cdf_check",
    residual_diagnostics = "phasea_02c_residual_diagnostics",
    regime_density = "phasea_03a_regime_density",
    bootstrap_median = "phasea_03b_bootstrap_median_sgpc",
    bootstrap_mean = "phasea_03c_bootstrap_mean_sgpc",
    bootstrap_combined = "phasea_03d_bootstrap_combined",
    recovery_summary = "phasea_03e_recovery_summary",
    independence_diagnostic = "phasea_04_independence_diagnostic"
  )
}

# 01. Marginal U/V panel (infographic step A)
plot_marginal_uv_density(
  u_sample = u_cross,
  v_sample = v_cross,
  output_dir = viz_dir,
  filename = phasea_fig$marginal_uv_density,
  title = paste0("A. Unlinked Marginals — ", sg_label)
)

# CDF comparison
best_est$F_uniform <- predict_marginal_cdf(
  v_grid = best_est$v_grid,
  u_sample = u_cross,
  regime = regime_beta(0.5, 2),
  kernel_cache = kernel_cache
)
best_est$F_tamp <- ecdf(u_cross)(best_est$v_grid)
best_est$w1_uniform <- wasserstein1(best_est$F_uniform, best_est$F_obs, best_est$v_grid)

plot_observed_vs_predicted_cdf(
  best_est,
  title = paste0("B2. Forward CDF Check — ", sg_label),
  output_dir = viz_dir,
  filename = phasea_fig$forward_cdf_check
)

# Objective surface (B1)
plot_objective_surface(
  best_est,
  output_dir = viz_dir,
  filename = phasea_fig$objective_surface,
  title = paste0("Growth Regime Surface — ", sg_label)
)

# Regime shape vs true SGPc
plot_regime_shape(
  best_est$regime, true_sgpc,
  title = paste0("C. Inferred Regime Density — ", sg_label),
  output_dir = viz_dir,
  filename = phasea_fig$regime_density,
  bootstrap = boot_results
)

# Residual curve
plot_residual_curve(
  best_est,
  output_dir = viz_dir,
  filename = phasea_fig$residual_diagnostics,
  title = paste0("Residual Diagnostics — ", sg_label)
)

# Multi-panel recovery summary
plot_recovery_summary(
  best_est, true_sgpc,
  title = paste0("Growth Regime Recovery Summary: ", sg_label),
  output_dir = viz_dir,
  filename = phasea_fig$recovery_summary
)

# Independence diagnostic (Panel I re-usable artifact)
plot_independence_diagnostic(
  u_sample = u_sg,
  true_sgpc = true_sgpc,
  n_bins = u_bins,
  output_dir = viz_dir,
  filename = phasea_fig$independence_diagnostic,
  title = paste0("I. Independence Diagnostic — ", sg_label)
)

# Bootstrap uncertainty: median + mean + combined
plot_bootstrap_sgpc(
  boot_results,
  measure = "median",
  true_sgpc = true_sgpc,
  title = paste0("Bootstrap Uncertainty: Median SGPc — ", sg_label),
  output_dir = viz_dir,
  filename = phasea_fig$bootstrap_median
)
plot_bootstrap_sgpc(
  boot_results,
  measure = "mean",
  true_sgpc = true_sgpc,
  title = paste0("Bootstrap Uncertainty: Mean SGPc — ", sg_label),
  output_dir = viz_dir,
  filename = phasea_fig$bootstrap_mean
)
plot_bootstrap_sgpc_combined(
  boot_results,
  true_sgpc = true_sgpc,
  title = paste0("Bootstrap Uncertainty: Median & Mean SGPc — ", sg_label),
  output_dir = viz_dir,
  filename = phasea_fig$bootstrap_combined
)

if (exists("write_phasea_legacy_aliases", mode = "function")) {
  write_phasea_legacy_aliases(
    output_dir = viz_dir,
    enable_alias = isTRUE(cfg$output$phase_a_legacy_alias_plots),
    formats = cfg$output$export_formats
  )
}

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
  independence_diagnostics = independence_diagnostics,
  flag_independence_violation = flag_independence_violation,
  family_comparison  = family_comparison,
  best_family        = best_family,
  best_estimate      = best_est,
  bootstrap          = boot_results,
  u_sample           = u_cross,
  v_sample           = v_cross,
  kernel_cache       = kernel_cache,
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
  mean_sgpc_inferred   = round(best_est$regime$mean * 100, 2),
  median_sgpc_true     = round(median(true_sgpc, na.rm = TRUE), 2),
  mean_sgpc_true       = round(mean(true_sgpc, na.rm = TRUE), 2),
  median_diff          = round(best_est$regime$median * 100 -
                               median(true_sgpc, na.rm = TRUE), 2),
  mean_diff            = round(best_est$regime$mean * 100 -
                               mean(true_sgpc, na.rm = TRUE), 2),
  w1_uniform      = round(best_est$w1_uniform, 6),
  w1_reduction_pct = round(100 * (1 - (best_est$all_distances$wasserstein1 / best_est$w1_uniform)), 2),
  max_abs_residual = round(max(abs(best_est$F_pred - best_est$F_obs), na.rm = TRUE), 6),
  mean_abs_residual = round(mean(abs(best_est$F_pred - best_est$F_obs), na.rm = TRUE), 6),
  wasserstein1    = round(best_est$all_distances$wasserstein1, 6),
  cvm             = round(best_est$all_distances$cramer_von_mises, 6),
  boot_ci_lo      = round(boot_results$ci_median_sgpc[1], 1),
  boot_ci_hi      = round(boot_results$ci_median_sgpc[2], 1),
  boot_ci_mean_lo = round(boot_results$ci_mean_sgpc[1], 1),
  boot_ci_mean_hi = round(boot_results$ci_mean_sgpc[2], 1),
  boot_se         = round(boot_results$se_median_sgpc, 2),
  spearman_rho_u_sgpc_true = round(spearman_rho, 6),
  kruskal_p_u_bins = round(kw_p, 8),
  flag_independence_violation = flag_independence_violation,
  stringsAsFactors = FALSE
)
fwrite(summary_row, file.path(RESULTS_DIR, "phase_a_summary.csv"))

# Precision anchor for sample-size scaling narrative in Phase B/Step 5
se_median <- if (!is.null(boot_results$se_median_sgpc)) boot_results$se_median_sgpc else NA_real_
se_mean   <- if (!is.null(boot_results$se_mean_sgpc))   boot_results$se_mean_sgpc   else NA_real_

precision_anchor <- data.table::data.table(
  dataset_id = dataset_id,
  condition_id = condition_id,
  subgroup_id = subgroup_id,
  n0 = nrow(pairs_sg),
  measure = c("median_sgpc", "mean_sgpc"),
  estimate = c(
    round(best_est$regime$median * 100, 2),
    round(best_est$regime$mean * 100, 2)
  ),
  se0 = c(
    round(se_median, 4),
    round(se_mean, 4)
  ),
  ci95_lo = c(
    round(boot_results$ci_median_sgpc[1], 4),
    round(boot_results$ci_mean_sgpc[1], 4)
  ),
  ci95_hi = c(
    round(boot_results$ci_median_sgpc[2], 4),
    round(boot_results$ci_mean_sgpc[2], 4)
  )
)
precision_anchor[, ci95_width := round(ci95_hi - ci95_lo, 4)]
data.table::fwrite(precision_anchor, file.path(RESULTS_DIR, "phase_a_precision_anchor.csv"))

# Export notation-aligned analytic payload + tidy figure data
phase_a_exports <- export_phase_a_figure_data(
  phase_a_results = phase_a_results,
  output_dir = RESULTS_DIR,
  write_files = TRUE
)
export_phase_a_dir <- file.path(RESULTS_DIR, "exports", "phase_a")
if (!dir.exists(export_phase_a_dir)) dir.create(export_phase_a_dir, recursive = TRUE)
data.table::fwrite(
  independence_diagnostics,
  file.path(export_phase_a_dir, "step3_independence_diagnostics.csv")
)
phase_a_results$figure_exports <- list(
  cdf_rows = nrow(phase_a_exports$cdf_curves),
  objective_rows = nrow(phase_a_exports$objective_surface),
  density_rows = nrow(phase_a_exports$regime_density),
  independence_rows = nrow(independence_diagnostics)
)
saveRDS(phase_a_results, file.path(RESULTS_DIR, "phase_a_deep_dive.rds"))

# Export comprehensive Phase A manifest files (JSON + MD)
export_phase_a_manifest(phase_a_results, output_dir = RESULTS_DIR, prefix = "phase_a")

cat("  Saved: phase_a_deep_dive.rds, phase_a_summary.csv\n")
cat("  Saved: phase_a_precision_anchor.csv\n")
cat("  Saved: phase_a_analytic_payload.rds and exports/phase_a/*.csv\n")
cat("  Saved: exports/phase_a/step3_independence_diagnostics.csv\n")
cat("  Saved: phase_a_manifest.json, phase_a_manifest.md\n")

cat("\n--- Phase A complete ---\n\n")
