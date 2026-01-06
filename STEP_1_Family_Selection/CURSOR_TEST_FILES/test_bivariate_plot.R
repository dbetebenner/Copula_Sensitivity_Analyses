############################################################################
### TEST SCRIPT: Bivariate Density Plot Quick Iteration
############################################################################
### Purpose: Quick test script to iterate on bivariate density plot styling
###          without running the full analysis pipeline
###
### Usage:
###   1. Run from project root: source("STEP_1_Family_Selection/test_bivariate_plot.R")
###   2. Review output in: STEP_1_Family_Selection/test_bivariate_output/
###
### This script runs STANDALONE - no need to run master_analysis.R first
############################################################################

require(data.table)
require(ggplot2)
require(gridExtra)

cat("\n")
cat("====================================================================\n")
cat("TEST: BIVARIATE DENSITY PLOT STYLING\n")
cat("====================================================================\n")
cat("\n")

# Determine project root and set up path prefix
if (file.exists("functions/copula_contour_plots.R") && file.exists("dataset_configs.R")) {
  PROJECT_ROOT <- getwd()
  cat("Working directory:", PROJECT_ROOT, "\n")
  func_prefix <- ""
} else if (file.exists("../functions/copula_contour_plots.R") && file.exists("../dataset_configs.R")) {
  PROJECT_ROOT <- normalizePath("..")
  cat("Detected project root:", PROJECT_ROOT, "\n")
  func_prefix <- "../"
} else {
  stop("Cannot locate project root. Please run from project root or STEP_1_Family_Selection directory.")
}

# Source required functions
cat("Loading functions...\n")
source(paste0(func_prefix, "functions/copula_contour_plots.R"))
source(paste0(func_prefix, "functions/export_plot_utils.R"))
source(paste0(func_prefix, "dataset_configs.R"))
local_config <- paste0(func_prefix, "dataset_configs_local.R")
if (file.exists(local_config)) source(local_config)

################################################################################
### CONFIGURATION
################################################################################

# Export settings
EXPORT_FORMATS <- c("pdf", "svg", "png")
EXPORT_DPI <- 300
EXPORT_VERBOSE <- TRUE

# Output directory (relative to STEP_1_Family_Selection)
if (func_prefix == "") {
  OUTPUT_DIR <- "STEP_1_Family_Selection/test_bivariate_output"
} else {
  OUTPUT_DIR <- "test_bivariate_output"
}

# Create output directory
if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  cat("Created output directory:", OUTPUT_DIR, "\n")
}

################################################################################
### DATA LOADING
################################################################################

# Select dataset
DATASET_TO_TEST <- "dataset_1"
current_dataset <- DATASETS[[DATASET_TO_TEST]]
cat("\nDataset:", current_dataset$name, "\n")
cat("  Description:", current_dataset$description, "\n\n")

# Load data (following pattern from test_contour_plots.R)
if (!exists("STATE_DATA_LONG")) {
  cat("Loading state data from file...\n")
  
  # Check if SGP data file exists (preferred - contains traditional SGP columns)
  sgp_data_path <- paste0(func_prefix, current_dataset$local_path_sgp)
  use_sgp_data <- !is.null(current_dataset$local_path_sgp) && file.exists(sgp_data_path)
  
  if (use_sgp_data) {
    cat("  Using SGP data file (includes SGP_ORDER_1 and SGP columns)\n")
    load(sgp_data_path)
    
    if (exists(current_dataset$rdata_object_name_sgp)) {
      STATE_DATA_LONG <- get(current_dataset$rdata_object_name_sgp)
      cat("  Loaded:", current_dataset$rdata_object_name_sgp, "\n")
      cat("  Rows:", nrow(STATE_DATA_LONG), "\n\n")
    } else {
      stop("Expected object '", current_dataset$rdata_object_name_sgp, "' not found in SGP .Rdata file")
    }
  } else {
    # Fallback to base data file
    cat("  SGP data file not found, using base data file\n")
    
    data_path <- paste0(func_prefix, current_dataset$local_path)
    
    if (!file.exists(data_path)) {
      stop("Data file not found at: ", data_path,
           "\nPlease ensure data is available or update path in dataset_configs.R")
    }
    
    load(data_path)
    
    if (exists(current_dataset$rdata_object_name)) {
      STATE_DATA_LONG <- get(current_dataset$rdata_object_name)
      cat("  Loaded:", current_dataset$rdata_object_name, "\n")
      cat("  Rows:", nrow(STATE_DATA_LONG), "\n\n")
    } else {
      stop("Expected object '", current_dataset$rdata_object_name, "' not found in .Rdata file")
    }
  }
}

