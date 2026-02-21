############################################################################
### STEP 2: SGPc Sensitivity Analysis - Publication-Grade Plotting Functions
###
### Purpose: Create 10 core plots for publication figure
###          Panel A: Individual-level ECDF (8 comparison pairs)
###          Panel B: School-level ECDF (with inset + district option)
###          Panel C: Condition-level dots (MAD by strata)
###          Panel D: Rank agreement (Spearman rho)
###          Panel E: Decile stability (classification)
###          Panel F: Prior achievement quartile sensitivity
###          Panel G: Cross-dataset comparison
###          Panel H: Multi-level aggregation hierarchy
###          Panel I: Error decomposition (Family vs Sampling)
###          Panel J: Condition N vs MAD (observed sample-size effect)
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

# Recommended portrait dimensions for the tall classification panels (D2, E)
PANEL_CLASSIFICATION_PAGE_WIDTH <- 8.5
PANEL_CLASSIFICATION_PAGE_HEIGHT <- 11

# All 10 comparison pair names (used as default across all panels)
# Labels use en-dash (\u2013) with spaces to suggest subtraction
ALL_COMPARISONS <- c(
  "Empirical \u2013 Best-Fit Parametric",
  "Empirical \u2013 Canonical",
  "Best-Fit \u2013 Canonical",
  "Empirical \u2013 Gaussian",
  "Empirical \u2013 Gumbel",
  "Empirical \u2013 Frank",
  "Empirical \u2013 Clayton",
  "Empirical \u2013 t (Student)",
  "Empirical \u2013 Comonotonic",
  "Empirical \u2013 B-spline SGP"
)

# Canonical ordering: best agreement (left) to worst agreement (right)
# Comonotonic is always rightmost; best-fitting pairs leftmost
COMPARISON_ORDER <- c(
  "Best-Fit \u2013 Canonical",
  "Empirical \u2013 B-spline SGP",
  "Empirical \u2013 Best-Fit Parametric",
  "Empirical \u2013 Canonical",
  "Empirical \u2013 Frank",
  "Empirical \u2013 Clayton",
  "Empirical \u2013 Gumbel",
  "Empirical \u2013 t (Student)",
  "Empirical \u2013 Gaussian",
  "Empirical \u2013 Comonotonic"
)

# Classification-aware ordering: Accuracy (vs Empirical truth) first,
# then Inter-Model Consistency.  Used by panels that display classification
# or rank stability (D1, D2 bucket, E, K) to visually separate the two
# conceptual groups.
ACCURACY_COMPARISON_ORDER <- c(
  # --- Classification Accuracy (Empirical = truth) ---
  "Empirical \u2013 Canonical",
  "Empirical \u2013 Best-Fit Parametric",
  "Empirical \u2013 Clayton",
  "Empirical \u2013 Comonotonic",
  "Empirical \u2013 Frank",
  "Empirical \u2013 Gaussian",
  "Empirical \u2013 Gumbel",
  "Empirical \u2013 t (Student)",
  # --- Inter-Model Consistency (two legitimate approaches to truth) ---
  "Empirical \u2013 B-spline SGP",
  "Best-Fit \u2013 Canonical"
)

# Comparisons that represent inter-model consistency rather than accuracy.
# Both "Empirical - Traditional" (copula SGPc vs B-spline SGP) and
# "Best-Fit - Canonical" compare two legitimate estimation methods with
# no single truth reference.
CONSISTENCY_COMPARISONS <- c(
  "Empirical \u2013 B-spline SGP",
  "Best-Fit \u2013 Canonical"
)

# Colours used to distinguish accuracy vs consistency on x-axis tick labels
ACCURACY_LABEL_COLOR    <- "#6A3D9A"   # dark purple  (Empirical – X)
CONSISTENCY_LABEL_COLOR <- "#1B7837"   # forest green (parametric vs parametric)

############################################################################
### ECDF Thinning Helper
###
### ECDF curves are monotonically increasing; subsampling to max_pts
### evenly-spaced quantile points per group preserves perfect visual
### fidelity while reducing SVG file sizes from GB to KB.
############################################################################

thin_ecdf <- function(dt, max_pts = 10000, by_col = "comparison") {
  dt[, {
    n <- .N
    if (n <= max_pts) {
      .SD
    } else {
      idx <- unique(as.integer(c(1L, seq(1L, n, length.out = max_pts), n)))
      .SD[idx]
    }
  }, by = by_col]
}

#' Background layers for accuracy / consistency regions
#'
#' Returns a list of ggplot annotation layers: two semi-opaque coloured
#' rectangles (purple for accuracy, green for consistency) and a thin
#' solid separator line.  Add these layers BEFORE \code{geom_col()} so
#' the rectangles sit behind the bars.
#'
#' @param comps Character vector of comparisons actually present (factor levels)
#' @return list of ggplot layers (empty list if only one region exists)
accuracy_background_layers <- function(comps) {
  consistency_comps <- intersect(comps, CONSISTENCY_COMPARISONS)
  accuracy_comps    <- setdiff(comps, consistency_comps)

  n_accuracy    <- length(accuracy_comps)
  n_consistency <- length(consistency_comps)
  n_total       <- length(comps)

  if (n_accuracy == 0 || n_consistency == 0) return(list())

  separator_x <- n_accuracy + 0.5

  list(
    # Purple background for accuracy region (left)
    annotate("rect",
      xmin = 0.5, xmax = separator_x,
      ymin = -Inf, ymax = Inf,
      fill = ACCURACY_LABEL_COLOR, alpha = 0.25
    ),
    # Green background for consistency region (right)
    annotate("rect",
      xmin = separator_x, xmax = n_total + 0.5,
      ymin = -Inf, ymax = Inf,
      fill = CONSISTENCY_LABEL_COLOR, alpha = 0.25
    ),
    # Thin solid separator line
    geom_vline(
      xintercept = separator_x,
      linetype   = "solid",
      color      = "gray30",
      linewidth  = 0.3
    )
  )
}

#' Add accuracy / consistency separator to a ggplot with comparison on x-axis
#'
#' Legacy wrapper: inserts a vertical line between Classification Accuracy
#' and Inter-Model Consistency comparisons.  For panels that also want
#' coloured background rectangles, use \code{accuracy_background_layers()}
#' instead (added before \code{geom_col()}).
#'
#' @param p     ggplot object
#' @param comps Character vector of comparisons actually present (factor levels)
#' @return Modified ggplot object
add_accuracy_separator <- function(p, comps) {
  consistency_comps <- intersect(comps, CONSISTENCY_COMPARISONS)
  accuracy_comps    <- setdiff(comps, consistency_comps)

  n_accuracy    <- length(accuracy_comps)
  n_consistency <- length(consistency_comps)

  if (n_accuracy == 0 || n_consistency == 0) return(p)

  separator_x <- n_accuracy + 0.5

  p <- p + geom_vline(
    xintercept = separator_x,
    linetype   = "solid",
    color      = "gray30",
    linewidth  = 0.3
  )

  return(p)
}

#' Colour for accuracy vs consistency comparison labels
#'
#' Returns a character vector of colours (one per element of \code{comps})
#' used to draw coloured x-axis labels via \code{geom_text()} annotation
#' layers, visually distinguishing classification accuracy from inter-model
#' consistency comparisons (as defined by \code{CONSISTENCY_COMPARISONS}).
#'
#' @param comps Character vector of comparison levels (in display order)
#' @return Character vector of colours (same length as \code{comps})
xaxis_accuracy_colors <- function(comps) {
  ifelse(comps %in% CONSISTENCY_COMPARISONS, CONSISTENCY_LABEL_COLOR, ACCURACY_LABEL_COLOR)
}

############################################################################
### UNIFIED COLOUR PALETTE (Wes Anderson "Zissou1")
### All discrete and categorical palettes in STEP_2 are derived from the
### same base palette used by STEP_1's copula_contour_plots.R:
###   colorRampPalette(wes_palette("Zissou1"))
### This ensures visual coherence across the entire publication figure.
############################################################################

ZISSOU1_BASE <- wes_palette("Zissou1")                 # 5 anchor colours
ZISSOU1_RAMP <- colorRampPalette(ZISSOU1_BASE)         # continuous ramp function

# 10-colour comparison palette: smooth teal -> light blue -> gold -> amber -> red
# Semantic ordering preserved: close-to-empirical at teal end,
# mis-specified at red end (same gradient direction as STEP_1 contours)
COMPARISON_COLORS <- setNames(
  ZISSOU1_RAMP(10),
  ALL_COMPARISONS
)

# 3-colour classification palette (Panels D2 and E)
# Zissou1 anchors: teal = good, gold = warning, red = bad
CATEGORY_COLORS <- c(
  "Exact match"     = ZISSOU1_BASE[1],   # teal   (#3B9AB2)
  "+/- 1 category"  = ZISSOU1_BASE[3],   # gold   (#EBCC2A)
  ">= 2 categories" = ZISSOU1_BASE[5]    # red    (#F21A00)
)

# 3-colour aggregation-level palette (Panel H: Individual -> School -> District)
# Red = widest spread (individual), gold = mid, teal = tightest (district)
LEVEL_COLORS <- c(
  "Individual" = ZISSOU1_BASE[5],   # red
  "School"     = ZISSOU1_BASE[3],   # gold
  "District"   = ZISSOU1_BASE[1]    # teal
)

# 2-colour variance-share palette (Panel I right: stacked area)
SHARE_COLORS <- c(
  "Sampling (Finite N)"     = ZISSOU1_BASE[4],   # amber  (#E1AF00)
  "Copula Comparison Pair"  = ZISSOU1_BASE[1]     # teal   (#3B9AB2)
)

