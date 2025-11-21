############################################################################
### PHASE 1: COPULA FAMILY SELECTION STUDY
### Objective: Identify which copula family consistently provides best fit
###           for longitudinal educational assessment data
###
### Hypothesis: T-copula will dominate due to heavy tails in educational
###             data, with tail dependence increasing as time between
###             observations increases.
############################################################################

# Load libraries
require(data.table)
require(splines2)
require(copula)

# Data is loaded centrally by master_analysis.R
# STATE_DATA_LONG should already be available (generic name for state data)

# Functions are loaded centrally by master_analysis.R
# No need to source them individually

cat("====================================================================\n")
cat("PHASE 1: COPULA FAMILY SELECTION STUDY\n")
cat("====================================================================\n")
cat("Testing all 9 copula families across diverse conditions\n")
cat("to identify which family consistently provides best fit.\n")
cat("Note: Comonotonic copula included to demonstrate TAMP misfit.\n")
cat("Note: T-copula variants (free, df=5, df=10, df=15) test tail dependence.\n")
cat("====================================================================\n\n")

################################################################################
### CONFIGURATION
################################################################################

# All copula families to test
# Including comonotonic (Fréchet-Hoeffding upper bound) to show how badly
# the implicit TAMP assumption (perfect positive dependence) misfits the data
# Note: We focus on t-copula with data-driven df estimation (not fixed df)
# as preliminary results showed free df consistently dominates fixed df variants
COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")

# Define test conditions
# Two strategies:
# 1. Strategic subset (datasets 1 & 2): Representative sampling for family selection
# 2. Exhaustive (dataset 3): All valid combinations for transition analysis

# Check if we should use exhaustive conditions for this dataset
USE_EXHAUSTIVE_CONDITIONS <- exists("current_dataset", envir = .GlobalEnv) && 
                             !is.null(current_dataset) && 
                             current_dataset$id == "dataset_3"

