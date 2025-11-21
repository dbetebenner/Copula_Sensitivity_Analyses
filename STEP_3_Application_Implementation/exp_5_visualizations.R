############################################################################
### EXPERIMENT 5: VISUALIZATION SCRIPT
### Publication-quality figures for transformation method validation
############################################################################

require(data.table)
require(grid)

# Load results from exp_5_transformation_validation.R
if (!exists("all_results")) {
  load("STEP_2_Transformation_Validation/results/exp5_transformation_validation_full.RData")
}

cat("====================================================================\n")
cat("EXPERIMENT 5: GENERATING VISUALIZATIONS\n")
cat("====================================================================\n\n")

# Create output directory
dir.create("STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation", 
           showWarnings = FALSE, recursive = TRUE)

################################################################################
### FIGURE 1: METHOD COMPARISON DASHBOARD (4x4 GRID FOR EACH METHOD)
################################################################################

create_method_dashboard <- function(method_name, results, empirical_U, empirical_V) {
  
  U <- results$U
  V <- results$V
  
  pdf(paste0("STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/", method_name, "_dashboard.pdf"),
      width = 10, height = 10)
  
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
  
  # Panel 1: Histogram of U
  hist(U, breaks = 50, col = "steelblue", border = "white",
       main = paste("U Distribution -", results$method$label),
       xlab = "U (Pseudo-observations)", ylab = "Frequency")
  abline(h = length(U)/50, col = "red", lty = 2, lwd = 2)  # Expected uniform height
  
  # Panel 2: Q-Q plot for U
  qqplot(qunif(ppoints(length(U))), U,
         main = "U Q-Q Plot vs Uniform(0,1)",
         xlab = "Theoretical Quantiles", ylab = "Sample Quantiles",
         pch = 20, cex = 0.3, col = rgb(0, 0, 0, 0.3))
  abline(0, 1, col = "red", lwd = 2)
  
  # Panel 3: Scatter of U vs V
  plot(U, V, pch = 20, cex = 0.3, col = rgb(0, 0, 0, 0.3),
       main = "Pseudo-Observations (U vs V)",
       xlab = "U (Prior)", ylab = "V (Current)")
  # Overlay empirical ranks for comparison
  points(sample(empirical_U, min(1000, length(empirical_U))),
         sample(empirical_V, min(1000, length(empirical_V))),
         pch = 20, cex = 0.2, col = rgb(1, 0, 0, 0.1))
  legend("topleft", legend = c("This method", "Empirical ranks"),
         col = c(rgb(0, 0, 0, 0.5), rgb(1, 0, 0, 0.5)),
         pch = 20, bg = "white")
  
  # Panel 4: Chi-plot for tail dependence
  h_seq <- seq(0.5, 0.99, length = 50)
  chi_vals <- sapply(h_seq, function(h) {
    in_tail <- (U > h) & (V > h)
    if (sum(in_tail) < 10) return(NA)
    sum(in_tail) / sum(U > h)
  })
  
  chi_vals_emp <- sapply(h_seq, function(h) {
    in_tail <- (empirical_U > h) & (empirical_V > h)
    if (sum(in_tail) < 10) return(NA)
    sum(in_tail) / sum(empirical_U > h)
  })
  
  plot(h_seq, chi_vals, type = "l", lwd = 2, col = "black",
       main = "Upper Tail Dependence (Chi-plot)",
       xlab = "Threshold", ylab = expression(chi),
       ylim = range(c(chi_vals, chi_vals_emp), na.rm = TRUE))
  lines(h_seq, chi_vals_emp, col = "red", lwd = 2, lty = 2)
  legend("topleft", legend = c("This method", "Empirical ranks"),
         col = c("black", "red"), lty = c(1, 2), lwd = 2, bg = "white")
  
  dev.off()
  
  cat("  Dashboard saved:", method_name, "\n")
}

# Generate dashboards for key methods
key_methods <- c("empirical_n_plus_1", "ispline_4knots", "ispline_9knots", 
                 "ispline_19knots", "qspline")

empirical_U <- all_results[["empirical_n_plus_1"]]$U
empirical_V <- all_results[["empirical_n_plus_1"]]$V

cat("Generating method dashboards...\n")
for (method in key_methods) {
  if (method %in% names(all_results)) {
    create_method_dashboard(method, all_results[[method]], empirical_U, empirical_V)
  }
}
cat("\n")

################################################################################
### FIGURE 2: UNIFORMITY TEST FOREST PLOT
################################################################################

cat("Generating uniformity test forest plot...\n")

pdf("STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/uniformity_forest_plot.pdf",
    width = 10, height = 8)

par(mar = c(5, 12, 4, 2))

# Extract K-S p-values
ks_pvals <- sapply(all_results, function(x) x$uniformity$combined_ks_pval)
method_labels <- sapply(all_results, function(x) x$method$label)