# 4-colour dataset palette (Panel G: cross-dataset comparison)
DATASET_COLORS <- setNames(
  ZISSOU1_RAMP(4),
  c("D1: Vertical Scale", "D2: Non-Vertical", "D3: Transition", "D4: Pandemic Gap")
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
#' @param comparisons Character vector of comparison names to include (default: all 8)
#' @param reference_lines Numeric vector of x-values for vertical reference lines (default: c(5, 10))
#' @param title Plot title
#' @return ggplot object
plot_individual_ecdf <- function(
  enhanced_stats,
  comparisons = ALL_COMPARISONS,
  reference_lines = c(5, 10),
  title = "Individual-Level Sensitivity: How Much Do SGPc Values Differ?"
) {
  # Filter to comparisons that exist in the data
  available <- intersect(comparisons, unique(enhanced_stats$individual_stats$all_ecdf_data$comparison))
  if (length(available) == 0) stop("No valid comparisons found in data.")
  comparisons <- available
  
  # Extract ECDF data and thin for SVG-friendly rendering
  ecdf_data <- enhanced_stats$individual_stats$all_ecdf_data
  ecdf_data <- ecdf_data[comparison %in% comparisons]
  ecdf_data <- thin_ecdf(ecdf_data, max_pts = 10000)
  
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
    geom_line(linewidth = 0.78) +
    geom_vline(xintercept = reference_lines, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_point(data = annotation_data, aes(x = x, y = y), size = 2, shape = 21, fill = "white") +
    geom_text(data = annotation_data, aes(x = x, y = y, label = label), 
              hjust = -0.3, vjust = -0.5, size = 3, fontface = "bold", show.legend = FALSE) +
    scale_color_manual(values = COMPARISON_COLORS[comparisons], name = "Comparison") +
    scale_x_continuous(
      name = bquote("Absolute Difference (|" * Delta * "| in percentile points)"),
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
      subtitle = "How large are individual student SGPc differences across copula models?\nECDF of |differences| with policy-relevant thresholds at 5 and 10 percentile points",
      caption = sprintf("n = %s observations across %d conditions", 
                       format(nrow(ecdf_data[comparison == comparisons[1]]), big.mark = ","),
                       if ("dataset_id" %in% names(enhanced_stats$rank_agreement))
                         uniqueN(enhanced_stats$rank_agreement[, paste(dataset_id, condition_id, sep = "__")])
                       else uniqueN(enhanced_stats$rank_agreement$condition_id))
    ) +
    coord_cartesian(clip = "off") +
    theme_publication() +
    theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      plot.margin = margin(12, 40, 7, 0, "pt"),
      legend.position = c(0.70, 0.45),
      legend.justification = c(1, 1),
      legend.direction = "vertical",
      legend.background = element_rect(fill = alpha("white", 0.85), color = "gray60", linewidth = 0.5),
      legend.key.width = unit(0.35, "cm"),
      legend.key.height = unit(0.4, "cm"),
      legend.title = element_text(size = 9, hjust = 0),
      legend.title.position = "top",
      legend.text = element_text(size = 6),
      legend.margin = margin(2, 4, 2, 2, "pt"),
      panel.grid.minor = element_blank()
    )
  
  return(p)
}

############################################################################
### PANEL B: Group-Level ECDF
############################################################################

#' Plot group-level ECDF of absolute SGPc differences (school/district aggregation)
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param reference_lines Numeric vector of x-values for vertical reference lines
#' @param add_inset Logical, whether to add scatter plot inset showing |Delta_g| vs n_g
#' @param group_level "school" or "district"
#' @param agg_method "mean" or "median" -- which aggregation statistic to use
#' @param title Plot title
#' @return ggplot object
plot_group_ecdf <- function(
  enhanced_stats,
  comparisons = ALL_COMPARISONS,
  reference_lines = c(5, 10),
  add_inset = TRUE,
  group_level = "school",
  agg_method = "mean",
  title = NULL
) {
  
  agg_method <- match.arg(agg_method, c("mean", "median"))
  agg_label <- if (agg_method == "mean") "Mean SGPc" else "Median SGPc"
  
  # Select the appropriate group stats based on level
  if (group_level == "district" && !is.null(enhanced_stats$district_stats)) {
    grp <- enhanced_stats$district_stats
    level_label <- "District"
    min_n_label <- "30"
  } else {
    if (is.null(enhanced_stats$group_stats)) {
      stop("Group statistics not available. Ensure SCHOOL_NUMBER/DISTRICT_NUMBER are in data.")
    }
    grp <- enhanced_stats$group_stats
    level_label <- "School"
    min_n_label <- "10"
  }
  
  if (is.null(title)) {
    title <- sprintf("%s-Level Aggregation (%s): Differences Shrink Dramatically", level_label, agg_label)
  }
  
  # Select ECDF data based on agg_method and group_level
  ecdf_key_mean   <- if (group_level == "district") "all_district_ecdf_data_mean"   else "all_group_ecdf_data_mean"
  ecdf_key_median <- if (group_level == "district") "all_district_ecdf_data_median" else "all_group_ecdf_data_median"
  ecdf_key_compat <- if (group_level == "district") "all_district_ecdf_data"        else "all_group_ecdf_data"
  
  ecdf_data <- if (agg_method == "median" && !is.null(grp[[ecdf_key_median]])) {
    grp[[ecdf_key_median]]
  } else if (!is.null(grp[[ecdf_key_mean]])) {
    grp[[ecdf_key_mean]]
  } else {
    grp[[ecdf_key_compat]]
  }
  
  available <- intersect(comparisons, unique(ecdf_data$comparison))
  if (length(available) == 0) stop("No valid comparisons found in group data.")
  comparisons <- available
  ecdf_data <- ecdf_data[comparison %in% comparisons]
  ecdf_data <- thin_ecdf(ecdf_data, max_pts = 10000)
  
  # Calculate annotations for reference lines
  annotations <- lapply(comparisons, function(comp) {
    comp_data <- ecdf_data[comparison == comp]
    if (nrow(comp_data) == 0) return(data.table())
    lapply(reference_lines, function(ref) {
      pct <- mean(comp_data$delta_group <= ref, na.rm = TRUE)
      data.table(comparison = comp, x = ref, y = pct, label = sprintf("%.0f%%", pct * 100))
    })
  })
  annotation_data <- rbindlist(lapply(annotations, function(x) rbindlist(x)))
  
  # Get individual-level and group-level medians for comparison
  ind_medians <- sapply(comparisons, function(comp) {
    s <- enhanced_stats$individual_stats$by_comparison[[comp]]
    if (!is.null(s)) s$median else NA_real_
  })
  
  # Select group-level median of deltas for the chosen agg_method
  delta_key <- if (agg_method == "median") "median_group_delta_median" else "median_group_delta_mean"
  delta_key_compat <- "median_group_delta"
  grp_medians <- sapply(comparisons, function(comp) {
    s <- grp$by_comparison[[comp]]
    if (!is.null(s) && !is.null(s[[delta_key]])) s[[delta_key]]
    else if (!is.null(s) && !is.null(s[[delta_key_compat]])) s[[delta_key_compat]]
    else NA_real_
  })
  
  ind_medians <- ind_medians[!is.na(ind_medians)]
  grp_medians <- grp_medians[!is.na(grp_medians)]
  
  comparison_text <- sprintf(
    "Individual median \u0394: %.1f\u2013%.1f | %s median \u0394: %.1f\u2013%.1f (%.0f%% reduction)",
    min(ind_medians), max(ind_medians),
    level_label,
    min(grp_medians), max(grp_medians),
    (1 - mean(grp_medians) / mean(ind_medians)) * 100
  )
  
  # Get first valid comparison for n_groups
  first_valid <- Filter(Negate(is.null), grp$by_comparison)
  n_groups_str <- if (length(first_valid) > 0) {
    format(first_valid[[1]]$n_groups, big.mark = ",")
  } else { "?" }
  
  # Create main plot
  p <- ggplot(ecdf_data, aes(x = delta_group, y = cumulative_pct, color = comparison)) +
    geom_line(linewidth = 0.78) +
    geom_vline(xintercept = reference_lines, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_point(data = annotation_data, aes(x = x, y = y), size = 2, shape = 21, fill = "white") +
    geom_text(data = annotation_data, aes(x = x, y = y, label = label), 
              hjust = -0.3, vjust = -0.5, size = 3, fontface = "bold", show.legend = FALSE) +
    scale_color_manual(values = COMPARISON_COLORS[comparisons], name = "Comparison") +
    scale_x_continuous(
      name = bquote("Absolute " * .(level_label) * "-Level Difference (|" * Delta[g] * "| in percentile points)"),
      breaks = seq(0, 50, 5),
      limits = c(0, 50)
    ) +
    scale_y_continuous(
      name = sprintf("Cumulative %% of %ss", level_label),
      labels = percent_format(accuracy = 1),
      breaks = seq(0, 1, 0.1)
    ) +
    labs(
      title = title,
      subtitle = sprintf("Aggregation via %s | Does averaging students to %s level wash out copula-choice differences?\nAggregation sharply reduces sensitivity | %s",
                        agg_label, tolower(level_label), comparison_text),
      caption = sprintf("%ss with >= %s students | Total groups: ~%s | Aggregation: %s\n(%ss as surrogates for TIMSS countries / NAEP states)",
                       level_label, min_n_label, n_groups_str, agg_label, level_label)
    ) +
    coord_cartesian(clip = "off") +
    theme_publication() +
    theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      plot.margin = margin(12, 40, 7, 0, "pt"),
      legend.position = c(0.70, 0.45),
      legend.justification = c(1, 1),
      legend.direction = "vertical",
      legend.background = element_rect(fill = alpha("white", 0.85), color = "gray60", linewidth = 0.5),
      legend.key.width = unit(0.35, "cm"),
      legend.key.height = unit(0.4, "cm"),
      legend.title = element_text(size = 9, hjust = 0),
      legend.title.position = "top",
      legend.text = element_text(size = 6),
      legend.margin = margin(2, 4, 2, 2, "pt"),
      panel.grid.minor = element_blank()
    )
  
  # Add inset: |Delta_g| vs group size n_g (sqrt(n) averaging effect)
  if (add_inset && !is.null(enhanced_stats$group_size_analysis)) {
    # Collect all group-level data with sizes
    inset_data_list <- list()
    for (cn in names(enhanced_stats$group_size_analysis)) {
      rd <- enhanced_stats$group_size_analysis[[cn]]$raw_data
      if (!is.null(rd)) {
        rd_copy <- copy(rd)
        rd_copy[, comparison := cn]
        inset_data_list[[cn]] <- rd_copy
      }
    }
    
    if (length(inset_data_list) > 0) {
      inset_data <- rbindlist(inset_data_list, fill = TRUE)
      # Select appropriate delta column for the chosen agg_method
      delta_col_inset <- if (agg_method == "median" && "delta_group_median" %in% names(inset_data)) {
        "delta_group_median"
      } else if ("delta_group_mean" %in% names(inset_data)) {
        "delta_group_mean"
      } else {
        "delta_group"
      }
      if (!delta_col_inset %in% names(inset_data)) inset_data[, delta_group := delta_group_mean]
      # Use just a representative comparison for the inset
      rep_comp <- intersect(c("Emp-Best", "Emp-Canonical"), comparisons)
      if (length(rep_comp) > 0) {
        inset_data <- inset_data[comparison == rep_comp[1]]
        
        p_inset <- ggplot(inset_data, aes(x = n, y = get(delta_col_inset))) +
          geom_point(alpha = 0.2, size = 0.5, color = "gray40") +
          geom_smooth(method = "loess", color = COMPARISON_COLORS[rep_comp[1]], se = FALSE, linewidth = 1) +
          scale_x_log10(name = "Group size (n)", breaks = c(10, 30, 100, 300, 1000)) +
          scale_y_continuous(name = bquote("|" * Delta[g] * "|"), limits = c(0, NA)) +
          labs(title = bquote("sqrt(n) effect")) +
          theme_minimal(base_size = 7) +
          theme(
            plot.title = element_text(face = "bold", size = 7),
            panel.border = element_rect(fill = NA, color = "gray60"),
            plot.background = element_rect(fill = alpha("white", 0.85), color = "gray60", linewidth = 0.5),
            plot.margin = margin(2, 2, 2, 2, "pt")
          )
        
        # Add inset as annotation -- upper-right where ECDF curves have flattened
        p <- p + annotation_custom(
          grob = ggplotGrob(p_inset),
          xmin = 22, xmax = 48,
          ymin = 0.55, ymax = 0.98
        )
      }
    }
  }
  
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
  comparisons = ALL_COMPARISONS,
  title = "Condition-Level Replication: Independent Tests"
) {
  # Filter to comparisons that have valid pairs defined
  comparisons <- intersect(comparisons, names(enhanced_stats$comparison_pairs))
  
  # Compute MAD for each condition and comparison
  comparison_pairs <- enhanced_stats$comparison_pairs
  
  mad_by_condition_list <- list()
  
  for (comp_name in comparisons) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    mad_by_cols <- if ("dataset_id" %in% names(sgpc_data)) c("dataset_id", "condition_id", "year_span", "content_area") else c("condition_id", "year_span", "content_area")
    mad_data <- sgpc_data[, .(
      mad = mean(abs(get(var1) - get(var2)), na.rm = TRUE),
      n = sum(!is.na(get(var1)) & !is.na(get(var2)))
    ), by = mad_by_cols]
    
    mad_data[, comparison := comp_name]
    mad_by_condition_list[[comp_name]] <- mad_data
  }
  
  mad_by_condition <- rbindlist(mad_by_condition_list)
  
  # Apply accuracy-first ordering
  mad_by_condition[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]
  
  # Compute summary stats for overlay
  summary_stats <- mad_by_condition[, .(
    median_mad = median(mad, na.rm = TRUE),
    q25 = quantile(mad, 0.25, na.rm = TRUE),
    q75 = quantile(mad, 0.75, na.rm = TRUE)
  ), by = .(comparison, year_span, content_area)]
  
  # Build coloured x-axis label data -- bottom facet row only
  comps <- levels(mad_by_condition$comparison)
  bottom_content <- tail(sort(unique(as.character(mad_by_condition$content_area))), 1)
  xaxis_label_data <- data.table(
    comparison = factor(comps, levels = comps),
    content_area = bottom_content,
    xcolor = ifelse(comps %in% CONSISTENCY_COMPARISONS,
                    CONSISTENCY_LABEL_COLOR, ACCURACY_LABEL_COLOR)
  )
  
  # Create plot
  p <- ggplot(mad_by_condition, aes(x = comparison, y = mad)) +
    accuracy_background_layers(comps) +
    geom_jitter(width = 0.2, height = 0, alpha = 0.4, size = 1.5, color = "gray30") +
    geom_point(data = summary_stats, aes(y = median_mad),
               size = 2, shape = 18, color = rgb(247, 247, 247, maxColorValue = 255)) +
    geom_errorbar(data = summary_stats, 
                  aes(y = median_mad, ymin = q25, ymax = q75),
                  width = 0.2, linewidth = 0.4, color = rgb(247, 247, 247, maxColorValue = 255)) +
    facet_grid(content_area ~ year_span, 
               labeller = labeller(year_span = function(x) paste(x, "year"),
                                  content_area = function(x) x)) +
    scale_x_discrete(name = "Comparison", labels = NULL) +
    scale_y_continuous(
      name = "Mean Absolute Difference (MAD, percentile points)",
      breaks = seq(0, 30, 5)
    ) +
    coord_cartesian(ylim = c(-2, 30), clip = "off") +
    labs(
      title = title,
      subtitle = "How does copula sensitivity vary across grade spans and content areas?\nEach dot = one condition's MAD | Diamond = median | Error bars = IQR",
      caption = sprintf("n = %d conditions across 4 year spans \u00d7 %d content areas\nX-axis label colour: purple = classification accuracy (vs empirical) | green = inter-model consistency",
                       uniqueN(mad_by_condition$condition_id),
                       uniqueN(mad_by_condition$content_area))
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.title.x = element_text(margin = margin(t = 80, b = 5)),
      legend.position = "none",
      panel.spacing = unit(0.5, "lines"),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )
  
  # Add coloured x-axis comparison labels in margin (bottom row only)
  p <- p + geom_text(
    data = xaxis_label_data,
    aes(x = comparison, y = -4, label = comparison, colour = xcolor),
    inherit.aes = FALSE,
    angle = 45,
    hjust = 1,
    vjust = 0.5,
    size = 1.7,
    show.legend = FALSE
  ) +
  scale_colour_identity()
  
  return(p)
}

############################################################################
### PANEL D1: Rank Agreement (Spearman rho)
############################################################################

