###############################################################################
###
### step3_export_data.R - Export panel-ready data for Error Budget infographic
###
### Generates synthetic but representative accuracy/precision data for
### copula-based stochastic growth regime inference.
###
### Panel A: Truth benchmark — true P_S density from linked data
### Panel B: Bridge accuracy — displacement when linkage is erased
### Panel C: Sampling worlds — conceptual (minimal data)
### Panel D: Precision operating curve — CI width vs N
### Panel E: Total uncertainty — combined error budget bands
###
### Usage: source("step3_export_data.R")  (from Error_Figure/ directory)
###
###############################################################################

set.seed(20260312)

script_file <- sub(
  "^--file=",
  "",
  commandArgs(trailingOnly = FALSE)[
    grep("^--file=", commandArgs(trailingOnly = FALSE))
  ][1]
)

pstricks_dir <- if (!is.na(script_file) && nzchar(script_file)) {
  normalizePath(dirname(script_file), winslash = "/", mustWork = TRUE)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

data_dir <- file.path(pstricks_dir, "data")
if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}


# --- Helper ------------------------------------------------------------------
write_dat <- function(x, y, filename) {
  out <- file.path(data_dir, filename)
  writeLines(paste(x, y), out)
  cat("  ", filename, "\n")
}


###############################################################################
# Configuration — synthetic low-growth subgroup
###############################################################################

# True growth regime: Beta(kappa*m, kappa*(1-m))
true_m <- 0.39 # true mean SGPc on 0-1 scale (matches overview figure)
true_kappa <- 18 # concentration
true_alpha <- true_kappa * true_m
true_beta <- true_kappa * (1 - true_m)
true_mean_sgpc <- true_m * 100 # = 39.0

# Copula parameters (baseline t-copula)
copula_rho <- 0.72
copula_df <- 8

# Subgroup size for main demonstration
n_main <- 3500

# Bridge inference bias (systematic small positive bias typical of the method)
bridge_bias <- 0.4 # SGPc points

# Bridge-recovered estimate
bridge_mean_sgpc <- true_mean_sgpc + bridge_bias # 39.4

# Number of validation conditions
n_conditions <- 25


###############################################################################
# Panel A: Truth benchmark — density of true P_S from linked data
###############################################################################

cat("Panel A (truth benchmark)...\n")

p_grid <- seq(0.001, 0.999, length.out = 500)

# True regime density
d_true <- dbeta(p_grid, true_alpha, true_beta)
write_dat(round(p_grid * 100, 4), round(d_true, 6), "panel_A_density_true.dat")

# Uniform reference density (flat at 1)
write_dat(
  round(p_grid * 100, 4),
  round(rep(1, length(p_grid)), 4),
  "panel_A_density_uniform.dat"
)

# Bridge-recovered density (slightly shifted)
bridge_m <- bridge_mean_sgpc / 100
bridge_kappa <- true_kappa + 0.2 # slight perturbation
bridge_alpha <- bridge_kappa * bridge_m
bridge_beta <- bridge_kappa * (1 - bridge_m)
d_bridge <- dbeta(p_grid, bridge_alpha, bridge_beta)
write_dat(
  round(p_grid * 100, 4),
  round(d_bridge, 6),
  "panel_A_density_bridge.dat"
)


###############################################################################
# Panel B: Bridge accuracy — truth vs bridge estimate across conditions
###############################################################################

cat("Panel B (bridge accuracy)...\n")

# Generate validation conditions: different true means, each with a bridge estimate
# True means range from ~25 to ~65 (covering low to high growth subgroups)
true_means_conditions <- sort(c(
  runif(8, 25, 35), # low growth
  runif(9, 35, 55), # middle
  runif(8, 55, 65) # high growth
))

# Bridge errors: systematic small bias + condition-specific noise
# Method tends to be slightly biased toward 50 (regression to mean of [0,1])
bridge_errors <- sapply(true_means_conditions, function(tm) {
  # Slight pull toward 50 + small noise
  pull_toward_50 <- (50 - tm) * 0.015
  noise <- rnorm(1, 0, 0.8)
  pull_toward_50 + noise
})

bridge_estimates <- true_means_conditions + bridge_errors

# Write as (true_mean, bridge_estimate) pairs for dot plot
write_dat(
  round(true_means_conditions, 2),
  round(bridge_estimates, 2),
  "panel_B_accuracy_pairs.dat"
)

# Write bridge errors for histogram/density
bridge_error_density <- density(bridge_errors, bw = "SJ", n = 256)
write_dat(
  round(bridge_error_density$x, 4),
  round(bridge_error_density$y, 6),
  "panel_B_error_density.dat"
)

# Summary statistics for bridge accuracy
mean_bridge_error <- mean(bridge_errors)
median_bridge_error <- median(bridge_errors)
mae_bridge <- mean(abs(bridge_errors))
max_abs_error <- max(abs(bridge_errors))
rmse_bridge <- sqrt(mean(bridge_errors^2))


