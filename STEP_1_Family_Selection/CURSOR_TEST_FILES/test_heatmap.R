#!/usr/bin/env Rscript
#' Test Script for 10x10 Decile Heatmap Visualization
#'
#' Tests the new heatmap feature in plot_sgpc_comparison_panel()
#' INCLUDING traditional SGP comparison (SGP_ORDER_1 and SGP)
#' Run from terminal: Rscript STEP_1_Family_Selection/test_heatmap.R

cat(
  "========================================================================\n"
)
cat("TESTING: 10x10 Decile Heatmap for SGPc Comparison\n")
cat("        (with Traditional SGP Comparison)\n")
cat(
  "========================================================================\n\n"
)

# Load required packages
cat("Loading packages...\n")
suppressPackageStartupMessages({
  library(ggplot2)
  library(data.table)
  library(copula)
  library(patchwork)
  library(cowplot)
})
cat("Packages loaded successfully\n\n")

# Set working directory if not already there
if (!file.exists("functions/sgpc_engine.R")) {
  if (file.exists("../functions/sgpc_engine.R")) {
    setwd("..")
    cat("Changed to project root:", getwd(), "\n")
  } else {
    stop("Run from project root or STEP_1_Family_Selection directory")
  }
}

# Source function files
cat("Loading functions...\n")
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
source("functions/copula_contour_plots.R")
source("functions/sgpc_engine.R")
source("dataset_configs.R")
if (file.exists("dataset_configs_local.R")) {
  source("dataset_configs_local.R")
}
cat("Functions loaded successfully\n\n")

# Helper function to save in multiple formats
save_multi_format <- function(plot, base_path, width, height, dpi = 300) {
  # PDF
  ggsave(paste0(base_path, ".pdf"), plot, width = width, height = height)
  cat("    Saved:", paste0(base_path, ".pdf"), "\n")

  # SVG with transparent background
  ggsave(
    paste0(base_path, ".svg"),
    plot,
    width = width,
    height = height,
    bg = "transparent"
  )
  cat("    Saved:", paste0(base_path, ".svg"), "\n")

  # PNG with transparent background
  ggsave(
    paste0(base_path, "@2x.png"),
    plot,
    width = width,
    height = height,
    dpi = dpi * 2,
    bg = "transparent"
  )
  cat("    Saved:", paste0(base_path, "@2x.png"), "\n")
}

# Output directory
output_dir <- "STEP_1_Family_Selection/test_heatmap_output"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
cat("Output directory:", output_dir, "\n\n")

# Load data (use SGP data file to include traditional SGP columns)
cat("Loading Dataset 1 (with SGP columns)...\n")
current_dataset <- DATASETS[["dataset_1"]]

# Use SGP data file if available (contains SGP_ORDER_1 and SGP columns)
sgp_data_path <- current_dataset$local_path_sgp
if (!is.null(sgp_data_path) && file.exists(sgp_data_path)) {
  load(sgp_data_path)
  STATE_DATA_LONG <- get(current_dataset$rdata_object_name_sgp)
  cat("  Loaded SGP data file:", sgp_data_path, "\n")
  cat(
    "  Contains SGP columns: SGP_ORDER_1 =",
    "SGP_ORDER_1" %in% names(STATE_DATA_LONG),
    ", SGP =",
    "SGP" %in% names(STATE_DATA_LONG),
    "\n"
  )
} else {
  # Fallback to base data file
  load(current_dataset$local_path)
  STATE_DATA_LONG <- get(current_dataset$rdata_object_name)
  cat(
    "  Loaded base data file (no SGP columns):",
    current_dataset$local_path,
    "\n"
  )
}
get_state_data <- function() STATE_DATA_LONG
cat("Data loaded:", nrow(STATE_DATA_LONG), "rows\n\n")

# Create longitudinal pairs (includes SGP columns if available in source data)
# Note: Use a later year (e.g., 2010) where SGP values should be available
#       2005 is the first year in the dataset, so no prior SGP can be calculated
cat("Creating longitudinal pairs (Grade 5->6, Math, 2010)...\n")
pairs_full <- create_longitudinal_pairs(
  data = get_state_data(),
  grade_prior = 5,
  grade_current = 6,
  year_prior = "2010",
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS"
)
cat("  Matched pairs:", format(nrow(pairs_full), big.mark = ","), "\n")