#' Plot distribution of Spearman rho across conditions
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param title Plot title
#' @return ggplot object
plot_rank_agreement <- function(
  enhanced_stats,
  comparisons = ALL_COMPARISONS,
  title = "Individual-Level SGPc Rank Stability"
) {
  available <- intersect(comparisons, unique(enhanced_stats$rank_agreement$comparison))
  if (length(available) == 0) stop("No valid comparisons found in rank agreement data.")
  comparisons <- available
  
  # Extract rank agreement data
  rank_data <- enhanced_stats$rank_agreement
  rank_data <- rank_data[comparison %in% comparisons]
  
  # Apply accuracy-first ordering (Empirical-* = accuracy, others = consistency)
  rank_data[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]
  
  # Compute summary stats
  summary_stats <- rank_data[, .(
    median_rho = median(rho, na.rm = TRUE),
    q25 = quantile(rho, 0.25, na.rm = TRUE),
    q75 = quantile(rho, 0.75, na.rm = TRUE),
    min_rho = min(rho, na.rm = TRUE)
  ), by = .(comparison, year_span, content_area)]
  
  # Build coloured x-axis label data -- bottom facet row only
  comps <- levels(rank_data$comparison)
  bottom_content <- tail(sort(unique(as.character(rank_data$content_area))), 1)
  xaxis_label_data <- data.table(
    comparison = factor(comps, levels = comps),
    content_area = bottom_content,
    xcolor = ifelse(comps %in% CONSISTENCY_COMPARISONS,
                    CONSISTENCY_LABEL_COLOR, ACCURACY_LABEL_COLOR)
  )
  
  # Create plot
  p <- ggplot(rank_data, aes(x = comparison, y = rho)) +
    accuracy_background_layers(comps) +
    geom_hline(yintercept = 1.0, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_jitter(width = 0.2, height = 0, alpha = 0.4, size = 1.5, color = "gray30") +
    geom_point(data = summary_stats, aes(y = median_rho),
               size = 2, shape = 18, color = rgb(247, 247, 247, maxColorValue = 255)) +
    geom_errorbar(data = summary_stats,
                  aes(y = median_rho, ymin = q25, ymax = q75),
                  width = 0.2, linewidth = 0.4, color = rgb(247, 247, 247, maxColorValue = 255)) +
    facet_grid(content_area ~ year_span,
               labeller = labeller(year_span = function(x) paste(x, "year"),
                                  content_area = function(x) x)) +
    scale_x_discrete(name = "Comparison", labels = NULL) +
    scale_y_continuous(
      name = bquote("Spearman" ~ rho ~ "(rank correlation)"),
      breaks = seq(0.75, 1.0, 0.05)
    ) +
    coord_cartesian(ylim = c(0.75, 1.0), clip = "off") +
    labs(
      title = title,
      subtitle = "Are individual student rank orderings preserved when the copula model changes?\nEach dot = one condition's Spearman \u03c1 | Rank agreement empirical vs parametric (purple) | parametric vs parametric (green)",
      caption = sprintf("n = %d conditions | All medians >= %.3f\nX-axis label colour: Rank agreement empirical vs parametric (purple) | parametric vs parametric (green)",
                       uniqueN(rank_data$condition_id),
                       min(summary_stats$median_rho))
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.title.x = element_text(margin = margin(t = 75, b = 5)),
      legend.position = "none",
      panel.spacing = unit(0.5, "lines"),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )
  
  # Add coloured x-axis comparison labels in margin (bottom row only)
  p <- p + geom_text(
    data = xaxis_label_data,
    aes(x = comparison, y = 0.72, label = comparison, colour = xcolor),
    inherit.aes = FALSE,
    angle = 45,
    hjust = 1,
    vjust = 0.5,
    size = 1.7,
    show.legend = FALSE
  ) +
  scale_colour_identity()
  
  return(p)
}

############################################################################
### PANEL E: Individual Classification Stability (K=3,5,10)
############################################################################

#' Plot individual-level classification stability as stacked bars
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param stratify_by Either "year_span" or "content_area" for faceting
#' @param n_buckets Integer vector of category counts to show (subset of c(3, 5, 10))
#' @param title Plot title
#' @return ggplot object
plot_decile_stability <- function(
  enhanced_stats,
  comparisons = ALL_COMPARISONS,
  stratify_by = "year_span",
  n_buckets = c(3, 5, 10),
  title = "Classification Accuracy/Precision: Individual-Level SGPc Category Agreement"
) {
  bucket_values <- as.integer(n_buckets)
  
  # Prefer new multi-K table when available; fall back to decile-only legacy table
  if (!is.null(enhanced_stats$individual_bucket_stability) &&
      nrow(enhanced_stats$individual_bucket_stability) > 0) {
    class_data <- copy(enhanced_stats$individual_bucket_stability)
  } else {
    class_data <- copy(enhanced_stats$decile_misclass)
    class_data[, n_buckets := 10L]
  }
  
  available <- intersect(comparisons, unique(class_data$comparison))
  if (length(available) == 0) stop("No valid comparisons found in decile data.")
  comparisons <- available
  
  # Filter to requested comparisons and K values
  class_data <- class_data[comparison %in% comparisons & n_buckets %in% bucket_values]
  if (nrow(class_data) == 0) stop("No matching rows after filtering by comparison and n_buckets.")
  
  # Apply accuracy-first ordering (Empirical-* = accuracy, others = consistency)
  class_data[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]
  
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
        "\nNote: K-category classification not possible for some observations (bimodal: values are 1 or 99 only): ",
        paste(issue_summary, collapse = ", ")
      )
    }
  }
  
  # Filter to relevant strata
  if (stratify_by == "year_span") {
    class_data <- class_data[grepl("^(Overall|Year_)", stratum)]
    class_data[, facet_var := ifelse(stratum == "Overall", "All", gsub("Year_", "", stratum))]
    facet_label <- "Year Span"
  } else {
    class_data <- class_data[stratum %in% c("Overall", "MATHEMATICS", "READING")]
    class_data[, facet_var := stratum]
    facet_label <- "Content Area"
  }
  
  # Row facet labels for K categories
  bucket_labels <- c(
    "3" = "Individual SGPc Terciles (K=3)",
    "5" = "Individual SGPc Quintiles (K=5)",
    "10" = "Individual SGPc Deciles (K=10)"
  )
  class_data[, bucket_label := factor(
    bucket_labels[as.character(n_buckets)],
    levels = bucket_labels[as.character(sort(unique(n_buckets)))]
  )]
  
  # Reshape to long format for stacking
  decile_long <- melt(
    class_data,
    id.vars = c("comparison", "facet_var", "bucket_label", "n_buckets", "n"),
    measure.vars = c("exact_match", "off_by_1", "off_by_2plus"),
    variable.name = "category",
    value.name = "proportion"
  )
  
  # Define category labels and colors
  decile_long[, category := factor(
    category,
    levels = c("off_by_2plus", "off_by_1", "exact_match"),
    labels = c(">= 2 categories", "+/- 1 category", "Exact match")
  )]
  
  category_colors <- CATEGORY_COLORS
  
  # Identify Comonotonic bars with missing/NA data for special annotation
  como_label <- grep("Comonotonic", levels(decile_long$comparison), value = TRUE)
  como_missing <- decile_long[comparison %in% como_label & category == "Exact match" &
                               (is.na(proportion) | proportion == 0)]
  
  # Build coloured x-axis label data (one row per comparison x facet)
  comp_levels <- levels(class_data$comparison)
  xaxis_label_data <- CJ(comparison = factor(comp_levels, levels = comp_levels),
                         facet_var = unique(class_data$facet_var),
                         bucket_label = unique(class_data$bucket_label))
  xaxis_label_data[, xcolor := xaxis_accuracy_colors(as.character(comparison))]
  
  # Prepare kappa annotation data (one row per comparison x facet)
  kappa_anno <- unique(class_data[, .(comparison, facet_var, bucket_label, kappa_w, kappa_w_quad)])
  kappa_anno <- kappa_anno[!is.na(kappa_w)]
  
  # Create plot
  p <- ggplot(decile_long, aes(x = comparison, y = proportion, fill = category)) +
    accuracy_background_layers(levels(class_data$comparison)) +
    geom_col(position = "stack", width = 0.7) +
    geom_text(
      data = decile_long[category == "Exact match" & !is.na(proportion) & proportion > 0],
      aes(label = sprintf("%.0f%%", proportion * 100)),
      position = position_stack(vjust = 0.5),
      size = 1.6,
      fontface = "bold",
      color = "white",
      angle = 90
    ) +
    facet_grid(bucket_label ~ facet_var) +
    scale_fill_manual(values = category_colors, name = "Classification") +
    scale_y_continuous(
      name = "Percentage of Students",
      labels = percent_format(accuracy = 1),
      expand = c(0, 0)
    ) +
    scale_x_discrete(name = "Comparison", labels = NULL) +
    coord_cartesian(ylim = c(-0.01, 1.01), clip = "off") +
    labs(
      title = title,
      subtitle = sprintf("Do individual student classifications change when the copula model changes?\nRows: K=3/5/10 | Stratified by %s | \u03ba = Cohen\u2019s weighted kappa (linear/quadratic weights)", facet_label),
      caption = paste0(
        "X-axis label colour: ",
        "purple = classification accuracy (vs empirical copula) | ",
        "green = inter-model consistency",
        classification_note)
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.text.y = element_text(size = 8),
      axis.ticks.x = element_blank(),
      axis.title.x = element_text(margin = margin(t = 110, b = 5)),  # X-axis title position (room for dual kappa + labels)
      legend.position = "bottom",
      legend.box.spacing = unit(5, "pt"),  # Space above legend
      panel.spacing = unit(0.8, "lines"),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      plot.margin = margin(10, 10, 10, 10, "pt")  #margin around the plot
    ) +
    guides(fill = guide_legend(nrow = 1, reverse = TRUE))
  
  # Add dual kappa annotation below x-axis (bottom row only, between bars and comparison labels)
  kappa_anno_bottom <- kappa_anno[bucket_label == "Individual SGPc Deciles (K=10)"]
  if (nrow(kappa_anno_bottom) > 0) {
    p <- p + geom_text(
      data = kappa_anno_bottom,
      aes(x = comparison, y = -0.03,
          label = sprintf("\u03ba = %.2f / %.2f", kappa_w, kappa_w_quad)),
      inherit.aes = FALSE,
      size = 1.7, angle = 90,
      hjust = 1,    # top of rotated text anchored at y=0 (extends downward)
      vjust = 0.5,  # centered horizontally on the column
      color = "gray30"
    )
  }
  
  # Add manually coloured x-axis labels via geom_text
  # Only show on bottom row (K=10) to avoid repeated clutter
  xaxis_label_data_bottom <- xaxis_label_data[bucket_label == "Individual SGPc Deciles (K=10)"]
  p <- p + geom_text(
    data = xaxis_label_data_bottom,
    aes(x = comparison, y = -0.26, label = comparison),
    inherit.aes = FALSE,
    color = xaxis_label_data_bottom$xcolor,
    angle = 45,
    hjust = 1,    # text end anchored at column position
    vjust = 0.5,  # centered on column (no perpendicular shift)
    size = 1.7
  )
  
  # Add rotated annotation for Comonotonic bars where classification is unavailable
  if (nrow(como_missing) > 0) {
    como_anno <- unique(como_missing[, .(comparison, facet_var, bucket_label)])
    p <- p + geom_text(
      data = como_anno,
      aes(x = comparison, y = 0.5, label = "Category Classification not Possible (Bimodal: Values are 1 or 99 only)"),
      inherit.aes = FALSE,
      angle = 90, size = 1.3, color = "gray20", fontface = "italic", lineheight = 0.9,
      hjust = 0.5,  # vertical centering (along text direction) at y = 0.5
      vjust = 0.2   # horizontal centering on bar column (perpendicular to text); < 0.5 shifts left, > 0.5 shifts right
    )
  }
  
  # Background rectangles + separator line already added via accuracy_background_layers()
  
  return(p)
}


############################################################################
### PANEL D2: Group-Level Mean SGPc Classification Accuracy/Precision (School / District)
###
### For TIMSS/NAEP applications, the analyst only has group-level mean SGPc
### (for states/countries).  This panel answers: "If we classify groups into
### K categories based on their mean SGPc (terciles, quintiles, or deciles),
### how stable are those classifications across copula models?"
############################################################################

#' Plot group-level mean SGPc classification stability across copula models
#'
#' Creates a faceted stacked bar chart showing how stable K-category
#' classifications of group-level mean SGPc are when the copula model changes.
#' Rows = classification granularity (K=3,5,10), columns = aggregation level
#' (School / District).
#'
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparisons to include
#' @param levels Aggregation levels to show (subset of c("school", "district"))
#' @param n_buckets Category counts to display (subset of c(3, 5, 10))
#' @param title Plot title
#' @return ggplot object
plot_group_bucket_stability <- function(
  enhanced_stats,
  comparisons = ALL_COMPARISONS,
  levels = c("school", "district"),
  n_buckets = c(3, 5, 10),
  agg_method = "mean",
  title = NULL
) {
  
  require(ggplot2)
  require(data.table)
  require(scales)
  
  gbs <- enhanced_stats$group_bucket_stability
  
  if (is.null(gbs) || nrow(gbs) == 0) {
    warning("No group_bucket_stability data available. Returning empty plot.")
    return(ggplot() + theme_void() + ggtitle("Panel D2: No group-level bucket data"))
  }
  
  # Derive labels from agg_method
  agg_label <- if (agg_method == "mean") "Mean SGPc" else "Median SGPc"
  if (is.null(title)) {
    title <- paste0("Classification Accuracy/Precision: Group-Level ", agg_label, " Agreement")
  }
  selected_agg <- agg_method

  # Filter to Overall stratum, requested levels, K values, and selected aggregation method
  plot_dt <- gbs[stratum == "Overall" &
                 level %in% levels &
                 n_buckets %in% n_buckets &
                 agg_method == selected_agg]
  
  # Filter to requested comparisons
  available <- intersect(comparisons, unique(plot_dt$comparison))
  if (length(available) == 0) {
    warning("No matching comparisons in group_bucket_stability.")
    return(ggplot() + theme_void() + ggtitle("Panel D2: No matching comparisons"))
  }
  plot_dt <- plot_dt[comparison %in% available]
  
  # Apply accuracy-first ordering (Empirical-* = accuracy, others = consistency)
  plot_dt[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]
  
  # Pretty labels for facets (reflect chosen aggregation method)
  bucket_labels <- c(
    "3"  = paste0(agg_label, " Terciles (K=3)"),
    "5"  = paste0(agg_label, " Quintiles (K=5)"),
    "10" = paste0(agg_label, " Deciles (K=10)")
  )
  plot_dt[, bucket_label := factor(
    bucket_labels[as.character(n_buckets)],
    levels = bucket_labels[as.character(sort(unique(n_buckets)))]
  )]
  
  plot_dt[, level_label := factor(
    fifelse(level == "school", "School", "District"),
    levels = c("School", "District")
  )]
  
  # Reshape to long format for stacking
  plot_long <- melt(
    plot_dt,
    id.vars = c("comparison", "level_label", "bucket_label", "n_groups"),
    measure.vars = c("exact_match", "off_by_1", "off_by_2plus"),
    variable.name = "category",
    value.name = "proportion"
  )
  
  # Define category labels with more technical terminology
  plot_long[, category := factor(
    category,
    levels = c("off_by_2plus", "off_by_1", "exact_match"),
    labels = c(">= 2 categories", "+/- 1 category", "Exact match")
  )]
  
  # Use shared category palette (kept identical to Panel E)
  bucket_colors <- CATEGORY_COLORS
  
  # Build coloured x-axis label data for all facet combinations
  comp_levels <- levels(plot_dt$comparison)
  xaxis_label_data_d2 <- CJ(
    comparison   = factor(comp_levels, levels = comp_levels),
    level_label  = unique(plot_dt$level_label),
    bucket_label = unique(plot_dt$bucket_label)
  )
  xaxis_label_data_d2[, xcolor := xaxis_accuracy_colors(as.character(comparison))]
  
  # Create plot
  p <- ggplot(plot_long, aes(x = comparison, y = proportion, fill = category)) +
    accuracy_background_layers(levels(plot_dt$comparison)) +
    geom_col(position = "stack", width = 0.7) +
    geom_text(
      data = plot_long[category == "Exact match" & !is.na(proportion) & proportion > 0],
      aes(label = sprintf("%.0f%%", proportion * 100)),
      position = position_stack(vjust = 0.5),
      size = 1.6,
      fontface = "bold",
      color = "white"
    ) +
    facet_grid(bucket_label ~ level_label) +
    scale_fill_manual(values = bucket_colors, name = "Classification") +
    scale_y_continuous(
      name = "Percentage of Groups",
      labels = percent_format(accuracy = 1),
      expand = c(0, 0)
    ) +
    scale_x_discrete(name = "Comparison", labels = NULL) +
    coord_cartesian(ylim = c(-0.01, 1.01), clip = "off") +
    labs(
      title = title,
      subtitle = paste0("Do school/district ", tolower(agg_label), " categories change when the copula model changes?\nRows: K=3/5/10 | Columns: School/District | \u03ba = Cohen\u2019s weighted kappa (linear/quadratic weights)"),
      caption = paste0(
        "School (n\u226510 students) | District (n\u226530 students) | ",
        "X-axis label colour: purple = accuracy (vs empirical) | green = classification consistency"
      )
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.text.y = element_text(size = 8),
      axis.ticks.x = element_blank(),
      axis.title.x = element_text(margin = margin(t = 110, b = 5)),  # X-axis title position (room for dual kappa + labels)
      legend.position = "bottom",
      legend.box.spacing = unit(5, "pt"),  # Space above legend (matches Panel E)
      panel.spacing = unit(0.8, "lines"),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold", size = 9),
      plot.margin = margin(10, 10, 10, 10, "pt")  # margin around the plot (matches Panel E)
    ) +
    guides(fill = guide_legend(nrow = 1, reverse = TRUE))
  
  # Add dual kappa annotation below x-axis (bottom row only, between bars and comparison labels)
  if ("kappa_w" %in% names(plot_dt)) {
    kappa_anno_d2 <- unique(plot_dt[, .(comparison, level_label, bucket_label, kappa_w, kappa_w_quad)])
    kappa_anno_d2 <- kappa_anno_d2[!is.na(kappa_w) & bucket_label == bucket_labels[["10"]]]
    if (nrow(kappa_anno_d2) > 0) {
      p <- p + geom_text(
        data = kappa_anno_d2,
        aes(x = comparison, y = -0.03,
            label = sprintf("\u03ba = %.2f / %.2f", kappa_w, kappa_w_quad)),
        inherit.aes = FALSE,
        size = 1.7, angle = 90,
        hjust = 1,    # top of rotated text at y anchor (extends downward)
        vjust = 0.5,  # centered horizontally on the column
        color = "gray30"
      )
    }
  }
  
  # Add manually coloured x-axis labels via geom_text
  # Only show for bottom row (Deciles K=10)
  xaxis_label_data_bottom <- xaxis_label_data_d2[bucket_label == bucket_labels[["10"]]]
  
  p <- p + geom_text(
    data = xaxis_label_data_bottom,
    aes(x = comparison, y = -0.26, label = comparison),
    inherit.aes = FALSE,
    color = xaxis_label_data_bottom$xcolor,
    angle = 45,
    hjust = 1,    # text end anchored at column position
    vjust = 0.5,  # centered on column (no perpendicular shift)
    size = 1.7
  )
  
  # Background rectangles + separator line already added via accuracy_background_layers()
  
  return(p)
}


