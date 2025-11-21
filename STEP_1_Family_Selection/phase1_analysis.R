############################################################################
### PHASE 1: ANALYSIS AND DECISION
### Analyze copula family selection patterns and determine Phase 2 families
############################################################################

require(data.table)
require(grid)
require(wesanderson)  # For Zissou1 color palette

# For violin plots
if (!requireNamespace("vioplot", quietly = TRUE)) {
  install.packages("vioplot")
}
require(vioplot)

# For ggplot2 visualizations
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  install.packages("ggplot2")
}
require(ggplot2)

if (!requireNamespace("scales", quietly = TRUE)) {
  install.packages("scales")
}
require(scales)

# For beeswarm plots
if (!requireNamespace("ggbeeswarm", quietly = TRUE)) {
  install.packages("ggbeeswarm")
}
require(ggbeeswarm)

################################################################################
### MULTI-FORMAT EXPORT INFRASTRUCTURE
################################################################################

# Source multi-format export utilities
if (file.exists("functions/export_plot_utils.R")) {
  source("functions/export_plot_utils.R")
  cat("✓ Loaded export_plot_utils.R\n")
} else if (file.exists("../functions/export_plot_utils.R")) {
  source("../functions/export_plot_utils.R")
  cat("✓ Loaded export_plot_utils.R\n")
}

# Multi-format export configuration
EXPORT_FORMATS_PHASE1 <- c("pdf", "svg", "png")
EXPORT_DPI_PHASE1 <- 300
EXPORT_VERBOSE_PHASE1 <- FALSE

# Helper function for ggplot multi-format export
save_phase1_plot <- function(plot_obj, base_filename, width, height) {
  if (exists("export_ggplot_multi_format")) {
    export_ggplot_multi_format(
      plot_obj = plot_obj,
      base_filename = base_filename,
      width = width,
      height = height,
      formats = EXPORT_FORMATS_PHASE1,
      dpi = EXPORT_DPI_PHASE1,
      verbose = EXPORT_VERBOSE_PHASE1
    )
  } else {
    # Fallback to ggsave
    ggsave(paste0(base_filename, ".pdf"), plot_obj, 
           width = width, height = height)
    cat("  Created:", paste0(base_filename, ".pdf"), "\n")
  }
}

# Helper function for base R multi-format export
save_phase1_base_plot <- function(plot_code, base_filename, width, height) {
  if (exists("export_plot_multi_format")) {
    export_plot_multi_format(
      plot_expr = plot_code,
      base_filename = base_filename,
      width = width,
      height = height,
      formats = EXPORT_FORMATS_PHASE1,
      png_res = EXPORT_DPI_PHASE1,
      verbose = EXPORT_VERBOSE_PHASE1
    )
  } else {
    # Fallback to pdf()
    pdf(paste0(base_filename, ".pdf"), width = width, height = height)
    eval(plot_code)
    dev.off()
    cat("  Created:", paste0(base_filename, ".pdf"), "\n")
  }
}

cat("====================================================================\n")
cat("PHASE 1: FAMILY SELECTION ANALYSIS\n")
cat("====================================================================\n\n")

# Load Phase 1 combined results (from all datasets)
results_file <- "STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv"

if (!file.exists(results_file)) {
  stop("Phase 1 combined results not found! This file should be created after combining all dataset results.")
}

results <- fread(results_file)

cat("Loaded results from:", results_file, "\n")
cat("Conditions tested:", uniqueN(results$condition_id), "\n")
cat("Total fits:", nrow(results), "\n\n")

# CRITICAL FIX: Recalculate delta_aic_vs_best with correct grouping
# Must group by (dataset_id, condition_id) to ensure uniqueness across datasets
# Without dataset_id, conditions with the same ID across different datasets 
# would incorrectly share the same minimum AIC
cat("Recalculating delta AIC with proper dataset grouping...\n")
results[, delta_aic_vs_best := aic - min(aic), by = .(dataset_id, condition_id)]
results[, delta_bic_vs_best := bic - min(bic), by = .(dataset_id, condition_id)]

# Calculate AIC weights for interpretability
# AIC weight = exp(-delta_i/2) / sum(exp(-delta_j/2))
# Represents the probability that model i is the best model
# For very large delta values (e.g., comonotonic), exp(-delta/2) ≈ 0
cat("Calculating AIC weights...\n")
results[, aic_weight := {
  # Use pmax to avoid numerical underflow for very large deltas
  exp_vals <- exp(-pmax(delta_aic_vs_best, 0) / 2)
  exp_vals / sum(exp_vals)
}, by = .(dataset_id, condition_id)]

cat("Delta AIC range:", range(results$delta_aic_vs_best), "\n")
cat("AIC weight range:", range(results$aic_weight), "\n\n")

# Output directory for combined results
output_dir <- "STEP_1_Family_Selection/results/dataset_all"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

################################################################################
### ANALYSIS 1: OVERALL WINNER
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 1: OVERALL FAMILY SELECTION FREQUENCY\n")
cat("====================================================================\n\n")

# Count selection frequency by AIC (group by dataset_id + condition_id for uniqueness)
selection_freq_aic <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id)][, .N, by = family]
setorder(selection_freq_aic, -N)
selection_freq_aic[, pct := round(100 * N / sum(N), 1)]

cat("Selection frequency by AIC:\n")
print(selection_freq_aic)
cat("\n")

# Count selection frequency by BIC (group by dataset_id + condition_id for uniqueness)
selection_freq_bic <- results[, .SD[which.min(bic)], by = .(dataset_id, condition_id)][, .N, by = family]
setorder(selection_freq_bic, -N)
selection_freq_bic[, pct := round(100 * N / sum(N), 1)]

cat("Selection frequency by BIC:\n")
print(selection_freq_bic)
cat("\n")

# Mean AIC advantage and weights
mean_aic_by_family <- results[, .(
  mean_aic = mean(aic),
  sd_aic = sd(aic),
  mean_delta_aic = mean(delta_aic_vs_best),
  mean_aic_weight = mean(aic_weight),
  median_aic_weight = median(aic_weight),
  n_times_best = sum(delta_aic_vs_best == 0)
), by = family]
setorder(mean_aic_by_family, mean_aic)

cat("Mean AIC, Delta AIC, and AIC Weights by family:\n")
cat("(AIC weight = probability model is best; ranges 0-1)\n")
print(mean_aic_by_family)
cat("\n")

################################################################################
### ANALYSIS 2: PATTERN BY GRADE SPAN
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 2: FAMILY SELECTION BY GRADE SPAN\n")
cat("====================================================================\n\n")

# Best family by year span
by_span <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id, year_span)][
  , .(
    winner = names(sort(table(family), decreasing = TRUE)[1]),
    t_selected = sum(family == "t"),
    gaussian_selected = sum(family == "gaussian"),
    total = .N
  ), by = year_span]

by_span[, t_pct := round(100 * t_selected / total, 1)]
by_span[, gaussian_pct := round(100 * gaussian_selected / total, 1)]
setorder(by_span, year_span)

cat("Selection patterns by grade span:\n")
print(by_span)
cat("\n")

# Mean delta AIC: t-copula vs Gaussian by grade span
t_vs_gaussian <- merge(
  results[family == "t", .(dataset_id, condition_id, year_span, aic_t = aic)],
  results[family == "gaussian", .(dataset_id, condition_id, aic_gaussian = aic)],
  by = c("dataset_id", "condition_id")
)
t_vs_gaussian[, delta_aic := aic_gaussian - aic_t]

span_comparison <- t_vs_gaussian[, .(
  mean_delta_aic = mean(delta_aic),
  sd_delta_aic = sd(delta_aic),
  t_better_count = sum(delta_aic > 0),
  total = .N
), by = year_span]
span_comparison[, t_better_pct := round(100 * t_better_count / total, 1)]
setorder(span_comparison, year_span)

cat("T-copula vs Gaussian by grade span (positive = t better):\n")
print(span_comparison)
cat("\n")

################################################################################
### ANALYSIS 3: PATTERN BY CONTENT AREA
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 3: FAMILY SELECTION BY CONTENT AREA\n")
cat("====================================================================\n\n")

