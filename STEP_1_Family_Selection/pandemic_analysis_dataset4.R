############################################################################
### PANDEMIC COPULA ANALYSIS: Dataset 4 (Hawaii)
### 
### Purpose: Focused comparison of pandemic-era (2019-2021) copula fits
###          versus pre-pandemic baselines to quantify COVID-19 impact
###          on longitudinal dependency structure
###
### Research Question: Did the pandemic disrupt the copula dependency
###                     structure in educational assessments?
###
### Usage: Run AFTER phase1_family_selection.R completes for dataset_4
###        source("STEP_1_Family_Selection/pandemic_analysis_dataset4.R")
############################################################################

require(data.table)
require(ggplot2)
require(copula)

cat("====================================================================\n")
cat("PANDEMIC COPULA ANALYSIS: Dataset 4\n")
cat("====================================================================\n")
cat("Comparing 2019-2021 pandemic copulas to pre-pandemic baselines\n")
cat("====================================================================\n\n")

################################################################################
### LOAD RESULTS
################################################################################

results_file <- "STEP_1_Family_Selection/results/dataset_4/phase1_copula_family_comparison.csv"

if (!file.exists(results_file)) {
  stop("ERROR: Results file not found. Run phase1_family_selection.R first.\n",
       "Expected file: ", results_file)
}

cat("Loading results from:", results_file, "\n")
results <- fread(results_file)
cat("✓ Loaded", nrow(results), "rows\n\n")

# Filter to dataset_4 only (should already be filtered)
if ("dataset_id" %in% names(results)) {
  results <- results[dataset_id == "dataset_4"]
  cat("Filtered to dataset_4:", nrow(results), "rows\n\n")
}

################################################################################
### IDENTIFY PANDEMIC AND BASELINE PAIRS
################################################################################

cat("Identifying pandemic and baseline pairs...\n")

# Pandemic pairs: 2019-2021 or 2018-2021
pandemic_conditions <- results[
  grepl("^(2019|2018)_", condition_id) & 
  grepl("2021", condition_id),
  unique(condition_id)
]

cat("Pandemic conditions found:", length(pandemic_conditions), "\n")
print(pandemic_conditions)
cat("\n")

# Pre-pandemic baseline pairs: 2017-2019 or 2016-2019
baseline_conditions <- results[
  grepl("^(2017|2016)_", condition_id) & 
  grepl("2019", condition_id),
  unique(condition_id)
]

cat("Baseline conditions found:", length(baseline_conditions), "\n")
print(baseline_conditions)
cat("\n")

################################################################################
### CREATE MATCHED PAIRS
################################################################################

cat("Creating matched pandemic-baseline pairs...\n")

# Define matching logic
# 2019_G3_G5_MATHEMATICS -> 2017_G3_G5_MATHEMATICS (2-year span)
# 2018_G8_G11_MATHEMATICS -> 2016_G8_G11_MATHEMATICS (3-year span)

matched_pairs <- list(
  list(
    pandemic = "2019_G3_G5_MATHEMATICS",
    baseline = "2017_G3_G5_MATHEMATICS",
    label = "G3→G5 MATH"
  ),
  list(
    pandemic = "2019_G3_G5_READING",
    baseline = "2017_G3_G5_READING",
    label = "G3→G5 READ"
  ),
  list(
    pandemic = "2019_G4_G6_MATHEMATICS",
    baseline = "2017_G4_G6_MATHEMATICS",
    label = "G4→G6 MATH"
  ),
  list(
    pandemic = "2019_G4_G6_READING",
    baseline = "2017_G4_G6_READING",
    label = "G4→G6 READ"
  ),
  list(
    pandemic = "2019_G5_G7_MATHEMATICS",
    baseline = "2017_G5_G7_MATHEMATICS",
    label = "G5→G7 MATH"
  ),
  list(
    pandemic = "2019_G5_G7_READING",
    baseline = "2017_G5_G7_READING",
    label = "G5→G7 READ"
  ),
  list(
    pandemic = "2019_G6_G8_MATHEMATICS",
    baseline = "2017_G6_G8_MATHEMATICS",
    label = "G6→G8 MATH"
  ),
  list(
    pandemic = "2019_G6_G8_READING",
    baseline = "2017_G6_G8_READING",
    label = "G6→G8 READ"
  ),
  list(
    pandemic = "2018_G8_G11_MATHEMATICS",
    baseline = "2016_G8_G11_MATHEMATICS",
    label = "G8→G11 MATH (3yr)"
  ),
  list(
    pandemic = "2018_G8_G11_READING",
    baseline = "2016_G8_G11_READING",
    label = "G8→G11 READ (3yr)"
  )
)

