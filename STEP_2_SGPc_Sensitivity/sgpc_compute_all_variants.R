############################################################################
### STEP 2: SGPc Sensitivity Analysis - Main Computation Script
### 
### Purpose: Compute multiple SGPc variants for all observations to assess
###          the practical impact of copula choice on student growth percentiles
###
### Variants Computed:
###   1. SGPc_emp - Empirical Bernstein copula (non-parametric truth)
###   2. SGPc_best - Best-fitting parametric copula from Phase 1
###   3. SGPc_avg - Canonical copula from Phase 1 manifest (t-copula with
###                 stratum-specific median rho and df parameters)
###   4. SGPc_gaussian - Gaussian copula (mis-specified)
###   5. SGPc_gumbel - Gumbel copula (mis-specified, upper tail)
###   6. SGPc_frank - Frank copula (mis-specified, symmetric, no tail dep.)
###   7. SGPc_clayton - Clayton copula (mis-specified, lower tail)
###   8. SGPc_t - t-copula with df=4 (extreme tail dependence stress test)
###   9. SGPc_comonotonic - Perfect dependence (TAMP assumption)
###                        NOTE: Uses derivative-based conditional CDF (step
###                        function) yielding bimodal SGPc (1s/99s) to demonstrate
###                        TAMP extremity. Alternative constant-50 interpretation
###                        may be explored for growth regime inference (STEP 3).
###                        See functions/sgpc_engine.R for detailed discussion.
###  10. SGP_traditional - B-spline quantile regression (if available)
###
### Canonical Copula Rationale:
###   The canonical (SGPc_avg) is a t-copula with median rho and df computed
###   from all t-copula fits within each year_span x content_area stratum.
###   This is the copula that would be used operationally for datasets like
###   TIMSS/NAEP where no empirical copula is available.
###
###   STEP_1 family selection across 966 conditions found:
###     - t-copula: 63.6% (AIC-best), plurality winner in all 16 strata
###     - Frank:    30.7% (AIC-best), significant minority
###     - Gumbel:    3.6%
###     - Gaussian:  2.1%
###
###   The SGPc_frank variant directly captures sensitivity for the 30.7% of
###   conditions where Frank was the true best fit. The canonical_validation.R
###   script (STEP 2.2) provides empirical evidence that the t-canonical
###   produces SGPc values sufficiently close to empirical across all strata.
###
### Author: dataimago
### Date: January 2026 (canonical validation added February 2026)
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

# --- STEP_2 Subset Controls (set from master_analysis.R or interactively) ---
# STEP2_MAX_CONDITIONS: integer or NULL (all).  Limits conditions per dataset.
# STEP2_SAMPLE_STRATEGY: "first" | "random" | "stratified" (default "stratified")
# STEP2_SEED: integer seed for reproducible random/stratified subsetting
if (!exists("STEP2_MAX_CONDITIONS"))    STEP2_MAX_CONDITIONS    <- NULL
if (!exists("STEP2_SAMPLE_STRATEGY"))   STEP2_SAMPLE_STRATEGY   <- "stratified"
if (!exists("STEP2_SEED"))              STEP2_SEED              <- 42

# --- Memory-aware worker cap ---
# STEP2_MEMORY_PER_WORKER_GB: estimated peak RSS per worker (dataset + overhead).
#   Set NULL for auto-estimate from dataset file size.  Manual override encouraged
#   for EC2 instances with known memory budgets.
# STEP2_TOTAL_MEMORY_GB: total system RAM budget for workers.
#   NULL = auto-detect via /proc/meminfo or Sys.meminfo (fallback: 16 GB).
if (!exists("STEP2_MEMORY_PER_WORKER_GB"))  STEP2_MEMORY_PER_WORKER_GB <- NULL
if (!exists("STEP2_TOTAL_MEMORY_GB"))       STEP2_TOTAL_MEMORY_GB      <- NULL

# Load canonical parameters from Phase 1 using helper function
canonical_data <- load_canonical_parameters()
manifest <- canonical_data$manifest
canonical_params <- canonical_data$canonical_params

cat("Loaded Phase 1 outputs:\n")
cat("  Manifest: analysis_manifest.json\n")
cat("  Canonical parameters:", nrow(canonical_params), "strata\n")
cat("  Datasets to process:", paste(DATASETS_TO_PROCESS, collapse = ", "), "\n")

