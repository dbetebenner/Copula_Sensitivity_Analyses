############################################################################
### STEP 2: SGPc Sensitivity Analysis - Aggregate Statistics
###
### Purpose: Compute aggregate statistics comparing all SGPc variants
###
### Key Comparisons:
###   - Correlations between variants
###   - Mean absolute differences (MAD)
###   - Root mean square differences (RMSD)
###   - Stratified analyses (by year_span, content_area, prior quartile)
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)
require(jsonlite)

cat("====================================================================\n")
cat("STEP 2: AGGREGATE ANALYSIS OF SGPc VARIANTS\n")
cat("====================================================================\n\n")

############################################################################
### CONFIGURATION
############################################################################

RESULTS_DIR <- "STEP_2_SGPc_Sensitivity/results"
OUTPUT_DIR <- RESULTS_DIR

# Load all dataset results
dataset_files <- list.files(
  RESULTS_DIR,
  pattern = "^sgpc_all_variants_dataset_.*\\.rds$",
  full.names = TRUE
)

if (length(dataset_files) == 0) {
  stop("No variant results found. Run sgpc_compute_all_variants.R first.")
}

cat("Loading results from:\n")
for (f in dataset_files) {
  cat(" ", f, "\n")
}
cat("\n")

# Load and combine all datasets
# Each RDS should contain a dataset_id column; infer from filename for backward compat
all_data_list <- mapply(
  function(dt, f) {
    if (!"dataset_id" %in% names(dt)) {
      ds_id <- sub(
        ".*sgpc_all_variants_(dataset_\\d+)\\.rds$",
        "\\1",
        basename(f)
      )
      dt[, dataset_id := ds_id]
    }
    dt
  },
  lapply(dataset_files, readRDS),
  dataset_files,
  SIMPLIFY = FALSE
)
all_data <- rbindlist(all_data_list, fill = TRUE)

n_conditions <- uniqueN(all_data[, paste(dataset_id, condition_id, sep = "__")])
cat("Combined dataset:\n")
cat("  Total observations:", nrow(all_data), "\n")
cat("  Datasets:", uniqueN(all_data$dataset_id), "\n")
cat("  Conditions:", n_conditions, "\n")
cat(
  "  Year spans:",
  paste(sort(unique(all_data$year_span)), collapse = ", "),
  "\n"
)
cat(
  "  Content areas:",
  paste(unique(all_data$content_area), collapse = ", "),
  "\n\n"
)

############################################################################
### HELPER FUNCTIONS
############################################################################

#' Compute correlation matrix for SGPc variants
compute_correlations <- function(dt) {
  sgpc_cols <- grep("^sgpc_|^sgp_", names(dt), value = TRUE)

  # Filter out columns that are entirely NA
  valid_cols <- character(0)
  for (col in sgpc_cols) {
    if (sum(!is.na(dt[[col]])) > 0) {
      valid_cols <- c(valid_cols, col)
    }
  }

  if (length(valid_cols) == 0) {
    stop("No valid SGPc columns with non-NA values")
  }

  cor_matrix <- matrix(NA, nrow = length(valid_cols), ncol = length(valid_cols))
  rownames(cor_matrix) <- colnames(cor_matrix) <- valid_cols

  for (i in seq_along(valid_cols)) {
    for (j in seq_along(valid_cols)) {
      if (i <= j) {
        cor_val <- cor(
          dt[[valid_cols[i]]],
          dt[[valid_cols[j]]],
          use = "complete.obs"
        )
        cor_matrix[i, j] <- cor_matrix[j, i] <- cor_val
      }
    }
  }

  return(as.data.table(cor_matrix, keep.rownames = "variant"))
}

#' Compute mean absolute difference
mad <- function(x, y) {
  mean(abs(x - y), na.rm = TRUE)
}

#' Compute root mean square difference
rmsd <- function(x, y) {
  sqrt(mean((x - y)^2, na.rm = TRUE))
}

#' Compute pairwise differences for all variants
compute_differences <- function(dt) {
  sgpc_cols <- grep("^sgpc_|^sgp_", names(dt), value = TRUE)

  # Filter out columns that are entirely NA
  valid_cols <- character(0)
  for (col in sgpc_cols) {
    if (sum(!is.na(dt[[col]])) > 0) {
      valid_cols <- c(valid_cols, col)
    }
  }

  diff_stats <- data.table()

  for (i in 1:(length(valid_cols) - 1)) {
    for (j in (i + 1):length(valid_cols)) {
      var1 <- valid_cols[i]
      var2 <- valid_cols[j]

      n_complete <- sum(!is.na(dt[[var1]]) & !is.na(dt[[var2]]))

      # Only compute if there are complete pairs
      if (n_complete > 0) {
        diff_stats <- rbind(
          diff_stats,
          data.table(
            variant1 = var1,
            variant2 = var2,
            correlation = cor(dt[[var1]], dt[[var2]], use = "complete.obs"),
            mad = mad(dt[[var1]], dt[[var2]]),
            rmsd = rmsd(dt[[var1]], dt[[var2]]),
            n_obs = n_complete
          )
        )
      }
    }
  }

  return(diff_stats)
}

