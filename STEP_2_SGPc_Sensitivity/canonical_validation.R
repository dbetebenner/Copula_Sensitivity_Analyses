############################################################################
### STEP 2.2: Canonical Copula Validation
###
### Purpose: Empirically validate the canonical copula selection against 
###          STEP_2 SGPc results. The canonical copula is the copula that 
###          will be operationally deployed for datasets like TIMSS/NAEP
###          where no empirical copula is available. This script answers:
###          "Is the current canonical the best single-parametric copula 
###           we could offer for each year_span x content_area stratum?"
###
### Inputs:
###   - STEP_1: phase1_copula_family_comparison_all_datasets.csv
###   - STEP_1: canonical_copula_parameters.csv
###   - STEP_2: sgpc_all_variants_dataset_{1-4}.rds (from sgpc_compute_all_variants.R)
###
### Outputs:
###   - results/canonical_family_distribution_by_stratum.csv
###   - results/canonical_validation_by_stratum.csv
###   - results/canonical_validation_report.md
###
### Run after: sgpc_compute_all_variants.R (STEP 2.1)
### Author: dataimago
### Date: February 2026
############################################################################

require(data.table)

cat("====================================================================\n")
cat("STEP 2.2: CANONICAL COPULA VALIDATION\n")
cat("====================================================================\n\n")

############################################################################
### CONFIGURATION
############################################################################

STEP1_RESULTS_DIR <- "STEP_1_Family_Selection/results/dataset_all"
STEP2_RESULTS_DIR <- "STEP_2_SGPc_Sensitivity/results"

