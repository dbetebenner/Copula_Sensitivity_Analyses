############################################################################
### STEP 2: SGPc Sensitivity Analysis - Main Computation Script
### 
### Purpose: Compute multiple SGPc variants for all observations to assess
###          the practical impact of copula choice on student growth percentiles
###
### Variants Computed:
###   1. SGPc_emp - Empirical Bernstein copula (non-parametric truth)
###   2. SGPc_best - Best-fitting parametric copula from Phase 1
###   3. SGPc_avg - Canonical averaged copula from manifest
###   4. SGPc_gaussian - Gaussian copula (mis-specified)
###   5. SGPc_gumbel - Gumbel copula (mis-specified, upper tail)
###   6. SGPc_frank - Frank copula (mis-specified, symmetric)
###   7. SGPc_comonotonic - Perfect dependence (TAMP assumption)
###   8. SGP_traditional - B-spline quantile regression (if available)
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)
require(copula)

# Source required functions
source("functions/sgpc_engine.R")
source("functions/longitudinal_pairs.R")
source("STEP_2_SGPc_Sensitivity/phase1_data_loader.R")

cat("====================================================================\n")
cat("STEP 2: SGPc SENSITIVITY ANALYSIS\n")
cat("====================================================================\n\n")

############################################################################
### CONFIGURATION
############################################################################

# Which datasets to process (can be set by master_analysis.R)
if (!exists("DATASETS_TO_PROCESS")) {
  DATASETS_TO_PROCESS <- c("dataset_1", "dataset_2", "dataset_3", "dataset_4")
}

# Parallel processing (can be set by master_analysis.R)
if (!exists("USE_PARALLEL")) {
  USE_PARALLEL <- FALSE  # Set to TRUE for mirai parallel processing
}
N_CORES <- parallel::detectCores() - 1

# Load canonical parameters from Phase 1 using helper function
canonical_data <- load_canonical_parameters()
manifest <- canonical_data$manifest
canonical_params <- canonical_data$canonical_params

cat("Loaded Phase 1 outputs:\n")
cat("  Manifest: analysis_manifest.json\n")
cat("  Canonical parameters:", nrow(canonical_params), "strata\n")
cat("  Datasets to process:", paste(DATASETS_TO_PROCESS, collapse = ", "), "\n\n")

############################################################################
### HELPER FUNCTIONS
############################################################################

# NOTE: parse_condition_id() is now sourced from phase1_data_loader.R (line 27)
# DO NOT define it inline here as it will override the correct version