############################################################################
### PANEL D3: Group-Level Transition Matrices (School / District, K=5/7/10)
############################################################################

#' Plot group-level transition matrices with policy-oriented diagnostics
#'
#' Deep-dive companion to Panel D2. For a selected bucket count K, each facet
#' shows the full transition matrix P(comparison bucket | empirical bucket) for
#' one comparison model and one aggregation level (School or District).
#' Adjacent annotation reports rank/classification diagnostics for that facet.
#'
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param agg_method "mean" or "median"
#' @param comparisons Comparison groups to render as facet rows
#' @param levels Aggregation levels to show
#' @param n_buckets Single bucket count K to display (5, 7, or 10)
#' @param title Plot title
#' @return ggplot object
plot_group_transition_matrices <- function(
  enhanced_stats,
  agg_method = "mean",
  comparisons = c(
    "Empirical – Canonical",
    "Empirical – Best-Fit Parametric",
    "Empirical – t (Student)",
    "Empirical – Gaussian",
    "Empirical – B-spline SGP",
    "Empirical – Comonotonic"
  ),
  levels = c("school", "district"),
  n_buckets = 10,
  title = NULL
) {
  require(ggplot2)
  require(data.table)
  require(scales)
  
  tm <- enhanced_stats$group_transition_matrices
  tmet <- enhanced_stats$group_transition_metrics
  
  if (is.null(tm) || nrow(tm) == 0 || is.null(tmet) || nrow(tmet) == 0) {
    warning("No group transition matrix data available. Returning empty plot.")
    return(ggplot() + theme_void() + ggtitle("Panel D3: No transition matrix data"))
  }
  
  if (length(n_buckets) != 1L) {
    stop("plot_group_transition_matrices() now expects a single K per figure (e.g., 5, 7, or 10).")
  }
  
  agg_label <- if (agg_method == "mean") "Mean SGPc" else "Median SGPc"
  selected_k <- as.integer(n_buckets[[1]])
  if (is.null(title)) {
    title <- paste0(
      "Classification Pathways: Group-Level ", agg_label, " Transition Matrices (K=", selected_k, ")"
    )
  }
  selected_agg <- agg_method
  selected_levels <- levels
  
  tm_filt <- tm[
    level %in% selected_levels &
      n_buckets == selected_k &
      agg_method == selected_agg &
      comparison %in% comparisons
  ]
  
  # Fall back to available comparisons if requested ones are absent
  if (nrow(tm_filt) == 0) {
    available_comps <- unique(tm[agg_method == selected_agg & n_buckets == selected_k, comparison])
    if (length(available_comps) == 0) {
      warning("No transition matrix rows for selected aggregation method.")
      return(ggplot() + theme_void() + ggtitle("Panel D3: No matching transitions"))
    }
    comparisons <- available_comps
    tm_filt <- tm[
      level %in% selected_levels &
        n_buckets == selected_k &
        agg_method == selected_agg &
        comparison %in% comparisons
    ]
  }
  
  available_comparisons <- intersect(comparisons, unique(tm_filt$comparison))
  if (length(available_comparisons) == 0) {
    warning("No requested comparisons available for selected K and aggregation.")
    return(ggplot() + theme_void() + ggtitle("Panel D3: No matching comparisons"))
  }
  
  tm_filt[, level_label := factor(
    fifelse(level == "school", "School", "District"),
    levels = c("School", "District")
  )]
  tm_filt[, comparison_label := factor(comparison, levels = available_comparisons)]
  tm_filt[, label_txt := fifelse(!is.na(row_prop), sprintf(".%02.0f", row_prop * 100), "")]
  tm_filt[, label_txt := fifelse(label_txt == ".100", "1.0", label_txt)]
  tm_filt[, label_col := fifelse(!is.na(row_prop) & row_prop >= 0.45, "white", "gray20")]
  
  # Build diagnostics for each facet (comparison x level), shown to the right of square heatmap
  met_filt <- tmet[
    level %in% selected_levels &
      n_buckets == selected_k &
      agg_method == selected_agg &
      comparison %in% available_comparisons
  ]
  
  met_filt[, level_label := factor(
    fifelse(level == "school", "School", "District"),
    levels = c("School", "District")
  )]
  met_filt[, comparison_label := factor(comparison, levels = available_comparisons)]
  
  comp_short <- c(
    "Empirical – Comonotonic" = "Emp-Comono",
    "Empirical – Best-Fit Parametric" = "Emp-Best",
    "Empirical – B-spline SGP" = "Emp-BSpline",
    "Empirical – t (Student)" = "Emp-t",
    "Empirical – Gaussian" = "Emp-Gauss",
    "Empirical – Canonical" = "Emp-Canon"
  )
  met_filt[, comp_short := fifelse(comparison %in% names(comp_short), comp_short[comparison], comparison)]
  
  stats_dt <- met_filt[, {
    d <- .SD[1]
    stats_label <- paste(
      sprintf("%s  (n = %s)", d$comp_short, format(d$n_groups, big.mark = ",")),
      "",
      "Rank agreement",
      sprintf("  \u03c1 = %.3f", d$spearman_rho),
      sprintf("  \u03baL = %.3f", d$kappa_w),
      sprintf("  \u03baQ = %.3f", d$kappa_w_quad),
      "",
      "Classification",
      sprintf("  Exact  = %.1f%%", 100 * d$exact_match),
      sprintf("  \u00b11      = %.1f%%", 100 * d$off_by_1),
      sprintf("  \u22652      = %.1f%%", 100 * d$off_by_2plus),
      "",
      "Error rates (top / bottom)",
      sprintf("  FP = %.1f%% / %.1f%%", 100 * d$fpr_top, 100 * d$fpr_bottom),
      sprintf("  FN = %.1f%% / %.1f%%", 100 * d$fnr_top, 100 * d$fnr_bottom),
      "",
      "Conditional probs",
      sprintf("  P(Ctop|Etop) = %.1f%%", 100 * d$p_comp_top_given_emp_top),
      sprintf("  P(Etop|Ctop) = %.1f%%", 100 * d$p_emp_top_given_comp_top),
      sprintf("  P(Cbot|Ebot) = %.1f%%", 100 * d$p_comp_bottom_given_emp_bottom),
      sprintf("  P(Ebot|Cbot) = %.1f%%", 100 * d$p_emp_bottom_given_comp_bottom),
      sep = "\n"
    )
    list(
      stats_label = stats_label,
      x_pos = selected_k + 0.65,
      y_pos = (selected_k + 0.5) / 2
    )
  }, by = .(comparison_label, level_label)]
  
  p <- ggplot(tm_filt, aes(x = comparison_bucket, y = empirical_bucket, fill = row_prop)) +
    geom_tile(color = "white", linewidth = 0.25) +
    geom_text(aes(label = label_txt, color = label_col), size = 1.9, show.legend = FALSE) +
    geom_label(
      data = stats_dt,
      aes(x = x_pos, y = y_pos, label = stats_label),
      inherit.aes = FALSE,
      hjust = 0,
      vjust = 0.5,
      size = 1.85,
      lineheight = 0.92,
      label.size = 0.2,
      label.padding = unit(0.18, "lines"),
      fill = "white",
      color = "gray20",
      alpha = 0.92,
      family = "mono"
    ) +
    facet_grid(comparison_label ~ level_label) +
    scale_fill_gradientn(
      colors = ZISSOU1_RAMP(100),
      limits = c(0, 1),
      labels = function(x) sprintf("%.2f", x),
      na.value = "gray95",
      name = "P(Comp bucket |\nEmp bucket)"
    ) +
    scale_color_identity() +
    scale_x_continuous(
      breaks = seq_len(selected_k),
      minor_breaks = NULL,
      limits = c(0.5, 0.5 + selected_k * (10.3 / 7)),
      expand = expansion(mult = c(0, 0))
    ) +
    scale_y_continuous(
      breaks = seq_len(selected_k),
      minor_breaks = NULL,
      limits = c(0.5, selected_k + 0.5),
      expand = expansion(mult = c(0, 0))
    ) +
    coord_fixed(ratio = 1, clip = "off") +
    labs(
      title = title,
      subtitle = paste0(
        "How do school/district growth-bucket classifications shift under different comparison models at K=", selected_k, "?\n",
        "Rows: comparison groups | Columns: School/District | Aggregation: ", agg_label,
        " | School n≥250 | District n≥500"
      ),
      x = "Comparison Bucket",
      y = "Empirical Bucket",
      caption = paste0(
        "Each facet: square transition matrix plus right-side diagnostics ",
        "(ρ, weighted κ, exact/±1/≥2, FP/FN top-bottom, and policy conditional probabilities)."
      )
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_text(size = 7),
      axis.text.y = element_text(size = 7),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold", size = 8.8),
      legend.position = "right",
      legend.title = element_text(size = 8),
      legend.text = element_text(size = 7),
      plot.margin = margin(10, 42, 10, 10, "pt")
    )
  
  return(p)
}


############################################################################
### PANEL F: Prior Achievement Quartile Sensitivity
############################################################################

#' Plot SGPc sensitivity by prior achievement quartile
#' 
#' Shows whether copula choice differentially affects low-achievers vs high-achievers.
#' Key finding: insensitivity holds across the achievement distribution.
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param title Plot title
#' @return ggplot object
plot_prior_quartile_sensitivity <- function(
  enhanced_stats,
  comparisons = ALL_COMPARISONS,
  title = "Achievement Equity: Copula Choice Does Not Differentially Affect Students"
) {
  
  if (is.null(enhanced_stats$prior_quartile_stats) ||
      nrow(enhanced_stats$prior_quartile_stats$raw) == 0) {
    stop("Prior quartile statistics not available. Recompute enhanced statistics.")
  }
  
  raw_data <- enhanced_stats$prior_quartile_stats$raw
  available <- intersect(comparisons, unique(raw_data$comparison))
  if (length(available) == 0) stop("No valid comparisons found in quartile data.")
  comparisons <- available
  raw_data <- raw_data[comparison %in% comparisons]
  
  # Downsample for violin KDE performance (KDE converges well below 100K points)
  MAX_PER_GROUP <- 100000
  raw_data <- raw_data[, {
    if (.N > MAX_PER_GROUP) .SD[sample(.N, MAX_PER_GROUP)] else .SD
  }, by = .(comparison, prior_quartile)]
  
  # Apply accuracy-first ordering (Empirical-* accuracy on left, consistency on right)
  raw_data[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]
  
  # Compute summary statistics for annotation
  summary_data <- raw_data[, .(
    median_delta = median(delta, na.rm = TRUE),
    q90_delta = quantile(delta, 0.90, na.rm = TRUE),
    n = .N
  ), by = .(comparison, prior_quartile)]
  
  # Create violin + boxplot (adjust = 2 smooths KDE over integer-valued deltas)
  # dodge width > violin width creates visible gaps between adjacent violins
  dodge_w <- 0.9
  p <- ggplot(raw_data, aes(x = prior_quartile, y = delta, fill = comparison)) +
    geom_violin(alpha = 0.5, position = position_dodge(width = dodge_w), scale = "width",
                adjust = 2, width = 0.78) +
    stat_summary(fun = "median", geom = "point", size = 1.5, color = "black",
                 position = position_dodge(width = dodge_w)) +
    geom_hline(yintercept = c(5, 10), linetype = "dashed", color = "gray50", linewidth = 0.5) +
    scale_fill_manual(values = COMPARISON_COLORS[comparisons], name = "Comparison") +
    scale_y_continuous(
      name = bquote("|" * Delta * "| (percentile points)"),
      limits = c(0, 30),
      breaks = seq(0, 30, 5)
    ) +
    labs(
      title = title,
      subtitle = "Does copula choice differentially affect low-achieving vs high-achieving students?\nViolin width shows density of |SGPc differences| by prior quartile | Dashed lines at policy thresholds (5, 10 pts)",
      x = "Prior Achievement Quartile",
      caption = "Flat pattern across quartiles = no differential impact on low vs high achievers"
    ) +
    theme_publication(base_size = 9) +
    theme(
      legend.position = "bottom",
      axis.text.x = element_text(size = 9)
    ) +
    guides(fill = guide_legend(nrow = 3))
  
  return(p)
}

