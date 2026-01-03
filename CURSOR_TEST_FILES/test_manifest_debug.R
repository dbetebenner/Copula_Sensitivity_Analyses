# Quick debug: Test manifest export in isolation
# Save as: test_manifest_debug.R
#
# Run with: Rscript test_manifest_debug.R
# Or source from R console: source("test_manifest_debug.R")

require(data.table)
require(jsonlite)

cat("\n")
cat("====================================================================\n")
cat("DEBUG: Testing export_analysis_manifest()\n")
cat("====================================================================\n")
cat("\n")

# Source the function file
cat("Sourcing functions/copula_contour_plots.R...\n")
source("functions/copula_contour_plots.R")
cat("  ✓ Functions loaded\n\n")

# Create minimal mock data that matches what test_contour_plots.R creates
cat("Creating mock_results data.table...\n")

mock_results <- data.table(
  dataset_id = rep("dataset_1", 3),
  condition_id = rep("2005_G4_G5_MATHEMATICS", 3),
  year_span = rep(1, 3),
  grade_prior = rep(4, 3),
  grade_current = rep(5, 3),
  content_area = rep("MATHEMATICS", 3),
  n_pairs = rep(51536, 3),
  family = c("t", "gaussian", "frank"),
  aic = c(-69145.8, -69100.5, -68900.2),
  bic = c(-69128.1, -69085.3, -68885.1),
  tau = c(0.660, 0.660, 0.660),
  parameter_1 = c(0.861, 0.85, 5.2),
  parameter_2 = c(18.5, NA, NA),
  tail_dep_lower = c(0.05, 0.0, 0.0),
  tail_dep_upper = c(0.05, 0.0, 0.0)
)

# Add delta_aic_vs_best (required by the function)
min_aic <- min(mock_results$aic, na.rm = TRUE)
mock_results[, delta_aic_vs_best := aic - min_aic]

cat("  ✓ Mock data created with", nrow(mock_results), "rows\n")
cat("\nMock data preview:\n")
print(mock_results[, .(family, aic, delta_aic_vs_best, tau)])
cat("\n")

# Test output directory
test_dir <- "STEP_1_Family_Selection/results/test/contour_plots/2005_G4_G5_MATHEMATICS/manifest_test"
cat("Output directory:", test_dir, "\n")

# Check if directory exists and create if needed
if (!dir.exists(test_dir)) {
  cat("  Directory does not exist, creating...\n")
  dir.create(test_dir, recursive = TRUE)
  cat("  ✓ Directory created\n")
} else {
  cat("  ✓ Directory exists\n")
}

# Check directory is writable
test_file <- file.path(test_dir, ".write_test")
write_ok <- tryCatch({
  writeLines("test", test_file)
  file.remove(test_file)
  TRUE
}, error = function(e) {
  cat("  ✗ Directory is NOT writable:", e$message, "\n")
  FALSE
})

if (write_ok) {
  cat("  ✓ Directory is writable\n")
}

cat("\n")
cat("--------------------------------------------------------------------\n")
cat("Calling export_analysis_manifest()...\n")
cat("--------------------------------------------------------------------\n")
cat("\n")

result <- tryCatch({
  export_analysis_manifest(
    results_dt = mock_results,
    output_dir = test_dir,
    manifest_filename = "debug_manifest.json"
  )
}, error = function(e) {
  cat("\n")
  cat("!!! ERROR OCCURRED !!!\n")
  cat("Message:", e$message, "\n")
  cat("\nCall stack:\n")
  cat(deparse(e$call), "\n")
  cat("\nTraceback:\n")
  traceback()
  NULL
})

cat("\n")
cat("--------------------------------------------------------------------\n")
cat("Results\n")
cat("--------------------------------------------------------------------\n")
cat("\n")

if (!is.null(result)) {
  cat("✓ Function returned successfully!\n\n")
  cat("Result structure:\n")
  cat("  - metadata:", !is.null(result$metadata), "\n")
  cat("  - parameter_recommendations:", !is.null(result$parameter_recommendations), "\n")
  cat("  - family_selection_summary:", !is.null(result$family_selection_summary), "\n")
  cat("  - conditions_index:", !is.null(result$conditions_index), "\n")
  cat("  - usage_guide:", !is.null(result$usage_guide), "\n")
  
  # Check if file exists
  json_file <- file.path(test_dir, "debug_manifest.json")
  cat("\nChecking for output file...\n")
  
  if (file.exists(json_file)) {
    file_size <- file.info(json_file)$size
    cat("  ✓ JSON file created:", json_file, "\n")
    cat("  ✓ File size:", file_size, "bytes\n")
    
    # Preview content
    cat("\nJSON content preview (first 500 chars):\n")
    content <- readLines(json_file, warn = FALSE)
    preview <- substr(paste(content, collapse = "\n"), 1, 500)
    cat(preview, "\n...\n")
  } else {
    cat("  ✗ JSON file NOT created!\n")
    cat("  Expected path:", json_file, "\n")
  }
  
  # Also test markdown export
  cat("\n")
  cat("--------------------------------------------------------------------\n")
  cat("Testing export_manifest_markdown()...\n")
  cat("--------------------------------------------------------------------\n")
  
  md_result <- tryCatch({
    export_manifest_markdown(
      manifest_file = json_file,
      output_file = file.path(test_dir, "debug_manifest.md")
    )
    TRUE
  }, error = function(e) {
    cat("  ✗ Markdown export failed:", e$message, "\n")
    FALSE
  })
  
  if (md_result) {
    md_file <- file.path(test_dir, "debug_manifest.md")
    if (file.exists(md_file)) {
      cat("  ✓ Markdown file created:", md_file, "\n")
      cat("  ✓ File size:", file.info(md_file)$size, "bytes\n")
    }
  }
  
} else {
  cat("✗ Function returned NULL (error occurred above)\n")
  cat("\nPossible causes:\n")
  cat("  1. Missing required columns in mock_results\n")
  cat("  2. Error in data processing within the function\n")
  cat("  3. JSON serialization issue\n")
  
  cat("\nRequired columns check:\n")
  required_cols <- c("condition_id", "family", "dataset_id", "year_span", 
                     "content_area", "delta_aic_vs_best", "tau", "n_pairs",
                     "grade_prior", "grade_current")
  for (col in required_cols) {
    has_col <- col %in% names(mock_results)
    cat(sprintf("  %s %s\n", ifelse(has_col, "✓", "✗"), col))
  }
}

cat("\n")
cat("====================================================================\n")
cat("DEBUG COMPLETE\n")
cat("====================================================================\n")
cat("\n")

# List all files in test directory
cat("Files in", test_dir, ":\n")
files <- list.files(test_dir, full.names = FALSE)
if (length(files) > 0) {
  for (f in files) {
    cat("  -", f, "\n")
  }
} else {
  cat("  (empty directory)\n")
}
cat("\n")

