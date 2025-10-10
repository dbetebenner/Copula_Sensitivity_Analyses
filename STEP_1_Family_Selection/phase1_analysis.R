############################################################################
### PHASE 1: ANALYSIS AND DECISION
### Analyze copula family selection patterns and determine Phase 2 families
############################################################################

require(data.table)
require(grid)

cat("====================================================================\n")
cat("PHASE 1: FAMILY SELECTION ANALYSIS\n")
cat("====================================================================\n\n")

# Load Phase 1 results
results_file <- "STEP_1_Family_Selection/results/phase1_copula_family_comparison.csv"

if (!file.exists(results_file)) {
  stop("Phase 1 results not found! Run phase1_family_selection.R first.")
}

results <- fread(results_file)

cat("Loaded results from:", results_file, "\n")
cat("Conditions tested:", uniqueN(results$condition_id), "\n")
cat("Total fits:", nrow(results), "\n\n")

################################################################################
### ANALYSIS 1: OVERALL WINNER
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 1: OVERALL FAMILY SELECTION FREQUENCY\n")
cat("====================================================================\n\n")

# Count selection frequency by AIC
selection_freq_aic <- results[, .SD[which.min(aic)], by = condition_id][, .N, by = family]
setorder(selection_freq_aic, -N)
selection_freq_aic[, pct := round(100 * N / sum(N), 1)]

cat("Selection frequency by AIC:\n")
print(selection_freq_aic)
cat("\n")

# Count selection frequency by BIC
selection_freq_bic <- results[, .SD[which.min(bic)], by = condition_id][, .N, by = family]
setorder(selection_freq_bic, -N)
selection_freq_bic[, pct := round(100 * N / sum(N), 1)]

cat("Selection frequency by BIC:\n")
print(selection_freq_bic)
cat("\n")

# Mean AIC advantage
mean_aic_by_family <- results[, .(
  mean_aic = mean(aic),
  sd_aic = sd(aic),
  mean_delta = mean(delta_aic_vs_best)
), by = family]
setorder(mean_aic_by_family, mean_aic)

cat("Mean AIC by family:\n")
print(mean_aic_by_family)
cat("\n")

################################################################################
### ANALYSIS 2: PATTERN BY GRADE SPAN
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 2: FAMILY SELECTION BY GRADE SPAN\n")
cat("====================================================================\n\n")

# Best family by grade span
by_span <- results[, .SD[which.min(aic)], by = .(condition_id, grade_span)][
  , .(
    winner = names(sort(table(family), decreasing = TRUE)[1]),
    t_selected = sum(family == "t"),
    gaussian_selected = sum(family == "gaussian"),
    total = .N
  ), by = grade_span]

by_span[, t_pct := round(100 * t_selected / total, 1)]
by_span[, gaussian_pct := round(100 * gaussian_selected / total, 1)]
setorder(by_span, grade_span)

cat("Selection patterns by grade span:\n")
print(by_span)
cat("\n")

# Mean delta AIC: t-copula vs Gaussian by grade span
t_vs_gaussian <- merge(
  results[family == "t", .(condition_id, grade_span, aic_t = aic)],
  results[family == "gaussian", .(condition_id, aic_gaussian = aic)],
  by = "condition_id"
)
t_vs_gaussian[, delta_aic := aic_gaussian - aic_t]

span_comparison <- t_vs_gaussian[, .(
  mean_delta_aic = mean(delta_aic),
  sd_delta_aic = sd(delta_aic),
  t_better_count = sum(delta_aic > 0),
  total = .N
), by = grade_span]
span_comparison[, t_better_pct := round(100 * t_better_count / total, 1)]
setorder(span_comparison, grade_span)

cat("T-copula vs Gaussian by grade span (positive = t better):\n")
print(span_comparison)
cat("\n")

################################################################################
### ANALYSIS 3: PATTERN BY CONTENT AREA
################################################################################

cat("====================================================================\n")
cat("ANALYSIS 3: FAMILY SELECTION BY CONTENT AREA\n")
cat("====================================================================\n\n")

by_content <- results[, .SD[which.min(aic)], by = .(condition_id, content_area)][
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
required_cols <- c("tail_dep_lower", "tail_dep_upper", "tau", "family", "grade_span")
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
    n = .N
  ), by = .(family, grade_span)]
  setorder(tail_analysis, grade_span, family)
  
  cat("Tail dependence patterns:\n")
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
pdf("STEP_1_Family_Selection/results/phase1_selection_frequency.pdf", width = 8, height = 6)
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
cat("Created: STEP_1_Family_Selection/results/phase1_selection_frequency.pdf\n")

# Plot 2: AIC advantage by grade span
pdf("STEP_1_Family_Selection/results/phase1_aic_by_span.pdf", width = 10, height = 6)
par(mar = c(5, 5, 4, 8), xpd = TRUE)

families <- unique(results$family)
colors <- c("#1976D2", "#2E7D32", "#D32F2F", "#F57C00", "#7B1FA2")
names(colors) <- c("gaussian", "t", "clayton", "gumbel", "frank")

# Calculate mean AIC by family and span
span_aic <- results[, .(mean_aic = mean(aic)), by = .(family, grade_span)]

# Plot lines
plot(NULL, xlim = c(1, 4), ylim = range(span_aic$mean_aic),
     xlab = "Grade Span (years)", ylab = "Mean AIC",
     main = "Mean AIC by Copula Family and Grade Span",
     xaxt = "n")
axis(1, at = 1:4)
grid()