# Check for traditional SGP columns (extracted from current grade data)
has_sgp_order_1 <- "SGP_ORDER_1" %in% names(pairs_full)
has_sgp_best <- "SGP" %in% names(pairs_full)
cat("  SGP_ORDER_1 column present:", has_sgp_order_1, "\n")
cat("  SGP (best) column present:", has_sgp_best, "\n")

# Extract traditional SGP values if available, checking for valid (non-NA) values
sgp_order_1_values <- NULL
sgp_best_values <- NULL

if (has_sgp_order_1) {
  n_valid_order_1 <- sum(!is.na(pairs_full$SGP_ORDER_1))
  cat(
    "  SGP_ORDER_1 valid values:",
    n_valid_order_1,
    "(",
    round(100 * n_valid_order_1 / nrow(pairs_full), 1),
    "%)\n"
  )
  if (n_valid_order_1 > 0) {
    sgp_order_1_values <- pairs_full$SGP_ORDER_1
  }
}

if (has_sgp_best) {
  n_valid_best <- sum(!is.na(pairs_full$SGP))
  cat(
    "  SGP (best) valid values:",
    n_valid_best,
    "(",
    round(100 * n_valid_best / nrow(pairs_full), 1),
    "%)\n"
  )
  if (n_valid_best > 0) {
    sgp_best_values <- pairs_full$SGP
  }
}
cat("\n")

# Fit copulas using standard workflow (creates empirical copulas properly)
cat("Fitting copulas...\n")
copula_fits <- fit_copula_from_pairs(
  scores_prior = pairs_full$SCALE_SCORE_PRIOR,
  scores_current = pairs_full$SCALE_SCORE_CURRENT,
  framework_prior = NULL,
  framework_current = NULL,
  copula_families = c("t"),
  return_best = FALSE,
  use_empirical_ranks = TRUE,
  save_copula_data = TRUE,
  output_dir = output_dir
)
cat("  Best family:", copula_fits$best_family, "\n")
cat("  Kendall's tau:", round(copula_fits$empirical_tau, 3), "\n\n")

# Load empirical copulas
cat("Loading empirical copulas...\n")
empirical_copulas <- readRDS(file.path(output_dir, "empirical_copulas.rds"))
cat("  Bernstein:", !is.null(empirical_copulas$bernstein), "\n")
cat("  Raw:", !is.null(empirical_copulas$raw), "\n\n")

# Get pseudo-observations
pseudo_obs <- copula_fits$pseudo_obs
u_obs <- pseudo_obs[, 1]
v_obs <- pseudo_obs[, 2]
t_copula <- copula_fits$results[["t"]]$copula

# Calculate SGPc values
cat("Calculating SGPc values...\n")

# Empirical SGPc (from Bernstein smoothed copula)
sgpc_emp <- sgpc_engine(
  u_obs,
  v_obs,
  empirical_copulas$bernstein,
  scale = "percentile"
)
cat("  Empirical SGPc: mean =", round(mean(sgpc_emp, na.rm = TRUE), 1), "\n")

# t-copula SGPc
sgpc_t <- sgpc_engine(u_obs, v_obs, t_copula, scale = "percentile")
cat("  t-copula SGPc: mean =", round(mean(sgpc_t, na.rm = TRUE), 1), "\n")

# Comonotonic SGPc (step function: 1 if v >= u, 99 otherwise)
sgpc_como <- sgpc_engine(u_obs, v_obs, "comonotonic", scale = "percentile")
cat(
  "  Comonotonic SGPc: mean =",
  round(mean(sgpc_como, na.rm = TRUE), 1),
  "\n\n"
)

# Create empirical grid for copula difference plot
cat("Creating empirical grid for plots...\n")
grid_size <- 100
empirical_grid <- calculate_empirical_copula_grid(
  pseudo_obs = pseudo_obs,
  grid_size = grid_size,
  method = "ecdf" # Use "ecdf" for CDF-based comparison
)
cat("Grid created:", grid_size, "x", grid_size, "\n\n")

