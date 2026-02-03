############################################################################
### STEP 2: SGPc Sensitivity Analysis - Enhanced Statistics
###
### Purpose: Compute additional statistics for publication-grade visualizations
###          - Individual-level quantiles and exceedance rates
###          - Group-level aggregates (school/district means)
###          - Rank agreement (Spearman correlations by condition)
###          - Decile misclassification rates
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)

#' Compute enhanced statistics for SGPc sensitivity analysis
#' 
#' @param sgpc_data data.table with all SGPc variants (from sgpc_all_variants_*.rds)
#' @param comparison_pairs Named list of comparison pairs (default: all 5 key comparisons)
#' @return List with individual_stats, group_stats, rank_agreement, decile_misclass
compute_enhanced_statistics <- function(
  sgpc_data,
  comparison_pairs = list(
    "Emp-Best" = c("sgpc_emp", "sgpc_best"),
    "Emp-Canonical" = c("sgpc_emp", "sgpc_avg"),
    "Best-Canonical" = c("sgpc_best", "sgpc_avg"),
    "Emp-Gaussian" = c("sgpc_emp", "sgpc_gaussian"),
    "Emp-Comonotonic" = c("sgpc_emp", "sgpc_comonotonic")
  )
) {
  
  cat("====================================================================\n")
  cat("COMPUTING ENHANCED STATISTICS FOR PUBLICATION FIGURES\n")
  cat("====================================================================\n\n")
  
  cat("Input data:\n")
  cat("  Observations:", nrow(sgpc_data), "\n")
  cat("  Conditions:", uniqueN(sgpc_data$condition_id), "\n")
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
  ### B. GROUP-LEVEL STATISTICS
  ############################################################################
  
  cat("Computing group-level statistics (school/district aggregates)...\n")
  
  group_stats <- list()
  
  # Check if school/district IDs are available
  has_school <- "SCHOOL_NUMBER" %in% names(sgpc_data) && sum(!is.na(sgpc_data$SCHOOL_NUMBER)) > 0
  has_district <- "DISTRICT_NUMBER" %in% names(sgpc_data) && sum(!is.na(sgpc_data$DISTRICT_NUMBER)) > 0
  
  if (!has_school && !has_district) {
    cat("  WARNING: No SCHOOL_NUMBER or DISTRICT_NUMBER found. Skipping group aggregation.\n")
    cat("  Re-run Step 2.1 with updated sgpc_compute_all_variants.R to include these IDs.\n\n")
  } else {
    # Use SCHOOL_NUMBER as primary grouping
    group_var <- if (has_school) "SCHOOL_NUMBER" else "DISTRICT_NUMBER"
    cat(sprintf("  Grouping by: %s\n", group_var))
    
    for (comp_name in names(comparison_pairs)) {
      var1 <- comparison_pairs[[comp_name]][1]
      var2 <- comparison_pairs[[comp_name]][2]
      
      # Aggregate by group
      group_means <- sgpc_data[!is.na(get(group_var)), .(
        mean_var1 = mean(get(var1), na.rm = TRUE),
        mean_var2 = mean(get(var2), na.rm = TRUE),
        n = .N
      ), by = c(group_var, "condition_id")]
      
      setnames(group_means, c("mean_var1", "mean_var2"), c("mean1", "mean2"))
      
      # Compute group-level differences
      group_means[, delta_group := abs(mean1 - mean2)]
      
      # Filter out very small groups (n < 10 for stability)
      group_means_filtered <- group_means[n >= 10]
      
      # Quantiles of group differences
      if (nrow(group_means_filtered) > 0) {
        group_quantiles <- quantile(group_means_filtered$delta_group, 
                                     probs = c(0.50, 0.90, 0.95), na.rm = TRUE)
        
        # ECDF data for plotting
        delta_sorted <- sort(group_means_filtered$delta_group)
        group_ecdf_data <- data.table(
          comparison = comp_name,
          delta_group = delta_sorted,
          cumulative_pct = seq_along(delta_sorted) / length(delta_sorted)
        )
        
        group_stats[[comp_name]] <- list(
          comparison = comp_name,
          var1 = var1,
          var2 = var2,
          n_groups = nrow(group_means_filtered),
          median_group_delta = group_quantiles["50%"],
          q90_group_delta = group_quantiles["90%"],
          q95_group_delta = group_quantiles["95%"],
          group_ecdf_data = group_ecdf_data,
          group_means_full = group_means_filtered
        )
        
        cat(sprintf("  %s: %d groups, median group Δ=%.1f (vs individual median=%.1f)\n",
                    comp_name, nrow(group_means_filtered),
                    group_quantiles["50%"], 
                    individual_stats[[comp_name]]$median))
      }
    }
    
    # Combine all group ECDF data
    if (length(group_stats) > 0) {
      all_group_ecdf_data <- rbindlist(lapply(group_stats, function(x) x$group_ecdf_data))
    } else {
      all_group_ecdf_data <- data.table()
    }
  }
  
  cat("\n")
  
  ############################################################################
  ### C. RANK AGREEMENT (Spearman correlations by condition)
  ############################################################################
  
  cat("Computing rank agreement (Spearman ρ by condition)...\n")
  
  rank_agreement_list <- list()
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    # Compute Spearman correlation for each condition
    rho_by_condition <- sgpc_data[, .(
      rho = cor(get(var1), get(var2), method = "spearman", use = "complete.obs"),
      n = sum(!is.na(get(var1)) & !is.na(get(var2)))
    ), by = .(condition_id, year_span, content_area)]
    
    rho_by_condition[, comparison := comp_name]
    
    rank_agreement_list[[comp_name]] <- rho_by_condition
    
    cat(sprintf("  %s: median ρ=%.4f, min ρ=%.4f\n",
                comp_name, 
                median(rho_by_condition$rho, na.rm = TRUE),
                min(rho_by_condition$rho, na.rm = TRUE)))
  }
  
  rank_agreement <- rbindlist(rank_agreement_list)
  
  cat("\n")
  
  ############################################################################
  ### D. DECILE MISCLASSIFICATION
  ############################################################################
  
  cat("Computing decile misclassification rates...\n")
  
  # Compute deciles for each SGPc variant (within each condition for fairness)
  # Handle cases where variance is too low (e.g., comonotonic in extreme conditions)
  sgpc_with_deciles <- copy(sgpc_data)
  
  # Track which variables had classification issues
  classification_issues <- list()
  
  for (var in c("sgpc_emp", "sgpc_best", "sgpc_avg", "sgpc_gaussian", "sgpc_comonotonic")) {
    if (var %in% names(sgpc_with_deciles)) {
      decile_var <- paste0("decile_", gsub("sgpc_", "", var))
      
      # Strategy: Try deciles by condition, with intelligent fallback
      sgpc_with_deciles[, (decile_var) := {
        
        # Get values for this condition
        vals <- get(var)
        
        # Try deciles (10 bins)
        decile_result <- tryCatch({
          breaks <- quantile(vals, probs = 0:10/10, na.rm = TRUE, type = 1)
          
          # Check if breaks are unique
          if (length(unique(breaks)) < length(breaks)) {
            # Try quintiles (5 bins) as fallback
            breaks_q <- quantile(vals, probs = 0:5/5, na.rm = TRUE, type = 1)
            
            if (length(unique(breaks_q)) < length(breaks_q)) {
              # Still not unique - very low variance
              # Return NA and track this condition
              rep(NA_character_, length(vals))
            } else {
              # Quintiles work - use them but map to decile scale
              quintile <- cut(vals, breaks = breaks_q, labels = 1:5, include.lowest = TRUE)
              # Map quintiles to approximate deciles (1->1-2, 2->3-4, etc.)
              as.character(as.integer(quintile) * 2)
            }
          } else {
            # Deciles work - use them
            cut(vals, breaks = breaks, labels = 1:10, include.lowest = TRUE)
          }
        }, error = function(e) {
          # If any error, return NA
          rep(NA_character_, length(vals))
        })
        
        decile_result
        
      }, by = condition_id]
      
      # Track conditions where classification failed
      n_na <- sum(is.na(sgpc_with_deciles[[decile_var]]))
      if (n_na > 0) {
        failed_conditions <- sgpc_with_deciles[is.na(get(decile_var)), unique(condition_id)]
        classification_issues[[var]] <- list(
          n_failed = n_na,
          n_total = nrow(sgpc_with_deciles),
          pct_failed = 100 * n_na / nrow(sgpc_with_deciles),
          failed_conditions = failed_conditions
        )
        cat(sprintf("  NOTE: %s classification failed for %d obs (%.1f%%) across %d conditions\n",
                    var, n_na, 100 * n_na / nrow(sgpc_with_deciles), length(failed_conditions)))
        cat(sprintf("        (Likely due to low variance in: %s)\n",
                    paste(head(failed_conditions, 3), collapse = ", ")))
      }
    }
  }
  
  decile_misclass_list <- list()
  
  for (comp_name in names(comparison_pairs)) {
    var1 <- comparison_pairs[[comp_name]][1]
    var2 <- comparison_pairs[[comp_name]][2]
    
    decile1 <- paste0("decile_", gsub("sgpc_", "", var1))
    decile2 <- paste0("decile_", gsub("sgpc_", "", var2))
    
    if (decile1 %in% names(sgpc_with_deciles) && decile2 %in% names(sgpc_with_deciles)) {
      # Compute misclassification rates overall and by strata
      misclass_overall <- sgpc_with_deciles[, {
        decile_diff <- abs(as.integer(get(decile1)) - as.integer(get(decile2)))
        list(
          exact_match = mean(decile_diff == 0, na.rm = TRUE),
          off_by_1 = mean(decile_diff == 1, na.rm = TRUE),
          off_by_2plus = mean(decile_diff >= 2, na.rm = TRUE),
          n = sum(!is.na(decile_diff))
        )
      }]
      
      misclass_overall[, comparison := comp_name]
      misclass_overall[, stratum := "Overall"]
      
      # By year span
      misclass_by_year <- sgpc_with_deciles[, {
        decile_diff <- abs(as.integer(get(decile1)) - as.integer(get(decile2)))
        list(
          exact_match = mean(decile_diff == 0, na.rm = TRUE),
          off_by_1 = mean(decile_diff == 1, na.rm = TRUE),
          off_by_2plus = mean(decile_diff >= 2, na.rm = TRUE),
          n = sum(!is.na(decile_diff))
        )
      }, by = year_span]
      
      misclass_by_year[, comparison := comp_name]
      misclass_by_year[, stratum := paste0("Year_", year_span)]
      
      # By content area
      misclass_by_content <- sgpc_with_deciles[, {
        decile_diff <- abs(as.integer(get(decile1)) - as.integer(get(decile2)))
        list(
          exact_match = mean(decile_diff == 0, na.rm = TRUE),
          off_by_1 = mean(decile_diff == 1, na.rm = TRUE),
          off_by_2plus = mean(decile_diff >= 2, na.rm = TRUE),
          n = sum(!is.na(decile_diff))
        )
      }, by = content_area]
      
      misclass_by_content[, comparison := comp_name]
      misclass_by_content[, stratum := content_area]
      
      decile_misclass_list[[comp_name]] <- rbind(
        misclass_overall,
        misclass_by_year[, .(comparison, stratum, exact_match, off_by_1, off_by_2plus, n)],
        misclass_by_content[, .(comparison, stratum, exact_match, off_by_1, off_by_2plus, n)]
      )
      
      cat(sprintf("  %s: %.1f%% exact, %.1f%% ±1, %.1f%% ≥2 deciles different\n",
                  comp_name,
                  misclass_overall$exact_match * 100,
                  misclass_overall$off_by_1 * 100,
                  misclass_overall$off_by_2plus * 100))
    }
  }
  
  decile_misclass <- rbindlist(decile_misclass_list, fill = TRUE)
  
  cat("\n====================================================================\n")
  cat("ENHANCED STATISTICS COMPUTATION COMPLETE\n")
  cat("====================================================================\n\n")
  
  ############################################################################
  ### RETURN RESULTS
  ############################################################################
  
  result <- list(
    individual_stats = list(
      by_comparison = individual_stats,
      all_ecdf_data = all_ecdf_data
    ),
    group_stats = if (length(group_stats) > 0) {
      list(
        by_comparison = group_stats,
        all_group_ecdf_data = all_group_ecdf_data
      )
    } else {
      NULL
    },
    rank_agreement = rank_agreement,
    decile_misclass = decile_misclass,
    classification_issues = if (length(classification_issues) > 0) classification_issues else NULL,
    comparison_pairs = comparison_pairs
  )
  
  return(result)
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