for (fam in families) {
  fam_data <- span_aic[family == fam]
  if (nrow(fam_data) > 0) {
    lines(fam_data$grade_span, fam_data$mean_aic, 
          col = colors[fam], lwd = 2, type = "o", pch = 16)
  }
}

legend("topright", inset = c(-0.25, 0),
       legend = families,
       col = colors[families],
       lwd = 2, pch = 16,
       title = "Copula Family")
dev.off()
cat("Created: STEP_1_Family_Selection/results/phase1_aic_by_span.pdf\n")

# Plot 3: Box plots of delta AIC
pdf("STEP_1_Family_Selection/results/phase1_delta_aic_distributions.pdf", width = 10, height = 6)
par(mar = c(5, 5, 4, 2))
boxplot(delta_aic_vs_best ~ family, data = results,
        main = expression("Distribution of" ~ Delta * "AIC vs Best Family"),
        xlab = "Copula Family",
        ylab = expression(Delta * "AIC (0 = best fit)"),
        col = colors[unique(results$family)],
        ylim = c(0, quantile(results$delta_aic_vs_best, 0.95)))
abline(h = 0, col = "red", lwd = 2, lty = 2)
abline(h = 10, col = "orange", lwd = 1, lty = 2)
text(x = 1, y = 10, labels = expression(Delta ~ "= 10"), pos = 3, col = "orange")
dev.off()
cat("Created: STEP_1_Family_Selection/results/phase1_delta_aic_distributions.pdf\n")

# Plot 4: Tail dependence by grade span
if (nrow(tail_analysis) > 0) {
  pdf("STEP_1_Family_Selection/results/phase1_tail_dependence.pdf", width = 10, height = 6)
  par(mar = c(5, 5, 4, 8), xpd = TRUE)
  
  # Only plot families with tail dependence
  tail_families <- c("t", "clayton", "gumbel")
  tail_colors <- colors[tail_families]
  
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
    fam_data <- tail_analysis[family == fam & grade_span %in% 1:4]
    if (nrow(fam_data) > 0) {
      # Plot upper tail if present
      if (any(fam_data$mean_tail_upper > 0, na.rm = TRUE)) {
        lines(fam_data$grade_span, fam_data$mean_tail_upper, 
              col = tail_colors[fam], lwd = 2, type = "o", pch = 16)
      }
      # Plot lower tail if present  
      if (any(fam_data$mean_tail_lower > 0, na.rm = TRUE)) {
        lines(fam_data$grade_span, fam_data$mean_tail_lower, 
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
  cat("Created: STEP_1_Family_Selection/results/phase1_tail_dependence.pdf\n")
} else {
  cat("Skipped: STEP_1_Family_Selection/results/phase1_tail_dependence.pdf (no tail analysis data)\n")
}

# Plot 5: Heatmap of best family by span and content
pdf("STEP_1_Family_Selection/results/phase1_heatmap.pdf", width = 10, height = 6)

# Create matrix for heatmap
best_by_span_content <- results[, .SD[which.min(aic)], by = .(condition_id, grade_span, content_area)][
  , .N, by = .(grade_span, content_area, family)]

# Convert to wide format for visualization
heatmap_data <- dcast(best_by_span_content, 
                      grade_span + content_area ~ family, 
                      value.var = "N", fill = 0)

# Simple visualization
par(mar = c(10, 10, 4, 2))
text_matrix <- as.matrix(heatmap_data[, -c(1:2)])
rownames(text_matrix) <- paste0("Span", heatmap_data$grade_span, "_", heatmap_data$content_area)

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
cat("Created: STEP_1_Family_Selection/results/phase1_heatmap.pdf\n\n")

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
  span_winners <- by_span[, .(family = winner, pct = t_pct), by = grade_span]
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
     file = "STEP_1_Family_Selection/results/phase1_decision.RData")
cat("Saved: STEP_1_Family_Selection/results/phase1_decision.RData\n")

# Save selection table
fwrite(selection_freq_aic, "STEP_1_Family_Selection/results/phase1_selection_table.csv")
cat("Saved: STEP_1_Family_Selection/results/phase1_selection_table.csv\n")

# Write text summary
summary_file <- "STEP_1_Family_Selection/results/phase1_summary.txt"
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
  cat("1. Review selection plots in STEP_1_Family_Selection/results/phase1_*.pdf\n")
  cat("2. If approved, run Phase 2 experiments with", phase2_families, "copula\n")
  cat("3. Consider creating phase2_", phase2_families, "_deep_dive.R\n")
  cat("4. Run phase2_comprehensive_report.R after experiments complete\n")
} else {
  cat("1. Review selection plots in STEP_1_Family_Selection/results/phase1_*.pdf\n")
  cat("2. If approved, run Phase 2 experiments with selected families\n")
  cat("3. Run phase2_comprehensive_report.R after experiments complete\n")
}

sink()

cat("Saved: STEP_1_Family_Selection/results/phase1_summary.txt\n\n")

cat("====================================================================\n")
cat("PHASE 1 ANALYSIS COMPLETE!\n")
cat("====================================================================\n\n")

cat("Review the following files:\n")
cat("  - STEP_1_Family_Selection/results/phase1_summary.txt\n")
cat("  - STEP_1_Family_Selection/results/phase1_*.pdf\n\n")

cat("If results look good, proceed to Phase 2:\n")
cat("  1. Update experiment scripts (or they'll auto-load decision)\n")
cat("  2. Run sensitivity analyses\n")
cat("  3. Generate final report\n\n")

