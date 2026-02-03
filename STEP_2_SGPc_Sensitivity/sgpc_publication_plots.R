############################################################################
### STEP 2: SGPc Sensitivity Analysis - Publication-Grade Plotting Functions
###
### Purpose: Create 5 core plots for publication figure
###          Panel A: Individual-level ECDF
###          Panel B: Group-level ECDF
###          Panel C: Condition-level dots (MAD by strata)
###          Panel D1: Rank agreement (Spearman ρ)
###          Panel D2: Decile stability (classification)
###
### Author: dataimago
### Date: January 2026
############################################################################

require(ggplot2)
require(data.table)
require(scales)

# Load wesanderson for color palettes (consistent with STEP_1)
if (!requireNamespace("wesanderson", quietly = TRUE)) {
  stop("Package 'wesanderson' required but not installed. Install with: install.packages('wesanderson')")
}
require(wesanderson)

# Define consistent color palette for 5 comparison pairs
# Using Wes Anderson "Zissou1" palette to match STEP_1 aesthetics
COMPARISON_COLORS <- setNames(
  wes_palette("Zissou1", 5, type = "continuous"),
  c("Emp-Best", "Emp-Canonical", "Best-Canonical", "Emp-Gaussian", "Emp-Comonotonic")
)

# Consistent theme for all plots
theme_publication <- function(base_size = 10) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = base_size + 4, hjust = 0),
      plot.subtitle = element_text(size = base_size + 1, color = "gray30"),
      axis.title = element_text(face = "bold", size = base_size + 1),
      axis.text = element_text(size = base_size),
      legend.title = element_text(face = "bold", size = base_size),
      legend.text = element_text(size = base_size - 1),
      legend.position = "right",
      panel.grid.minor = element_blank(),
      panel.border = element_rect(fill = NA, color = "gray80"),
      strip.text = element_text(face = "bold", size = base_size),
      strip.background = element_rect(fill = "gray95", color = "gray80")
    )
}

############################################################################
### PANEL A: Individual-Level ECDF
############################################################################