# Log key manifest statistics for STEP_2 context
if (!is.null(manifest)) {
  tryCatch({
    cat("\n  STEP_1 Manifest Context:\n")
    cat(sprintf("    Conditions: %d across %d datasets\n",
                manifest$metadata$n_conditions, manifest$metadata$n_datasets))
    cat(sprintf("    Year spans tested: %s\n",
                paste(manifest$metadata$year_spans_tested, collapse = ", ")))
    cat(sprintf("    Families tested: %d\n", manifest$metadata$n_families))
    
    # Family selection summary
    if (!is.null(manifest$family_selection_summary)) {
      cat("    Family selection (AIC-best):\n")
      for (fam in manifest$family_selection_summary) {
        cat(sprintf("      %s: %.1f%% (%d/%d conditions)\n",
                    fam$family, fam$pct_best, fam$n_best_aic, fam$n_conditions))
      }
    }
    
    # Canonical stability overview
    if (nrow(canonical_params) > 0 && "overall_stability" %in% names(canonical_params)) {
      n_high <- sum(canonical_params$overall_stability == "HIGH", na.rm = TRUE)
      n_med <- sum(canonical_params$overall_stability == "MEDIUM", na.rm = TRUE)
      n_low <- sum(canonical_params$overall_stability == "LOW", na.rm = TRUE)
      cat(sprintf("    Canonical stability: %d HIGH, %d MEDIUM, %d LOW\n",
                  n_high, n_med, n_low))
    }
  }, error = function(e) {
    cat("    (manifest context extraction failed:", e$message, ")\n")
  })
}
cat("\n")

############################################################################
### SUBSET & MEMORY HELPERS
############################################################################

#' Subset conditions for local profiling / smoke testing
#' @param conditions Character vector of condition IDs
#' @param max_n NULL (keep all) or integer cap
#' @param strategy "first", "random", or "stratified"
#' @param seed Integer seed for reproducibility
#' @return Subset of conditions (character vector)
.subset_conditions <- function(conditions, max_n = NULL, strategy = "stratified", seed = 42) {
  if (is.null(max_n) || max_n >= length(conditions)) return(conditions)
  
  max_n <- as.integer(max_n)
  if (max_n <= 0) return(conditions)
  
  if (strategy == "first") {
    return(conditions[seq_len(max_n)])
  }
  
  if (strategy == "random") {
    set.seed(seed)
    return(sample(conditions, max_n))
  }
  
  # "stratified": sample proportionally across year_span x content_area strata
  set.seed(seed)
  meta <- data.table::data.table(
    cond = conditions,
    year_span = sapply(conditions, function(c) parse_condition_id(c)$year_span),
    content   = sapply(conditions, function(c) parse_condition_id(c)$content_area)
  )
  meta[, stratum := paste(year_span, content, sep = "_")]
  
  # Allocate proportionally (at least 1 per non-empty stratum)
  strata_counts <- meta[, .N, by = stratum]
  strata_counts[, alloc := pmax(1L, as.integer(round(N / nrow(meta) * max_n)))]
  # Trim if over-allocated
  while (sum(strata_counts$alloc) > max_n) {
    biggest <- which.max(strata_counts$alloc)
    strata_counts$alloc[biggest] <- strata_counts$alloc[biggest] - 1L
  }
  
  selected <- character(0)
  for (r in seq_len(nrow(strata_counts))) {
    s <- strata_counts$stratum[r]
    k <- strata_counts$alloc[r]
    pool <- meta[stratum == s, cond]
    selected <- c(selected, sample(pool, min(k, length(pool))))
  }
  return(selected)
}


