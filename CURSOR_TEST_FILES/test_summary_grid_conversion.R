#!/usr/bin/env Rscript
############################################################################
# test_summary_grid_conversion.R
#
# Purpose: Debug why summary_grid SVG/PNG conversion isn't happening
#          during parallel execution but works manually.
#
# Run from EC2: Rscript test_summary_grid_conversion.R
############################################################################

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("TEST: Summary Grid SVG/PNG Conversion Debug\n")
cat(paste0(rep("=", 70), collapse = ""), "\n\n")

############################################################################
# STEP 1: Locate project and source functions
############################################################################

cat("=== STEP 1: Setup Environment ===\n\n")

# Find project root
if (file.exists("master_analysis.R")) {
  PROJECT_ROOT <- getwd()
} else if (file.exists("../master_analysis.R")) {
  PROJECT_ROOT <- normalizePath("..")
} else if (file.exists("../../master_analysis.R")) {
  PROJECT_ROOT <- normalizePath("../..")
} else {
  stop("Cannot find project root. Run from project root or CURSOR_TEST_FILES/")
}

cat("Project root:", PROJECT_ROOT, "\n")

# Source the functions
functions_file <- file.path(PROJECT_ROOT, "functions/copula_contour_plots.R")
cat("Sourcing:", functions_file, "\n")

if (!file.exists(functions_file)) {
  stop("Functions file not found: ", functions_file)
}

source(functions_file)
cat("  ✓ Functions loaded\n\n")

############################################################################
# STEP 2: Check external tools
############################################################################

cat("=== STEP 2: Check External Tools ===\n\n")

# Check pdf2svg
pdf2svg_path <- Sys.which("pdf2svg")
cat("pdf2svg path: '", pdf2svg_path, "'\n", sep = "")
cat("  Found: ", pdf2svg_path != "", "\n", sep = "")

# Check pdftoppm
pdftoppm_path <- Sys.which("pdftoppm")
cat("pdftoppm path: '", pdftoppm_path, "'\n", sep = "")
cat("  Found: ", pdftoppm_path != "", "\n", sep = "")

# Check convert (ImageMagick)
convert_path <- Sys.which("convert")
cat("convert path: '", convert_path, "'\n", sep = "")
cat("  Found: ", convert_path != "", "\n", sep = "")

cat("\n")

############################################################################
# STEP 3: Find a completed condition directory
############################################################################

cat("=== STEP 3: Find Test Condition Directory ===\n\n")

# Look for dataset_4 results
results_base <- file.path(
  PROJECT_ROOT,
  "STEP_1_Family_Selection/results/dataset_4/contour_plots"
)

if (!dir.exists(results_base)) {
  stop("Results directory not found: ", results_base)
}

# Find first condition with summary_grid.pdf
condition_dirs <- list.dirs(results_base, recursive = FALSE)
cat("Found", length(condition_dirs), "condition directories\n")

test_dir <- NULL
for (cond_dir in condition_dirs) {
  pdf_file <- file.path(cond_dir, "summary_grid.pdf")
  if (file.exists(pdf_file)) {
    test_dir <- cond_dir
    cat("  Using:", basename(cond_dir), "\n")
    break
  }
}

if (is.null(test_dir)) {
  stop("No condition directory found with summary_grid.pdf")
}

cat("\nTest directory:", test_dir, "\n\n")

############################################################################
# STEP 4: List existing files
############################################################################

cat("=== STEP 4: Current Files in Test Directory ===\n\n")

existing_files <- list.files(test_dir, pattern = "summary_grid")
cat("Existing summary_grid files:\n")
for (f in existing_files) {
  info <- file.info(file.path(test_dir, f))
  cat(sprintf(
    "  %s (%s bytes, %s)\n",
    f,
    format(info$size, big.mark = ","),
    info$mtime
  ))
}

cat("\n")

############################################################################
# STEP 5: Load condition metadata
############################################################################

cat("=== STEP 5: Load Condition Metadata ===\n\n")

# Parse condition from directory name (e.g., "2023_G4_G5_READING")
cond_name <- basename(test_dir)
parts <- strsplit(cond_name, "_")[[1]]