#' Plot individual-level ECDF of absolute SGPc differences
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include (default: all 5)
#' @param reference_lines Numeric vector of x-values for vertical reference lines (default: c(5, 10))
#' @param title Plot title
#' @return ggplot object
plot_individual_ecdf <- function(
  enhanced_stats,
  comparisons = c("Emp-Best", "Emp-Canonical", "Best-Canonical", "Emp-Gaussian", "Emp-Comonotonic"),
  reference_lines = c(5, 10),
  title = "Individual-Level Sensitivity: How Much Do SGPc Values Differ?"
) {
  
  # Extract ECDF data
  ecdf_data <- enhanced_stats$individual_stats$all_ecdf_data
  ecdf_data <- ecdf_data[comparison %in% comparisons]
  
  # Calculate annotations for reference lines
  annotations <- lapply(comparisons, function(comp) {
    comp_data <- ecdf_data[comparison == comp]
    lapply(reference_lines, function(ref) {
      pct <- mean(comp_data$delta <= ref, na.rm = TRUE)
      data.table(
        comparison = comp,
        x = ref,
        y = pct,
        label = sprintf("%.0f%%", pct * 100)
      )
    })
  })
  annotation_data <- rbindlist(lapply(annotations, rbindlist))
  
  # Create plot
  p <- ggplot(ecdf_data, aes(x = delta, y = cumulative_pct, color = comparison)) +
    geom_line(linewidth = 1.2) +
    geom_vline(xintercept = reference_lines, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_point(data = annotation_data, aes(x = x, y = y), size = 2, shape = 21, fill = "white") +
    geom_text(data = annotation_data, aes(x = x, y = y, label = label), 
              hjust = -0.3, vjust = -0.5, size = 3, fontface = "bold", show.legend = FALSE) +
    scale_color_manual(values = COMPARISON_COLORS, name = "Comparison") +
    scale_x_continuous(
      name = "Absolute Difference (|Δ| in percentile points)",
      breaks = seq(0, 50, 5),
      limits = c(0, 50)
    ) +
    scale_y_continuous(
      name = "Cumulative % of Students",
      labels = percent_format(accuracy = 1),
      breaks = seq(0, 1, 0.1)
    ) +
    labs(
      title = title,
      subtitle = "Each curve shows the distribution of individual student differences\nVertical lines mark policy-relevant thresholds (5 and 10 percentile points)",
      caption = sprintf("n = %s observations across %d conditions", 
                       format(nrow(ecdf_data[comparison == comparisons[1]]), big.mark = ","),
                       uniqueN(enhanced_stats$rank_agreement$condition_id))
    ) +
    theme_publication() +
    theme(legend.position = c(0.80, 0.35))
  
  return(p)
}

############################################################################
### PANEL B: Group-Level ECDF
############################################################################

#' Plot group-level ECDF of absolute SGPc differences (school/district means)
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param reference_lines Numeric vector of x-values for vertical reference lines
#' @param add_inset Logical, whether to add scatter plot inset showing |Δ_g| vs n_g
#' @param title Plot title
#' @return ggplot object
plot_group_ecdf <- function(
  enhanced_stats,
  comparisons = c("Emp-Best", "Emp-Canonical", "Best-Canonical", "Emp-Gaussian", "Emp-Comonotonic"),
  reference_lines = c(5, 10),
  add_inset = FALSE,
  title = "Group-Level Aggregation: Differences Shrink Dramatically"
) {
  
  if (is.null(enhanced_stats$group_stats)) {
    stop("Group statistics not available. Ensure SCHOOL_NUMBER/DISTRICT_NUMBER are in data.")
  }
  
  # Extract group ECDF data
  ecdf_data <- enhanced_stats$group_stats$all_group_ecdf_data
  ecdf_data <- ecdf_data[comparison %in% comparisons]
  
  # Calculate annotations for reference lines
  annotations <- lapply(comparisons, function(comp) {
    comp_data <- ecdf_data[comparison == comp]
    lapply(reference_lines, function(ref) {
      pct <- mean(comp_data$delta_group <= ref, na.rm = TRUE)
      data.table(
        comparison = comp,
        x = ref,
        y = pct,
        label = sprintf("%.0f%%", pct * 100)
      )
    })
  })
  annotation_data <- rbindlist(lapply(annotations, rbindlist))
  
  # Get individual-level median for comparison annotation
  ind_medians <- sapply(comparisons, function(comp) {
    enhanced_stats$individual_stats$by_comparison[[comp]]$median
  })
  
  grp_medians <- sapply(comparisons, function(comp) {
    enhanced_stats$group_stats$by_comparison[[comp]]$median_group_delta
  })
  
  comparison_text <- sprintf(
    "Individual median Δ: %.1f–%.1f\nGroup median Δ: %.1f–%.1f (%.0f%% reduction)",
    min(ind_medians), max(ind_medians),
    min(grp_medians), max(grp_medians),
    (1 - mean(grp_medians) / mean(ind_medians)) * 100
  )
  
  # Create main plot
  p <- ggplot(ecdf_data, aes(x = delta_group, y = cumulative_pct, color = comparison)) +
    geom_line(linewidth = 1.2) +
    geom_vline(xintercept = reference_lines, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_point(data = annotation_data, aes(x = x, y = y), size = 2, shape = 21, fill = "white") +
    geom_text(data = annotation_data, aes(x = x, y = y, label = label), 
              hjust = -0.3, vjust = -0.5, size = 3, fontface = "bold", show.legend = FALSE) +
    scale_color_manual(values = COMPARISON_COLORS, name = "Comparison") +
    scale_x_continuous(
      name = "Absolute Group-Level Difference (|Δ_g| in percentile points)",
      breaks = seq(0, 50, 5),
      limits = c(0, 50)
    ) +
    scale_y_continuous(
      name = "Cumulative % of Groups",
      labels = percent_format(accuracy = 1),
      breaks = seq(0, 1, 0.1)
    ) +
    labs(
      title = title,
      subtitle = sprintf("Aggregating students by school dramatically reduces sensitivity\n%s",
                        comparison_text),
      caption = sprintf("Groups = schools with ≥10 students | Total groups: ~%s",
                       format(enhanced_stats$group_stats$by_comparison[[1]]$n_groups, big.mark = ","))
    ) +
    theme_publication() +
    theme(legend.position = c(0.80, 0.35))
  
  return(p)
}

############################################################################
### PANEL C: Condition-Level Dots (MAD by Strata)
############################################################################

#' Plot condition-level MAD as dots with faceting by year_span and content_area
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param sgpc_data Original data for computing condition-level MAD
#' @param comparisons Character vector of comparison names to include
#' @param title Plot title
#' @return ggplot object
plot_condition_dots <- function(
  enhanced_stats,
  sgpc_data,
  comparisons = c("Emp-Best", "Emp-Canonical", "Best-Canonical", "Emp-Gaussian", "Emp-Comonotonic"),
  title = "Condition-Level Replication: 182 Independent Tests"
) {
  
  # Compute MAD for each condition and comparison
  comparison_pairs <- enhanced_stats$comparison_pairs
  
  mad_by_condition_list <- list()
  
  for (comp_name in comparisons) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    mad_data <- sgpc_data[, .(
      mad = mean(abs(get(var1) - get(var2)), na.rm = TRUE),
      n = sum(!is.na(get(var1)) & !is.na(get(var2)))
    ), by = .(condition_id, year_span, content_area)]
    
    mad_data[, comparison := comp_name]
    mad_by_condition_list[[comp_name]] <- mad_data
  }
  
  mad_by_condition <- rbindlist(mad_by_condition_list)
  
  # Compute summary stats for overlay
  summary_stats <- mad_by_condition[, .(
    median_mad = median(mad, na.rm = TRUE),
    q25 = quantile(mad, 0.25, na.rm = TRUE),
    q75 = quantile(mad, 0.75, na.rm = TRUE)
  ), by = .(comparison, year_span, content_area)]
  
  # Create plot
  p <- ggplot(mad_by_condition, aes(x = comparison, y = mad, color = comparison)) +
    geom_jitter(width = 0.2, height = 0, alpha = 0.4, size = 1.5) +
    geom_point(data = summary_stats, aes(y = median_mad), size = 3, shape = 18) +
    geom_errorbar(data = summary_stats, 
                  aes(y = median_mad, ymin = q25, ymax = q75),
                  width = 0.3, linewidth = 1) +
    facet_grid(content_area ~ year_span, 
               labeller = labeller(year_span = function(x) paste(x, "year"),
                                  content_area = function(x) x)) +
    scale_color_manual(values = COMPARISON_COLORS, name = "Comparison") +
    scale_y_continuous(
      name = "Mean Absolute Difference (MAD, percentile points)",
      breaks = seq(0, 30, 5)
    ) +
    labs(
      title = title,
      subtitle = "Each dot = one condition's MAD | Diamond = median | Error bars = IQR\nShows full replication distribution, not just cell means",
      caption = sprintf("n = %d conditions across 4 year spans × %d content areas",
                       uniqueN(mad_by_condition$condition_id),
                       uniqueN(mad_by_condition$content_area))
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      legend.position = "bottom",
      panel.spacing = unit(0.5, "lines")
    ) +
    guides(color = guide_legend(nrow = 2, override.aes = list(alpha = 1, size = 3)))
  
  return(p)
}

############################################################################
### PANEL D1: Rank Agreement (Spearman ρ)
############################################################################

#' Plot distribution of Spearman ρ across conditions
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param title Plot title
#' @return ggplot object
plot_rank_agreement <- function(
  enhanced_stats,
  comparisons = c("Emp-Best", "Emp-Canonical", "Best-Canonical", "Emp-Gaussian", "Emp-Comonotonic"),
  title = "Rank Stability: Spearman Correlations"
) {
  
  # Extract rank agreement data
  rank_data <- enhanced_stats$rank_agreement
  rank_data <- rank_data[comparison %in% comparisons]
  
  # Compute summary stats
  summary_stats <- rank_data[, .(
    median_rho = median(rho, na.rm = TRUE),
    q25 = quantile(rho, 0.25, na.rm = TRUE),
    q75 = quantile(rho, 0.75, na.rm = TRUE),
    min_rho = min(rho, na.rm = TRUE)
  ), by = .(comparison, year_span, content_area)]
  
  # Create plot
  p <- ggplot(rank_data, aes(x = comparison, y = rho, color = comparison)) +
    geom_hline(yintercept = 1.0, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_jitter(width = 0.2, height = 0, alpha = 0.4, size = 1.5) +
    geom_point(data = summary_stats, aes(y = median_rho), size = 3, shape = 18) +
    geom_errorbar(data = summary_stats,
                  aes(y = median_rho, ymin = q25, ymax = q75),
                  width = 0.3, linewidth = 1) +
    facet_grid(content_area ~ year_span,
               labeller = labeller(year_span = function(x) paste(x, "year"),
                                  content_area = function(x) x)) +
    scale_color_manual(values = COMPARISON_COLORS, name = "Comparison") +
    scale_y_continuous(
      name = "Spearman ρ (rank correlation)",
      limits = c(0.95, 1.0),
      breaks = seq(0.95, 1.0, 0.01)
    ) +
    labs(
      title = title,
      subtitle = "Each dot = one condition | Diamond = median | Dashed line = perfect agreement (ρ=1)\nHigh correlations indicate rank orderings are nearly identical",
      caption = sprintf("n = %d conditions | All medians ≥ %.3f",
                       uniqueN(rank_data$condition_id),
                       min(summary_stats$median_rho))
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      legend.position = "bottom",
      panel.spacing = unit(0.5, "lines")
    ) +
    guides(color = guide_legend(nrow = 2, override.aes = list(alpha = 1, size = 3)))
  
  return(p)
}

############################################################################
### PANEL D2: Decile Stability (Classification)
############################################################################

#' Plot decile misclassification rates as stacked bars
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param stratify_by Either "year_span" or "content_area" for faceting
#' @param title Plot title
#' @return ggplot object
plot_decile_stability <- function(
  enhanced_stats,
  comparisons = c("Emp-Best", "Emp-Canonical", "Best-Canonical", "Emp-Gaussian", "Emp-Comonotonic"),
  stratify_by = "year_span",
  title = "Classification Stability: Decile Agreement"
) {
  
  # Extract decile misclassification data
  decile_data <- enhanced_stats$decile_misclass
  decile_data <- decile_data[comparison %in% comparisons]
  
  # Check for classification issues and prepare warning note
  classification_note <- ""
  if (!is.null(enhanced_stats$classification_issues)) {
    issue_vars <- names(enhanced_stats$classification_issues)
    if (length(issue_vars) > 0) {
      # Create concise note for caption
      issue_summary <- sapply(issue_vars, function(v) {
        sprintf("%s (%.1f%%)", gsub("sgpc_", "", v), 
                enhanced_stats$classification_issues[[v]]$pct_failed)
      })
      classification_note <- paste0(
        "\nNote: Classification unavailable for some observations due to low variance: ",
        paste(issue_summary, collapse = ", ")
      )
    }
  }
  
  # Filter to relevant strata
  if (stratify_by == "year_span") {
    decile_data <- decile_data[grepl("^(Overall|Year_)", stratum)]
    decile_data[, facet_var := ifelse(stratum == "Overall", "All", gsub("Year_", "", stratum))]
    facet_label <- "Year Span"
  } else {
    decile_data <- decile_data[stratum %in% c("Overall", "MATHEMATICS", "READING")]
    decile_data[, facet_var := stratum]
    facet_label <- "Content Area"
  }
  
  # Reshape to long format for stacking
  decile_long <- melt(
    decile_data,
    id.vars = c("comparison", "facet_var", "n"),
    measure.vars = c("exact_match", "off_by_1", "off_by_2plus"),
    variable.name = "category",
    value.name = "proportion"
  )
  
  # Define category labels and colors
  decile_long[, category := factor(
    category,
    levels = c("off_by_2plus", "off_by_1", "exact_match"),
    labels = c("≥2 deciles", "±1 decile", "Exact match")
  )]
  
  category_colors <- c(
    "Exact match" = "#2ca02c",    # Green
    "±1 decile" = "#ff7f0e",      # Orange
    "≥2 deciles" = "#d62728"      # Red
  )
  
  # Create plot
  p <- ggplot(decile_long, aes(x = comparison, y = proportion, fill = category)) +
    geom_col(position = "stack", width = 0.7) +
    geom_text(
      data = decile_long[category == "Exact match"],
      aes(label = sprintf("%.0f%%", proportion * 100)),
      position = position_stack(vjust = 0.5),
      size = 3,
      fontface = "bold",
      color = "white"
    ) +
    facet_wrap(~ facet_var, nrow = 1, labeller = labeller(facet_var = function(x) x)) +
    scale_fill_manual(values = category_colors, name = "Classification") +
    scale_y_continuous(
      name = "Proportion of Students",
      labels = percent_format(accuracy = 1),
      expand = c(0, 0)
    ) +
    labs(
      title = title,
      subtitle = sprintf("Percentage in exact decile match (green) shows high decision stability\nStratified by: %s", facet_label),
      caption = paste0("Lower differences indicate copula choice has minimal impact on accountability classifications",
                      classification_note)
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1),
      legend.position = "bottom",
      panel.spacing = unit(0.8, "lines")
    ) +
    guides(fill = guide_legend(nrow = 1, reverse = TRUE))
  
  return(p)
}

############################################################################
### HELPER: Save Plot in Multiple Formats
############################################################################

#' Save a ggplot in PDF, SVG, and PNG formats
#' 
#' @param plot ggplot object
#' @param name Base filename (without extension)
#' @param dir Output directory
#' @param width Plot width in inches
#' @param height Plot height in inches
#' @param dpi Resolution for raster formats
save_plot_multi <- function(plot, name, dir, width = 8, height = 6, dpi = 300) {
  
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  
  formats <- c("pdf", "svg", "png")
  
  for (fmt in formats) {
    filepath <- file.path(dir, paste0(name, ".", fmt))
    
    ggsave(
      filename = filepath,
      plot = plot,
      width = width,
      height = height,
      dpi = dpi,
      device = fmt
    )
    
    cat(sprintf("  Saved: %s\n", filepath))
  }
}
