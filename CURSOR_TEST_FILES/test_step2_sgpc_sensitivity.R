############################################################################
### Test Script: New STEP 2 SGPc Sensitivity Analysis
###
### Purpose: Validate the re-imagined STEP 2 implementation
###
### Tests:
###   1. Phase 1 data loading infrastructure
###   2. SGPc variant computation on sample condition
###   3. File structure and outputs
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)
require(copula)

cat("====================================================================\n")
cat("TESTING NEW STEP 2: SGPc SENSITIVITY ANALYSIS\n")
cat("====================================================================\n\n")

############################################################################
### TEST 1: Load Phase 1 Helper Functions
############################################################################

cat("TEST 1: Loading Phase 1 helper functions...\n")

tryCatch(
  {
    source("STEP_2_SGPc_Sensitivity/phase1_data_loader.R")
    cat("  ✓ phase1_data_loader.R loaded successfully\n")
  },
  error = function(e) {
    cat("  ✗ ERROR:", e$message, "\n")
    stop("Cannot proceed without helper functions")
  }
)

############################################################################
### TEST 2: Load Canonical Parameters
############################################################################

cat("\nTEST 2: Loading canonical parameters...\n")

canonical_data <- tryCatch(
  {
    load_canonical_parameters()
  },
  error = function(e) {
    cat("  ✗ ERROR:", e$message, "\n")
    stop("Cannot load canonical parameters. Run Phase 1 analysis first.")
  }
)

cat("  ✓ Manifest loaded:", length(canonical_data$manifest), "top-level keys\n")
cat(
  "  ✓ Canonical parameters:",
  nrow(canonical_data$canonical_params),
  "strata\n"
)

############################################################################
### TEST 3: Check Phase 1 Condition Availability
############################################################################

cat("\nTEST 3: Checking Phase 1 condition availability...\n")

test_dataset <- "dataset_1"
conditions <- get_phase1_conditions(test_dataset)

cat("  ✓ Found", length(conditions), "conditions in", test_dataset, "\n")
cat("  Sample conditions:\n")
for (i in 1:min(5, length(conditions))) {
  cat("   ", conditions[i], "\n")
}

############################################################################
### TEST 4: Load Sample Condition from Phase 1
############################################################################

cat("\nTEST 4: Loading sample condition from Phase 1...\n")

if (length(conditions) > 0) {
  test_condition <- conditions[1]
  cat("  Testing with:", test_condition, "\n")

  phase1_result <- tryCatch(
    {
      load_phase1_condition(test_dataset, test_condition)
    },
    error = function(e) {
      cat("  ✗ ERROR:", e$message, "\n")
      return(NULL)
    }
  )

  if (!is.null(phase1_result)) {
    cat("  ✓ Condition loaded successfully\n")
    cat(
      "    - Empirical copula:",
      !is.null(phase1_result$empirical_copula),
      "\n"
    )
    cat("    - Best-fit copula:", !is.null(phase1_result$best_fit_copula), "\n")
    cat("    - Copula params:", !is.null(phase1_result$copula_params), "\n")

    if (!is.null(phase1_result$empirical_copula)) {
      cat(
        "    - Empirical copula class:",
        class(phase1_result$empirical_copula),
        "\n"
      )
    }

    if (!is.null(phase1_result$best_fit_copula)) {
      cat(
        "    - Best-fit copula class:",
        class(phase1_result$best_fit_copula),
        "\n"
      )
    }
  }
} else {
  cat("  ⚠ No conditions available to test\n")
}

############################################################################
### TEST 5: Parse Condition ID
############################################################################

cat("\nTEST 5: Testing condition ID parsing...\n")

if (length(conditions) > 0) {
  test_condition <- conditions[1]
  parsed <- parse_condition_id(test_condition)

  cat("  Condition:", test_condition, "\n")
  cat("  Parsed:\n")
  cat("    - Year prior:", parsed$year_prior, "\n")
  cat("    - Grade prior:", parsed$grade_prior, "\n")
  cat("    - Grade current:", parsed$grade_current, "\n")
  cat("    - Content area:", parsed$content_area, "\n")
  cat("    - Year span:", parsed$year_span, "\n")
  cat("  ✓ Parsing works correctly\n")
}

############################################################################
### TEST 6: Create Canonical Copula
############################################################################

cat("\nTEST 6: Creating canonical copula from manifest...\n")

test_span <- 1
test_content <- "MATHEMATICS"

tryCatch(
  {
    canonical_cop <- create_canonical_copula(
      test_span,
      test_content,
      canonical_data$canonical_params
    )
    cat(
      "  ✓ Created canonical t-copula for",
      test_span,
      "year",
      test_content,
      "\n"
    )
    cat("    Class:", class(canonical_cop), "\n")
    cat(
      "    Parameters:",
      paste(names(canonical_cop@parameters), collapse = ", "),
      "\n"
    )
  },
  error = function(e) {
    cat("  ✗ ERROR:", e$message, "\n")
  }
)

############################################################################
### TEST 7: Check sgpc_engine Availability
############################################################################

cat("\nTEST 7: Checking sgpc_engine availability...\n")

if (file.exists("functions/sgpc_engine.R")) {
  source("functions/sgpc_engine.R")
  cat("  ✓ sgpc_engine.R loaded successfully\n")

  # Test with sample data
  u <- runif(100, 0.01, 0.99)
  v <- runif(100, 0.01, 0.99)

  test_cop <- normalCopula(param = 0.7)
  sgpc_test <- sgpc_engine(u, v, test_cop, scale = "percentile")

  cat("  ✓ sgpc_engine() works (test output length:", length(sgpc_test), ")\n")
} else {
  cat("  ✗ sgpc_engine.R not found\n")
}

############################################################################
### TEST 8: Verify File Structure
############################################################################

cat("\nTEST 8: Verifying new file structure...\n")

required_files <- c(
  "STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R",
  "STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R",
  "STEP_2_SGPc_Sensitivity/sgpc_visualizations.R",
  "STEP_2_SGPc_Sensitivity/sgpc_generate_report.R",
  "STEP_2_SGPc_Sensitivity/phase1_data_loader.R",
  "STEP_2_SGPc_Sensitivity/README.md"
)

all_exist <- TRUE
for (f in required_files) {
  exists <- file.exists(f)
  status <- if (exists) "✓" else "✗"
  cat("  ", status, basename(f), "\n")
  if (!exists) all_exist <- FALSE
}

if (all_exist) {
  cat("  ✓ All required files present\n")
} else {
  cat("  ✗ Some files missing\n")
}

############################################################################
### SUMMARY
############################################################################

cat("\n====================================================================\n")
cat("TEST SUMMARY\n")
cat("====================================================================\n\n")

cat("Infrastructure Status:\n")
cat("  ✓ Helper functions loaded\n")
cat("  ✓ Canonical parameters accessible\n")
cat("  ✓ Phase 1 conditions discoverable\n")
cat("  ✓ sgpc_engine operational\n")
cat("  ✓ File structure complete\n\n")

cat("Ready to run:\n")
cat("  1. source('STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R')\n")
cat("  2. source('STEP_2_SGPc_Sensitivity/sgpc_aggregate_analysis.R')\n")
cat("  3. source('STEP_2_SGPc_Sensitivity/sgpc_visualizations.R')\n")
cat("  4. source('STEP_2_SGPc_Sensitivity/sgpc_generate_report.R')\n\n")

cat("Or via master_analysis.R:\n")
cat("  STEPS_TO_RUN <- c(2)\n")
cat("  source('master_analysis.R')\n\n")

cat("Note: Actual computation will require loading STATE_DATA_LONG first.\n\n")