#' Estimate per-worker memory budget and compute safe worker count
#' @param dataset_id Character dataset ID (for file-size lookup)
#' @param n_cores_available Integer CPU core count
#' @param mem_per_worker_gb NULL (auto) or numeric override
#' @param total_mem_gb NULL (auto) or numeric override
#' @return Named list: n_workers, mem_per_worker_gb, total_mem_gb, limiting_factor
.compute_worker_count <- function(dataset_id, n_cores_available,
                                  mem_per_worker_gb = NULL,
                                  total_mem_gb = NULL) {
  
  # --- Total system memory ---
  if (is.null(total_mem_gb)) {
    total_mem_gb <- tryCatch({
      # Linux / EC2
      meminfo <- readLines("/proc/meminfo", n = 1)
      as.numeric(gsub("[^0-9]", "", meminfo)) / 1024 / 1024  # kB -> GB
    }, error = function(e) {
      tryCatch({
        # macOS
        raw <- system("sysctl -n hw.memsize", intern = TRUE)
        as.numeric(raw) / 1024^3
      }, error = function(e2) 16)  # fallback 16 GB
    })
  }
  
  # --- Per-worker memory estimate ---
  if (is.null(mem_per_worker_gb)) {
    # Heuristic: in-memory dataset is ~6-8x compressed .Rdata size,
    # plus ~0.5 GB overhead per worker for copula objects + result tables
    ds_config <- NULL
    if (exists("DATASETS", envir = .GlobalEnv)) {
      ds_config <- get("DATASETS", envir = .GlobalEnv)[[dataset_id]]
    }
    
    file_size_gb <- 0.05  # fallback
    if (!is.null(ds_config)) {
      use_sgp <- exists("USE_SGP_DATA", envir = .GlobalEnv) && isTRUE(get("USE_SGP_DATA", envir = .GlobalEnv))
      fpath <- if (use_sgp && !is.null(ds_config$local_path_sgp)) {
        ds_config$local_path_sgp
      } else {
        ds_config$local_path
      }
      if (file.exists(fpath)) file_size_gb <- file.info(fpath)$size / 1024^3
    }
    
    # R .Rdata typically decompresses 6-8x; add 0.5 GB worker overhead
    mem_per_worker_gb <- file_size_gb * 7 + 0.5
  }
  
  # --- Worker count ---
  # CPU-based cap (same formula as before)
  cores_to_reserve <- max(1, min(6, ceiling(n_cores_available / 40)))
  cpu_cap <- n_cores_available - cores_to_reserve
  
  # Memory-based cap: leave 20% for OS + host R process
  usable_mem <- total_mem_gb * 0.80
  mem_cap <- max(1L, as.integer(floor(usable_mem / mem_per_worker_gb)))
  
  n_workers <- min(cpu_cap, mem_cap)
  limiting <- if (cpu_cap <= mem_cap) "CPU" else "MEMORY"
  
  list(
    n_workers          = n_workers,
    mem_per_worker_gb  = round(mem_per_worker_gb, 2),
    total_mem_gb       = round(total_mem_gb, 1),
    cpu_cap            = cpu_cap,
    mem_cap            = mem_cap,
    limiting_factor    = limiting
  )
}


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
    
    # Get dataset configuration (check both DATASETS_CONFIG and DATASETS)
    if (is.null(dataset_config)) {
      if (exists("DATASETS_CONFIG")) {
        dataset_config <- DATASETS_CONFIG[[dataset_id]]
      } else if (exists("DATASETS")) {
        dataset_config <- DATASETS[[dataset_id]]
      }
    }
    
    if (!is.null(dataset_config)) {
      # Determine file path (EC2 vs local, SGP vs base)
      # CRITICAL: Check USE_SGP_DATA flag to load SGP-enriched data when available
      # The SGP data files contain pre-computed traditional SGP columns needed for
      # the Emp-Traditional comparison pair in STEP_2 visualizations
      use_sgp <- exists("USE_SGP_DATA") && isTRUE(USE_SGP_DATA)
      
      if (use_sgp && !is.null(dataset_config$local_path_sgp)) {
        ds_path <- if (exists("IS_EC2") && IS_EC2) {
          dataset_config$ec2_path_sgp
        } else {
          dataset_config$local_path_sgp
        }
        ds_object_name <- dataset_config$rdata_object_name_sgp
        cat("\n[WORKER] Loading SGP dataset:", dataset_id, "from", ds_path, "\n")
      } else {
        ds_path <- if (exists("IS_EC2") && IS_EC2) {
          dataset_config$ec2_path
        } else {
          dataset_config$local_path
        }
        ds_object_name <- dataset_config$rdata_object_name
        if (use_sgp) {
          cat("\n[WORKER] WARNING: SGP data not configured for", dataset_id, ", using base data\n")
        }
        cat("\n[WORKER] Loading dataset:", dataset_id, "from", ds_path, "\n")
      }
      
      load(ds_path)
      ds_data <- get(ds_object_name)
      
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
  # Include dataset_id for globally-unique condition identification across datasets,
  # and SCHOOL_NUMBER and DISTRICT_NUMBER for group-level aggregation (Panel B)
  result <- data.table(
    dataset_id = dataset_id,
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
  
  # 3. Canonical averaged copula (t-copula with stratum-specific median parameters)
  # This is the copula that would be used operationally for TIMSS/NAEP
  cat(" -> SGPc_avg...")
  sgpc_start <- Sys.time()
  canonical_cop <- tryCatch({
    create_canonical_copula(cond_meta$year_span, cond_meta$content_area, canonical_params)
  }, error = function(e) NULL)
  
  if (!is.null(canonical_cop)) {
    result[, sgpc_avg := sgpc_engine(u, v, canonical_cop, scale = "percentile")]
    # Log stability context from STEP_1 (first condition per dataset only, to avoid noise)
    canon_stability <- attr(canonical_cop, "overall_stability")
    if (!is.null(canon_stability) && !exists(".canonical_stability_logged")) {
      cat(sprintf(" [stability=%s]", canon_stability))
      assign(".canonical_stability_logged", TRUE, envir = parent.frame())
    }
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
  
  # Clayton (lower tail dependence)
  clayton_param <- max(0.001, 2 * tau / (1 - tau))
  clayton_cop <- claytonCopula(param = clayton_param)
  result[, sgpc_clayton := sgpc_engine(u, v, clayton_cop, scale = "percentile")]
  
  # t copula with df=4: extreme tail dependence stress test
  # STEP_1 manifest shows actual df median ranges 23.7 (1yr Writing) to 55.6 (1yr ELA)
  # across strata, with CI lower bounds ~22-28. df=4 is intentionally ~5x more extreme
  # than anything observed, demonstrating SGPc robustness under heavy mis-specification.
  t_rho <- sin(pi * tau / 2)
  t_cop <- tCopula(param = t_rho, df = 4)
  result[, sgpc_t := sgpc_engine(u, v, t_cop, scale = "percentile")]
  
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
  # If not, try to load dataset file using DATASETS config (respects USE_SGP_DATA)
  if (!exists("STATE_DATA_LONG")) {
    cat("Loading dataset file...\n")
    
    # First try: use DATASETS config (preferred, respects USE_SGP_DATA flag)
    ds_config <- NULL
    if (exists("DATASETS")) ds_config <- DATASETS[[dataset_id]]
    
    dataset_loaded <- FALSE
    if (!is.null(ds_config)) {
      use_sgp <- exists("USE_SGP_DATA") && isTRUE(USE_SGP_DATA)
      
      if (use_sgp && !is.null(ds_config$local_path_sgp)) {
        ds_path <- if (exists("IS_EC2") && IS_EC2) ds_config$ec2_path_sgp else ds_config$local_path_sgp
        ds_object <- ds_config$rdata_object_name_sgp
        cat("  Using SGP data (includes traditional SGP column)\n")
      } else {
        ds_path <- if (exists("IS_EC2") && IS_EC2) ds_config$ec2_path else ds_config$local_path
        ds_object <- ds_config$rdata_object_name
        if (use_sgp) cat("  WARNING: SGP data not configured, using base data\n")
      }
      
      if (file.exists(ds_path)) {
        load(ds_path)
        STATE_DATA_LONG <- get(ds_object)
        if (!inherits(STATE_DATA_LONG, "data.table")) {
          STATE_DATA_LONG <- as.data.table(STATE_DATA_LONG)
        }
        # Mark which dataset is loaded so compute_sgpc_variants() won't re-load
        .LOADED_DATASET_ID <- dataset_id
        cat("  Loaded from config:", ds_path, "\n")
        cat("  Rows:", format(nrow(STATE_DATA_LONG), big.mark = ","), "\n")
        dataset_loaded <- TRUE
      }
    }
    
    # Fallback: try multiple possible generic locations
    if (!dataset_loaded) {
      possible_paths <- c(
        file.path("SGP", paste0(dataset_id, ".Rdata")),
        file.path("data", paste0(dataset_id, ".rda")),
        paste0(dataset_id, ".Rdata"),
        paste0(dataset_id, ".rda")
      )
      
      dataset_file <- possible_paths[file.exists(possible_paths)][1]
      
      if (is.na(dataset_file)) {
        cat("Dataset file not found for", dataset_id, "\n")
        cat("  Tried config paths and:", paste(possible_paths, collapse = ", "), "\n")
        next
      }
      
      load(dataset_file)  # Loads STATE_DATA_LONG
      .LOADED_DATASET_ID <- dataset_id
      cat("  Loaded from fallback:", dataset_file, "\n")
      cat("  Rows:", format(nrow(STATE_DATA_LONG), big.mark = ","), "\n")
    }
  } else {
    # Ensure .LOADED_DATASET_ID is consistent with pre-loaded data
    if (!exists(".LOADED_DATASET_ID")) .LOADED_DATASET_ID <- dataset_id
    cat("Using pre-loaded STATE_DATA_LONG\n")
    cat("  Rows:", format(nrow(STATE_DATA_LONG), big.mark = ","), "\n")
  }
  
  # Get list of conditions from Phase 1
  conditions_all <- get_phase1_conditions(dataset_id)
  
  if (length(conditions_all) == 0) {
    cat("No Phase 1 conditions found for", dataset_id, "\n")
    next
  }
  
  cat("Found", length(conditions_all), "conditions from Phase 1\n")
  
  # --- Apply subset controls (for local profiling / smoke testing) ---
  conditions <- .subset_conditions(
    conditions_all,
    max_n    = STEP2_MAX_CONDITIONS,
    strategy = STEP2_SAMPLE_STRATEGY,
    seed     = STEP2_SEED
  )
  if (length(conditions) < length(conditions_all)) {
    cat(sprintf("  SUBSET MODE: %d of %d conditions selected (strategy=%s, seed=%d)\n",
                length(conditions), length(conditions_all),
                STEP2_SAMPLE_STRATEGY, STEP2_SEED))
  }
  
  # --- Performance logging setup ---
  perf_dir <- "STEP_2_SGPc_Sensitivity/results/perf"
  if (!dir.exists(perf_dir)) dir.create(perf_dir, recursive = TRUE, showWarnings = FALSE)
  
  perf_dataset <- list(
    dataset_id      = dataset_id,
    n_conditions    = length(conditions),
    n_conditions_total = length(conditions_all),
    subset_mode     = length(conditions) < length(conditions_all),
    use_parallel    = USE_PARALLEL,
    n_cores         = N_CORES,
    timestamp_start = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  dataset_wall_start <- Sys.time()
  
  # Batch load Phase 1 results for all conditions
  cat("Loading Phase 1 copula results...\n")
  phase1_load_start <- Sys.time()
  phase1_batch <- batch_load_phase1(dataset_id, conditions, verbose = TRUE)
  perf_dataset$phase1_load_secs <- as.numeric(difftime(Sys.time(), phase1_load_start, units = "secs"))
  
  # Process each condition (sequential or parallel)
  all_results <- list()
  
  cat("\nComputing SGPc variants...\n")
  compute_start <- Sys.time()
  
  if (USE_PARALLEL) {
    if (!requireNamespace("mirai", quietly = TRUE)) {
      stop("mirai package required for parallel processing. Install with: install.packages('mirai')")
    }
    
    require(mirai)
    
    # --- Memory-aware worker count ---
    winfo <- .compute_worker_count(
      dataset_id          = dataset_id,
      n_cores_available   = N_CORES,
      mem_per_worker_gb   = STEP2_MEMORY_PER_WORKER_GB,
      total_mem_gb        = STEP2_TOTAL_MEMORY_GB
    )
    n_workers <- winfo$n_workers
    
    cat(sprintf("Worker scaling:\n"))
    cat(sprintf("  System memory:   %.1f GB\n", winfo$total_mem_gb))
    cat(sprintf("  Per-worker est:  %.2f GB\n", winfo$mem_per_worker_gb))
    cat(sprintf("  CPU cap:         %d workers\n", winfo$cpu_cap))
    cat(sprintf("  Memory cap:      %d workers\n", winfo$mem_cap))
    cat(sprintf("  SELECTED:        %d workers  (limited by %s)\n", n_workers, winfo$limiting_factor))
    
    perf_dataset$n_workers          <- n_workers
    perf_dataset$mem_per_worker_gb  <- winfo$mem_per_worker_gb
    perf_dataset$total_mem_gb       <- winfo$total_mem_gb
    perf_dataset$worker_limit       <- winfo$limiting_factor
    
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
    
    # Check USE_SGP_DATA flag (needed for workers to load SGP-enriched data)
    USE_SGP_DATA_VALUE <- if (exists("USE_SGP_DATA", envir = .GlobalEnv)) {
      get("USE_SGP_DATA", envir = .GlobalEnv)
    } else {
      TRUE  # Default to TRUE so workers load SGP data when available
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
       IS_EC2 = IS_EC2_VALUE,
       USE_SGP_DATA = USE_SGP_DATA_VALUE)
    
    # Wait for export
    export_results <- export_data[]
    if (!all(sapply(export_results, isTRUE))) {
      stop("Failed to export function to some workers")
    }
    cat("Export complete\n")
    
    # ---------------------------------------------------------------
    # LOW-MEMORY DISPATCH: Workers load Phase 1 results individually
    # instead of receiving the full phase1_batch via serialization.
    # This avoids O(n_workers × phase1_batch_size) memory overhead.
    # ---------------------------------------------------------------
    cat("Starting mirai_map processing (worker-local Phase 1 loading)...\n")
    
    mirai_results <- mirai_map(
      .x = seq_along(conditions),
      .f = function(i, conditions, canonical_params, dataset_id) {
        cond_id <- conditions[i]
        
        # Worker loads its own Phase 1 results from disk (low memory)
        phase1_results <- load_phase1_condition(dataset_id, cond_id)
        
        # Periodic garbage collection (every 10 conditions)
        if (i %% 10 == 0) {
          gc(verbose = FALSE, reset = FALSE)
        }
        
        # Call compute_sgpc_variants with dataset_id (not data)
        result <- compute_sgpc_variants(
          condition_id = cond_id,
          dataset_id = dataset_id,
          phase1_results = phase1_results,
          canonical_params = canonical_params,
          dataset_config = DATASETS_CONFIG[[dataset_id]]
        )
        
        # Free Phase 1 objects immediately
        rm(phase1_results)
        
        result
      },
      .args = list(
        conditions = conditions,
        canonical_params = canonical_params,
        dataset_id = dataset_id
      )
    )
    
    # Free host-side phase1_batch now that workers load their own
    rm(phase1_batch); gc(verbose = FALSE)
    
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
  
  # Record compute time
  perf_dataset$compute_secs <- as.numeric(difftime(Sys.time(), compute_start, units = "secs"))
  
  # Combine all results
  save_start <- Sys.time()
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
    
    perf_dataset$n_obs   <- nrow(dataset_results)
    perf_dataset$n_ok    <- length(all_results)
    perf_dataset$rds_mb  <- round(file.info(output_file)$size / 1024^2, 1)
  } else {
    cat("\nNo results generated for", dataset_id, "\n\n")
    perf_dataset$n_obs <- 0
    perf_dataset$n_ok  <- 0
  }
  perf_dataset$save_secs <- as.numeric(difftime(Sys.time(), save_start, units = "secs"))
  perf_dataset$total_secs <- as.numeric(difftime(Sys.time(), dataset_wall_start, units = "secs"))
  perf_dataset$timestamp_end <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  # --- Write performance log ---
  perf_file <- file.path(perf_dir, paste0("step2_perf_", dataset_id, ".json"))
  tryCatch({
    jsonlite::write_json(perf_dataset, perf_file, auto_unbox = TRUE, pretty = TRUE)
    cat("Performance log:", perf_file, "\n")
  }, error = function(e) {
    cat("Warning: could not write perf log:", e$message, "\n")
  })
  
  # Summary timing table
  cat(sprintf("\n--- %s Performance Summary ---\n", dataset_id))
  cat(sprintf("  Phase 1 load:  %6.1f s\n", perf_dataset$phase1_load_secs))
  cat(sprintf("  Compute:       %6.1f s  (%.1f min)\n", perf_dataset$compute_secs, perf_dataset$compute_secs / 60))
  cat(sprintf("  Save:          %6.1f s\n", perf_dataset$save_secs))
  cat(sprintf("  TOTAL:         %6.1f s  (%.1f min)\n", perf_dataset$total_secs, perf_dataset$total_secs / 60))
  cat(sprintf("  Throughput:    %.2f conditions/min\n",
              perf_dataset$n_ok / (perf_dataset$compute_secs / 60)))
  cat("---\n\n")
}

cat("====================================================================\n")
cat("COMPUTATION COMPLETE\n")
cat("====================================================================\n\n")
