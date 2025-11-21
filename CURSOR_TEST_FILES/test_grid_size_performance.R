#!/usr/bin/env Rscript
################################################################################
# Test Grid Size Performance Impact
# Compare grid_size 100 vs 300 for computation time and file sizes
################################################################################

# Source required functions
source("functions/longitudinal_pairs.R")
source("functions/copula_contour_plots.R")
source("functions/export_plot_utils.R")

# Load packages
library(copula)
library(data.table)
library(ggplot2)
library(wesanderson)

# Configuration
EXPORT_FORMATS <- c("pdf", "svg", "png")
EXPORT_DPI <- 300
EXPORT_VERBOSE <- FALSE

# Create test output directory
output_dir <- "quick_test_output/grid_size_test"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

################################################################################
# Load sample data (using Dataset 1)
################################################################################

cat("\n=================================================================\n")
cat("GRID SIZE PERFORMANCE TEST\n")
cat("=================================================================\n\n")

local_path <- "Data/Copula_Sensitivity_Data_Set_1.Rdata"
load(local_path)
cat("Data loaded: Copula_Sensitivity_Data_Set_1\n\n")

# Define test condition
test_condition <- list(
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2005,
  year_current = 2006,
  content_area = "MATHEMATICS"
)

# Create longitudinal pairs
cat("Creating test pairs...\n")
pairs_test <- create_longitudinal_pairs(
  data = Copula_Sensitivity_Data_Set_1,
  grade_prior = test_condition$grade_prior,
  grade_current = test_condition$grade_current,
  year_prior = test_condition$year_prior,
  year_current = test_condition$year_current,
  content_prior = test_condition$content_area
)
n_pairs <- nrow(pairs_test)
cat(sprintf("Sample size: n = %s\n\n", format(n_pairs, big.mark = ",")))

# Fit a single copula (t-copula) for testing
cat("Fitting t-copula...\n")
pseudo_obs <- pobs(as.matrix(pairs_test[, .(SCALE_SCORE_PRIOR, SCALE_SCORE_CURRENT)]))
fitted_t <- fitCopula(tCopula(dim = 2), pseudo_obs, method = "mpl")
fitted_copula <- tCopula(
  param = coef(fitted_t)[1],
  dim = 2,
  df = round(coef(fitted_t)[2])
)
cat("  Fitted successfully\n\n")

################################################################################
# Test 1: Comonotonic with grid_size 100 (current default)
################################################################################

cat("=================================================================\n")
cat("TEST 1: Comonotonic with grid_size 100\n")
cat("=================================================================\n")

time_start_100 <- Sys.time()

# Temporarily override the function to force grid_size 100
p_comonotonic_100 <- plot_parametric_copula_contour(
  fitted_copula = NULL,
  family = "comonotonic",
  grid_size = 100,  # Force 100
  plot_type = "cdf",
  title = "Comonotonic Copula (grid=100)",
  sample_size = n_pairs
)

time_100 <- as.numeric(difftime(Sys.time(), time_start_100, units = "secs"))
cat(sprintf("  Computation time: %.3f seconds\n", time_100))

# Export and measure file sizes
export_ggplot_multi_format(
  plot_obj = p_comonotonic_100,
  base_filename = file.path(output_dir, "comonotonic_grid100"),
  width = 10, height = 8,
  formats = EXPORT_FORMATS,
  dpi = EXPORT_DPI,
  verbose = FALSE
)

pdf_size_100 <- file.size(file.path(output_dir, "comonotonic_grid100.pdf")) / 1024
svg_size_100 <- file.size(file.path(output_dir, "comonotonic_grid100.svg")) / 1024
png_size_100 <- file.size(file.path(output_dir, "comonotonic_grid100@2x.png")) / 1024

cat(sprintf("  PDF size: %.1f KB\n", pdf_size_100))
cat(sprintf("  SVG size: %.1f KB\n", svg_size_100))
cat(sprintf("  PNG size: %.1f KB\n\n", png_size_100))

################################################################################
# Test 2: Comonotonic with grid_size 300
################################################################################

cat("=================================================================\n")
cat("TEST 2: Comonotonic with grid_size 300\n")
cat("=================================================================\n")

time_start_300 <- Sys.time()

p_comonotonic_300 <- plot_parametric_copula_contour(
  fitted_copula = NULL,
  family = "comonotonic",
  grid_size = 300,  # Force 300
  plot_type = "cdf",
  title = "Comonotonic Copula (grid=300)",
  sample_size = n_pairs
)

time_300 <- as.numeric(difftime(Sys.time(), time_start_300, units = "secs"))
cat(sprintf("  Computation time: %.3f seconds\n", time_300))

export_ggplot_multi_format(
  plot_obj = p_comonotonic_300,
  base_filename = file.path(output_dir, "comonotonic_grid300"),
  width = 10, height = 8,
  formats = EXPORT_FORMATS,
  dpi = EXPORT_DPI,
  verbose = FALSE
)

pdf_size_300 <- file.size(file.path(output_dir, "comonotonic_grid300.pdf")) / 1024
svg_size_300 <- file.size(file.path(output_dir, "comonotonic_grid300.svg")) / 1024
png_size_300 <- file.size(file.path(output_dir, "comonotonic_grid300@2x.png")) / 1024

cat(sprintf("  PDF size: %.1f KB\n", pdf_size_300))
cat(sprintf("  SVG size: %.1f KB\n", svg_size_300))
cat(sprintf("  PNG size: %.1f KB\n\n", png_size_300))

################################################################################
# Test 3: T-copula with grid_size 100
################################################################################

cat("=================================================================\n")
cat("TEST 3: T-copula with grid_size 100\n")
cat("=================================================================\n")

time_start_t100 <- Sys.time()

