############################################################################
### Quick test script for panels D2 and E only
### 
### Purpose: Rapidly regenerate panel_d2 and panel_e without running
###          the full publication figure pipeline
###
### Usage: source("STEP_2_SGPc_Sensitivity/test_panels_d2_e.R")
###
### Prerequisites: sgpc_enhanced_stats.rds must exist from prior run
###   NOTE: Panel D2 kappa annotations require kappa_w in
###   group_bucket_stability.  If missing, rebuild the cache via the
###   full pipeline (create_publication_figure.R).
############################################################################

require(data.table)
require(ggplot2)
require(scales)

# Source only the publication plot functions (no pipeline code)
source("STEP_2_SGPc_Sensitivity/sgpc_publication_plots.R")

cat("====================================================================\n")
cat("TESTING PANELS D2 AND E\n")
cat("====================================================================\n\n")

# Load cached enhanced statistics
cat("Loading cached enhanced statistics...\n")
enhanced_stats <- readRDS("STEP_2_SGPc_Sensitivity/results/sgpc_enhanced_stats.rds")
cat("  Loaded successfully.\n\n")

# Output directory
out_dir <- "STEP_2_SGPc_Sensitivity/results/visualizations"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# --- Panel D2 ---
cat("Generating Panel D2: Mean SGPc classification stability...\n")
p_d2 <- plot_group_bucket_stability(
  enhanced_stats,
  title = "Classification Accuracy/Precision: Group-Level Mean SGPc Category Agreement"
)
ggsave(file.path(out_dir, "panel_d2_group_bucket_stability.pdf"),
       p_d2,
       width = PANEL_CLASSIFICATION_PAGE_WIDTH,
       height = PANEL_CLASSIFICATION_PAGE_HEIGHT,
       device = cairo_pdf)
cat("  Saved: panel_d2_group_bucket_stability.pdf\n\n")

# --- Panel E ---
cat("Generating Panel E: Individual classification stability (K=3,5,10)...\n")
p_e <- plot_decile_stability(
  enhanced_stats,
  stratify_by = "year_span",
  n_buckets = c(3, 5, 10),
  title = "Classification Accuracy/Precision: Individual-Level SGPc Category Agreement"
)
ggsave(file.path(out_dir, "panel_e_decile_stability.pdf"),
       p_e,
       width = PANEL_CLASSIFICATION_PAGE_WIDTH,
       height = PANEL_CLASSIFICATION_PAGE_HEIGHT,
       device = cairo_pdf)
cat("  Saved: panel_e_decile_stability.pdf\n\n")

cat("COMPLETE. Check:\n")
cat("  ", file.path(out_dir, "panel_d2_group_bucket_stability.pdf"), "\n")
cat("  ", file.path(out_dir, "panel_e_decile_stability.pdf"), "\n")