cat("Total matched pairs:", length(matched_pairs), "\n\n")

################################################################################
### PARAMETER COMPARISON: T-COPULA
################################################################################

cat("====================================================================\n")
cat("T-COPULA PARAMETER COMPARISON\n")
cat("====================================================================\n\n")

# Focus on t-copula (expected winner from STEP 1)
t_results <- results[family == "t"]

comparison_table <- data.table()

for (pair in matched_pairs) {
  pandemic_row <- t_results[condition_id == pair$pandemic]
  baseline_row <- t_results[condition_id == pair$baseline]
  
  if (nrow(pandemic_row) == 0 || nrow(baseline_row) == 0) {
    cat("WARNING: Missing data for", pair$label, "\n")
    next
  }
  
  # Calculate changes
  delta_rho <- pandemic_row$rho - baseline_row$rho
  delta_tau <- pandemic_row$tau - baseline_row$tau
  delta_df <- pandemic_row$df - baseline_row$df
  delta_tail_dep <- pandemic_row$tail_dep_upper - baseline_row$tail_dep_upper
  
  # Store in comparison table
  comparison_table <- rbind(comparison_table, data.table(
    pair_label = pair$label,
    pandemic_condition = pair$pandemic,
    baseline_condition = pair$baseline,
    
    # Baseline parameters
    baseline_rho = baseline_row$rho,
    baseline_tau = baseline_row$tau,
    baseline_df = baseline_row$df,
    baseline_tail_dep = baseline_row$tail_dep_upper,
    baseline_n = baseline_row$n,
    
    # Pandemic parameters
    pandemic_rho = pandemic_row$rho,
    pandemic_tau = pandemic_row$tau,
    pandemic_df = pandemic_row$df,
    pandemic_tail_dep = pandemic_row$tail_dep_upper,
    pandemic_n = pandemic_row$n,
    
    # Changes
    delta_rho = delta_rho,
    delta_tau = delta_tau,
    delta_df = delta_df,
    delta_tail_dep = delta_tail_dep,
    
    # Percent changes
    pct_change_rho = 100 * delta_rho / baseline_row$rho,
    pct_change_tau = 100 * delta_tau / baseline_row$tau,
    pct_change_df = 100 * delta_df / baseline_row$df,
    pct_change_tail_dep = 100 * delta_tail_dep / baseline_row$tail_dep_upper
  ))
}

# Print comparison table
cat("PARAMETER CHANGES: Pandemic vs. Baseline\n")
cat(paste(rep("-", 80), collapse = ""), "\n")
print(comparison_table[, .(pair_label, 
                           baseline_tau, pandemic_tau, delta_tau, pct_change_tau,
                           baseline_df, pandemic_df, delta_df)])
cat("\n")

# Summary statistics
cat("SUMMARY OF PARAMETER CHANGES\n")
cat(paste(rep("-", 80), collapse = ""), "\n")
cat(sprintf("Kendall's tau change:  Mean = %.4f, SD = %.4f, Range = [%.4f, %.4f]\n",
            mean(comparison_table$delta_tau), sd(comparison_table$delta_tau),
            min(comparison_table$delta_tau), max(comparison_table$delta_tau)))
cat(sprintf("Degrees of freedom:    Mean = %.2f, SD = %.2f, Range = [%.2f, %.2f]\n",
            mean(comparison_table$delta_df), sd(comparison_table$delta_df),
            min(comparison_table$delta_df), max(comparison_table$delta_df)))
cat(sprintf("Tail dependence:       Mean = %.4f, SD = %.4f, Range = [%.4f, %.4f]\n",
            mean(comparison_table$delta_tail_dep), sd(comparison_table$delta_tail_dep),
            min(comparison_table$delta_tail_dep), max(comparison_table$delta_tail_dep)))