p_t_100 <- plot_parametric_copula_contour(
  fitted_copula = fitted_copula,
  family = "t",
  grid_size = 100,
  plot_type = "cdf",
  title = "T Copula (grid=100)",
  sample_size = n_pairs
)

time_t100 <- as.numeric(difftime(Sys.time(), time_start_t100, units = "secs"))
cat(sprintf("  Computation time: %.3f seconds\n", time_t100))

export_ggplot_multi_format(
  plot_obj = p_t_100,
  base_filename = file.path(output_dir, "t_copula_grid100"),
  width = 10, height = 8,
  formats = EXPORT_FORMATS,
  dpi = EXPORT_DPI,
  verbose = FALSE
)

pdf_size_t100 <- file.size(file.path(output_dir, "t_copula_grid100.pdf")) / 1024
svg_size_t100 <- file.size(file.path(output_dir, "t_copula_grid100.svg")) / 1024
png_size_t100 <- file.size(file.path(output_dir, "t_copula_grid100@2x.png")) / 1024

cat(sprintf("  PDF size: %.1f KB\n", pdf_size_t100))
cat(sprintf("  SVG size: %.1f KB\n", svg_size_t100))
cat(sprintf("  PNG size: %.1f KB\n\n", png_size_t100))

################################################################################
# Test 4: T-copula with grid_size 300
################################################################################

cat("=================================================================\n")
cat("TEST 4: T-copula with grid_size 300\n")
cat("=================================================================\n")

time_start_t300 <- Sys.time()

p_t_300 <- plot_parametric_copula_contour(
  fitted_copula = fitted_copula,
  family = "t",
  grid_size = 300,
  plot_type = "cdf",
  title = "T Copula (grid=300)",
  sample_size = n_pairs
)

time_t300 <- as.numeric(difftime(Sys.time(), time_start_t300, units = "secs"))
cat(sprintf("  Computation time: %.3f seconds\n", time_t300))

export_ggplot_multi_format(
  plot_obj = p_t_300,
  base_filename = file.path(output_dir, "t_copula_grid300"),
  width = 10, height = 8,
  formats = EXPORT_FORMATS,
  dpi = EXPORT_DPI,
  verbose = FALSE
)

pdf_size_t300 <- file.size(file.path(output_dir, "t_copula_grid300.pdf")) / 1024
svg_size_t300 <- file.size(file.path(output_dir, "t_copula_grid300.svg")) / 1024
png_size_t300 <- file.size(file.path(output_dir, "t_copula_grid300@2x.png")) / 1024

cat(sprintf("  PDF size: %.1f KB\n", pdf_size_t300))
cat(sprintf("  SVG size: %.1f KB\n", svg_size_t300))
cat(sprintf("  PNG size: %.1f KB\n\n", png_size_t300))

################################################################################
# Summary
################################################################################

cat("\n=================================================================\n")
cat("PERFORMANCE SUMMARY\n")
cat("=================================================================\n\n")

cat("COMONOTONIC COPULA:\n")
cat(sprintf("  Time (100 -> 300): %.3fs -> %.3fs (%.1fx slower)\n", 
            time_100, time_300, time_300/time_100))
cat(sprintf("  PDF size: %.1f KB -> %.1f KB (+%.1f%%)\n", 
            pdf_size_100, pdf_size_300, (pdf_size_300/pdf_size_100 - 1)*100))
cat(sprintf("  SVG size: %.1f KB -> %.1f KB (+%.1f%%)\n", 
            svg_size_100, svg_size_300, (svg_size_300/svg_size_100 - 1)*100))
cat(sprintf("  PNG size: %.1f KB -> %.1f KB (+%.1f%%)\n\n", 
            png_size_100, png_size_300, (png_size_300/png_size_100 - 1)*100))

cat("T-COPULA (representative of fitted copulas):\n")
cat(sprintf("  Time (100 -> 300): %.3fs -> %.3fs (%.1fx slower)\n", 
            time_t100, time_t300, time_t300/time_t100))
cat(sprintf("  PDF size: %.1f KB -> %.1f KB (+%.1f%%)\n", 
            pdf_size_t100, pdf_size_t300, (pdf_size_t300/pdf_size_t100 - 1)*100))
cat(sprintf("  SVG size: %.1f KB -> %.1f KB (+%.1f%%)\n", 
            svg_size_t100, svg_size_t300, (svg_size_t300/svg_size_t100 - 1)*100))
cat(sprintf("  PNG size: %.1f KB -> %.1f KB (+%.1f%%)\n\n", 
            png_size_t100, png_size_t300, (png_size_t300/png_size_t100 - 1)*100))

# Recommendation
avg_time_increase <- mean(c(time_300/time_100, time_t300/time_t100))
avg_size_increase <- mean(c(
  pdf_size_300/pdf_size_100,
  svg_size_300/svg_size_100,
  pdf_size_t300/pdf_size_t100,
  svg_size_t300/svg_size_t100
))

cat("RECOMMENDATION:\n")
if (avg_time_increase < 1.5 && avg_size_increase < 1.3) {
  cat("  ✓ Impact is NEGLIGIBLE - Safe to use grid_size=300 for ALL copulas\n")
  cat(sprintf("    Average time increase: %.1fx\n", avg_time_increase))
  cat(sprintf("    Average size increase: %.1fx\n", avg_size_increase))
} else {
  cat("  ⚠ Impact is SIGNIFICANT - Use grid_size=300 only for comonotonic\n")
  cat(sprintf("    Average time increase: %.1fx\n", avg_time_increase))
  cat(sprintf("    Average size increase: %.1fx\n", avg_size_increase))
}

cat("\n=================================================================\n")
cat("Test files saved to: quick_test_output/grid_size_test/\n")
cat("=================================================================\n\n")

