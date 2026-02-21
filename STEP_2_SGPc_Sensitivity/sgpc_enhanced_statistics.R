############################################################################
### STEP 2: SGPc Sensitivity Analysis - Enhanced Statistics
###
### Purpose: Compute comprehensive statistics for publication-grade visualizations
###          - Individual-level quantiles and exceedance rates (8 comparison pairs)
###          - Group-level aggregates (school AND district means)
###          - Individual & group-level rank agreement (Spearman correlations)
###          - Decile misclassification rates
###          - Prior achievement quartile stratification
###          - Per-dataset statistics (cross-dataset generalizability)
###          - Group-size stratification (sqrt(n) averaging effect)
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)

#' Compute Cohen's weighted kappa (no external package dependency)
#'
#' @param x1 Integer vector of category assignments (e.g., decile 1-10)
#' @param x2 Integer vector of category assignments (same scale as x1)
#' @param K  Number of categories (default: 10 for deciles)
#' @param weights "linear" (default) or "quadratic"
#' @return Numeric scalar: weighted kappa, or NA_real_ if not computable
compute_weighted_kappa <- function(x1, x2, K = 10, weights = "linear") {
  valid <- !is.na(x1) & !is.na(x2)
  x1 <- as.integer(x1[valid]); x2 <- as.integer(x2[valid])
  if (length(x1) == 0) return(NA_real_)
  tab <- table(factor(x1, levels = 1:K), factor(x2, levels = 1:K))
  n <- sum(tab)
  if (n == 0) return(NA_real_)
  p_obs <- tab / n
  p_row <- rowSums(p_obs); p_col <- colSums(p_obs)
  p_exp <- outer(p_row, p_col)
  w <- if (weights == "linear") {
    1 - abs(outer(1:K, 1:K, "-")) / (K - 1)
  } else {
    1 - (outer(1:K, 1:K, "-"))^2 / (K - 1)^2
  }
  po_w <- sum(w * p_obs); pe_w <- sum(w * p_exp)
  if (pe_w >= 1) return(NA_real_)
  (po_w - pe_w) / (1 - pe_w)
}