############################################################################
### OVERALL STATISTICS
############################################################################

cat("Computing overall statistics...\n")

# Summary statistics for each variant
summary_stats <- all_data[, .(
  mean_sgpc_emp = mean(sgpc_emp, na.rm = TRUE),
  sd_sgpc_emp = sd(sgpc_emp, na.rm = TRUE),
  mean_sgpc_best = mean(sgpc_best, na.rm = TRUE),
  sd_sgpc_best = sd(sgpc_best, na.rm = TRUE),
  mean_sgpc_avg = mean(sgpc_avg, na.rm = TRUE),
  sd_sgpc_avg = sd(sgpc_avg, na.rm = TRUE),
  mean_sgpc_gaussian = mean(sgpc_gaussian, na.rm = TRUE),
  sd_sgpc_gaussian = sd(sgpc_gaussian, na.rm = TRUE),
  mean_sgpc_gumbel = mean(sgpc_gumbel, na.rm = TRUE),
  sd_sgpc_gumbel = sd(sgpc_gumbel, na.rm = TRUE),
  mean_sgpc_frank = mean(sgpc_frank, na.rm = TRUE),
  sd_sgpc_frank = sd(sgpc_frank, na.rm = TRUE),
  mean_sgpc_comonotonic = mean(sgpc_comonotonic, na.rm = TRUE),
  sd_sgpc_comonotonic = sd(sgpc_comonotonic, na.rm = TRUE),
  n_obs = .N
)]

# Correlation matrix
cat("Computing correlation matrix...\n")
cor_matrix <- compute_correlations(all_data)

# Pairwise differences
cat("Computing pairwise differences...\n")
diff_stats <- compute_differences(all_data)

# Key comparisons of interest
key_comparisons <- data.table(
  comparison = c(
    "Empirical vs Best-fit",
    "Empirical vs Canonical",
    "Best-fit vs Canonical",
    "Empirical vs Gaussian",
    "Empirical vs Comonotonic",
    "Traditional vs Empirical"
  ),
  variant1 = c(
    "sgpc_emp",
    "sgpc_emp",
    "sgpc_best",
    "sgpc_emp",
    "sgpc_emp",
    "sgp_traditional"
  ),
  variant2 = c(
    "sgpc_best",
    "sgpc_avg",
    "sgpc_avg",
    "sgpc_gaussian",
    "sgpc_comonotonic",
    "sgpc_emp"
  )
)

key_stats <- merge(key_comparisons, diff_stats, by = c("variant1", "variant2"))

############################################################################
### STRATIFIED ANALYSES
############################################################################

cat("Computing stratified analyses...\n")

# By year span
by_year_span <- all_data[,
  {
    list(
      n_obs = .N,
      n_conditions = uniqueN(paste(dataset_id, condition_id, sep = "__")),
      mad_emp_best = mad(sgpc_emp, sgpc_best),
      mad_emp_avg = mad(sgpc_emp, sgpc_avg),
      mad_emp_gaussian = mad(sgpc_emp, sgpc_gaussian),
      mad_emp_comonotonic = mad(sgpc_emp, sgpc_comonotonic),
      cor_emp_best = cor(sgpc_emp, sgpc_best, use = "complete.obs"),
      cor_emp_avg = cor(sgpc_emp, sgpc_avg, use = "complete.obs")
    )
  },
  by = year_span
]

# By content area
by_content_area <- all_data[,
  {
    list(
      n_obs = .N,
      n_conditions = uniqueN(paste(dataset_id, condition_id, sep = "__")),
      mad_emp_best = mad(sgpc_emp, sgpc_best),
      mad_emp_avg = mad(sgpc_emp, sgpc_avg),
      mad_emp_gaussian = mad(sgpc_emp, sgpc_gaussian),
      mad_emp_comonotonic = mad(sgpc_emp, sgpc_comonotonic),
      cor_emp_best = cor(sgpc_emp, sgpc_best, use = "complete.obs"),
      cor_emp_avg = cor(sgpc_emp, sgpc_avg, use = "complete.obs")
    )
  },
  by = content_area
]