by_content <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id, content_area)][
  , .(
    winner = names(sort(table(family), decreasing = TRUE)[1]),
    t_selected = sum(family == "t"),
    gaussian_selected = sum(family == "gaussian"),
    total = .N
  ), by = content_area]

by_content[, t_pct := round(100 * t_selected / total, 1)]
setorder(by_content, -t_pct)

cat("Selection patterns by content area:\n")
print(by_content)
cat("\n")

################################################################################
### ANALYSIS 4: TAIL DEPENDENCE ANALYSIS
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 4: TAIL DEPENDENCE BY FAMILY AND GRADE SPAN\n")
cat("====================================================================\n\n")

# Check for required columns
required_cols <- c("tail_dep_lower", "tail_dep_upper", "tau", "family", "year_span")
missing_cols <- setdiff(required_cols, names(results))
if (length(missing_cols) > 0) {
  cat("Warning: Missing columns in results:", paste(missing_cols, collapse = ", "), "\n")
  cat("Available columns:", paste(names(results), collapse = ", "), "\n\n")
  cat("Skipping tail dependence analysis.\n\n")
  tail_analysis <- data.table()
} else {
  # Ensure numeric columns
  results[, tail_dep_lower := as.numeric(tail_dep_lower)]
  results[, tail_dep_upper := as.numeric(tail_dep_upper)]
  results[, tau := as.numeric(tau)]
  
  tail_analysis <- results[, .(
    mean_tail_lower = mean(tail_dep_lower, na.rm = TRUE),
    mean_tail_upper = mean(tail_dep_upper, na.rm = TRUE),
    mean_tau = mean(tau, na.rm = TRUE),
    mean_aic_weight = mean(aic_weight, na.rm = TRUE),
    median_aic_weight = median(aic_weight, na.rm = TRUE),
    n = .N
  ), by = .(family, year_span)]
  setorder(tail_analysis, year_span, -mean_aic_weight)
  
  cat("Tail dependence patterns (sorted by mean AIC weight):\n")
  cat("(Higher AIC weight = better fit)\n")
  print(tail_analysis)
  cat("\n")
}

################################################################################
### VISUALIZATIONS
################################################################################

cat("====================================================================\n")
cat("GENERATING VISUALIZATIONS\n")
cat("====================================================================\n\n")

# NOTE: phase1_selection_frequency.pdf removed - info now in phase1_absolute_relative_fit.pdf

# Define family ordering and colors for consistent styling across plots
# Order families by median delta AIC for better visualization
results[, delta_aic_plot := delta_aic_vs_best + 1]  # Add 1 to avoid log(0)
family_order <- results[, .(median_delta = median(delta_aic_plot)), by = family][
  order(median_delta), family]

# Create pretty family labels with proper capitalization
# Note: Fixed-df t-copula variants removed as free t-copula consistently dominates
pretty_names <- c(
  "t" = "t",
  "gaussian" = "Gaussian",
  "frank" = "Frank",
  "clayton" = "Clayton",
  "gumbel" = "Gumbel",
  "comonotonic" = "Comonotonic"
)

# Get pretty labels for ordered families
family_labels <- sapply(family_order, function(x) pretty_names[x])

# Generate Zissou1 color palette (best = warm, worst = cool)
n_families <- length(family_order)
zissou_colors <- wes_palette("Zissou1", n_families, type = "continuous")

# Plot 2: Mean AIC by Copula Family and Year Span
pdf(file.path(output_dir, "phase1_aic_by_span.pdf"), width = 10, height = 6)
par(mar = c(5, 6, 4, 8), xpd = TRUE)

# Calculate mean AIC by family and span, add absolute values for log scale
span_aic <- results[, .(mean_aic = mean(aic)), by = .(family, year_span)]
span_aic[, mean_aic_abs := abs(mean_aic)]

# Plot with manual axes and log scale
plot(NULL, xlim = c(0.8, 4.2), ylim = range(span_aic$mean_aic_abs),
     log = "y",
     axes = FALSE,
     xlab = "", ylab = "", main = "")

# Add x-axis
axis(1, at = 1:4, labels = c("1", "2", "3", "4"), las = 1, cex.axis = 0.9)

# Add y-axis with negative labels (since we're plotting absolute values)
# Calculate appropriate tick positions based on data range
y_range <- range(span_aic$mean_aic_abs)
y_ticks <- c(1e3, 5e3, 1e4, 5e4, 1e5, 5e5, 1e6, 5e6, 1e7)
y_ticks_in_range <- y_ticks[y_ticks >= y_range[1] & y_ticks <= y_range[2]]
y_labels <- ifelse(y_ticks_in_range < 1e6,
                   paste0("-", format(y_ticks_in_range / 1e3, big.mark = ","), "K"),
                   paste0("-", format(y_ticks_in_range / 1e6, big.mark = ","), "M"))
# Handle positive comonotonic value
if (any(span_aic$mean_aic > 0)) {
  pos_ticks <- c(1e6, 5e6)
  pos_ticks_in_range <- pos_ticks[pos_ticks >= y_range[1] & pos_ticks <= y_range[2]]
  if (length(pos_ticks_in_range) > 0) {
    y_ticks_in_range <- c(y_ticks_in_range, pos_ticks_in_range)
    y_labels <- c(y_labels, paste0("+", format(pos_ticks_in_range / 1e6, big.mark = ","), "M"))
  }
}
axis(2, at = y_ticks_in_range, labels = y_labels, las = 1, cex.axis = 0.9)

# Add grid lines
abline(h = y_ticks_in_range, col = "gray90", lty = 1, lwd = 0.5)
abline(v = 1:4, col = "gray90", lty = 1, lwd = 0.5)

# Plot lines for each family in order, using Zissou1 colors
for (i in seq_along(family_order)) {
  fam <- family_order[i]
  fam_data <- span_aic[family == fam]
  if (nrow(fam_data) > 0) {
    lines(fam_data$year_span, fam_data$mean_aic_abs, 
          col = zissou_colors[i], lwd = 2, type = "o", pch = 16)
  }
}

# Add axis labels and title using mtext
mtext("Year Span", side = 1, line = 3.5, cex = 1.2)
mtext("Mean AIC", side = 2, line = 4.5, cex = 1.2)
mtext("Mean AIC by Copula Family and Year Span", side = 3, line = 1.5, cex = 1.3, font = 2)

# Add legend with pretty names
legend("topright", inset = c(-0.25, 0),
       legend = family_labels,
       col = zissou_colors,
       lwd = 2, pch = 16,
       title = "Copula Family",
       cex = 0.9)
dev.off()
cat("Created:", file.path(output_dir, "phase1_aic_by_span.pdf"), "\n")

# NOTE: phase1_delta_aic_distributions.pdf removed - info now in phase1_absolute_relative_fit.pdf

################################################################################
### Plot: Two-Panel Violin Plot - Absolute and Relative Fit (KEEP)
################################################################################

