############################################################################
### PHASE 1: ANALYSIS AND DECISION
### Analyze copula family selection patterns and determine Phase 2 families
############################################################################

require(data.table)
require(grid)
require(wesanderson)  # For Zissou1 color palette

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

# Plot 1: Family selection frequency
pdf(file.path(output_dir, "phase1_selection_frequency.pdf"), width = 8, height = 6)
par(mar = c(5, 5, 4, 2))
barplot(selection_freq_aic$N,
        names.arg = selection_freq_aic$family,
        main = "Copula Family Selection Frequency (AIC)",
        xlab = "Copula Family",
        ylab = "Number of Conditions (Best Fit)",
        col = c("#2E7D32", "#1976D2", "#D32F2F", "#F57C00", "#7B1FA2")[1:nrow(selection_freq_aic)],
        ylim = c(0, max(selection_freq_aic$N) * 1.2))
text(x = barplot(selection_freq_aic$N, plot = FALSE),
     y = selection_freq_aic$N + max(selection_freq_aic$N) * 0.05,
     labels = paste0(selection_freq_aic$pct, "%"),
     pos = 3, cex = 1.2, font = 2)
dev.off()
cat("Created:", file.path(output_dir, "phase1_selection_frequency.pdf"), "\n")

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

# Plot 3: Box plots of delta AIC (horizontal, log scale)
pdf(file.path(output_dir, "phase1_delta_aic_distributions.pdf"), width = 10, height = 8)

# Set margins: bottom, left, top, right
# Increase left margin for family names, top margin for title spacing, right margin for selection counts
par(mar = c(5, 10, 7, 6))

# Create horizontal boxplot with log scale on x-axis
# Let R determine xlim automatically based on data range
boxplot(delta_aic_plot ~ factor(family, levels = family_order), 
        data = results,
        horizontal = TRUE,
        log = "x",
        axes = FALSE,
        col = zissou_colors,
        xlab = "",
        ylab = "",
        main = "",
        outline = FALSE)  # Suppress outliers for cleaner look with log scale

# Capture the x-axis limits for later use
xlim_range <- par("usr")[1:2]

# Add x-axis (bottom) with log-scale tick marks (extended range)
axis(1, 
     at = c(1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 100000, 1000000, 10000000),
     labels = c("0", "1", "4", "9", "19", "49", "99", "199", "499", "999", "1,999", "4,999", "9,999", "99,999", "999,999", "1e7"),
     las = 1,
     cex.axis = 0.6)

# Add top axis (side = 3) showing AIC weights (relative probability)
# Strategic tick marks at key thresholds:
# - Delta = 0 (best fit, weight = 1.0)
# - Delta = 1.39 (weight = 0.5, equiprobable with best)
# - Delta = 10 (Burnham & Anderson threshold)
# - Delta = 100 (overwhelming evidence)
# - Delta = 500 (current endpoint)
delta_for_weights <- c(0, 1.386, 10, 100, 500)
aic_weights <- exp(-delta_for_weights / 2)

axis(3,
     at = delta_for_weights + 1,  # Match the +1 offset used in plot
     labels = c("1.0", "0.5", "0.007", "2e-22", "3e-109"),  # Simplified first two labels
     las = 1,
     cex.axis = 0.75,  # Slightly larger since fewer ticks
     col.axis = "navy",
     col.ticks = "navy")

# Add y-axis (left) with pretty family names, right-justified
axis(2, 
     at = 1:length(family_order),
     labels = family_labels,
     las = 1,
     hadj = 1,  # Right justify
     cex.axis = 1.0,
     tick = FALSE)

# Add right y-axis (side 4) showing selection counts
# Calculate how many times each family was selected as best
selection_counts <- results[, .(n_best = sum(family == best_aic)), by = family]
setkey(selection_counts, family)