# By year span × content area (cross-stratified)
by_stratum <- all_data[,
  {
    list(
      n_obs = .N,
      n_conditions = uniqueN(paste(dataset_id, condition_id, sep = "__")),
      mad_emp_best = mad(sgpc_emp, sgpc_best),
      mad_emp_avg = mad(sgpc_emp, sgpc_avg),
      mad_emp_gaussian = mad(sgpc_emp, sgpc_gaussian),
      mad_emp_comonotonic = mad(sgpc_emp, sgpc_comonotonic),
      cor_emp_best = cor(sgpc_emp, sgpc_best, use = "complete.obs"),
      cor_emp_avg = cor(sgpc_emp, sgpc_avg, use = "complete.obs"),
      rmsd_emp_best = rmsd(sgpc_emp, sgpc_best),
      rmsd_emp_avg = rmsd(sgpc_emp, sgpc_avg)
    )
  },
  by = .(year_span, content_area)
]

# By prior achievement quartile
all_data[,
  prior_quartile := cut(
    SCALE_SCORE_PRIOR,
    breaks = quantile(SCALE_SCORE_PRIOR, probs = 0:4 / 4, na.rm = TRUE),
    labels = c("Q1_Low", "Q2", "Q3", "Q4_High"),
    include.lowest = TRUE
  )
]

by_prior_quartile <- all_data[
  !is.na(prior_quartile),
  {
    list(
      n_obs = .N,
      mad_emp_best = mad(sgpc_emp, sgpc_best),
      mad_emp_avg = mad(sgpc_emp, sgpc_avg),
      mad_emp_gaussian = mad(sgpc_emp, sgpc_gaussian),
      cor_emp_best = cor(sgpc_emp, sgpc_best, use = "complete.obs"),
      cor_emp_avg = cor(sgpc_emp, sgpc_avg, use = "complete.obs")
    )
  },
  by = prior_quartile
]

############################################################################
### SAVE RESULTS
############################################################################

cat("\nSaving results...\n")

# Summary statistics
fwrite(summary_stats, file.path(OUTPUT_DIR, "sgpc_sensitivity_summary.csv"))
cat("  Saved summary statistics\n")

# Correlation matrix
fwrite(cor_matrix, file.path(OUTPUT_DIR, "sgpc_correlation_matrix.csv"))
cat("  Saved correlation matrix\n")

# All pairwise differences
fwrite(diff_stats, file.path(OUTPUT_DIR, "sgpc_pairwise_differences.csv"))
cat("  Saved pairwise differences\n")

# Key comparisons
fwrite(key_stats, file.path(OUTPUT_DIR, "sgpc_key_comparisons.csv"))
cat("  Saved key comparisons\n")

# Stratified analyses
fwrite(by_year_span, file.path(OUTPUT_DIR, "sgpc_by_year_span.csv"))
fwrite(by_content_area, file.path(OUTPUT_DIR, "sgpc_by_content_area.csv"))
fwrite(by_stratum, file.path(OUTPUT_DIR, "sgpc_by_stratum.csv"))
fwrite(by_prior_quartile, file.path(OUTPUT_DIR, "sgpc_by_prior_quartile.csv"))
cat("  Saved stratified analyses\n")
cat("  Manifest will be written at end of STEP_2 (Step 2.6)\n")

############################################################################
### PRINT SUMMARY
############################################################################

cat("\n====================================================================\n")
cat("AGGREGATE ANALYSIS COMPLETE\n")
cat("====================================================================\n\n")

key_findings_display <- c(
  sprintf(
    "Empirical vs best-fit parametric: r=%.3f, MAD=%.1f percentile points",
    key_stats[comparison == "Empirical vs Best-fit", correlation],
    key_stats[comparison == "Empirical vs Best-fit", mad]
  ),
  sprintf(
    "Empirical vs canonical averaged: r=%.3f, MAD=%.1f percentile points",
    key_stats[comparison == "Empirical vs Canonical", correlation],
    key_stats[comparison == "Empirical vs Canonical", mad]
  ),
  sprintf(
    "Impact of mis-specification (Gaussian): MAD=%.1f percentile points",
    key_stats[comparison == "Empirical vs Gaussian", mad]
  ),
  sprintf(
    "TAMP comonotonic assumption: MAD=%.1f percentile points",
    key_stats[comparison == "Empirical vs Comonotonic", mad]
  )
)
cat("Key Findings:\n")
for (finding in key_findings_display) {
  cat(" ", finding, "\n")
}

cat("\nOutput files created in:", OUTPUT_DIR, "\n")
cat("  - sgpc_sensitivity_summary.csv\n")
cat("  - sgpc_correlation_matrix.csv\n")
cat("  - sgpc_pairwise_differences.csv\n")
cat("  - sgpc_key_comparisons.csv\n")
cat("  - sgpc_by_year_span.csv\n")
cat("  - sgpc_by_content_area.csv\n")
cat("  - sgpc_by_stratum.csv\n")
cat("  - sgpc_by_prior_quartile.csv\n")
cat("  - sgpc_sensitivity_manifest.json\n\n")