if (USE_EXHAUSTIVE_CONDITIONS) {
  cat("Using EXHAUSTIVE conditions for", current_dataset$name, "\n")
  cat("  (All valid year/grade/content combinations for transition analysis)\n\n")
  
  # Generate all valid conditions for this dataset
  CONDITIONS <- generate_exhaustive_conditions(current_dataset, max_year_span = 4)
  
} else {
  cat("Using STRATEGIC SUBSET conditions\n")
  cat("  (Representative sampling for copula family selection)\n\n")
  
  # Strategic subset: Representative conditions for family selection
  # Year spans: 1, 2, 3, 4 years (temporal distance)
  # Content areas: MATHEMATICS, READING, WRITING (dataset-dependent)
  # Grade range: G3→G10 (includes early elementary and middle school transition)
  # Cohorts: Multiple starting years for robustness
  
  # Expanded to include Grade 3 and Grade 7 priors
  # Grade 3: Tests early elementary patterns
  # Grade 7: Captures middle school transition (G7→G8)
  
  CONDITIONS <- list(
    # === 1-YEAR SPANS ===
    # Grade 3 prior (early elementary)
    list(grade_prior = 3, grade_current = 4, year_prior = "2010", content = "MATHEMATICS", year_span = 1),
    list(grade_prior = 3, grade_current = 4, year_prior = "2010", content = "READING", year_span = 1),
    
    # Grade 4-6 prior (existing)
    list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "MATHEMATICS", year_span = 1),
    list(grade_prior = 4, grade_current = 5, year_prior = "2011", content = "MATHEMATICS", year_span = 1),
    list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", year_span = 1),
    list(grade_prior = 6, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", year_span = 1),
    list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "READING", year_span = 1),
    list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "READING", year_span = 1),
    list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "WRITING", year_span = 1),
    
    # Grade 7 prior (middle school transition)
    list(grade_prior = 7, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", year_span = 1),
    list(grade_prior = 7, grade_current = 8, year_prior = "2010", content = "READING", year_span = 1),
    
    # === 2-YEAR SPANS ===
    # Grade 3 prior
    list(grade_prior = 3, grade_current = 5, year_prior = "2010", content = "MATHEMATICS", year_span = 2),
    list(grade_prior = 3, grade_current = 5, year_prior = "2010", content = "READING", year_span = 2),
    
    # Grade 4-6 prior (existing)
    list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", year_span = 2),
    list(grade_prior = 4, grade_current = 6, year_prior = "2011", content = "MATHEMATICS", year_span = 2),
    list(grade_prior = 5, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", year_span = 2),
    list(grade_prior = 6, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", year_span = 2),
    list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "READING", year_span = 2),
    list(grade_prior = 5, grade_current = 7, year_prior = "2010", content = "READING", year_span = 2),
    list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "WRITING", year_span = 2),
    
    # Grade 7 prior
    list(grade_prior = 7, grade_current = 9, year_prior = "2010", content = "MATHEMATICS", year_span = 2),
    list(grade_prior = 7, grade_current = 9, year_prior = "2010", content = "READING", year_span = 2),
    
    # === 3-YEAR SPANS ===
    # Grade 3 prior
    list(grade_prior = 3, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", year_span = 3),
    list(grade_prior = 3, grade_current = 6, year_prior = "2010", content = "READING", year_span = 3),
    
    # Grade 4-6 prior (existing)
    list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", year_span = 3),
    list(grade_prior = 4, grade_current = 7, year_prior = "2009", content = "MATHEMATICS", year_span = 3),
    list(grade_prior = 5, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", year_span = 3),
    list(grade_prior = 6, grade_current = 9, year_prior = "2010", content = "MATHEMATICS", year_span = 3),
    list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "READING", year_span = 3),
    list(grade_prior = 5, grade_current = 8, year_prior = "2010", content = "READING", year_span = 3),
    list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "WRITING", year_span = 3),
    
    # Grade 7 prior
    list(grade_prior = 7, grade_current = 10, year_prior = "2009", content = "MATHEMATICS", year_span = 3),
    list(grade_prior = 7, grade_current = 10, year_prior = "2009", content = "READING", year_span = 3),
    
    # === 4-YEAR SPANS ===
    # Grade 3 prior
    list(grade_prior = 3, grade_current = 7, year_prior = "2009", content = "MATHEMATICS", year_span = 4),
    list(grade_prior = 3, grade_current = 7, year_prior = "2009", content = "READING", year_span = 4),
    
    # Grade 4-6 prior (existing + expanded)
    list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "MATHEMATICS", year_span = 4),
    list(grade_prior = 4, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", year_span = 4),
    list(grade_prior = 5, grade_current = 9, year_prior = "2009", content = "MATHEMATICS", year_span = 4),
    list(grade_prior = 6, grade_current = 10, year_prior = "2009", content = "MATHEMATICS", year_span = 4),
    list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "READING", year_span = 4),
    list(grade_prior = 5, grade_current = 9, year_prior = "2009", content = "READING", year_span = 4),
    list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "WRITING", year_span = 4)
  )
}

################################################################################
### FILTER CONDITIONS BY AVAILABLE CONTENT AREAS
################################################################################

# Filter out conditions with content areas not available in current dataset
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)) {
  available_content_areas <- current_dataset$content_areas
  original_count <- length(CONDITIONS)
  
  CONDITIONS <- CONDITIONS[sapply(CONDITIONS, function(cond) {
    cond$content %in% available_content_areas
  })]
  
  filtered_count <- original_count - length(CONDITIONS)
  if (filtered_count > 0) {
    cat("\n")
    cat("====================================================================\n")
    cat("CONTENT AREA FILTERING\n")
    cat("====================================================================\n")
    cat("Dataset:", current_dataset$name, "\n")
    cat("Available content areas:", paste(available_content_areas, collapse = ", "), "\n")
    cat("Filtered out", filtered_count, "condition(s) with unavailable content areas\n")
    cat("Remaining conditions:", length(CONDITIONS), "\n\n")
  }
}

################################################################################
### ENRICH CONDITIONS WITH DATASET METADATA
################################################################################

