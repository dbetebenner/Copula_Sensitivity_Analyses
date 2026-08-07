############################################################################
### DIAGNOSTIC TEST: Summary Grid LaTeX Generation
############################################################################
### Purpose: Isolate and debug the generate_summary_grid_latex() function
###          to determine why .tex files are not being produced on EC2
###
### Usage: Run line-by-line in an R session, or source the whole file
###        from the project root or CURSOR_TEST_FILES directory
############################################################################

cat("\n")
cat("============================================================\n")
cat("DIAGNOSTIC: Summary Grid LaTeX Generation\n")
cat("============================================================\n")
cat("\n")

############################################################################
### STEP 1: Environment and LaTeX Availability Checks
############################################################################

cat("=== STEP 1: Environment Checks ===\n\n")

# Check working directory
cat("Working directory:", getwd(), "\n")

# Check for pdflatex in system PATH
pdflatex_path <- Sys.which("pdflatex")
cat("pdflatex available:", pdflatex_path != "", "\n")
if (pdflatex_path != "") {
  cat("  Path:", pdflatex_path, "\n")
}

# Check for tinytex R package
tinytex_available <- requireNamespace("tinytex", quietly = TRUE)
cat("tinytex R package:", tinytex_available, "\n")
if (tinytex_available) {
  tinytex_installed <- tryCatch(
    {
      tinytex::is_tinytex()
    },
    error = function(e) FALSE
  )
  cat("  TinyTeX installed:", tinytex_installed, "\n")
}

# Check for jsonlite (needed for metadata reading)
jsonlite_available <- requireNamespace("jsonlite", quietly = TRUE)
cat("jsonlite R package:", jsonlite_available, "\n")

cat("\n")

############################################################################
### STEP 2: Locate Project Root and Source Functions
############################################################################

cat("=== STEP 2: Source Functions ===\n\n")

# Determine project root
if (file.exists("functions/copula_contour_plots.R")) {
  PROJECT_ROOT <- getwd()
  func_prefix <- ""
} else if (file.exists("../functions/copula_contour_plots.R")) {
  PROJECT_ROOT <- normalizePath("..")
  func_prefix <- "../"
} else {
  stop(
    "Cannot locate project root. Run from project root or CURSOR_TEST_FILES/"
  )
}

cat("Project root:", PROJECT_ROOT, "\n")

# Source the main functions file
cat("Sourcing copula_contour_plots.R...\n")
source(paste0(func_prefix, "functions/copula_contour_plots.R"))

# Verify function exists
if (!exists("generate_summary_grid_latex")) {
  stop("ERROR: generate_summary_grid_latex function not found after sourcing!")
}
cat("  ✓ generate_summary_grid_latex function loaded\n\n")

############################################################################
### STEP 3: Define Test Output Directory
############################################################################

cat("=== STEP 3: Locate Test Output Directory ===\n\n")

# Look for existing test output (adjust path as needed for your EC2 setup)
possible_dirs <- c(
  # Standard test output location
  file.path(PROJECT_ROOT, "STEP_1_Family_Selection/results/test/contour_plots"),
  # Current directory if already in output
  ".",
  # Parent if in a condition subdirectory
  ".."
)

# Find first directory that contains condition subdirectories
output_base <- NULL
for (dir in possible_dirs) {
  if (dir.exists(dir)) {
    subdirs <- list.dirs(dir, full.names = FALSE, recursive = FALSE)
    # Look for pattern like "2005_G4_G5_MATHEMATICS"
    condition_dirs <- subdirs[grepl("^\\d{4}_G\\d+_G\\d+_", subdirs)]
    if (length(condition_dirs) > 0) {
      output_base <- normalizePath(dir)
      break
    }
  }
}