############################################################################
### PANEL G: Cross-Dataset Comparison
############################################################################

#' Plot cross-dataset comparison of SGPc sensitivity
#' 
#' Shows that insensitivity holds across all 4 assessment configurations:
#' Dataset 1 (vertical scale), Dataset 2 (non-vertical), Dataset 3 (transition),
#' Dataset 4 (pandemic gap).
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param title Plot title
#' @return ggplot object
plot_cross_dataset_comparison <- function(
  enhanced_stats,
  comparisons = ALL_COMPARISONS,
  title = "Cross-Dataset Generalizability: Insensitivity Across Assessment Configurations"
) {
  
  if (is.null(enhanced_stats$by_dataset_stats) ||
      nrow(enhanced_stats$by_dataset_stats) == 0) {
    stop("Per-dataset statistics not available. Recompute enhanced statistics.")
  }
  
  ds_data <- enhanced_stats$by_dataset_stats
  available <- intersect(comparisons, unique(ds_data$comparison))
  if (length(available) == 0) stop("No valid comparisons found in dataset stats.")
  comparisons <- available
  ds_data <- ds_data[comparison %in% comparisons]
  
  # Apply accuracy-first ordering
  ds_data[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]
  
  # Add descriptive dataset labels
  dataset_labels <- c(
    "dataset_1" = "D1: Vertical Scale",
    "dataset_2" = "D2: Non-Vertical",
    "dataset_3" = "D3: Transition",
    "dataset_4" = "D4: Pandemic Gap"
  )
  ds_data[, dataset_label := ifelse(
    dataset_id %in% names(dataset_labels),
    dataset_labels[dataset_id],
    dataset_id
  )]
  
  # Build coloured x-axis label data (one row per comparison)
  comps <- levels(ds_data$comparison)
  xaxis_label_data <- data.table(
    comparison = factor(comps, levels = comps),
    xcolor = ifelse(comps %in% CONSISTENCY_COMPARISONS,
                    CONSISTENCY_LABEL_COLOR, ACCURACY_LABEL_COLOR)
  )
  
  # Create grouped dot + error bar plot (keep dataset colour)
  p <- ggplot(ds_data, aes(x = comparison, y = mad, color = dataset_label, group = dataset_label)) +
    accuracy_background_layers(comps) +
    geom_point(size = 3, position = position_dodge(width = 0.6)) +
    geom_hline(yintercept = c(3, 5, 10), linetype = "dashed", color = "gray60", linewidth = 0.4) +
    scale_color_manual(values = DATASET_COLORS, name = "Dataset") +
    scale_x_discrete(name = "Comparison", labels = NULL) +
    scale_y_continuous(
      name = "Mean Absolute Difference (MAD, percentile points)",
      breaks = seq(0, 30, 5)
    ) +
    coord_cartesian(ylim = c(0, NA), clip = "off") +
    annotate("text", x = 0.6, y = 3, label = "Negligible", color = "gray50", 
             hjust = 0, vjust = -0.5, size = 2.5, fontface = "italic") +
    annotate("text", x = 0.6, y = 5, label = "Small", color = "gray50",
             hjust = 0, vjust = -0.5, size = 2.5, fontface = "italic") +
    annotate("text", x = 0.6, y = 10, label = "Moderate", color = "gray50",
             hjust = 0, vjust = -0.5, size = 2.5, fontface = "italic") +
    labs(
      title = title,
      subtitle = "Does copula insensitivity hold across different assessment configurations?\nSame comparisons across 4 datasets | Consistent MAD values confirm robustness",
      caption = sprintf("n = %d total observations | %d datasets | %d conditions\nX-axis label colour: purple = classification accuracy (vs empirical) | green = inter-model consistency",
                       sum(ds_data$n),
                       uniqueN(ds_data$dataset_id),
                       sum(ds_data$n_conditions))
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.title.x = element_text(margin = margin(t = 75, b = 5)),
      legend.position = "bottom",
      plot.caption = element_text(margin = margin(t = 14)),
      plot.margin = margin(10, 10, 10, 10, "pt")
    ) +
    guides(color = guide_legend(nrow = 1))
  
  # Add coloured x-axis comparison labels in margin (via annotate to avoid

  # conflict with the existing scale_color_manual for dataset colours)
  for (i in seq_along(comps)) {
    p <- p + annotate("text",
      x = i, y = -2, label = comps[i],
      color = xaxis_label_data$xcolor[i],
      angle = 45, hjust = 1, vjust = 0.5, size = 2.0
    )
  }
  
  return(p)
}

############################################################################
### PANEL H: Multi-Level Aggregation Hierarchy
############################################################################

#' Plot multi-level aggregation showing Individual -> School -> District
#' 
#' Demonstrates that as aggregation level increases, SGPc differences shrink
#' dramatically, validating the Sklar-theoretic extension for TIMSS/NAEP
#' country/state-level reporting.
#' 
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names (subset recommended)
#' @param agg_method "mean" or "median" -- which group aggregation statistic
#' @param title Plot title
#' @return ggplot object
plot_multilevel_aggregation <- function(
  enhanced_stats,
  comparisons = c(
    "Empirical \u2013 Best-Fit Parametric",
    "Empirical \u2013 Gaussian",
    "Empirical \u2013 Comonotonic"
  ),
  agg_method = "mean",
  title = NULL
) {
  
  agg_method <- match.arg(agg_method, c("mean", "median"))
  agg_label <- if (agg_method == "mean") "Mean SGPc" else "Median SGPc"
  if (is.null(title)) {
    title <- sprintf("Multi-Level Aggregation (%s): Individual to School to District", agg_label)
  }
  
  # Build combined ECDF data across levels
  ecdf_list <- list()
  
  # Individual level (always the same -- raw student-level values, not aggregated)
  if (!is.null(enhanced_stats$individual_stats$all_ecdf_data)) {
    ind_ecdf <- enhanced_stats$individual_stats$all_ecdf_data
    available_ind <- intersect(comparisons, unique(ind_ecdf$comparison))
    if (length(available_ind) > 0) {
      ind_ecdf <- ind_ecdf[comparison %in% available_ind]
      ind_ecdf <- copy(ind_ecdf)
      ind_ecdf[, level := "Individual"]
      if ("delta" %in% names(ind_ecdf)) setnames(ind_ecdf, "delta", "abs_diff")
      ecdf_list[["individual"]] <- ind_ecdf[, .(comparison, abs_diff, cumulative_pct, level)]
    }
  }
  
  # School level -- select mean or median ECDF
  sch_ecdf_key <- if (agg_method == "median") "all_group_ecdf_data_median" else "all_group_ecdf_data_mean"
  sch_ecdf_src <- enhanced_stats$group_stats[[sch_ecdf_key]]
  if (is.null(sch_ecdf_src)) sch_ecdf_src <- enhanced_stats$group_stats$all_group_ecdf_data
  if (!is.null(sch_ecdf_src)) {
    available_sch <- intersect(comparisons, unique(sch_ecdf_src$comparison))
    if (length(available_sch) > 0) {
      sch_ecdf <- sch_ecdf_src[comparison %in% available_sch]
      sch_ecdf <- copy(sch_ecdf)
      sch_ecdf[, level := "School"]
      if ("delta_group" %in% names(sch_ecdf)) setnames(sch_ecdf, "delta_group", "abs_diff")
      ecdf_list[["school"]] <- sch_ecdf[, .(comparison, abs_diff, cumulative_pct, level)]
    }
  }
  
  # District level -- select mean or median ECDF
  dist_ecdf_key <- if (agg_method == "median") "all_district_ecdf_data_median" else "all_district_ecdf_data_mean"
  dist_ecdf_src <- enhanced_stats$district_stats[[dist_ecdf_key]]
  if (is.null(dist_ecdf_src)) dist_ecdf_src <- enhanced_stats$district_stats$all_district_ecdf_data
  if (!is.null(dist_ecdf_src)) {
    available_dist <- intersect(comparisons, unique(dist_ecdf_src$comparison))
    if (length(available_dist) > 0) {
      dist_ecdf <- dist_ecdf_src[comparison %in% available_dist]
      dist_ecdf <- copy(dist_ecdf)
      dist_ecdf[, level := "District"]
      if ("delta_group" %in% names(dist_ecdf)) setnames(dist_ecdf, "delta_group", "abs_diff")
      ecdf_list[["district"]] <- dist_ecdf[, .(comparison, abs_diff, cumulative_pct, level)]
    }
  }
  
  if (length(ecdf_list) < 2) {
    stop("Need at least 2 aggregation levels for multi-level plot. Check that school/district stats are available.")
  }
  
  all_ecdf <- rbindlist(ecdf_list)
  all_ecdf[, level := factor(level, levels = c("Individual", "School", "District"))]
  all_ecdf <- thin_ecdf(all_ecdf, max_pts = 10000, by_col = c("level", "comparison"))
  
  # Compute summary annotation: median |Delta| at each level
  medians <- all_ecdf[, .(
    median_diff = median(abs_diff, na.rm = TRUE)
  ), by = .(level, comparison)]
  
  # Create faceted plot: one facet per comparison
  p <- ggplot(all_ecdf, aes(x = abs_diff, y = cumulative_pct, color = level, linetype = level)) +
    geom_line(linewidth = 0.78) +
    geom_vline(xintercept = c(5, 10), linetype = "dashed", color = "gray50", linewidth = 0.4) +
    facet_wrap(~ comparison, nrow = 1) +
    scale_color_manual(
      values = LEVEL_COLORS,
      name = "Aggregation Level"
    ) +
    scale_linetype_manual(
      values = c("Individual" = "solid", "School" = "longdash", "District" = "dotted"),
      name = "Aggregation Level"
    ) +
    scale_x_continuous(
      name = bquote("Absolute Difference (|" * Delta * "| in percentile points)"),
      breaks = seq(0, ceiling(max(all_ecdf$abs_diff, na.rm = TRUE) / 5) * 5, 5),
      limits = c(0, ceiling(max(all_ecdf$abs_diff, na.rm = TRUE) / 5) * 5)
    ) +
    scale_y_continuous(
      name = "Cumulative %",
      labels = percent_format(accuracy = 1),
      breaks = seq(0, 1, 0.2)
    ) +
    labs(
      title = title,
      subtitle = paste0(
        sprintf("Group aggregation via %s | ", agg_label),
        "How much do copula differences shrink at each level of aggregation?\n",
        "Individual \u2192 School \u2192 District: progressive tightening toward near-zero sensitivity"
      ),
      caption = sprintf("Individual = student-level | School = n>=10 | District = n>=30 | Aggregation: %s", agg_label)
    ) +
    theme_publication(base_size = 9) +
    theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      legend.position = "bottom",
      legend.direction = "horizontal",
      legend.background = element_rect(fill = "transparent", color = NA, linewidth = 0),
      legend.key.width = unit(0.6, "cm"),
      legend.key.height = unit(0.35, "cm"),
      legend.title = element_text(size = 9, hjust = 0),
      legend.text = element_text(size = 7),
      legend.margin = margin(2, 4, 2, 2, "pt"),
      strip.text = element_text(face = "bold", size = 9),
      panel.grid.minor = element_blank()
    )
  
  return(p)
}

############################################################################
### PANEL I: Error Decomposition Ribbon Plot (Comparison Pair vs Sampling)
###
### Visualises how the observed SGPc insensitivity holds across sample sizes.
### Left panel:  ribbon of MAD by comparison pair across sample sizes.
### Right panel: stacked area showing share of variance attributable to
###              comparison-pair selection vs sampling noise.
############################################################################

