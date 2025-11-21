################################################################################
### Quick Validation: Test Multi-Format Export
################################################################################
### Purpose: Verify that multi-format export works correctly before full run
################################################################################

# Setup
setwd("/Users/conet/Research/Graphics_Visualizations/Copula_Sensitivity_Analyses")

# Source the export utility
cat("Testing multi-format export utility...\n\n")

# Check if required packages are installed
required_packages <- c("ggplot2", "svglite", "ragg")
missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("WARNING: Some packages are missing:\n")
  cat("  -", paste(missing_packages, collapse = ", "), "\n")
  cat("\nInstall with:\n")
  cat("  install.packages(c('", paste(missing_packages, collapse = "', '"), "'))\n\n", sep = "")
  cat("Continuing with available formats...\n\n")
}

# Source the export utility
source("functions/export_plot_utils.R")

# Check if functions are available
if (exists("export_plot_multi_format")) {
  cat("✓ export_plot_multi_format() loaded successfully\n")
} else {
  stop("✗ export_plot_multi_format() not found")
}

if (exists("export_ggplot_multi_format")) {
  cat("✓ export_ggplot_multi_format() loaded successfully\n")
} else {
  stop("✗ export_ggplot_multi_format() not found")
}

cat("\n")

# Create test output directory
test_dir <- "STEP_1_Family_Selection/export_format_test"
if (!dir.exists(test_dir)) {
  dir.create(test_dir, recursive = TRUE)
}

################################################################################
### Test 1: Base R Plot Export
################################################################################

cat("Test 1: Base R plot export\n")
cat("  Creating simple scatter plot...\n")

simple_plot <- function() {
  set.seed(42)
  x <- rnorm(100)
  y <- 2*x + rnorm(100, sd = 0.5)
  
  plot(x, y, pch = 19, col = rgb(0, 0, 1, 0.5),
       main = "Test Scatter Plot (Base R)",
       xlab = "X Variable", ylab = "Y Variable")
  abline(lm(y ~ x), col = "red", lwd = 2)
  grid(col = "grey90")
}

# Determine available formats
available_formats <- c("pdf")
if ("svglite" %in% installed.packages()[,1]) available_formats <- c(available_formats, "svg")
if ("ragg" %in% installed.packages()[,1]) available_formats <- c(available_formats, "png")

cat("  Exporting to:", paste(available_formats, collapse = ", "), "\n")

result1 <- export_plot_multi_format(
  plot_expr = simple_plot,
  base_filename = file.path(test_dir, "test_base_r"),
  width = 7,
  height = 7,
  formats = available_formats,
  verbose = TRUE
)

cat("  ✓ Base R export complete\n\n")

################################################################################
### Test 2: ggplot2 Export
################################################################################

cat("Test 2: ggplot2 export\n")
cat("  Creating ggplot2 scatter plot...\n")

library(ggplot2)

test_data <- data.frame(
  x = rnorm(100),
  y = 2 * rnorm(100) + rnorm(100, sd = 0.5)
)

p <- ggplot(test_data, aes(x = x, y = y)) +
  geom_point(color = "steelblue", alpha = 0.6, size = 2) +
  geom_smooth(method = "lm", color = "red", se = TRUE) +
  labs(
    title = "Test Scatter Plot (ggplot2)",
    x = "X Variable",
    y = "Y Variable"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    panel.grid.minor = element_blank()
  )

cat("  Exporting to:", paste(available_formats, collapse = ", "), "\n")

result2 <- export_ggplot_multi_format(
  plot_obj = p,
  base_filename = file.path(test_dir, "test_ggplot2"),
  width = 8,
  height = 7,
  formats = available_formats,
  verbose = TRUE
)

cat("  ✓ ggplot2 export complete\n\n")

################################################################################
### Test 3: Verify Files Created
################################################################################

cat("Test 3: Verifying output files\n")

expected_files <- c(
  "test_base_r.pdf",
  "test_ggplot2.pdf"
)

if ("svg" %in% available_formats) {
  expected_files <- c(expected_files, "test_base_r.svg", "test_ggplot2.svg")
}

if ("png" %in% available_formats) {
  expected_files <- c(expected_files, "test_base_r@2x.png", "test_ggplot2@2x.png")
}

all_exist <- TRUE
for (f in expected_files) {
  full_path <- file.path(test_dir, f)
  if (file.exists(full_path)) {
    file_size <- file.info(full_path)$size
    cat("  ✓", f, "-", format(file_size / 1024, digits = 1), "KB\n")
  } else {
    cat("  ✗", f, "- MISSING\n")
    all_exist <- FALSE
  }
}

cat("\n")

################################################################################
### Summary
################################################################################

cat("====================================================================\n")
cat("MULTI-FORMAT EXPORT VALIDATION\n")
cat("====================================================================\n\n")

if (all_exist) {
  cat("✓ ALL TESTS PASSED\n\n")
  cat("Multi-format export is working correctly!\n")
  cat("Output files located in:", test_dir, "\n\n")
  cat("You can now run:\n")
  cat("  - quick_test_uncertainty.R (with multi-format export)\n")
  cat("  - test_contour_plots.R (with multi-format export)\n\n")
} else {
  cat("✗ SOME TESTS FAILED\n\n")
  cat("Please check the error messages above.\n")
}

cat("Available formats on this system:\n")
cat("  PDF:", "pdf" %in% available_formats, "\n")
cat("  SVG:", "svg" %in% available_formats, 
    ifelse("svg" %in% available_formats, "", " (install 'svglite')"), "\n")
cat("  PNG:", "png" %in% available_formats, 
    ifelse("png" %in% available_formats, "", " (install 'ragg')"), "\n")

cat("\n")
cat("====================================================================\n")