#' Compute enhanced statistics for SGPc sensitivity analysis
#' 
#' @param sgpc_data data.table with all SGPc variants (from sgpc_all_variants_*.rds)
#' @param comparison_pairs Named list of comparison pairs (default: all 8 key comparisons)
#' @return List with individual_stats, group_stats, district_stats, rank_agreement,
#'         group_rank_agreement, individual_bucket_stability, decile_misclass,
#'         prior_quartile_stats, by_dataset_stats, group_size_analysis
compute_enhanced_statistics <- function(
  sgpc_data,
  comparison_pairs = list(
    "Empirical \u2013 Best-Fit Parametric"      = c("sgpc_emp", "sgpc_best"),
    "Empirical \u2013 Canonical"      = c("sgpc_emp", "sgpc_avg"),
    "Best-Fit \u2013 Canonical"                  = c("sgpc_best", "sgpc_avg"),
    "Empirical \u2013 Gaussian"                  = c("sgpc_emp", "sgpc_gaussian"),
    "Empirical \u2013 Gumbel"                    = c("sgpc_emp", "sgpc_gumbel"),
    "Empirical \u2013 Frank"                     = c("sgpc_emp", "sgpc_frank"),
    "Empirical \u2013 Clayton"                   = c("sgpc_emp", "sgpc_clayton"),
    "Empirical \u2013 t (Student)"               = c("sgpc_emp", "sgpc_t"),
    "Empirical \u2013 Comonotonic"               = c("sgpc_emp", "sgpc_comonotonic"),
    "Empirical \u2013 B-spline SGP" = c("sgpc_emp", "sgp_traditional")
  )
) {
  
  cat("====================================================================\n")
  cat("COMPUTING ENHANCED STATISTICS FOR PUBLICATION FIGURES\n")
  cat("====================================================================\n\n")
  
  cat("Input data:\n")
  cat("  Observations:", nrow(sgpc_data), "\n")
  has_dataset_id <- "dataset_id" %in% names(sgpc_data)
  if (has_dataset_id) {
    cat("  Datasets:", uniqueN(sgpc_data$dataset_id), "\n")
    cat("  Conditions:", uniqueN(sgpc_data[, paste(dataset_id, condition_id, sep = "__")]), "\n")
  } else {
    cat("  Conditions:", uniqueN(sgpc_data$condition_id), "(WARNING: no dataset_id column)\n")
  }
  cat("  Comparison pairs:", length(comparison_pairs), "\n\n")
  
  ############################################################################
  ### A. INDIVIDUAL-LEVEL STATISTICS
  ############################################################################
  
  cat("Computing individual-level statistics...\n")
  
  individual_stats <- list()
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    # Compute absolute differences
    delta <- abs(sgpc_data[[var1]] - sgpc_data[[var2]])
    
    # Quantiles
    quantiles <- quantile(delta, probs = c(0.50, 0.90, 0.95, 0.99), na.rm = TRUE)
    
    # Exceedance rates
    exceedance_5 <- mean(delta > 5, na.rm = TRUE)
    exceedance_10 <- mean(delta > 10, na.rm = TRUE)
    
    # ECDF data for plotting
    delta_sorted <- sort(delta[!is.na(delta)])
    ecdf_data <- data.table(
      comparison = comp_name,
      delta = delta_sorted,
      cumulative_pct = seq_along(delta_sorted) / length(delta_sorted)
    )
    
    individual_stats[[comp_name]] <- list(
      comparison = comp_name,
      var1 = var1,
      var2 = var2,
      n = sum(!is.na(delta)),
      median = quantiles["50%"],
      q90 = quantiles["90%"],
      q95 = quantiles["95%"],
      q99 = quantiles["99%"],
      exceedance_5 = exceedance_5,
      exceedance_10 = exceedance_10,
      ecdf_data = ecdf_data
    )
    
    cat(sprintf("  %s: median=%.1f, Q95=%.1f, P(>5)=%.1f%%, P(>10)=%.1f%%\n",
                comp_name, quantiles["50%"], quantiles["95%"], 
                exceedance_5 * 100, exceedance_10 * 100))
  }
  
  # Combine all ECDF data for plotting
  all_ecdf_data <- rbindlist(lapply(individual_stats, function(x) x$ecdf_data))
  
  cat("\n")
  
  ############################################################################
  ### B. GROUP-LEVEL STATISTICS (School-level)
  ############################################################################
  
  cat("Computing school-level group statistics...\n")
  
  group_stats <- list()
  district_stats <- list()
  group_size_analysis <- list()
  
  # Check if school/district IDs are available
  has_school <- "SCHOOL_NUMBER" %in% names(sgpc_data) && sum(!is.na(sgpc_data$SCHOOL_NUMBER)) > 0
  has_district <- "DISTRICT_NUMBER" %in% names(sgpc_data) && sum(!is.na(sgpc_data$DISTRICT_NUMBER)) > 0
  
  cat(sprintf("  SCHOOL_NUMBER available: %s\n", has_school))
  cat(sprintf("  DISTRICT_NUMBER available: %s\n", has_district))
  
  if (!has_school && !has_district) {
    cat("  WARNING: No SCHOOL_NUMBER or DISTRICT_NUMBER found. Skipping group aggregation.\n")
    cat("  Re-run Step 2.1 with updated sgpc_compute_all_variants.R to include these IDs.\n\n")
  }
  
  # Build once-per-comparison group aggregates and reuse across sections (B, C2, D2, D3)
  build_group_aggregate_cache <- function(dt, group_var, level_label) {
    cache <- list()
    grp_by <- if (has_dataset_id) {
      c(group_var, "dataset_id", "condition_id", "year_span", "content_area")
    } else {
      c(group_var, "condition_id", "year_span", "content_area")
    }
    
    for (comp_name in names(comparison_pairs)) {
      var1 <- comparison_pairs[[comp_name]][1]
      var2 <- comparison_pairs[[comp_name]][2]
      
      if (all(is.na(dt[[var1]])) || all(is.na(dt[[var2]]))) {
        next
      }
      
      agg <- dt[!is.na(get(group_var)) & !is.na(get(var1)) & !is.na(get(var2)), .(
        mean1   = mean(get(var1), na.rm = TRUE),
        mean2   = mean(get(var2), na.rm = TRUE),
        median1 = as.double(median(get(var1), na.rm = TRUE)),
        median2 = as.double(median(get(var2), na.rm = TRUE)),
        n = .N
      ), by = grp_by]
      
      if (nrow(agg) == 0L) next
      
      agg[, `:=`(
        comparison = comp_name,
        var1 = var1,
        var2 = var2,
        level = level_label,
        delta_group_mean = abs(mean1 - mean2),
        delta_group_median = abs(median1 - median2)
      )]
      
      cache[[comp_name]] <- agg
    }
    
    cache
  }
  
  school_group_cache <- list()
  district_group_cache <- list()
  
  if (has_school) {
    cat("  Precomputing school-level group aggregates (reused across sections)...\n")
    school_group_cache <- build_group_aggregate_cache(sgpc_data, "SCHOOL_NUMBER", "school")
  }
  
  if (has_district) {
    cat("  Precomputing district-level group aggregates (reused across sections)...\n")
    district_group_cache <- build_group_aggregate_cache(sgpc_data, "DISTRICT_NUMBER", "district")
  }
  
  # --- B1: School-level aggregation ---
  if (has_school) {
    cat("  Computing school-level aggregates (min n=10)...\n")
    
    for (comp_name in names(comparison_pairs)) {
      var1 <- comparison_pairs[[comp_name]][1]
      var2 <- comparison_pairs[[comp_name]][2]
      group_agg <- school_group_cache[[comp_name]]
      if (is.null(group_agg)) next
      
      # Filter: n >= 10 for stability
      group_agg_filtered <- group_agg[n >= 10]
      
      if (nrow(group_agg_filtered) > 0) {
        # Mean-based ECDF
        q_mean <- quantile(group_agg_filtered$delta_group_mean,
                           probs = c(0.50, 0.90, 0.95), na.rm = TRUE)
        ds_mean <- sort(group_agg_filtered$delta_group_mean)
        ecdf_mean <- data.table(
          comparison = comp_name,
          delta_group = ds_mean,
          cumulative_pct = seq_along(ds_mean) / length(ds_mean)
        )
        
        # Median-based ECDF
        q_median <- quantile(group_agg_filtered$delta_group_median,
                             probs = c(0.50, 0.90, 0.95), na.rm = TRUE)
        ds_median <- sort(group_agg_filtered$delta_group_median)
        ecdf_median <- data.table(
          comparison = comp_name,
          delta_group = ds_median,
          cumulative_pct = seq_along(ds_median) / length(ds_median)
        )
        
        group_stats[[comp_name]] <- list(
          comparison = comp_name,
          var1 = var1, var2 = var2,
          n_groups = nrow(group_agg_filtered),
          median_group_delta_mean   = q_mean["50%"],
          q90_group_delta_mean      = q_mean["90%"],
          q95_group_delta_mean      = q_mean["95%"],
          median_group_delta_median = q_median["50%"],
          q90_group_delta_median    = q_median["90%"],
          q95_group_delta_median    = q_median["95%"],
          group_ecdf_data_mean   = ecdf_mean,
          group_ecdf_data_median = ecdf_median,
          group_ecdf_data = ecdf_mean,
          group_agg_full = group_agg_filtered
        )
        
        cat(sprintf("    %s: %d schools, median Delta (mean agg)=%.1f, median Delta (median agg)=%.1f (vs individual %.1f)\n",
                    comp_name, nrow(group_agg_filtered),
                    q_mean["50%"], q_median["50%"],
                    individual_stats[[comp_name]]$median))
      }
    }
    
    # Combine all school ECDF data (both mean-based and median-based)
    if (length(group_stats) > 0) {
      all_group_ecdf_data       <- rbindlist(lapply(group_stats, function(x) x$group_ecdf_data_mean))
      all_group_ecdf_data_mean  <- all_group_ecdf_data
      all_group_ecdf_data_median <- rbindlist(lapply(group_stats, function(x) x$group_ecdf_data_median))
    } else {
      all_group_ecdf_data        <- data.table()
      all_group_ecdf_data_mean   <- data.table()
      all_group_ecdf_data_median <- data.table()
    }
    
    # --- B1b: Group-size stratification (sqrt(n) effect) ---
    cat("  Computing group-size stratification (sqrt(n) effect)...\n")
    
    # Use the first valid comparison to build the group-size analysis
    # (pattern is the same across comparisons, so one representative suffices)
    for (comp_name in names(comparison_pairs)) {
      if (!is.null(group_stats[[comp_name]])) {
        gm <- group_stats[[comp_name]]$group_agg_full
        
        # Bin by group size
        gm[, size_bin := cut(n, breaks = c(10, 30, 100, 300, Inf),
                             labels = c("10-29", "30-99", "100-299", "300+"),
                             include.lowest = TRUE)]
        
        size_summary <- gm[, .(
          n_groups = .N,
          median_delta_mean   = median(delta_group_mean, na.rm = TRUE),
          q90_delta_mean      = quantile(delta_group_mean, 0.90, na.rm = TRUE),
          median_delta_median = median(delta_group_median, na.rm = TRUE),
          q90_delta_median    = quantile(delta_group_median, 0.90, na.rm = TRUE),
          mean_n = mean(n)
        ), by = size_bin]
        
        group_size_analysis[[comp_name]] <- list(
          comparison = comp_name,
          size_summary = size_summary,
          raw_data = gm[, .(SCHOOL_NUMBER, condition_id, n, delta_group_mean, delta_group_median, size_bin)]
        )
      }
    }
    
    if (length(group_size_analysis) > 0) {
      size_summary_all <- rbindlist(lapply(names(group_size_analysis), function(cn) {
        s <- group_size_analysis[[cn]]$size_summary
        s[, comparison := cn]
        s
      }))
      cat(sprintf("    Size bins: %s\n", paste(unique(size_summary_all$size_bin), collapse = ", ")))
    }
  }
  
  # --- B2: District-level aggregation (TIMSS country / NAEP state surrogate) ---
  if (has_district) {
    cat("  Computing district-level aggregates (min n=30, TIMSS/NAEP surrogate)...\n")
    
    for (comp_name in names(comparison_pairs)) {
      var1 <- comparison_pairs[[comp_name]][1]
      var2 <- comparison_pairs[[comp_name]][2]
      dist_agg <- district_group_cache[[comp_name]]
      if (is.null(dist_agg)) next
      
      # Filter: n >= 30 for district-level stability
      dist_agg_filtered <- dist_agg[n >= 30]
      
      if (nrow(dist_agg_filtered) > 0) {
        # Mean-based ECDF
        dq_mean <- quantile(dist_agg_filtered$delta_group_mean,
                            probs = c(0.50, 0.90, 0.95), na.rm = TRUE)
        ds_mean <- sort(dist_agg_filtered$delta_group_mean)
        dist_ecdf_mean <- data.table(
          comparison = comp_name,
          delta_group = ds_mean,
          cumulative_pct = seq_along(ds_mean) / length(ds_mean)
        )
        
        # Median-based ECDF
        dq_median <- quantile(dist_agg_filtered$delta_group_median,
                              probs = c(0.50, 0.90, 0.95), na.rm = TRUE)
        ds_median <- sort(dist_agg_filtered$delta_group_median)
        dist_ecdf_median <- data.table(
          comparison = comp_name,
          delta_group = ds_median,
          cumulative_pct = seq_along(ds_median) / length(ds_median)
        )
        
        district_stats[[comp_name]] <- list(
          comparison = comp_name,
          var1 = var1, var2 = var2,
          n_groups = nrow(dist_agg_filtered),
          median_group_delta_mean   = dq_mean["50%"],
          q90_group_delta_mean      = dq_mean["90%"],
          q95_group_delta_mean      = dq_mean["95%"],
          median_group_delta_median = dq_median["50%"],
          q90_group_delta_median    = dq_median["90%"],
          q95_group_delta_median    = dq_median["95%"],
          group_ecdf_data_mean   = dist_ecdf_mean,
          group_ecdf_data_median = dist_ecdf_median,
          group_ecdf_data = dist_ecdf_mean,
          group_agg_full = dist_agg_filtered
        )
        
        cat(sprintf("    %s: %d districts, median Delta (mean agg)=%.1f, median Delta (median agg)=%.1f (vs school %.1f, individual %.1f)\n",
                    comp_name, nrow(dist_agg_filtered),
                    dq_mean["50%"], dq_median["50%"],
                    if (!is.null(group_stats[[comp_name]])) group_stats[[comp_name]]$median_group_delta_mean else NA,
                    individual_stats[[comp_name]]$median))
      }
    }
    
    # Combine all district ECDF data (both mean-based and median-based)
    if (length(district_stats) > 0) {
      all_district_ecdf_data       <- rbindlist(lapply(district_stats, function(x) x$group_ecdf_data_mean))
      all_district_ecdf_data_mean  <- all_district_ecdf_data
      all_district_ecdf_data_median <- rbindlist(lapply(district_stats, function(x) x$group_ecdf_data_median))
    } else {
      all_district_ecdf_data        <- data.table()
      all_district_ecdf_data_mean   <- data.table()
      all_district_ecdf_data_median <- data.table()
    }
  }
  
  cat("\n")
  
  ############################################################################
  ### C. RANK AGREEMENT (Spearman correlations by condition)
  ############################################################################
  
  cat("Computing individual-level rank agreement (Spearman rho by condition)...\n")
  
  rank_agreement_list <- list()
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    if (all(is.na(sgpc_data[[var1]])) || all(is.na(sgpc_data[[var2]]))) {
      cat(sprintf("  %s: skipped (NA values)\n", comp_name))
      next
    }
    
    # Compute Spearman correlation for each condition (include dataset_id)
    rho_by_cols <- if (has_dataset_id) c("dataset_id", "condition_id", "year_span", "content_area") else c("condition_id", "year_span", "content_area")
    rho_by_condition <- sgpc_data[, .(
      rho = tryCatch(
        cor(get(var1), get(var2), method = "spearman", use = "complete.obs"),
        error = function(e) NA_real_
      ),
      n = sum(!is.na(get(var1)) & !is.na(get(var2)))
    ), by = rho_by_cols]
    
    rho_by_condition[, comparison := comp_name]
    
    rank_agreement_list[[comp_name]] <- rho_by_condition
    
    cat(sprintf("  %s: median rho=%.4f, min rho=%.4f\n",
                comp_name, 
                median(rho_by_condition$rho, na.rm = TRUE),
                min(rho_by_condition$rho, na.rm = TRUE)))
  }
  
  rank_agreement <- rbindlist(rank_agreement_list)
  
  ############################################################################
  ### C2. GROUP-LEVEL RANK AGREEMENT (School/District rank preservation)
  ############################################################################
  
  cat("\nComputing group-level rank agreement...\n")
  cat("  (Do school/district rank orderings change with copula choice?)\n")
  
  group_rank_agreement_list <- list()
  
  # Helper: compute group-level Spearman rho using precomputed group aggregates
  # Returns rho for both mean-based and median-based group aggregations
  compute_group_rank_rho <- function(group_cache, min_n, level_label) {
    results <- list()
    for (comp_name in names(group_cache)) {
      group_agg <- group_cache[[comp_name]]
      if (is.null(group_agg)) next
      group_agg <- group_agg[n >= min_n]
      if (nrow(group_agg) == 0L) next
      
      # For each condition, compute Spearman rho of group rankings (mean-based and median-based)
      rho_by_cols <- if ("dataset_id" %in% names(group_agg)) c("dataset_id", "condition_id", "year_span", "content_area") else c("condition_id", "year_span", "content_area")
      rho_by_cond <- group_agg[, {
        if (.N >= 5) {
          list(
            rho_mean = tryCatch(
              cor(mean1, mean2, method = "spearman", use = "complete.obs"),
              error = function(e) NA_real_
            ),
            rho_median = tryCatch(
              cor(median1, median2, method = "spearman", use = "complete.obs"),
              error = function(e) NA_real_
            ),
            n_groups = .N
          )
        } else {
          list(rho_mean = NA_real_, rho_median = NA_real_, n_groups = .N)
        }
      }, by = rho_by_cols]
      
      # Keep backward-compatible 'rho' column (mean-based)
      rho_by_cond[, rho := rho_mean]
      rho_by_cond[, `:=`(comparison = comp_name, level = level_label)]
      results[[comp_name]] <- rho_by_cond
    }
    
    if (length(results) > 0) rbindlist(results) else data.table()
  }
  
  if (has_school) {
    cat("  School-level rank agreement...\n")
    school_rank_rho <- compute_group_rank_rho(school_group_cache, 10, "school")
    if (nrow(school_rank_rho) > 0) {
      group_rank_agreement_list[["school"]] <- school_rank_rho
      for (cn in unique(school_rank_rho$comparison)) {
        sub <- school_rank_rho[comparison == cn & !is.na(rho)]
        if (nrow(sub) > 0) {
          cat(sprintf("    %s: median school-rank rho=%.4f, min=%.4f (%d conditions)\n",
                      cn, median(sub$rho), min(sub$rho), nrow(sub)))
        }
      }
    }
  }
  
  if (has_district) {
    cat("  District-level rank agreement...\n")
    district_rank_rho <- compute_group_rank_rho(district_group_cache, 30, "district")
    if (nrow(district_rank_rho) > 0) {
      group_rank_agreement_list[["district"]] <- district_rank_rho
      for (cn in unique(district_rank_rho$comparison)) {
        sub <- district_rank_rho[comparison == cn & !is.na(rho)]
        if (nrow(sub) > 0) {
          cat(sprintf("    %s: median district-rank rho=%.4f, min=%.4f (%d conditions)\n",
                      cn, median(sub$rho), min(sub$rho), nrow(sub)))
        }
      }
    }
  }
  
  group_rank_agreement <- if (length(group_rank_agreement_list) > 0) {
    rbindlist(group_rank_agreement_list)
  } else {
    data.table()
  }
  
  cat("\n")
  
  ############################################################################
  ### D. INDIVIDUAL-LEVEL CLASSIFICATION STABILITY (K=3,5,10)
  ############################################################################
  
  cat("Computing individual-level classification stability (K=3,5,10)...\n")
  
  # Compute per-condition K-bucket assignments for each SGPc variant
  sgpc_with_buckets <- copy(sgpc_data)
  individual_bucket_sizes <- c(3L, 5L, 10L)
  
  # Track K=10 classification issues (backward-compatible reporting/captions)
  classification_issues <- list()
  
  bucket_vars <- c("sgpc_emp", "sgpc_best", "sgpc_avg", "sgpc_gaussian",
                   "sgpc_gumbel", "sgpc_frank", "sgpc_clayton", "sgpc_t",
                   "sgpc_comonotonic", "sgp_traditional")
  for (var in bucket_vars) {
    if (var %in% names(sgpc_with_buckets)) {
      clean_name <- gsub("^sgpc_|^sgp_", "", var)
      
      for (K in individual_bucket_sizes) {
        bucket_var <- paste0("bucket_k", K, "_", clean_name)
        
        bucket_by <- if (has_dataset_id) c("dataset_id", "condition_id") else "condition_id"
        sgpc_with_buckets[, (bucket_var) := {
          vals <- get(var)
          tryCatch({
            breaks <- quantile(vals, probs = seq(0, 1, 1 / K), na.rm = TRUE, type = 1)
            if (length(unique(breaks)) < length(breaks)) {
              rep(NA_character_, length(vals))
            } else {
              as.character(cut(vals, breaks = breaks, labels = seq_len(K), include.lowest = TRUE))
            }
          }, error = function(e) {
            rep(NA_character_, length(vals))
          })
        }, by = bucket_by]
        
        if (K == 10L) {
          n_na <- sum(is.na(sgpc_with_buckets[[bucket_var]]))
          if (n_na > 0) {
            failed_conditions <- if (has_dataset_id) {
              sgpc_with_buckets[is.na(get(bucket_var)),
                unique(paste(dataset_id, condition_id, sep = "__"))]
            } else {
              sgpc_with_buckets[is.na(get(bucket_var)), unique(condition_id)]
            }
            classification_issues[[var]] <- list(
              n_failed = n_na,
              n_total = nrow(sgpc_with_buckets),
              pct_failed = 100 * n_na / nrow(sgpc_with_buckets),
              failed_conditions = failed_conditions
            )
            cat(sprintf("  NOTE: %s classification failed for %d obs (%.1f%%) across %d conditions\n",
                        var, n_na, 100 * n_na / nrow(sgpc_with_buckets), length(failed_conditions)))
            cat(sprintf("        (Bimodal distribution: values are 1 or 99 only in: %s)\n",
                        paste(head(failed_conditions, 3), collapse = ", ")))
          }
        }
      }
    }
  }
  
  individual_bucket_stability_list <- list()
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    clean1 <- gsub("^sgpc_|^sgp_", "", var1)
    clean2 <- gsub("^sgpc_|^sgp_", "", var2)
    
    for (K in individual_bucket_sizes) {
      bucket1 <- paste0("bucket_k", K, "_", clean1)
      bucket2 <- paste0("bucket_k", K, "_", clean2)
      
      if (bucket1 %in% names(sgpc_with_buckets) && bucket2 %in% names(sgpc_with_buckets)) {
        # Overall
        stability_overall <- sgpc_with_buckets[, {
          d1 <- as.integer(get(bucket1)); d2 <- as.integer(get(bucket2))
          bucket_diff <- abs(d1 - d2)
          list(
            exact_match = mean(bucket_diff == 0, na.rm = TRUE),
            off_by_1 = mean(bucket_diff == 1, na.rm = TRUE),
            off_by_2plus = mean(bucket_diff >= 2, na.rm = TRUE),
            n = sum(!is.na(bucket_diff)),
            kappa_w = compute_weighted_kappa(d1, d2, K = K, weights = "linear"),
            kappa_w_quad = compute_weighted_kappa(d1, d2, K = K, weights = "quadratic")
          )
        }]
        stability_overall[, `:=`(comparison = comp_name, stratum = "Overall", n_buckets = K)]
        
        # By year span
        stability_by_year <- sgpc_with_buckets[, {
          d1 <- as.integer(get(bucket1)); d2 <- as.integer(get(bucket2))
          bucket_diff <- abs(d1 - d2)
          list(
            exact_match = mean(bucket_diff == 0, na.rm = TRUE),
            off_by_1 = mean(bucket_diff == 1, na.rm = TRUE),
            off_by_2plus = mean(bucket_diff >= 2, na.rm = TRUE),
            n = sum(!is.na(bucket_diff)),
            kappa_w = compute_weighted_kappa(d1, d2, K = K, weights = "linear"),
            kappa_w_quad = compute_weighted_kappa(d1, d2, K = K, weights = "quadratic")
          )
        }, by = year_span]
        stability_by_year[, `:=`(comparison = comp_name, stratum = paste0("Year_", year_span), n_buckets = K)]
        
        # By content area
        stability_by_content <- sgpc_with_buckets[, {
          d1 <- as.integer(get(bucket1)); d2 <- as.integer(get(bucket2))
          bucket_diff <- abs(d1 - d2)
          list(
            exact_match = mean(bucket_diff == 0, na.rm = TRUE),
            off_by_1 = mean(bucket_diff == 1, na.rm = TRUE),
            off_by_2plus = mean(bucket_diff >= 2, na.rm = TRUE),
            n = sum(!is.na(bucket_diff)),
            kappa_w = compute_weighted_kappa(d1, d2, K = K, weights = "linear"),
            kappa_w_quad = compute_weighted_kappa(d1, d2, K = K, weights = "quadratic")
          )
        }, by = content_area]
        stability_by_content[, `:=`(comparison = comp_name, stratum = content_area, n_buckets = K)]
        
        individual_bucket_stability_list[[paste0(comp_name, "_K", K)]] <- rbind(
          stability_overall[, .(comparison, stratum, n_buckets, exact_match, off_by_1, off_by_2plus, n, kappa_w, kappa_w_quad)],
          stability_by_year[, .(comparison, stratum, n_buckets, exact_match, off_by_1, off_by_2plus, n, kappa_w, kappa_w_quad)],
          stability_by_content[, .(comparison, stratum, n_buckets, exact_match, off_by_1, off_by_2plus, n, kappa_w, kappa_w_quad)]
        )
        
        if (K == 10L) {
          cat(sprintf("  %s: %.1f%% exact, %.1f%% ±1, %.1f%% ≥2 deciles different | \u03ba_w=%.3f\n",
                      comp_name,
                      stability_overall$exact_match * 100,
                      stability_overall$off_by_1 * 100,
                      stability_overall$off_by_2plus * 100,
                      stability_overall$kappa_w))
        }
      }
    }
  }
  
  individual_bucket_stability <- rbindlist(individual_bucket_stability_list, fill = TRUE)
  
  # Backward-compatible decile-only table for existing consumers
  decile_misclass <- individual_bucket_stability[n_buckets == 10,
    .(comparison, stratum, exact_match, off_by_1, off_by_2plus, n, kappa_w, kappa_w_quad)]
  
  cat("\n")
  
  ############################################################################
  ### D2. GROUP-LEVEL BUCKET STABILITY (School/District)
  ###
  ### For TIMSS/NAEP applications, the analyst only has group-level mean SGPc

  ### (for states/countries).  This section answers: "If we classify groups
  ### into K growth buckets, how stable are those assignments across copula
  ### models?"
  ###
  ### Computes bucket stability for K in {3, 5, 10} (terciles, quintiles,
  ### deciles) at the school and district aggregation levels.
  ############################################################################
  
  cat("Computing group-level bucket stability (K=3,5,10)...\n")
  
  group_bucket_stability_list <- list()
  bucket_sizes <- c(3L, 5L, 10L)
  
  # Helper: compute bucket stability for a given level and K using cached group aggregates
  # Computes both mean-based and median-based bucket assignments, tagged via agg_method column
  compute_bucket_stability <- function(group_cache, min_n, level_label, K) {
    results <- list()
    for (comp_name in names(group_cache)) {
      group_agg <- group_cache[[comp_name]]
      if (is.null(group_agg)) next
      group_agg <- group_agg[n >= min_n]
      if (nrow(group_agg) == 0) next
      
      grp_bucket_by <- if ("dataset_id" %in% names(group_agg)) c("dataset_id", "condition_id") else "condition_id"
      
      # Inner helper: assign buckets, compute stability for a given (val1, val2) pair
      run_bucket_stability <- function(ga, v1_col, v2_col, method_label) {
        ga_copy <- copy(ga)
        ga_copy[, bucket1 := {
          brks <- unique(quantile(get(v1_col), probs = seq(0, 1, 1/K), na.rm = TRUE))
          if (length(brks) < 2) rep(1L, .N)
          else as.integer(cut(get(v1_col), breaks = brks, include.lowest = TRUE))
        }, by = grp_bucket_by]
        
        ga_copy[, bucket2 := {
          brks <- unique(quantile(get(v2_col), probs = seq(0, 1, 1/K), na.rm = TRUE))
          if (length(brks) < 2) rep(1L, .N)
          else as.integer(cut(get(v2_col), breaks = brks, include.lowest = TRUE))
        }, by = grp_bucket_by]
        
        ga_copy <- ga_copy[!is.na(bucket1) & !is.na(bucket2)]
        if (nrow(ga_copy) == 0) return(NULL)
        
        ga_copy[, bucket_diff := abs(bucket1 - bucket2)]
        
        overall <- ga_copy[, .(
          exact_match  = mean(bucket_diff == 0, na.rm = TRUE),
          off_by_1     = mean(bucket_diff == 1, na.rm = TRUE),
          off_by_2plus = mean(bucket_diff >= 2, na.rm = TRUE),
          n_groups     = .N,
          kappa_w      = compute_weighted_kappa(bucket1, bucket2, K = K, weights = "linear"),
          kappa_w_quad = compute_weighted_kappa(bucket1, bucket2, K = K, weights = "quadratic")
        )]
        overall[, `:=`(comparison = comp_name, level = level_label,
                       n_buckets = K, stratum = "Overall", agg_method = method_label)]
        
        by_year <- ga_copy[, .(
          exact_match  = mean(bucket_diff == 0, na.rm = TRUE),
          off_by_1     = mean(bucket_diff == 1, na.rm = TRUE),
          off_by_2plus = mean(bucket_diff >= 2, na.rm = TRUE),
          n_groups     = .N,
          kappa_w      = compute_weighted_kappa(bucket1, bucket2, K = K, weights = "linear"),
          kappa_w_quad = compute_weighted_kappa(bucket1, bucket2, K = K, weights = "quadratic")
        ), by = year_span]
        by_year[, `:=`(comparison = comp_name, level = level_label,
                       n_buckets = K, stratum = paste0("Year_", year_span), agg_method = method_label)]
        
        by_content <- ga_copy[, .(
          exact_match  = mean(bucket_diff == 0, na.rm = TRUE),
          off_by_1     = mean(bucket_diff == 1, na.rm = TRUE),
          off_by_2plus = mean(bucket_diff >= 2, na.rm = TRUE),
          n_groups     = .N,
          kappa_w      = compute_weighted_kappa(bucket1, bucket2, K = K, weights = "linear"),
          kappa_w_quad = compute_weighted_kappa(bucket1, bucket2, K = K, weights = "quadratic")
        ), by = content_area]
        by_content[, `:=`(comparison = comp_name, level = level_label,
                          n_buckets = K, stratum = content_area, agg_method = method_label)]
        
        out_cols <- c("comparison", "level", "n_buckets", "stratum", "agg_method",
                      "exact_match", "off_by_1", "off_by_2plus", "n_groups", "kappa_w", "kappa_w_quad")
        rbind(overall[, ..out_cols], by_year[, ..out_cols], by_content[, ..out_cols])
      }
      
      res_mean   <- run_bucket_stability(group_agg, "mean1", "mean2", "mean")
      res_median <- run_bucket_stability(group_agg, "median1", "median2", "median")
      
      comp_results <- rbindlist(list(res_mean, res_median)[!sapply(list(res_mean, res_median), is.null)])
      if (nrow(comp_results) > 0) results[[comp_name]] <- comp_results
    }
    
    if (length(results) > 0) rbindlist(results) else data.table()
  }
  
  if (has_school) {
    cat("  School-level bucket stability...\n")
    for (K in bucket_sizes) {
      res <- compute_bucket_stability(school_group_cache, 10, "school", K)
      if (nrow(res) > 0) {
        group_bucket_stability_list[[paste0("school_K", K)]] <- res
        ovr <- res[stratum == "Overall"]
        if (nrow(ovr) > 0) {
          cat(sprintf("    K=%d: median exact match = %.1f%% across %d comparisons\n",
                      K, median(ovr$exact_match) * 100, nrow(ovr)))
        }
      }
    }
  }
  
  if (has_district) {
    cat("  District-level bucket stability...\n")
    for (K in bucket_sizes) {
      res <- compute_bucket_stability(district_group_cache, 30, "district", K)
      if (nrow(res) > 0) {
        group_bucket_stability_list[[paste0("district_K", K)]] <- res
        ovr <- res[stratum == "Overall"]
        if (nrow(ovr) > 0) {
          cat(sprintf("    K=%d: median exact match = %.1f%% across %d comparisons\n",
                      K, median(ovr$exact_match) * 100, nrow(ovr)))
        }
      }
    }
  }
  
  group_bucket_stability <- if (length(group_bucket_stability_list) > 0) {
    rbindlist(group_bucket_stability_list, fill = TRUE)
  } else {
    data.table()
  }
  
  if (!has_school && !has_district) {
    cat("  WARNING: No SCHOOL_NUMBER or DISTRICT_NUMBER. Skipping bucket stability.\n")
  }
  
  cat("\n")
  
  ############################################################################
  ### D3. GROUP-LEVEL TRANSITION MATRICES (School/District, policy sample floors)
  ###
  ### Deep-dive companion to D2: instead of only reporting exact/off-by rates,
  ### compute full bucket-to-bucket transition matrices and policy-oriented
  ### error metrics under stricter minimum group sizes.
  ###
  ### Requested sample-size floors:
  ###   - School:   n >= 250 students
  ###   - District: n >= 500 students
  ###
  ### Bucket granularities:
  ###   - Terciles (K=3), Quintiles (K=5), Septiles (K=7), Deciles (K=10)
  ############################################################################
  
  cat("Computing group-level transition matrices (K=3,5,7,10; school>=250, district>=500)...\n")
  
  transition_bucket_sizes <- c(3L, 5L, 7L, 10L)
  group_transition_matrices_list <- list()
  group_transition_metrics_list <- list()
  
  compute_group_transitions <- function(group_cache, min_n, level_label, K) {
    trans_results <- list()
    metric_results <- list()
    
    for (comp_name in names(group_cache)) {
      group_agg <- group_cache[[comp_name]]
      if (is.null(group_agg)) next
      group_agg <- group_agg[n >= min_n]
      if (nrow(group_agg) == 0) next
      
      grp_bucket_by <- if ("dataset_id" %in% names(group_agg)) c("dataset_id", "condition_id") else "condition_id"
      
      run_transition <- function(ga, v1_col, v2_col, method_label) {
        ga_copy <- copy(ga)
        
        ga_copy[, empirical_bucket := {
          brks <- unique(quantile(get(v1_col), probs = seq(0, 1, 1 / K), na.rm = TRUE))
          if (length(brks) < 2) rep(1L, .N)
          else as.integer(cut(get(v1_col), breaks = brks, include.lowest = TRUE))
        }, by = grp_bucket_by]
        
        ga_copy[, comparison_bucket := {
          brks <- unique(quantile(get(v2_col), probs = seq(0, 1, 1 / K), na.rm = TRUE))
          if (length(brks) < 2) rep(1L, .N)
          else as.integer(cut(get(v2_col), breaks = brks, include.lowest = TRUE))
        }, by = grp_bucket_by]
        
        ga_copy <- ga_copy[!is.na(empirical_bucket) & !is.na(comparison_bucket)]
        if (nrow(ga_copy) == 0) return(list(trans = NULL, metrics = NULL))
        
        ga_copy[, bucket_diff := abs(empirical_bucket - comparison_bucket)]
        
        # Full transition matrix (including zero-count cells)
        trans <- ga_copy[, .(n = .N), by = .(empirical_bucket, comparison_bucket)]
        grid <- CJ(empirical_bucket = 1:K, comparison_bucket = 1:K)
        trans <- merge(grid, trans, by = c("empirical_bucket", "comparison_bucket"), all.x = TRUE)
        trans[is.na(n), n := 0L]
        trans[, row_total := sum(n), by = empirical_bucket]
        trans[, row_prop := fifelse(row_total > 0, n / row_total, NA_real_)]
        trans[, `:=`(
          comparison = comp_name,
          level = level_label,
          n_buckets = K,
          agg_method = method_label,
          min_group_n = min_n,
          n_groups_total = nrow(ga_copy)
        )]
        
        # Policy-relevant summary metrics
        emp_top <- ga_copy$empirical_bucket == K
        cmp_top <- ga_copy$comparison_bucket == K
        emp_bot <- ga_copy$empirical_bucket == 1L
        cmp_bot <- ga_copy$comparison_bucket == 1L
        
        tp_top <- sum(emp_top & cmp_top, na.rm = TRUE)
        fp_top <- sum(!emp_top & cmp_top, na.rm = TRUE)
        fn_top <- sum(emp_top & !cmp_top, na.rm = TRUE)
        tn_top <- sum(!emp_top & !cmp_top, na.rm = TRUE)
        
        tp_bot <- sum(emp_bot & cmp_bot, na.rm = TRUE)
        fp_bot <- sum(!emp_bot & cmp_bot, na.rm = TRUE)
        fn_bot <- sum(emp_bot & !cmp_bot, na.rm = TRUE)
        tn_bot <- sum(!emp_bot & !cmp_bot, na.rm = TRUE)
        
        den_non_top <- fp_top + tn_top
        den_top <- tp_top + fn_top
        den_cmp_top <- tp_top + fp_top
        
        den_non_bot <- fp_bot + tn_bot
        den_bot <- tp_bot + fn_bot
        den_cmp_bot <- tp_bot + fp_bot
        
        metrics <- data.table(
          comparison = comp_name,
          level = level_label,
          n_buckets = K,
          agg_method = method_label,
          min_group_n = min_n,
          n_groups = nrow(ga_copy),
          exact_match = mean(ga_copy$bucket_diff == 0, na.rm = TRUE),
          off_by_1 = mean(ga_copy$bucket_diff == 1, na.rm = TRUE),
          off_by_2plus = mean(ga_copy$bucket_diff >= 2, na.rm = TRUE),
          spearman_rho = tryCatch(
            cor(as.double(ga_copy[[v1_col]]), as.double(ga_copy[[v2_col]]), method = "spearman", use = "complete.obs"),
            error = function(e) NA_real_
          ),
          kappa_w = compute_weighted_kappa(ga_copy$empirical_bucket, ga_copy$comparison_bucket, K = K, weights = "linear"),
          kappa_w_quad = compute_weighted_kappa(ga_copy$empirical_bucket, ga_copy$comparison_bucket, K = K, weights = "quadratic"),
          fpr_top = ifelse(den_non_top > 0, fp_top / den_non_top, NA_real_),
          fnr_top = ifelse(den_top > 0, fn_top / den_top, NA_real_),
          fpr_bottom = ifelse(den_non_bot > 0, fp_bot / den_non_bot, NA_real_),
          fnr_bottom = ifelse(den_bot > 0, fn_bot / den_bot, NA_real_),
          p_comp_top_given_emp_top = ifelse(den_top > 0, tp_top / den_top, NA_real_),
          p_emp_top_given_comp_top = ifelse(den_cmp_top > 0, tp_top / den_cmp_top, NA_real_),
          p_comp_bottom_given_emp_bottom = ifelse(den_bot > 0, tp_bot / den_bot, NA_real_),
          p_emp_bottom_given_comp_bottom = ifelse(den_cmp_bot > 0, tp_bot / den_cmp_bot, NA_real_)
        )
        
        list(trans = trans, metrics = metrics)
      }
      
      res_mean <- run_transition(group_agg, "mean1", "mean2", "mean")
      res_median <- run_transition(group_agg, "median1", "median2", "median")
      
      if (!is.null(res_mean$trans))  trans_results[[paste0(comp_name, "_mean")]] <- res_mean$trans
      if (!is.null(res_median$trans)) trans_results[[paste0(comp_name, "_median")]] <- res_median$trans
      if (!is.null(res_mean$metrics))  metric_results[[paste0(comp_name, "_mean")]] <- res_mean$metrics
      if (!is.null(res_median$metrics)) metric_results[[paste0(comp_name, "_median")]] <- res_median$metrics
    }
    
    list(
      transitions = if (length(trans_results) > 0) rbindlist(trans_results, fill = TRUE) else data.table(),
      metrics = if (length(metric_results) > 0) rbindlist(metric_results, fill = TRUE) else data.table()
    )
  }
  
  if (has_school) {
    cat("  School-level transitions...\n")
    for (K in transition_bucket_sizes) {
      res <- compute_group_transitions(school_group_cache, 250L, "school", K)
      if (nrow(res$transitions) > 0) {
        group_transition_matrices_list[[paste0("school_K", K)]] <- res$transitions
      }
      if (nrow(res$metrics) > 0) {
        group_transition_metrics_list[[paste0("school_K", K)]] <- res$metrics
      }
      ovr <- res$metrics[comparison == "Empirical – Canonical" & agg_method == "mean"]
      if (nrow(ovr) > 0) {
        cat(sprintf("    K=%d: canonical exact match = %.1f%% (n_groups=%s)\n",
                    K, ovr$exact_match[1] * 100, format(ovr$n_groups[1], big.mark = ",")))
      }
    }
  }
  
  if (has_district) {
    cat("  District-level transitions...\n")
    for (K in transition_bucket_sizes) {
      res <- compute_group_transitions(district_group_cache, 500L, "district", K)
      if (nrow(res$transitions) > 0) {
        group_transition_matrices_list[[paste0("district_K", K)]] <- res$transitions
      }
      if (nrow(res$metrics) > 0) {
        group_transition_metrics_list[[paste0("district_K", K)]] <- res$metrics
      }
      ovr <- res$metrics[comparison == "Empirical – Canonical" & agg_method == "mean"]
      if (nrow(ovr) > 0) {
        cat(sprintf("    K=%d: canonical exact match = %.1f%% (n_groups=%s)\n",
                    K, ovr$exact_match[1] * 100, format(ovr$n_groups[1], big.mark = ",")))
      }
    }
  }
  
  group_transition_matrices <- if (length(group_transition_matrices_list) > 0) {
    rbindlist(group_transition_matrices_list, fill = TRUE)
  } else {
    data.table()
  }
  
  group_transition_metrics <- if (length(group_transition_metrics_list) > 0) {
    rbindlist(group_transition_metrics_list, fill = TRUE)
  } else {
    data.table()
  }
  
  if (!has_school && !has_district) {
    cat("  WARNING: No SCHOOL_NUMBER or DISTRICT_NUMBER. Skipping transition matrices.\n")
  }
  
  cat("\n")
  
  ############################################################################
  ### E. PRIOR ACHIEVEMENT QUARTILE STATISTICS
  ############################################################################
  
  cat("Computing prior achievement quartile statistics...\n")
  
  prior_quartile_stats <- list()
  prior_quartile_raw <- list()
  prior_quartile_combined <- data.table()
  prior_quartile_raw_combined <- data.table()
  
  if (!"SCALE_SCORE_PRIOR" %in% names(sgpc_data) || all(is.na(sgpc_data$SCALE_SCORE_PRIOR))) {
    cat("  WARNING: SCALE_SCORE_PRIOR not available. Skipping quartile analysis.\n\n")
  } else {
  
  # Create prior quartile variable
  sgpc_data[, prior_quartile := cut(
    SCALE_SCORE_PRIOR,
    breaks = quantile(SCALE_SCORE_PRIOR, probs = 0:4/4, na.rm = TRUE),
    labels = c("Q1 (Low)", "Q2", "Q3", "Q4 (High)"),
    include.lowest = TRUE
  )]
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    if (all(is.na(sgpc_data[[var1]])) || all(is.na(sgpc_data[[var2]]))) next
    
    # Compute statistics within each quartile
    # Note: as.double() ensures type consistency across groups (data.table requirement)
    q_stats <- sgpc_data[!is.na(prior_quartile) & !is.na(get(var1)) & !is.na(get(var2)), {
      delta <- as.double(abs(get(var1) - get(var2)))
      list(
        n = .N,
        mad = mean(delta, na.rm = TRUE),
        median_abs_diff = median(delta, na.rm = TRUE),
        q90 = as.double(quantile(delta, 0.90, na.rm = TRUE)),
        q95 = as.double(quantile(delta, 0.95, na.rm = TRUE)),
        exceedance_5 = mean(delta > 5, na.rm = TRUE),
        exceedance_10 = mean(delta > 10, na.rm = TRUE),
        correlation = tryCatch(
          cor(as.double(get(var1)), as.double(get(var2)), use = "complete.obs"),
          error = function(e) NA_real_
        )
      )
    }, by = prior_quartile]
    
    q_stats[, comparison := comp_name]
    prior_quartile_stats[[comp_name]] <- q_stats
    
    cat(sprintf("  %s: MAD by quartile = %.1f / %.1f / %.1f / %.1f\n",
                comp_name,
                q_stats[prior_quartile == "Q1 (Low)", mad],
                q_stats[prior_quartile == "Q2", mad],
                q_stats[prior_quartile == "Q3", mad],
                q_stats[prior_quartile == "Q4 (High)", mad]))
  }
  
  prior_quartile_combined <- if (length(prior_quartile_stats) > 0) {
    rbindlist(prior_quartile_stats)
  } else {
    data.table()
  }
  
  # Also compute raw individual differences by quartile (for violin/ridgeline plots)
  prior_quartile_raw <- list()
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    if (all(is.na(sgpc_data[[var1]])) || all(is.na(sgpc_data[[var2]]))) next
    
    raw <- sgpc_data[!is.na(prior_quartile) & !is.na(get(var1)) & !is.na(get(var2)),
                     .(prior_quartile, delta = as.double(abs(get(var1) - get(var2))))]
    raw[, comparison := comp_name]
    prior_quartile_raw[[comp_name]] <- raw
  }
  
  prior_quartile_raw_combined <- if (length(prior_quartile_raw) > 0) {
    rbindlist(prior_quartile_raw)
  } else {
    data.table()
  }
  
  } # end SCALE_SCORE_PRIOR guard
  
  cat("\n")
  
  ############################################################################
  ### F. PER-DATASET STATISTICS (Cross-Dataset Generalizability)
  ############################################################################
  
  cat("Computing per-dataset statistics (cross-dataset generalizability)...\n")
  
  # Use existing dataset_id if available; otherwise try to extract from condition_id
  if (!"dataset_id" %in% names(sgpc_data)) {
    sgpc_data[, dataset_id := sub("^(dataset_[0-9]+)_.*", "\\1", condition_id)]
  }
  
  by_dataset_stats <- list()
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    if (all(is.na(sgpc_data[[var1]])) || all(is.na(sgpc_data[[var2]]))) next
    
    ds_stats <- sgpc_data[!is.na(get(var1)) & !is.na(get(var2)), {
      v1 <- as.double(get(var1))
      v2 <- as.double(get(var2))
      delta <- abs(v1 - v2)
      list(
        n = .N,
        n_conditions = uniqueN(condition_id),
        mad = mean(delta, na.rm = TRUE),
        median_abs_diff = median(delta, na.rm = TRUE),
        rmsd = sqrt(mean((v1 - v2)^2, na.rm = TRUE)),
        correlation = tryCatch(
          cor(v1, v2, use = "complete.obs"),
          error = function(e) NA_real_
        ),
        spearman_rho = tryCatch(
          cor(v1, v2, method = "spearman", use = "complete.obs"),
          error = function(e) NA_real_
        )
      )
    }, by = dataset_id]
    
    ds_stats[, comparison := comp_name]
    by_dataset_stats[[comp_name]] <- ds_stats
    
    cat(sprintf("  %s: MAD by dataset = %s\n",
                comp_name,
                paste(sprintf("%s:%.1f", ds_stats$dataset_id, ds_stats$mad), collapse = " | ")))
  }
  
  by_dataset_combined <- if (length(by_dataset_stats) > 0) {
    rbindlist(by_dataset_stats)
  } else {
    data.table()
  }
  
  cat("\n")
  
  ############################################################################
  ### G. CONDITION-LEVEL STATISTICS (N vs MAD per condition)
  ############################################################################
  
  cat("Computing condition-level statistics (N vs MAD for Panel J)...\n")
  
  # Build a single vectorized computation of per-condition MAD for all pairs
  # using data.table grouping (fast, no loops over rows)
  condition_level_list <- list()
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    if (all(is.na(sgpc_data[[var1]])) || all(is.na(sgpc_data[[var2]]))) next
    
    cond_stats <- sgpc_data[!is.na(get(var1)) & !is.na(get(var2)), {
      v1 <- as.double(get(var1))
      v2 <- as.double(get(var2))
      delta <- abs(v1 - v2)
      list(
        n = .N,
        mad = mean(delta, na.rm = TRUE),
        median_abs_diff = as.double(median(delta, na.rm = TRUE)),
        rmsd = sqrt(mean((v1 - v2)^2, na.rm = TRUE)),
        q90 = as.double(quantile(delta, 0.90, na.rm = TRUE)),
        q95 = as.double(quantile(delta, 0.95, na.rm = TRUE)),
        spearman_rho = tryCatch(
          cor(v1, v2, method = "spearman", use = "complete.obs"),
          error = function(e) NA_real_
        )
      )
    }, by = c(if (has_dataset_id) "dataset_id", "condition_id", "year_span", "content_area")]
    
    cond_stats[, comparison := comp_name]
    condition_level_list[[comp_name]] <- cond_stats
  }
  
  condition_level_stats <- if (length(condition_level_list) > 0) {
    rbindlist(condition_level_list)
  } else {
    data.table()
  }
  
  if (nrow(condition_level_stats) > 0) {
    # Summary: median condition-level MAD and range of N
    n_range <- range(condition_level_stats$n)
    n_unique_conditions <- if ("dataset_id" %in% names(condition_level_stats)) {
      uniqueN(condition_level_stats[, paste(dataset_id, condition_id, sep = "__")])
    } else {
      uniqueN(condition_level_stats$condition_id)
    }
    cat(sprintf("  Conditions: %d unique, N range: %s - %s\n",
                n_unique_conditions,
                format(n_range[1], big.mark = ","),
                format(n_range[2], big.mark = ",")))
    
    # Report median MAD per comparison
    summ <- condition_level_stats[, .(
      median_mad = round(median(mad, na.rm = TRUE), 2),
      median_n = as.integer(median(n))
    ), by = comparison]
    for (i in seq_len(nrow(summ))) {
      cat(sprintf("  %s: median condition MAD=%.2f (median n=%s)\n",
                  summ$comparison[i], summ$median_mad[i],
                  format(summ$median_n[i], big.mark = ",")))
    }
  }
  
  cat("\n")
  
  cat("====================================================================\n")
  cat("ENHANCED STATISTICS COMPUTATION COMPLETE\n")
  cat("====================================================================\n\n")
  
  ############################################################################
  ### RETURN RESULTS
  ############################################################################
  
  result <- list(
    # Individual-level ECDF and statistics
    individual_stats = list(
      by_comparison = individual_stats,
      all_ecdf_data = all_ecdf_data
    ),
    # School-level group statistics (mean- and median-based)
    group_stats = if (length(group_stats) > 0) {
      list(
        by_comparison = group_stats,
        all_group_ecdf_data        = all_group_ecdf_data,
        all_group_ecdf_data_mean   = all_group_ecdf_data_mean,
        all_group_ecdf_data_median = all_group_ecdf_data_median
      )
    } else {
      NULL
    },
    # District-level group statistics (TIMSS country / NAEP state surrogate, mean- and median-based)
    district_stats = if (length(district_stats) > 0) {
      list(
        by_comparison = district_stats,
        all_district_ecdf_data        = all_district_ecdf_data,
        all_district_ecdf_data_mean   = all_district_ecdf_data_mean,
        all_district_ecdf_data_median = all_district_ecdf_data_median
      )
    } else {
      NULL
    },
    # Group-size stratification (sqrt(n) averaging effect)
    group_size_analysis = if (length(group_size_analysis) > 0) group_size_analysis else NULL,
    # Individual-level rank agreement (Spearman rho by condition)
    rank_agreement = rank_agreement,
    # Group-level rank agreement (school/district rank preservation)
    group_rank_agreement = group_rank_agreement,
    # Individual-level classification stability (K=3,5,10)
    individual_bucket_stability = individual_bucket_stability,
    # Backward-compatible decile-only view (K=10)
    decile_misclass = decile_misclass,
    classification_issues = if (length(classification_issues) > 0) classification_issues else NULL,
    # Group-level bucket stability (K=3,5,10 for school/district)
    group_bucket_stability = group_bucket_stability,
    # Group-level transition matrices and policy metrics for D3 (K=5,7,10; stricter min_n)
    group_transition_matrices = group_transition_matrices,
    group_transition_metrics = group_transition_metrics,
    # Prior achievement quartile statistics
    prior_quartile_stats = list(
      summary = prior_quartile_combined,
      raw = prior_quartile_raw_combined
    ),
    # Per-dataset statistics (cross-dataset generalizability)
    by_dataset_stats = by_dataset_combined,
    # Condition-level statistics (N vs MAD for Panel J)
    condition_level_stats = condition_level_stats,
    # Comparison pairs used
    comparison_pairs = comparison_pairs
  )
  
  return(result)
}