# Sort by p-value
order_idx <- order(ks_pvals, decreasing = TRUE)
ks_pvals <- ks_pvals[order_idx]
method_labels <- method_labels[order_idx]

# Color code
colors <- ifelse(ks_pvals > 0.05, "darkgreen",
                ifelse(ks_pvals > 0.01, "orange", "red"))

# Plot
y_pos <- 1:length(ks_pvals)
plot(ks_pvals, y_pos, xlim = c(0, max(ks_pvals, 0.1)), pch = 19, 
     col = colors, cex = 1.5,
     yaxt = "n", xlab = "K-S Test p-value", ylab = "",
     main = "Uniformity Test Results (Combined U & V)")
axis(2, at = y_pos, labels = method_labels, las = 1, cex.axis = 0.8)

# Add reference lines
abline(v = 0.05, col = "darkgreen", lty = 2, lwd = 2)
abline(v = 0.01, col = "orange", lty = 2, lwd = 2)

# Add legend
legend("bottomright", 
       legend = c("p > 0.05 (Pass)", "0.01 < p < 0.05 (Marginal)", "p < 0.01 (Fail)"),
       col = c("darkgreen", "orange", "red"),
       pch = 19, cex = 0.9, bg = "white")

dev.off()
cat("  Uniformity forest plot saved\n\n")

################################################################################
### FIGURE 3: TAIL CONCENTRATION COMPARISON
################################################################################

cat("Generating tail concentration comparison...\n")

pdf("STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/tail_concentration_comparison.pdf",
    width = 12, height = 6)

par(mfrow = c(1, 2), mar = c(10, 4, 3, 1))

# Lower tail (10%)
lower_10 <- sapply(all_results, function(x) x$tail$lower_10)
empirical_lower <- empirical_baseline$tail$lower_10

barplot(lower_10, names.arg = rep("", length(lower_10)),
        col = "steelblue", border = "white",
        main = "Lower Tail Concentration (10th Percentile)",
        ylab = "Proportion in Joint Lower Tail",
        las = 2)
abline(h = empirical_lower, col = "red", lwd = 3, lty = 2)
axis(1, at = 1:length(lower_10), labels = names(lower_10), 
     las = 2, cex.axis = 0.7)

# Upper tail (90%)
upper_90 <- sapply(all_results, function(x) x$tail$upper_90)
empirical_upper <- empirical_baseline$tail$upper_90

barplot(upper_90, names.arg = rep("", length(upper_90)),
        col = "darkgreen", border = "white",
        main = "Upper Tail Concentration (90th Percentile)",
        ylab = "Proportion in Joint Upper Tail",
        las = 2)
abline(h = empirical_upper, col = "red", lwd = 3, lty = 2)
axis(1, at = 1:length(upper_90), labels = names(upper_90), 
     las = 2, cex.axis = 0.7)

dev.off()
cat("  Tail concentration comparison saved\n\n")

################################################################################
### FIGURE 4: COPULA SELECTION RESULTS
################################################################################

cat("Generating copula selection results...\n")

pdf("STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/copula_selection_results.pdf",
    width = 10, height = 8)

par(mar = c(10, 4, 3, 1))

# Extract best copula families and AIC differences
best_copulas <- sapply(all_results, function(x) x$copula_results$best_family)
aic_deltas <- sapply(all_results, function(x) x$copula_results$aic_delta_from_empirical)
correct <- (best_copulas == empirical_baseline$best_family)

# Color code by copula family
copula_colors <- c(
  "gaussian" = "blue",
  "t" = "darkgreen",
  "clayton" = "orange",
  "gumbel" = "purple",
  "frank" = "red"
)

bar_colors <- sapply(best_copulas, function(fam) copula_colors[fam])
bar_colors[correct] <- adjustcolor(bar_colors[correct], alpha.f = 1.0)
bar_colors[!correct] <- adjustcolor(bar_colors[!correct], alpha.f = 0.5)

barplot(aic_deltas, names.arg = rep("", length(aic_deltas)),
        col = bar_colors, border = "white",
        main = expression(paste("Copula Selection: ", Delta, "AIC from Empirical Best")),
        ylab = expression(paste(Delta, "AIC")),
        las = 2)
axis(1, at = 1:length(aic_deltas), labels = names(aic_deltas), 
     las = 2, cex.axis = 0.7)
abline(h = 0, col = "black", lwd = 2)

# Add legend
legend("topleft", 
       legend = c("Gaussian", "t-copula", "Clayton", "Gumbel", "Frank", "", 
                 "Solid = Correct", "Faded = Wrong"),
       fill = c(copula_colors, NA, NA, NA),
       border = c(rep("white", 5), NA, NA, NA),
       cex = 0.8, bg = "white")

dev.off()
cat("  Copula selection results saved\n\n")

################################################################################
### FIGURE 5: TRADE-OFF SPACE (UNIFORMITY VS COPULA CORRECTNESS)
################################################################################

cat("Generating trade-off space plot...\n")

