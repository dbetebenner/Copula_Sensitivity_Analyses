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

cat(sprintf("Total observations: %s\n", format(nrow(all_data), big.mark = ",")))

# Full dataset is used for hex-binned plots (scatter, Bland-Altman, heatmaps,
# histograms).  geom_hex bins millions of rows into ~2,500 hexes so performance
# and file size stay manageable.  Only the violin-plot section (KDE-based)
# receives a targeted subsample below.

# Add prior achievement quartile (needed by violin section)
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
  geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
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
  geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
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
  geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
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
  geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
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

# Empirical vs Gumbel (Mis-specified: upper-tail only)
if ("sgpc_gumbel" %in% names(all_data) && sum(!is.na(all_data$sgpc_gumbel)) > 0) {
  p_emp_gumbel <- ggplot(all_data[!is.na(sgpc_emp) & !is.na(sgpc_gumbel)], 
                          aes(x = sgpc_emp, y = sgpc_gumbel)) +
    geom_hex(bins = 50) +
    geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
    labs(
      title = "Empirical vs Gumbel SGPc (Asymmetric Mis-specification)",
      subtitle = sprintf("r = %.3f | n = %s", 
                         cor(all_data$sgpc_emp, all_data$sgpc_gumbel, use = "complete.obs"),
                         format(sum(!is.na(all_data$sgpc_emp) & !is.na(all_data$sgpc_gumbel)), big.mark = ",")),
      x = "Empirical SGPc (Non-parametric Truth)",
      y = "Gumbel SGPc (Upper Tail Only)"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  save_plot(p_emp_gumbel, "scatter_emp_vs_gumbel", width = 8, height = 8)
}

# Empirical vs Frank (Mis-specified: no tail dependence)
if ("sgpc_frank" %in% names(all_data) && sum(!is.na(all_data$sgpc_frank)) > 0) {
  p_emp_frank <- ggplot(all_data[!is.na(sgpc_emp) & !is.na(sgpc_frank)], 
                         aes(x = sgpc_emp, y = sgpc_frank)) +
    geom_hex(bins = 50) +
    geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
    labs(
      title = "Empirical vs Frank SGPc (Symmetric, No Tails)",
      subtitle = sprintf("r = %.3f | n = %s", 
                         cor(all_data$sgpc_emp, all_data$sgpc_frank, use = "complete.obs"),
                         format(sum(!is.na(all_data$sgpc_emp) & !is.na(all_data$sgpc_frank)), big.mark = ",")),
      x = "Empirical SGPc (Non-parametric Truth)",
      y = "Frank SGPc (Symmetric, No Tail Dependence)"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  save_plot(p_emp_frank, "scatter_emp_vs_frank", width = 8, height = 8)
}

# Empirical vs Traditional SGP (Operational Benchmark)
if ("sgp_traditional" %in% names(all_data) && sum(!is.na(all_data$sgp_traditional)) > 0) {
  p_emp_trad <- ggplot(all_data[!is.na(sgpc_emp) & !is.na(sgp_traditional)], 
                        aes(x = sgpc_emp, y = sgp_traditional)) +
    geom_hex(bins = 50) +
    geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
    labs(
      title = "Empirical SGPc vs Traditional SGP (B-Spline QR)",
      subtitle = sprintf("r = %.3f | n = %s", 
                         cor(all_data$sgpc_emp, all_data$sgp_traditional, use = "complete.obs"),
                         format(sum(!is.na(all_data$sgpc_emp) & !is.na(all_data$sgp_traditional)), big.mark = ",")),
      x = "Empirical SGPc (Copula-based)",
      y = "Traditional SGP (B-Spline Quantile Regression)"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  save_plot(p_emp_trad, "scatter_emp_vs_traditional", width = 8, height = 8)
  
  # Best-Fit vs Traditional SGP
  p_best_trad <- ggplot(all_data[!is.na(sgpc_best) & !is.na(sgp_traditional)], 
                         aes(x = sgpc_best, y = sgp_traditional)) +
    geom_hex(bins = 50) +
    geom_abline(slope = 1, intercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    coord_equal(xlim = c(1, 99), ylim = c(1, 99)) +
    labs(
      title = "Best-Fit Parametric SGPc vs Traditional SGP",
      subtitle = sprintf("r = %.3f | n = %s", 
                         cor(all_data$sgpc_best, all_data$sgp_traditional, use = "complete.obs"),
                         format(sum(!is.na(all_data$sgpc_best) & !is.na(all_data$sgp_traditional)), big.mark = ",")),
      x = "Best-Fit Parametric SGPc",
      y = "Traditional SGP (B-Spline Quantile Regression)"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  save_plot(p_best_trad, "scatter_best_vs_traditional", width = 8, height = 8)
}

############################################################################
### 2. HISTOGRAMS: Difference Distributions
############################################################################

cat("\nCreating difference histograms...\n")

# Prepare difference data (all variants)
# Order: Best-fit, Canonical, Gaussian, Comonotonic, Gumbel, Frank, Clayton, t, Traditional SGP, Best-Canonical
diff_data <- data.table(
  diff_emp_best = all_data$sgpc_emp - all_data$sgpc_best,
  diff_emp_avg = all_data$sgpc_emp - all_data$sgpc_avg,
  diff_emp_gaussian = all_data$sgpc_emp - all_data$sgpc_gaussian,
  diff_emp_comon = all_data$sgpc_emp - all_data$sgpc_comonotonic
)

# Add Gumbel, Frank, Clayton, t, Traditional if available
if ("sgpc_gumbel" %in% names(all_data)) {
  diff_data[, diff_emp_gumbel := all_data$sgpc_emp - all_data$sgpc_gumbel]
}
if ("sgpc_frank" %in% names(all_data)) {
  diff_data[, diff_emp_frank := all_data$sgpc_emp - all_data$sgpc_frank]
}
if ("sgpc_clayton" %in% names(all_data)) {
  diff_data[, diff_emp_clayton := all_data$sgpc_emp - all_data$sgpc_clayton]
}
if ("sgpc_t" %in% names(all_data)) {
  diff_data[, diff_emp_t := all_data$sgpc_emp - all_data$sgpc_t]
}
if ("sgp_traditional" %in% names(all_data)) {
  diff_data[, diff_emp_trad := all_data$sgpc_emp - all_data$sgp_traditional]
}
# Add Best-Fit vs Canonical comparison (last position, bottom right)
if ("sgpc_best" %in% names(all_data) && "sgpc_avg" %in% names(all_data)) {
  diff_data[, diff_best_canon := all_data$sgpc_best - all_data$sgpc_avg]
}

# Reshape for faceted plot
diff_long <- melt(diff_data, measure.vars = names(diff_data), 
                  variable.name = "comparison", value.name = "difference")

# Define levels and labels for 10 histograms (5 rows x 2 columns)
level_names <- c("diff_emp_best", "diff_emp_avg", "diff_emp_gaussian", "diff_emp_comon",
                 "diff_emp_gumbel", "diff_emp_frank", "diff_emp_clayton", "diff_emp_t",
                 "diff_emp_trad", "diff_best_canon")
label_names <- c("Empirical - Best-Fit", "Empirical - Canonical",
                 "Empirical - Gaussian", "Empirical - Comonotonic",
                 "Empirical - Gumbel", "Empirical - Frank", "Empirical - Clayton", 
                 "Empirical - t", "Empirical - Traditional SGP", "Best-Fit - Canonical")

# Keep only levels that exist
existing_levels <- intersect(level_names, levels(diff_long$comparison))
existing_labels <- label_names[match(existing_levels, level_names)]

diff_long[, comparison := factor(comparison, levels = existing_levels, labels = existing_labels)]

p_diff_hist <- ggplot(diff_long[!is.na(difference)], aes(x = difference)) +
  geom_histogram(bins = 100, fill = "steelblue", color = "white", alpha = 0.7) +
  geom_vline(xintercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
  facet_wrap(~ comparison, scales = "free_y", ncol = 2) +
  labs(
    title = "Distribution of SGPc Differences",
    x = "Difference in Percentile Points",
    y = "Count"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold"),
    strip.text = element_text(face = "bold", size = 10)
  )

save_plot(p_diff_hist, "histogram_differences", width = 11, height = 16)

############################################################################
### 3. HEATMAP: MAD by Year Span × Content Area
############################################################################

cat("\nCreating heatmaps...\n")

# Compute MAD by stratum (all variants)
mad_by_stratum <- all_data[, {
  result <- list(
    mad_emp_best = mean(abs(sgpc_emp - sgpc_best), na.rm = TRUE),
    mad_emp_avg = mean(abs(sgpc_emp - sgpc_avg), na.rm = TRUE),
    mad_emp_gaussian = mean(abs(sgpc_emp - sgpc_gaussian), na.rm = TRUE),
    n_obs = .N
  )
  if ("sgpc_gumbel" %in% names(.SD)) result$mad_emp_gumbel <- mean(abs(sgpc_emp - sgpc_gumbel), na.rm = TRUE)
  if ("sgpc_frank" %in% names(.SD)) result$mad_emp_frank <- mean(abs(sgpc_emp - sgpc_frank), na.rm = TRUE)
  if ("sgp_traditional" %in% names(.SD)) result$mad_emp_trad <- mean(abs(sgpc_emp - sgp_traditional), na.rm = TRUE)
  result
}, by = .(year_span, content_area)]

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

# Subsample for violin KDE performance (KDE converges well below 200K points)
VIOLIN_MAX <- 200000L
if (nrow(all_data) > VIOLIN_MAX) {
  cat(sprintf("  Subsampling to %s observations for violin KDE...\n",
              format(VIOLIN_MAX, big.mark = ",")))
  set.seed(42)
  violin_data <- all_data[sample(.N, VIOLIN_MAX)]
} else {
  violin_data <- all_data
}

# Calculate differences first, then melt (all variants)
violin_cols <- list(
  diff_emp_best = c("sgpc_emp", "sgpc_best"),
  diff_emp_avg = c("sgpc_emp", "sgpc_avg"),
  diff_emp_gaussian = c("sgpc_emp", "sgpc_gaussian")
)

# Add optional variants
if ("sgpc_gumbel" %in% names(all_data)) violin_cols$diff_emp_gumbel <- c("sgpc_emp", "sgpc_gumbel")
if ("sgpc_frank" %in% names(all_data)) violin_cols$diff_emp_frank <- c("sgpc_emp", "sgpc_frank")
if ("sgp_traditional" %in% names(all_data)) violin_cols$diff_emp_trad <- c("sgpc_emp", "sgp_traditional")

violin_prep <- violin_data[!is.na(prior_quartile), "prior_quartile"]
for (cn in names(violin_cols)) {
  v1 <- violin_cols[[cn]][1]
  v2 <- violin_cols[[cn]][2]
  if (v1 %in% names(violin_data) && v2 %in% names(violin_data)) {
    violin_prep[, (cn) := violin_data[!is.na(prior_quartile)][[v1]] - violin_data[!is.na(prior_quartile)][[v2]]]
  }
}

diff_cols <- setdiff(names(violin_prep), "prior_quartile")
violin_long <- melt(violin_prep, id.vars = "prior_quartile", 
                    measure.vars = diff_cols,
                    variable.name = "comparison", value.name = "difference")

violin_level_map <- c(
  diff_emp_best = "Empirical - Best-Fit",
  diff_emp_avg = "Empirical - Canonical",
  diff_emp_gaussian = "Empirical - Gaussian",
  diff_emp_gumbel = "Empirical - Gumbel",
  diff_emp_frank = "Empirical - Frank",
  diff_emp_trad = "Empirical - Traditional SGP"
)
existing_violin_levels <- intersect(names(violin_level_map), diff_cols)
violin_long[, comparison := factor(comparison,
                                   levels = existing_violin_levels,
                                   labels = violin_level_map[existing_violin_levels])]

p_violin <- ggplot(violin_long[!is.na(difference)], 
                   aes(x = prior_quartile, y = difference, fill = prior_quartile)) +
  geom_violin(alpha = 0.7, quantiles = c(0.25, 0.5, 0.75)) +
  stat_summary(fun = "median", geom = "point", size = 2, color = "black") +
  geom_hline(yintercept = 0, color = "#F21A00", linetype = "dashed") +
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

# Free the subsampled copy used only for violins
if (exists("violin_data")) rm(violin_data)

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
  geom_hline(yintercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
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
  theme(
    plot.title = element_text(face = "bold"),
    plot.margin = margin(10, 10, 10, 10, "pt")
  )

save_plot(p_ba_best, "bland_altman_emp_vs_best", width = 10, height = 7)

# Bland-Altman: Empirical vs Traditional SGP (capstone comparison)
if ("sgp_traditional" %in% names(all_data) && sum(!is.na(all_data$sgp_traditional)) > 0) {
  ba_data_trad <- all_data[!is.na(sgpc_emp) & !is.na(sgp_traditional), .(
    mean = (sgpc_emp + sgp_traditional) / 2,
    diff = sgpc_emp - sgp_traditional
  )]
  
  p_ba_trad <- ggplot(ba_data_trad, aes(x = mean, y = diff)) +
    geom_hex(bins = 50) +
    geom_hline(yintercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    geom_hline(yintercept = mean(ba_data_trad$diff, na.rm = TRUE), 
               color = "blue", linetype = "solid", linewidth = 1) +
    geom_hline(yintercept = mean(ba_data_trad$diff, na.rm = TRUE) + 1.96 * sd(ba_data_trad$diff, na.rm = TRUE),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    geom_hline(yintercept = mean(ba_data_trad$diff, na.rm = TRUE) - 1.96 * sd(ba_data_trad$diff, na.rm = TRUE),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    labs(
      title = "Bland-Altman Plot: Empirical SGPc vs Traditional SGP",
      subtitle = sprintf("Mean diff = %.2f | SD = %.2f | Capstone: copula-based vs B-spline QR",
                         mean(ba_data_trad$diff, na.rm = TRUE),
                         sd(ba_data_trad$diff, na.rm = TRUE)),
      x = "Mean of Two Methods",
      y = "Difference (Empirical SGPc - Traditional SGP)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold"),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )
  
  save_plot(p_ba_trad, "bland_altman_emp_vs_traditional", width = 10, height = 7)
}

# Bland-Altman: Empirical vs Gumbel
if ("sgpc_gumbel" %in% names(all_data) && sum(!is.na(all_data$sgpc_gumbel)) > 0) {
  ba_data_gumbel <- all_data[!is.na(sgpc_emp) & !is.na(sgpc_gumbel), .(
    mean = (sgpc_emp + sgpc_gumbel) / 2,
    diff = sgpc_emp - sgpc_gumbel
  )]
  
  p_ba_gumbel <- ggplot(ba_data_gumbel, aes(x = mean, y = diff)) +
    geom_hex(bins = 50) +
    geom_hline(yintercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    geom_hline(yintercept = mean(ba_data_gumbel$diff, na.rm = TRUE), 
               color = "blue", linetype = "solid", linewidth = 1) +
    geom_hline(yintercept = mean(ba_data_gumbel$diff, na.rm = TRUE) + 1.96 * sd(ba_data_gumbel$diff, na.rm = TRUE),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    geom_hline(yintercept = mean(ba_data_gumbel$diff, na.rm = TRUE) - 1.96 * sd(ba_data_gumbel$diff, na.rm = TRUE),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    labs(
      title = "Bland-Altman Plot: Empirical vs Gumbel SGPc",
      subtitle = sprintf("Mean diff = %.2f | SD = %.2f",
                         mean(ba_data_gumbel$diff, na.rm = TRUE),
                         sd(ba_data_gumbel$diff, na.rm = TRUE)),
      x = "Mean of Two Methods",
      y = "Difference (Empirical - Gumbel)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold"),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )
  
  save_plot(p_ba_gumbel, "bland_altman_emp_vs_gumbel", width = 10, height = 7)
}

# Bland-Altman: Empirical vs Gaussian
if ("sgpc_gaussian" %in% names(all_data) && sum(!is.na(all_data$sgpc_gaussian)) > 0) {
  ba_data_gaussian <- all_data[!is.na(sgpc_emp) & !is.na(sgpc_gaussian), .(
    mean = (sgpc_emp + sgpc_gaussian) / 2,
    diff = sgpc_emp - sgpc_gaussian
  )]
  
  p_ba_gaussian <- ggplot(ba_data_gaussian, aes(x = mean, y = diff)) +
    geom_hex(bins = 50) +
    geom_hline(yintercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    geom_hline(yintercept = mean(ba_data_gaussian$diff, na.rm = TRUE), 
               color = "blue", linetype = "solid", linewidth = 1) +
    geom_hline(yintercept = mean(ba_data_gaussian$diff, na.rm = TRUE) + 1.96 * sd(ba_data_gaussian$diff, na.rm = TRUE),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    geom_hline(yintercept = mean(ba_data_gaussian$diff, na.rm = TRUE) - 1.96 * sd(ba_data_gaussian$diff, na.rm = TRUE),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    labs(
      title = "Bland-Altman Plot: Empirical vs Gaussian SGPc",
      subtitle = sprintf("Mean diff = %.2f | SD = %.2f",
                         mean(ba_data_gaussian$diff, na.rm = TRUE),
                         sd(ba_data_gaussian$diff, na.rm = TRUE)),
      x = "Mean of Two Methods",
      y = "Difference (Empirical - Gaussian)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold"),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )
  
  save_plot(p_ba_gaussian, "bland_altman_emp_vs_gaussian", width = 10, height = 7)
}

############################################################################
### COMPLETION
############################################################################

cat("\n====================================================================\n")
cat("VISUALIZATIONS COMPLETE\n")
cat("====================================================================\n\n")

cat("Output directory:", VIS_DIR, "\n")
cat("Files created:\n")
cat("  - scatter_emp_vs_*.{pdf,svg,png} (including gumbel, frank, traditional)\n")
cat("  - scatter_best_vs_traditional.{pdf,svg,png}\n")
cat("  - histogram_differences.{pdf,svg,png} (all 7 comparison pairs)\n")
cat("  - heatmap_mad_*.{pdf,svg,png}\n")
cat("  - violin_by_prior_quartile.{pdf,svg,png} (all variants)\n")
cat("  - bland_altman_*.{pdf,svg,png} (including traditional, gumbel)\n\n")