###############################################################################
# Panel C: Sampling worlds — minimal data (mostly schematic)
###############################################################################

cat("Panel C (sampling worlds)...\n")

# Generate small illustration data for paired vs independent
# Paired: same 10 students sampled at both times
paired_u <- runif(10, 0.1, 0.9)
paired_v <- paired_u + rnorm(10, -0.05, 0.15)
paired_v <- pmin(pmax(paired_v, 0.02), 0.98)

# Independent: different students at each time
indep_u <- runif(10, 0.1, 0.9)
indep_v <- runif(10, 0.15, 0.85)

write_dat(round(paired_u, 4), round(paired_v, 4), "panel_C_paired_sample.dat")
write_dat(
  round(indep_u, 4),
  round(indep_v, 4),
  "panel_C_independent_sample.dat"
)


###############################################################################
# Panel D: Precision operating curves — CI width vs N
###############################################################################

cat("Panel D (precision curves)...\n")

# Sample sizes to evaluate
N_grid <- c(
  seq(50, 500, by = 25),
  seq(600, 1000, by = 50),
  seq(1200, 2000, by = 200),
  seq(2500, 5000, by = 500)
)

# Paired subsampling precision (tighter):
# SE_paired ~ k_p / sqrt(N), CI_width = 3.92 * SE
# At N=500: CI_width ~ 3.5 SGPc points -> k_p = 3.5 * sqrt(500) / 3.92 = 20.0
k_paired <- 20.0
ci_width_paired <- 3.92 * k_paired / sqrt(N_grid)

# Independent cross-sectional precision (wider):
# At N=500: CI_width ~ 6.0 SGPc points -> k_i = 6.0 * sqrt(500) / 3.92 = 34.2
k_indep <- 34.2
ci_width_indep <- 3.92 * k_indep / sqrt(N_grid)

# Add slight curvature for realism (precision improves sharply then flattens)
# Add log-correction: actual SE has a small finite-sample correction
ci_width_paired <- ci_width_paired * (1 + 2.5 / sqrt(N_grid))
ci_width_indep <- ci_width_indep * (1 + 4.0 / sqrt(N_grid))

write_dat(N_grid, round(ci_width_paired, 3), "panel_D_precision_paired.dat")
write_dat(N_grid, round(ci_width_indep, 3), "panel_D_precision_indep.dat")

# Also write MAE curves (secondary annotation)
mae_paired <- ci_width_paired * 0.38 # MAE/CI_width ratio ~ 0.38 for normal
mae_indep <- ci_width_indep * 0.38
write_dat(N_grid, round(mae_paired, 3), "panel_D_mae_paired.dat")
write_dat(N_grid, round(mae_indep, 3), "panel_D_mae_indep.dat")


###############################################################################
# Panel E: Total uncertainty budget — nested bands
###############################################################################

cat("Panel E (total uncertainty)...\n")

# For a set of representative subgroups, show:
# - center estimate (bridge-recovered mean SGPc)
# - inner band: sampling precision (95% CI)
# - outer band: sampling + bridge error
# - optional: stress-test sensitivity

subgroup_labels <- c(
  "Low\ngrowth",
  "Below\navg.",
  "Average",
  "Above\navg.",
  "High\ngrowth"
)
subgroup_estimates <- c(32.5, 42.0, 50.5, 58.0, 67.5)
subgroup_truth <- c(32.0, 41.5, 50.0, 57.5, 68.0)

# Sampling precision (half-width of 95% CI) at N=500 for independent design
sampling_hw_indep <- 3.92 * k_indep / sqrt(500) * (1 + 4.0 / sqrt(500)) / 2

# Bridge bias per subgroup (slight pull toward 50)
bridge_biases <- subgroup_estimates - subgroup_truth

# Stress-test sensitivity (small additional perturbation)
stress_test_hw <- c(1.2, 0.8, 0.5, 0.8, 1.3)

# Write as structured data: est, truth, sampling_hw, bridge_bias, stress_hw
panel_e_lines <- character()
for (i in seq_along(subgroup_estimates)) {
  panel_e_lines <- c(
    panel_e_lines,
    paste(
      i,
      subgroup_estimates[i],
      subgroup_truth[i],
      round(sampling_hw_indep, 2),
      round(bridge_biases[i], 2),
      round(stress_test_hw[i], 2)
    )
  )
}
writeLines(panel_e_lines, file.path(data_dir, "panel_E_uncertainty_budget.dat"))
cat("   panel_E_uncertainty_budget.dat\n")


###############################################################################
# Summary metrics (LaTeX macros)
###############################################################################

cat("Summary metrics...\n")