pdf("STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/tradeoff_space.pdf",
    width = 10, height = 8)

par(mar = c(5, 5, 4, 2))

# Extract metrics
ks_pvals <- sapply(all_results, function(x) x$uniformity$combined_ks_pval)
aic_deltas <- sapply(all_results, function(x) x$copula_results$aic_delta_from_empirical)
correct <- sapply(all_results, function(x) 
  x$copula_results$best_family == empirical_baseline$best_family)

# Color and shape by classification
classifications <- sapply(all_results, function(x) x$classification$classification)
class_colors <- c(
  "EXCELLENT" = "darkgreen",
  "ACCEPTABLE" = "green",
  "MARGINAL" = "orange",
  "UNACCEPTABLE" = "red"
)
colors <- sapply(classifications, function(c) class_colors[c])

# Plot
plot(ks_pvals, aic_deltas, 
     col = colors, pch = ifelse(correct, 19, 1), cex = 2,
     xlab = "Uniformity (K-S p-value, higher = better)",
     ylab = expression(paste(Delta, "AIC from Empirical (lower = better)")),
     main = "Transformation Method Trade-off Space",
     xlim = c(0, max(ks_pvals)), ylim = range(aic_deltas))

# Add quadrant lines
abline(v = 0.05, col = "gray", lty = 2)
abline(h = 100, col = "gray", lty = 2)

# Add quadrant labels
text(0.025, max(aic_deltas) * 0.9, "Bad uniformity\nWrong copula", 
     col = "red", cex = 0.9)
text(max(ks_pvals) * 0.7, max(aic_deltas) * 0.9, "Good uniformity\nWrong copula", 
     col = "orange", cex = 0.9)
text(max(ks_pvals) * 0.7, min(aic_deltas) * 0.9, "Good uniformity\nCorrect copula\n(IDEAL)", 
     col = "darkgreen", cex = 0.9, font = 2)

# Add method labels for key points
text(ks_pvals, aic_deltas, names(all_results), pos = 3, cex = 0.6)

# Legend
legend("topright",
       legend = c("EXCELLENT", "ACCEPTABLE", "MARGINAL", "UNACCEPTABLE", "",
                 "Filled = Correct copula", "Open = Wrong copula"),
       col = c(class_colors, NA, "black", "black"),
       pch = c(rep(19, 4), NA, 19, 1),
       cex = 0.8, bg = "white")

dev.off()
cat("  Trade-off space plot saved\n\n")

################################################################################
### FIGURE 6: SUMMARY COMPARISON (SELECTED METHODS ONLY)
################################################################################

cat("Generating summary comparison for key methods...\n")

# Select key methods: empirical, ispline variants, qspline
key_methods <- c("empirical_n_plus_1", "mid_ranks", 
                 "ispline_4knots", "ispline_9knots", "ispline_19knots",
                 "qspline", "hyman")

if (!all(key_methods %in% names(all_results))) {
  key_methods <- key_methods[key_methods %in% names(all_results)]
}

pdf("STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/key_methods_comparison.pdf",
    width = 14, height = 10)

par(mfrow = c(2, 3), mar = c(5, 4, 3, 1))

for (i in 1:6) {
  if (i <= length(key_methods)) {
    method <- key_methods[i]
    res <- all_results[[method]]
    
    # Scatter plot with empirical overlay
    plot(res$U, res$V, pch = 20, cex = 0.3, col = rgb(0, 0, 0, 0.3),
         main = res$method$label,
         xlab = "U (Prior)", ylab = "V (Current)")
    
    # Add classification badge
    badge_color <- class_colors[res$classification$classification]
    rect(0.7, 0.05, 0.95, 0.15, col = badge_color, border = NA)
    text(0.825, 0.1, res$classification$classification, 
         col = "white", cex = 0.7, font = 2)
    
    # Add K-S p-value
    text(0.05, 0.95, sprintf("K-S p = %.3f", res$uniformity$combined_ks_pval),
         adj = c(0, 1), cex = 0.8)
    
    # Add best copula
    text(0.05, 0.88, paste("Copula:", res$copula_results$best_family),
         adj = c(0, 1), cex = 0.8,
         col = ifelse(res$copula_results$best_family == empirical_baseline$best_family,
                     "darkgreen", "red"))
  }
}

dev.off()
cat("  Key methods comparison saved\n\n")

################################################################################
### SUMMARY
################################################################################

cat("====================================================================\n")
cat("VISUALIZATION COMPLETE\n")
cat("====================================================================\n\n")

cat("Generated figures:\n")
cat("  1. Method dashboards (4x4 grids) for key methods\n")
cat("  2. Uniformity test forest plot\n")
cat("  3. Tail concentration comparison\n")
cat("  4. Copula selection results\n")
cat("  5. Trade-off space plot\n")
cat("  6. Key methods comparison\n\n")

cat("All figures saved to: figures/exp5_transformation_validation/\n\n")

