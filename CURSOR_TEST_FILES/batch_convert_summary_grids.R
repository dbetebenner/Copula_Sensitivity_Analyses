#!/usr/bin/env Rscript
############################################################################
# batch_convert_summary_grids.R
# 
# Purpose: Batch convert all existing summary_grid.pdf files to SVG and PNG
#          for conditions that were processed before the conversion code
#          was added to generate_summary_grid_latex().
#
# Run from EC2: Rscript CURSOR_TEST_FILES/batch_convert_summary_grids.R
############################################################################

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("Batch Convert: summary_grid.pdf -> SVG + PNG\n")
cat(paste0(rep("=", 70), collapse = ""), "\n\n")

# Configuration
EXPORT_DPI <- 300
DRY_RUN <- FALSE  # Set to TRUE to preview without converting

############################################################################
# STEP 1: Check tools
############################################################################

cat("=== Step 1: Check External Tools ===\n\n")

pdf2svg_path <- Sys.which("pdf2svg")
pdftoppm_path <- Sys.which("pdftoppm")

cat(sprintf("pdf2svg: %s\n", ifelse(pdf2svg_path != "", pdf2svg_path, "NOT FOUND")))
cat(sprintf("pdftoppm: %s\n", ifelse(pdftoppm_path != "", pdftoppm_path, "NOT FOUND")))

if (pdf2svg_path == "" && pdftoppm_path == "") {
  stop("Neither pdf2svg nor pdftoppm found. Install with: sudo dnf install poppler-utils && (build pdf2svg from source)")
}

cat("\n")

############################################################################
# STEP 2: Find all summary_grid.pdf files
############################################################################

cat("=== Step 2: Find All summary_grid.pdf Files ===\n\n")

# Find project root
if (file.exists("master_analysis.R")) {
  PROJECT_ROOT <- getwd()
} else if (file.exists("../master_analysis.R")) {
  PROJECT_ROOT <- normalizePath("..")
} else {
  stop("Cannot find project root. Run from project root or CURSOR_TEST_FILES/")
}

# Search for all summary_grid.pdf files
results_dir <- file.path(PROJECT_ROOT, "STEP_1_Family_Selection/results")

if (!dir.exists(results_dir)) {
  stop("Results directory not found: ", results_dir)
}

# Find all summary_grid.pdf files recursively
pdf_files <- list.files(results_dir, 
                        pattern = "^summary_grid\\.pdf$", 
                        recursive = TRUE, 
                        full.names = TRUE)

cat(sprintf("Found %d summary_grid.pdf files\n\n", length(pdf_files)))

if (length(pdf_files) == 0) {
  cat("No files to convert.\n")
  quit(save = "no")
}

############################################################################
# STEP 3: Convert each PDF
############################################################################

cat("=== Step 3: Convert PDFs ===\n\n")

converted_svg <- 0
converted_png <- 0
skipped_svg <- 0
skipped_png <- 0
failed <- 0

for (pdf_file in pdf_files) {
  dir_path <- dirname(pdf_file)
  cond_name <- basename(dir_path)
  
  svg_file <- file.path(dir_path, "summary_grid.svg")
  png_file <- file.path(dir_path, "summary_grid@2x.png")
  
  cat(sprintf("Processing: %s\n", cond_name))
  
  # SVG conversion
  if (file.exists(svg_file)) {
    cat("  SVG: already exists (skipped)\n")
    skipped_svg <- skipped_svg + 1
  } else if (pdf2svg_path != "") {
    if (DRY_RUN) {
      cat("  SVG: would convert (dry run)\n")
    } else {
      result <- tryCatch({
        system2("pdf2svg", args = c(pdf_file, svg_file), 
                stdout = FALSE, stderr = FALSE)
        if (file.exists(svg_file)) {
          cat("  SVG: ✓ converted\n")
          converted_svg <- converted_svg + 1
          TRUE
        } else {
          cat("  SVG: ✗ conversion failed (no output)\n")
          failed <- failed + 1
          FALSE
        }
      }, error = function(e) {
        cat(sprintf("  SVG: ✗ error: %s\n", e$message))
        failed <- failed + 1
        FALSE
      })
    }
  } else {
    cat("  SVG: skipped (pdf2svg not available)\n")
    skipped_svg <- skipped_svg + 1
  }
  
  # PNG conversion
  if (file.exists(png_file)) {
    cat("  PNG: already exists (skipped)\n")
    skipped_png <- skipped_png + 1
  } else if (pdftoppm_path != "") {
    if (DRY_RUN) {
      cat("  PNG: would convert (dry run)\n")
    } else {
      result <- tryCatch({
        # pdftoppm outputs to prefix.png, use -singlefile for single page
        tmp_prefix <- file.path(dir_path, "summary_grid_tmp")
        system2("pdftoppm", 
                args = c("-png", "-r", as.character(EXPORT_DPI * 2), "-singlefile",
                         pdf_file, tmp_prefix),
                stdout = FALSE, stderr = FALSE)
        tmp_png <- paste0(tmp_prefix, ".png")
        if (file.exists(tmp_png)) {
          file.rename(tmp_png, png_file)
          cat(sprintf("  PNG: ✓ converted (%ddpi)\n", EXPORT_DPI * 2))
          converted_png <- converted_png + 1
          TRUE
        } else {
          cat("  PNG: ✗ conversion failed (no output)\n")
          failed <- failed + 1
          FALSE
        }
      }, error = function(e) {
        cat(sprintf("  PNG: ✗ error: %s\n", e$message))
        failed <- failed + 1
        FALSE
      })
    }
  } else {
    cat("  PNG: skipped (pdftoppm not available)\n")
    skipped_png <- skipped_png + 1
  }
  
  cat("\n")
}

############################################################################
# STEP 4: Summary
############################################################################

cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("SUMMARY\n")
cat(paste0(rep("=", 70), collapse = ""), "\n\n")

cat(sprintf("Total PDF files found: %d\n\n", length(pdf_files)))

cat("SVG:\n")
cat(sprintf("  Converted: %d\n", converted_svg))
cat(sprintf("  Skipped (exists): %d\n", skipped_svg))

cat("\nPNG:\n")
cat(sprintf("  Converted: %d\n", converted_png))
cat(sprintf("  Skipped (exists): %d\n", skipped_png))

cat(sprintf("\nFailed: %d\n", failed))

if (DRY_RUN) {
  cat("\n*** DRY RUN - no files were actually converted ***\n")
  cat("Set DRY_RUN <- FALSE to perform actual conversion.\n")
}

cat("\nDone!\n")