if (is.null(output_base)) {
  cat("WARNING: Could not find standard output directory structure.\n")
  cat("Checking if current directory is a condition output directory...\n")

  # Check if we're already in a condition directory
  if (
    file.exists("bivariate_density_original.pdf") || dir.exists("PARAMETRIC")
  ) {
    output_dir <- normalizePath(".")
    cat("  Using current directory as output_dir:", output_dir, "\n")
  } else {
    stop("Cannot locate output directory. Please set output_dir manually.")
  }
} else {
  # Use first condition directory found
  condition_dirs <- list.dirs(
    output_base,
    full.names = FALSE,
    recursive = FALSE
  )
  condition_dirs <- condition_dirs[grepl(
    "^\\d{4}_G\\d+_G\\d+_",
    condition_dirs
  )]

  cat(
    "Found",
    length(condition_dirs),
    "condition directories in:",
    output_base,
    "\n"
  )
  cat("Available conditions:\n")
  for (i in seq_along(condition_dirs)) {
    cat(sprintf("  [%d] %s\n", i, condition_dirs[i]))
  }

  # Use first one for testing
  output_dir <- file.path(output_base, condition_dirs[1])
  cat("\nUsing for test:", output_dir, "\n")
}

cat("\n")

############################################################################
### STEP 4: Verify Required Input Files
############################################################################

cat("=== STEP 4: Verify Required Input Files ===\n\n")

# Check for bivariate density plot
bivariate_pdf <- file.path(output_dir, "bivariate_density_original.pdf")
cat("bivariate_density_original.pdf:", file.exists(bivariate_pdf), "\n")

# Check PARAMETRIC directory structure
parametric_dir <- file.path(output_dir, "PARAMETRIC")
cat("PARAMETRIC/ directory:", dir.exists(parametric_dir), "\n")

if (dir.exists(parametric_dir)) {
  family_dirs <- list.dirs(
    parametric_dir,
    full.names = FALSE,
    recursive = FALSE
  )
  cat("  Family subdirectories:", paste(family_dirs, collapse = ", "), "\n")

  # Find best family by looking for summary JSON files
  best_family <- NULL
  for (fam in tolower(family_dirs)) {
    json_file <- file.path(
      parametric_dir,
      toupper(fam),
      sprintf("comparison_empirical_vs_%s_summary.json", fam)
    )
    if (file.exists(json_file)) {
      best_family <- fam
      cat("\n  Found metadata JSON for family:", fam, "\n")
      break
    }
  }

  if (is.null(best_family)) {
    # Fallback: use first non-empty family directory
    for (fam in tolower(family_dirs)) {
      fam_dir <- file.path(parametric_dir, toupper(fam))
      if (length(list.files(fam_dir)) > 0) {
        best_family <- fam
        cat("\n  Using first non-empty family (no JSON found):", fam, "\n")
        break
      }
    }
  }

  if (!is.null(best_family)) {
    # Check required files for this family
    fam_upper <- toupper(best_family)

    uncertainty_pdf <- file.path(
      parametric_dir,
      fam_upper,
      sprintf("%s_copula_with_uncertainty_CDF.pdf", best_family)
    )
    comparison_pdf <- file.path(
      parametric_dir,
      fam_upper,
      sprintf("comparison_empirical_vs_%s_full.pdf", best_family)
    )
    summary_json <- file.path(
      parametric_dir,
      fam_upper,
      sprintf("comparison_empirical_vs_%s_summary.json", best_family)
    )

    cat("\n  Checking files for", best_family, "copula:\n")
    cat(
      "    uncertainty CDF:",
      file.exists(uncertainty_pdf),
      if (!file.exists(uncertainty_pdf)) " <- MISSING!" else "",
      "\n"
    )
    cat(
      "    comparison full:",
      file.exists(comparison_pdf),
      if (!file.exists(comparison_pdf)) " <- MISSING!" else "",
      "\n"
    )
    cat(
      "    summary JSON:",
      file.exists(summary_json),
      if (!file.exists(summary_json)) " <- MISSING!" else "",
      "\n"
    )
  }
} else {
  cat("  ERROR: PARAMETRIC/ directory not found!\n")
  best_family <- "gaussian" # Default fallback
}

cat("\n")

############################################################################
### STEP 5: Create Minimal condition_info
############################################################################

cat("=== STEP 5: Create condition_info ===\n\n")

# Parse condition from directory name (e.g., "2005_G4_G5_MATHEMATICS")
dir_name <- basename(output_dir)
parts <- strsplit(dir_name, "_")[[1]]

