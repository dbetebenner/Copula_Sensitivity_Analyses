############################################################################
### Integration Test: STEP 2 SGPc Sensitivity - Full Pipeline
###
### Purpose: Test the complete workflow on a small sample
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)
require(copula)

cat("====================================================================\n")
cat("STEP 2 SGPc SENSITIVITY: INTEGRATION TEST\n")
cat("====================================================================\n\n")

############################################################################
### SETUP
############################################################################

# Load functions
source("functions/sgpc_engine.R")
source("functions/longitudinal_pairs.R")
source("STEP_2_SGPc_Sensitivity/phase1_data_loader.R")

# Load test dataset
test_dataset <- "dataset_1"
dataset_file <- file.path("SGP", paste0(test_dataset, ".Rdata"))

if (!file.exists(dataset_file)) {
  # Try alternate locations
  alt_paths <- c(
    file.path("data", paste0(test_dataset, ".rda")),
    paste0(test_dataset, ".Rdata"),
    paste0(test_dataset, ".rda")
  )
  dataset_file <- alt_paths[file.exists(alt_paths)][1]

  if (is.na(dataset_file)) {
    stop(
      "Test dataset not found. Tried:\n  ",
      paste(
        c(file.path("SGP", paste0(test_dataset, ".Rdata")), alt_paths),
        collapse = "\n  "
      )
    )
  }
}

load(dataset_file)
cat("✓ Loaded", test_dataset, ":", nrow(STATE_DATA_LONG), "rows\n\n")

# Load canonical parameters
canonical_data <- load_canonical_parameters()
canonical_params <- canonical_data$canonical_params

cat("✓ Loaded canonical parameters:", nrow(canonical_params), "strata\n\n")

############################################################################
### TEST: Process Single Condition
############################################################################

# Get conditions
conditions <- get_phase1_conditions(test_dataset)
cat("Available conditions:", length(conditions), "\n")

# Pick a valid condition (one that actually exists in Phase 1 outputs)
test_condition <- "2006_G4_G5_MATHEMATICS"

cat("Testing with condition:", test_condition, "\n\n")

# Parse condition
cond_meta <- parse_condition_id(test_condition)
cat("Condition metadata:\n")
cat("  Year:", cond_meta$year_prior, "\n")
cat(
  "  Grade span:",
  cond_meta$grade_prior,
  "->",
  cond_meta$grade_current,
  "(",
  cond_meta$year_span,
  "year)\n"
)
cat("  Content:", cond_meta$content_area, "\n\n")

# Load Phase 1 results
cat("Loading Phase 1 results for condition...\n")
phase1_results <- load_phase1_condition(test_dataset, test_condition)

cat("  Empirical copula:", !is.null(phase1_results$empirical_copula), "\n")
cat("  Best-fit copula:", !is.null(phase1_results$best_fit_copula), "\n")
cat("  Copula params:", !is.null(phase1_results$copula_params), "\n")

if (is.null(phase1_results$empirical_copula)) {
  cat("\n⚠ Warning: Empirical copula not loaded. Will create on-the-fly.\n")
}

# Create longitudinal pairs
cat("\nCreating longitudinal pairs...\n")
pairs <- create_longitudinal_pairs(
  data = STATE_DATA_LONG,
  grade_prior = cond_meta$grade_prior,
  grade_current = cond_meta$grade_current,
  year_prior = as.character(cond_meta$year_prior),
  content_prior = cond_meta$content_area,
  content_current = cond_meta$content_area
)

cat("  ✓ Created", nrow(pairs), "pairs\n\n")

# Convert to pseudo-observations
u <- rank(pairs$SCALE_SCORE_PRIOR) / (nrow(pairs) + 1)
v <- rank(pairs$SCALE_SCORE_CURRENT) / (nrow(pairs) + 1)

cat("Pseudo-observations:\n")
cat("  u range:", round(min(u), 3), "-", round(max(u), 3), "\n")
cat("  v range:", round(min(v), 3), "-", round(max(v), 3), "\n")
cat("  Kendall tau:", round(cor(u, v, method = "kendall"), 3), "\n\n")

############################################################################
### TEST: Compute All SGPc Variants
############################################################################

cat("Computing SGPc variants...\n")

# 1. Empirical
if (!is.null(phase1_results$empirical_copula)) {
  sgpc_emp <- sgpc_engine(
    u,
    v,
    phase1_results$empirical_copula,
    scale = "percentile"
  )
  cat(
    "  ✓ SGPc_emp computed (range:",
    min(sgpc_emp, na.rm = TRUE),
    "-",
    max(sgpc_emp, na.rm = TRUE),
    ")\n"
  )
} else {
  # Create on-the-fly
  emp_cop <- empCopula(cbind(u, v), smoothing = "beta")
  sgpc_emp <- sgpc_engine(u, v, emp_cop, scale = "percentile")
  cat("  ✓ SGPc_emp computed (created empCopula on-the-fly)\n")
}

# 2. Best-fit parametric
if (!is.null(phase1_results$best_fit_copula)) {
  sgpc_best <- sgpc_engine(
    u,
    v,
    phase1_results$best_fit_copula,
    scale = "percentile"
  )
  cat("  ✓ SGPc_best computed\n")
} else {
  cat("  ⚠ SGPc_best: No best-fit copula available\n")
}

# 3. Canonical averaged
canonical_cop <- create_canonical_copula(
  cond_meta$year_span,
  cond_meta$content_area,
  canonical_params
)
sgpc_avg <- sgpc_engine(u, v, canonical_cop, scale = "percentile")
cat("  ✓ SGPc_avg computed (canonical t-copula)\n")

# 4. Gaussian
tau_est <- cor(u, v, method = "kendall")
gaussian_cop <- normalCopula(param = sin(pi * tau_est / 2))
sgpc_gaussian <- sgpc_engine(u, v, gaussian_cop, scale = "percentile")
cat("  ✓ SGPc_gaussian computed\n")

# 5. Comonotonic
sgpc_comon <- sgpc_engine(u, v, "comonotonic", scale = "percentile")
cat("  ✓ SGPc_comonotonic computed\n\n")

############################################################################
### TEST: Compare Variants
############################################################################

cat("Comparing variants:\n")
cat("  Empirical vs Canonical:\n")
cat("    Correlation: r =", round(cor(sgpc_emp, sgpc_avg), 3), "\n")
cat(
  "    MAD:",
  round(mean(abs(sgpc_emp - sgpc_avg)), 2),
  "percentile points\n\n"
)

cat("  Empirical vs Gaussian:\n")
cat("    Correlation: r =", round(cor(sgpc_emp, sgpc_gaussian), 3), "\n")
cat(
  "    MAD:",
  round(mean(abs(sgpc_emp - sgpc_gaussian)), 2),
  "percentile points\n\n"
)

cat("  Empirical vs Comonotonic:\n")
cat("    Correlation: r =", round(cor(sgpc_emp, sgpc_comon), 3), "\n")
cat(
  "    MAD:",
  round(mean(abs(sgpc_emp - sgpc_comon)), 2),
  "percentile points\n\n"
)

############################################################################
### SUMMARY
############################################################################

cat("====================================================================\n")
cat("INTEGRATION TEST COMPLETE\n")
cat("====================================================================\n\n")

cat("✓ Full pipeline operational:\n")
cat("  - Phase 1 data loading works\n")
cat("  - Canonical copulas can be created\n")
cat("  - SGPc variants can be computed\n")
cat("  - Comparisons are meaningful\n\n")

cat("Ready to run full analysis on all datasets.\n")
cat(
  "Estimated runtime per dataset: 30-90 minutes (depending on parallel mode)\n\n"
)