# Create plot as expression for multi-format export
absolute_relative_plot <- quote({
  # Set up 2-panel layout with spacer: top panel (CvM), blank row, bottom panel (Delta AIC)
  layout(matrix(c(1, 0, 2), nrow = 3, ncol = 1), heights = c(0.425, 0.05, 0.525))

########################################
# PANEL 1: Absolute Fit (GoF CvM Statistic)
########################################

# Set margins: bottom, left, top, right
par(mar = c(5, 10, 4, 2))

# Filter out rows with missing gof_statistic
results_with_gof <- results[!is.na(gof_statistic)]

# Pre-transform data to log10 scale for reliable vioplot rendering
results_with_gof[, gof_log10 := log10(gof_statistic)]

# Create empty plot on LINEAR scale (data already log-transformed)
plot(NULL,
     xlim = c(-3.0, 2.0) + c(-0.1, 0.1),  # Small buffer
     ylim = c(0.5, length(family_order) + 0.5),
     axes = FALSE,
     frame.plot = FALSE,
     xlab = "",
     ylab = "",
     main = "")

# Draw violin plots for each family using log-transformed data
for (i in seq_along(family_order)) {
  fam <- family_order[i]
  fam_data_log <- results_with_gof[family == fam, gof_log10]
  
  if (length(fam_data_log) > 1) {
    # Use vioplot on log-transformed data (no xlog needed)
    vioplot(fam_data_log,
            at = i,
            horizontal = TRUE,
            add = TRUE,
            col = adjustcolor(zissou_colors[i], alpha.f = 0.4),
            border = adjustcolor(zissou_colors[i], alpha.f = 0.8),
            drawRect = TRUE,
            rectCol = adjustcolor("#7C7C7C", alpha.f = 0.6),
            lineCol = adjustcolor("#7C7C7C", alpha.f = 0.6),
            axes = FALSE)
    
    # Add median line (on log scale)
    median_val_log <- median(fam_data_log, na.rm = TRUE)
    segments(x0 = median_val_log, y0 = i - 0.2,
             x1 = median_val_log, y1 = i + 0.2,
             col = "#7C7C7C", lwd = 2)
  }
}

# Add acceptance region for GoF test (α = 0.05)
# Critical value at 0.015 (fail to reject H₀ if CvM < 0.015)
# Convert to log10 scale for rectangle coordinates
xleft_log <- -3.0
xright_log <- log10(0.015)
rect(xleft = xleft_log,
     ybottom = 0.5,
     xright = xright_log,
     ytop = length(family_order) + 0.5,
     col = adjustcolor("darkgreen", alpha.f = 0.5),
     border = adjustcolor("darkgreen", alpha.f = 0.5),
     lwd = 1.5)

# Add annotation for acceptance region (centered in green box, white text)
# Center of box on log scale: mean of log-transformed boundaries
box_center_log <- (xleft_log + xright_log) / 2
text(x = box_center_log, 
     y = (length(family_order) + 1) / 2,  # Vertical center
     labels = expression(atop("Fail to Reject " * H[0], 
                              paste("(", alpha, " = 0.05)"))),
     col = "white",
     cex = 1.2,
     font = 2)

# Add x-axis with log-scale labels
# Create tick positions in original scale, convert to log for plotting
tick_values_orig <- c(0.001, 0.01, 0.1, 1, 10, 100)
tick_positions_log <- log10(tick_values_orig)
tick_labels <- c("0", "0.01", "0.1", "1", "10", "100")
axis(1, 
     at = tick_positions_log,
     labels = tick_labels,
     las = 1, 
     cex.axis = 0.9)

# Add y-axis with family names
axis(2,
     at = 1:length(family_order),
     labels = family_labels,
     las = 1,
     hadj = 1,
     cex.axis = 1.2,
     tick = FALSE,
     line = -1)  # Negative values move labels right (into plot area)

# Add grid lines
grid(nx = NULL, ny = NA, col = "gray80", lty = 2, lwd = 0.5)

# Add axis labels
mtext("Cramér-von Mises Statistic (log scale)",
      side = 1,
      line = 3.5,
      cex = 1.1)

mtext("Copula Family",
      side = 2,
      line = 7.5,
      cex = 1.1)

# Add panel subtitle
mtext("A. Absolute Copula Fit: Goodness-of-Fit Test Statistics",
      side = 3,
      line = 1.5,
      cex = 1.2,
      font = 2,
      adj = 0)  # Left-justified

# Add data source annotation (lower right corner)
n_conditions_gof <- results_with_gof[, uniqueN(paste(dataset_id, condition_id))]
text(x = log10(.03), y = 6.0,
     labels = paste0("CvM statistic: 1,000 bootstrap simulations per condition"),
     pos = 4,
     cex = 1.0,
     col = "gray20")
text(x = log10(.03), y = 5.8,
     labels = paste0("(", n_conditions_gof, " assessment pair copula simulations)"),
     pos = 4,
     cex = 0.95,
     col = "gray20")
text(x = log10(.03), y = 5.6,
     labels = expression(italic("All") ~ italic(p) < 0.01 ~ "-> Reject " * H[0] ~ "(all parametric families)"),
     pos = 4,
     cex = 0.95,
     col = "gray20",
     font = 3)

########################################
# PANEL 2: Relative Fit (Delta AIC)
########################################

# Set margins to match current Plot 3
par(mar = c(5, 10, 4, 6))

# Pre-transform delta_aic_plot to log10 scale
results[, delta_aic_log10 := log10(delta_aic_plot)]

# Create empty plot on LINEAR scale (data already log-transformed)
plot(NULL,
     xlim = range(results$delta_aic_log10) + c(-0.1, 0.1),  # Small buffer
     ylim = c(0.5, length(family_order) + 0.5),
     axes = FALSE,
     frame.plot = FALSE,
     xlab = "",
     ylab = "",
     main = "")

# Draw violin plots for each family using log-transformed data
for (i in seq_along(family_order)) {
  fam <- family_order[i]
  fam_data_log <- results[family == fam, delta_aic_log10]
  
  if (length(fam_data_log) > 1) {
    # Use vioplot on log-transformed data (no xlog needed)
    vioplot(fam_data_log,
            at = i,
            horizontal = TRUE,
            add = TRUE,
            col = adjustcolor(zissou_colors[i], alpha.f = 0.4),
            border = adjustcolor(zissou_colors[i], alpha.f = 0.8),
            drawRect = TRUE,
            rectCol = adjustcolor("#7C7C7C", alpha.f = 0.6),
            lineCol = adjustcolor("#7C7C7C", alpha.f = 0.6),
            axes = FALSE)
    
    # Add median line (on log scale)
    median_val_log <- median(fam_data_log, na.rm = TRUE)
    segments(x0 = median_val_log, y0 = i - 0.2,
             x1 = median_val_log, y1 = i + 0.2,
             col = "#7C7C7C", lwd = 2)
  }
}

# Add x-axis with log-scale labels
# Original delta_aic_plot values, convert to log10 for plotting
tick_values_orig <- c(1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 100000, 1000000, 10000000)
tick_positions_log <- log10(tick_values_orig)
tick_labels <- c("0", "1", "4", "9", "19", "49", "99", "199", "499", "999", "1,999", "4,999", "9,999", "99,999", "999,999", "1e7")
axis(1,
     at = tick_positions_log,
     labels = tick_labels,
     las = 1,
     cex.axis = 0.75)

# Add top axis showing AIC weights (convert to log10)
delta_for_weights_orig <- c(0, 1.386, 10, 100, 500)
delta_for_weights_plot <- delta_for_weights_orig + 1  # Add 1 (as in delta_aic_plot)
delta_for_weights_log <- log10(delta_for_weights_plot)
axis(3,
     at = delta_for_weights_log,
     labels = c("1.0", "0.5", "0.007", "2e-22", "3e-109"),
     las = 1,
     cex.axis = 0.75,
     col.axis = "navy",
     col.ticks = "navy")

# Add y-axis with family names
axis(2,
     at = 1:length(family_order),
     labels = family_labels,
     las = 1,
     hadj = 1,
     cex.axis = 1.2,
     tick = FALSE,
     line = -1)  # Negative values move labels right (into plot area)

# Add right y-axis showing selection counts
selection_counts_violin <- selection_freq_aic[, .(family, n_best = N)]
setkey(selection_counts_violin, family)
counts_ordered <- sapply(family_order, function(fam) {
  count <- selection_counts_violin[family == fam, n_best]
  if (length(count) == 0) return(0)
  return(count)
})
axis(4,
     at = 1:length(family_order),
     labels = counts_ordered,
     las = 1,
     cex.axis = 0.9,
     col.axis = "gray30",
     line = 1)

# Add grid lines (convert to log10)
grid_values_orig <- c(1, 10, 100, 1000, 10000, 100000, 10000000)
grid_positions_log <- log10(grid_values_orig)
abline(v = grid_positions_log,
       col = "gray80",
       lty = 2,
       lwd = 0.5)

# Add reference lines (convert to log10)
abline(v = log10(1), col = "black", lwd = 1, lty = 2)    # Delta = 0
abline(v = log10(11), col = "orange", lwd = 1, lty = 2)  # Delta = 10
abline(v = log10(101), col = "red", lwd = 1, lty = 2)    # Delta = 100

# Add axis labels
mtext(expression(Delta * "AIC + 1 (log scale)"),
      side = 1,
      line = 3.5,
      cex = 1.1)

mtext("Copula Family",
      side = 2,
      line = 6.5,
      cex = 1.1)

mtext("Times Selected",
      side = 4,
      line = 3.5,
      cex = 1.0,
      col = "gray30")

mtext("Relative AIC Weight",
      side = 3,
      line = 2.5,
      cex = 1.0,
      col = "navy")

# Add panel subtitle
mtext("B. Relative Copula Fit: AIC-Based Model Comparison",
      side = 3,
      line = 5.4,
      cex = 1.2,
      font = 2,
      adj = 0)  # Left-justified

# Add threshold annotations (convert x to log10)
text(x = log10(11), y = length(family_order) * 0.95,
     labels = expression(Delta ~ "= 10"),
     pos = 4,
     col = "orange",
     cex = 1.1,
     font = 3)

text(x = log10(101), y = length(family_order) * 0.85,
     labels = expression(Delta ~ "= 100"),
     pos = 4,
     col = "red",
     cex = 1.1,
     font = 3)

# Add data source annotation (convert x to log10)
n_conditions_violin <- results[, uniqueN(paste(dataset_id, condition_id))]
n_datasets_violin <- uniqueN(results$dataset_id)
text(x = log10(50000), y = 3.5,
     labels = paste0("Based upon ", n_conditions_violin, " conditions across:"),
     pos = 4,
     cex = 1.0,
     col = "gray20")
text(x = log10(60000), y = 3.35,
     labels = paste0(n_datasets_violin, " longitudinal assessment datasets"),
     pos = 4,
     cex = 0.95,
     col = "gray20")
text(x = log10(60000), y = 3.2,
     labels = paste0("3 content areas"),
     pos = 4,
     cex = 0.95,
     col = "gray20")
})