#' Compute all SGPc variants for a single condition
#'
#' @param condition_id String identifier
#' @param dataset_id String dataset identifier (e.g., "dataset_1")
#' @param phase1_results List with empirical_copula, best_fit_copula, etc.
#' @param canonical_params data.table from Phase 1
#' @param dataset_config Optional dataset configuration for lazy loading
#' @return data.table with all SGPc variants (traditional_sgp extracted from pairs data)
compute_sgpc_variants <- function(
  condition_id,
  dataset_id,
  phase1_results,
  canonical_params,
  dataset_config = NULL
) {
  
  # Start timing
  start_time <- Sys.time()
  cat("\n[", format(start_time, "%H:%M:%S"), "] START:", condition_id)
  
  # Parse condition metadata
  cat(" -> Parsing...")
  cond_meta <- parse_condition_id(condition_id)
  
  # === LAZY DATA LOADING (like STEP_1) ===
  # Load dataset from disk if not already in memory
  if (!exists("STATE_DATA_LONG") || 
      !exists(".LOADED_DATASET_ID") || 
      .LOADED_DATASET_ID != dataset_id) {
    
    # Get dataset configuration
    if (is.null(dataset_config) && exists("DATASETS_CONFIG")) {
      dataset_config <- DATASETS_CONFIG[[dataset_id]]
    }
    
    if (!is.null(dataset_config)) {
      # Determine file path (EC2 vs local, SGP vs base)
      ds_path <- if (exists("IS_EC2") && IS_EC2) {
        dataset_config$ec2_path
      } else {
        dataset_config$local_path
      }
      
      cat("\n[WORKER] Loading dataset:", dataset_id, "from", ds_path, "\n")
      load(ds_path)
      ds_data <- get(dataset_config$rdata_object_name)
      
      if (!inherits(ds_data, "data.table")) {
        ds_data <- as.data.table(ds_data)
      }
      
      # Cache in global environment
      assign("STATE_DATA_LONG", ds_data, envir = .GlobalEnv)
      assign(".LOADED_DATASET_ID", dataset_id, envir = .GlobalEnv)
      cat("[WORKER] Loaded", format(nrow(ds_data), big.mark = ","), "rows\n")
    } else {
      stop("Cannot load dataset: ", dataset_id, " - no config available")
    }
  }
  
  dataset_data <- STATE_DATA_LONG
  # === END LAZY LOADING ===
  
  # Create longitudinal pairs
  cat(" -> Creating pairs...")
  pair_start <- Sys.time()
  # CRITICAL: Explicitly pass year_current to prevent incorrect calculation
  pairs <- tryCatch({
    create_longitudinal_pairs(
      data = dataset_data,
      grade_prior = cond_meta$grade_prior,
      grade_current = cond_meta$grade_current,
      year_prior = as.character(cond_meta$year_prior),
      year_current = as.character(cond_meta$year_current),
      content_prior = cond_meta$content_area,
      content_current = cond_meta$content_area
    )
  }, error = function(e) {
    cat("\n    ERROR creating pairs:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(pairs) || nrow(pairs) < 10) {
    cat("\n    SKIP: insufficient data (n=", ifelse(is.null(pairs), 0, nrow(pairs)), ")\n")
    return(NULL)
  }
  
  pair_time <- as.numeric(difftime(Sys.time(), pair_start, units = "secs"))
  cat(sprintf(" OK (n=%s, %.1fs)", format(nrow(pairs), big.mark = ","), pair_time))
  
  # Get pseudo-observations
  cat("\n    -> Pseudo-obs...")
  pobs_start <- Sys.time()
  # CRITICAL: Use Phase 1's pseudo-observations for consistency with copula fitting
  # These are the EXACT same u,v values used to fit all Phase 1 copulas
  if (!is.null(phase1_results$pseudo_observations) && 
      nrow(phase1_results$pseudo_observations) == nrow(pairs)) {
    # Use Phase 1's pre-computed pseudo-observations
    cat(" Phase1")
    pobs <- phase1_results$pseudo_observations
    # Handle different storage formats (matrix or data.frame/data.table)
    if (is.matrix(pobs)) {
      u <- pobs[, 1]
      v <- pobs[, 2]
    } else {
      u <- pobs[[1]]
      v <- pobs[[2]]
    }
  } else {
    # Fallback: compute pseudo-observations from scale scores
    # (This should rarely happen if Phase 1 completed successfully)
    if (!is.null(phase1_results$pseudo_observations)) {
      cat(" WARN:mismatch,recompute")
    } else {
      cat(" compute")
    }
    u <- rank(pairs$SCALE_SCORE_PRIOR, na.last = "keep") / (nrow(pairs) + 1)
    v <- rank(pairs$SCALE_SCORE_CURRENT, na.last = "keep") / (nrow(pairs) + 1)
  }
  
  pobs_time <- as.numeric(difftime(Sys.time(), pobs_start, units = "secs"))
  cat(sprintf(" (%.1fs)", pobs_time))
  
  # Initialize result data.table
  # Include SCHOOL_NUMBER and DISTRICT_NUMBER for group-level aggregation (Panel B)
  result <- data.table(
    condition_id = condition_id,
    year_span = cond_meta$year_span,
    content_area = cond_meta$content_area,
    grade_prior = cond_meta$grade_prior,
    grade_current = cond_meta$grade_current,
    ID = pairs$ID,
    SCHOOL_NUMBER = if ("SCHOOL_NUMBER" %in% names(pairs)) pairs$SCHOOL_NUMBER else NA_character_,
    DISTRICT_NUMBER = if ("DISTRICT_NUMBER" %in% names(pairs)) pairs$DISTRICT_NUMBER else NA_character_,
    SCALE_SCORE_PRIOR = pairs$SCALE_SCORE_PRIOR,
    SCALE_SCORE_CURRENT = pairs$SCALE_SCORE_CURRENT,
    u = u,
    v = v
  )
  
  # 1. Empirical Bernstein copula (if available from Phase 1)
  cat("\n    -> SGPc_emp...")
  sgpc_start <- Sys.time()
  if (!is.null(phase1_results$empirical_copula)) {
    result[, sgpc_emp := sgpc_engine(u, v, phase1_results$empirical_copula, scale = "percentile")]
  } else {
    # Create empirical copula on-the-fly
    pseudo_obs <- cbind(u, v)
    emp_cop <- tryCatch({
      empCopula(pseudo_obs, smoothing = "beta")
    }, error = function(e) NULL)
    
    if (!is.null(emp_cop)) {
      result[, sgpc_emp := sgpc_engine(u, v, emp_cop, scale = "percentile")]
    } else {
      result[, sgpc_emp := NA_integer_]
    }
  }
  cat(sprintf(" %.1fs", as.numeric(difftime(Sys.time(), sgpc_start, units = "secs"))))
  
  # 2. Best-fitting parametric copula from Phase 1
  cat(" -> SGPc_best...")
  sgpc_start <- Sys.time()
  if (!is.null(phase1_results$best_fit_copula)) {
    result[, sgpc_best := sgpc_engine(u, v, phase1_results$best_fit_copula, scale = "percentile")]
  } else {
    result[, sgpc_best := NA_integer_]
  }
  cat(sprintf(" %.1fs", as.numeric(difftime(Sys.time(), sgpc_start, units = "secs"))))
  
  # 3. Canonical averaged copula
  cat(" -> SGPc_avg...")
  sgpc_start <- Sys.time()
  canonical_cop <- tryCatch({
    create_canonical_copula(cond_meta$year_span, cond_meta$content_area, canonical_params)
  }, error = function(e) NULL)
  
  if (!is.null(canonical_cop)) {
    result[, sgpc_avg := sgpc_engine(u, v, canonical_cop, scale = "percentile")]
  } else {
    result[, sgpc_avg := NA_integer_]
  }
  cat(sprintf(" %.1fs", as.numeric(difftime(Sys.time(), sgpc_start, units = "secs"))))
  
  # 4. Mis-specified copulas
  cat(" -> Misspec...")
  sgpc_start <- Sys.time()
  # Gaussian (no tail dependence)
  gaussian_cop <- normalCopula(param = cor(u, v, method = "kendall", use = "complete.obs") * sin(pi/2))
  result[, sgpc_gaussian := sgpc_engine(u, v, gaussian_cop, scale = "percentile")]
  
  # Gumbel (upper tail dependence)
  tau <- cor(u, v, method = "kendall", use = "complete.obs")
  gumbel_param <- max(1.001, 1 / (1 - tau))
  gumbel_cop <- gumbelCopula(param = gumbel_param)
  result[, sgpc_gumbel := sgpc_engine(u, v, gumbel_cop, scale = "percentile")]
  
  # Frank (symmetric, no tail dependence)
  frank_param <- iTau(frankCopula(), tau)
  frank_cop <- frankCopula(param = frank_param)
  result[, sgpc_frank := sgpc_engine(u, v, frank_cop, scale = "percentile")]
  cat(sprintf(" %.1fs", as.numeric(difftime(Sys.time(), sgpc_start, units = "secs"))))
  
  # 5. Comonotonic (TAMP assumption)
  cat(" -> SGPc_como...")
  sgpc_start <- Sys.time()
  result[, sgpc_comonotonic := sgpc_engine(u, v, "comonotonic", scale = "percentile")]
  cat(sprintf(" %.1fs", as.numeric(difftime(Sys.time(), sgpc_start, units = "secs"))))
  
  # 6. Traditional SGP (extract from pairs data if available)
  cat(" -> SGP_trad...")
  # The pairs data includes SGP columns like SGP_ORDER_1_SPAN_N_YEAR
  sgp_col_name <- paste0("SGP_ORDER_1_SPAN_", cond_meta$year_span, "_YEAR")
  
  if (sgp_col_name %in% names(pairs)) {
    result[, sgp_traditional := pairs[[sgp_col_name]]]
  } else {
    # Try alternative naming convention
    sgp_alt_col <- paste0("SGP_SPAN_", cond_meta$year_span, "_YEAR")
    if (sgp_alt_col %in% names(pairs)) {
      result[, sgp_traditional := pairs[[sgp_alt_col]]]
    } else {
      result[, sgp_traditional := NA_integer_]
    }
  }
  cat(" OK")
  
  # Total timing
  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  cat(sprintf("\n    COMPLETE: %.1f seconds total (n=%s)\n", 
              total_time, format(nrow(result), big.mark = ",")))
  
  return(result)
}

############################################################################
### MAIN PROCESSING LOOP
############################################################################

for (dataset_id in DATASETS_TO_PROCESS) {
  
  cat("\n====================================================================\n")
  cat("Processing", dataset_id, "\n")
  cat("====================================================================\n\n")
  
  # Check if STATE_DATA_LONG already exists (e.g., loaded by master_analysis.R)
  # If not, try to load dataset file
  if (!exists("STATE_DATA_LONG")) {
    cat("Loading dataset file...\n")
    
    # Try multiple possible locations
    possible_paths <- c(
      file.path("SGP", paste0(dataset_id, ".Rdata")),
      file.path("data", paste0(dataset_id, ".rda")),
      paste0(dataset_id, ".Rdata"),
      paste0(dataset_id, ".rda")
    )
    
    dataset_file <- possible_paths[file.exists(possible_paths)][1]
    
    if (is.na(dataset_file)) {
      cat("Dataset file not found for", dataset_id, "\n")
      cat("  Tried:", paste(possible_paths, collapse = ", "), "\n")
      next
    }
    
    load(dataset_file)  # Loads STATE_DATA_LONG
    
    cat("Loaded dataset from:", dataset_file, "\n")
    cat("  Rows:", format(nrow(STATE_DATA_LONG), big.mark = ","), "\n")
  } else {
    cat("Using pre-loaded STATE_DATA_LONG\n")
    cat("  Rows:", format(nrow(STATE_DATA_LONG), big.mark = ","), "\n")
  }
  
  # Get list of conditions from Phase 1
  conditions <- get_phase1_conditions(dataset_id)
  
  if (length(conditions) == 0) {
    cat("No Phase 1 conditions found for", dataset_id, "\n")
    next
  }
  
  cat("Found", length(conditions), "conditions from Phase 1\n")
  
  # Batch load Phase 1 results for all conditions
  cat("Loading Phase 1 copula results...\n")
  phase1_batch <- batch_load_phase1(dataset_id, conditions, verbose = TRUE)
  
  # Process each condition (sequential or parallel)
  all_results <- list()
  
  cat("\nComputing SGPc variants...\n")
  
  if (USE_PARALLEL) {
    cat("Using parallel processing with", N_CORES, "cores\n")
    
    if (!requireNamespace("mirai", quietly = TRUE)) {
      stop("mirai package required for parallel processing. Install with: install.packages('mirai')")
    }
    
    require(mirai)
    
    # Reduce worker count to leave memory headroom
    # STEP_1 uses n-4 for large instances; we'll use n-5 for extra safety
    n_workers <- N_CORES - 5
    cat("Creating", n_workers, "workers (leaving 5 cores for system/GC)\n")
    
    # Create mirai daemons
    daemons(n = n_workers, dispatcher = FALSE)
    
    # Initialize workers with packages and functions
    cat("Initializing workers...\n")
    PROJECT_ROOT <- normalizePath(getwd(), mustWork = TRUE)
    
    init_workers <- everywhere({
      # Load packages
      suppressPackageStartupMessages({
        library(data.table)
        library(copula)
      })
      
      # Change to project root for relative paths
      setwd(PROJECT_ROOT)
      
      # Source all necessary function files
      source("functions/longitudinal_pairs.R")
      source("functions/sgpc_engine.R")
      source("STEP_2_SGPc_Sensitivity/phase1_data_loader.R")
      
      TRUE  # Return success
    }, PROJECT_ROOT = PROJECT_ROOT)
    
    # Wait for initialization to complete
    init_results <- init_workers[]
    if (!all(sapply(init_results, isTRUE))) {
      stop("Failed to initialize some workers")
    }
    cat("Workers initialized successfully\n")
    
    # Export compute_sgpc_variants and configs to workers
    cat("Exporting functions and configs...\n")
    
    # Get dataset configs from global env
    if (exists("DATASETS", envir = .GlobalEnv)) {
      DATASETS_CONFIG <- get("DATASETS", envir = .GlobalEnv)
    } else {
      stop("DATASETS configuration not found in global environment")
    }
    
    # Check IS_EC2 flag
    IS_EC2_VALUE <- if (exists("IS_EC2", envir = .GlobalEnv)) {
      get("IS_EC2", envir = .GlobalEnv)
    } else {
      FALSE
    }
    
    export_data <- everywhere({
      # Verify compute_sgpc_variants is available
      if (!exists("compute_sgpc_variants")) {
        cat("[DAEMON ERROR] compute_sgpc_variants not found\n")
        stop("compute_sgpc_variants not available")
      }
      TRUE
    }, compute_sgpc_variants = compute_sgpc_variants,
       DATASETS_CONFIG = DATASETS_CONFIG,
       IS_EC2 = IS_EC2_VALUE)
    
    # Wait for export
    export_results <- export_data[]
    if (!all(sapply(export_results, isTRUE))) {
      stop("Failed to export function to some workers")
    }
    cat("Export complete\n")
    
    # Use mirai_map for memory-efficient parallel processing
    cat("Starting mirai_map processing...\n")
    
    mirai_results <- mirai_map(
      .x = seq_along(conditions),
      .f = function(i, conditions, phase1_batch, canonical_params, dataset_id) {
        cond_id <- conditions[i]
        phase1_results <- phase1_batch[[cond_id]]
        
        # Periodic garbage collection (every 5 conditions)
        if (i %% 5 == 0) {
          gc(verbose = FALSE, reset = TRUE)
        }
        
        # Call compute_sgpc_variants with dataset_id (not data)
        compute_sgpc_variants(
          condition_id = cond_id,
          dataset_id = dataset_id,
          phase1_results = phase1_results,
          canonical_params = canonical_params,
          dataset_config = DATASETS_CONFIG[[dataset_id]]
        )
      },
      .args = list(
        conditions = conditions,
        phase1_batch = phase1_batch,
        canonical_params = canonical_params,
        dataset_id = dataset_id
      )
    )
    
    # Collect results (blocking)
    cat("Collecting results...\n")
    all_condition_results <- mirai_results[]
    
    # Process results
    n_success <- 0
    n_errors <- 0
    
    for (i in seq_along(all_condition_results)) {
      result <- all_condition_results[[i]]
      cond_id <- conditions[i]
      
      if (inherits(result, "miraiError") || inherits(result, "errorValue")) {
        n_errors <- n_errors + 1
        if (n_errors <= 3) {  # Only print first 3 errors
          cat(sprintf("\n  ERROR in condition %s: %s\n", cond_id,
                     if (inherits(result, "errorValue")) result$data else as.character(result)))
        }
      } else if (!is.null(result)) {
        all_results[[cond_id]] <- result
        n_success <- n_success + 1
      }
      
      if (i %% 10 == 0) {
        cat(sprintf("  Processed: %d/%d (%.1f%%) - Success: %d, Errors: %d\n",
                    i, length(conditions), 100 * i / length(conditions), 
                    n_success, n_errors))
      }
    }
    
    cat(sprintf("\nCollection complete: %d successful, %d errors out of %d total\n",
                n_success, n_errors, length(conditions)))
    
    # Stop daemons
    daemons(0)
    
  } else {
    # Sequential execution
    cat("Using sequential processing\n")
    cat("====================================================================\n\n")
    
    dataset_start <- Sys.time()
    n_success <- 0
    n_skipped <- 0
    n_errors <- 0
    
    for (i in seq_along(conditions)) {
      cond_id <- conditions[i]
      
      # Progress header every 10 conditions
      if (i %% 10 == 1 || i == 1) {
        elapsed <- as.numeric(difftime(Sys.time(), dataset_start, units = "mins"))
        remaining_est <- if (i > 1) elapsed / (i - 1) * (length(conditions) - i + 1) else NA
        cat(sprintf("\n--- Batch %d-%d (%.1f%% complete, %.1f min elapsed, ~%.1f min remaining) ---\n",
                    i, min(i + 9, length(conditions)),
                    100 * (i - 1) / length(conditions),
                    elapsed,
                    if (is.na(remaining_est)) 0 else remaining_est))
      }
      
      # Get Phase 1 results for this condition
      phase1_results <- phase1_batch[[cond_id]]
      
      # Compute variants
      cond_result <- tryCatch({
        compute_sgpc_variants(
          condition_id = cond_id,
          dataset_id = dataset_id,
          phase1_results = phase1_results,
          canonical_params = canonical_params
        )
      }, error = function(e) {
        cat(sprintf("\n    ERROR in %s: %s\n", cond_id, e$message))
        n_errors <<- n_errors + 1
        return(NULL)
      })
      
      if (!is.null(cond_result)) {
        all_results[[cond_id]] <- cond_result
        n_success <- n_success + 1
      } else {
        n_skipped <- n_skipped + 1
      }
    }
    
    cat("\n====================================================================\n")
    cat(sprintf("SEQUENTIAL PROCESSING COMPLETE: %d/%d successful (%.1f%%), %d skipped, %d errors\n",
                n_success, length(conditions), 100 * n_success / length(conditions),
                n_skipped, n_errors))
    cat(sprintf("Total time: %.1f minutes\n", 
                as.numeric(difftime(Sys.time(), dataset_start, units = "mins"))))
    cat("====================================================================\n\n")
  }
  
  # Combine all results
  if (length(all_results) > 0) {
    dataset_results <- rbindlist(all_results, fill = TRUE)
    
    # Save results - ensure directory exists
    output_dir <- "STEP_2_SGPc_Sensitivity/results"
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
      cat("\nCreated output directory:", output_dir, "\n")
    }
    
    output_file <- file.path(
      output_dir,
      paste0("sgpc_all_variants_", dataset_id, ".rds")
    )
    saveRDS(dataset_results, output_file)
    
    cat("\nSaved results to:", output_file, "\n")
    cat("  Total observations:", nrow(dataset_results), "\n")
    cat("  Conditions processed:", length(all_results), "\n\n")
  } else {
    cat("\nNo results generated for", dataset_id, "\n\n")
  }
}

cat("====================================================================\n")
cat("COMPUTATION COMPLETE\n")
cat("====================================================================\n\n")