#' Plot error decomposition: comparison pair vs sampling error across sample sizes
#'
#' @param sampling_results Output of compute_sampling_sensitivity()
#' @param title Plot title override
#' @return list of two ggplot objects (ribbon, share)
plot_error_decomposition <- function(
    sampling_results,
    title = "SGPc Sensitivity Stability Across Sample Sizes"
) {

  require(ggplot2)
  require(data.table)

  # ---- Left panel: ribbon of MAD by comparison pair across sample sizes ----
  cell <- copy(sampling_results$cell_summary)
  cell[, sample_size_f := factor(sample_size)]

  # Order comparisons to match COMPARISON_COLORS (defined at top of this file)
  comp_order <- intersect(names(COMPARISON_COLORS), unique(cell$comparison))
  cell[, comparison := factor(comparison, levels = comp_order)]

  # Use the existing COMPARISON_COLORS palette
  comp_colors <- COMPARISON_COLORS[comp_order]

  p_ribbon <- ggplot(cell, aes(x = sample_size, y = mad_mean,
                                color = comparison, fill = comparison)) +
    geom_ribbon(aes(ymin = mad_q05, ymax = mad_q95), alpha = 0.12, linewidth = 0) +
    geom_ribbon(aes(ymin = mad_q25, ymax = mad_q75), alpha = 0.22, linewidth = 0) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2) +
    scale_x_log10(
      name = "Subsample Size (N)",
      breaks = sampling_results$metadata$sample_sizes,
      labels = scales::comma
    ) +
    scale_y_continuous(
      name = bquote("Mean Absolute Difference (percentile points)"),
      limits = c(0, NA)
    ) +
    scale_color_manual(values = comp_colors, name = "Comparison") +
    scale_fill_manual(values = comp_colors, name = "Comparison") +
    labs(
      title = title,
      subtitle = paste0(
        "Does the insensitivity conclusion hold at TIMSS- and NAEP-like sample sizes?\n",
        "Ribbons span 5th\u201395th and 25th\u201375th percentiles across ",
        sampling_results$metadata$B, " replicates | Narrow ribbons confirm robustness at small N"
      )
    ) +
    theme_publication(base_size = 10) +
    theme(
      legend.position = "right",
      plot.margin = margin(10, 10, 10, 10, "pt")
    )

  # ---- Right panel: stacked area of variance shares ----
  per_ss <- copy(sampling_results$per_ss_decomposition)

  # Reshape for stacked area
  per_ss_long <- melt(per_ss,
    id.vars = "sample_size",
    measure.vars = c("comparison_share", "sampling_share"),
    variable.name = "source",
    value.name = "share"
  )
  per_ss_long[, source_label := fifelse(source == "comparison_share",
                                         "Copula Comparison Pair",
                                         "Sampling (Finite N)")]
  per_ss_long[, source_label := factor(source_label,
    levels = c("Sampling (Finite N)", "Copula Comparison Pair"))]

  share_colors <- SHARE_COLORS

  # Secondary-axis context: show total absolute MAD SD as a line
  # scaled onto [0, 1], then recover SD units via sec_axis.
  per_ss[, total_sd := sqrt(pmax(total_var, 0))]
  sd_scale <- max(per_ss$total_sd, na.rm = TRUE)
  if (!is.finite(sd_scale) || sd_scale <= 0) sd_scale <- 1

  p_share <- ggplot(per_ss_long, aes(x = sample_size, y = share, fill = source_label)) +
    geom_area(alpha = 0.7, position = "stack") +
    geom_line(
      data = per_ss,
      aes(x = sample_size, y = total_sd / sd_scale),
      inherit.aes = FALSE,
      linewidth = 0.8,
      color = "black",
      linetype = "solid",
      alpha = 0.75
    ) +
    scale_x_log10(
      name = "Subsample Size (N)",
      breaks = sampling_results$metadata$sample_sizes,
      labels = scales::comma
    ) +
    scale_y_continuous(
      name = "Share of MAD Variance",
      labels = scales::percent_format(accuracy = 1),
      limits = c(0, 1),
      breaks = seq(0, 1, 0.2),
      sec.axis = sec_axis(~ . * sd_scale, name = "Total MAD SD (percentile points)")
    ) +
    scale_fill_manual(values = share_colors, name = "Error Source") +
    labs(
      title = "Variance Decomposition of MAD",
      subtitle = paste0(
        "Is observed MAD driven more by copula choice or by sampling variability?\n",
        "Across N = 50 to 10,000, copula-pair differences explain most variance; sampling share is small and drops quickly below ~5%\n",
        "Black line (right axis) = total MAD SD at each N"
      )
    ) +
    theme_publication(base_size = 10) +
    theme(
      legend.position = "bottom",
      plot.margin = margin(10, 10, 10, 10, "pt")
    )

  # Return a list of two plots; save_plot_multi_panel handles the composite
  return(list(ribbon = p_ribbon, share = p_share))
}

#' Save a composite (multi-panel) figure from a list of ggplots
#' Uses gridExtra to arrange side-by-side and saves in all formats.
#'
#' @param plot_list Named list of ggplot objects
#' @param name Base filename (without extension)
#' @param dir Output directory
#' @param width Total plot width in inches
#' @param height Total plot height in inches
#' @param ncol Number of columns
#' @param widths Relative column widths
#' @param dpi Resolution for raster formats
save_plot_multi_panel <- function(plot_list, name, dir, width = 14, height = 7,
                                  ncol = 2, widths = c(1.2, 1), dpi = 300) {
  
  require(gridExtra)
  
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  
  grob <- gridExtra::arrangeGrob(grobs = plot_list, ncol = ncol, widths = widths)
  
  formats <- c("pdf", "svg", "png")
  
  for (fmt in formats) {
    filepath <- file.path(dir, paste0(name, ".", fmt))
    
    if (fmt == "pdf") {
      if (capabilities("cairo")) {
        cairo_pdf(filepath, width = width, height = height)
      } else {
        pdf(filepath, width = width, height = height)
      }
    } else if (fmt == "svg") {
      svg(filepath, width = width, height = height)
    } else if (fmt == "png") {
      png(filepath, width = width, height = height, units = "in", res = dpi)
    }
    
    grid::grid.draw(grob)
    dev.off()
    cat(sprintf("  Saved: %s\n", filepath))
  }
}


############################################################################
### PANEL J: Condition N vs MAD Scatter (Observed Sample Size Effect)
###
### Uses condition-level statistics from compute_enhanced_statistics()
### to show how MAD varies with observed condition sample size.
### Reveals the sqrt(N) averaging effect visible in real data.
############################################################################

#' Plot condition-level N vs MAD scatter for each comparison pair
#'
#' @param enhanced_stats Output of compute_enhanced_statistics()
#' @param comparisons Character vector of comparisons to plot (default: key pairs)
#' @param title Plot title override
#' @return ggplot object
plot_condition_n_vs_mad <- function(
    enhanced_stats,
    comparisons = ALL_COMPARISONS,
    title = "Condition Sample Size vs SGPc Sensitivity"
) {
  
  require(ggplot2)
  require(data.table)
  
  cond_stats <- enhanced_stats$condition_level_stats
  
  if (is.null(cond_stats) || nrow(cond_stats) == 0) {
    warning("No condition_level_stats available. Returning empty plot.")
    return(ggplot() + theme_void() + ggtitle("Panel J: No condition-level data"))
  }
  
  # Filter to requested comparisons
  plot_dt <- cond_stats[comparison %in% comparisons]
  
  if (nrow(plot_dt) == 0) {
    warning("No data for requested comparisons. Returning empty plot.")
    return(ggplot() + theme_void() + ggtitle("Panel J: No matching comparisons"))
  }
  
  # Apply canonical ordering
  avail_comps <- intersect(COMPARISON_ORDER, unique(plot_dt$comparison))
  plot_dt[, comparison := factor(comparison, levels = avail_comps)]
  
  # Use COMPARISON_COLORS for consistency
  comp_colors <- COMPARISON_COLORS[avail_comps]
  
  p <- ggplot(plot_dt, aes(x = n, y = mad, color = comparison, fill = comparison)) +
    geom_point(alpha = 0.6, size = 1.5, show.legend = TRUE) +
    # Smoothed trend line per comparison
    geom_smooth(method = "loess", se = TRUE, alpha = 0.15, linewidth = 0.8,
                span = 0.75) +
    scale_x_continuous(
      name = "Condition Sample Size (N)",
      labels = scales::comma
    ) +
    scale_y_continuous(
      name = bquote("Mean Absolute Difference (percentile points)"),
      limits = c(0, NA)
    ) +
    scale_color_manual(values = comp_colors, name = "Comparison") +
    scale_fill_manual(values = comp_colors, name = "Comparison") +
    labs(
      title = title,
      subtitle = paste0(
        "Does sensitivity decrease as condition sample size grows?\n",
        "Each point = one condition | Loess trend lines are largely horizontal, indicating little systematic N-related bias (MAD remains stable from <10k to >100k)"
      ),
      caption = bquote("MAD = mean |" * Delta * "SGPc| between copula variants within each condition")
    ) +
    theme_publication(base_size = 10) +
    theme(
      legend.position = "right",
      legend.key.height = unit(0.4, "cm")
    )
  
  return(p)
}


############################################################################
### PANEL K: Group-Level Rank Stability (School + District)
###
### Parallels Panel D (individual rank stability) but for group-level
### rankings.  Shows that school and district rank orderings are preserved
### across copula choices.
############################################################################

#' Plot group-level rank stability (school + district)
#'
#' @param enhanced_stats Output of compute_enhanced_statistics()
#' @param comparisons Character vector of comparisons to include
#' @param title Plot title override
#' @return ggplot object
plot_group_rank_stability <- function(
    enhanced_stats,
    comparisons = ALL_COMPARISONS,
    agg_method = "mean",
    title = NULL
) {
  
  require(ggplot2)
  require(data.table)
  
  # Derive labels from agg_method
  agg_label <- if (agg_method == "mean") "Mean SGPc" else "Median SGPc"
  rho_col   <- if (agg_method == "mean") "rho_mean" else "rho_median"
  if (is.null(title)) {
    title <- paste0("School & District Level ", agg_label, " Rank Stability")
  }
  
  gra <- enhanced_stats$group_rank_agreement
  
  if (is.null(gra) || nrow(gra) == 0) {
    warning("No group_rank_agreement data available. Returning empty plot.")
    return(ggplot() + theme_void() + ggtitle("Panel K: No group-level data"))
  }
  
  available <- intersect(comparisons, unique(gra$comparison))
  if (length(available) == 0) {
    warning("No matching comparisons in group_rank_agreement.")
    return(ggplot() + theme_void() + ggtitle("Panel K: No matching comparisons"))
  }
  
  # Select the appropriate rho column; fall back to 'rho' for backward compat
  if (!rho_col %in% names(gra) && "rho" %in% names(gra)) rho_col <- "rho"
  
  plot_dt <- gra[comparison %in% available & !is.na(get(rho_col))]
  plot_dt[, rho_plot := get(rho_col)]
  
  # Apply accuracy-first ordering (Empirical-* = accuracy, others = consistency)
  plot_dt[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]
  
  # Capitalise level for display
  plot_dt[, level := factor(
    fifelse(level == "school", "School", "District"),
    levels = c("School", "District")
  )]
  
  # Correct condition count (composite key when dataset_id present)
  n_conditions <- if ("dataset_id" %in% names(plot_dt)) {
    uniqueN(plot_dt[, paste(dataset_id, condition_id, sep = "__")])
  } else {
    uniqueN(plot_dt$condition_id)
  }
  
  # Compute summary stats per comparison x level
  summary_dt <- plot_dt[, .(
    median_rho = median(rho_plot, na.rm = TRUE),
    q25        = as.double(quantile(rho_plot, 0.25, na.rm = TRUE)),
    q75        = as.double(quantile(rho_plot, 0.75, na.rm = TRUE))
  ), by = .(comparison, level)]
  
  # Build coloured x-axis label data (one row per comparison)
  comps <- levels(plot_dt$comparison)
  xaxis_label_data <- data.table(
    comparison = factor(comps, levels = comps),
    xcolor = ifelse(comps %in% CONSISTENCY_COMPARISONS,
                    CONSISTENCY_LABEL_COLOR, ACCURACY_LABEL_COLOR)
  )
  
  # Build plot
  p <- ggplot(plot_dt, aes(x = comparison, y = rho_plot)) +
    accuracy_background_layers(comps) +
    geom_hline(yintercept = 1.0, linetype = "dashed", color = "gray50", linewidth = 0.5) +
    geom_jitter(width = 0.2, height = 0, alpha = 0.15, size = 0.9, color = "gray30") +
    geom_point(data = summary_dt, aes(y = median_rho),
               size = 2, shape = 18, color = rgb(247, 247, 247, maxColorValue = 255)) +
    geom_errorbar(data = summary_dt,
                  aes(y = median_rho, ymin = q25, ymax = q75),
                  width = 0.2, linewidth = 0.4, color = rgb(247, 247, 247, maxColorValue = 255)) +
    facet_wrap(~ level, nrow = 1) +
    scale_x_discrete(name = "Comparison", labels = NULL) +
    scale_y_continuous(
      name = bquote("Spearman" ~ rho ~ "(rank correlation)"),
      breaks = seq(0.50, 1.0, 0.05)
    ) +
    coord_cartesian(ylim = c(0.50, 1.0), clip = "off") +
    labs(
      title = title,
      subtitle = paste0(
        "Are school and district ", tolower(agg_label), " growth rankings preserved across copula models?\n",
        "Each dot represents Spearman \u03c1 for ", tolower(agg_label),
        " ranking of schools/districts within each copula combination\n",
        "Diamond = median \u03c1 | Error bars = IQR | Rank agreement empirical vs parametric (purple) | parametric vs parametric (green)"
      ),
      caption = sprintf("School (n\u226510 students) | District (n\u226530 students) | %d conditions",
                       n_conditions)
    ) +
    theme_publication(base_size = 9) +
    theme(
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      axis.title.x = element_text(margin = margin(t = 75, b = 5)),
      legend.position = "none",
      strip.text = element_text(face = "bold", size = 10),
      panel.spacing = unit(1, "lines"),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )
  
  # Add coloured x-axis comparison labels in margin
  p <- p + geom_text(
    data = xaxis_label_data,
    aes(x = comparison, y = 0.46, label = comparison, colour = xcolor),
    inherit.aes = FALSE,
    angle = 45,
    hjust = 1,
    vjust = 0.5,
    size = 1.7,
    show.legend = FALSE
  ) +
  scale_colour_identity()
  
  return(p)
}

############################################################################
### GAUSSIAN MISFIT DIAGNOSTICS
###
### Standalone diagnostic figures anchored to Panel F data structures
### and raw sgpc_data.  These do NOT modify any existing panels (A-K).
###
### Naming convention:  plot_diag_<short_name>()
###   Diag F-A : Focused Quartile Violins   (Panel F subset)
###   Diag F-B : Quartile Summary Lines      (Panel F summary derivative)
###   Diag L   : Delta-vs-Prior Miscalibration (signed, with LOESS)
###   Diag M   : Tail-Focused Rank Stability   (Bottom 10 / Middle 80 / Top 10)
###   Diag N   : Mean-vs-Median Group-Level Stability
############################################################################

# Default comparison subset for Gaussian-misfit diagnostics.
# Highlights Gaussian against three well-fitting copula alternatives.
GAUSSIAN_DIAG_COMPARISONS <- c(
  "Empirical \u2013 Best-Fit Parametric",
  "Empirical \u2013 Canonical",
  "Empirical \u2013 Gaussian",
  "Empirical \u2013 Gumbel"
)

GAUSSIAN_DIAG_PAIRS <- list(
  "Empirical \u2013 Best-Fit Parametric" = c("sgpc_emp", "sgpc_best"),
  "Empirical \u2013 Canonical"           = c("sgpc_emp", "sgpc_avg"),
  "Empirical \u2013 Gaussian"            = c("sgpc_emp", "sgpc_gaussian"),
  "Empirical \u2013 Gumbel"              = c("sgpc_emp", "sgpc_gumbel")
)