# Export to all formats
save_phase1_base_plot(
  plot_code = absolute_relative_plot,
  base_filename = file.path(output_dir, "phase1_absolute_relative_fit"),
  width = 10,
  height = 14
)

cat("Created:", file.path(output_dir, "phase1_absolute_relative_fit.{pdf,svg,png}"), "\n")

# NOTE: Mosaic plots removed - information consolidated into phase1_copula_selection_by_condition.pdf

################################################################################
### EXTRACT BEST FAMILIES FOR VISUALIZATIONS
################################################################################

# Extract best family for each condition (where delta_aic_vs_best == 0)
best_families <- results[delta_aic_vs_best == 0, 
                         .(dataset_id, condition_id, family, content_area, year_span)]

cat("\nBest family selections extracted:", nrow(best_families), "conditions\n")
cat("Families in dataset:", paste(unique(best_families$family), collapse = ", "), "\n")
cat("Content areas:", paste(unique(best_families$content_area), collapse = ", "), "\n")
cat("Year spans:", paste(sort(unique(best_families$year_span)), collapse = ", "), "\n\n")

# Ensure family is a factor with consistent ordering
best_families[, family := factor(family, levels = family_order)]
best_families[, family := droplevels(family)]

################################################################################
### NEW VISUALIZATION: PROPORTION BARS - COPULA SELECTION BY CONDITION
################################################################################

cat("\n====================================================================\n")
cat("CREATING PROPORTION BARS VISUALIZATION\n")
cat("====================================================================\n\n")

# Calculate proportions for stacked bars
family_props <- best_families[, .N, by = .(content_area, year_span, family)]
family_props[, total := sum(N), by = .(content_area, year_span)]
family_props[, proportion := N / total]

# Ensure family is factor with consistent ordering
family_props[, family := factor(family, levels = family_order)]

# Get Kendall's tau values for each best-fit family to add to dot plot
# Merge with results to get tau values
best_families_with_tau <- merge(
  best_families[, .(dataset_id, condition_id, family)],
  results[, .(dataset_id, condition_id, family, tau, content_area, year_span)],
  by = c("dataset_id", "condition_id", "family"),
  all.x = TRUE
)

cat("Best families with tau values:\n")
cat("  Rows:", nrow(best_families_with_tau), "\n")
cat("  Tau range:", sprintf("%.3f to %.3f", 
    min(best_families_with_tau$tau, na.rm = TRUE),
    max(best_families_with_tau$tau, na.rm = TRUE)), "\n\n")

# Ensure family is factor with consistent ordering for dot plot
best_families_with_tau[, family := factor(family, levels = family_order)]

# Add tail dependence values to the data
# Merge with results to get tail_dep_lower and tail_dep_upper
best_families_with_tau <- merge(
  best_families_with_tau,
  results[, .(dataset_id, condition_id, family, tail_dep_lower, tail_dep_upper)],
  by = c("dataset_id", "condition_id", "family"),
  all.x = TRUE
)

# Calculate effective tail dependence for each family
# Gaussian & Frank: 0 (no tail dependence)
# t-copula: symmetric, use average (lambda_L + lambda_U) / 2
# Clayton: lower tail only (lambda_L)
# Gumbel: upper tail only (lambda_U)
best_families_with_tau[, tail_dep_plot := fcase(
  family %in% c("gaussian", "frank"), 0,
  family == "t", (tail_dep_lower + tail_dep_upper) / 2,
  family == "clayton", tail_dep_lower,
  family == "gumbel", tail_dep_upper,
  default = NA_real_
)]

cat("Tail dependence values:\n")
cat("  Total rows:", nrow(best_families_with_tau), "\n")
cat("  Tail dep = 0:", nrow(best_families_with_tau[tail_dep_plot == 0]), 
    "(", paste(unique(best_families_with_tau[tail_dep_plot == 0, family]), collapse = ", "), ")\n")
cat("  Tail dep > 0:", nrow(best_families_with_tau[tail_dep_plot > 0]), "\n")
cat("  Tail dep range:", sprintf("%.3f to %.3f", 
    min(best_families_with_tau$tail_dep_plot, na.rm = TRUE),
    max(best_families_with_tau$tail_dep_plot, na.rm = TRUE)), "\n\n")

# Add correlation_rho values to the data
# Merge with results to get correlation_rho
best_families_with_tau <- merge(
  best_families_with_tau,
  results[, .(dataset_id, condition_id, family, correlation_rho)],
  by = c("dataset_id", "condition_id", "family"),
  all.x = TRUE
)

cat("Correlation rho values:\n")
cat("  Rho range:", sprintf("%.3f to %.3f", 
    min(best_families_with_tau$correlation_rho, na.rm = TRUE),
    max(best_families_with_tau$correlation_rho, na.rm = TRUE)), "\n\n")

# Calculate total counts and percentages by family for legend
family_totals <- best_families[, .N, by = family]
grand_total_for_pct <- nrow(best_families)
family_totals[, pct := round(100 * N / grand_total_for_pct, 1)]

# Get pretty labels for legend (for scale_fill_manual)
# Create labels for the families that actually appear in this plot
# Format: "t (n=120, 93%)"
families_in_plot <- levels(family_props$family)
family_labels_for_plot <- sapply(families_in_plot, function(f) {
  # Get pretty name
  pretty_name <- if (f %in% names(pretty_names)) {
    pretty_names[[f]]
  } else {
    as.character(f)
  }
  
  # Get count and percentage for this family
  if (f %in% family_totals$family) {
    n_val <- family_totals[family == f, N]
    pct_val <- family_totals[family == f, pct]
    sprintf("%s (n=%d, %.1f%%)", pretty_name, n_val, pct_val)
  } else {
    pretty_name
  }
})
names(family_labels_for_plot) <- families_in_plot

cat("Family totals for legend:\n")
print(family_totals)
cat("\n")

# Calculate marginal counts for inline labels
# Count by year span (across all content areas)
n_by_span <- best_families[, .N, by = year_span]
setkey(n_by_span, year_span)

# Count by content area (across all year spans)
n_by_content <- best_families[, .N, by = content_area]
setkey(n_by_content, content_area)

# Grand total
grand_total <- uniqueN(best_families[, .(dataset_id, condition_id)])

# Create x-axis labels with marginal counts
# Format: "1\n(n=25)"
x_labels <- sapply(sort(unique(family_props$year_span)), function(span) {
  n <- n_by_span[year_span == span, N]
  sprintf("%d\n(n=%d)", span, n)
})
names(x_labels) <- sort(unique(family_props$year_span))