# Enrich each condition with dataset-specific metadata
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)) {
  cat("\nEnriching conditions with dataset metadata...\n")
  
  for (i in seq_along(CONDITIONS)) {
    cond <- CONDITIONS[[i]]
    
    # Calculate year_current from year_prior + year_span
    year_current <- as.character(as.numeric(cond$year_prior) + cond$year_span)
    
    # Add dataset identifiers
    cond$dataset_id <- current_dataset$id
    cond$dataset_name <- current_dataset$name
    cond$anonymized_state <- current_dataset$anonymized_state
    
    # Add scaling metadata using helper functions from dataset_configs.R
    cond$year_current <- year_current
    cond$prior_scaling_type <- get_scaling_type(current_dataset, cond$year_prior)
    cond$current_scaling_type <- get_scaling_type(current_dataset, year_current)
    cond$scaling_transition_type <- get_scaling_transition_type(current_dataset, cond$year_prior, year_current)
    
    # Add transition metadata
    cond$has_transition <- current_dataset$has_transition
    cond$transition_year <- if (current_dataset$has_transition) current_dataset$transition_year else NA
    cond$includes_transition_span <- crosses_transition(current_dataset, cond$year_prior, year_current)
    cond$transition_period <- get_transition_period(current_dataset, cond$year_prior, year_current)
    
    # Update the condition in the list
    CONDITIONS[[i]] <- cond
  }
  
  cat("✓ Conditions enriched with dataset metadata\n")
  cat("  Dataset:", current_dataset$name, "\n")
  cat("  Scaling types:", paste(unique(current_dataset$scaling_by_year$scaling_type), collapse = ", "), "\n")
  if (current_dataset$has_transition) {
    cat("  Transition year:", current_dataset$transition_year, "\n")
  }
  cat("\n")
} else {
  warning("current_dataset not found. Conditions will not have dataset metadata.")
}

cat("Total conditions to test:", length(CONDITIONS), "\n")
cat("Copula families:", paste(COPULA_FAMILIES, collapse = ", "), "\n")
cat("Total fits:", length(CONDITIONS) * length(COPULA_FAMILIES), "\n\n")

################################################################################
### RUN FAMILY SELECTION STUDY
################################################################################

# Storage for all results
all_results <- list()
result_counter <- 0