# =============================================================================
# TEST 1: t-copula heatmap (with traditional SGP comparison)
# =============================================================================
cat(
  "========================================================================\n"
)
cat("TEST 1: SGPc Comparison Panel - Empirical vs t-copula (with heatmap)\n")
cat("        Including traditional SGP comparison lines if available\n")
cat(
  "========================================================================\n"
)

panel_result_t <- plot_sgpc_comparison_panel(
  sgpc_empirical = sgpc_emp,
  sgpc_parametric = sgpc_t,
  u_obs = u_obs,
  family = "t",
  show_stats = TRUE,
  show_cutpoints = TRUE,
  sgp_order_1 = sgp_order_1_values, # Traditional SGP (1 prior)
  sgp_best = sgp_best_values # Traditional SGP (best available)
)

if (!is.null(panel_result_t)) {
  cat("  Panel created successfully\n")
  cat("  Statistics:\n")
  cat("    KS distance:", round(panel_result_t$statistics$ks_distance, 4), "\n")
  cat("    Correlation:", round(panel_result_t$statistics$correlation, 4), "\n")
  cat(
    "    P(|diff|>10):",
    round(panel_result_t$statistics$pct_diff_gt_10 * 100, 1),
    "%\n"
  )

  # Show traditional SGP comparison stats if available (check for non-NA values)
  sgp_order_1_mean <- panel_result_t$statistics$mean_sgp_order_1
  sgp_order_1_cor <- panel_result_t$statistics$cor_empirical_vs_sgp_order_1
  if (!is.null(sgp_order_1_mean) && !is.na(sgp_order_1_mean)) {
    cat("    Mean SGP_ORDER_1:", round(sgp_order_1_mean, 1), "\n")
    if (!is.null(sgp_order_1_cor) && !is.na(sgp_order_1_cor)) {
      cat("    Cor(Empirical, SGP_ORDER_1):", round(sgp_order_1_cor, 4), "\n")
    }
  }
  sgp_best_mean <- panel_result_t$statistics$mean_sgp_best
  sgp_best_cor <- panel_result_t$statistics$cor_empirical_vs_sgp_best
  if (!is.null(sgp_best_mean) && !is.na(sgp_best_mean)) {
    cat("    Mean SGP (best):", round(sgp_best_mean, 1), "\n")
    if (!is.null(sgp_best_cor) && !is.na(sgp_best_cor)) {
      cat("    Cor(Empirical, SGP_best):", round(sgp_best_cor, 4), "\n")
    }
  }

  save_multi_format(
    panel_result_t$plot,
    file.path(output_dir, "test1_panel_t_heatmap_with_sgp"),
    width = 7,
    height = 12
  ) # Taller to accommodate summary table
  cat("\n")
} else {
  cat("  ERROR: Panel creation failed\n\n")
}

# =============================================================================
# TEST 2: Comonotonic heatmap (with traditional SGP comparison)
# =============================================================================
cat(
  "========================================================================\n"
)
cat("TEST 2: SGPc Comparison Panel - Empirical vs Comonotonic (with heatmap)\n")
cat("        Including traditional SGP comparison lines if available\n")
cat(
  "========================================================================\n"
)

panel_result_como <- plot_sgpc_comparison_panel(
  sgpc_empirical = sgpc_emp,
  sgpc_parametric = sgpc_como,
  u_obs = u_obs,
  family = "comonotonic",
  show_stats = TRUE,
  show_cutpoints = TRUE,
  sgp_order_1 = sgp_order_1_values, # Traditional SGP (1 prior)
  sgp_best = sgp_best_values # Traditional SGP (best available)
)

if (!is.null(panel_result_como)) {
  cat("  Panel created successfully\n")
  cat("  Statistics:\n")
  cat(
    "    KS distance:",
    round(panel_result_como$statistics$ks_distance, 4),
    "\n"
  )
  cat(
    "    Correlation:",
    round(panel_result_como$statistics$correlation, 4),
    "\n"
  )
  cat(
    "    P(|diff|>10):",
    round(panel_result_como$statistics$pct_diff_gt_10 * 100, 1),
    "%\n"
  )

  # Show traditional SGP comparison stats if available (check for non-NA values)
  sgp_order_1_mean <- panel_result_como$statistics$mean_sgp_order_1
  if (!is.null(sgp_order_1_mean) && !is.na(sgp_order_1_mean)) {
    cat("    Mean SGP_ORDER_1:", round(sgp_order_1_mean, 1), "\n")
  }
  sgp_best_mean <- panel_result_como$statistics$mean_sgp_best
  if (!is.null(sgp_best_mean) && !is.na(sgp_best_mean)) {
    cat("    Mean SGP (best):", round(sgp_best_mean, 1), "\n")
  }

  save_multi_format(
    panel_result_como$plot,
    file.path(output_dir, "test2_panel_comonotonic_heatmap_with_sgp"),
    width = 7,
    height = 12
  ) # Taller to accommodate summary table
  cat("\n")
} else {
  cat("  ERROR: Panel creation failed\n\n")
}