# Create facet labels with marginal counts
# We'll use labeller to modify the facet strip text
content_labels <- sapply(unique(family_props$content_area), function(ca) {
  n <- n_by_content[content_area == ca, N]
  # Format content area with SGP::capwords if available
  ca_formatted <- if (requireNamespace("SGP", quietly = TRUE)) {
    SGP::capwords(ca)
  } else {
    tools::toTitleCase(tolower(ca))
  }
  sprintf("%s (n=%d)", ca_formatted, n)
})
names(content_labels) <- unique(family_props$content_area)

cat("Marginal counts:\n")
cat("  By year span:\n")
print(n_by_span)
cat("  By content area:\n")
print(n_by_content)
cat("  Grand total:", grand_total, "\n\n")

# Calculate cell counts (content_area × year_span) for labels above bars
cell_counts <- family_props[, .(cell_n = sum(N)), by = .(content_area, year_span)]
cell_counts[, label := sprintf("(n=%d)", cell_n)]

cat("Cell counts (content_area × year_span):\n")
print(cell_counts)
cat("\n")

# Create stacked bar plot with dot plot overlay showing individual tau values
p_selection <- ggplot(family_props, 
                      aes(x = factor(year_span), y = proportion, fill = family)) +
  # Stacked bars (narrower to make room for dots)
  geom_col(position = "stack", width = 0.4, color = "white", linewidth = 0.3) +
  
  # Percentage labels on bars
  geom_text(aes(label = ifelse(proportion > 0.05, 
                                sprintf("%d%%", round(proportion*100)), "")),
            position = position_stack(vjust = 0.5), 
            size = 3, color = "white", fontface = "bold") +
  
  # Mean line for rho values by family (drawn first, behind dots)
  # Only for families that have correlation_rho (Gaussian, t)
  stat_summary(data = best_families_with_tau[!is.na(correlation_rho)],
               aes(x = as.numeric(factor(year_span)) + 0.3, 
                   y = correlation_rho,
                   color = family),
               fun = mean,
               fun.min = mean,
               fun.max = mean,
               geom = "errorbar",
               width = 0.1,
               linewidth = 0.3,
               lineend = "round") +
  
  # Correlation rho dot plot (positioned first, left-most)
  # Shows the fitted correlation parameter from the copula
  geom_beeswarm(data = best_families_with_tau[!is.na(correlation_rho)],
                aes(x = as.numeric(factor(year_span)) + 0.3, 
                    y = correlation_rho, 
                    fill = family),
                cex = 0.3,
                size = 1.4,
                alpha = 0.5,
                color = rgb(20, 20, 16, maxColorValue = 255),
                shape = 21,  # Circle with fill and outline
                stroke = 0.1,
                inherit.aes = FALSE) +
  
  # Mean line for tau values by family (drawn first, behind dots)
  stat_summary(data = best_families_with_tau,
               aes(x = as.numeric(factor(year_span)) + 0.45, 
                   y = tau,
                   color = family,
                   group = interaction(year_span, family)),
               fun = mean,
               fun.min = mean,
               fun.max = mean,
               geom = "errorbar",
               width = 0.1,
               linewidth = 0.3,
               lineend = "round") +
  
  # Dot plot of tau values (positioned second)
  # All families superimposed, colored by family, with beeswarm arrangement
  geom_beeswarm(data = best_families_with_tau,
                aes(x = as.numeric(factor(year_span)) + 0.45, 
                    y = tau, 
                    fill = family),
                cex = 0.3,
                size = 1.4,
                alpha = 0.5,
                color = rgb(20, 20, 16, maxColorValue = 255),
                shape = 21,  # Circle with fill and outline
                stroke = 0.1,
                inherit.aes = FALSE) +
  
  # Mean line for lambda values by family (drawn first, behind dots)
  stat_summary(data = best_families_with_tau,
               aes(x = as.numeric(factor(year_span)) + 0.6, 
                   y = tail_dep_plot,
                   color = family,
                   group = interaction(year_span, family)),
               fun = mean,
               fun.min = mean,
               fun.max = mean,
               geom = "errorbar",
               width = 0.1,
               linewidth = 0.3,
               lineend = "round") +
  
  # Tail dependence dot plot (positioned third, right-most)
  # Shows: 0 for Gaussian/Frank, avg for t, lambda_L for Clayton, lambda_U for Gumbel
  geom_beeswarm(data = best_families_with_tau,
                aes(x = as.numeric(factor(year_span)) + 0.6, 
                    y = tail_dep_plot, 
                    fill = family),
                cex = 0.3,
                size = 1.4,
                alpha = 0.5,
                color = rgb(20, 20, 16, maxColorValue = 255),
                shape = 21,  # Circle with fill and outline
                stroke = 0.1,
                inherit.aes = FALSE) +
  
  # Cell count labels above bars
  geom_text(data = cell_counts,
            aes(x = factor(year_span), y = 1.02, label = label),
            inherit.aes = FALSE,
            size = 2.5, color = "gray30", vjust = 0) +
  
  # Rho dot plot label (Greek letter rho)
  geom_text(data = cell_counts,
            aes(x = as.numeric(factor(year_span)) + 0.3, y = 1.02, label = "rho"),
            parse = TRUE,  # Parse as plotmath expression
            inherit.aes = FALSE,
            size = 3, color = "gray20", vjust = 0, fontface = "bold") +
  
  # Tau dot plot label (Greek letter tau)
  geom_text(data = cell_counts,
            aes(x = as.numeric(factor(year_span)) + 0.45, y = 1.02, label = "tau"),
            parse = TRUE,  # Parse as plotmath expression
            inherit.aes = FALSE,
            size = 3, color = "gray20", vjust = 0, fontface = "bold") +
  
  # Lambda dot plot label (Greek letter lambda)
  geom_text(data = cell_counts,
            aes(x = as.numeric(factor(year_span)) + 0.6, y = 1.02, label = "lambda"),
            parse = TRUE,  # Parse as plotmath expression
            inherit.aes = FALSE,
            size = 3, color = "gray20", vjust = 0, fontface = "bold") +
  
  # Faceting and scales
  facet_wrap(~ content_area, ncol = 1, scales = "free_y",
             labeller = labeller(content_area = content_labels)) +
  scale_fill_manual(values = zissou_colors, 
                    labels = family_labels_for_plot,
                    name = "Best Copula",
                    guide = guide_legend(override.aes = list(shape = 21, size = 4, stroke = 0.5, alpha = 1,
                                                              color = rgb(20, 20, 16, maxColorValue = 255)))) +
  scale_color_manual(values = zissou_colors,
                     labels = family_labels_for_plot,
                     name = "Best Copula",
                     limits = family_order,
                     guide = "none") +
  scale_y_continuous(labels = function(x) sprintf("%d%%/%.2f", round(x * 100), x),
                     expand = expansion(mult = c(0.02, 0.08)),  # Add 8% space at top for labels
                     breaks = seq(0, 1, 0.25)) +
  scale_x_discrete(labels = x_labels) +
  
  # Labels
  labs(x = "Year Span (years between assessments)", 
       y = bquote("Proportion / Correlation " * rho * " / Kendall's " * tau * " / Tail Dependence (" * lambda * ")"),
       title = "Copula Family Selection by Year Span and Content Area",
       subtitle = bquote("Based on" ~ .(grand_total) ~ "conditions total; bars show selection %, dots show" ~ rho * "," ~ tau * ", and tail dependence" ~ lambda ~ "values")) +
  
  # Theme
  theme_minimal() +
  theme(
    legend.position = "bottom",
    legend.box = "horizontal",
    strip.text = element_text(size = 11, face = "bold"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    panel.spacing = unit(1.5, "lines"),  # Add spacing between facet rows
    plot.background = element_rect(fill = "transparent", color = NA),
    panel.background = element_rect(fill = "transparent", color = NA),
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 10, color = "gray30"),
    plot.margin = margin(t = 15, r = 10, b = 10, l = 15, unit = "pt"),  # Extended left margin for dual-format labels
    axis.text.y = element_text(size = 9),  # Slightly smaller text to fit dual labels
    axis.title.x = element_text(margin = margin(t = 10, r = 0, b = 0, l = 0))  # Add space above x-axis title
  )