if (length(parts) >= 4) {
  year_current <- as.integer(parts[1])
  grade_prior <- as.integer(gsub("G", "", parts[2]))
  grade_current <- as.integer(gsub("G", "", parts[3]))
  content_area <- paste(parts[4:length(parts)], collapse = "_")
} else {
  stop("Cannot parse condition name: ", cond_name)
}

condition_info <- list(
  year_prior = year_current - 1,
  year_current = year_current,
  grade_prior = grade_prior,
  grade_current = grade_current,
  content_area = content_area
)

cat("Condition info:\n")
cat(sprintf(
  "  Year: %d -> %d\n",
  condition_info$year_prior,
  condition_info$year_current
))
cat(sprintf(
  "  Grade: %d -> %d\n",
  condition_info$grade_prior,
  condition_info$grade_current
))
cat(sprintf("  Content: %s\n", condition_info$content_area))

# Load copula results if available
copula_results_file <- file.path(test_dir, "copula_results.rds")
copula_results <- NULL
best_family <- "gaussian"

if (file.exists(copula_results_file)) {
  copula_results <- readRDS(copula_results_file)
  cat("\nCopula results loaded\n")

  # Find best family by AIC
  if (!is.null(copula_results)) {
    aics <- sapply(copula_results, function(x) {
      if (!is.null(x$aic)) x$aic else Inf
    })
    best_family <- names(which.min(aics))
    cat("Best family:", best_family, "\n")
  }
}

cat("\n")

############################################################################
# STEP 6: Remove existing SVG/PNG and test conversion
############################################################################

cat("=== STEP 6: Test Conversion ===\n\n")

# Remove existing SVG/PNG to test fresh conversion
svg_file <- file.path(test_dir, "summary_grid.svg")
png_file <- file.path(test_dir, "summary_grid@2x.png")

if (file.exists(svg_file)) {
  cat("Removing existing:", svg_file, "\n")
  file.remove(svg_file)
}

if (file.exists(png_file)) {
  cat("Removing existing:", png_file, "\n")
  file.remove(png_file)
}

cat(
  "\nCalling generate_summary_grid_latex() with export_formats = c('pdf', 'svg', 'png')...\n\n"
)

# Call the function with explicit formats
tryCatch(
  {
    generate_summary_grid_latex(
      output_dir = test_dir,
      condition_info = condition_info,
      best_family = best_family,
      copula_results = copula_results,
      sgpc_stats = NULL,
      compile_pdf = TRUE, # Will skip if PDF already exists
      keep_tex = TRUE, # Keep .tex for debugging
      fbox_sep = 1,
      export_formats = c("pdf", "svg", "png"),
      export_dpi = 300
    )
  },
  error = function(e) {
    cat("\n*** ERROR in generate_summary_grid_latex ***\n")
    cat("Message:", e$message, "\n")
    cat("\nTraceback:\n")
    traceback()
  }
)

cat("\n")

############################################################################
# STEP 7: Check results
############################################################################

cat("=== STEP 7: Results ===\n\n")

final_files <- list.files(test_dir, pattern = "summary_grid")
cat("Summary grid files after test:\n")
for (f in final_files) {
  info <- file.info(file.path(test_dir, f))
  cat(sprintf(
    "  %s (%s bytes, %s)\n",
    f,
    format(info$size, big.mark = ","),
    info$mtime
  ))
}

cat("\n")

# Check what was created
svg_exists <- file.exists(svg_file)
png_exists <- file.exists(png_file)

cat("Conversion results:\n")
cat("  SVG created:", svg_exists, "\n")
cat("  PNG created:", png_exists, "\n")

if (!svg_exists && pdf2svg_path != "") {
  cat("\n⚠ SVG not created despite pdf2svg being available!\n")
  cat("  This suggests an issue in the conversion code path.\n")
}

if (!png_exists && pdftoppm_path != "") {
  cat("\n⚠ PNG not created despite pdftoppm being available!\n")
  cat("  This suggests an issue in the conversion code path.\n")
}

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("TEST COMPLETE\n")
cat(paste0(rep("=", 70), collapse = ""), "\n\n")