# Ensure output directory exists
if (!dir.exists(STEP2_RESULTS_DIR)) {
  dir.create(STEP2_RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
}

############################################################################
### PHASE 1: Per-Stratum Family Distribution Diagnostic
############################################################################

cat("PHASE 1: Per-Stratum Family Distribution\n")
cat("--------------------------------------------------------------------\n\n")

# Load the all-datasets family comparison CSV from STEP_1
comparison_file <- file.path(STEP1_RESULTS_DIR, "phase1_copula_family_comparison_all_datasets.csv")

if (!file.exists(comparison_file)) {
  stop("STEP_1 comparison file not found: ", comparison_file,
       "\nRun STEP_1 (phase1_family_selection_parallel.R) first.")
}

comparison_dt <- fread(comparison_file)
cat(sprintf("Loaded STEP_1 comparison data: %s rows, %d conditions\n",
            format(nrow(comparison_dt), big.mark = ","),
            length(unique(comparison_dt$condition_id))))

# Identify the best-fit family per condition (delta_aic_vs_best == 0)
# Handle NA delta_aic_vs_best (some families like comonotonic may have NA AIC)
best_fits <- comparison_dt[!is.na(delta_aic_vs_best) & delta_aic_vs_best == 0]

# De-duplicate: some conditions may have ties in AIC (multiple families with delta==0)
# Take the first family alphabetically for consistency
best_fits <- best_fits[order(condition_id, family)]
best_fits <- best_fits[, .SD[1], by = condition_id]

cat(sprintf("Best-fit families identified for %d conditions\n", nrow(best_fits)))

# Compute per-stratum family distributions
stratum_family_dist <- best_fits[, .(
  n_conditions = .N,
  n_t = sum(family == "t"),
  n_frank = sum(family == "frank"),
  n_gaussian = sum(family == "gaussian"),
  n_gumbel = sum(family == "gumbel"),
  n_clayton = sum(family == "clayton"),
  pct_t = round(100 * mean(family == "t"), 1),
  pct_frank = round(100 * mean(family == "frank"), 1),
  pct_gaussian = round(100 * mean(family == "gaussian"), 1),
  pct_gumbel = round(100 * mean(family == "gumbel"), 1),
  pct_clayton = round(100 * mean(family == "clayton"), 1)
), by = .(year_span, content_area)]

setorder(stratum_family_dist, year_span, content_area)

# Add stratum_id for downstream matching
stratum_family_dist[, stratum_id := paste0("year_", year_span, "_", tolower(content_area))]

# Flag strata where t-copula wins less than 50%
stratum_family_dist[, t_majority := pct_t >= 50]

# Report
cat("\nPer-stratum family distributions:\n")
cat(sprintf("  Total strata: %d\n", nrow(stratum_family_dist)))
cat(sprintf("  Strata where t-copula is majority (>=50%%): %d\n", 
            sum(stratum_family_dist$t_majority)))
cat(sprintf("  Strata where t-copula is NOT majority: %d\n", 
            sum(!stratum_family_dist$t_majority)))

# Print detailed breakdown
cat("\n  %-25s  n   %%t    %%frank  %%gauss  %%gumbel  majority?\n")
for (i in seq_len(nrow(stratum_family_dist))) {
  row <- stratum_family_dist[i]
  cat(sprintf("  %-25s %3d  %5.1f  %5.1f   %5.1f   %5.1f    %s\n",
              row$stratum_id, row$n_conditions,
              row$pct_t, row$pct_frank, row$pct_gaussian, row$pct_gumbel,
              ifelse(row$t_majority, "YES", "*** NO ***")))
}

# Save Phase 1 output
phase1_output <- file.path(STEP2_RESULTS_DIR, "canonical_family_distribution_by_stratum.csv")
fwrite(stratum_family_dist, phase1_output)
cat(sprintf("\nPhase 1 output saved: %s\n\n", phase1_output))

############################################################################
### PHASE 2: Empirical Validation of Canonical SGPc Accuracy
############################################################################

cat("PHASE 2: Empirical Validation of Canonical SGPc Accuracy\n")
cat("--------------------------------------------------------------------\n\n")

# Load STEP_2 results
dataset_ids <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")
all_variants <- list()

for (ds_id in dataset_ids) {
  rds_file <- file.path(STEP2_RESULTS_DIR, paste0("sgpc_all_variants_", ds_id, ".rds"))
  if (file.exists(rds_file)) {
    dt <- readRDS(rds_file)
    dt[, dataset_id := ds_id]
    all_variants[[ds_id]] <- dt
    cat(sprintf("  Loaded %s: %s observations, %d conditions\n",
                ds_id, format(nrow(dt), big.mark = ","),
                length(unique(dt$condition_id))))
  } else {
    cat(sprintf("  WARNING: %s not found - skipping\n", rds_file))
  }
}

if (length(all_variants) == 0) {
  cat("\nERROR: No STEP_2 results found. Run sgpc_compute_all_variants.R first.\n")
  cat("Phase 2 will be skipped. Phase 1 results are still available.\n")
  
  # Write a partial report
  report_path <- file.path(STEP2_RESULTS_DIR, "canonical_validation_report.md")
  report_lines <- c(
    "# Canonical Copula Validation Report",
    "",
    paste("**Generated:**", Sys.time()),
    "",
    "## Status: PARTIAL (STEP_2 results not yet available)",
    "",
    "Phase 1 (per-stratum family distribution) completed successfully.",
    "Phase 2 (empirical SGPc validation) requires STEP_2 results.",
    "",
    "Run sgpc_compute_all_variants.R first, then re-run this script.",
    ""
  )
  writeLines(report_lines, report_path)
  cat(sprintf("\nPartial report saved: %s\n", report_path))
  
  cat("\n====================================================================\n")
  cat("CANONICAL VALIDATION: PHASE 1 COMPLETE (Phase 2 pending STEP_2 results)\n")
  cat("====================================================================\n")
  
  # Still quit gracefully
  if (!interactive()) q(status = 0)
  stop("STEP_2 results not yet available. Re-run after sgpc_compute_all_variants.R completes.")
}

variants_dt <- rbindlist(all_variants, fill = TRUE)
cat(sprintf("\nCombined STEP_2 data: %s observations across %d conditions\n",
            format(nrow(variants_dt), big.mark = ","),
            length(unique(variants_dt$condition_id))))

# Merge best-fit family information from STEP_1 into STEP_2 results
# (at the condition level, so we know each condition's true best family)
#
# CRITICAL: STEP_1 uses numeric condition_ids (12, 19, 20, ...),
# while STEP_2 uses descriptive string IDs ("2024_G5_G6_MATHEMATICS", ...).
# These will never match directly. Instead, construct the descriptive ID
# from STEP_1 metadata columns (year_current, grade_prior, grade_current,
# content_area) -- the same formula used by get_phase1_conditions() in
# phase1_data_loader.R (lines 162-167).
condition_best_family <- best_fits[, .(
  descriptive_id = paste0(year_current, "_G", grade_prior, "_G", grade_current, "_", content_area),
  best_family_aic = family
)]

# De-duplicate: a single descriptive_id could appear in multiple datasets
# (same year/grade/content across dataset_1..4). Take majority family.
condition_best_family <- condition_best_family[, .(
  best_family_aic = names(sort(table(best_family_aic), decreasing = TRUE))[1]
), by = descriptive_id]

cat(sprintf("  STEP_1 best-family lookup: %d unique conditions\n", nrow(condition_best_family)))
cat(sprintf("  Sample IDs: %s\n", paste(head(condition_best_family$descriptive_id, 3), collapse = ", ")))
cat(sprintf("  STEP_2 sample IDs: %s\n", paste(head(unique(variants_dt$condition_id), 3), collapse = ", ")))

# Merge on the descriptive condition_id that both sides now share
variants_dt <- merge(
  variants_dt, condition_best_family,
  by.x = "condition_id", by.y = "descriptive_id",
  all.x = TRUE
)

n_matched <- sum(!is.na(variants_dt$best_family_aic))
cat(sprintf("Family info merged: %d/%d observations matched (%.1f%%)\n",
            n_matched, nrow(variants_dt), 100 * n_matched / nrow(variants_dt)))

if (n_matched == 0) {
  cat("\nWARNING: No condition_id matches between STEP_1 and STEP_2.\n")
  cat("STEP_1 descriptive IDs: ", paste(head(condition_best_family$descriptive_id, 3), collapse=", "), "\n")
  cat("STEP_2 condition IDs:   ", paste(head(unique(variants_dt$condition_id), 3), collapse=", "), "\n")
}

# Compute per-observation absolute differences from empirical
# Only for observations where sgpc_emp is not NA
valid_obs <- variants_dt[!is.na(sgpc_emp)]
cat(sprintf("Valid observations (with empirical SGPc): %s\n",
            format(nrow(valid_obs), big.mark = ",")))

valid_obs[, `:=`(
  ad_canonical = abs(sgpc_avg - sgpc_emp),
  ad_best      = abs(sgpc_best - sgpc_emp),
  ad_frank     = abs(sgpc_frank - sgpc_emp),
  ad_gaussian  = abs(sgpc_gaussian - sgpc_emp),
  ad_t4        = abs(sgpc_t - sgpc_emp),
  ad_gumbel    = abs(sgpc_gumbel - sgpc_emp),
  ad_clayton   = abs(sgpc_clayton - sgpc_emp)
)]

# --- Per-condition summary ---
condition_summary <- valid_obs[, .(
  n_obs = .N,
  year_span = year_span[1],
  content_area = content_area[1],
  best_family_aic = best_family_aic[1],
  
  # Mean Absolute Difference (MAD) from empirical
  mad_canonical = round(mean(ad_canonical, na.rm = TRUE), 2),
  mad_best      = round(mean(ad_best, na.rm = TRUE), 2),
  mad_frank     = round(mean(ad_frank, na.rm = TRUE), 2),
  mad_gaussian  = round(mean(ad_gaussian, na.rm = TRUE), 2),
  mad_t4        = round(mean(ad_t4, na.rm = TRUE), 2),
  mad_gumbel    = round(mean(ad_gumbel, na.rm = TRUE), 2),
  mad_clayton   = round(mean(ad_clayton, na.rm = TRUE), 2),
  
  # Correlation with empirical
  cor_canonical = round(cor(sgpc_avg, sgpc_emp, use = "complete.obs"), 4),
  cor_best      = round(cor(sgpc_best, sgpc_emp, use = "complete.obs"), 4),
  cor_frank     = round(cor(sgpc_frank, sgpc_emp, use = "complete.obs"), 4),
  cor_gaussian  = round(cor(sgpc_gaussian, sgpc_emp, use = "complete.obs"), 4)
), by = condition_id]

# Add stratum_id
condition_summary[, stratum_id := paste0("year_", year_span, "_", tolower(content_area))]

# --- Per-stratum aggregation ---
stratum_validation <- condition_summary[, .(
  n_conditions = .N,
  n_obs_total = sum(n_obs),
  
  # Overall canonical accuracy
  mad_canonical_mean = round(mean(mad_canonical, na.rm = TRUE), 2),
  mad_canonical_median = round(median(mad_canonical, na.rm = TRUE), 2),
  mad_canonical_sd = round(sd(mad_canonical, na.rm = TRUE), 2),
  
  # Best-fit accuracy (upper bound on parametric performance)
  mad_best_mean = round(mean(mad_best, na.rm = TRUE), 2),
  mad_best_median = round(median(mad_best, na.rm = TRUE), 2),
  
  # Frank accuracy (runner-up family)
  mad_frank_mean = round(mean(mad_frank, na.rm = TRUE), 2),
  mad_frank_median = round(median(mad_frank, na.rm = TRUE), 2),
  
  # Gaussian accuracy
  mad_gaussian_mean = round(mean(mad_gaussian, na.rm = TRUE), 2),
  
  # t with df=4 accuracy (stress test)
  mad_t4_mean = round(mean(mad_t4, na.rm = TRUE), 2),
  
  # Canonical accuracy for t-best vs Frank-best conditions
  mad_canonical_t_best = round(mean(mad_canonical[best_family_aic == "t"], na.rm = TRUE), 2),
  mad_canonical_frank_best = round(mean(mad_canonical[best_family_aic == "frank"], na.rm = TRUE), 2),
  
  # Frank accuracy for Frank-best conditions (does Frank actually beat canonical there?)
  mad_frank_frank_best = round(mean(mad_frank[best_family_aic == "frank"], na.rm = TRUE), 2),
  
  # Number of conditions by best family
  n_t_best = sum(best_family_aic == "t", na.rm = TRUE),
  n_frank_best = sum(best_family_aic == "frank", na.rm = TRUE),
  n_other_best = sum(!best_family_aic %in% c("t", "frank"), na.rm = TRUE),
  
  # Correlation with empirical (mean across conditions)
  cor_canonical_mean = round(mean(cor_canonical, na.rm = TRUE), 4),
  cor_best_mean = round(mean(cor_best, na.rm = TRUE), 4),
  cor_frank_mean = round(mean(cor_frank, na.rm = TRUE), 4)
), by = .(year_span, content_area)]

setorder(stratum_validation, year_span, content_area)
stratum_validation[, stratum_id := paste0("year_", year_span, "_", tolower(content_area))]

# Compute "canonical gap" -- how much worse is canonical than best-fit?
stratum_validation[, canonical_gap := round(mad_canonical_mean - mad_best_mean, 2)]

# Does Frank beat canonical for Frank-best conditions?
stratum_validation[, frank_beats_canonical_for_frank_conds := mad_frank_frank_best < mad_canonical_frank_best]

# Report
cat("\nPer-stratum validation results:\n\n")
cat(sprintf("  %-25s  n_cond  MAD_canon  MAD_best  MAD_frank  gap   canon_frank_best  frank_frank_best  frank_wins?\n",
            "stratum"))
for (i in seq_len(nrow(stratum_validation))) {
  row <- stratum_validation[i]
  cat(sprintf("  %-25s  %3d     %5.2f      %5.2f     %5.2f    %5.2f     %5.2f             %5.2f             %s\n",
              row$stratum_id, row$n_conditions,
              row$mad_canonical_mean, row$mad_best_mean, row$mad_frank_mean,
              row$canonical_gap,
              row$mad_canonical_frank_best, row$mad_frank_frank_best,
              ifelse(is.na(row$frank_beats_canonical_for_frank_conds), "N/A",
                     ifelse(row$frank_beats_canonical_for_frank_conds, "YES", "no"))))
}

# Save Phase 2 outputs
phase2_output <- file.path(STEP2_RESULTS_DIR, "canonical_validation_by_stratum.csv")
fwrite(stratum_validation, phase2_output)
cat(sprintf("\nPhase 2 stratum output saved: %s\n", phase2_output))

condition_output <- file.path(STEP2_RESULTS_DIR, "canonical_validation_by_condition.csv")
fwrite(condition_summary, condition_output)
cat(sprintf("Phase 2 condition output saved: %s\n", condition_output))

############################################################################
### PHASE 3: Decision and Report
############################################################################

cat("\nPHASE 3: Decision and Report\n")
cat("--------------------------------------------------------------------\n\n")

# Load canonical copula parameters for context
canonical_csv_file <- file.path(STEP1_RESULTS_DIR, "canonical_copula_parameters.csv")
canonical_params_dt <- if (file.exists(canonical_csv_file)) {
  fread(canonical_csv_file)
} else {
  data.table()
}

# Global summary statistics
global_mad_canonical <- round(mean(condition_summary$mad_canonical, na.rm = TRUE), 2)
global_mad_best <- round(mean(condition_summary$mad_best, na.rm = TRUE), 2)
global_mad_frank <- round(mean(condition_summary$mad_frank, na.rm = TRUE), 2)
global_cor_canonical <- round(mean(condition_summary$cor_canonical, na.rm = TRUE), 4)
global_cor_best <- round(mean(condition_summary$cor_best, na.rm = TRUE), 4)
global_gap <- round(global_mad_canonical - global_mad_best, 2)

# For Frank-best conditions only
frank_best_conds <- condition_summary[best_family_aic == "frank"]
t_best_conds <- condition_summary[best_family_aic == "t"]

if (nrow(frank_best_conds) > 0) {
  mad_canonical_on_frank <- round(mean(frank_best_conds$mad_canonical, na.rm = TRUE), 2)
  mad_frank_on_frank <- round(mean(frank_best_conds$mad_frank, na.rm = TRUE), 2)
  cor_canonical_on_frank <- round(mean(frank_best_conds$cor_canonical, na.rm = TRUE), 4)
} else {
  mad_canonical_on_frank <- NA
  mad_frank_on_frank <- NA
  cor_canonical_on_frank <- NA
}

if (nrow(t_best_conds) > 0) {
  mad_canonical_on_t <- round(mean(t_best_conds$mad_canonical, na.rm = TRUE), 2)
} else {
  mad_canonical_on_t <- NA
}

# Determine verdict
# Criterion: if canonical MAD is within 1.5x of best-fit MAD, and correlation > 0.99,
# the canonical is considered validated.
canonical_ratio <- global_mad_canonical / global_mad_best
is_validated <- canonical_ratio < 1.5 && global_cor_canonical > 0.99

# Frank-specific: does the Frank copula meaningfully outperform canonical for Frank-best conditions?
frank_improvement <- if (!is.na(mad_canonical_on_frank) && !is.na(mad_frank_on_frank)) {
  mad_canonical_on_frank - mad_frank_on_frank
} else {
  NA
}

cat(sprintf("Global Summary:\n"))
cat(sprintf("  MAD (canonical vs empirical): %.2f\n", global_mad_canonical))
cat(sprintf("  MAD (best-fit vs empirical):  %.2f\n", global_mad_best))
cat(sprintf("  MAD (Frank vs empirical):     %.2f\n", global_mad_frank))
cat(sprintf("  Canonical/Best-fit ratio:     %.3f\n", canonical_ratio))
cat(sprintf("  Correlation (canonical):      %.4f\n", global_cor_canonical))
cat(sprintf("  Correlation (best-fit):       %.4f\n", global_cor_best))
cat(sprintf("\n  Canonical gap (MAD excess):   %.2f SGPc points\n", global_gap))

if (!is.na(frank_improvement)) {
  cat(sprintf("  Frank improvement on Frank-best conditions: %.2f SGPc points\n", frank_improvement))
}

cat(sprintf("\n  VERDICT: %s\n", 
            ifelse(is_validated, 
                   "VALIDATED -- t-canonical is a defensible choice for TIMSS deployment",
                   "REVIEW NEEDED -- canonical MAD ratio or correlation outside acceptable range")))

############################################################################
### GENERATE REPORT
############################################################################

report_lines <- c(
  "# Canonical Copula Validation Report",
  "",
  paste("**Generated:**", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  paste("**STEP_1 conditions:**", nrow(best_fits)),
  paste("**STEP_2 observations:**", format(nrow(variants_dt), big.mark = ",")),
  "",
  "---",
  "",
  "## Executive Summary",
  "",
  paste0("The canonical copula (t-copula with stratum-specific median parameters from STEP_1) ",
         "was validated against empirical SGPc values across all STEP_2 conditions."),
  "",
  sprintf("- **Overall MAD (canonical vs empirical):** %.2f SGPc percentile points", global_mad_canonical),
  sprintf("- **Overall MAD (best-fit vs empirical):** %.2f SGPc percentile points", global_mad_best),
  sprintf("- **Canonical gap (excess MAD over best-fit):** %.2f points", global_gap),
  sprintf("- **Canonical/Best-fit MAD ratio:** %.3f", canonical_ratio),
  sprintf("- **Mean correlation (canonical vs empirical):** %.4f", global_cor_canonical),
  "",
  sprintf("**Verdict:** %s",
          ifelse(is_validated,
                 "VALIDATED. The t-canonical is a defensible choice for operational deployment (e.g., TIMSS).",
                 "REVIEW NEEDED. The canonical copula shows meaningful degradation relative to best-fit.")),
  "",
  "---",
  "",
  "## Phase 1: Per-Stratum Family Distribution",
  "",
  "The table below shows the AIC-best family distribution within each year_span x content_area stratum.",
  "The canonical is t-copula for all strata; this phase checks whether t is actually the majority winner.",
  "",
  "| Stratum | n | %t | %frank | %gaussian | %gumbel | t majority? |",
  "|---------|---|----|--------|-----------|---------|-------------|"
)

for (i in seq_len(nrow(stratum_family_dist))) {
  row <- stratum_family_dist[i]
  report_lines <- c(report_lines,
    sprintf("| %s | %d | %.1f | %.1f | %.1f | %.1f | %s |",
            row$stratum_id, row$n_conditions,
            row$pct_t, row$pct_frank, row$pct_gaussian, row$pct_gumbel,
            ifelse(row$t_majority, "Yes", "**NO**")))
}

report_lines <- c(report_lines,
  "",
  "---",
  "",
  "## Phase 2: Empirical SGPc Validation",
  "",
  "For each stratum, mean absolute difference (MAD) between parametric SGPc variants and empirical SGPc.",
  "Lower MAD = closer to empirical truth.",
  "",
  "| Stratum | n_cond | MAD canonical | MAD best-fit | MAD Frank | Gap | cor(canonical) |",
  "|---------|--------|---------------|--------------|-----------|-----|----------------|"
)

for (i in seq_len(nrow(stratum_validation))) {
  row <- stratum_validation[i]
  report_lines <- c(report_lines,
    sprintf("| %s | %d | %.2f | %.2f | %.2f | %.2f | %.4f |",
            row$stratum_id, row$n_conditions,
            row$mad_canonical_mean, row$mad_best_mean, row$mad_frank_mean,
            row$canonical_gap, row$cor_canonical_mean))
}

report_lines <- c(report_lines,
  "",
  "### Canonical Performance by Condition's True Best Family",
  "",
  "This table shows whether the t-canonical degrades specifically for conditions where Frank was the true best fit.",
  ""
)

if (!is.na(mad_canonical_on_frank)) {
  report_lines <- c(report_lines,
    sprintf("| Metric | t-best conditions (n=%d) | Frank-best conditions (n=%d) |",
            nrow(t_best_conds), nrow(frank_best_conds)),
    "|--------|-------------------------|------------------------------|",
    sprintf("| MAD (canonical vs emp) | %.2f | %.2f |", mad_canonical_on_t, mad_canonical_on_frank),
    sprintf("| MAD (Frank vs emp) | %.2f | %.2f |", 
            round(mean(t_best_conds$mad_frank, na.rm = TRUE), 2), mad_frank_on_frank),
    sprintf("| Frank improvement | -- | %.2f points |", frank_improvement),
    ""
  )
  
  if (frank_improvement > 0.5) {
    report_lines <- c(report_lines,
      sprintf("**Note:** Frank copula outperforms canonical by %.2f MAD points on Frank-best conditions.", frank_improvement),
      "Consider whether this magnitude warrants adjustment to the canonical selection for affected strata.",
      ""
    )
  } else {
    report_lines <- c(report_lines,
      sprintf("**Note:** Frank improvement (%.2f points) is modest. The t-canonical is robust even for Frank-best conditions.", frank_improvement),
      ""
    )
  }
} else {
  report_lines <- c(report_lines,
    "No Frank-best conditions found (or family matching failed).",
    ""
  )
}

report_lines <- c(report_lines,
  "---",
  "",
  "## Phase 3: Decision for TIMSS Deployment",
  "",
  sprintf("### Recommendation: %s",
          ifelse(is_validated, "Use Current t-Canonical", "Review and Potentially Revise")),
  ""
)

if (is_validated) {
  report_lines <- c(report_lines,
    "The current canonical copula selection (t-copula with stratum-specific median rho and df)",
    "is empirically validated as a defensible choice for operational use.",
    "",
    "**Evidence:**",
    "",
    sprintf("1. The canonical-to-empirical MAD (%.2f) is close to the best-fit-to-empirical MAD (%.2f), ratio = %.3f",
            global_mad_canonical, global_mad_best, canonical_ratio),
    sprintf("2. The canonical-empirical correlation (%.4f) indicates near-perfect rank agreement", global_cor_canonical),
    sprintf("3. The canonical gap (%.2f SGPc points) represents minimal practical impact on student percentile classifications",
            global_gap),
    ""
  )
  
  if (!is.na(frank_improvement) && frank_improvement > 0) {
    report_lines <- c(report_lines,
      "**For Frank-best conditions:**",
      "",
      sprintf("- The canonical MAD increases modestly (%.2f vs %.2f for t-best conditions)",
              mad_canonical_on_frank, mad_canonical_on_t),
      sprintf("- Frank copula would improve MAD by %.2f points for these conditions", frank_improvement),
      "- However, this does not justify a mixed-family canonical because:",
      "  - The improvement is within noise for individual student classifications",
      "  - A single-family canonical is simpler to communicate and implement",
      "  - The t-copula subsumes Gaussian as df -> infinity, offering more flexibility",
      ""
    )
  }
  
  report_lines <- c(report_lines,
    "### TIMSS Application (4-year Mathematics)",
    "",
    "For TIMSS (year_span=4, content_area=MATHEMATICS), use the canonical parameters from:",
    "`STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv`",
    "",
    "```r",
    "# Load canonical and create copula for TIMSS",
    "source('STEP_1_Family_Selection/results/dataset_all/lookup_canonical_copula.R')",
    "timss_cop <- create_canonical_copula(year_span = 4, content_area = 'MATHEMATICS')",
    "```",
    ""
  )
} else {
  report_lines <- c(report_lines,
    "The canonical copula shows meaningful degradation relative to best-fit.",
    "Consider the following improvements:",
    "",
    "**Option A (minimal):** Restrict canonical median computation to only conditions",
    "where t-copula was actually the AIC-best fit. This removes parameter estimates from",
    "suboptimal t-copula fits (where Frank or other families were better).",
    "",
    "**Option B (structural):** Compute a separate canonical for strata where Frank",
    "dominates. Use frankCopula with stratum-specific median theta for those strata.",
    "",
    "Implementation would modify `copula_contour_plots.R` lines 5108-5148.",
    ""
  )
}

report_lines <- c(report_lines,
  "---",
  "",
  "## Methodology",
  "",
  "### Metrics",
  "",
  "- **MAD (Mean Absolute Difference):** Average |SGPc_variant - SGPc_empirical| across all observations in a condition, then averaged across conditions in a stratum. Units: SGPc percentile points (0-99 scale).",
  "- **Correlation:** Pearson correlation between SGPc_variant and SGPc_empirical per condition.",
  "- **Canonical Gap:** MAD_canonical - MAD_best_fit. How much accuracy is lost by using the canonical vs. the condition-specific best-fit copula.",
  "",
  "### Validation Criteria",
  "",
  "- Canonical/Best-fit MAD ratio < 1.5 (canonical is no more than 50% worse than best-fit)",
  "- Mean correlation > 0.99 (near-perfect rank agreement)",
  "",
  "### Files Produced",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `canonical_family_distribution_by_stratum.csv` | Per-stratum AIC-best family distribution |",
  "| `canonical_validation_by_stratum.csv` | Per-stratum MAD/correlation comparison |",
  "| `canonical_validation_by_condition.csv` | Per-condition MAD/correlation detail |",
  "| `canonical_validation_report.md` | This report |",
  ""
)

# Write report
report_path <- file.path(STEP2_RESULTS_DIR, "canonical_validation_report.md")
writeLines(report_lines, report_path)
cat(sprintf("\nValidation report saved: %s\n", report_path))

cat("\n====================================================================\n")
cat("CANONICAL COPULA VALIDATION COMPLETE\n")
cat(sprintf("  Phase 1: %d strata characterized\n", nrow(stratum_family_dist)))
cat(sprintf("  Phase 2: %d conditions validated\n", nrow(condition_summary)))
cat(sprintf("  Phase 3: Verdict = %s\n",
            ifelse(is_validated, "VALIDATED", "REVIEW NEEDED")))
cat("====================================================================\n")