if (length(parts) >= 4) {
  year_prior <- parts[1]
  grade_prior <- as.integer(gsub("G", "", parts[2]))
  grade_current <- as.integer(gsub("G", "", parts[3]))
  content <- paste(parts[4:length(parts)], collapse = "_")
  year_current <- as.character(as.integer(year_prior) + 1)
} else {
  # Fallback defaults
  year_prior <- "2005"
  grade_prior <- 4
  grade_current <- 5
  content <- "MATHEMATICS"
  year_current <- "2006"
}

condition_info <- list(
  dataset_id = "dataset_1",
  dataset_number = "1",
  year_prior = year_prior,
  year_current = year_current,
  grade_prior = grade_prior,
  grade_current = grade_current,
  content = content,
  year_span = 1,
  n_pairs = 10000 # Placeholder
)

cat("condition_info:\n")
print(condition_info)
cat("\n")

############################################################################
### STEP 6: Test LaTeX Generation (No Compilation)
############################################################################

cat("=== STEP 6: Test .tex Generation (compile_pdf = FALSE) ===\n\n")

# First, remove any existing summary_grid files
existing_tex <- file.path(output_dir, "summary_grid.tex")
existing_pdf <- file.path(output_dir, "summary_grid.pdf")
if (file.exists(existing_tex)) {
  cat("Removing existing summary_grid.tex...\n")
  file.remove(existing_tex)
}
if (file.exists(existing_pdf)) {
  cat("Removing existing summary_grid.pdf...\n")
  file.remove(existing_pdf)
}

cat("Calling generate_summary_grid_latex()...\n")
cat("  output_dir:", output_dir, "\n")
cat("  best_family:", best_family, "\n")
cat("  compile_pdf: FALSE\n")
cat("  keep_tex: TRUE\n\n")