############################################################################
### Diag F-A: Focused Quartile Violins (Panel F derivative)
###
### Same grammar as Panel F but restricted to the Gaussian-focused
### comparison subset.  Reuses enhanced_stats$prior_quartile_stats$raw.
############################################################################

#' Diagnostic F-A: Focused Quartile Violins
#'
#' Violin + median dot plot of |SGPc differences| by prior achievement
#' quartile, restricted to Gaussian-focused comparisons.
#'
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param title Plot title
#' @return ggplot object
plot_diag_quartile_focused <- function(
  enhanced_stats,
  comparisons = GAUSSIAN_DIAG_COMPARISONS,
  title = "Gaussian Misfit: Quartile-Level |SGPc Differences|"
) {

  raw_data <- enhanced_stats$prior_quartile_stats$raw
  if (is.null(raw_data) || nrow(raw_data) == 0) {
    stop("Prior quartile raw data not available. Recompute enhanced statistics.")
  }

  available <- intersect(comparisons, unique(raw_data$comparison))
  if (length(available) == 0) stop("No valid comparisons in quartile data.")
  raw_data <- raw_data[comparison %in% available]

  # Downsample for violin KDE performance (KDE converges well below 100K points)
  MAX_PER_GROUP <- 100000
  raw_data <- raw_data[, {
    if (.N > MAX_PER_GROUP) .SD[sample(.N, MAX_PER_GROUP)] else .SD
  }, by = .(comparison, prior_quartile)]

  # Apply accuracy-first ordering
  raw_data[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]

  comp_cols <- COMPARISON_COLORS[levels(raw_data$comparison)]

  # adjust = 2 smooths KDE over integer-valued deltas
  p <- ggplot(raw_data, aes(x = prior_quartile, y = delta, fill = comparison)) +
    geom_violin(alpha = 0.5, position = position_dodge(width = 0.8), scale = "width",
                adjust = 2) +
    stat_summary(fun = "median", geom = "point", size = 1.5, color = "black",
                 position = position_dodge(width = 0.8)) +
    geom_hline(yintercept = c(5, 10), linetype = "dashed", color = "gray50",
               linewidth = 0.5) +
    scale_fill_manual(values = comp_cols, name = "Comparison") +
    scale_y_continuous(
      name = bquote("|" * Delta * "| (percentile points)"),
      limits = c(0, 30),
      breaks = seq(0, 30, 5)
    ) +
    labs(
      title = title,
      subtitle = paste0(
        "Focused: Gaussian vs key alternatives by prior achievement quartile\n",
        "Violin width = density | Points = medians | Dashed lines at 5 & 10 pt thresholds"
      ),
      x = "Prior Achievement Quartile",
      caption = "Wider violins / higher medians for Gaussian suggest tail-sensitive miscalibration"
    ) +
    theme_publication(base_size = 9) +
    theme(
      legend.position = "bottom",
      plot.margin = margin(10, 10, 10, 10, "pt")
    ) +
    guides(fill = guide_legend(nrow = 2))

  return(p)
}


############################################################################
### Diag F-B: Quartile Summary Lines (Panel F derivative)
###
### Connected line plot of median |delta| and Q90 |delta| across prior
### achievement quartiles, one line per comparison.  A steep slope
### (especially at the extremes) signals tail-concentrated misfit.
############################################################################

#' Diagnostic F-B: Quartile Summary Lines
#'
#' @param enhanced_stats List from compute_enhanced_statistics()
#' @param comparisons Character vector of comparison names to include
#' @param title Plot title
#' @return ggplot object
plot_diag_quartile_summary <- function(
  enhanced_stats,
  comparisons = GAUSSIAN_DIAG_COMPARISONS,
  title = "Quartile-Level Summary: Median and Q90 |SGPc Differences|"
) {

  summary_data <- enhanced_stats$prior_quartile_stats$summary
  if (is.null(summary_data) || nrow(summary_data) == 0) {
    stop("Prior quartile summary data not available. Recompute enhanced statistics.")
  }

  available <- intersect(comparisons, unique(summary_data$comparison))
  if (length(available) == 0) stop("No valid comparisons in quartile summary.")
  summary_data <- summary_data[comparison %in% available]
  summary_data[, comparison := factor(comparison,
    levels = intersect(ACCURACY_COMPARISON_ORDER, unique(comparison)))]

  comp_cols <- COMPARISON_COLORS[levels(summary_data$comparison)]

  # Melt to long form for the two summary statistics
  plot_dt <- melt(
    summary_data,
    id.vars = c("prior_quartile", "comparison"),
    measure.vars = c("median_abs_diff", "q90"),
    variable.name = "statistic",
    value.name = "value"
  )
  plot_dt[, statistic := ifelse(
    statistic == "median_abs_diff",
    "Median |\u0394|",
    "Q90 |\u0394|"
  )]

  p <- ggplot(plot_dt, aes(x = prior_quartile, y = value,
                            color = comparison,
                            group = interaction(comparison, statistic),
                            linetype = statistic)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2.5) +
    scale_color_manual(values = comp_cols, name = "Comparison") +
    scale_linetype_manual(
      values = c("Median |\u0394|" = "solid", "Q90 |\u0394|" = "dashed"),
      name = "Statistic"
    ) +
    scale_y_continuous(
      name = "SGPc Difference (percentile points)",
      breaks = seq(0, 30, 5)
    ) +
    labs(
      title = title,
      subtitle = paste0(
        "Connected lines show gradient (slope) vs flatness across quartiles\n",
        "Steep rise at extremes = tail-concentrated misfit"
      ),
      x = "Prior Achievement Quartile",
      caption = "Gaussian showing steeper gradient than alternatives confirms tail-sensitive miscalibration"
    ) +
    theme_publication(base_size = 9) +
    theme(
      legend.position = "bottom",
      plot.margin = margin(10, 10, 10, 10, "pt")
    ) +
    guides(
      color = guide_legend(nrow = 2),
      linetype = guide_legend(nrow = 1)
    )

  return(p)
}


############################################################################
### Diag L: Delta-vs-Prior Miscalibration
###
### Hex-binned scatter of signed delta (sgpc_emp - sgpc_X) against prior
### achievement percentile, with LOESS smooth.  A flat, zero-centred
### smooth = well-calibrated; a structured curve = systematic bias that
### a given copula introduces across the prior-achievement axis.
############################################################################

#' Diagnostic L: Signed Miscalibration by Prior Achievement
#'
#' @param sgpc_data data.table with SGPc variants and SCALE_SCORE_PRIOR
#' @param comparison_pairs Named list of comparison pairs
#' @param title Plot title
#' @return ggplot object
plot_diag_delta_vs_prior <- function(
  sgpc_data,
  comparison_pairs = GAUSSIAN_DIAG_PAIRS,
  title = "Signed Miscalibration by Prior Achievement",
  max_rows_per_facet = 50000L
) {

  if (!"SCALE_SCORE_PRIOR" %in% names(sgpc_data) ||
      all(is.na(sgpc_data$SCALE_SCORE_PRIOR))) {
    stop("SCALE_SCORE_PRIOR not available in sgpc_data.")
  }

  require(hexbin)
  require(mgcv)   # for method = "gam" (fast O(n) smooth)

  # Build long-form data: one row per student per comparison
  delta_list <- list()
  for (comp_name in names(comparison_pairs)) {
    vars <- comparison_pairs[[comp_name]]
    var1 <- vars[1]; var2 <- vars[2]
    if (!var1 %in% names(sgpc_data) || !var2 %in% names(sgpc_data)) next

    sub <- sgpc_data[!is.na(get(var1)) & !is.na(get(var2)) & !is.na(SCALE_SCORE_PRIOR)]
    if (nrow(sub) == 0) next

    # Downsample very large facets (preserves hex density pattern;
    # GAM smooth converges well below 50k points)
    if (nrow(sub) > max_rows_per_facet) {
      set.seed(42L)
      sub <- sub[sample(.N, max_rows_per_facet)]
    }

    # Convert prior score to percentile rank for cross-scale comparability
    delta_list[[comp_name]] <- sub[, .(
      prior_pctile = frank(SCALE_SCORE_PRIOR, ties.method = "average") / .N * 100,
      signed_delta = get(var1) - get(var2),
      comparison = comp_name
    )]
  }

  if (length(delta_list) == 0) stop("No valid comparisons found in data.")
  delta_dt <- rbindlist(delta_list)

  # Order comparisons
  avail <- unique(delta_dt$comparison)
  ordered <- intersect(ACCURACY_COMPARISON_ORDER, avail)
  if (length(ordered) == 0) ordered <- avail
  delta_dt[, comparison := factor(comparison, levels = ordered)]

  zissou_grad <- colorRampPalette(wes_palette("Zissou1"))(50)

  # Use GAM (mgcv) instead of LOESS: O(n) vs O(n^2), virtually identical
  # visual output for this diagnostic purpose.
  p <- ggplot(delta_dt, aes(x = prior_pctile, y = signed_delta)) +
    geom_hex(bins = 60) +
    geom_hline(yintercept = 0, color = "gray30", linetype = "dashed",
               linewidth = 0.5) +
    geom_smooth(method = "gam", formula = y ~ s(x, bs = "cs"),
                color = "#F21A00", linewidth = 0.9, fill = "gray80",
                alpha = 0.3, se = TRUE) +
    facet_wrap(~ comparison, ncol = 2, scales = "free_y") +
    scale_fill_gradientn(
      colors = zissou_grad, trans = "log10", name = "Count"
    ) +
    scale_x_continuous(
      name = "Prior Achievement (percentile rank)",
      breaks = seq(0, 100, 25)
    ) +
    scale_y_continuous(
      name = expression(Delta ~ "=" ~ SGPc[emp] - SGPc[X])
    ) +
    labs(
      title = title,
      subtitle = paste0(
        "GAM smooth reveals systematic miscalibration axis\n",
        "Flat line = well-calibrated | Curved = structured bias"
      ),
      caption = paste0(
        "Positive \u0394: empirical SGPc > parametric SGPc | ",
        "Hex shading: observation density (log scale)"
      )
    ) +
    theme_publication(base_size = 9) +
    theme(
      legend.position = "right",
      plot.margin = margin(10, 10, 10, 10, "pt")
    )

  return(p)
}


############################################################################
### Diag M: Tail-Focused Rank Stability
###
### Partitions students by prior achievement into Bottom 10 %, Middle 80 %,
### Top 10 % and computes Spearman rho between SGPc variants within each
### tier and condition.  If Gaussian misfit concentrates in the tails,
### Gaussian rho will drop noticeably in the Bottom/Top panels while
### well-fitting alternatives remain stable.
############################################################################

#' Diagnostic M: Tail-Focused Rank Stability
#'
#' @param sgpc_data data.table with SGPc variants, SCALE_SCORE_PRIOR,
#'   condition_id, year_span, content_area
#' @param comparison_pairs Named list of comparison pairs
#' @param title Plot title
#' @return ggplot object
plot_diag_tail_rank_stability <- function(
  sgpc_data,
  comparison_pairs = GAUSSIAN_DIAG_PAIRS,
  title = "Tail-Focused Rank Stability: Does Gaussian Misfit Concentrate in Tails?"
) {

  if (!"SCALE_SCORE_PRIOR" %in% names(sgpc_data) ||
      all(is.na(sgpc_data$SCALE_SCORE_PRIOR))) {
    stop("SCALE_SCORE_PRIOR not available in sgpc_data.")
  }

  # Create prior achievement tiers (added to sgpc_data by reference)
  sgpc_data[, prior_tier := cut(
    SCALE_SCORE_PRIOR,
    breaks = quantile(SCALE_SCORE_PRIOR,
                      probs = c(0, 0.10, 0.90, 1), na.rm = TRUE),
    labels = c("Bottom 10%", "Middle 80%", "Top 10%"),
    include.lowest = TRUE
  )]

  # Compute Spearman rho per tier per condition per comparison
  # Include dataset_id in grouping when available to preserve unique dataset-condition combinations
  has_dataset_id <- "dataset_id" %in% names(sgpc_data)
  by_cols <- c("prior_tier", if (has_dataset_id) "dataset_id", "condition_id", "year_span", "content_area")
  rho_list <- list()
  for (comp_name in names(comparison_pairs)) {
    vars <- comparison_pairs[[comp_name]]
    var1 <- vars[1]; var2 <- vars[2]
    if (!var1 %in% names(sgpc_data) || !var2 %in% names(sgpc_data)) next

    rho_by_tier <- sgpc_data[
      !is.na(prior_tier) & !is.na(get(var1)) & !is.na(get(var2)),
      {
        n_valid <- sum(!is.na(get(var1)) & !is.na(get(var2)))
        if (n_valid >= 30) {
          list(
            rho = tryCatch(
              cor(get(var1), get(var2), method = "spearman", use = "complete.obs"),
              error = function(e) NA_real_
            ),
            n = n_valid
          )
        } else {
          list(rho = NA_real_, n = n_valid)
        }
      },
      by = by_cols
    ]

    rho_by_tier[, comparison := comp_name]
    rho_list[[comp_name]] <- rho_by_tier
  }

  if (length(rho_list) == 0) stop("No valid comparisons found in data.")
  rho_dt <- rbindlist(rho_list)
  rho_dt <- rho_dt[!is.na(rho)]

  # Order comparisons
  avail <- unique(rho_dt$comparison)
  ordered <- intersect(ACCURACY_COMPARISON_ORDER, avail)
  if (length(ordered) == 0) ordered <- avail
  rho_dt[, comparison := factor(comparison, levels = ordered)]
  rho_dt[, prior_tier := factor(prior_tier,
    levels = c("Bottom 10%", "Middle 80%", "Top 10%"))]

  # Compute summary for annotation
  summary_dt <- rho_dt[, .(
    median_rho = median(rho, na.rm = TRUE),
    q25 = quantile(rho, 0.25, na.rm = TRUE),
    q75 = quantile(rho, 0.75, na.rm = TRUE),
    n_conditions = .N
  ), by = .(comparison, prior_tier)]

  comp_cols <- COMPARISON_COLORS[levels(rho_dt$comparison)]

  # Fixed y-axis floor for comparability across regenerated outputs
  y_floor <- 0.7

  p <- ggplot(rho_dt, aes(x = comparison, y = rho, color = comparison)) +
    geom_jitter(width = 0.2, alpha = 0.3, size = 1) +
    geom_point(data = summary_dt, aes(y = median_rho),
               size = 3, shape = 18, color = "black") +
    geom_errorbar(data = summary_dt,
                  aes(y = median_rho, ymin = q25, ymax = q75),
                  width = 0.3, linewidth = 0.6, color = "black") +
    facet_wrap(~ prior_tier, nrow = 1) +
    scale_color_manual(values = comp_cols) +
    scale_y_continuous(
      name = "Spearman \u03c1",
      breaks = seq(y_floor, 1.0, 0.05)
    ) +
    coord_cartesian(ylim = c(y_floor, 1.0)) +
    labs(
      title = title,
      subtitle = paste0(
        "Rank stability by prior achievement tier\n",
        "Points = one Spearman \u03c1 per tier \u00d7 dataset \u00d7 condition combination | Diamonds = median | Bars = IQR across conditions"
      ),
      x = "Comparison",
      caption = "Weaker tail correlations for Gaussian support the tail-dependence hypothesis"
    ) +
    theme_publication(base_size = 9) +
    theme(
      legend.position = "none",
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )

  return(p)
}


