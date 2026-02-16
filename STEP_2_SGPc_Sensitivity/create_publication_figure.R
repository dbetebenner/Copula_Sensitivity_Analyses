############################################################################
### STEP 2: SGPc Sensitivity Analysis - Publication Figure Master Script
###
### Purpose: Orchestrate the complete workflow to generate publication figure
###          1. Load data with school/district IDs
###          2. Compute enhanced statistics (8 comparison pairs)
###          3a. Generate 8 core panels (A-H)
###          3b. Run sampling sensitivity analysis (Family x Sample Size)
###          3c. Generate panels I (error decomposition) and J (N vs MAD)
###          4. Save plots in multiple formats (PDF, SVG, PNG)
###          5. Assemble LaTeX grid (5x2 layout with 10 panels)
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
# Each RDS should contain a dataset_id column (added in sgpc_compute_all_variants.R).
# For backward compatibility with RDS files that lack it, infer from filename.
all_data_list <- mapply(function(dt, f) {
  if (!"dataset_id" %in% names(dt)) {
    ds_id <- sub(".*sgpc_all_variants_(dataset_\\d+)\\.rds$", "\\1", basename(f))
    dt[, dataset_id := ds_id]
  }
  dt
}, lapply(dataset_files, readRDS), dataset_files, SIMPLIFY = FALSE)
sgpc_data <- rbindlist(all_data_list, fill = TRUE)

# Condition count must account for dataset_id to avoid collision across datasets
n_conditions <- uniqueN(sgpc_data[, paste(dataset_id, condition_id, sep = "__")])
cat(sprintf("Combined dataset: %s observations, %d conditions (across %d datasets)\n\n",
            format(nrow(sgpc_data), big.mark = ","),
            n_conditions,
            uniqueN(sgpc_data$dataset_id)))

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

# Force recomputation flag (set TRUE to invalidate cache)
# Cache MUST be regenerated when comparison pairs or statistics sections change
if (!exists("FORCE_RECOMPUTE")) FORCE_RECOMPUTE <- FALSE

if (file.exists(enhanced_stats_file) && !FORCE_RECOMPUTE) {
  # Validate cache: check that it has the expected 8 comparison pairs
  cat("Loading cached enhanced statistics...\n")
  enhanced_stats <- readRDS(enhanced_stats_file)
  
  n_pairs <- length(enhanced_stats$comparison_pairs)
  if (n_pairs < 8) {
    cat(sprintf("  Cache has %d comparison pairs (need 8). Recomputing...\n", n_pairs))
    enhanced_stats <- compute_enhanced_statistics(sgpc_data)
    saveRDS(enhanced_stats, enhanced_stats_file)
    cat(sprintf("  Cached updated statistics to: %s\n\n", enhanced_stats_file))
  } else {
    cat(sprintf("  Cache valid (%d comparison pairs)\n\n", n_pairs))
  }
} else {
  if (FORCE_RECOMPUTE && file.exists(enhanced_stats_file)) {
    cat("Invalidating stale cache (FORCE_RECOMPUTE=TRUE)...\n")
    file.remove(enhanced_stats_file)
  }
  cat("Computing enhanced statistics (8 comparison pairs, this may take a few minutes)...\n")
  enhanced_stats <- compute_enhanced_statistics(sgpc_data)
  
  # Save for future use
  saveRDS(enhanced_stats, enhanced_stats_file)
  cat(sprintf("  Cached enhanced statistics to: %s\n\n", enhanced_stats_file))
}

############################################################################
### STEP 3: GENERATE PLOTS
############################################################################

cat("====================================================================\n")
cat("STEP 3: GENERATING PUBLICATION PLOTS\n")
cat("====================================================================\n\n")

# Load plotting functions
source("STEP_2_SGPc_Sensitivity/sgpc_publication_plots.R")

# Define plot dimensions for all 8 panels
PLOT_WIDTH <- 10
PLOT_HEIGHT <- 7

# Generate each panel
plots <- list()

# --- Panel A: Individual-level ECDF ---
cat("Generating Panel A (Individual-level ECDF, 8 comparison pairs)...\n")
plots$panel_a <- plot_individual_ecdf(enhanced_stats)
save_plot_multi(plots$panel_a, "panel_a_individual_ecdf", VIZ_DIR, 
                width = PLOT_WIDTH, height = PLOT_HEIGHT)