result <- tryCatch(
  {
    generate_summary_grid_latex(
      output_dir = output_dir,
      condition_info = condition_info,
      best_family = best_family,
      copula_results = NULL, # Will use JSON metadata
      sgpc_stats = NULL, # Will use JSON metadata
      compile_pdf = FALSE, # Don't compile, just generate .tex
      keep_tex = TRUE
    )
  },
  error = function(e) {
    cat("\n!!! ERROR in generate_summary_grid_latex() !!!\n")
    cat("Error message:", conditionMessage(e), "\n")
    cat("\nFull error:\n")
    print(e)
    cat("\nTraceback:\n")
    traceback()
    return(NULL)
  },
  warning = function(w) {
    cat("WARNING:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }
)

cat("\n")

############################################################################
### STEP 7: Verify .tex File Was Created
############################################################################

cat("=== STEP 7: Verify Output ===\n\n")

tex_file <- file.path(output_dir, "summary_grid.tex")
if (file.exists(tex_file)) {
  cat("✓ summary_grid.tex was created successfully!\n")
  cat("  Path:", tex_file, "\n")
  cat("  Size:", file.info(tex_file)$size, "bytes\n")

  # Show first 30 lines
  cat("\nFirst 30 lines of .tex file:\n")
  cat("----------------------------\n")
  tex_content <- readLines(tex_file, n = 30)
  cat(tex_content, sep = "\n")
  cat("\n... (truncated)\n")
} else {
  cat("✗ summary_grid.tex was NOT created!\n")
  cat("  Expected at:", tex_file, "\n")

  # List what IS in the directory
  cat("\nFiles in output directory:\n")
  all_files <- list.files(output_dir, recursive = FALSE)
  for (f in head(all_files, 20)) {
    cat("  ", f, "\n")
  }
  if (length(all_files) > 20) {
    cat("  ... and", length(all_files) - 20, "more files\n")
  }
}

cat("\n")

############################################################################
### STEP 8: Manual LaTeX Compilation Test (if .tex exists)
############################################################################

cat("=== STEP 8: Manual LaTeX Compilation Test ===\n\n")

if (file.exists(tex_file)) {
  cat("Attempting manual compilation with pdflatex...\n")

  # Save current directory
  old_wd <- getwd()
  setwd(output_dir)

  # Try compilation with full error output
  compile_result <- tryCatch(
    {
      # Run pdflatex with interaction mode that shows errors
      result <- system2(
        "pdflatex",
        args = c(
          "-interaction=nonstopmode",
          "-halt-on-error",
          "summary_grid.tex"
        ),
        stdout = TRUE,
        stderr = TRUE
      )

      # Check for PDF
      if (file.exists("summary_grid.pdf")) {
        cat("\n✓ PDF compiled successfully!\n")
        cat("  Size:", file.info("summary_grid.pdf")$size, "bytes\n")
        "success"
      } else {
        cat("\n✗ PDF compilation failed. pdflatex output:\n")
        cat("-------------------------------------------\n")
        # Show last 50 lines of output (usually contains the error)
        output_lines <- tail(result, 50)
        cat(output_lines, sep = "\n")
        "failed"
      }
    },
    error = function(e) {
      cat("ERROR running pdflatex:", conditionMessage(e), "\n")
      "error"
    }
  )

  # Check for .log file which has detailed errors
  if (file.exists("summary_grid.log")) {
    cat("\nLaTeX log file exists. Checking for errors...\n")
    log_content <- readLines("summary_grid.log")
    error_lines <- grep("^!", log_content, value = TRUE)
    if (length(error_lines) > 0) {
      cat("Errors found in log:\n")
      cat(error_lines, sep = "\n")
    }

    # Also check for missing packages
    missing_pkg <- grep(
      "LaTeX Error: File.*not found",
      log_content,
      value = TRUE
    )
    if (length(missing_pkg) > 0) {
      cat("\nMissing LaTeX packages:\n")
      cat(missing_pkg, sep = "\n")
    }
  }

  # Restore directory
  setwd(old_wd)
} else {
  cat("Skipping compilation test - no .tex file to compile.\n")
}

cat("\n")

############################################################################
### STEP 9: Summary and Next Steps
############################################################################

cat("============================================================\n")
cat("DIAGNOSTIC SUMMARY\n")
cat("============================================================\n\n")

cat("Environment:\n")
cat(
  "  pdflatex:",
  if (pdflatex_path != "") "✓ Available" else "✗ NOT FOUND",
  "\n"
)
cat("  tinytex:", if (tinytex_available) "✓ Available" else "✗ NOT FOUND", "\n")
cat(
  "  jsonlite:",
  if (jsonlite_available) "✓ Available" else "✗ NOT FOUND",
  "\n"
)

cat("\nInput files:\n")
cat(
  "  bivariate_density_original.pdf:",
  if (file.exists(bivariate_pdf)) "✓" else "✗",
  "\n"
)
if (!is.null(best_family)) {
  fam_upper <- toupper(best_family)
  cat(
    "  ",
    best_family,
    "_copula_with_uncertainty_CDF.pdf: ",
    if (
      file.exists(file.path(
        parametric_dir,
        fam_upper,
        sprintf("%s_copula_with_uncertainty_CDF.pdf", best_family)
      ))
    ) {
      "✓"
    } else {
      "✗"
    },
    "\n",
    sep = ""
  )
}

cat("\nOutput:\n")
cat(
  "  summary_grid.tex:",
  if (file.exists(tex_file)) "✓ Created" else "✗ NOT created",
  "\n"
)
cat(
  "  summary_grid.pdf:",
  if (file.exists(file.path(output_dir, "summary_grid.pdf"))) {
    "✓ Compiled"
  } else {
    "✗ NOT compiled"
  },
  "\n"
)

cat("\n")

if (!file.exists(tex_file)) {
  cat("NEXT STEPS:\n")
  cat("1. Check the error output above from generate_summary_grid_latex()\n")
  cat("2. Verify all required input PDFs exist\n")
  cat("3. Check that jsonlite can read the summary JSON files\n")
} else if (!file.exists(file.path(output_dir, "summary_grid.pdf"))) {
  cat("NEXT STEPS:\n")
  cat("1. Check the LaTeX error output above\n")
  cat("2. Install missing LaTeX packages if indicated\n")
  cat("3. On EC2, you may need to install texlive packages:\n")
  cat("   sudo yum install texlive-latex texlive-collection-fontsrecommended\n")
  cat("   Or install TinyTeX in R: tinytex::install_tinytex()\n")
}

cat("\n============================================================\n")
cat("Test complete.\n")
cat("============================================================\n")