############################################################################
### STANDALONE EXECUTION (if run directly)
############################################################################

############################################################################
### compute_sampling_sensitivity()
###
### Bootstrap-of-existing-differences approach:
### The sgpc_data already contains individual-level SGPc under every copula
### variant (sgpc_emp, sgpc_best, sgpc_gaussian, etc.).  Instead of
### refitting copulas at each subsample, we simply:
###   1. Draw N students from a condition (data.table row sampling)
###   2. Compute MAD, RMSD, Spearman rho on that subsample using the
###      pre-computed SGPc columns
###   3. Repeat B times per (comparison_pair x sample_size x condition)
###
### This decomposes the "observed insensitivity" into two dimensions:
###   - Comparison-pair effect: which pairs show larger differences?
###   - Sample-size effect: how stable is the summary statistic at smaller N?
###
### Performance: pure data.table aggregation, no copula fitting,
### no sgpc_engine.  Runs in ~10-30 seconds.
############################################################################

#' Bootstrap sampling sensitivity of pre-computed SGPc differences
#'
#' @param sgpc_data data.table with all SGPc variant columns and condition_id
#' @param sample_sizes Integer vector of sub-sample sizes to evaluate.
#'        Default: c(500, 1000, 2000, 4000).
#' @param B Number of bootstrap replicates per cell. Default: 50.
#' @param comparison_pairs Named list of comparison pairs (column name pairs).
#' @param conditions Character vector of condition_ids to include.
#'        Default NULL = pick the largest conditions automatically.
#' @param max_conditions Maximum number of conditions when conditions is NULL.
#' @param seed Random seed for reproducibility. Default: 42.
#' @return A list with components:
#'   \describe{
#'     \item{replicate_results}{data.table: one row per (condition, comparison,
#'       sample_size, replicate) with MAD, RMSD, Spearman rho.}
#'     \item{cell_summary}{data.table: mean/sd/quantiles of MAD and RMSD
#'       per (comparison, sample_size) cell.}
#'     \item{error_decomposition}{data.table: ANOVA-style variance decomposition
#'       of MAD into comparison, sample-size, and interaction components.}
#'     \item{per_ss_decomposition}{data.table: per-sample-size partition of
#'       variance into comparison vs sampling shares.}
#'     \item{metadata}{list: arguments and timing.}
#'   }
compute_sampling_sensitivity <- function(
    sgpc_data,
    sample_sizes = c(500L, 1000L, 2000L, 4000L),
    B = 50L,
    comparison_pairs = list(
      "Empirical \u2013 Best-Fit Parametric"      = c("sgpc_emp", "sgpc_best"),
      "Empirical \u2013 Canonical"      = c("sgpc_emp", "sgpc_avg"),
      "Empirical \u2013 Gaussian"                  = c("sgpc_emp", "sgpc_gaussian"),
      "Empirical \u2013 Gumbel"                    = c("sgpc_emp", "sgpc_gumbel"),
      "Empirical \u2013 Frank"                     = c("sgpc_emp", "sgpc_frank"),
      "Empirical \u2013 Clayton"                   = c("sgpc_emp", "sgpc_clayton"),
      "Empirical \u2013 t (Student)"               = c("sgpc_emp", "sgpc_t"),
      "Empirical \u2013 B-spline SGP" = c("sgpc_emp", "sgp_traditional")
    ),
    conditions = NULL,
    max_conditions = 5L,
    seed = 42L
) {

  require(data.table)

  t0 <- Sys.time()
  set.seed(seed)

  cat("====================================================================\n")
  cat("SAMPLING SENSITIVITY ANALYSIS (Bootstrap of Existing Differences)\n")
  cat("====================================================================\n\n")

  ############################################################################
  ### 1. VALIDATE COMPARISON PAIRS (drop any with all-NA columns)
  ############################################################################

  valid_pairs <- list()
  for (nm in names(comparison_pairs)) {
    cols <- comparison_pairs[[nm]]
    if (all(cols %in% names(sgpc_data)) &&
        !all(is.na(sgpc_data[[cols[1]]])) &&
        !all(is.na(sgpc_data[[cols[2]]]))) {
      valid_pairs[[nm]] <- cols
    } else {
      cat(sprintf("  Skipping %s: column missing or all-NA\n", nm))
    }
  }
  comparison_pairs <- valid_pairs

  if (length(comparison_pairs) == 0) {
    stop("No valid comparison pairs found in the data.")
  }

  cat(sprintf("Comparison pairs: %d\n", length(comparison_pairs)))
  for (nm in names(comparison_pairs)) {
    cat(sprintf("  %s: %s vs %s\n", nm,
                comparison_pairs[[nm]][1], comparison_pairs[[nm]][2]))
  }

  ############################################################################
  ### 2. SELECT CONDITIONS
  ############################################################################

  max_n <- max(sample_sizes)

  # Count students per condition
  cond_n <- sgpc_data[, .N, by = condition_id]
  setorder(cond_n, -N)

  eligible <- cond_n[N >= max_n * 1.1]  # 10% margin

  if (nrow(eligible) == 0) {
    cat("WARNING: No condition large enough for the largest subsample.\n")
    for (ss in rev(sample_sizes)) {
      eligible <- cond_n[N >= ss * 1.1]
      if (nrow(eligible) > 0) {
        sample_sizes <- sample_sizes[sample_sizes <= ss]
        cat(sprintf("  Reduced sample sizes to: %s\n",
                    paste(format(sample_sizes, big.mark = ","), collapse = ", ")))
        break
      }
    }
    if (nrow(eligible) == 0) {
      stop("No conditions are large enough for even the smallest subsample.")
    }
  }

  if (is.null(conditions)) {
    conditions <- eligible$condition_id[seq_len(min(max_conditions, nrow(eligible)))]
  } else {
    missing <- setdiff(conditions, eligible$condition_id)
    if (length(missing) > 0) {
      cat(sprintf("  Dropping conditions too small: %s\n",
                  paste(missing, collapse = ", ")))
      conditions <- intersect(conditions, eligible$condition_id)
    }
  }

  cat(sprintf("Conditions: %d\n", length(conditions)))
  for (cc in conditions) {
    cat(sprintf("  %s (N=%s)\n", cc,
                format(cond_n[condition_id == cc, N], big.mark = ",")))
  }
  cat(sprintf("Sample sizes: %s\n",
              paste(format(sample_sizes, big.mark = ","), collapse = ", ")))
  cat(sprintf("Replicates per cell: %d\n", B))

  total_cells <- length(conditions) * length(comparison_pairs) * length(sample_sizes) * B
  cat(sprintf("Total bootstrap units: %s\n\n",
              format(total_cells, big.mark = ",")))

  ############################################################################
  ### 3. BOOTSTRAP LOOP: Condition x ComparisonPair x SampleSize x Replicate
  ###    Pure data.table subsampling -- no copula fitting, no sgpc_engine
  ############################################################################

  cat("Running bootstrap subsampling...\n")

  # Pre-allocate result list
  result_list <- vector("list", total_cells)
  idx <- 0L

  n_conditions <- length(conditions)
  progress_total <- n_conditions * length(sample_sizes) * length(comparison_pairs)
  progress_counter <- 0L
  progress_pct_last <- -1L

  for (ci in seq_along(conditions)) {
    cond_id <- conditions[ci]

    # Extract this condition's data once
    cond_dt <- sgpc_data[condition_id == cond_id]
    cond_N <- nrow(cond_dt)

    cat(sprintf("  [%d/%d] %s (N=%s)\n", ci, n_conditions, cond_id,
                format(cond_N, big.mark = ",")))

    for (ss in sample_sizes) {
      for (comp_name in names(comparison_pairs)) {
        progress_counter <- progress_counter + 1L
        progress_pct <- as.integer(100 * progress_counter / progress_total)
        if (progress_pct %% 10 == 0 && progress_pct != progress_pct_last) {
          cat(sprintf("    %d%% complete\n", progress_pct))
          progress_pct_last <- progress_pct
        }

        var1 <- comparison_pairs[[comp_name]][1]
        var2 <- comparison_pairs[[comp_name]][2]

        # Pre-extract the two columns as double vectors (avoid repeated get())
        v1_full <- as.double(cond_dt[[var1]])
        v2_full <- as.double(cond_dt[[var2]])

        for (b in seq_len(B)) {
          idx <- idx + 1L

          # Subsample without replacement
          rows <- sample.int(cond_N, size = ss, replace = FALSE)
          v1 <- v1_full[rows]
          v2 <- v2_full[rows]

          # Remove NAs
          valid_mask <- !is.na(v1) & !is.na(v2)
          n_valid <- sum(valid_mask)

          if (n_valid < 10L) {
            result_list[[idx]] <- data.table(
              condition_id = cond_id,
              comparison = comp_name,
              sample_size = ss,
              replicate = b,
              mad = NA_real_,
              rmsd = NA_real_,
              spearman_rho = NA_real_,
              median_abs_diff = NA_real_,
              max_abs_diff = NA_real_,
              n_compared = n_valid
            )
            next
          }

          v1v <- v1[valid_mask]
          v2v <- v2[valid_mask]
          delta <- abs(v1v - v2v)

          result_list[[idx]] <- data.table(
            condition_id = cond_id,
            comparison = comp_name,
            sample_size = ss,
            replicate = b,
            mad = mean(delta),
            rmsd = sqrt(mean(delta^2)),
            spearman_rho = tryCatch(
              cor(v1v, v2v, method = "spearman", use = "complete.obs"),
              error = function(e) NA_real_
            ),
            median_abs_diff = as.double(median(delta)),
            max_abs_diff = max(delta),
            n_compared = n_valid
          )
        } # end replicates
      } # end comparison_pairs
    } # end sample_sizes
  } # end conditions

  cat("  100% complete\n\n")

  # Combine all results with one rbindlist call
  replicate_results <- rbindlist(result_list, use.names = TRUE)

  ############################################################################
  ### 4. CELL-LEVEL SUMMARY: Comparison x SampleSize
  ############################################################################

  cat("Computing factorial cell summaries...\n")

  cell_summary <- replicate_results[!is.na(mad), {
    list(
      n_replicates = .N,
      n_conditions = uniqueN(condition_id),
      mad_mean = mean(mad),
      mad_sd = sd(mad),
      mad_q05 = as.double(quantile(mad, 0.05)),
      mad_q25 = as.double(quantile(mad, 0.25)),
      mad_median = as.double(median(mad)),
      mad_q75 = as.double(quantile(mad, 0.75)),
      mad_q95 = as.double(quantile(mad, 0.95)),
      rmsd_mean = mean(rmsd),
      rmsd_sd = sd(rmsd),
      rho_mean = mean(spearman_rho, na.rm = TRUE),
      rho_sd = sd(spearman_rho, na.rm = TRUE)
    )
  }, by = .(comparison, sample_size)]

  setorder(cell_summary, sample_size, comparison)

  cat("  Factorial table (Comparison x Sample Size):\n")
  cat(sprintf("  %-18s  %-6s  %8s  %8s  %8s  %8s\n",
              "Comparison", "N", "MAD.mean", "MAD.sd", "RMSD.mean", "Rho.mean"))
  cat(paste0("  ", strrep("-", 68), "\n"))
  for (i in seq_len(nrow(cell_summary))) {
    r <- cell_summary[i]
    cat(sprintf("  %-18s  %6s  %8.2f  %8.2f  %8.2f  %8.3f\n",
                r$comparison, format(r$sample_size, big.mark = ","),
                r$mad_mean, r$mad_sd, r$rmsd_mean, r$rho_mean))
  }
  cat("\n")

  ############################################################################
  ### 5. ERROR DECOMPOSITION: comparison vs sampling variance
  ############################################################################

  cat("Decomposing error variance (comparison vs sampling vs interaction)...\n")

  valid_reps <- replicate_results[!is.na(mad)]
  grand_mean <- mean(valid_reps$mad)

  # Comparison marginal means
  comp_means <- valid_reps[, .(comp_mean = mean(mad)), by = comparison]

  # Sample size marginal means
  ss_means <- valid_reps[, .(ss_mean = mean(mad)), by = sample_size]

  # Cell means (comparison x sample_size)
  cell_means <- valid_reps[, .(cell_mean = mean(mad)), by = .(comparison, sample_size)]

  # SS_comparison
  comp_counts <- valid_reps[, .N, by = comparison]
  ss_comparison <- sum(comp_counts$N * (comp_means$comp_mean - grand_mean)^2)

  # SS_sample_size
  ss_counts <- valid_reps[, .N, by = sample_size]
  ss_sample <- sum(ss_counts$N * (ss_means$ss_mean - grand_mean)^2)

  # SS_total
  ss_total <- sum((valid_reps$mad - grand_mean)^2)

  # SS_cells
  cell_details <- merge(cell_means, valid_reps[, .N, by = .(comparison, sample_size)],
                        by = c("comparison", "sample_size"))
  ss_cells <- sum(cell_details$N * (cell_details$cell_mean - grand_mean)^2)

  # SS_interaction = SS_cells - SS_comparison - SS_sample
  ss_interaction <- max(0, ss_cells - ss_comparison - ss_sample)

  # SS_residual = SS_total - SS_cells
  ss_residual <- max(0, ss_total - ss_cells)

  error_decomposition <- data.table(
    source = c("comparison", "sample_size", "interaction", "residual", "total"),
    sum_of_squares = c(ss_comparison, ss_sample, ss_interaction, ss_residual, ss_total),
    proportion = c(
      ss_comparison / ss_total,
      ss_sample / ss_total,
      ss_interaction / ss_total,
      ss_residual / ss_total,
      1.0
    )
  )

  cat("  Error decomposition of MAD:\n")
  for (i in seq_len(nrow(error_decomposition))) {
    r <- error_decomposition[i]
    cat(sprintf("    %-15s  SS=%10.1f  (%.1f%%)\n",
                r$source, r$sum_of_squares, r$proportion * 100))
  }
  cat("\n")

  # Per-sample-size decomposition (comparison vs sampling at each N)
  # Feeds the variance-share stacked area in Panel I
  per_ss_decomposition <- valid_reps[, {
    gm <- mean(mad)
    cm <- .SD[, .(cm = mean(mad)), by = comparison]
    comparison_var <- var(cm$cm)         # between-comparison variance of MAD means
    within_var <- mean(.SD[, .(wv = var(mad)), by = comparison]$wv)  # within-comparison variance
    list(
      grand_mean = gm,
      comparison_var = comparison_var,
      sampling_var = within_var,
      total_var = var(mad),
      comparison_share = comparison_var / (comparison_var + within_var + 1e-12),
      sampling_share = within_var / (comparison_var + within_var + 1e-12)
    )
  }, by = sample_size]

  setorder(per_ss_decomposition, sample_size)

  cat("  Per-sample-size variance partition:\n")
  cat(sprintf("  %6s  %10s  %10s  %10s  %8s  %8s\n",
              "N", "Comp.var", "Samp.var", "Total.var", "%Comp", "%Samp"))
  for (i in seq_len(nrow(per_ss_decomposition))) {
    r <- per_ss_decomposition[i]
    cat(sprintf("  %6s  %10.3f  %10.3f  %10.3f  %7.1f%%  %7.1f%%\n",
                format(r$sample_size, big.mark = ","),
                r$comparison_var, r$sampling_var, r$total_var,
                r$comparison_share * 100, r$sampling_share * 100))
  }

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("\nSampling sensitivity analysis complete in %.1f seconds.\n\n", elapsed))

  list(
    replicate_results = replicate_results,
    cell_summary = cell_summary,
    error_decomposition = error_decomposition,
    per_ss_decomposition = per_ss_decomposition,
    metadata = list(
      sample_sizes = sample_sizes,
      B = B,
      comparison_pairs = names(comparison_pairs),
      conditions = conditions,
      seed = seed,
      elapsed_seconds = elapsed
    )
  )
}


############################################################################
### STANDALONE EXECUTION (if run directly)
############################################################################

if (!interactive() || exists("STANDALONE_MODE")) {
  cat("Running in standalone mode...\n\n")
  
  # Load data
  RESULTS_DIR <- "STEP_2_SGPc_Sensitivity/results"
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
  
  # Compute enhanced statistics
  enhanced_stats <- compute_enhanced_statistics(sgpc_data)
  
  # Save results
  output_file <- file.path(RESULTS_DIR, "sgpc_enhanced_stats.rds")
  saveRDS(enhanced_stats, output_file)
  cat(sprintf("\n✓ Enhanced statistics saved to: %s\n", output_file))
}