# Get counts in the same order as family_order
counts_ordered <- sapply(family_order, function(fam) {
  count <- selection_counts[family == fam, n_best]
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

# Add grid lines for reference
abline(v = c(1, 10, 100, 1000, 10000, 100000, 10000000), 
       col = "gray80", 
       lty = 2, 
       lwd = 0.5)

# Add reference lines for interpretation thresholds
# Placement is correct: v = delta + 1 (to match plot's +1 offset)
abline(v = 1, col = "black", lwd = 2, lty = 2)  # Delta = 0 (best fit)
abline(v = 11, col = "orange", lwd = 2, lty = 2)  # Delta = 10 threshold
abline(v = 101, col = "red", lwd = 1.5, lty = 3)  # Delta = 100 threshold

# Add axis labels using mtext
mtext(expression(Delta * "AIC + 1 (log scale)"), 
      side = 1, 
      line = 3.5, 
      cex = 1.2)

mtext("Copula Family", 
      side = 2, 
      line = 6.5, 
      cex = 1.2)

# Add right axis label for selection counts
mtext("Times Selected", 
      side = 4, 
      line = 3.5, 
      cex = 1.0,
      col = "gray30")

# Add top axis label for AIC weights
mtext("Relative AIC Weight", 
      side = 3, 
      line = 2.5, 
      cex = 1.0,
      col = "navy")

# Add title using mtext (positioned above the weight axis)
mtext(expression("Distribution of " ~ Delta * "AIC by Copula Family"), 
      side = 3, 
      line = 3.8, 
      cex = 1.3, 
      font = 2)

# Add subtle annotation for thresholds
text(x = 11, y = length(family_order) * 0.95, 
     labels = expression(Delta ~ "= 10"), 
     pos = 4, 
     col = "orange", 
     cex = 0.9, 
     font = 3)

text(x = 101, y = length(family_order) * 0.85, 
     labels = expression(Delta ~ "= 100"), 
     pos = 4, 
     col = "red", 
     cex = 0.9, 
     font = 3)

# Add annotation about data source (bottom right corner)
n_conditions <- results[, uniqueN(paste(dataset_id, condition_id))]  # Unique conditions across all datasets
n_datasets <- uniqueN(results$dataset_id)
text(x = 100000, y = 1.5,
     labels = paste0("Based upon ", n_conditions, " conditions across"),
     pos = 4,
     cex = 0.7,
     col = "gray20")
text(x = 100000, y = 1.2,
     labels = paste0(n_datasets, " longitudinal assessment datasets"),
     pos = 4,
     cex = 0.7,
     col = "gray20")

dev.off()
cat("Created:", file.path(output_dir, "phase1_delta_aic_distributions.pdf"), "\n")

# Plot 3b: AIC Weights (more intuitive than delta AIC)
pdf(file.path(output_dir, "phase1_aic_weights.pdf"), width = 10, height = 6)
par(mar = c(5, 5, 4, 2))

# Order families by mean AIC weight (use local variable to avoid overwriting global family_order)
family_order_aic <- mean_aic_by_family[order(-mean_aic_weight), family]
results[, family_ordered := factor(family, levels = family_order_aic)]

# Create color mapping for this plot
aic_colors <- zissou_colors[match(family_order_aic, family_order)]

boxplot(aic_weight ~ family_ordered, data = results,
        main = "AIC Weights: Model Selection Probabilities",
        xlab = "Copula Family",
        ylab = "AIC Weight (probability model is best)",
        col = aic_colors,
        ylim = c(0, 1),
        las = 2)
abline(h = 0.95, col = "darkgreen", lwd = 2, lty = 2)
text(x = 1, y = 0.95, labels = "95% confidence", pos = 3, col = "darkgreen", cex = 0.8)
grid()
dev.off()
cat("Created:", file.path(output_dir, "phase1_aic_weights.pdf"), "\n")

# Plot 4: Tail dependence by grade span
if (nrow(tail_analysis) > 0) {
  pdf(file.path(output_dir, "phase1_tail_dependence.pdf"), width = 10, height = 6)
  par(mar = c(5, 5, 4, 8), xpd = TRUE)
  
  # Only plot families with tail dependence
  tail_families <- c("t", "clayton", "gumbel")
  # Get colors from zissou palette based on family_order
  tail_colors <- zissou_colors[match(tail_families, family_order)]
  names(tail_colors) <- tail_families
  
  # Calculate y-axis limit safely
  max_tail <- max(c(0.01, tail_analysis[family %in% tail_families, 
                                        pmax(mean_tail_lower, mean_tail_upper, na.rm = TRUE)]), 
                  na.rm = TRUE)
  
  plot(NULL, xlim = c(1, 4), 
       ylim = c(0, max_tail),
       xlab = "Grade Span (years)", 
       ylab = "Mean Tail Dependence Coefficient",
       main = "Tail Dependence by Grade Span",
       xaxt = "n")
  axis(1, at = 1:4)
  grid()
  
  for (fam in tail_families) {
    fam_data <- tail_analysis[family == fam & year_span %in% 1:4]
    if (nrow(fam_data) > 0) {
      # Plot upper tail if present
      if (any(fam_data$mean_tail_upper > 0, na.rm = TRUE)) {
        lines(fam_data$year_span, fam_data$mean_tail_upper, 
              col = tail_colors[fam], lwd = 2, type = "o", pch = 16)
      }
      # Plot lower tail if present  
      if (any(fam_data$mean_tail_lower > 0, na.rm = TRUE)) {
        lines(fam_data$year_span, fam_data$mean_tail_lower, 
              col = tail_colors[fam], lwd = 2, type = "o", pch = 1, lty = 2)
      }
    }
  }
  
  legend("topright", inset = c(-0.25, 0),
         legend = c("t (symmetric)", "Clayton (lower)", "Gumbel (upper)"),
         col = tail_colors,
         lwd = 2, pch = c(16, 1, 16),
         lty = c(1, 2, 1),
         title = "Copula Family")
  dev.off()
  cat("Created:", file.path(output_dir, "phase1_tail_dependence.pdf"), "\n")
} else {
  cat("Skipped:", file.path(output_dir, "phase1_tail_dependence.pdf"), "(no tail analysis data)\n")
}

# Plot 5: Heatmap of best family by span and content
pdf(file.path(output_dir, "phase1_heatmap.pdf"), width = 10, height = 6)

# Create matrix for heatmap
best_by_span_content <- results[, .SD[which.min(aic)], by = .(dataset_id, condition_id, year_span, content_area)][
  , .N, by = .(year_span, content_area, family)]

# Convert to wide format for visualization
heatmap_data <- dcast(best_by_span_content, 
                      year_span + content_area ~ family, 
                      value.var = "N", fill = 0)

# Simple visualization
par(mar = c(10, 10, 4, 2))
text_matrix <- as.matrix(heatmap_data[, -c(1:2)])
rownames(text_matrix) <- paste0("Span", heatmap_data$year_span, "_", heatmap_data$content_area)

image(1:ncol(text_matrix), 1:nrow(text_matrix), 
      t(text_matrix),
      col = colorRampPalette(c("white", "darkgreen"))(10),
      xlab = "", ylab = "",
      main = "Best Family Selection: Grade Span × Content Area",
      xaxt = "n", yaxt = "n")
axis(1, at = 1:ncol(text_matrix), labels = names(heatmap_data)[-c(1:2)], las = 2)
axis(2, at = 1:nrow(text_matrix), labels = rownames(text_matrix), las = 2)

# Add values
for (i in 1:nrow(text_matrix)) {
  for (j in 1:ncol(text_matrix)) {
    if (text_matrix[i, j] > 0) {
      text(j, i, text_matrix[i, j], cex = 1.5, font = 2)
    }
  }
}

dev.off()
cat("Created:", file.path(output_dir, "phase1_heatmap.pdf"), "\n\n")

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
cat("  -", output_dir, "/phase1_*.pdf\n")
cat("  -", output_dir, "/phase1_aic_weights_summary.csv\n\n")

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

