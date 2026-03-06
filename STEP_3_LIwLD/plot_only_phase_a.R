############################################################################
###
### STEP 3 — Plot-Only Regeneration for Phase A
###
### Regenerates Phase A diagnostic plots from saved results without rerunning
### longitudinal extraction, kernel fitting, optimization, or bootstrap.
###
### Usage:
###   # From project root
###   source("STEP_3_LIwLD/plot_only_phase_a.R")
###
###   # Or from STEP_3_LIwLD directory
###   source("plot_only_phase_a.R")
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

cat("--- STEP 3 Phase A Plot-Only Regeneration ---\n\n")

# Resolve paths from either project root or STEP_3_LIwLD directory
if (grepl("STEP_3_LIwLD$", getwd())) {
  STEP3_ROOT <- getwd()
  PROJECT_ROOT <- dirname(STEP3_ROOT)
} else {
  PROJECT_ROOT <- getwd()
  STEP3_ROOT <- file.path(PROJECT_ROOT, "STEP_3_LIwLD")
}

RESULTS_DIR <- file.path(STEP3_ROOT, "results")
PHASE_A_RDS <- file.path(RESULTS_DIR, "phase_a_deep_dive.rds")
PHASE_A_PAYLOAD <- file.path(RESULTS_DIR, "phase_a_analytic_payload.rds")
VIZ_DIR <- file.path(RESULTS_DIR, "visualizations", "phase_a")

if (!file.exists(PHASE_A_RDS)) {
  stop("Phase A results file not found: ", PHASE_A_RDS,
       "\nRun Phase A first with run_step3.R, then rerun this script.")
}

if (!file.exists(PHASE_A_PAYLOAD)) {
  stop("Phase A analytic payload not found: ", PHASE_A_PAYLOAD,
       "\nRun Phase A first with run_step3.R to generate export payloads.")
}

# Plot dependencies
require(ggplot2)
require(patchwork)
require(wesanderson)

source(file.path(STEP3_ROOT, "functions/step3_publication_style.R"))
source(file.path(STEP3_ROOT, "functions/figure_naming.R"))
source(file.path(STEP3_ROOT, "functions/diagnostics_plots.R"))
source(file.path(STEP3_ROOT, "config_step3.R"))

if (!dir.exists(VIZ_DIR)) {
  dir.create(VIZ_DIR, recursive = TRUE)
}

phase_a <- readRDS(PHASE_A_RDS)
payload <- readRDS(PHASE_A_PAYLOAD)

if (is.null(phase_a$best_estimate) || is.null(phase_a$true_sgpc)) {
  stop("phase_a_deep_dive.rds is missing required objects ",
       "(best_estimate and/or true_sgpc).")
}

best_est <- phase_a$best_estimate
if (!is.null(payload$F_uniform)) best_est$F_uniform <- payload$F_uniform
if (!is.null(payload$F_tamp)) best_est$F_tamp <- payload$F_tamp
if (!is.null(payload$fit_metrics$w1_uniform)) best_est$w1_uniform <- payload$fit_metrics$w1_uniform[1]
true_sgpc <- phase_a$true_sgpc
condition_id <- phase_a$condition_id
subgroup_id <- phase_a$subgroup_id
sg_col <- phase_a$subgroup_col

sg_label <- format_step3_condition_label(condition_id, sg_col, subgroup_id)
phasea_fig <- get_phasea_figure_map()

cat("Loaded:", PHASE_A_RDS, "\n")
cat("Regenerating plots for:", sg_label, "\n")
cat("Output dir:", VIZ_DIR, "\n\n")

# 01. Marginal U/V panel
plot_marginal_uv_density(
  u_sample = phase_a$u_sample,
  v_sample = phase_a$v_sample,
  title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "A."),
  output_dir = VIZ_DIR,
  filename = phasea_fig$marginal_uv_density
)

# 02b. CDF comparison
plot_observed_vs_predicted_cdf(
  best_est,
  title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "B2."),
  output_dir = VIZ_DIR,
  filename = phasea_fig$forward_cdf_check
)

# 02a. Objective surface
plot_objective_surface(
  best_est,
  title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "B1."),
  output_dir = VIZ_DIR,
  filename = phasea_fig$objective_surface
)

# 03a. Regime shape comparison
plot_regime_shape(
  best_est$regime,
  true_sgpc = true_sgpc,
  title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "C."),
  output_dir = VIZ_DIR,
  filename = phasea_fig$regime_density,
  bootstrap = phase_a$bootstrap
)

# 03e. Multi-panel recovery summary
plot_recovery_summary(
  best_est,
  true_sgpc = true_sgpc,
  title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "Growth Regime Recovery Summary —"),
  output_dir = VIZ_DIR,
  filename = phasea_fig$recovery_summary
)

# 04. Independence diagnostics
plot_independence_diagnostic(
  u_sample = phase_a$u_sample,
  true_sgpc = true_sgpc,
  n_bins = STEP3_CONFIG$assumptions$independence$u_bins,
  title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "I."),
  output_dir = VIZ_DIR,
  filename = phasea_fig$independence_diagnostic
)

# E. Bootstrap uncertainty — Median SGPc
if (!is.null(phase_a$bootstrap)) {
  plot_bootstrap_sgpc(
    phase_a$bootstrap,
    measure = "median",
    true_sgpc = true_sgpc,
    title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "Bootstrap Median SGPc —"),
    output_dir = VIZ_DIR,
    filename = phasea_fig$bootstrap_median
  )

  # F. Bootstrap uncertainty — Mean SGPc
  plot_bootstrap_sgpc(
    phase_a$bootstrap,
    measure = "mean",
    true_sgpc = true_sgpc,
    title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "Bootstrap Mean SGPc —"),
    output_dir = VIZ_DIR,
    filename = phasea_fig$bootstrap_mean
  )

  # G. Combined median + mean bootstrap panel
  plot_bootstrap_sgpc_combined(
    phase_a$bootstrap,
    true_sgpc = true_sgpc,
    title = format_step3_condition_label(condition_id, sg_col, subgroup_id, "Bootstrap Uncertainty —"),
    output_dir = VIZ_DIR,
    filename = phasea_fig$bootstrap_combined
  )
} else {
  cat("  Skipping bootstrap panels (no bootstrap data).\n")
}

write_phasea_legacy_aliases(
  output_dir = VIZ_DIR,
  enable_alias = isTRUE(STEP3_CONFIG$output$phase_a_legacy_alias_plots),
  formats = STEP3_CONFIG$output$export_formats
)

cat("\nDone. Phase A diagnostic plots regenerated.\n")