################################################################################
### EXTRACT TEST DATA
################################################################################

# Get a single condition for testing
cat("\nExtracting test condition...\n")

# Find consecutive year pairs
years <- sort(unique(STATE_DATA_LONG$YEAR))
if (length(years) >= 2) {
  year_prior <- years[length(years) - 1]
  year_current <- years[length(years)]
} else {
  stop("Need at least 2 years of data")
}

# Select content area and grades
content_area <- "MATHEMATICS"
grades <- sort(as.numeric(unique(STATE_DATA_LONG[CONTENT_AREA == content_area]$GRADE)))
grade_prior_num <- grades[3]  # Pick middle-ish grade
grade_current_num <- grade_prior_num + 1

# Convert to character for data.table filtering (GRADE is stored as character)
grade_prior <- as.character(grade_prior_num)
grade_current <- as.character(grade_current_num)

cat(sprintf("Test condition: %s->%s, Grade %s->%s, %s\n",
            year_prior, year_current, grade_prior, grade_current, content_area))

# Extract scores
test_data <- STATE_DATA_LONG[CONTENT_AREA == content_area & 
                             YEAR == year_current & 
                             GRADE == grade_current,
                             .(ID, SCALE_SCORE_CURRENT = SCALE_SCORE)]

prior_data <- STATE_DATA_LONG[CONTENT_AREA == content_area & 
                              YEAR == year_prior & 
                              GRADE == grade_prior,
                              .(ID, SCALE_SCORE_PRIOR = SCALE_SCORE)]

merged_data <- merge(test_data, prior_data, by = "ID")
merged_data <- na.omit(merged_data)

cat(sprintf("Sample size: %s students\n", format(nrow(merged_data), big.mark = ",")))

################################################################################
### CREATE BIVARIATE DENSITY PLOT
################################################################################

cat("\nCreating bivariate density plot...\n")

# Create subtitle showing grade/content/year progression (consistent with other plots)
plot_subtitle <- sprintf("Grade %s -> %s, %s, %s -> %s",
                         grade_prior, grade_current,
                         content_area,
                         year_prior, year_current)

# Create the plot with new styling
p <- plot_bivariate_density(
  scores_prior = merged_data$SCALE_SCORE_PRIOR,
  scores_current = merged_data$SCALE_SCORE_CURRENT,
  title = "Original Score Distribution",
  subtitle = plot_subtitle,
  x_label = sprintf("%s Grade %s", year_prior, grade_prior),
  y_label = sprintf("%s Grade %s", year_current, grade_current),
  n_bins = 100,
  sample_size = nrow(merged_data),
  plot_width = 7,
  plot_height = 7
)

# Get plot dimensions from attributes
plot_width <- attr(p, "plot_width") %||% 7
plot_height <- attr(p, "plot_height") %||% 7

cat(sprintf("Plot dimensions: %g x %g inches\n", plot_width, plot_height))

################################################################################
### EXPORT PLOT
################################################################################

cat("\nExporting plot...\n")

output_base <- file.path(OUTPUT_DIR, "bivariate_density_test")

# Use export_plot if available, otherwise fall back to ggsave
if (exists("export_plot")) {
  export_plot(
    plot = p,
    filename = output_base,
    formats = EXPORT_FORMATS,
    width = plot_width,
    height = plot_height,
    dpi = EXPORT_DPI,
    verbose = EXPORT_VERBOSE
  )
} else {
  # Fallback to basic ggsave
  for (fmt in EXPORT_FORMATS) {
    ggsave(
      filename = paste0(output_base, ".", fmt),
      plot = p,
      width = plot_width,
      height = plot_height,
      dpi = EXPORT_DPI,
      bg = "white"
    )
    cat(sprintf("  Saved: %s.%s\n", output_base, fmt))
  }
}

################################################################################
### DISPLAY IN R
################################################################################

cat("\n")
cat("====================================================================\n")
cat("TEST COMPLETE\n")
cat("====================================================================\n")
cat("\nOutput files in:", OUTPUT_DIR, "\n")
cat("Files:\n")
for (fmt in EXPORT_FORMATS) {
  cat(sprintf("  - bivariate_density_test.%s\n", fmt))
}
cat("\nDisplaying plot in R graphics window...\n")

# Display plot
print(p)

cat("\n")
cat("To iterate on styling:\n")
cat("  1. Edit functions/copula_contour_plots.R (plot_bivariate_density function)\n")
cat("  2. Re-run: source(\"STEP_1_Family_Selection/test_bivariate_plot.R\")\n")
cat("\n")