# =============================================================================
# TEST 3: Full combined plot (Copula diff + SGPc heatmap + Traditional SGP)
# =============================================================================
cat(
  "========================================================================\n"
)
cat("TEST 3: Combined Plot - Copula Diff + SGPc Heatmap (t-copula)\n")
cat("        Including traditional SGP comparison if available\n")
cat(
  "========================================================================\n"
)

combined_result_t <- plot_copula_comparison_with_sgpc(
  empirical_grid = empirical_grid,
  fitted_copula = t_copula,
  family = "t",
  sgpc_empirical = sgpc_emp,
  sgpc_parametric = sgpc_t,
  u_obs = u_obs,
  subtitle = "Mathematics | 2010 Grade 5 -> 2011 Grade 6",
  sgp_order_1 = sgp_order_1_values, # Traditional SGP (1 prior)
  sgp_best = sgp_best_values # Traditional SGP (best available)
)

if (!is.null(combined_result_t$combined_plot)) {
  cat("  Combined plot created successfully\n")

  save_multi_format(
    combined_result_t$combined_plot,
    file.path(output_dir, "test3_combined_t_heatmap_with_sgp"),
    width = 15,
    height = 10
  ) # Taller to accommodate summary table
  cat("\n")
} else {
  cat("  ERROR: Combined plot creation failed\n\n")
}

# =============================================================================
# TEST 4: Full combined plot (Comonotonic + Traditional SGP)
# =============================================================================
cat(
  "========================================================================\n"
)
cat("TEST 4: Combined Plot - Copula Diff + SGPc Heatmap (Comonotonic)\n")
cat("        Including traditional SGP comparison if available\n")
cat(
  "========================================================================\n"
)

combined_result_como <- plot_copula_comparison_with_sgpc(
  empirical_grid = empirical_grid,
  fitted_copula = NULL,
  family = "comonotonic",
  sgpc_empirical = sgpc_emp,
  sgpc_parametric = sgpc_como,
  u_obs = u_obs,
  subtitle = "Mathematics | 2010 Grade 5 -> 2011 Grade 6",
  sgp_order_1 = sgp_order_1_values, # Traditional SGP (1 prior)
  sgp_best = sgp_best_values # Traditional SGP (best available)
)

if (!is.null(combined_result_como$combined_plot)) {
  cat("  Combined plot created successfully\n")

  save_multi_format(
    combined_result_como$combined_plot,
    file.path(output_dir, "test4_combined_comonotonic_heatmap_with_sgp"),
    width = 15,
    height = 10
  ) # Taller to accommodate summary table
  cat("\n")
} else {
  cat("  ERROR: Combined plot creation failed\n\n")
}

# =============================================================================
# TEST 5: New plot_empirical_vs_sgp_comparison() function
# =============================================================================
cat(
  "========================================================================\n"
)
cat("TEST 5: SGPc vs SGP_ORDER_1 Direct Comparison (Bernstein empirical)\n")
cat("        Using new plot_empirical_vs_sgp_comparison() function\n")
cat(
  "========================================================================\n"
)