# Save to all formats
save_phase1_plot(
  plot_obj = p_selection,
  base_filename = file.path(output_dir, "phase1_copula_selection_by_condition"),
  width = 10.5,  # Increased from 9.5 to accommodate rho, tau, and lambda dots
  height = 11
)

cat("Created:", file.path(output_dir, "phase1_copula_selection_by_condition.{pdf,svg,png}"), "\n\n")

# NOTE: phase1_aic_weights.pdf removed - info now in phase1_absolute_relative_fit.pdf
# NOTE: phase1_tail_dependence.pdf removed - info now in phase1_copula_selection_by_condition.pdf (lambda dots)
# NOTE: phase1_heatmap.pdf removed - replaced with phase1_copula_selection_by_condition.pdf (proportion bars)
# NOTE: phase1_mosaic_*.pdf removed - info consolidated into phase1_copula_selection_by_condition.pdf

################################################################################
### NEW VISUALIZATION: t-COPULA PHASE DIAGRAM
################################################################################

cat("\n====================================================================\n")
cat("CREATING t-COPULA PHASE DIAGRAM\n")
cat("====================================================================\n\n")

# Extract t-copula fits only
t_fits <- results[family == "t"]

cat("t-Copula fits:", nrow(t_fits), "\n")
if (nrow(t_fits) > 0) {
  cat("  Year spans:", paste(sort(unique(t_fits$year_span)), collapse = ", "), "\n")
  cat("  Content areas:", paste(unique(t_fits$content_area), collapse = ", "), "\n")
  cat("  Degrees of freedom range:", sprintf("%.1f to %.1f", 
      min(t_fits$degrees_freedom, na.rm = TRUE), 
      max(t_fits$degrees_freedom, na.rm = TRUE)), "\n")
  cat("  Tail dependence range:", sprintf("%.3f to %.3f", 
      min(t_fits$tail_dep_upper, na.rm = TRUE), 
      max(t_fits$tail_dep_upper, na.rm = TRUE)), "\n\n")
}

# Verify required columns
required_cols <- c("degrees_freedom", "tail_dep_upper", "year_span", "content_area", "n_pairs")
missing_cols <- setdiff(required_cols, names(t_fits))
if (length(missing_cols) > 0) {
  cat("WARNING: Missing required columns for phase diagram:", paste(missing_cols, collapse = ", "), "\n")
  cat("Skipping t-copula phase diagram\n\n")
} else if (nrow(t_fits) == 0) {
  cat("WARNING: No t-copula fits found\n")
  cat("Skipping t-copula phase diagram\n\n")
} else {
  # Calculate mean correlation_rho for each content_area × year_span combination
  mean_rho_by_content_span <- t_fits[, .(mean_rho = mean(correlation_rho, na.rm = TRUE)), 
                                      by = .(content_area, year_span)]
  
  cat("\nMean correlation (rho) by content area and year span:\n")
  print(mean_rho_by_content_span[order(content_area, year_span)])
  cat("\n")
  
  # Generate theoretical lambda contour curves in (nu, rho) space
  # For a given lambda value, find the rho values across a range of nu
  generate_lambda_contour <- function(lambda_target, nu_seq = 10^seq(log10(2), log10(100), length = 200)) {
    # For each nu, solve for rho that gives the target lambda
    # Lambda formula: lambda = 2 * pt(-sqrt((nu+1)(1-rho)/(1+rho)), df = nu+1)
    # We need to solve this numerically for rho
    
    rho_values <- sapply(nu_seq, function(nu) {
      # Function to minimize: difference between computed lambda and target
      obj_fn <- function(rho) {
        if (rho <= -1 || rho >= 1) return(Inf)
        lambda_computed <- 2 * pt(-sqrt((nu + 1) * (1 - rho) / (1 + rho)), df = nu + 1)
        return((lambda_computed - lambda_target)^2)
      }
      
      # Optimize to find rho
      result <- optimize(obj_fn, interval = c(-0.99, 0.99))
      return(result$minimum)
    })
    
    data.table(nu = nu_seq, rho = rho_values, lambda = lambda_target)
  }
  
  # Function to create phase diagram for a single content area
  create_content_phase_diagram <- function(content_name, plot_data, lambda_contours, year_span_colors, max_nu) {
    # Format content area name
    content_formatted <- if (requireNamespace("SGP", quietly = TRUE)) {
      SGP::capwords(content_name)
    } else {
      tools::toTitleCase(tolower(content_name))
    }
    
    # Calculate year-span-specific median values for this content area
    year_span_stats_ca <- plot_data[, .(
      median_nu = median(degrees_freedom, na.rm = TRUE),
      median_rho = median(correlation_rho, na.rm = TRUE),
      n = .N
    ), by = year_span]
    setorder(year_span_stats_ca, year_span)
    
    # Create labels for lambda contours - position at x=101, left-justified
    # Get rho value at nu=101 for each lambda contour
    contour_labels <- lambda_contours[, {
      # Find rho value closest to nu=101 for labeling
      idx <- which.min(abs(nu - 101))
      list(nu_label = 103, rho_label = rho[idx])
    }, by = lambda]
    contour_labels[, label := sprintf("lambda==%.2f", lambda)]
    
    p <- ggplot(plot_data, aes(x = degrees_freedom, y = correlation_rho)) +
      # Add lambda contour curves (gray, in background)
      geom_line(data = lambda_contours[rho >= 0.6], 
                aes(x = nu, y = rho, group = factor(lambda)),
                inherit.aes = FALSE,
                color = "gray75", linetype = "dashed", linewidth = 0.3, alpha = 0.7) +
      # Add contour labels at x=101, left-justified
      geom_text(data = contour_labels,
                aes(x = nu_label, y = rho_label, label = label),
                inherit.aes = FALSE,
                parse = TRUE,
                hjust = 0, vjust = -0.2, size = 1.5, color = "gray50", fontface = "italic") +
      # Add year-span-specific crosshairs (colored by year span)
      geom_vline(data = year_span_stats_ca,
                 aes(xintercept = median_nu, color = factor(year_span)),
                 linetype = "dotted", linewidth = 0.5, alpha = 0.7) +
      geom_hline(data = year_span_stats_ca,
                 aes(yintercept = median_rho, color = factor(year_span)),
                 linetype = "dotted", linewidth = 0.5, alpha = 0.7) +
      # Add empirical fits as dots
      geom_point(aes(color = factor(year_span), size = n_pairs), 
                 alpha = 0.7) +
      # Add year-span-specific markers at intersections (X marks without text)
      geom_point(data = year_span_stats_ca,
                 aes(x = median_nu, y = median_rho, color = factor(year_span)),
                 size = 3, shape = 4, stroke = 1.2, inherit.aes = FALSE) +
      scale_x_log10(limits = c(2, max_nu),
                    breaks = c(2, 5, 10, 20, 50, 100),
                    labels = c("2", "5", "10", "20", "50", "100")) +
      scale_y_continuous(limits = c(0.6, 1), 
                         breaks = seq(0.6, 1, 0.1),
                         labels = sprintf("%.1f", seq(0.6, 1, 0.1))) +
      scale_color_manual(values = year_span_colors, name = "Year Span") +
      scale_size_continuous(range = c(1.5, 4), 
                            labels = scales::comma,
                            name = "Sample Size") +
      labs(x = bquote(nu ~ "(log scale)"),
           y = bquote(rho ~ "(correlation)"),
           title = content_formatted,
           subtitle = bquote("Gray curves: constant" ~ lambda * "; crosshairs: median" ~ (nu * "," ~ rho) ~ "by year span")) +
      theme_minimal() +
      theme(
        legend.position = "none",  # Remove legend from individual plots
        panel.grid.minor = element_line(color = "gray95"),
        panel.grid.major = element_line(color = "gray90"),
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.title = element_text(size = 11, face = "bold", hjust = 0.5),
        plot.subtitle = element_text(size = 8, color = "gray30", hjust = 0.5),
        axis.title = element_text(size = 9)
      )
    
    return(p)
  }
  
  # Define Darjeeling1 color palette for year spans (1, 2, 3, 4)
  # Darjeeling1 has excellent color distinction (better than Zissou1 for this purpose)
  # Alternative palettes: "GrandBudapest1", "Royal1", "Moonrise3"
  year_span_colors <- wes_palette("Darjeeling1", 4, type = "continuous")
  names(year_span_colors) <- c("1", "2", "3", "4")
  
  cat("\nYear span colors (Darjeeling1):\n")
  print(year_span_colors)
  cat("\n")
  
  # Generate theoretical lambda contour curves
  # These show constant tail dependence in (nu, rho) space
  cat("Generating theoretical lambda contours...\n")
  lambda_values <- c(0.01, 0.05, 0.10, 0.15, 0.20, 0.25)
  lambda_contours <- rbindlist(lapply(lambda_values, generate_lambda_contour))
  cat("Contours generated for λ =", paste(lambda_values, collapse = ", "), "\n\n")
  
  # Calculate year-span-specific statistics across ALL content areas
  year_span_stats_all <- t_fits[, .(
    median_nu = median(degrees_freedom, na.rm = TRUE),
    median_rho = median(correlation_rho, na.rm = TRUE),
    median_lambda = median(tail_dep_upper, na.rm = TRUE),
    mean_nu = mean(degrees_freedom, na.rm = TRUE),
    mean_rho = mean(correlation_rho, na.rm = TRUE),
    mean_lambda = mean(tail_dep_upper, na.rm = TRUE),
    n = .N
  ), by = year_span]
  setorder(year_span_stats_all, year_span)
  
  cat("\n====================================================================\n")
  cat("RULE OF THUMB T-COPULA PARAMETERS BY YEAR SPAN\n")
  cat("====================================================================\n\n")
  cat("Based on marginal distributions of fitted t-copulas:\n\n")
  cat("MEDIAN values (Recommended - robust to outliers):\n")
  print(year_span_stats_all[, .(year_span, median_nu, median_rho, median_lambda, n)])
  cat("\nMEAN values (Alternative - accounts for all variation):\n")
  print(year_span_stats_all[, .(year_span, mean_nu, mean_rho, mean_lambda, n)])
  cat("\nNote: Median values are more robust and recommended for rule-of-thumb.\n")
  cat("      Crosshairs on plots show year-span-specific medians for each content area.\n\n")
  
  # Calculate global max degrees of freedom for consistent x-axis across all plots
  max_nu_global <- max(t_fits$degrees_freedom, na.rm = TRUE)
  cat(sprintf("Setting consistent x-axis range: 2 to %.1f (max across all content areas)\n\n", max_nu_global))
  
  # Create 4 separate plots, one for each content area
  content_areas <- sort(unique(t_fits$content_area))
  phase_plots <- list()
  content_stats <- list()
  
  for (ca in content_areas) {
    # Get data for this content area
    ca_data <- t_fits[content_area == ca]
    
    # Calculate content-specific statistics by year span
    content_stats[[ca]] <- ca_data[, .(
      content_area = ca,
      year_span = year_span,
      median_nu = median(degrees_freedom, na.rm = TRUE),
      median_rho = median(correlation_rho, na.rm = TRUE),
      median_lambda = median(tail_dep_upper, na.rm = TRUE),
      mean_nu = mean(degrees_freedom, na.rm = TRUE),
      mean_rho = mean(correlation_rho, na.rm = TRUE),
      mean_lambda = mean(tail_dep_upper, na.rm = TRUE),
      n = .N
    ), by = year_span]
    
    # Create plot for this content area
    phase_plots[[ca]] <- create_content_phase_diagram(ca, ca_data, lambda_contours, year_span_colors, max_nu_global)
    
    cat("Created phase diagram for:", ca, "\n")
  }
  
  # Combine and print content-specific statistics
  content_stats_dt <- rbindlist(content_stats)
  setorder(content_stats_dt, content_area, year_span)
  
  cat("\n====================================================================\n")
  cat("CONTENT & YEAR-SPAN-SPECIFIC T-COPULA PARAMETERS\n")
  cat("====================================================================\n\n")
  cat("Median values (shown as crosshairs on plots):\n")
  print(content_stats_dt[, .(content_area, year_span, median_nu, median_rho, median_lambda, n)])
  cat("\nMean values (for reference):\n")
  print(content_stats_dt[, .(content_area, year_span, mean_nu, mean_rho, mean_lambda, n)])
  cat("\n")
  
  # Create a shared legend
  # Use the first plot to extract legend
  p_legend <- ggplot(t_fits, aes(x = degrees_freedom, y = correlation_rho)) +
    geom_point(aes(color = factor(year_span), size = n_pairs), alpha = 0.7) +
    scale_color_manual(values = year_span_colors, name = "Year Span") +
    scale_size_continuous(range = c(1.5, 4), 
                          labels = scales::comma,
                          name = "Sample Size") +
    theme_minimal() +
    theme(legend.position = "bottom",
          legend.box = "horizontal")
  
  # Extract legend as grob
  library(grid)
  library(gridExtra)
  
  legend_grob <- ggplotGrob(p_legend + theme(legend.position = "bottom"))$grobs
  legend_index <- which(sapply(legend_grob, function(x) x$name) == "guide-box")
  legend <- legend_grob[[legend_index]]
  
  # Arrange plots in 2x2 grid with shared legend at bottom
  combined_plot <- arrangeGrob(
    grobs = phase_plots,
    ncol = 2,
    nrow = 2,
    top = textGrob(
      expression(bold("t-Copula Phase Diagrams: Degrees of Freedom (" * nu * ") vs Correlation (" * rho * ")")),
      gp = gpar(fontsize = 14, fontface = "bold")
    ),
    bottom = legend
  )
  
  # Save combined plot to all formats
  save_phase1_base_plot(
    plot_code = quote({ grid.draw(combined_plot) }),
    base_filename = file.path(output_dir, "phase1_t_copula_phase_diagram"),
    width = 12,
    height = 10
  )
  
  cat("\nCreated:", file.path(output_dir, "phase1_t_copula_phase_diagram.{pdf,svg,png}"), "\n\n")
}