############################################################################
### Diag N: Mean-vs-Median Group-Level Stability
###
### Computes group-level Spearman rho using BOTH mean and median
### aggregation of SGPc within schools/districts.  If Gaussian instability
### is tail-amplified, mean aggregation (more sensitive to tails) will
### show lower rho than median aggregation.
############################################################################

#' Diagnostic N: Mean vs Median Group-Level Stability
#'
#' @param sgpc_data data.table with SGPc variants, SCHOOL_NUMBER,
#'   DISTRICT_NUMBER, condition_id, year_span, content_area
#' @param comparison_pairs Named list of comparison pairs
#' @param title Plot title
#' @return ggplot object
plot_diag_mean_vs_median_stability <- function(
  sgpc_data,
  comparison_pairs = GAUSSIAN_DIAG_PAIRS,
  title = "Mean vs Median Aggregation: Group-Level Rank Stability"
) {

  has_school <- "SCHOOL_NUMBER" %in% names(sgpc_data) &&
                sum(!is.na(sgpc_data$SCHOOL_NUMBER)) > 0
  has_district <- "DISTRICT_NUMBER" %in% names(sgpc_data) &&
                  sum(!is.na(sgpc_data$DISTRICT_NUMBER)) > 0

  if (!has_school && !has_district) {
    stop("SCHOOL_NUMBER and DISTRICT_NUMBER not found or all NA.")
  }

  # Helper: compute group rho for mean AND median aggregation
  compute_agg_rho <- function(dt, group_var, min_n, pairs, level_label) {
    results <- list()
    for (comp_name in names(pairs)) {
      vars <- pairs[[comp_name]]
      var1 <- vars[1]; var2 <- vars[2]
      if (!var1 %in% names(dt) || !var2 %in% names(dt)) next

      group_agg <- dt[!is.na(get(group_var)) &
                       !is.na(get(var1)) & !is.na(get(var2)), .(
        mean1   = mean(get(var1), na.rm = TRUE),
        mean2   = mean(get(var2), na.rm = TRUE),
        median1 = as.double(median(get(var1), na.rm = TRUE)),
        median2 = as.double(median(get(var2), na.rm = TRUE)),
        n = .N
      ), by = c(group_var, "condition_id", "year_span", "content_area")]

      group_agg <- group_agg[n >= min_n]

      rho_by_cond <- group_agg[, {
        if (.N >= 5) {
          list(
            rho_mean = tryCatch(
              cor(mean1, mean2, method = "spearman", use = "complete.obs"),
              error = function(e) NA_real_),
            rho_median = tryCatch(
              cor(median1, median2, method = "spearman", use = "complete.obs"),
              error = function(e) NA_real_),
            n_groups = .N
          )
        } else {
          list(rho_mean = NA_real_, rho_median = NA_real_, n_groups = .N)
        }
      }, by = .(condition_id, year_span, content_area)]

      rho_by_cond[, `:=`(comparison = comp_name, level = level_label)]
      results[[comp_name]] <- rho_by_cond
    }
    if (length(results) > 0) rbindlist(results) else data.table()
  }

  rho_parts <- list()
  if (has_school) {
    rho_parts[["school"]] <- compute_agg_rho(
      sgpc_data, "SCHOOL_NUMBER", 10, comparison_pairs, "School")
  }
  if (has_district) {
    rho_parts[["district"]] <- compute_agg_rho(
      sgpc_data, "DISTRICT_NUMBER", 30, comparison_pairs, "District")
  }

  rho_dt <- rbindlist(rho_parts)
  if (nrow(rho_dt) == 0) stop("No valid group-level data found.")

  # Melt to long form for plotting
  rho_long <- melt(
    rho_dt,
    id.vars = c("condition_id", "year_span", "content_area",
                 "comparison", "level", "n_groups"),
    measure.vars = c("rho_mean", "rho_median"),
    variable.name = "aggregation",
    value.name = "rho"
  )
  rho_long <- rho_long[!is.na(rho)]
  rho_long[, aggregation := ifelse(
    aggregation == "rho_mean", "Mean", "Median")]

  # Order comparisons
  avail <- unique(rho_long$comparison)
  ordered <- intersect(ACCURACY_COMPARISON_ORDER, avail)
  if (length(ordered) == 0) ordered <- avail
  rho_long[, comparison := factor(comparison, levels = ordered)]

  # Summary statistics
  summary_dt <- rho_long[, .(
    median_rho = median(rho, na.rm = TRUE),
    q25 = quantile(rho, 0.25, na.rm = TRUE),
    q75 = quantile(rho, 0.75, na.rm = TRUE)
  ), by = .(comparison, level, aggregation)]

  y_floor <- min(0.5, min(rho_long$rho, na.rm = TRUE) - 0.05)

  p <- ggplot(rho_long, aes(x = comparison, y = rho,
                              color = aggregation, shape = aggregation)) +
    geom_point(alpha = 0.25, size = 1,
               position = position_jitterdodge(
                 jitter.width = 0.12, dodge.width = 0.5)) +
    geom_point(data = summary_dt, aes(y = median_rho),
               size = 3, position = position_dodge(width = 0.5)) +
    geom_errorbar(data = summary_dt,
                  aes(y = median_rho, ymin = q25, ymax = q75),
                  width = 0.3, linewidth = 0.5,
                  position = position_dodge(width = 0.5)) +
    facet_wrap(~ level, nrow = 1) +
    scale_color_manual(
      values = c("Mean" = ZISSOU1_BASE[5], "Median" = ZISSOU1_BASE[1]),
      name = "Aggregation"
    ) +
    scale_shape_manual(
      values = c("Mean" = 16, "Median" = 17),
      name = "Aggregation"
    ) +
    scale_y_continuous(
      name = "Spearman \u03c1",
      breaks = seq(round(y_floor, 1), 1.0, 0.1)
    ) +
    coord_cartesian(ylim = c(y_floor, 1.0)) +
    labs(
      title = title,
      subtitle = paste0(
        "Mean aggregation amplifies tail effects | Median is more robust to outliers\n",
        "Large points = median | Bars = IQR across conditions"
      ),
      x = "Comparison",
      caption = "If median \u03c1 > mean \u03c1 for Gaussian, confirms tail-amplified instability in mean aggregation"
    ) +
    theme_publication(base_size = 9) +
    theme(
      legend.position = "bottom",
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
      plot.margin = margin(10, 10, 10, 10, "pt")
    )

  return(p)
}


############################################################################
### Diag O: Composition-Bias Pathway
###
### Quantifies the causal link between Diag L (individual-level signed tilt)
### and Diag N (group-level rank instability).
###
### For each school g in each condition, computes:
###   mean_prior_g  = mean(SCALE_SCORE_PRIOR)
###   mean_delta_g  = mean(SGPc_emp - SGPc_X)       (signed)
### Then correlates across schools: r(mean_prior_g, mean_delta_g).
###
### A large negative r for Gaussian (with near-zero r for well-fitting
### copulas) confirms that Gaussian misfit propagates to group rankings
### via differential composition bias.
############################################################################

#' Diagnostic O: Composition-Bias Pathway
#'
#' @param sgpc_data data.table with SGPc variants, SCHOOL_NUMBER,
#'   SCALE_SCORE_PRIOR, condition_id, year_span, content_area
#' @param comparison_pairs Named list of comparison pairs
#' @param min_school_n Minimum students per school to include
#' @param title Plot title
#' @return ggplot object
plot_diag_composition_bias <- function(
  sgpc_data,
  comparison_pairs = GAUSSIAN_DIAG_PAIRS,
  min_school_n = 10L,
  title = "Composition-Bias Pathway: Does Group Prior Achievement Predict SGPc Discrepancy?"
) {

  has_school <- "SCHOOL_NUMBER" %in% names(sgpc_data) &&
                sum(!is.na(sgpc_data$SCHOOL_NUMBER)) > 0
  if (!has_school) stop("SCHOOL_NUMBER not found or all NA.")
  if (!"SCALE_SCORE_PRIOR" %in% names(sgpc_data) ||
      all(is.na(sgpc_data$SCALE_SCORE_PRIOR))) {
    stop("SCALE_SCORE_PRIOR not available in sgpc_data.")
  }

  # --- Aggregate to school level per condition per comparison ---
  agg_list <- list()
  for (comp_name in names(comparison_pairs)) {
    vars <- comparison_pairs[[comp_name]]
    var1 <- vars[1]; var2 <- vars[2]
    if (!var1 %in% names(sgpc_data) || !var2 %in% names(sgpc_data)) next

    school_agg <- sgpc_data[
      !is.na(SCHOOL_NUMBER) & !is.na(get(var1)) &
        !is.na(get(var2)) & !is.na(SCALE_SCORE_PRIOR),
      .(
        mean_prior = mean(SCALE_SCORE_PRIOR, na.rm = TRUE),
        mean_delta = mean(get(var1) - get(var2), na.rm = TRUE),
        n = .N
      ),
      by = .(SCHOOL_NUMBER, condition_id)
    ]
    school_agg <- school_agg[n >= min_school_n]
    if (nrow(school_agg) == 0) next

    school_agg[, comparison := comp_name]
    agg_list[[comp_name]] <- school_agg
  }

  if (length(agg_list) == 0) stop("No valid school-level data found.")
  agg_dt <- rbindlist(agg_list)

  # --- Compute per-condition Pearson r for annotation ---
  r_by_cond <- agg_dt[, {
    if (.N >= 5) {
      list(r = tryCatch(
        cor(mean_prior, mean_delta, method = "pearson", use = "complete.obs"),
        error = function(e) NA_real_
      ))
    } else {
      list(r = NA_real_)
    }
  }, by = .(comparison, condition_id)]
  r_by_cond <- r_by_cond[!is.na(r)]

  r_summary <- r_by_cond[, .(
    median_r = median(r, na.rm = TRUE),
    q25 = quantile(r, 0.25, na.rm = TRUE),
    q75 = quantile(r, 0.75, na.rm = TRUE),
    n_conditions = .N
  ), by = comparison]

  # Print to console for diagnostic confirmation
  cat("  Composition-bias Pearson r (school mean_prior vs mean_delta):\n")
  for (i in seq_len(nrow(r_summary))) {
    cat(sprintf("    %s: median r = %.3f  [IQR: %.3f, %.3f]  (%d conditions)\n",
                r_summary$comparison[i],
                r_summary$median_r[i],
                r_summary$q25[i], r_summary$q75[i],
                r_summary$n_conditions[i]))
  }

  # --- Order comparisons ---
  avail <- unique(agg_dt$comparison)
  ordered <- intersect(ACCURACY_COMPARISON_ORDER, avail)
  if (length(ordered) == 0) ordered <- avail
  agg_dt[, comparison := factor(comparison, levels = ordered)]
  r_summary[, comparison := factor(comparison, levels = ordered)]

  # --- Build annotation labels ---
  r_summary[, label := sprintf("median r = %.3f", median_r)]

  # Convert prior to percentile rank within each comparison facet for

  # cross-scale comparability (same approach as Diag L)
  agg_dt[, mean_prior_pctile := frank(mean_prior, ties.method = "average") / .N * 100,
         by = comparison]

  zissou_grad <- colorRampPalette(wes_palette("Zissou1"))(50)

  # --- Plot ---
  p <- ggplot(agg_dt, aes(x = mean_prior_pctile, y = mean_delta)) +
    geom_hex(bins = 50) +
    geom_hline(yintercept = 0, color = "gray30", linetype = "dashed",
               linewidth = 0.5) +
    geom_smooth(method = "lm", formula = y ~ x, se = TRUE,
                color = "#F21A00", linewidth = 0.9, fill = "gray80",
                alpha = 0.3) +
    geom_text(
      data = r_summary,
      aes(x = 10, y = Inf, label = label),
      hjust = 0, vjust = 1.5, size = 3.5, fontface = "bold",
      color = "black", inherit.aes = FALSE
    ) +
    facet_wrap(~ comparison, ncol = 2, scales = "free_y") +
    scale_fill_gradientn(
      colors = zissou_grad, trans = "log10", name = "Count"
    ) +
    scale_x_continuous(
      name = "School Mean Prior Achievement (percentile rank)",
      breaks = seq(0, 100, 25)
    ) +
    scale_y_continuous(
      name = expression(bar(Delta)[g] ~ "= school mean" ~ (SGPc[emp] - SGPc[X]))
    ) +
    labs(
      title = title,
      subtitle = paste0(
        "Strong slope = copula misfit propagates to group rankings via composition\n",
        "Flat line = misfit does not bias groups differentially"
      ),
      caption = paste0(
        "Each hex = school (\u2265", min_school_n, " students) \u00d7 condition | ",
        "r = median Pearson correlation across conditions"
      )
    ) +
    theme_publication(base_size = 9) +
    theme(
      legend.position = "right",
      plot.margin = margin(10, 10, 10, 10, "pt")
    )

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
    
    # Use cairo_pdf for PDF when available (better Unicode/font support)
    if (fmt == "pdf" && capabilities("cairo")) {
      device <- cairo_pdf
    } else {
      device <- fmt
    }
    
    ggsave(
      filename = filepath,
      plot = plot,
      width = width,
      height = height,
      dpi = dpi,
      device = device
    )
    
    cat(sprintf("  Saved: %s\n", filepath))
  }
}
