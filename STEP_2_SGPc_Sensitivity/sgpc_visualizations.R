############################################################################
### STEP 2: SGPc Sensitivity Analysis - Visualizations
###
### Purpose: Create comprehensive visualizations comparing SGPc variants
###
### Visualizations:
###   - Scatter plots: SGP/SGPc comparisons with 45° reference
###   - Histograms: Difference distributions
###   - Heatmaps: MAD by year_span × content_area
###   - Violin plots: Differences by prior achievement quartile
###   - Bland-Altman plots: Agreement analysis
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)
require(ggplot2)
require(gridExtra)
require(wesanderson)
require(hexbin)

# Load export utilities if available
if (file.exists("functions/export_plot_utils.R")) {
  source("functions/export_plot_utils.R")
}

cat("====================================================================\n")
cat("STEP 2: SGPc SENSITIVITY VISUALIZATIONS\n")
cat("====================================================================\n\n")

############################################################################
### CONFIGURATION
############################################################################

RESULTS_DIR <- "STEP_2_SGPc_Sensitivity/results"
VIS_DIR <- file.path(RESULTS_DIR, "visualizations")
dir.create(VIS_DIR, recursive = TRUE, showWarnings = FALSE)

EXPORT_FORMATS <- c("pdf", "svg", "png")
EXPORT_DPI <- 300

# Load data
dataset_files <- list.files(RESULTS_DIR, pattern = "^sgpc_all_variants_dataset_.*\\.rds$", full.names = TRUE)

if (length(dataset_files) == 0) {
  stop("No variant results found. Run sgpc_compute_all_variants.R first.")
}

cat("Loading data from", length(dataset_files), "files...\n")
all_data_list <- lapply(dataset_files, readRDS)
all_data <- rbindlist(all_data_list, fill = TRUE)

cat("Total observations:", nrow(all_data), "\n")

# Subsample if dataset is very large (for visualization performance)
if (nrow(all_data) > 100000) {
  cat("Subsampling to 100,000 observations for visualizations...\n")
  set.seed(42)
  all_data <- all_data[sample(.N, 100000)]
}

# Add prior achievement quartile
all_data[, prior_quartile := cut(
  SCALE_SCORE_PRIOR,
  breaks = quantile(SCALE_SCORE_PRIOR, probs = 0:4/4, na.rm = TRUE),
  labels = c("Q1 (Low)", "Q2", "Q3", "Q4 (High)"),
  include.lowest = TRUE
)]

############################################################################
### HELPER FUNCTIONS
############################################################################

#' Save plot in multiple formats
save_plot <- function(plot_obj, base_filename, width = 10, height = 7) {
  if (exists("export_ggplot_multi_format")) {
    export_ggplot_multi_format(
      plot_obj = plot_obj,
      base_filename = file.path(VIS_DIR, base_filename),
      width = width,
      height = height,
      formats = EXPORT_FORMATS,
      dpi = EXPORT_DPI,
      verbose = FALSE
    )
  } else {
    # Fallback to ggsave
    for (fmt in EXPORT_FORMATS) {
      ggsave(
        filename = file.path(VIS_DIR, paste0(base_filename, ".", fmt)),
        plot = plot_obj,
        width = width,
        height = height,
        dpi = if (fmt == "png") EXPORT_DPI else NULL
      )
    }
  }
  cat("  Created:", base_filename, "\n")
}

############################################################################
### 1. SCATTER PLOTS: Variant Comparisons
############################################################################

cat("\nCreating scatter plots...\n")

# Zissou1 continuous palette (matching STEP_1 contour plots)
zissou1_colors <- colorRampPalette(wes_palette("Zissou1"))(50)