if (!is.null(sgp_order_1_values) && sum(!is.na(sgp_order_1_values)) > 10) {
  emp_vs_sgp_result <- tryCatch(
    {
      plot_empirical_vs_sgp_comparison(
        sgpc_empirical = sgpc_emp,
        sgp_order_1 = sgp_order_1_values,
        u_obs = u_obs,
        method = "bernstein",
        show_stats = TRUE,
        show_cutpoints = TRUE
      )
    },
    error = function(e) {
      cat("  ERROR:", e$message, "\n")
      NULL
    }
  )

  if (!is.null(emp_vs_sgp_result)) {
    cat("  Comparison plot created successfully\n")
    cat("  Statistics:\n")
    cat("    n valid:", emp_vs_sgp_result$statistics$n_valid, "\n")
    cat(
      "    Mean SGPc:",
      round(emp_vs_sgp_result$statistics$mean_sgpc, 1),
      "\n"
    )
    cat("    Mean SGP:", round(emp_vs_sgp_result$statistics$mean_sgp, 1), "\n")
    cat(
      "    Correlation:",
      round(emp_vs_sgp_result$statistics$correlation, 4),
      "\n"
    )
    cat(
      "    KS distance:",
      round(emp_vs_sgp_result$statistics$ks_distance, 4),
      "\n"
    )

    # Create EMPIRICAL directory structure for output
    empirical_bernstein_dir <- file.path(output_dir, "EMPIRICAL", "BERNSTEIN")
    dir.create(empirical_bernstein_dir, showWarnings = FALSE, recursive = TRUE)

    save_multi_format(
      emp_vs_sgp_result$plot,
      file.path(empirical_bernstein_dir, "bernstein_vs_SGP_ORDER_1_comparison"),
      width = 7,
      height = 12
    )
    cat("\n")
  }
} else {
  cat("  SKIPPED: Insufficient SGP_ORDER_1 data for comparison\n\n")
}

# =============================================================================
# Summary
# =============================================================================
cat(
  "========================================================================\n"
)
cat("SUMMARY\n")
cat(
  "========================================================================\n"
)
cat("\n")
cat("All outputs saved to:", output_dir, "\n")
cat("\n")

# Show new directory structure
cat("New directory structure:\n")
cat("  ", output_dir, "/\n")
cat("    ├── EMPIRICAL/\n")
cat("    │   └── BERNSTEIN/\n")
cat("    │       └── bernstein_vs_SGP_ORDER_1_comparison.pdf\n")
cat("    └── [other test outputs]\n\n")

cat("Key differences to observe:\n")
cat("  t-copula: Should have small deviations (near 0 in all cells)\n")
cat("  Comonotonic: Should have LARGE deviations\n")
cat(
  "    - Diagonal cells: Large POSITIVE deviation (comonotonic over-represents)\n"
)
cat(
  "    - Off-diagonal cells: Large NEGATIVE deviation (comonotonic under-represents)\n"
)
cat("\n")
cat(
  "The heatmap shows how the parametric copula deviates from the empirical.\n"
)
cat("Under ideal conditions, empirical should have ~10% in each cell.\n")
cat("\n")

# Traditional SGP comparison summary
cat("Traditional SGP Comparison:\n")
has_valid_sgp_order_1 <- !is.null(sgp_order_1_values)
has_valid_sgp_best <- !is.null(sgp_best_values)

if (has_valid_sgp_order_1 || has_valid_sgp_best) {
  cat("  ✓ SGP data with valid values was found and included in plots\n")
  if (has_valid_sgp_order_1) {
    cat("    - SGP_ORDER_1 (Teal dashed line): Single prior b-spline SGP\n")
  }
  if (has_valid_sgp_best) {
    cat("    - SGP (Gold dashed line): Best available (typically 2 priors)\n")
  }
  cat("\n")
  cat("  In the ECDF plot (top):\n")
  cat("    - Solid black: Empirical SGPc\n")
  cat("    - Solid magenta: Parametric SGPc\n")
  if (has_valid_sgp_order_1) {
    cat("    - Dashed teal: SGP_ORDER_1 (traditional, 1 prior)\n")
  }
  if (has_valid_sgp_best) {
    cat("    - Dashed gold: SGP (traditional, best available)\n")
  }
  cat("\n")
  cat("  In the SGPc vs SGP comparison plot (TEST 5):\n")
  cat(
    "    - Direct comparison between empirical copula SGPc and traditional SGP\n"
  )
  cat("    - Decile cross-tabulation shows agreement/disagreement patterns\n")
} else {
  cat(
    "  ✗ No valid SGP data was found for this condition - plots show SGPc only\n"
  )
  cat("    SGP columns may exist but have all NA values for this cohort.\n")
  cat("    Try a different year (not the first year in the dataset).\n")
}
cat("\n")
cat("Done!\n")