################################################################################
### DECISION CRITERIA FOR PHASE 2
################################################################################

cat("====================================================================\n")
cat("APPLYING DECISION CRITERIA FOR PHASE 2\n")
cat("====================================================================\n\n")

# Get overall winner
winner <- selection_freq_aic$family[1]
winner_pct <- selection_freq_aic$pct[1]
winner_count <- selection_freq_aic$N[1]
total_conditions <- uniqueN(results$condition_id)

# Get runner-up
if (nrow(selection_freq_aic) > 1) {
  runner_up <- selection_freq_aic$family[2]
  runner_up_pct <- selection_freq_aic$pct[2]
  runner_up_count <- selection_freq_aic$N[2]
} else {
  runner_up <- NA
  runner_up_pct <- 0
  runner_up_count <- 0
}

# Calculate mean delta AIC for winner
winner_delta <- mean(results[family == winner, delta_aic_vs_best])

# Decision logic
decision <- NA
phase2_families <- NA
rationale <- ""

# Rule 1: Clear winner (>75% selection, mean delta AIC < 2 when it wins)
if (winner_pct > 75 && winner_delta < 2) {
  decision <- "SINGLE_WINNER"
  phase2_families <- c(winner)
  rationale <- sprintf(
    "%s copula selected in %.1f%% of conditions (mean Delta AIC = %.2f when selected). Clear dominance - proceed with %s only for Phase 2.",
    winner, winner_pct, winner_delta, winner
  )
} else if (!is.na(runner_up) && (winner_count + runner_up_count) / total_conditions > 0.90) {
  # Rule 2: Two strong contenders
  decision <- "TWO_CONTENDERS"
  phase2_families <- c(winner, runner_up)
  rationale <- sprintf(
    "%s (%.1f%%) and %s (%.1f%%) together account for >90%% of selections. Proceed with both families for Phase 2.",
    winner, winner_pct, runner_up, runner_up_pct
  )
} else {
  # Rule 3: Check for systematic pattern by grade span
  # Check if different families dominate different spans
  span_winners <- by_span[, .(family = winner, pct = t_pct), by = year_span]
  if (length(unique(span_winners$family)) > 1) {
    decision <- "CONTEXT_DEPENDENT"
    phase2_families <- unique(span_winners$family)
    rationale <- sprintf(
      "Family selection varies by grade span. Phase 2 will use condition-specific selection: %s",
      paste(unique(span_winners$family), collapse = ", ")
    )
  } else {
    # Rule 4: No clear pattern - keep all
    decision <- "NO_CLEAR_WINNER"
    phase2_families <- c("gaussian", "t", "clayton", "gumbel", "frank")
    rationale <- "No clear winner identified. Phase 2 will analyze all families."
  }
}