cat("\n")

################################################################################
### VISUALIZATIONS
################################################################################

cat("Generating pandemic comparison visualizations...\n")

output_dir <- "STEP_1_Family_Selection/results/dataset_4/pandemic_analysis"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# 1. Parameter Change Plot: Kendall's tau
p1 <- ggplot(comparison_table, aes(x = reorder(pair_label, delta_tau), y = delta_tau)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_col(aes(fill = delta_tau > 0)) +
  coord_flip() +
  scale_fill_manual(values = c("TRUE" = "steelblue", "FALSE" = "coral"), guide = "none") +
  labs(
    title = "Change in Kendall's τ: Pandemic (2019-2021) vs. Baseline (2017-2019)",
    subtitle = "Dataset 4 (Hawaii) - T-Copula",
    x = NULL,
    y = "Δτ (Pandemic - Baseline)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.major.y = element_blank()
  )

ggsave(file.path(output_dir, "pandemic_tau_change.pdf"), p1, width = 10, height = 6)
cat("✓ Saved:", file.path(output_dir, "pandemic_tau_change.pdf"), "\n")

# 2. Parameter Change Plot: Degrees of Freedom
p2 <- ggplot(comparison_table, aes(x = reorder(pair_label, delta_df), y = delta_df)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  geom_col(aes(fill = delta_df > 0)) +
  coord_flip() +
  scale_fill_manual(values = c("TRUE" = "steelblue", "FALSE" = "coral"), guide = "none") +
  labs(
    title = "Change in Degrees of Freedom: Pandemic vs. Baseline",
    subtitle = "Dataset 4 (Hawaii) - T-Copula (higher df = lighter tails)",
    x = NULL,
    y = "Δdf (Pandemic - Baseline)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.major.y = element_blank()
  )

ggsave(file.path(output_dir, "pandemic_df_change.pdf"), p2, width = 10, height = 6)
cat("✓ Saved:", file.path(output_dir, "pandemic_df_change.pdf"), "\n")

# 3. Scatter: Baseline vs. Pandemic tau
p3 <- ggplot(comparison_table, aes(x = baseline_tau, y = pandemic_tau)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
  geom_point(size = 3, alpha = 0.7, color = "steelblue") +
  geom_text(aes(label = pair_label), hjust = -0.1, vjust = -0.5, size = 3) +
  labs(
    title = "Kendall's τ: Pandemic vs. Baseline",
    subtitle = "Points below diagonal indicate weakened dependence during pandemic",
    x = "Baseline τ (2017-2019)",
    y = "Pandemic τ (2019-2021)"
  ) +
  coord_fixed() +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(output_dir, "pandemic_tau_scatter.pdf"), p3, width = 8, height = 8)
cat("✓ Saved:", file.path(output_dir, "pandemic_tau_scatter.pdf"), "\n")

################################################################################
### SAVE RESULTS
################################################################################

# Save comparison table
comparison_file <- file.path(output_dir, "pandemic_parameter_comparison.csv")
fwrite(comparison_table, comparison_file)
cat("✓ Saved comparison table:", comparison_file, "\n")

# Save summary report
report_file <- file.path(output_dir, "pandemic_summary_report.txt")
sink(report_file)

cat("====================================================================\n")
cat("PANDEMIC COPULA ANALYSIS: Dataset 4 (Hawaii)\n")
cat("====================================================================\n")
cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("====================================================================\n\n")

cat("RESEARCH QUESTION:\n")
cat("Did the COVID-19 pandemic (2020 school closures) disrupt the copula\n")
cat("dependency structure in longitudinal educational assessments?\n\n")

cat("METHODOLOGY:\n")
cat("- Pandemic pairs: 2019 prior → 2021 current (spans 2020 gap)\n")
cat("- Baseline pairs: 2017 prior → 2019 current (pre-pandemic)\n")
cat("- Copula family: t-copula (selected in STEP 1)\n")
cat("- Matched pairs: Same grade spans, same time duration, same content areas\n\n")

cat("MATCHED PAIRS:\n")
cat("- G3→G5 (MATH, READ): 2-year span\n")
cat("- G4→G6 (MATH, READ): 2-year span\n")
cat("- G5→G7 (MATH, READ): 2-year span\n")
cat("- G6→G8 (MATH, READ): 2-year span\n")
cat("- G8→G11 (MATH, READ): 3-year span\n\n")

cat("====================================================================\n")
cat("KEY FINDINGS\n")
cat("====================================================================\n\n")

cat("1. KENDALL'S TAU (Overall Dependence)\n")
cat("   Mean change:", sprintf("%.4f", mean(comparison_table$delta_tau)), "\n")
cat("   Range:", sprintf("[%.4f, %.4f]", min(comparison_table$delta_tau), 
                         max(comparison_table$delta_tau)), "\n")
if (mean(comparison_table$delta_tau) < -0.01) {
  cat("   → WEAKENED dependence during pandemic\n")
} else if (mean(comparison_table$delta_tau) > 0.01) {
  cat("   → STRENGTHENED dependence during pandemic\n")
} else {
  cat("   → NO SUBSTANTIAL CHANGE\n")
}
cat("\n")

cat("2. DEGREES OF FREEDOM (Tail Behavior)\n")
cat("   Mean change:", sprintf("%.2f", mean(comparison_table$delta_df)), "\n")
cat("   Range:", sprintf("[%.2f, %.2f]", min(comparison_table$delta_df), 
                         max(comparison_table$delta_df)), "\n")
if (mean(comparison_table$delta_df) < -1) {
  cat("   → HEAVIER tails during pandemic (more extreme joint outcomes)\n")
} else if (mean(comparison_table$delta_df) > 1) {
  cat("   → LIGHTER tails during pandemic (less extreme joint outcomes)\n")
} else {
  cat("   → NO SUBSTANTIAL CHANGE in tail behavior\n")
}
cat("\n")

cat("3. TAIL DEPENDENCE (Extreme Co-movement)\n")
cat("   Mean change:", sprintf("%.4f", mean(comparison_table$delta_tail_dep)), "\n")
cat("   Range:", sprintf("[%.4f, %.4f]", min(comparison_table$delta_tail_dep), 
                         max(comparison_table$delta_tail_dep)), "\n")
cat("\n")

cat("====================================================================\n")
cat("DETAILED COMPARISON TABLE\n")
cat("====================================================================\n\n")
print(comparison_table)
cat("\n")

cat("====================================================================\n")
cat("INTERPRETATION\n")
cat("====================================================================\n\n")

cat("The pandemic period (2019-2021, spanning the 2020 school closure) showed:\n\n")

if (abs(mean(comparison_table$delta_tau)) > 0.02) {
  cat("SUBSTANTIAL changes in dependency structure compared to pre-pandemic baseline.\n")
  cat("This suggests COVID-19 disruption affected the longitudinal relationship\n")
  cat("between prior and current achievement.\n\n")
} else {
  cat("MINIMAL changes in dependency structure compared to pre-pandemic baseline.\n")
  cat("This suggests the copula model is ROBUST to pandemic disruption, and\n")
  cat("the fundamental dependency structure remained intact despite school closures.\n\n")
}

cat("For detailed visualizations, see:\n")
cat("- pandemic_tau_change.pdf\n")
cat("- pandemic_df_change.pdf\n")
cat("- pandemic_tau_scatter.pdf\n\n")

cat("====================================================================\n")
cat("END OF REPORT\n")
cat("====================================================================\n")

sink()

cat("✓ Saved summary report:", report_file, "\n\n")

################################################################################
### COMPLETION MESSAGE
################################################################################

cat("====================================================================\n")
cat("PANDEMIC ANALYSIS COMPLETE\n")
cat("====================================================================\n")
cat("Output directory:", output_dir, "\n")
cat("Files generated:\n")
cat("  - pandemic_parameter_comparison.csv\n")
cat("  - pandemic_summary_report.txt\n")
cat("  - pandemic_tau_change.pdf\n")
cat("  - pandemic_df_change.pdf\n")
cat("  - pandemic_tau_scatter.pdf\n")
cat("====================================================================\n\n")
