############################################################################
### STEP 2: SGPc Sensitivity Analysis - Publication Figure Master Script
###
### Purpose: Orchestrate the complete workflow to generate publication figure
###          1. Load data with school/district IDs
###          2. Compute enhanced statistics
###          3. Generate 5 core plots
###          4. Save plots in multiple formats
###          5. Assemble LaTeX grid
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)
require(ggplot2)

cat("====================================================================\n")
cat("STEP 2: CREATING PUBLICATION-GRADE SGPc SENSITIVITY FIGURE\n")
cat("====================================================================\n\n")

cat("Starting time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

############################################################################
### STEP 1: LOAD DATA
############################################################################

cat("====================================================================\n")
cat("STEP 1: LOADING DATA\n")
cat("====================================================================\n\n")

RESULTS_DIR <- "STEP_2_SGPc_Sensitivity/results"
VIZ_DIR <- file.path(RESULTS_DIR, "visualizations")

# Ensure visualization directory exists
if (!dir.exists(VIZ_DIR)) dir.create(VIZ_DIR, recursive = TRUE)

# Load SGPc variant data
dataset_files <- list.files(RESULTS_DIR, pattern = "^sgpc_all_variants_dataset_.*\\.rds$", full.names = TRUE)

if (length(dataset_files) == 0) {
  stop("No variant results found. Run sgpc_compute_all_variants.R first.")
}

cat("Loading data from:\n")
for (f in dataset_files) {
  cat(" ", f, "\n")
}
cat("\n")

# Load and combine all datasets
all_data_list <- lapply(dataset_files, readRDS)
sgpc_data <- rbindlist(all_data_list, fill = TRUE)

cat(sprintf("Combined dataset: %s observations, %d conditions\n\n",
            format(nrow(sgpc_data), big.mark = ","),
            uniqueN(sgpc_data$condition_id)))

# Check for school/district IDs
has_school <- "SCHOOL_NUMBER" %in% names(sgpc_data) && sum(!is.na(sgpc_data$SCHOOL_NUMBER)) > 0
has_district <- "DISTRICT_NUMBER" %in% names(sgpc_data) && sum(!is.na(sgpc_data$DISTRICT_NUMBER)) > 0

if (!has_school && !has_district) {
  warning("SCHOOL_NUMBER and DISTRICT_NUMBER not found or all NA.\n",
          "Panel B (group-level) will be skipped.\n",
          "To fix: Re-run Step 2.1 after updating sgpc_compute_all_variants.R\n")
  skip_panel_b <- TRUE
} else {
  skip_panel_b <- FALSE
  cat(sprintf("✓ Group identifiers found: SCHOOL_NUMBER=%s, DISTRICT_NUMBER=%s\n\n",
              has_school, has_district))
}

############################################################################
### STEP 2: COMPUTE ENHANCED STATISTICS
############################################################################

cat("====================================================================\n")
cat("STEP 2: COMPUTING ENHANCED STATISTICS\n")
cat("====================================================================\n\n")

# Load enhanced statistics computation function
source("STEP_2_SGPc_Sensitivity/sgpc_enhanced_statistics.R")

# Check if we can load cached stats or need to recompute
enhanced_stats_file <- file.path(RESULTS_DIR, "sgpc_enhanced_stats.rds")

if (file.exists(enhanced_stats_file)) {
  cat("Loading cached enhanced statistics...\n")
  enhanced_stats <- readRDS(enhanced_stats_file)
  cat("✓ Loaded from cache\n\n")
} else {
  cat("Computing enhanced statistics (this may take a few minutes)...\n")
  enhanced_stats <- compute_enhanced_statistics(sgpc_data)
  
  # Save for future use
  saveRDS(enhanced_stats, enhanced_stats_file)
  cat(sprintf("✓ Cached enhanced statistics to: %s\n\n", enhanced_stats_file))
}

############################################################################
### STEP 3: GENERATE PLOTS
############################################################################

cat("====================================================================\n")
cat("STEP 3: GENERATING PUBLICATION PLOTS\n")
cat("====================================================================\n\n")

# Load plotting functions
source("STEP_2_SGPc_Sensitivity/sgpc_publication_plots.R")

# Define plot dimensions
PLOT_DIMS <- list(
  panel_a = list(width = 8, height = 6),
  panel_b = list(width = 8, height = 6),
  panel_c = list(width = 8, height = 6),
  panel_d1 = list(width = 8, height = 6),
  panel_d2 = list(width = 8, height = 6)
)

# Generate each panel
plots <- list()

cat("Generating Panel A (Individual-level ECDF)...\n")
plots$panel_a <- plot_individual_ecdf(enhanced_stats)
save_plot_multi(
  plots$panel_a, 
  "panel_a_individual_ecdf", 
  VIZ_DIR,
  width = PLOT_DIMS$panel_a$width,
  height = PLOT_DIMS$panel_a$height
)
cat("\n")

if (!skip_panel_b) {
  cat("Generating Panel B (Group-level ECDF)...\n")
  plots$panel_b <- plot_group_ecdf(enhanced_stats)
  save_plot_multi(
    plots$panel_b,
    "panel_b_group_ecdf",
    VIZ_DIR,
    width = PLOT_DIMS$panel_b$width,
    height = PLOT_DIMS$panel_b$height
  )
  cat("\n")
} else {
  cat("Skipping Panel B (no group identifiers available)\n\n")
}

cat("Generating Panel C (Condition-level dots)...\n")
plots$panel_c <- plot_condition_dots(enhanced_stats, sgpc_data)
save_plot_multi(
  plots$panel_c,
  "panel_c_condition_dots",
  VIZ_DIR,
  width = PLOT_DIMS$panel_c$width,
  height = PLOT_DIMS$panel_c$height
)
cat("\n")

cat("Generating Panel D1 (Rank agreement)...\n")
plots$panel_d1 <- plot_rank_agreement(enhanced_stats)
save_plot_multi(
  plots$panel_d1,
  "panel_d1_rank_agreement",
  VIZ_DIR,
  width = PLOT_DIMS$panel_d1$width,
  height = PLOT_DIMS$panel_d1$height
)
cat("\n")

cat("Generating Panel D2 (Decile stability)...\n")
plots$panel_d2 <- plot_decile_stability(enhanced_stats, stratify_by = "year_span")
save_plot_multi(
  plots$panel_d2,
  "panel_d2_decile_stability",
  VIZ_DIR,
  width = PLOT_DIMS$panel_d2$width,
  height = PLOT_DIMS$panel_d2$height
)
cat("\n")

cat("✓ All individual plots generated and saved\n\n")

############################################################################
### STEP 4: ASSEMBLE GRID
############################################################################

cat("====================================================================\n")
cat("STEP 4: ASSEMBLING PUBLICATION GRID\n")
cat("====================================================================\n\n")

# Load grid assembly function
source("STEP_2_SGPc_Sensitivity/generate_sgpc_summary_grid.R")

# Define panel file names
if (skip_panel_b) {
  cat("NOTE: Using placeholder for Panel B (group analysis not available)\n\n")
  # Create a simple placeholder PDF
  pdf(file.path(VIZ_DIR, "panel_b_placeholder.pdf"), width = 8, height = 6)
  plot.new()
  text(0.5, 0.5, 
       "Panel B: Group-Level Analysis\n\n(Requires SCHOOL_NUMBER/DISTRICT_NUMBER)\n\nRe-run Step 2.1 with updated sgpc_compute_all_variants.R",
       cex = 1.5, col = "gray50")
  dev.off()
  
  panel_files <- c(
    panel_a = "panel_a_individual_ecdf.pdf",
    panel_b = "panel_b_placeholder.pdf",
    panel_c = "panel_c_condition_dots.pdf",
    panel_d1 = "panel_d1_rank_agreement.pdf",
    panel_d2 = "panel_d2_decile_stability.pdf"
  )
} else {
  panel_files <- c(
    panel_a = "panel_a_individual_ecdf.pdf",
    panel_b = "panel_b_group_ecdf.pdf",
    panel_c = "panel_c_condition_dots.pdf",
    panel_d1 = "panel_d1_rank_agreement.pdf",
    panel_d2 = "panel_d2_decile_stability.pdf"
  )
}

# Assemble grid
grid_result <- generate_sgpc_summary_grid_latex(
  plot_files = panel_files,
  output_dir = VIZ_DIR,
  layout = "2x3",
  title = "SGPc Sensitivity to Copula Choice: A Multi-Level Analysis",
  compile_pdf = TRUE,
  keep_tex = FALSE,
  export_formats = c("pdf", "svg", "png"),
  export_dpi = 300
)

############################################################################
### SUMMARY
############################################################################

cat("====================================================================\n")
cat("PUBLICATION FIGURE GENERATION COMPLETE\n")
cat("====================================================================\n\n")

cat("Output directory:", VIZ_DIR, "\n\n")

cat("Individual panels:\n")
cat("  - panel_a_individual_ecdf.{pdf,svg,png}\n")
if (!skip_panel_b) {
  cat("  - panel_b_group_ecdf.{pdf,svg,png}\n")
} else {
  cat("  - panel_b_placeholder.pdf (re-run Step 2.1 to generate real panel)\n")
}
cat("  - panel_c_condition_dots.{pdf,svg,png}\n")
cat("  - panel_d1_rank_agreement.{pdf,svg,png}\n")
cat("  - panel_d2_decile_stability.{pdf,svg,png}\n\n")

cat("Assembled grid:\n")
cat("  - sgpc_summary_grid.tex (LaTeX source)\n")
cat("  - sgpc_summary_grid.pdf (main figure)\n")
if (!is.null(grid_result$svg)) {
  cat("  - sgpc_summary_grid.svg\n")
}
if (!is.null(grid_result$png)) {
  cat("  - sgpc_summary_grid.png\n")
}
cat("\n")

cat("Enhanced statistics cached at:\n")
cat(" ", enhanced_stats_file, "\n\n")

cat("Completion time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

cat("====================================================================\n")
cat("To view the figure:\n")
cat(sprintf("  open %s\n", file.path(VIZ_DIR, "sgpc_summary_grid.pdf")))
cat("====================================================================\n\n")

# Return paths invisibly for programmatic access
invisible(list(
  individual_plots = plots,
  grid_files = grid_result,
  enhanced_stats = enhanced_stats,
  output_dir = VIZ_DIR
))