cat("DECISION:", decision, "\n")
cat("PHASE 2 FAMILIES:", paste(phase2_families, collapse = ", "), "\n")
cat("\nRATIONALE:\n", rationale, "\n\n")

# Create decision summary table
decision_summary <- data.table(
  decision = decision,
  winner = winner,
  winner_pct = winner_pct,
  runner_up = runner_up,
  runner_up_pct = runner_up_pct,
  total_conditions = total_conditions
)

################################################################################
### SAVE DECISION AND SUMMARY
################################################################################

cat("====================================================================\n")
cat("SAVING PHASE 1 SUMMARY AND DECISION\n")
cat("====================================================================\n\n")

# Save decision for Phase 2
save(phase2_families, decision, rationale, decision_summary,
     file = file.path(output_dir, "phase1_decision.RData"))
cat("Saved:", file.path(output_dir, "phase1_decision.RData"), "\n")

# Save selection table
fwrite(selection_freq_aic, file.path(output_dir, "phase1_selection_table.csv"))
cat("Saved:", file.path(output_dir, "phase1_selection_table.csv"), "\n")

# Save AIC weights summary by family
aic_weights_summary <- mean_aic_by_family[, .(family, mean_delta_aic, mean_aic_weight, 
                                                median_aic_weight, n_times_best)]
setorder(aic_weights_summary, -mean_aic_weight)
fwrite(aic_weights_summary, file.path(output_dir, "phase1_aic_weights_summary.csv"))
cat("Saved:", file.path(output_dir, "phase1_aic_weights_summary.csv"), "\n")

# Write text summary
summary_file <- file.path(output_dir, "phase1_summary.txt")
sink(summary_file)

cat("====================================================================\n")
cat("PHASE 1: COPULA FAMILY SELECTION SUMMARY\n")
cat("====================================================================\n\n")

cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

cat("STUDY DESIGN\n")
cat("------------\n")
cat("Conditions tested:", total_conditions, "\n")
cat("Copula families:", paste(c("gaussian", "t", "clayton", "gumbel", "frank"), collapse = ", "), "\n")
cat("Total fits:", nrow(results), "\n\n")

cat("SELECTION FREQUENCY (by AIC)\n")
cat("----------------------------\n")
print(selection_freq_aic)
cat("\n")

cat("SELECTION BY GRADE SPAN\n")
cat("-----------------------\n")
print(by_span)
cat("\n")

cat("SELECTION BY CONTENT AREA\n")
cat("-------------------------\n")
print(by_content)
cat("\n")

cat("AIC WEIGHTS BY FAMILY\n")
cat("---------------------\n")
cat("AIC weights represent the probability that each model is the best.\n")
cat("Values range from 0 (no support) to 1 (certain support).\n\n")
print(aic_weights_summary)
cat("\n")

cat("VISUALIZATIONS GENERATED\n")
cat("------------------------\n")
cat("All plots exported in PDF, SVG, and PNG formats:\n")
cat("  - phase1_absolute_relative_fit: Absolute (GoF) and relative (ΔAIC) fit\n")
cat("  - phase1_copula_selection_by_condition: Family selection patterns with rho/tau/lambda dots\n")
cat("  - phase1_t_copula_phase_diagram: t-copula df vs tail dependence landscape\n")
cat("  - phase1_aic_by_span: Mean AIC trends by year span\n")
cat("\nNote: Removed redundant plots - information consolidated:\n")
cat("      • selection_frequency, delta_aic_distributions, aic_weights → absolute_relative_fit\n")
cat("      • heatmap, mosaic plots, tail_dependence → copula_selection_by_condition\n\n")

cat("T-COPULA VS GAUSSIAN BY GRADE SPAN\n")
cat("-----------------------------------\n")
print(span_comparison)
cat("\n")

if (nrow(tail_analysis) > 0) {
  cat("TAIL DEPENDENCE PATTERNS\n")
  cat("------------------------\n")
  print(tail_analysis)
  cat("\n")
} else {
  cat("TAIL DEPENDENCE PATTERNS\n")
  cat("------------------------\n")
  cat("(No tail dependence data available)\n\n")
}

cat("====================================================================\n")
cat("PHASE 2 DECISION\n")
cat("====================================================================\n\n")

cat("Decision:", decision, "\n")
cat("Phase 2 families:", paste(phase2_families, collapse = ", "), "\n\n")
cat("Rationale:\n", rationale, "\n\n")

cat("====================================================================\n")
cat("NEXT STEPS\n")
cat("====================================================================\n\n")

if (decision == "SINGLE_WINNER") {
  cat("1. Review selection plots in", output_dir, "/phase1_*.pdf\n")
  cat("2. If approved, run Phase 2 experiments with", phase2_families, "copula\n")
  cat("3. Consider creating phase2_", phase2_families, "_deep_dive.R\n")
  cat("4. Run phase2_comprehensive_report.R after experiments complete\n")
} else {
  cat("1. Review selection plots in", output_dir, "/phase1_*.pdf\n")
  cat("2. If approved, run Phase 2 experiments with selected families\n")
  cat("3. Run phase2_comprehensive_report.R after experiments complete\n")
}

sink()

cat("Saved:", summary_file, "\n\n")

cat("====================================================================\n")
cat("PHASE 1 ANALYSIS COMPLETE!\n")
cat("====================================================================\n\n")

cat("Review the following files:\n")
cat("  -", summary_file, "\n")
cat("  -", output_dir, "/phase1_*.{pdf,svg,png} (multi-format visualizations)\n")
cat("  -", output_dir, "/phase1_*.csv (summary tables)\n\n")

cat("====================================================================\n")
cat("INTERPRETING AIC RESULTS WITH LARGE SAMPLES\n")
cat("====================================================================\n\n")

cat("With your large sample sizes (n ≈ 50,000-60,000), you will see:\n\n")

cat("1. VERY LARGE Δ AIC VALUES\n")
cat("   - Δ AIC > 100 or even > 1,000 is NORMAL and EXPECTED\n")
cat("   - Poor-fitting models (e.g., comonotonic) may show Δ AIC > 1,000,000\n")
cat("   - This reflects STRONG statistical evidence, not measurement error\n\n")

cat("2. AIC WEIGHTS are more intuitive:\n")
cat("   - Values close to 1.0 = model is almost certainly best\n")
cat("   - Values close to 0.0 = model has essentially no support\n")
cat("   - Sum to 1.0 across all models for each condition\n\n")

cat("3. INTERPRETATION GUIDELINES:\n")
cat("   - Δ AIC < 2:      Substantial support for both models\n")
cat("   - Δ AIC 4-7:      Considerably less support for weaker model\n")
cat("   - Δ AIC > 10:     Essentially no support for weaker model\n")
cat("   - Δ AIC > 100:    Overwhelming evidence against weaker model\n\n")

cat("4. THESE THRESHOLDS DO NOT DEPEND ON SAMPLE SIZE\n")
cat("   - Δ AIC = 10 means the same thing whether n = 200 or n = 50,000\n")
cat("   - Evidence ratio = exp(Δ AIC / 2)\n")
cat("   - Δ AIC = 10 → 148× more likely; Δ AIC = 100 → 10²¹× more likely\n\n")

cat("Your results likely show the t-copula with AIC weight ≈ 1.0 (near certainty)\n")
cat("and other families with weights ≈ 0.0 (essentially zero probability).\n")
cat("This is statistically valid and reflects the power of large samples!\n\n")

cat("If results look good, proceed to Phase 2:\n")
cat("  1. Update experiment scripts (or they'll auto-load decision)\n")
cat("  2. Run sensitivity analyses\n")
cat("  3. Generate final report\n\n")