# Empirical vs Best-fit
p_emp_best <- ggplot(all_data[!is.na(sgpc_emp) & !is.na(sgpc_best)], 
                     aes(x = sgpc_emp, y = sgpc_best)) +
  geom_hex(bins = 50) +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
  scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
  coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
  labs(
    title = "Empirical vs Best-Fit Parametric SGPc",
    subtitle = sprintf("r = %.3f | n = %s", 
                       cor(all_data$sgpc_emp, all_data$sgpc_best, use = "complete.obs"),
                       format(sum(!is.na(all_data$sgpc_emp) & !is.na(all_data$sgpc_best)), big.mark = ",")),
    x = "Empirical SGPc (Non-parametric Truth)",
    y = "Best-Fit Parametric SGPc"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

save_plot(p_emp_best, "scatter_emp_vs_best", width = 8, height = 8)

# Empirical vs Canonical
p_emp_avg <- ggplot(all_data[!is.na(sgpc_emp) & !is.na(sgpc_avg)], 
                    aes(x = sgpc_emp, y = sgpc_avg)) +
  geom_hex(bins = 50) +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
  scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
  coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
  labs(
    title = "Empirical vs Canonical Averaged SGPc",
    subtitle = sprintf("r = %.3f | n = %s", 
                       cor(all_data$sgpc_emp, all_data$sgpc_avg, use = "complete.obs"),
                       format(sum(!is.na(all_data$sgpc_emp) & !is.na(all_data$sgpc_avg)), big.mark = ",")),
    x = "Empirical SGPc (Non-parametric Truth)",
    y = "Canonical Averaged SGPc (from Manifest)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

save_plot(p_emp_avg, "scatter_emp_vs_canonical", width = 8, height = 8)

# Empirical vs Gaussian (Mis-specified)
p_emp_gaussian <- ggplot(all_data[!is.na(sgpc_emp) & !is.na(sgpc_gaussian)], 
                         aes(x = sgpc_emp, y = sgpc_gaussian)) +
  geom_hex(bins = 50) +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
  scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
  coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
  labs(
    title = "Empirical vs Gaussian SGPc (Mis-specified)",
    subtitle = sprintf("r = %.3f | n = %s", 
                       cor(all_data$sgpc_emp, all_data$sgpc_gaussian, use = "complete.obs"),
                       format(sum(!is.na(all_data$sgpc_emp) & !is.na(all_data$sgpc_gaussian)), big.mark = ",")),
    x = "Empirical SGPc (Non-parametric Truth)",
    y = "Gaussian SGPc (No Tail Dependence)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

save_plot(p_emp_gaussian, "scatter_emp_vs_gaussian", width = 8, height = 8)

# Empirical vs Comonotonic (TAMP)
p_emp_comon <- ggplot(all_data[!is.na(sgpc_emp) & !is.na(sgpc_comonotonic)], 
                      aes(x = sgpc_emp, y = sgpc_comonotonic)) +
  geom_hex(bins = 50) +
  geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
  scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
  coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
  labs(
    title = "Empirical vs Comonotonic SGPc (TAMP Assumption)",
    subtitle = sprintf("r = %.3f | n = %s", 
                       cor(all_data$sgpc_emp, all_data$sgpc_comonotonic, use = "complete.obs"),
                       format(sum(!is.na(all_data$sgpc_emp) & !is.na(all_data$sgpc_comonotonic)), big.mark = ",")),
    x = "Empirical SGPc (Non-parametric Truth)",
    y = "Comonotonic SGPc (Perfect Dependence)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

save_plot(p_emp_comon, "scatter_emp_vs_comonotonic", width = 8, height = 8)

############################################################################
### 2. HISTOGRAMS: Difference Distributions
############################################################################

cat("\nCreating difference histograms...\n")

# Prepare difference data
diff_data <- data.table(
  diff_emp_best = all_data$sgpc_emp - all_data$sgpc_best,
  diff_emp_avg = all_data$sgpc_emp - all_data$sgpc_avg,
  diff_emp_gaussian = all_data$sgpc_emp - all_data$sgpc_gaussian,
  diff_emp_comon = all_data$sgpc_emp - all_data$sgpc_comonotonic
)

# Reshape for faceted plot
diff_long <- melt(diff_data, measure.vars = names(diff_data), 
                  variable.name = "comparison", value.name = "difference")

diff_long[, comparison := factor(comparison, 
                                 levels = c("diff_emp_best", "diff_emp_avg", 
                                           "diff_emp_gaussian", "diff_emp_comon"),
                                 labels = c("Empirical - Best-Fit",
                                           "Empirical - Canonical",
                                           "Empirical - Gaussian",
                                           "Empirical - Comonotonic"))]

p_diff_hist <- ggplot(diff_long[!is.na(difference)], aes(x = difference)) +
  geom_histogram(bins = 100, fill = "steelblue", color = "white", alpha = 0.7) +
  geom_vline(xintercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
  facet_wrap(~ comparison, scales = "free_y", ncol = 2) +
  labs(
    title = "Distribution of SGPc Differences (Empirical - Other Variants)",
    x = "Difference in Percentile Points",
    y = "Count"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold"),
    strip.text = element_text(face = "bold", size = 10)
  )

save_plot(p_diff_hist, "histogram_differences", width = 12, height = 8)

############################################################################
### 3. HEATMAP: MAD by Year Span × Content Area
############################################################################

cat("\nCreating heatmaps...\n")

# Compute MAD by stratum
mad_by_stratum <- all_data[, .(
  mad_emp_best = mean(abs(sgpc_emp - sgpc_best), na.rm = TRUE),
  mad_emp_avg = mean(abs(sgpc_emp - sgpc_avg), na.rm = TRUE),
  mad_emp_gaussian = mean(abs(sgpc_emp - sgpc_gaussian), na.rm = TRUE),
  n_obs = .N
), by = .(year_span, content_area)]

# Heatmap for Empirical vs Best-Fit
p_heatmap_best <- ggplot(mad_by_stratum, aes(x = factor(year_span), y = content_area, fill = mad_emp_best)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.1f", mad_emp_best)), color = "white", fontface = "bold") +
  scale_fill_gradient2(low = "darkgreen", mid = "orange", high = "darkred",
                       midpoint = 5, limits = c(0, NA),
                       name = "MAD\n(percentile\npoints)") +
  labs(
    title = "Mean Absolute Difference: Empirical vs Best-Fit Parametric",
    subtitle = "By Year Span and Content Area",
    x = "Year Span (years between assessments)",
    y = "Content Area"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

save_plot(p_heatmap_best, "heatmap_mad_emp_vs_best", width = 10, height = 6)

# Heatmap for Empirical vs Canonical
p_heatmap_avg <- ggplot(mad_by_stratum, aes(x = factor(year_span), y = content_area, fill = mad_emp_avg)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.1f", mad_emp_avg)), color = "white", fontface = "bold") +
  scale_fill_gradient2(low = "darkgreen", mid = "orange", high = "darkred",
                       midpoint = 7, limits = c(0, NA),
                       name = "MAD\n(percentile\npoints)") +
  labs(
    title = "Mean Absolute Difference: Empirical vs Canonical Averaged",
    subtitle = "By Year Span and Content Area",
    x = "Year Span (years between assessments)",
    y = "Content Area"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

save_plot(p_heatmap_avg, "heatmap_mad_emp_vs_canonical", width = 10, height = 6)

############################################################################
### 4. VIOLIN PLOTS: Differences by Prior Achievement Quartile
############################################################################

cat("\nCreating violin plots...\n")

# Prepare data for violin plots
violin_data <- melt(
  all_data[!is.na(prior_quartile)],
  id.vars = "prior_quartile",
  measure.vars = c("diff_emp_best" = "sgpc_emp - sgpc_best", 
                   "diff_emp_avg" = "sgpc_emp - sgpc_avg"),
  variable.name = "comparison"
)

# Calculate differences on-the-fly
violin_prep <- all_data[!is.na(prior_quartile), .(
  prior_quartile,
  diff_emp_best = sgpc_emp - sgpc_best,
  diff_emp_avg = sgpc_emp - sgpc_avg,
  diff_emp_gaussian = sgpc_emp - sgpc_gaussian
)]

violin_long <- melt(violin_prep, id.vars = "prior_quartile", 
                    variable.name = "comparison", value.name = "difference")

violin_long[, comparison := factor(comparison,
                                   levels = c("diff_emp_best", "diff_emp_avg", "diff_emp_gaussian"),
                                   labels = c("Empirical - Best-Fit",
                                             "Empirical - Canonical",
                                             "Empirical - Gaussian"))]

p_violin <- ggplot(violin_long[!is.na(difference)], 
                   aes(x = prior_quartile, y = difference, fill = prior_quartile)) +
  geom_violin(alpha = 0.7, draw_quantiles = c(0.25, 0.5, 0.75)) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  facet_wrap(~ comparison, scales = "free_y", ncol = 3) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "SGPc Differences by Prior Achievement Quartile",
    x = "Prior Achievement Quartile",
    y = "Difference in Percentile Points",
    fill = "Quartile"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold"),
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold")
  )

save_plot(p_violin, "violin_by_prior_quartile", width = 14, height = 6)

############################################################################
### 5. BLAND-ALTMAN PLOTS
############################################################################

cat("\nCreating Bland-Altman plots...\n")

# Empirical vs Best-Fit
ba_data_best <- all_data[!is.na(sgpc_emp) & !is.na(sgpc_best), .(
  mean = (sgpc_emp + sgpc_best) / 2,
  diff = sgpc_emp - sgpc_best
)]

p_ba_best <- ggplot(ba_data_best, aes(x = mean, y = diff)) +
  geom_hex(bins = 50) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
  geom_hline(yintercept = mean(ba_data_best$diff, na.rm = TRUE), 
             color = "blue", linetype = "solid", linewidth = 1) +
  geom_hline(yintercept = mean(ba_data_best$diff, na.rm = TRUE) + 1.96 * sd(ba_data_best$diff, na.rm = TRUE),
             color = "blue", linetype = "dotted", linewidth = 0.8) +
  geom_hline(yintercept = mean(ba_data_best$diff, na.rm = TRUE) - 1.96 * sd(ba_data_best$diff, na.rm = TRUE),
             color = "blue", linetype = "dotted", linewidth = 0.8) +
  scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
  labs(
    title = "Bland-Altman Plot: Empirical vs Best-Fit Parametric",
    subtitle = sprintf("Mean difference = %.2f | SD = %.2f",
                       mean(ba_data_best$diff, na.rm = TRUE),
                       sd(ba_data_best$diff, na.rm = TRUE)),
    x = "Mean of Two Methods",
    y = "Difference (Empirical - Best-Fit)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

save_plot(p_ba_best, "bland_altman_emp_vs_best", width = 10, height = 7)

############################################################################
### COMPLETION
############################################################################

cat("\n====================================================================\n")
cat("VISUALIZATIONS COMPLETE\n")
cat("====================================================================\n\n")

cat("Output directory:", VIS_DIR, "\n")
cat("Files created:\n")
cat("  - scatter_emp_vs_*.{pdf,svg,png}\n")
cat("  - histogram_differences.{pdf,svg,png}\n")
cat("  - heatmap_mad_*.{pdf,svg,png}\n")
cat("  - violin_by_prior_quartile.{pdf,svg,png}\n")
cat("  - bland_altman_*.{pdf,svg,png}\n\n")