cat("\n")

# --- Panel B: School-level ECDF (with inset) -- mean and median ---
if (!skip_panel_b) {
  for (agg_m in c("mean", "median")) {
    agg_lbl <- if (agg_m == "mean") "Mean SGPc" else "Median SGPc"
    
    cat(sprintf("Generating Panel B (School-level ECDF, %s, with sqrt(n) inset)...\n", agg_lbl))
    plots[[paste0("panel_b_", agg_m)]] <- plot_group_ecdf(enhanced_stats, add_inset = TRUE,
                                                           group_level = "school", agg_method = agg_m)
    save_plot_multi(plots[[paste0("panel_b_", agg_m)]],
                    paste0("panel_b_school_ecdf_", agg_m), VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
    cat("\n")
    
    cat(sprintf("Generating Panel B2 (District-level ECDF, %s)...\n", agg_lbl))
    plots[[paste0("panel_b2_", agg_m)]] <- plot_group_ecdf(enhanced_stats, add_inset = FALSE,
                                                            group_level = "district", agg_method = agg_m)
    save_plot_multi(plots[[paste0("panel_b2_", agg_m)]],
                    paste0("panel_b2_district_ecdf_", agg_m), VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
    cat("\n")
  }
} else {
  cat("Skipping Panel B / B2 (no group identifiers available)\n\n")
}

# --- Panel C: Condition-level MAD dots ---
cat("Generating Panel C (Condition-level MAD dots)...\n")
plots$panel_c <- plot_condition_dots(enhanced_stats, sgpc_data)
save_plot_multi(plots$panel_c, "panel_c_condition_dots", VIZ_DIR, 
                width = PLOT_WIDTH, height = PLOT_HEIGHT)
cat("\n")

# --- Panel D: Rank agreement (Spearman rho) ---
cat("Generating Panel D (Rank agreement)...\n")
plots$panel_d <- plot_rank_agreement(enhanced_stats)
save_plot_multi(plots$panel_d, "panel_d_rank_agreement", VIZ_DIR, 
                width = PLOT_WIDTH, height = PLOT_HEIGHT)
cat("\n")

# --- Panel E: Individual classification stability (K=3,5,10) ---
cat("Generating Panel E (Individual classification stability: K=3,5,10)...\n")
plots$panel_e <- plot_decile_stability(
  enhanced_stats,
  stratify_by = "year_span",
  n_buckets = c(3, 5, 10)
)
save_plot_multi(plots$panel_e, "panel_e_decile_stability", VIZ_DIR, 
                width = PANEL_CLASSIFICATION_PAGE_WIDTH,
                height = PANEL_CLASSIFICATION_PAGE_HEIGHT)
cat("\n")

# --- Panel D2: Group-level bucket stability (School + District), mean & median ---
if (!skip_panel_b) {
  for (agg_m in c("mean", "median")) {
    agg_lbl <- if (agg_m == "mean") "Mean SGPc" else "Median SGPc"
    cat(sprintf("Generating Panel D2 [%s] (Group-level bucket stability: K=3,5,10)...\n", agg_lbl))
    tryCatch({
      plots[[paste0("panel_d2_", agg_m)]] <- plot_group_bucket_stability(
        enhanced_stats, agg_method = agg_m)
      save_plot_multi(plots[[paste0("panel_d2_", agg_m)]],
                      paste0("panel_d2_group_bucket_stability_", agg_m), VIZ_DIR,
                      width = PANEL_CLASSIFICATION_PAGE_WIDTH,
                      height = PANEL_CLASSIFICATION_PAGE_HEIGHT)
      cat("\n")
    }, error = function(e) {
      cat(sprintf("  WARNING: Panel D2 [%s] failed: %s\n\n", agg_lbl, e$message))
    })
  }
} else {
  cat("Skipping Panel D2 (requires group identifiers)\n\n")
}

# --- Panel F: Prior achievement quartile sensitivity ---
cat("Generating Panel F (Prior achievement quartile)...\n")
tryCatch({
  plots$panel_f <- plot_prior_quartile_sensitivity(enhanced_stats)
  save_plot_multi(plots$panel_f, "panel_f_prior_quartile", VIZ_DIR, 
                  width = PLOT_WIDTH, height = PLOT_HEIGHT)
  cat("\n")
}, error = function(e) {
  cat(sprintf("  WARNING: Panel F failed: %s\n\n", e$message))
})

# --- Panel G: Cross-dataset comparison ---
cat("Generating Panel G (Cross-dataset comparison)...\n")
tryCatch({
  plots$panel_g <- plot_cross_dataset_comparison(enhanced_stats)
  save_plot_multi(plots$panel_g, "panel_g_cross_dataset", VIZ_DIR, 
                  width = PLOT_WIDTH, height = PLOT_HEIGHT)
  cat("\n")
}, error = function(e) {
  cat(sprintf("  WARNING: Panel G failed: %s\n\n", e$message))
})

# --- Panel H: Multi-level aggregation hierarchy -- mean and median ---
if (!skip_panel_b) {
  for (agg_m in c("mean", "median")) {
    agg_lbl <- if (agg_m == "mean") "Mean SGPc" else "Median SGPc"
    cat(sprintf("Generating Panel H (Multi-level aggregation, %s: Individual -> School -> District)...\n", agg_lbl))
    tryCatch({
      plots[[paste0("panel_h_", agg_m)]] <- plot_multilevel_aggregation(enhanced_stats, agg_method = agg_m)
      save_plot_multi(plots[[paste0("panel_h_", agg_m)]],
                      paste0("panel_h_multilevel_aggregation_", agg_m), VIZ_DIR,
                      width = PLOT_WIDTH, height = PLOT_HEIGHT)
      cat("\n")
    }, error = function(e) {
      cat(sprintf("  WARNING: Panel H (%s) failed: %s\n\n", agg_lbl, e$message))
    })
  }
} else {
  cat("Skipping Panel H (requires group identifiers for multi-level)\n\n")
}

# --- Panel I: Error Decomposition (Comparison Pair vs Sampling) ---
cat("====================================================================\n")
cat("STEP 3b: SAMPLING SENSITIVITY ANALYSIS (Comparison x Sample Size)\n")
cat("====================================================================\n\n")

# Check for cached sampling sensitivity results
sampling_results_file <- file.path(RESULTS_DIR, "sgpc_sampling_sensitivity.rds")

if (file.exists(sampling_results_file) && !FORCE_RECOMPUTE) {
  cat("Loading cached sampling sensitivity results...\n")
  sampling_results <- readRDS(sampling_results_file)
  cat(sprintf("  Loaded (%d replicate rows, %d comparison pairs, %d sample sizes)\n\n",
              nrow(sampling_results$replicate_results),
              length(sampling_results$metadata$comparison_pairs),
              length(sampling_results$metadata$sample_sizes)))
} else {
  cat("Computing sampling sensitivity (bootstrap of existing differences)...\n")
  sampling_results <- compute_sampling_sensitivity(
    sgpc_data,
    sample_sizes = c(500L, 1000L, 2000L, 4000L),
    B = 50L,
    max_conditions = 5L,
    seed = 42L
  )
  
  # Cache the results
  saveRDS(sampling_results, sampling_results_file)
  cat(sprintf("  Cached sampling sensitivity to: %s\n\n", sampling_results_file))
}

cat("Generating Panel I1 & I2 (Error Decomposition: Comparison vs Sampling)...\n")
tryCatch({
  panel_i_plots <- plot_error_decomposition(sampling_results)
  
  if (is.list(panel_i_plots) && !inherits(panel_i_plots, "gg")) {
    # Save each sub-panel as its own standalone figure
    plots$panel_i1 <- panel_i_plots$ribbon
    save_plot_multi(plots$panel_i1, "panel_i1_sensitivity_ribbon", VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
    
    plots$panel_i2 <- panel_i_plots$share
    save_plot_multi(plots$panel_i2, "panel_i2_variance_decomposition", VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
    
    # Also keep composite for backwards compatibility
    save_plot_multi_panel(panel_i_plots, "panel_i_error_decomposition", VIZ_DIR,
                          width = 14, height = 7, ncol = 2, widths = c(1.2, 1))
  } else {
    # Single ggplot fallback
    plots$panel_i1 <- panel_i_plots
    save_plot_multi(plots$panel_i1, "panel_i1_sensitivity_ribbon", VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
  }
  cat("\n")
}, error = function(e) {
  cat(sprintf("  WARNING: Panel I1/I2 failed: %s\n\n", e$message))
})

# --- Panel J: Condition N vs MAD scatter ---
cat("Generating Panel J (Condition N vs MAD scatter)...\n")
tryCatch({
  plots$panel_j <- plot_condition_n_vs_mad(enhanced_stats)
  save_plot_multi(plots$panel_j, "panel_j_condition_n_vs_mad", VIZ_DIR, 
                  width = PLOT_WIDTH, height = PLOT_HEIGHT)
  cat("\n")
}, error = function(e) {
  cat(sprintf("  WARNING: Panel J failed: %s\n\n", e$message))
})

# --- Panel K: Group-Level Rank Stability (School + District) ---
if (!skip_panel_b) {
  cat("Generating Panel K (Group-Level Rank Stability)...\n")
  tryCatch({
    plots$panel_k <- plot_group_rank_stability(enhanced_stats)
    save_plot_multi(plots$panel_k, "panel_k_group_rank_stability", VIZ_DIR, 
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
    cat("\n")
  }, error = function(e) {
    cat(sprintf("  WARNING: Panel K failed: %s\n\n", e$message))
  })
} else {
  cat("Skipping Panel K (requires group identifiers)\n\n")
}

############################################################################
### BLAND-ALTMAN PLOTS
############################################################################

cat("====================================================================\n")
cat("STEP 3c: BLAND-ALTMAN AGREEMENT PLOTS\n")
cat("====================================================================\n\n")

require(wesanderson)
require(hexbin)

zissou1_colors <- colorRampPalette(wes_palette("Zissou1"))(50)

# Helper to build a Bland-Altman plot
make_bland_altman <- function(dt, var1, var2, title_label) {
  ba_dt <- dt[!is.na(get(var1)) & !is.na(get(var2)), .(
    mean_val = (get(var1) + get(var2)) / 2,
    diff_val = get(var1) - get(var2)
  )]
  if (nrow(ba_dt) == 0) return(NULL)
  
  m <- mean(ba_dt$diff_val, na.rm = TRUE)
  s <- sd(ba_dt$diff_val, na.rm = TRUE)
  
  ggplot(ba_dt, aes(x = mean_val, y = diff_val)) +
    geom_hex(bins = 50) +
    geom_hline(yintercept = 0, color = "#F21A00", linetype = "dashed", linewidth = 1) +
    geom_hline(yintercept = m, color = "blue", linetype = "solid", linewidth = 1) +
    geom_hline(yintercept = m + 1.96 * s, color = "blue", linetype = "dotted", linewidth = 0.8) +
    geom_hline(yintercept = m - 1.96 * s, color = "blue", linetype = "dotted", linewidth = 0.8) +
    scale_fill_gradientn(colors = zissou1_colors, trans = "log10", name = "Count") +
    labs(
      title = sprintf("Bland-Altman Plot: %s", title_label),
      subtitle = sprintf("Mean diff = %.2f | SD = %.2f", m, s),
      x = "Mean of Two Methods",
      y = sprintf("Difference (%s)", title_label)
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold"),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )
}

# Bland-Altman: Empirical vs Best-Fit
if ("sgpc_best" %in% names(sgpc_data)) {
  cat("Generating Bland-Altman: Empirical vs Best-Fit Parametric...\n")
  plots$ba_emp_best <- make_bland_altman(sgpc_data, "sgpc_emp", "sgpc_best",
                                          "Empirical vs Best-Fit Parametric")
  if (!is.null(plots$ba_emp_best)) {
    save_plot_multi(plots$ba_emp_best, "bland_altman_emp_vs_best", VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
  }
}

# Bland-Altman: Empirical vs Gaussian
if ("sgpc_gaussian" %in% names(sgpc_data)) {
  cat("Generating Bland-Altman: Empirical vs Gaussian...\n")
  plots$ba_emp_gaussian <- make_bland_altman(sgpc_data, "sgpc_emp", "sgpc_gaussian",
                                              "Empirical vs Gaussian")
  if (!is.null(plots$ba_emp_gaussian)) {
    save_plot_multi(plots$ba_emp_gaussian, "bland_altman_emp_vs_gaussian", VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
  }
}

# Bland-Altman: Empirical vs Gumbel
if ("sgpc_gumbel" %in% names(sgpc_data)) {
  cat("Generating Bland-Altman: Empirical vs Gumbel...\n")
  plots$ba_emp_gumbel <- make_bland_altman(sgpc_data, "sgpc_emp", "sgpc_gumbel",
                                            "Empirical vs Gumbel")
  if (!is.null(plots$ba_emp_gumbel)) {
    save_plot_multi(plots$ba_emp_gumbel, "bland_altman_emp_vs_gumbel", VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
  }
}

# Bland-Altman: Empirical vs Traditional SGP
if ("sgp_traditional" %in% names(sgpc_data)) {
  cat("Generating Bland-Altman: Empirical SGPc vs Traditional SGP...\n")
  plots$ba_emp_trad <- make_bland_altman(sgpc_data, "sgpc_emp", "sgp_traditional",
                                          "Empirical SGPc vs Traditional SGP")
  if (!is.null(plots$ba_emp_trad)) {
    save_plot_multi(plots$ba_emp_trad, "bland_altman_emp_vs_traditional", VIZ_DIR,
                    width = PLOT_WIDTH, height = PLOT_HEIGHT)
  }
}

cat("\n")

############################################################################
### GAUSSIAN MISFIT DIAGNOSTICS (F-DeepDive composite + standalone)
############################################################################

cat("====================================================================\n")
cat("STEP 3d: GAUSSIAN MISFIT DIAGNOSTICS\n")
cat("====================================================================\n\n")

diag_plots <- list()

# --- Diag F-A: Focused Quartile Violins ---
cat("Generating Diag F-A (Focused Quartile Violins)...\n")
tryCatch({
  diag_plots$diag_fa <- plot_diag_quartile_focused(enhanced_stats)
  save_plot_multi(diag_plots$diag_fa, "diag_fa_quartile_focused", VIZ_DIR,
                  width = PLOT_WIDTH, height = PLOT_HEIGHT)
}, error = function(e) {
  cat(sprintf("  WARNING: Diag F-A failed: %s\n", e$message))
})

# --- Diag F-B: Quartile Summary Lines ---
cat("Generating Diag F-B (Quartile Summary Lines)...\n")
tryCatch({
  diag_plots$diag_fb <- plot_diag_quartile_summary(enhanced_stats)
  save_plot_multi(diag_plots$diag_fb, "diag_fb_quartile_summary", VIZ_DIR,
                  width = PLOT_WIDTH, height = PLOT_HEIGHT)
}, error = function(e) {
  cat(sprintf("  WARNING: Diag F-B failed: %s\n", e$message))
})

# --- Diag L: Delta-vs-Prior Miscalibration ---
cat("Generating Diag L (Delta-vs-Prior Miscalibration)...\n")
tryCatch({
  diag_plots$diag_l <- plot_diag_delta_vs_prior(sgpc_data)
  save_plot_multi(diag_plots$diag_l, "diag_l_delta_vs_prior", VIZ_DIR,
                  width = 12, height = 10)
}, error = function(e) {
  cat(sprintf("  WARNING: Diag L failed: %s\n", e$message))
})

# --- Diag M: Tail-Focused Rank Stability ---
cat("Generating Diag M (Tail-Focused Rank Stability)...\n")
tryCatch({
  diag_plots$diag_m <- plot_diag_tail_rank_stability(sgpc_data)
  save_plot_multi(diag_plots$diag_m, "diag_m_tail_rank_stability", VIZ_DIR,
                  width = 14, height = 7)
}, error = function(e) {
  cat(sprintf("  WARNING: Diag M failed: %s\n", e$message))
})

# --- Diag N: Mean-vs-Median Group Stability ---
if (!skip_panel_b) {
  cat("Generating Diag N (Mean-vs-Median Group Stability)...\n")
  tryCatch({
    diag_plots$diag_n <- plot_diag_mean_vs_median_stability(sgpc_data)
    save_plot_multi(diag_plots$diag_n, "diag_n_mean_vs_median_stability", VIZ_DIR,
                    width = 12, height = 7)
  }, error = function(e) {
    cat(sprintf("  WARNING: Diag N failed: %s\n", e$message))
  })
} else {
  cat("Skipping Diag N (requires group identifiers)\n")
}

# --- Diag O: Composition-Bias Pathway ---
if (!skip_panel_b) {
  cat("Generating Diag O (Composition-Bias Pathway)...\n")
  tryCatch({
    diag_plots$diag_o <- plot_diag_composition_bias(sgpc_data)
    save_plot_multi(diag_plots$diag_o, "diag_o_composition_bias", VIZ_DIR,
                    width = 12, height = 10)
  }, error = function(e) {
    cat(sprintf("  WARNING: Diag O failed: %s\n", e$message))
  })
} else {
  cat("Skipping Diag O (requires SCHOOL_NUMBER)\n")
}

# --- Assemble F-DeepDive Composite (2x2 grid) ---
diag_composite_panels <- list()
if (!is.null(diag_plots$diag_fa)) diag_composite_panels$fa <- diag_plots$diag_fa
if (!is.null(diag_plots$diag_fb)) diag_composite_panels$fb <- diag_plots$diag_fb
if (!is.null(diag_plots$diag_l))  diag_composite_panels$l  <- diag_plots$diag_l
if (!is.null(diag_plots$diag_m))  diag_composite_panels$m  <- diag_plots$diag_m

if (length(diag_composite_panels) >= 2) {
  cat("Assembling Gaussian Misfit Diagnostic Composite Grid...\n")
  n_diag <- length(diag_composite_panels)
  diag_ncol <- min(2, n_diag)
  diag_height <- if (n_diag > 2) 14 else 7
  tryCatch({
    save_plot_multi_panel(
      diag_composite_panels,
      "gaussian_misfit_diagnostic_grid", VIZ_DIR,
      width = 16, height = diag_height,
      ncol = diag_ncol, widths = rep(1, diag_ncol)
    )
  }, error = function(e) {
    cat(sprintf("  WARNING: Diagnostic composite failed: %s\n", e$message))
  })
}

cat("\nGaussian misfit diagnostics complete.\n\n")

cat("Panel generation complete.\n\n")

############################################################################
### STEP 4: ASSEMBLE GRID
############################################################################

cat("====================================================================\n")
cat("STEP 4: ASSEMBLING PUBLICATION GRID\n")
cat("====================================================================\n\n")

# Load grid assembly function
source("STEP_2_SGPc_Sensitivity/generate_sgpc_summary_grid.R")

# Build panel file list from successfully generated panels
panel_files <- c()

# Core panels (always expected)
panel_files["panel_a"] <- "panel_a_individual_ecdf.pdf"

if (!skip_panel_b) {
  panel_files["panel_b_mean"]    <- "panel_b_school_ecdf_mean.pdf"
  panel_files["panel_b_median"]  <- "panel_b_school_ecdf_median.pdf"
  panel_files["panel_b2_mean"]   <- "panel_b2_district_ecdf_mean.pdf"
  panel_files["panel_b2_median"] <- "panel_b2_district_ecdf_median.pdf"
} else {
  # Create placeholder
  pdf(file.path(VIZ_DIR, "panel_b_placeholder.pdf"), width = 10, height = 7)
  plot.new()
  text(0.5, 0.5, 
       "Panel B: School-Level Analysis\n\n(Requires SCHOOL_NUMBER/DISTRICT_NUMBER)\n\nRe-run Step 2.1 with updated sgpc_compute_all_variants.R",
       cex = 1.5, col = "gray50")
  dev.off()
  panel_files["panel_b"] <- "panel_b_placeholder.pdf"
}

panel_files["panel_c"] <- "panel_c_condition_dots.pdf"
panel_files["panel_d"] <- "panel_d_rank_agreement.pdf"
panel_files["panel_e"] <- "panel_e_decile_stability.pdf"

# New panels (may not exist if they failed)
if (!is.null(plots$panel_d2_mean)) {
  panel_files["panel_d2_mean"] <- "panel_d2_group_bucket_stability_mean.pdf"
}
if (!is.null(plots$panel_d2_median)) {
  panel_files["panel_d2_median"] <- "panel_d2_group_bucket_stability_median.pdf"
}
if (!is.null(plots$panel_f)) {
  panel_files["panel_f"] <- "panel_f_prior_quartile.pdf"
}
if (!is.null(plots$panel_g)) {
  panel_files["panel_g"] <- "panel_g_cross_dataset.pdf"
}
if (!is.null(plots$panel_h_mean)) {
  panel_files["panel_h_mean"]   <- "panel_h_multilevel_aggregation_mean.pdf"
}
if (!is.null(plots$panel_h_median)) {
  panel_files["panel_h_median"] <- "panel_h_multilevel_aggregation_median.pdf"
}
if (!is.null(plots$panel_k)) {
  panel_files["panel_k"] <- "panel_k_group_rank_stability.pdf"
}
if (!is.null(plots$panel_i1)) {
  panel_files["panel_i1"] <- "panel_i1_sensitivity_ribbon.pdf"
}
if (!is.null(plots$panel_i2)) {
  panel_files["panel_i2"] <- "panel_i2_variance_decomposition.pdf"
}
if (!is.null(plots$panel_j)) {
  panel_files["panel_j"] <- "panel_j_condition_n_vs_mad.pdf"
}

# Determine layout based on number of panels
n_panels <- length(panel_files)
if (n_panels >= 12) {
  layout_choice <- "6x2"
} else if (n_panels >= 10) {
  layout_choice <- "5x2"
} else if (n_panels >= 8) {
  layout_choice <- "4x2"
} else if (n_panels >= 6) {
  layout_choice <- "3x2"
} else {
  layout_choice <- "2x3"
}

cat(sprintf("Assembling %d panels in %s layout...\n", n_panels, layout_choice))

# Assemble grid
grid_result <- generate_sgpc_summary_grid_latex(
  plot_files = panel_files,
  output_dir = VIZ_DIR,
  layout = layout_choice,
  title = "SGPc Sensitivity to Copula Choice: Family Selection and Sampling Error",
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

cat("Individual panels generated:\n")
panel_labels <- c(
  panel_a  = "A:  Individual-level ECDF (10 comparisons)",
  panel_b  = "B:  School-level ECDF (with sqrt(n) inset)",
  panel_b2 = "B2: District-level ECDF",
  panel_c  = "C:  Condition-level MAD dots",
  panel_d  = "D:  Individual-level Rank Agreement",
  panel_e  = "E:  Decile Stability",
  panel_d2 = "D2: Group-Level Bucket Stability (School & District, K=3,5,10)",
  panel_f  = "F:  Prior Achievement Quartile Sensitivity",
  panel_g  = "G:  Cross-Dataset Comparison",
  panel_h  = "H:  Multi-Level Aggregation (Individual->School->District)",
  panel_k  = "K:  Group-Level Rank Stability (School & District)",
  panel_i  = "I:  Error Decomposition (Family vs Sampling)",
  panel_j  = "J:  Condition N vs MAD (Observed Sample Size Effect)"
)
for (pn in names(panel_files)) {
  label <- if (pn %in% names(panel_labels)) panel_labels[pn] else pn
  cat(sprintf("  [OK] %s\n", label))
}
cat("\n")

# Report diagnostics
diag_labels <- c(
  diag_fa = "F-A: Focused Quartile Violins (Gaussian misfit)",
  diag_fb = "F-B: Quartile Summary Lines (median / Q90)",
  diag_l  = "L:   Delta-vs-Prior Miscalibration (signed, GAM smooth)",
  diag_m  = "M:   Tail-Focused Rank Stability (Bottom 10/Mid 80/Top 10)",
  diag_n  = "N:   Mean-vs-Median Group Stability",
  diag_o  = "O:   Composition-Bias Pathway (school mean_prior vs mean_delta)"
)
if (length(diag_plots) > 0) {
  cat("Gaussian misfit diagnostics generated:\n")
  for (dn in names(diag_plots)) {
    if (!is.null(diag_plots[[dn]])) {
      label <- if (dn %in% names(diag_labels)) diag_labels[dn] else dn
      cat(sprintf("  [OK] %s\n", label))
    }
  }
  cat("\n")
}

cat("Assembled grid:\n")
cat(sprintf("  Layout: %s (%d panels)\n", layout_choice, n_panels))
cat("  - sgpc_summary_grid.tex (LaTeX source)\n")
cat("  - sgpc_summary_grid.pdf (main figure)\n")
if (!is.null(grid_result$svg)) cat("  - sgpc_summary_grid.svg\n")
if (!is.null(grid_result$png)) cat("  - sgpc_summary_grid.png\n")
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
  sampling_results = if (exists("sampling_results")) sampling_results else NULL,
  output_dir = VIZ_DIR
))