for (i in seq_along(CONDITIONS)) {
  
  cond <- CONDITIONS[[i]]
  
  cat("\n====================================================================\n")
  cat("Condition", i, "of", length(CONDITIONS), "\n")
  cat("Year span:", cond$year_span, "year(s) |",
      "G", cond$grade_prior, "->", cond$grade_current, "\n")
  cat("Years:", cond$year_prior, "->", cond$year_current, "\n")
  cat("Content:", cond$content, "\n")
  if (!is.null(cond$scaling_transition_type)) {
    cat("Scaling:", cond$scaling_transition_type, "\n")
  }
  if (!is.null(cond$includes_transition_span) && cond$includes_transition_span) {
    cat("** CROSSES ASSESSMENT TRANSITION **\n")
  }
  cat("====================================================================\n\n")
  
  # Create longitudinal pairs
  pairs_full <- tryCatch({
    create_longitudinal_pairs(
      data = get_state_data(),
      grade_prior = cond$grade_prior,
      grade_current = cond$grade_current,
      year_prior = cond$year_prior,
      content_prior = cond$content,
      content_current = cond$content
    )
  }, error = function(e) {
    cat("Error creating pairs:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(pairs_full) || nrow(pairs_full) < 100) {
    cat("Insufficient data for this configuration (N =", 
        ifelse(is.null(pairs_full), 0, nrow(pairs_full)), "). Skipping.\n")
    next
  }
  
  n_pairs <- nrow(pairs_full)
  cat("Longitudinal pairs:", n_pairs, "\n\n")
  
  # Create I-spline frameworks
  cat("Establishing I-spline frameworks...\n")
  framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
  framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
  
  # Fit all copula families
  # IMPORTANT: Phase 1 uses empirical ranks (not I-spline) for copula family selection
  # This ensures uniform pseudo-observations and preserves tail dependence structure
  # (See debug_frank_dominance.R for validation showing I-spline with 4 knots distorted results)
  cat("Fitting all copula families...\n")
  cat("  Using empirical ranks for family selection (ensures uniform U,V)\n\n")
  
  copula_fits <- fit_copula_from_pairs(
    scores_prior = pairs_full$SCALE_SCORE_PRIOR,
    scores_current = pairs_full$SCALE_SCORE_CURRENT,
    framework_prior = framework_prior,  # Still create for reference, but not used with ranks
    framework_current = framework_current,
    copula_families = COPULA_FAMILIES,
    return_best = FALSE,
    use_empirical_ranks = TRUE,  # Phase 1: Use ranks to avoid I-spline distortion
    n_bootstrap_gof = if (exists("N_BOOTSTRAP_GOF", envir = .GlobalEnv)) N_BOOTSTRAP_GOF else NULL
  )
  
  # Generate visualization plots if requested
  if (exists("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv) && 
      get("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv, inherits = FALSE) &&
      !is.null(copula_fits$pseudo_obs)) {
    
    # Prepare output directory for plots
    dataset_id <- if (!is.null(cond$dataset_id)) cond$dataset_id else "unknown"
    year_current <- if (!is.null(cond$year_current)) {
      cond$year_current 
    } else {
      as.character(as.numeric(cond$year_prior) + cond$year_span)
    }
    
    plot_output_dir <- file.path("STEP_1_Family_Selection/results", 
                                 dataset_id,
                                 "contour_plots",
                                 sprintf("%s_G%d_G%d_%s", 
                                        cond$year_prior, cond$grade_prior, 
                                        cond$grade_current, cond$content))
    
    # Prepare condition info with dataset_number extraction
    condition_info <- list(
      dataset_id = dataset_id,
      dataset_number = {
        parts <- strsplit(dataset_id, "_")[[1]]
        if (length(parts) >= 2) parts[2] else dataset_id
      },
      year_prior = cond$year_prior,
      year_current = year_current,
      grade_prior = cond$grade_prior,
      grade_current = cond$grade_current,
      content = cond$content
    )
    
    # Generate plots (wrapped in tryCatch to prevent failures from stopping analysis)
    tryCatch({
      if (exists("generate_condition_plots")) {
        generate_condition_plots(
          pseudo_obs = copula_fits$pseudo_obs,
          original_scores = pairs_full[, .(SCALE_SCORE_PRIOR, SCALE_SCORE_CURRENT)],
          copula_results = copula_fits$results,
          best_family = copula_fits$best_family,
          output_dir = plot_output_dir,
          condition_info = condition_info,
          save_plots = TRUE,
          grid_size = 300,  # High resolution for publication-quality plots
          export_formats = if (exists("EXPORT_FORMATS", envir = .GlobalEnv)) EXPORT_FORMATS else c("pdf"),
          export_dpi = if (exists("EXPORT_DPI", envir = .GlobalEnv)) EXPORT_DPI else 300,
          export_verbose = if (exists("EXPORT_VERBOSE", envir = .GlobalEnv)) EXPORT_VERBOSE else FALSE
        )
        cat("  ✓ Plots generated successfully\n")
      } else {
        cat("  ⚠ Warning: generate_condition_plots function not found\n")
      }
    }, error = function(e) {
      cat("  ⚠ Warning: Failed to generate plots:", e$message, "\n")
    })
  }
  
  # Extract results for each family
  for (family in COPULA_FAMILIES) {
    
    if (!is.null(copula_fits$results[[family]])) {
      
      result_counter <- result_counter + 1
      
      fit <- copula_fits$results[[family]]
      
      # Extract tail dependence coefficients
      if (family %in% c("t", "t_df5", "t_df10", "t_df15")) {
        # All t-copula variants: use pre-calculated values from copula_bootstrap.R
        tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
        tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 0
      } else if (family == "clayton") {
        # Clayton has lower tail dependence only
        theta <- fit$parameter[1]
        tail_dep_lower <- 2^(-1/theta)
        tail_dep_upper <- 0
      } else if (family == "gumbel") {
        # Gumbel has upper tail dependence only
        theta <- fit$parameter[1]
        tail_dep_lower <- 0
        tail_dep_upper <- 2 - 2^(1/theta)
      } else if (family == "comonotonic") {
        # Comonotonic: use pre-calculated values
        tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
        tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 1
      } else {
        # Gaussian and Frank have no tail dependence
        tail_dep_lower <- 0
        tail_dep_upper <- 0
      }
      
      # Extract parameters with proper naming
      # For clarity, we extract generic parameters and then create descriptive columns
      param_1 <- fit$parameter[1]
      param_2 <- if (!is.null(fit$df)) fit$df else NA_real_
      
      # Create descriptive parameter columns based on family
      if (family %in% c("gaussian", "t", "t_df5", "t_df10", "t_df15")) {
        correlation_rho <- param_1
        theta <- NA_real_
      } else if (family %in% c("clayton", "gumbel", "frank")) {
        correlation_rho <- NA_real_
        theta <- param_1
      } else {
        # Comonotonic
        correlation_rho <- NA_real_
        theta <- NA_real_
      }
      
      # Degrees of freedom (only for t-copula variants)
      degrees_freedom <- if (family %in% c("t", "t_df5", "t_df10", "t_df15")) param_2 else NA_real_
      
      all_results[[result_counter]] <- data.table(
        # Dataset identifiers
        dataset_id = if (!is.null(cond$dataset_id)) cond$dataset_id else NA_character_,
        dataset_name = if (!is.null(cond$dataset_name)) cond$dataset_name else NA_character_,
        anonymized_state = if (!is.null(cond$anonymized_state)) cond$anonymized_state else NA_character_,
        
        # Scaling characteristics
        prior_scaling_type = if (!is.null(cond$prior_scaling_type)) cond$prior_scaling_type else NA_character_,
        current_scaling_type = if (!is.null(cond$current_scaling_type)) cond$current_scaling_type else NA_character_,
        scaling_transition_type = if (!is.null(cond$scaling_transition_type)) cond$scaling_transition_type else NA_character_,
        has_transition = if (!is.null(cond$has_transition)) cond$has_transition else NA,
        transition_year = if (!is.null(cond$transition_year)) cond$transition_year else NA,
        includes_transition_span = if (!is.null(cond$includes_transition_span)) cond$includes_transition_span else NA,
        transition_period = if (!is.null(cond$transition_period)) cond$transition_period else NA_character_,
        
        # Condition identifiers
        condition_id = i,
        year_span = cond$year_span,
        grade_prior = cond$grade_prior,
        grade_current = cond$grade_current,
        year_prior = cond$year_prior,
        year_current = if (!is.null(cond$year_current)) cond$year_current else as.character(as.numeric(cond$year_prior) + cond$year_span),
        content_area = cond$content,
        n_pairs = n_pairs,
        
        # Copula family results
        family = family,
        aic = fit$aic,
        bic = fit$bic,
        loglik = fit$loglik,
        tau = fit$kendall_tau,
        tail_dep_lower = tail_dep_lower,
        tail_dep_upper = tail_dep_upper,
        
        # Generic parameters (for backwards compatibility)
        parameter_1 = param_1,
        parameter_2 = param_2,
        
        # Descriptive parameters (easier for analysis)
        correlation_rho = correlation_rho,
        degrees_freedom = degrees_freedom,
        theta = theta,
        
        # Goodness-of-Fit test results
        gof_statistic = if (!is.null(fit$gof_statistic)) fit$gof_statistic else NA_real_,
        gof_pvalue = if (!is.null(fit$gof_pvalue)) fit$gof_pvalue else NA_real_,
        gof_pass_0.05 = if (!is.null(fit$gof_pvalue)) (fit$gof_pvalue > 0.05) else NA,
        gof_method = if (!is.null(fit$gof_method)) fit$gof_method else NA_character_
      )
      
      cat(sprintf("  %-10s: AIC = %8.2f, BIC = %8.2f, tau = %.4f\n",
                  family, fit$aic, fit$bic, fit$kendall_tau))
    } else {
      cat(sprintf("  %-10s: FAILED to fit\n", family))
    }
  }
  
  # Show best family for this condition
  cat("\nBest family (AIC):", copula_fits$best_family, "\n")
  cat("Empirical tau:", round(copula_fits$empirical_tau, 4), "\n")
}

################################################################################
### COMPILE AND SAVE RESULTS
################################################################################

cat("\n\n====================================================================\n")
cat("COMPILING RESULTS\n")
cat("====================================================================\n\n")

if (length(all_results) == 0) {
  stop("No results to compile. Check data availability.")
}

# Combine all results
results_dt <- rbindlist(all_results)

# Calculate best family for each condition
# NOTE: Within a single dataset run, condition_id is unique, so we only need to group by condition_id here.
# Multi-dataset aggregation (grouping by dataset_id + condition_id) happens later in phase1_analysis.R
# when results from all datasets are combined.
results_dt[, best_aic := family[which.min(aic)], by = condition_id]
results_dt[, best_bic := family[which.min(bic)], by = condition_id]

# Calculate delta from best
results_dt[, delta_aic_vs_best := aic - min(aic), by = condition_id]
results_dt[, delta_bic_vs_best := bic - min(bic), by = condition_id]

# Sort by condition and AIC
setorder(results_dt, condition_id, aic)

################################################################################
### SAVE TO DATASET-SPECIFIC DIRECTORY
################################################################################

# Save results to dataset-specific directory for individual inspection
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset$id)) {
  dataset_results_dir <- paste0("STEP_1_Family_Selection/results/", current_dataset$id)
  dir.create(dataset_results_dir, showWarnings = FALSE, recursive = TRUE)
  output_file <- paste0(dataset_results_dir, "/phase1_copula_family_comparison.csv")
  fwrite(results_dt, output_file)
  cat("✓ Saved dataset-specific results to:", output_file, "\n")
  cat("  Total conditions:", uniqueN(results_dt$condition_id), "\n")
  cat("  Total fits:", nrow(results_dt), "\n\n")
}

################################################################################
### ADD TO ACCUMULATION LIST (FOR MULTI-DATASET COMBINING)
################################################################################

# Add results to accumulation list
cat("\n====================================================================\n")
cat("ADDING RESULTS TO ACCUMULATION LIST\n")
cat("====================================================================\n\n")

# Store in global list (accessed by master_analysis.R)
if (!exists("ALL_DATASET_RESULTS", envir = .GlobalEnv)) {
  stop("ERROR: ALL_DATASET_RESULTS not found in global environment. Must be created by master_analysis.R")
}

# Append to step1 results list using dataset_idx
if (!exists("dataset_idx", envir = .GlobalEnv)) {
  stop("ERROR: dataset_idx not found in global environment. Must be set by master_analysis.R")
}

dataset_idx_char <- as.character(dataset_idx)
# Directly assign to .GlobalEnv to avoid <<- operator issues
.GlobalEnv$ALL_DATASET_RESULTS$step1[[dataset_idx_char]] <- results_dt

cat("✓ Results stored for dataset", dataset_idx, "\n")
if (exists("CURRENT_DATASET_NAME")) {
  cat("  Dataset name:", CURRENT_DATASET_NAME, "\n")
}
cat("  Dataset ID:", if (exists("current_dataset", envir = .GlobalEnv)) current_dataset$id else "unknown", "\n")
cat("  Total unique conditions:", uniqueN(results_dt$condition_id), "\n")
cat("  Total copula families tested:", length(COPULA_FAMILIES), "\n")
cat("  Expected rows:", uniqueN(results_dt$condition_id), "×", length(COPULA_FAMILIES), "=", 
    uniqueN(results_dt$condition_id) * length(COPULA_FAMILIES), "\n")
cat("  Actual rows:", nrow(results_dt), "\n")
if (nrow(results_dt) != uniqueN(results_dt$condition_id) * length(COPULA_FAMILIES)) {
  cat("  ⚠ WARNING: Row count mismatch!\n")
}
cat("  Columns:", ncol(results_dt), "\n")
cat("  Condition type:", if (USE_EXHAUSTIVE_CONDITIONS) "EXHAUSTIVE" else "STRATEGIC SUBSET", "\n\n")

cat("Results will be combined with other datasets after all datasets complete.\n")
cat("Combined file: STEP_1_Family_Selection/results/phase1_copula_family_comparison_all_datasets.csv\n\n")

# Quick summary
cat("====================================================================\n")
cat("QUICK SUMMARY\n")
cat("====================================================================\n\n")

family_selection <- results_dt[aic == min(aic), .N, by = .(family)]
setorder(family_selection, -N)

cat("Family selection frequency (by AIC):\n")
print(family_selection)

cat("\n\nMean AIC by family:\n")
mean_aic <- results_dt[, .(mean_aic = mean(aic), sd_aic = sd(aic)), by = family]
setorder(mean_aic, mean_aic)
print(mean_aic)

cat("\n\nPhase 1 complete! Proceed to phase1_analysis.R for detailed analysis.\n")
cat("====================================================================\n\n")