metrics <- c(
  sprintf("\\providecommand{\\trueRegimeMean}{%.1f}", true_mean_sgpc),
  sprintf("\\providecommand{\\bridgeMean}{%.1f}", bridge_mean_sgpc),
  sprintf("\\providecommand{\\bridgeBias}{%.1f}", bridge_bias),
  sprintf("\\providecommand{\\meanBridgeError}{%.2f}", mean_bridge_error),
  sprintf("\\providecommand{\\medianBridgeError}{%.2f}", median_bridge_error),
  sprintf("\\providecommand{\\maeBridge}{%.2f}", mae_bridge),
  sprintf("\\providecommand{\\maxAbsError}{%.1f}", max_abs_error),
  sprintf("\\providecommand{\\rmseBridge}{%.2f}", rmse_bridge),
  sprintf("\\providecommand{\\nConditions}{%d}", n_conditions),
  sprintf("\\providecommand{\\nMain}{%s}", format(n_main, big.mark = ",")),
  sprintf("\\providecommand{\\copulaRho}{%.2f}", copula_rho),
  sprintf("\\providecommand{\\copulaDf}{%d}", copula_df),
  sprintf("\\providecommand{\\trueKappa}{%d}", true_kappa),
  sprintf("\\providecommand{\\trueAlpha}{%.1f}", true_alpha),
  sprintf("\\providecommand{\\trueBeta}{%.1f}", true_beta),
  sprintf(
    "\\providecommand{\\samplingHWpaired}{%.1f}",
    3.92 * k_paired / sqrt(500) * (1 + 2.5 / sqrt(500)) / 2
  ),
  sprintf(
    "\\providecommand{\\samplingHWindep}{%.1f}",
    round(sampling_hw_indep, 1)
  ),
  sprintf(
    "\\providecommand{\\ciWidthPairedFiveH}{%.1f}",
    ci_width_paired[which(N_grid == 500)]
  ),
  sprintf(
    "\\providecommand{\\ciWidthIndepFiveH}{%.1f}",
    ci_width_indep[which(N_grid == 500)]
  )
)
writeLines(metrics, file.path(data_dir, "summary_metrics.tex"))
cat("   summary_metrics.tex\n")


###############################################################################
# Axis limits (LaTeX macros)
###############################################################################

cat("Axis limits...\n")

# Panel A: density y-max
y_max_a <- max(d_true, d_bridge) * 1.15

# Panel B: error density y-max and x range
y_max_b_density <- max(bridge_error_density$y) * 1.15
x_range_b <- range(bridge_error_density$x)

# Panel D: max CI width and max N
max_ci_width <- max(ci_width_indep) * 1.05
max_N <- max(N_grid)

axes <- c(
  sprintf("\\providecommand{\\panelAymax}{%s}", ceiling(y_max_a * 10) / 10),
  sprintf(
    "\\providecommand{\\panelBymax}{%s}",
    ceiling(y_max_b_density * 10) / 10
  ),
  sprintf("\\providecommand{\\panelBxmin}{%s}", floor(x_range_b[1])),
  sprintf("\\providecommand{\\panelBxmax}{%s}", ceiling(x_range_b[2])),
  sprintf("\\providecommand{\\panelDymax}{%s}", ceiling(max_ci_width)),
  sprintf("\\providecommand{\\panelDxmax}{%s}", max_N),
  sprintf("\\providecommand{\\trueMeanVline}{%s}", round(true_mean_sgpc, 1)),
  sprintf("\\providecommand{\\bridgeMeanVline}{%s}", round(bridge_mean_sgpc, 1))
)
writeLines(axes, file.path(data_dir, "axis_limits.tex"))
cat("   axis_limits.tex\n")


###############################################################################
# Panel B: accuracy scatter TeX (truth vs estimate with arrows)
###############################################################################

cat("Panel B (accuracy markers)...\n")

# Generate PSTricks code for accuracy dot-plot
# Each condition: vertical line from (true, y) to (bridge, y) with dots
marker_lines <- character()
for (i in seq_along(true_means_conditions)) {
  tm <- true_means_conditions[i]
  be <- bridge_estimates[i]
  y_pos <- i # stacked vertically
  err <- be - tm

  # Color based on direction of error
  col <- if (err >= 0) "zissouTeal" else "zissouRed"

  marker_lines <- c(
    marker_lines,
    sprintf(
      "\\psline[linecolor=%s,linewidth=0.8pt]{->}(%.2f,%d)(%.2f,%d)%%",
      col,
      tm,
      y_pos,
      be,
      y_pos
    ),
    sprintf("\\pscircle*[linecolor=zissouAmber](%.2f,%d){0.15}%%", tm, y_pos)
  )
}
writeLines(marker_lines, file.path(data_dir, "panel_B_accuracy_markers.tex"))
cat("   panel_B_accuracy_markers.tex\n")


cat("\nExport complete. Files in:", data_dir, "\n")
