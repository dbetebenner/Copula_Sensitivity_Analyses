############################################################################
### PHASE 1: COPULA FAMILY SELECTION STUDY (PARALLEL VERSION)
### Parallelized across conditions using mirai or parallel package
###
### Objective: Identify which copula family consistently provides best fit
###           for longitudinal educational assessment data
###
### Hypothesis: T-copula will dominate due to heavy tails in educational
###             data, with tail dependence increasing as time between
###             observations increases.
###
### Parallelization Strategy:
###   - mirai (preferred): Uses NNG sockets, scales to 188+ workers
###   - parallel (fallback): Uses FORK/PSOCK, limited to ~96 workers
###   - Each condition processed independently on separate workers
###   - Expected speedup: proportional to worker count
############################################################################

require(data.table)
require(splines2)
require(copula)
require(parallel)

# Null-coalescing operator (for compatibility)
`%||%` <- function(x, y) if (is.null(x)) y else x

# Load mirai (required dependency for parallel processing)
library(mirai)

cat("====================================================================\n")
cat("PHASE 1: COPULA FAMILY SELECTION STUDY (MIRAI PARALLEL)\n")
cat("====================================================================\n")
cat("Using mirai package for scalable, cross-platform parallelization\n")
cat("mirai version:", as.character(packageVersion("mirai")), "\n")

# Detect cores and set up cluster
n_cores_available <- detectCores()

# ============================================================================
# ESTIMATE NUMBER OF CONDITIONS (before cluster creation)
# This allows us to create only as many workers as needed
# ============================================================================
n_conditions_expected <- NA

# Check if TEST_MODE is active and estimate condition count
if (exists("TEST_MODE", envir = .GlobalEnv) && get("TEST_MODE", envir = .GlobalEnv)) {
  # Get conditions per dataset (default 1)
  n_per_dataset <- 1
  if (exists("TEST_N_CONDITIONS_PER_DATASET", envir = .GlobalEnv)) {
    n_per_dataset <- get("TEST_N_CONDITIONS_PER_DATASET", envir = .GlobalEnv)
  }
  
  # Check if multi-dataset mode
  if (exists("ALL_DATASET_CONFIGS", envir = .GlobalEnv)) {
    n_datasets <- length(get("ALL_DATASET_CONFIGS", envir = .GlobalEnv))
    n_conditions_expected <- n_per_dataset * n_datasets
    cat("TEST_MODE: Expecting", n_conditions_expected, "conditions (", 
        n_per_dataset, "per dataset ×", n_datasets, "datasets)\n")
  } else if (exists("DATASETS_TO_RUN", envir = .GlobalEnv)) {
    n_datasets <- length(get("DATASETS_TO_RUN", envir = .GlobalEnv))
    n_conditions_expected <- n_per_dataset * n_datasets
    cat("TEST_MODE: Expecting", n_conditions_expected, "conditions (", 
        n_per_dataset, "per dataset ×", n_datasets, "datasets)\n")
  } else {
    # Single dataset mode
    n_conditions_expected <- n_per_dataset
    cat("TEST_MODE: Expecting", n_conditions_expected, "conditions\n")
  }
}

# Determine optimal core usage based on environment
if (exists("IS_EC2", envir = .GlobalEnv) && IS_EC2) {
  # EC2: Scale workers based on available cores
  # - Small instances (≤48 cores): Use n-2 cores (leave 2 for system)
  # - Large instances (>48 cores): Use n-4 cores (leave 4 for system overhead)
  if (n_cores_available <= 48) {
    n_cores_max <- n_cores_available - 2
  } else {
    n_cores_max <- n_cores_available - 4
  }
  cat("EC2 detected:", n_cores_available, "cores available, max workers:", n_cores_max, "\n")
} else {
  # Local: Use n-1 cores max
  n_cores_max <- n_cores_available - 1
}

# OPTIMIZATION: Use min(available cores, expected conditions)
# This prevents creating idle workers when processing fewer conditions than cores
if (!is.na(n_conditions_expected) && n_conditions_expected < n_cores_max) {
  n_cores_use <- n_conditions_expected
  cat("Optimized: Creating", n_cores_use, "workers (matched to", n_conditions_expected, "conditions)\n")
} else {
  n_cores_use <- n_cores_max
  if (!is.na(n_conditions_expected)) {
    cat("Using", n_cores_use, "workers for", n_conditions_expected, "conditions\n")
  }
}

################################################################################
### WORKER INITIALIZATION
################################################################################

cat("Initializing mirai daemons...\n")

# CRITICAL: Capture project root for daemon initialization
# Daemons start in home directory, need absolute paths
PROJECT_ROOT <- normalizePath(getwd(), mustWork = TRUE)
cat("  Project root:", PROJECT_ROOT, "\n")

# Create daemons (persistent background workers)
# output=TRUE: Show daemon output for debugging
# retry=FALSE: Don't mask errors by retrying failed tasks
daemons_result <- tryCatch({
  daemons(n_cores_use, output = TRUE, retry = FALSE)
  status <- status()
  list(
    success = TRUE, 
    n_daemons = status$connections,  # Count of connected daemons
    daemon_url = status$daemons       # Connection URL (for debugging)
  )
}, error = function(e) {
  cat("  ✗ mirai daemon creation failed:", e$message, "\n")
  list(success = FALSE, error = e$message)
})

if (!daemons_result$success) {
  stop("Failed to create mirai daemons: ", daemons_result$error)
}

n_workers_actual <- daemons_result$n_daemons
cat("  Type: mirai (NNG sockets, cross-platform)\n")
cat("  Daemons created:", n_workers_actual, "\n")
cat("  Connection URL:", daemons_result$daemon_url, "\n\n")

cat("Available cores:", n_cores_available, "\n")
cat("Using workers:", n_workers_actual, "\n\n")

# Capture N_BOOTSTRAP_GOF for workers
if (exists("N_BOOTSTRAP_GOF", envir = .GlobalEnv)) {
  N_BOOTSTRAP_GOF_VALUE <- get("N_BOOTSTRAP_GOF", envir = .GlobalEnv)
  cat("Goodness-of-Fit Testing: ENABLED (N =", N_BOOTSTRAP_GOF_VALUE, "bootstrap samples)\n")
} else {
  N_BOOTSTRAP_GOF_VALUE <- NULL
  cat("Goodness-of-Fit Testing: DISABLED\n")
}

# Capture CALCULATE_SGPC for workers
if (exists("CALCULATE_SGPC", envir = .GlobalEnv)) {
  CALCULATE_SGPC_VALUE <- get("CALCULATE_SGPC", envir = .GlobalEnv)
  cat("SGPc Calculation: ENABLED\n")
} else {
  CALCULATE_SGPC_VALUE <- FALSE
  cat("SGPc Calculation: DISABLED\n")
}

# Capture GENERATE_UNCERTAINTY_PLOTS for workers (bootstrap uncertainty bands)
if (exists("GENERATE_UNCERTAINTY_PLOTS", envir = .GlobalEnv)) {
  GENERATE_UNCERTAINTY_PLOTS_VALUE <- get("GENERATE_UNCERTAINTY_PLOTS", envir = .GlobalEnv)
} else {
  GENERATE_UNCERTAINTY_PLOTS_VALUE <- TRUE  # Default ON to match test_contour_plots.R
}

# Capture GENERATE_CONTOUR_PLOTS for workers (main visualization toggle)
if (exists("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv)) {
  GENERATE_CONTOUR_PLOTS_VALUE <- get("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv)
} else {
  GENERATE_CONTOUR_PLOTS_VALUE <- TRUE  # Default ON
}

# Capture N_BOOTSTRAP_UNCERTAINTY for workers
if (exists("N_BOOTSTRAP_UNCERTAINTY", envir = .GlobalEnv)) {
  N_BOOTSTRAP_UNCERTAINTY_VALUE <- get("N_BOOTSTRAP_UNCERTAINTY", envir = .GlobalEnv)
} else {
  N_BOOTSTRAP_UNCERTAINTY_VALUE <- 100  # Match test_contour_plots.R
}

# Capture BOOTSTRAP_ALL_FAMILIES for workers
if (exists("BOOTSTRAP_ALL_FAMILIES", envir = .GlobalEnv)) {
  BOOTSTRAP_ALL_FAMILIES_VALUE <- get("BOOTSTRAP_ALL_FAMILIES", envir = .GlobalEnv)
} else {
  BOOTSTRAP_ALL_FAMILIES_VALUE <- TRUE  # All 5 parametric families
}

# Capture GRID_SIZE for workers (main contour plot resolution)
if (exists("GRID_SIZE", envir = .GlobalEnv)) {
  GRID_SIZE_VALUE <- get("GRID_SIZE", envir = .GlobalEnv)
} else {
  GRID_SIZE_VALUE <- 300  # Default: high resolution
}

# Capture UNCERTAINTY_GRID_SIZE for workers (uncertainty overlay resolution)
if (exists("UNCERTAINTY_GRID_SIZE", envir = .GlobalEnv)) {
  UNCERTAINTY_GRID_SIZE_VALUE <- get("UNCERTAINTY_GRID_SIZE", envir = .GlobalEnv)
} else {
  UNCERTAINTY_GRID_SIZE_VALUE <- GRID_SIZE_VALUE  # Default: same as main grid
}

# Capture SKIP_COMONOTONIC for workers
if (exists("SKIP_COMONOTONIC", envir = .GlobalEnv)) {
  SKIP_COMONOTONIC_VALUE <- get("SKIP_COMONOTONIC", envir = .GlobalEnv)
} else {
  SKIP_COMONOTONIC_VALUE <- FALSE  # Default: include comonotonic
}

# Capture COMPARISON_FAMILIES for workers ("all" or "top3")
if (exists("COMPARISON_FAMILIES", envir = .GlobalEnv)) {
  COMPARISON_FAMILIES_VALUE <- get("COMPARISON_FAMILIES", envir = .GlobalEnv)
} else {
  COMPARISON_FAMILIES_VALUE <- "all"  # Default: all families
}

# Capture EXPORT_FORMATS for workers (multi-format export: pdf, svg, png)
if (exists("EXPORT_FORMATS", envir = .GlobalEnv)) {
  EXPORT_FORMATS_VALUE <- get("EXPORT_FORMATS", envir = .GlobalEnv)
} else {
  EXPORT_FORMATS_VALUE <- c("pdf", "svg", "png")  # Default: all formats
}

# Capture EXPORT_DPI for workers (resolution for raster outputs)
if (exists("EXPORT_DPI", envir = .GlobalEnv)) {
  EXPORT_DPI_VALUE <- get("EXPORT_DPI", envir = .GlobalEnv)
} else {
  EXPORT_DPI_VALUE <- 300  # Default: publication quality
}

# Capture EXPORT_VERBOSE for workers (print export messages)
if (exists("EXPORT_VERBOSE", envir = .GlobalEnv)) {
  EXPORT_VERBOSE_VALUE <- get("EXPORT_VERBOSE", envir = .GlobalEnv)
} else {
  EXPORT_VERBOSE_VALUE <- FALSE  # Default: quiet in batch mode
}

if (GENERATE_UNCERTAINTY_PLOTS_VALUE && exists("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv) && 
    get("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv)) {
  cat("Uncertainty Plots: ENABLED\n")
  cat("  Bootstrap samples:", N_BOOTSTRAP_UNCERTAINTY_VALUE, "\n")
  cat("  Uncertainty grid:", UNCERTAINTY_GRID_SIZE_VALUE, "×", UNCERTAINTY_GRID_SIZE_VALUE, "\n")
  cat("  Families:", ifelse(BOOTSTRAP_ALL_FAMILIES_VALUE, "ALL (5 parametric)", "BEST ONLY"), "\n")
  cat("  Mode: SEQUENTIAL within each parallel worker\n")
} else if (!GENERATE_UNCERTAINTY_PLOTS_VALUE) {
  cat("Uncertainty Plots: DISABLED\n")
}

cat("Plot Generation Settings:\n")
cat("  Generate contour plots:", GENERATE_CONTOUR_PLOTS_VALUE, "\n")
cat("  Main grid size:", GRID_SIZE_VALUE, "×", GRID_SIZE_VALUE, "\n")
cat("  Skip comonotonic:", SKIP_COMONOTONIC_VALUE, "\n")
cat("  Comparison families:", COMPARISON_FAMILIES_VALUE, "\n")
cat("Export Settings:\n")
cat("  Formats:", paste(EXPORT_FORMATS_VALUE, collapse = ", "), "\n")
cat("  DPI:", EXPORT_DPI_VALUE, "(raster @2x =", EXPORT_DPI_VALUE * 2, ")\n")
cat("  Verbose:", EXPORT_VERBOSE_VALUE, "\n")
cat("\n")

################################################################################
### DAEMON INITIALIZATION
################################################################################

cat("Setting up mirai daemons with everywhere()...\n")

# -------------------------------------------------------------------------
# OPTIMIZATION: Instead of loading combined data, each task loads ONLY
# the specific dataset it needs. This is much more efficient:
# - Dataset 1: ~2.3 GB (14M rows)
# - Dataset 2: ~600 MB (3.7M rows)
# - Dataset 3: ~600 MB (3.6M rows)
# - Dataset 4: ~250 MB (1.6M rows)
# vs. Combined: ~3.74 GB (23M rows)
# -------------------------------------------------------------------------

# Get DATASETS config for daemon use
if (!exists("DATASETS", envir = .GlobalEnv)) {
  stop("ERROR: DATASETS not found in .GlobalEnv. Ensure dataset_configs.R is sourced first.")
}
DATASETS_CONFIG <- get("DATASETS", envir = .GlobalEnv)

# Get USE_SGP_DATA and IS_EC2 flags
USE_SGP_DATA_VALUE <- if (exists("USE_SGP_DATA", envir = .GlobalEnv)) get("USE_SGP_DATA", envir = .GlobalEnv) else FALSE
IS_EC2_VALUE <- if (exists("IS_EC2", envir = .GlobalEnv)) get("IS_EC2", envir = .GlobalEnv) else FALSE

cat("  Data loading mode: PER-TASK (each task loads only its dataset)\n")
cat("  USE_SGP_DATA:", USE_SGP_DATA_VALUE, "\n")
cat("  IS_EC2:", IS_EC2_VALUE, "\n")
cat("  Datasets available:", paste(names(DATASETS_CONFIG), collapse = ", "), "\n")

# -------------------------------------------------------------------------
# STEP 1: Load packages and source function files ONCE per daemon
# -------------------------------------------------------------------------
cat("  Initializing packages and functions on all daemons...\n")

init_packages <- everywhere({
    # Debug: Log daemon startup
    cat("[DAEMON] Starting initialization at", format(Sys.time(), "%H:%M:%S"), "\n")
    cat("[DAEMON] Working directory:", getwd(), "\n")
    cat("[DAEMON] PROJECT_ROOT:", PROJECT_ROOT, "\n")
    
    # Set working directory
    tryCatch({
      setwd(PROJECT_ROOT)
      cat("[DAEMON] Changed to PROJECT_ROOT successfully\n")
    }, error = function(e) {
      cat("[DAEMON ERROR] setwd failed:", conditionMessage(e), "\n")
      stop(e)
    })
    
    # Load packages
    tryCatch({
      suppressPackageStartupMessages({
        library(data.table)
        library(splines2)
        library(copula)
      })
      cat("[DAEMON] Packages loaded successfully\n")
      
      # CRITICAL FOR EC2: Force single-threaded execution to prevent oversubscription
      # With 188+ daemons, allowing multi-threading per daemon causes CPU thrashing
      data.table::setDTthreads(1)
      Sys.setenv(
        OMP_NUM_THREADS = "1",
        MKL_NUM_THREADS = "1",
        OPENBLAS_NUM_THREADS = "1",
        VECLIB_MAXIMUM_THREADS = "1",
        NUMEXPR_NUM_THREADS = "1"
      )
      cat("[DAEMON] Thread management: Single-threaded mode enabled (prevents oversubscription)\n")
      
    }, error = function(e) {
      cat("[DAEMON ERROR] Package loading failed:", conditionMessage(e), "\n")
      stop(e)
    })
    
    # Source all required function files using absolute paths
    func_files <- c("longitudinal_pairs.R", "ispline_ecdf.R", "copula_bootstrap.R", 
                    "sgpc_engine.R", "copula_contour_plots.R", "dataset_configs.R")
    for (ff in func_files) {
      tryCatch({
        # For dataset_configs.R, use project root, not functions/ subdirectory
        file_path <- if (ff == "dataset_configs.R") {
          file.path(PROJECT_ROOT, ff)
        } else {
          file.path(PROJECT_ROOT, "functions", ff)
        }
        source(file_path)
        cat("[DAEMON] Sourced:", ff, "\n")
      }, error = function(e) {
        cat("[DAEMON ERROR] Failed to source", ff, ":", conditionMessage(e), "\n")
        stop(e)
      })
    }
    
    cat("[DAEMON] Package initialization complete\n")
    TRUE  # Return success indicator
  }, PROJECT_ROOT = PROJECT_ROOT)

# Wait for package initialization to complete
cat("  Waiting for daemon package initialization...\n")
init_packages_results <- init_packages[]

# Check results
n_success <- sum(sapply(init_packages_results, function(x) isTRUE(x) || identical(x, TRUE)))
n_fail <- length(init_packages_results) - n_success

if (n_fail > 0) {
  cat("  WARNING: Some daemons failed package initialization (", n_fail, "/", length(init_packages_results), ")\n")
  # Show failed results
  for (i in seq_along(init_packages_results)) {
    if (!isTRUE(init_packages_results[[i]])) {
      cat("    Daemon", i, ":", as.character(init_packages_results[[i]]), "\n")
    }
  }
} else {
  cat("  ✓ Packages and functions loaded on all", length(init_packages_results), "daemons\n")
}

# NOTE: Data export (STATE_DATA_LONG, process_condition, config values) is done
# later, just before mirai_map(), after process_condition is defined.
cat("  Package initialization complete. Data export deferred until process_condition is defined.\n\n")

cat("Daemons initialized successfully.\n\n")

################################################################################
### CONFIGURATION
################################################################################

# All copula families to test
# Including comonotonic (Fréchet-Hoeffding upper bound) to show how badly
# the implicit TAMP assumption (perfect positive dependence) misfits the data
# Note: We focus on t-copula with data-driven df estimation (not fixed df)
# as preliminary results showed free df consistently dominates fixed df variants
#
# SKIP_COMONOTONIC_VALUE: When TRUE, excludes comonotonic from testing
# (comonotonic is never selected as best fit and adds ~15% overhead)
if (SKIP_COMONOTONIC_VALUE) {
  COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank")
  cat("Copula families: gaussian, t, clayton, gumbel, frank (comonotonic SKIPPED)\n")
} else {
  COPULA_FAMILIES <- c("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")
  cat("Copula families: gaussian, t, clayton, gumbel, frank, comonotonic\n")
}

# Define test conditions
# Three modes:
# 1. ALL_DATASET_CONFIGS mode: Generate conditions for ALL datasets (from master_analysis.R)
# 2. Strategic subset: Representative sampling for family selection (single dataset)
# 3. Exhaustive: All valid combinations for transition analysis (single dataset)

# Check if we should use exhaustive conditions
USE_EXHAUSTIVE_CONDITIONS <- FALSE
if (exists("USE_EXHAUSTIVE_ALL_DATASETS", envir = .GlobalEnv)) {
  USE_EXHAUSTIVE_CONDITIONS <- get("USE_EXHAUSTIVE_ALL_DATASETS", envir = .GlobalEnv)
}

################################################################################
### MULTI-DATASET MODE: Generate conditions for ALL datasets
################################################################################

# Check if ALL_DATASET_CONFIGS exists (set by master_analysis.R for all-dataset processing)
if (exists("ALL_DATASET_CONFIGS", envir = .GlobalEnv)) {
  
  all_dataset_configs <- get("ALL_DATASET_CONFIGS", envir = .GlobalEnv)
  
  cat("====================================================================\n")
  cat("MULTI-DATASET MODE: Generating conditions for ALL datasets\n")
  cat("====================================================================\n")
  cat("Datasets:", paste(names(all_dataset_configs), collapse = ", "), "\n")
  cat("Exhaustive mode:", USE_EXHAUSTIVE_CONDITIONS, "\n\n")
  
  # Generate conditions for each dataset
  CONDITIONS <- list()
  
  for (ds_id in names(all_dataset_configs)) {
    ds_config <- all_dataset_configs[[ds_id]]
    
    cat("Generating conditions for:", ds_config$name, "\n")
    
    if (USE_EXHAUSTIVE_CONDITIONS) {
      # Generate exhaustive conditions for this dataset
      ds_conditions <- generate_exhaustive_conditions(ds_config, max_year_span = 4)
      
      # Rename year_span to span for consistency
      for (i in seq_along(ds_conditions)) {
        ds_conditions[[i]]$span <- ds_conditions[[i]]$year_span
      }
    } else {
      # Use strategic subset (will be filtered by content area later)
      ds_conditions <- list(
        # 1-YEAR SPANS
        list(grade_prior = 3, grade_current = 4, year_prior = "2010", content = "MATHEMATICS", span = 1),
        list(grade_prior = 3, grade_current = 4, year_prior = "2010", content = "READING", span = 1),
        list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "MATHEMATICS", span = 1),
        list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 1),
        list(grade_prior = 6, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 1),
        list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "READING", span = 1),
        list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "READING", span = 1),
        # 2-YEAR SPANS
        list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 2),
        list(grade_prior = 5, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 2),
        list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "READING", span = 2),
        # 3-YEAR SPANS
        list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 3),
        list(grade_prior = 5, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 3),
        list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "READING", span = 3),
        # 4-YEAR SPANS
        list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "MATHEMATICS", span = 4),
        list(grade_prior = 5, grade_current = 9, year_prior = "2009", content = "MATHEMATICS", span = 4),
        list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "READING", span = 4)
      )
    }
    
    # Filter by available content areas for this dataset
    available_content_areas <- ds_config$content_areas
    ds_conditions <- ds_conditions[sapply(ds_conditions, function(cond) {
      cond$content %in% available_content_areas
    })]
    
    # Enrich each condition with dataset metadata
    for (i in seq_along(ds_conditions)) {
      cond <- ds_conditions[[i]]
      
      # Normalize naming
      if (!is.null(cond$span) && is.null(cond$year_span)) {
        cond$year_span <- cond$span
      }
      
      # Calculate year_current
      year_current <- as.character(as.numeric(cond$year_prior) + cond$year_span)
      
      # Add dataset identifiers
      cond$dataset_id <- ds_config$id
      cond$dataset_name <- ds_config$name
      cond$anonymized_state <- ds_config$anonymized_state
      
      # Add scaling metadata
      cond$year_current <- year_current
      cond$prior_scaling_type <- get_scaling_type(ds_config, cond$year_prior)
      cond$current_scaling_type <- get_scaling_type(ds_config, year_current)
      cond$scaling_transition_type <- get_scaling_transition_type(ds_config, cond$year_prior, year_current)
      
      # Add transition metadata
      cond$has_transition <- ds_config$has_transition
      cond$transition_year <- if (ds_config$has_transition) ds_config$transition_year else NA
      cond$includes_transition_span <- crosses_transition(ds_config, cond$year_prior, year_current)
      cond$transition_period <- get_transition_period(ds_config, cond$year_prior, year_current)
      
      ds_conditions[[i]] <- cond
    }
    
    cat("  Generated", length(ds_conditions), "conditions\n")
    
    # Append to main CONDITIONS list
    CONDITIONS <- c(CONDITIONS, ds_conditions)
  }
  
  cat("\n✓ Total conditions across all datasets:", length(CONDITIONS), "\n")
  
  # Breakdown by dataset
  cat("\nBreakdown by dataset:\n")
  for (ds_id in names(all_dataset_configs)) {
    n_cond <- sum(sapply(CONDITIONS, function(c) c$dataset_id == ds_id))
    cat("  ", ds_id, ":", n_cond, "conditions\n")
  }
  cat("\n")
  
  # === RANDOMIZE CONDITION ORDER ===
  # Shuffle conditions to distribute dataset load evenly across workers
  # This prevents all workers from hitting the largest dataset simultaneously at startup
  # Use set.seed() for reproducibility (remove seed for true randomization each run)
  set.seed(42)
  CONDITIONS <- sample(CONDITIONS)
  cat("✓ Conditions randomized to distribute dataset load across workers\n")
  cat("  (This prevents memory spikes from all workers loading dataset_1 simultaneously)\n\n")
  # === END RANDOMIZATION ===
  
  # Skip the single-dataset enrichment/filtering sections below
  MULTI_DATASET_MODE <- TRUE
  
} else {
  
  ################################################################################
  ### SINGLE DATASET MODE: Original behavior
  ################################################################################
  
  MULTI_DATASET_MODE <- FALSE
  
  if (USE_EXHAUSTIVE_CONDITIONS) {
    cat("====================================================================\n")
    cat("EXHAUSTIVE MODE: ENABLED (Global setting)\n")
    cat("====================================================================\n")
  }
  
  if (USE_EXHAUSTIVE_CONDITIONS) {
    cat("Using EXHAUSTIVE conditions for", 
        if(exists("current_dataset")) current_dataset$name else "dataset", "\n")
    cat("  (All valid year/grade/content combinations across 1-4 year spans)\n")
    cat("  Purpose: Establish copula stability across time spans\n\n")
    
    # Generate all valid conditions for this dataset
    CONDITIONS <- generate_exhaustive_conditions(current_dataset, max_year_span = 4)
    
    # Rename year_span to span for consistency with parallel version
    for (i in seq_along(CONDITIONS)) {
      CONDITIONS[[i]]$span <- CONDITIONS[[i]]$year_span
    }
    
  } else {
    cat("Using STRATEGIC SUBSET conditions\n")
    cat("  (Representative sampling for copula family selection)\n\n")
    
    # Strategic subset conditions
    CONDITIONS <- list(
      # === 1-YEAR SPANS ===
      list(grade_prior = 3, grade_current = 4, year_prior = "2010", content = "MATHEMATICS", span = 1),
      list(grade_prior = 3, grade_current = 4, year_prior = "2010", content = "READING", span = 1),
      list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "MATHEMATICS", span = 1),
      list(grade_prior = 4, grade_current = 5, year_prior = "2011", content = "MATHEMATICS", span = 1),
      list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 1),
      list(grade_prior = 6, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 1),
      list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "READING", span = 1),
      list(grade_prior = 5, grade_current = 6, year_prior = "2010", content = "READING", span = 1),
      list(grade_prior = 4, grade_current = 5, year_prior = "2010", content = "WRITING", span = 1),
      list(grade_prior = 7, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 1),
      list(grade_prior = 7, grade_current = 8, year_prior = "2010", content = "READING", span = 1),
      # === 2-YEAR SPANS ===
      list(grade_prior = 3, grade_current = 5, year_prior = "2010", content = "MATHEMATICS", span = 2),
      list(grade_prior = 3, grade_current = 5, year_prior = "2010", content = "READING", span = 2),
      list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 2),
      list(grade_prior = 4, grade_current = 6, year_prior = "2011", content = "MATHEMATICS", span = 2),
      list(grade_prior = 5, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 2),
      list(grade_prior = 6, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 2),
      list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "READING", span = 2),
      list(grade_prior = 5, grade_current = 7, year_prior = "2010", content = "READING", span = 2),
      list(grade_prior = 4, grade_current = 6, year_prior = "2010", content = "WRITING", span = 2),
      list(grade_prior = 7, grade_current = 9, year_prior = "2010", content = "MATHEMATICS", span = 2),
      list(grade_prior = 7, grade_current = 9, year_prior = "2010", content = "READING", span = 2),
      # === 3-YEAR SPANS ===
      list(grade_prior = 3, grade_current = 6, year_prior = "2010", content = "MATHEMATICS", span = 3),
      list(grade_prior = 3, grade_current = 6, year_prior = "2010", content = "READING", span = 3),
      list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "MATHEMATICS", span = 3),
      list(grade_prior = 4, grade_current = 7, year_prior = "2009", content = "MATHEMATICS", span = 3),
      list(grade_prior = 5, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 3),
      list(grade_prior = 6, grade_current = 9, year_prior = "2010", content = "MATHEMATICS", span = 3),
      list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "READING", span = 3),
      list(grade_prior = 5, grade_current = 8, year_prior = "2010", content = "READING", span = 3),
      list(grade_prior = 4, grade_current = 7, year_prior = "2010", content = "WRITING", span = 3),
      list(grade_prior = 7, grade_current = 10, year_prior = "2009", content = "MATHEMATICS", span = 3),
      list(grade_prior = 7, grade_current = 10, year_prior = "2009", content = "READING", span = 3),
      # === 4-YEAR SPANS ===
      list(grade_prior = 3, grade_current = 7, year_prior = "2009", content = "MATHEMATICS", span = 4),
      list(grade_prior = 3, grade_current = 7, year_prior = "2009", content = "READING", span = 4),
      list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "MATHEMATICS", span = 4),
      list(grade_prior = 4, grade_current = 8, year_prior = "2010", content = "MATHEMATICS", span = 4),
      list(grade_prior = 5, grade_current = 9, year_prior = "2009", content = "MATHEMATICS", span = 4),
      list(grade_prior = 6, grade_current = 10, year_prior = "2009", content = "MATHEMATICS", span = 4),
      list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "READING", span = 4),
      list(grade_prior = 5, grade_current = 9, year_prior = "2009", content = "READING", span = 4),
      list(grade_prior = 4, grade_current = 8, year_prior = "2009", content = "WRITING", span = 4)
    )
  }
}

################################################################################
### ENRICH CONDITIONS WITH DATASET METADATA (Single-dataset mode only)
################################################################################

# Skip if we're in multi-dataset mode (already enriched above)
if (!exists("MULTI_DATASET_MODE") || !MULTI_DATASET_MODE) {
  
  # Add dataset-specific metadata to each condition using helper functions
  if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)) {
    cat("\n")
    cat("====================================================================\n")
    cat("ENRICHING CONDITIONS WITH DATASET METADATA\n")
    cat("====================================================================\n\n")
    
    for (i in seq_along(CONDITIONS)) {
      cond <- CONDITIONS[[i]]
      
      # Normalize naming: parallel version uses 'span', but we need 'year_span' for consistency
      if (!is.null(cond$span) && is.null(cond$year_span)) {
        cond$year_span <- cond$span
      }
      
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
    cat("  Total conditions:", length(CONDITIONS), "\n\n")
  }
  
  ################################################################################
  ### FILTER CONDITIONS BY AVAILABLE CONTENT AREAS (Single-dataset mode only)
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
}

################################################################################
### QUICK TEST MODE: MINIMAL CONDITIONS FOR FAST LOCAL VALIDATION
################################################################################

# QUICK_TEST_MODE takes precedence over TEST_MODE - provides fastest possible validation
# by selecting a minimal number of conditions from the smallest dataset
if (exists("QUICK_TEST_MODE", envir = .GlobalEnv) && get("QUICK_TEST_MODE", envir = .GlobalEnv)) {
  
  n_quick_test <- 1  # Default
  if (exists("QUICK_TEST_N_CONDITIONS", envir = .GlobalEnv)) {
    n_quick_test <- get("QUICK_TEST_N_CONDITIONS", envir = .GlobalEnv)
  }
  
  prefer_smallest <- TRUE  # Default
  if (exists("QUICK_TEST_PREFER_SMALLEST", envir = .GlobalEnv)) {
    prefer_smallest <- get("QUICK_TEST_PREFER_SMALLEST", envir = .GlobalEnv)
  }
  
  cat("\n")
  cat("====================================================================\n")
  cat("QUICK TEST MODE: FAST LOCAL VALIDATION\n")
  cat("====================================================================\n")
  cat("Target conditions:", n_quick_test, "\n")
  cat("Prefer smallest dataset:", prefer_smallest, "\n")
  
  if (prefer_smallest && exists("MULTI_DATASET_MODE") && MULTI_DATASET_MODE) {
    # Filter to smallest dataset (dataset_4) first
    # Dataset sizes: dataset_1 (~14M), dataset_2, dataset_3, dataset_4 (~1.6M)
    smallest_dataset <- "dataset_4"
    
    # Get conditions from smallest dataset
    ds4_conditions_idx <- which(sapply(CONDITIONS, function(c) c$dataset_id == smallest_dataset))
    
    if (length(ds4_conditions_idx) > 0) {
      cat("Filtering to", smallest_dataset, "(smallest, ~1.6M rows)...\n")
      cat("  Available conditions from", smallest_dataset, ":", length(ds4_conditions_idx), "\n")
      
      # Take first n_quick_test conditions from this dataset
      n_to_select <- min(n_quick_test, length(ds4_conditions_idx))
      selected_idx <- ds4_conditions_idx[seq_len(n_to_select)]
      CONDITIONS <- CONDITIONS[selected_idx]
      
      cat("  Selected:", length(CONDITIONS), "condition(s)\n")
    } else {
      # Fallback: just take first n conditions from randomized pool
      cat("WARNING: No conditions found for", smallest_dataset, ", using first", n_quick_test, "from pool\n")
      CONDITIONS <- CONDITIONS[seq_len(min(n_quick_test, length(CONDITIONS)))]
    }
  } else {
    # Single dataset mode or no preference - just take first n conditions
    cat("Selecting first", n_quick_test, "condition(s) from pool...\n")
    CONDITIONS <- CONDITIONS[seq_len(min(n_quick_test, length(CONDITIONS)))]
  }
  
  # Display selected conditions
  cat("\nSelected conditions for quick test:\n")
  for (i in seq_along(CONDITIONS)) {
    cond <- CONDITIONS[[i]]
    cat(sprintf("  %d. %s: G%d->G%d (%s, %s, span=%d)\n", 
               i, 
               cond$dataset_id %||% "unknown",
               cond$grade_prior, cond$grade_current, 
               cond$year_prior, cond$content, 
               cond$year_span %||% cond$span))
  }
  cat("\n")
  cat("Total conditions:", length(CONDITIONS), "\n")
  cat("====================================================================\n\n")
  
  # Skip TEST_MODE filtering since QUICK_TEST_MODE takes precedence
  
} else if (exists("TEST_MODE", envir = .GlobalEnv) && get("TEST_MODE", envir = .GlobalEnv)) {
  
################################################################################
### TEST MODE: LIMIT CONDITIONS FOR VALIDATION (per-dataset)
################################################################################
  
  n_conditions_test <- 1  # Default
  if (exists("TEST_N_CONDITIONS_PER_DATASET", envir = .GlobalEnv)) {
    n_conditions_test <- get("TEST_N_CONDITIONS_PER_DATASET", envir = .GlobalEnv)
  }
  
  # In multi-dataset mode, multiply by number of datasets
  if (exists("MULTI_DATASET_MODE") && MULTI_DATASET_MODE && 
      exists("ALL_DATASET_CONFIGS", envir = .GlobalEnv)) {
    n_datasets <- length(get("ALL_DATASET_CONFIGS", envir = .GlobalEnv))
    n_conditions_total <- n_conditions_test * n_datasets
    cat("\n")
    cat("====================================================================\n")
    cat("TEST MODE: MULTI-DATASET\n")
    cat("====================================================================\n")
    cat("Conditions per dataset:", n_conditions_test, "\n")
    cat("Number of datasets:", n_datasets, "\n")
    cat("Total conditions target:", n_conditions_total, "\n\n")
    
    # Select n conditions per dataset
    all_dataset_configs <- get("ALL_DATASET_CONFIGS", envir = .GlobalEnv)
    selected_conditions <- list()
    
    for (ds_id in names(all_dataset_configs)) {
      ds_conditions_idx <- which(sapply(CONDITIONS, function(c) c$dataset_id == ds_id))
      if (length(ds_conditions_idx) > n_conditions_test) {
        # Select first n_conditions_test from this dataset
        ds_conditions_idx <- ds_conditions_idx[1:n_conditions_test]
      }
      selected_conditions <- c(selected_conditions, CONDITIONS[ds_conditions_idx])
      cat("  ", ds_id, ": selected", length(ds_conditions_idx), "of", 
          sum(sapply(CONDITIONS, function(c) c$dataset_id == ds_id)), "conditions\n")
    }
    
    CONDITIONS <- selected_conditions
    cat("\nTotal conditions selected:", length(CONDITIONS), "\n")
    cat("====================================================================\n\n")
    
  } else {
    # Single-dataset mode
    original_count_test <- length(CONDITIONS)
    
    if (original_count_test > n_conditions_test) {
      cat("\n")
      cat("====================================================================\n")
      cat("TEST MODE: LIMITING CONDITIONS\n")
      cat("====================================================================\n")
      cat("Original conditions:", original_count_test, "\n")
      cat("Test subset size:", n_conditions_test, "\n")
      
      # Select diverse conditions across time spans if possible
      if (n_conditions_test >= 4 && USE_EXHAUSTIVE_CONDITIONS) {
        spans_available <- sapply(CONDITIONS, function(c) c$year_span %||% c$span)
        selected_indices <- c()
        
        for (span in 1:4) {
          span_indices <- which(spans_available == span)
          if (length(span_indices) > 0) {
            selected_indices <- c(selected_indices, span_indices[1])
            if (length(selected_indices) >= n_conditions_test) break
          }
        }
        
        CONDITIONS <- CONDITIONS[selected_indices]
        cat("Selected conditions:")
        for (i in seq_along(CONDITIONS)) {
          cond <- CONDITIONS[[i]]
          cat(sprintf("\n  %d. G%d->G%d (%s, %s, span=%d)", 
                     i, cond$grade_prior, cond$grade_current, 
                     cond$year_prior, cond$content, 
                     cond$year_span %||% cond$span))
        }
      } else {
        CONDITIONS <- CONDITIONS[1:n_conditions_test]
        cat("Selected first", n_conditions_test, "condition(s)\n")
      }
      
      cat("\n")
      cat("Remaining conditions:", length(CONDITIONS), "\n")
      cat("====================================================================\n\n")
    }
  }
}

################################################################################
### CHECKPOINT/RESUME: FILTER ALREADY-COMPLETED CONDITIONS
################################################################################

# Ensure checkpoint functions are available (in case running standalone)
if (!exists("get_completed_conditions") && file.exists("functions/checkpoint_utils.R")) {
  source("functions/checkpoint_utils.R")
}

# Check for SKIP_COMPLETED_CONDITIONS setting (for spot instance resilience)
SKIP_COMPLETED_CONDITIONS_VALUE <- FALSE
if (exists("SKIP_COMPLETED_CONDITIONS", envir = .GlobalEnv)) {
  SKIP_COMPLETED_CONDITIONS_VALUE <- get("SKIP_COMPLETED_CONDITIONS", envir = .GlobalEnv)
}

if (SKIP_COMPLETED_CONDITIONS_VALUE && length(CONDITIONS) > 0 && 
    exists("get_completed_conditions")) {
  cat("\n")
  cat("====================================================================\n")
  cat("CHECKPOINT/RESUME: FILTERING COMPLETED CONDITIONS\n")
  cat("====================================================================\n")
  
  # Get completed conditions
  completed_conditions <- get_completed_conditions("STEP_1_Family_Selection/results")
  
  if (nrow(completed_conditions) > 0) {
    original_count <- length(CONDITIONS)
    
    # Use get_remaining_conditions to filter
    CONDITIONS <- get_remaining_conditions(CONDITIONS, completed_conditions)
    
    skipped_count <- original_count - length(CONDITIONS)
    
    cat("Previously completed:", skipped_count, "conditions\n")
    cat("Remaining to process:", length(CONDITIONS), "conditions\n")
    
    if (length(CONDITIONS) == 0) {
      cat("\nAll conditions already completed! Nothing to process.\n")
      cat("====================================================================\n\n")
    } else {
      cat("\nResuming from checkpoint...\n")
      cat("====================================================================\n\n")
    }
  } else {
    cat("No previously completed conditions found.\n")
    cat("Starting fresh analysis...\n")
    cat("====================================================================\n\n")
  }
}

cat("Total conditions to test:", length(CONDITIONS), "\n")
cat("Copula families:", paste(COPULA_FAMILIES, collapse = ", "), "\n")
cat("Total fits:", length(CONDITIONS) * length(COPULA_FAMILIES), "\n\n")

################################################################################
### DEFINE WORKER FUNCTION
################################################################################

# Function to process a single condition (runs on each worker independently)
process_condition <- function(i, cond, copula_families, progress_file, total_conditions) {
  
  # This function runs on each worker independently
  # It must be self-contained and return a complete result
  
  # === DETAILED STEP TIMING INFRASTRUCTURE ===
  overall_start <- Sys.time()
  step_timings <- list()  # Store timing for each step
  current_step_start <- NULL
  
  # Helper function to record step timing
  record_step <- function(step_name, extra_info = NULL) {
    if (!is.null(current_step_start)) {
      elapsed <- as.numeric(difftime(Sys.time(), current_step_start, units = "secs"))
      step_timings[[step_name]] <<- list(
        elapsed_secs = elapsed,
        extra_info = extra_info
      )
    }
  }
  
  # Helper function to write detailed progress file to condition directory
  write_condition_progress <- function(output_dir, status, error_msg = NULL) {
    if (is.null(output_dir) || !dir.exists(output_dir)) return(invisible(NULL))
    
    progress_file_path <- file.path(output_dir, "condition.progress")
    overall_elapsed <- as.numeric(difftime(Sys.time(), overall_start, units = "secs"))
    
    # Build condition identifier
    year_current <- if (!is.null(cond$year_current)) cond$year_current else 
                    as.character(as.numeric(cond$year_prior) + cond$year_span)
    dataset_id <- if (!is.null(cond$dataset_id)) cond$dataset_id else "unknown"
    
    # Open file and write header
    sink(progress_file_path)
    on.exit(sink(), add = TRUE)
    
    cat(paste(rep("=", 70), collapse = ""), "\n")
    cat("CONDITION PROGRESS REPORT\n")
    cat(paste(rep("=", 70), collapse = ""), "\n")
    cat("Dataset:     ", dataset_id, "\n")
    cat("Content:     ", cond$content, "\n")
    cat("Transition:  G", cond$grade_prior, " -> G", cond$grade_current, "\n", sep = "")
    cat("Years:       ", cond$year_prior, " -> ", year_current, "\n")
    cat("Started:     ", format(overall_start, "%Y-%m-%d %H:%M:%S"), "\n")
    cat("Completed:   ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
    cat(paste(rep("-", 70), collapse = ""), "\n\n")
    
    # Step timing breakdown
    cat("STEP TIMING BREAKDOWN:\n")
    cat(paste(rep("-", 70), collapse = ""), "\n")
    
    total_accounted <- 0
    bottleneck_step <- NULL
    bottleneck_pct <- 0
    
    for (step_name in names(step_timings)) {
      result <- step_timings[[step_name]]
      pct <- if (overall_elapsed > 0) (result$elapsed_secs / overall_elapsed) * 100 else 0
      
      # Track bottleneck
      if (pct > bottleneck_pct) {
        bottleneck_pct <- pct
        bottleneck_step <- step_name
      }
      
      # Format time string
      if (result$elapsed_secs > 60) {
        time_str <- sprintf("%8.1f sec (%5.1f min)", result$elapsed_secs, result$elapsed_secs / 60)
      } else {
        time_str <- sprintf("%8.1f sec           ", result$elapsed_secs)
      }
      
      # Bottleneck marker
      marker <- if (pct > 40) " <-- BOTTLENECK" else ""
      
      cat(sprintf("%-25s %s  [%5.1f%%]%s\n", paste0(step_name, ":"), time_str, pct, marker))
      
      if (!is.null(result$extra_info)) {
        cat(sprintf("%-25s (%s)\n", "", result$extra_info))
      }
      
      total_accounted <- total_accounted + result$elapsed_secs
    }
    
    cat(paste(rep("-", 70), collapse = ""), "\n")
    cat(sprintf("%-25s %8.1f sec (%5.1f min)\n", "TOTAL:", overall_elapsed, overall_elapsed / 60))
    cat(paste(rep("=", 70), collapse = ""), "\n\n")
    
    # Status summary
    cat("STATUS: ", status, "\n")
    if (!is.null(error_msg)) {
      cat("ERROR:  ", error_msg, "\n")
    }
    if (!is.null(bottleneck_step) && bottleneck_pct > 30) {
      cat("BOTTLENECK: ", bottleneck_step, " (", round(bottleneck_pct, 1), "%)\n", sep = "")
    }
    cat(paste(rep("=", 70), collapse = ""), "\n")
    
    invisible(NULL)
  }
  # === END TIMING INFRASTRUCTURE ===
  
  # === PROGRESS TRACKING: START (central log) ===
  start_msg <- sprintf("[%s] STARTED  %3d/%d: %-4s G%d->G%d (%s->%s)\n",
                       format(overall_start, "%H:%M:%S"),
                       i, total_conditions,
                       cond$content, cond$grade_prior, cond$grade_current,
                       cond$year_prior, 
                       if (!is.null(cond$year_current)) cond$year_current else as.character(as.numeric(cond$year_prior) + cond$year_span))
  cat(start_msg, file = progress_file, append = TRUE)
  # === END PROGRESS TRACKING ===
  
  tryCatch({
    
    # =====================================================================
    # STEP 1: DATA PREPARATION
    # =====================================================================
    current_step_start <- Sys.time()
    
    # Create longitudinal pairs
    # In multi-dataset mode, filter by dataset_id to get only this condition's dataset
    pairs_full <- create_longitudinal_pairs(
      data = get_state_data(),
      grade_prior = cond$grade_prior,
      grade_current = cond$grade_current,
      year_prior = cond$year_prior,
      content_prior = cond$content,
      content_current = cond$content,
      dataset_id = cond$dataset_id  # Filter by dataset (NULL if single dataset)
    )
    
    # Check if sufficient data
    if (is.null(pairs_full) || nrow(pairs_full) < 100) {
      return(list(
        condition_id = i,
        success = FALSE,
        error = "Insufficient data",
        n_pairs = ifelse(is.null(pairs_full), 0, nrow(pairs_full))
      ))
    }
    
    n_pairs <- nrow(pairs_full)
    
    # Create I-spline frameworks
    framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
    framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
    
    record_step("Step 1 - Data prep", sprintf("n_pairs=%s", format(n_pairs, big.mark = ",")))
    
    # Check if we should generate contour plots (use exported _VALUE variable)
    # This ensures PSOCK workers (macOS) have access - they don't inherit .GlobalEnv
    GENERATE_CONTOUR_PLOTS <- GENERATE_CONTOUR_PLOTS_VALUE
    
    # Prepare output directory for plots if needed
    if (GENERATE_CONTOUR_PLOTS) {
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
                                          year_current, cond$grade_prior, 
                                          cond$grade_current, cond$content))
    } else {
      plot_output_dir <- NULL
    }
    
    # =====================================================================
    # STEP 2: COPULA FITTING + GOODNESS-OF-FIT
    # =====================================================================
    current_step_start <- Sys.time()
    
    # Fit all copula families
    # IMPORTANT: Phase 1 uses empirical ranks (not I-spline) for copula family selection
    # This ensures uniform pseudo-observations and preserves tail dependence structure
    copula_fits <- fit_copula_from_pairs(
      scores_prior = pairs_full$SCALE_SCORE_PRIOR,
      scores_current = pairs_full$SCALE_SCORE_CURRENT,
      framework_prior = framework_prior,
      framework_current = framework_current,
      copula_families = copula_families,
      return_best = FALSE,
      use_empirical_ranks = TRUE,  # Phase 1: Use ranks to avoid I-spline distortion
      n_bootstrap_gof = N_BOOTSTRAP_GOF_VALUE,  # Captured from .GlobalEnv and exported to workers
      save_copula_data = GENERATE_CONTOUR_PLOTS,  # New parameter
      output_dir = plot_output_dir  # Directory for saving copula data
    )
    
    record_step("Step 2 - Copula+GoF", 
                sprintf("best=%s, tau=%.3f, gof_n=%s", 
                        copula_fits$best_family, 
                        copula_fits$empirical_tau,
                        if (is.null(N_BOOTSTRAP_GOF_VALUE)) "skip" else N_BOOTSTRAP_GOF_VALUE))
    
    # Extract results for each family
    family_results <- list()
    
    for (family in copula_families) {
      
      if (!is.null(copula_fits$results[[family]])) {
        
        fit <- copula_fits$results[[family]]
        
        # Calculate tail dependence
        if (family %in% c("t", "t_df5", "t_df10", "t_df15")) {
          # All t-copula variants: use pre-calculated values from copula_bootstrap.R
          tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
          tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 0
        } else if (family == "clayton") {
          theta <- fit$parameter[1]
          tail_dep_lower <- 2^(-1/theta)
          tail_dep_upper <- 0
        } else if (family == "gumbel") {
          theta <- fit$parameter[1]
          tail_dep_lower <- 0
          tail_dep_upper <- 2 - 2^(1/theta)
        } else if (family == "comonotonic") {
          # Comonotonic: use pre-calculated values
          tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) fit$tail_dependence_lower else 0
          tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) fit$tail_dependence_upper else 1
        } else {
          tail_dep_lower <- 0
          tail_dep_upper <- 0
        }
        
        # Extract parameters with proper naming
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
        
        family_results[[family]] <- data.table(
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
          year_span = if (!is.null(cond$year_span)) cond$year_span else cond$span,
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
      }
    }
    
    # Generate visualization plots if requested
    if (GENERATE_CONTOUR_PLOTS && !is.null(copula_fits$pseudo_obs)) {
      # Source the visualization functions if not already loaded
      if (!exists("generate_condition_plots")) {
        if (file.exists("functions/copula_contour_plots.R")) {
          source("functions/copula_contour_plots.R")
        }
      }
      
      # Generate plots if function is available
      if (exists("generate_condition_plots")) {
        year_current <- if (!is.null(cond$year_current)) {
          cond$year_current 
        } else {
          as.character(as.numeric(cond$year_prior) + cond$year_span)
        }
        
        # Prepare condition info with metadata enrichment
        dataset_id <- if (!is.null(cond$dataset_id)) cond$dataset_id else "unknown"
        
        # Get dataset config for metadata lookup
        dataset_config <- if (exists("DATASETS", envir = .GlobalEnv) && !is.null(DATASETS[[dataset_id]])) {
          DATASETS[[dataset_id]]
        } else if (exists("current_dataset", envir = .GlobalEnv)) {
          current_dataset
        } else {
          NULL
        }
        
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
          content = cond$content,
          # NEW: Metadata from dataset config for enhanced JSON/summary display
          scale_note = if (!is.null(dataset_config)) dataset_config$notes else NA,
          transition_period = if (!is.null(dataset_config) && exists("get_transition_period", mode = "function")) {
            tryCatch(get_transition_period(dataset_config, cond$year_prior, year_current), error = function(e) NA)
          } else NA,
          pandemic_period = if (!is.null(dataset_config) && exists("get_pandemic_period", mode = "function")) {
            tryCatch(get_pandemic_period(dataset_config, cond$year_prior, year_current), error = function(e) NA)
          } else NA,
          testing_mode_prior = if (!is.null(dataset_config) && exists("get_testing_mode", mode = "function")) {
            tryCatch(get_testing_mode(dataset_config, cond$year_prior), error = function(e) NA)
          } else NA,
          testing_mode_current = if (!is.null(dataset_config) && exists("get_testing_mode", mode = "function")) {
            tryCatch(get_testing_mode(dataset_config, year_current), error = function(e) NA)
          } else NA,
          has_missing_years = if (!is.null(dataset_config) && exists("has_missing_years_in_span", mode = "function")) {
            tryCatch(has_missing_years_in_span(dataset_config, cond$year_prior, year_current), error = function(e) FALSE)
          } else FALSE
        )
        
        # Load empCopula objects if available
        empirical_copulas_file <- file.path(plot_output_dir, "empirical_copulas.rds")
        empirical_copulas <- NULL
        if (file.exists(empirical_copulas_file)) {
          empirical_copulas <- tryCatch({
            readRDS(empirical_copulas_file)
          }, error = function(e) {
            warning(sprintf("Failed to load empirical_copulas.rds: %s", e$message))
            NULL
          })
        }
        
        # =====================================================================
        # STEP 3: BOOTSTRAP UNCERTAINTY QUANTIFICATION (sequential within worker)
        # This generates uncertainty bands on parametric copula CDF plots
        # =====================================================================
        current_step_start <- Sys.time()
        bootstrap_results <- NULL
        bootstrap_info <- "skipped"
        
        if (isTRUE(GENERATE_UNCERTAINTY_PLOTS_VALUE) && !is.null(copula_fits$pseudo_obs)) {
          
          # Determine which families to bootstrap
          if (BOOTSTRAP_ALL_FAMILIES_VALUE) {
            # All 5 parametric families (exclude comonotonic - deterministic)
            bootstrap_families <- setdiff(copula_families, "comonotonic")
          } else {
            # Best family only (faster)
            bootstrap_families <- copula_fits$best_family
          }
          
          bootstrap_info <- sprintf("%d samples × %d families", 
                                    N_BOOTSTRAP_UNCERTAINTY_VALUE, length(bootstrap_families))
          
          # Run bootstrap SEQUENTIALLY within this worker
          # (Parallelization is across conditions, not within bootstrap)
          bootstrap_results <- tryCatch({
            bootstrap_copula_estimation(
              pairs_data = pairs_full,
              n_sample_prior = nrow(pairs_full),
              n_sample_current = nrow(pairs_full),
              n_bootstrap = N_BOOTSTRAP_UNCERTAINTY_VALUE,
              framework_prior = framework_prior,
              framework_current = framework_current,
              sampling_method = "paired",  # Preserves within-student correlation
              copula_families = bootstrap_families,
              with_replacement = TRUE,
              use_empirical_ranks = TRUE,  # Match Phase 1 approach
              use_parallel = FALSE,  # CRITICAL: Sequential within worker (no nested parallelism)
              n_cores = 1
            )
          }, error = function(e) {
            warning(sprintf("Bootstrap failed for condition %d: %s", i, e$message))
            NULL
          })
        }
        
        record_step("Step 3 - Bootstrap", bootstrap_info)
        
        # =====================================================================
        # STEP 4: PLOT GENERATION
        # =====================================================================
        current_step_start <- Sys.time()
        
        tryCatch({
          # Build span-specific column names based on year_span
          span_suffix <- paste0("_SPAN_", cond$year_span, "_YEAR")
          sgp_order_col <- paste0("SGP_ORDER_1", span_suffix)
          sgp_col <- paste0("SGP", span_suffix)
          
          # Include span-specific columns that exist, with fallback to legacy names
          sgp_related_cols <- intersect(
            names(pairs_full), 
            c("SCALE_SCORE_PRIOR", "SCALE_SCORE_CURRENT", 
              sgp_order_col, sgp_col, "SGP_ORDER_1", "SGP")
          )
          
          generate_condition_plots(
            pseudo_obs = copula_fits$pseudo_obs,
            original_scores = pairs_full[, .SD, .SDcols = sgp_related_cols],
            copula_results = copula_fits$results,
            best_family = copula_fits$best_family,
            output_dir = plot_output_dir,
            condition_info = condition_info,
            bootstrap_results = bootstrap_results,  # Bootstrap uncertainty bands
            empirical_copulas = empirical_copulas,
            save_plots = TRUE,
            grid_size = GRID_SIZE_VALUE,  # Configurable resolution (fast=150, full=300)
            export_formats = EXPORT_FORMATS_VALUE,
            export_dpi = EXPORT_DPI_VALUE,
            export_verbose = EXPORT_VERBOSE_VALUE
          )
        }, error = function(e) {
          warning(sprintf("Failed to generate plots for condition %d: %s", i, e$message))
        })
        
        record_step("Step 4 - Plot gen", 
                    sprintf("grid=%d, formats=%s", GRID_SIZE_VALUE, paste(EXPORT_FORMATS_VALUE, collapse=",")))
      }
    }
    
    # =========================================================================
    # STEP 5: SGPc CALCULATION (if enabled)
    # =========================================================================
    current_step_start <- Sys.time()
    sgpc_results <- NULL
    sgpc_info <- "skipped"
    
    if (isTRUE(CALCULATE_SGPC_VALUE) && !is.null(copula_fits$pseudo_obs)) {
      
      # Get pseudo-observations for SGPc calculation
      u_sgpc <- copula_fits$pseudo_obs[, 1]
      v_sgpc <- copula_fits$pseudo_obs[, 2]
      
      # Initialize data.table with student identifiers
      year_current <- if (!is.null(cond$year_current)) {
        cond$year_current 
      } else {
        as.character(as.numeric(cond$year_prior) + cond$year_span)
      }
      
      sgpc_results <- data.table(
        ID = pairs_full$ID,
        YEAR = year_current,
        GRADE = cond$grade_current,
        CONTENT_AREA = cond$content
      )
      
      # Calculate SGPc for each fitted parametric copula family
      for (family in copula_families) {
        if (!is.null(copula_fits$results[[family]])) {
          
          if (family == "comonotonic") {
            # Comonotonic: SGPc = u (prior percentile)
            sgpc_values <- sgpc_engine(u_sgpc, v_sgpc, "comonotonic", scale = "percentile")
          } else {
            # Parametric copula
            fitted_copula_obj <- copula_fits$results[[family]]$copula
            sgpc_values <- sgpc_engine(u_sgpc, v_sgpc, fitted_copula_obj, scale = "percentile")
          }
          
          col_name <- paste0("SGPc_", family)
          sgpc_results[, (col_name) := sgpc_values]
        }
      }
      
      # Calculate SGPc for empirical copulas if available
      if (GENERATE_CONTOUR_PLOTS && !is.null(plot_output_dir)) {
        empirical_copulas_file <- file.path(plot_output_dir, "empirical_copulas.rds")
        if (file.exists(empirical_copulas_file)) {
          emp_copulas <- tryCatch(readRDS(empirical_copulas_file), error = function(e) NULL)
          
          if (!is.null(emp_copulas)) {
            # Bernstein smoothed empirical copula
            if (!is.null(emp_copulas$bernstein)) {
              sgpc_bernstein <- sgpc_engine(u_sgpc, v_sgpc, emp_copulas$bernstein, scale = "percentile")
              sgpc_results[, SGPc_empirical_bernstein := sgpc_bernstein]
            }
            
            # Raw empirical copula (if available)
            if (!is.null(emp_copulas$raw)) {
              sgpc_raw <- sgpc_engine(u_sgpc, v_sgpc, emp_copulas$raw, scale = "percentile")
              sgpc_results[, SGPc_empirical_raw := sgpc_raw]
            }
          }
        }
      }
      
      # Save SGPc results for this condition
      if (!is.null(plot_output_dir)) {
        sgpc_output_dir <- file.path(plot_output_dir, "sgpc_results")
        dir.create(sgpc_output_dir, showWarnings = FALSE, recursive = TRUE)
        
        # Save full SGPc results
        sgpc_output_file <- file.path(sgpc_output_dir, "sgpc_values.rds")
        saveRDS(sgpc_results, file = sgpc_output_file)
        
        # Calculate and save correlations between SGPc variants
        sgpc_cols <- grep("^SGPc_", names(sgpc_results), value = TRUE)
        if (length(sgpc_cols) > 1) {
          cor_matrix <- cor(sgpc_results[, ..sgpc_cols], use = "pairwise.complete.obs")
          saveRDS(cor_matrix, file.path(sgpc_output_dir, "sgpc_correlations.rds"))
        }
      }
      # Update info regardless of output directory
      sgpc_cols <- grep("^SGPc_", names(sgpc_results), value = TRUE)
      sgpc_info <- sprintf("%d variants", length(sgpc_cols))
    }
    
    record_step("Step 5 - SGPc", sgpc_info)
    
    # === WRITE DETAILED CONDITION PROGRESS FILE ===
    if (!is.null(plot_output_dir) && dir.exists(plot_output_dir)) {
      tryCatch({
        write_condition_progress(plot_output_dir, "SUCCESS")
      }, error = function(e) {
        warning(sprintf("Failed to write condition progress: %s", e$message))
      })
    }
    
    # === PROGRESS TRACKING: COMPLETE (central log) ===
    end_time <- Sys.time()
    elapsed <- as.numeric(difftime(end_time, overall_start, units = "mins"))
    complete_msg <- sprintf("[%s] COMPLETE %3d/%d: %-4s G%d->G%d (%.1f min, n=%d, best=%s)\n",
                            format(end_time, "%H:%M:%S"),
                            i, total_conditions,
                            cond$content, cond$grade_prior, cond$grade_current,
                            elapsed, n_pairs, copula_fits$best_family)
    cat(complete_msg, file = progress_file, append = TRUE)
    # === END PROGRESS TRACKING ===
    
    # Build return list (extract needed values before cleanup)
    result_list <- list(
      condition_id = i,
      success = TRUE,
      n_pairs = n_pairs,
      best_family = copula_fits$best_family,
      empirical_tau = copula_fits$empirical_tau,
      results = family_results,
      sgpc_file = if (!is.null(plot_output_dir)) {
        file.path(plot_output_dir, "sgpc_results", "sgpc_values.rds")
      } else NULL
    )
    
    # === MEMORY CLEANUP ===
    # Explicitly remove large temporary objects to prevent memory accumulation
    # Critical for 180+ parallel workers to avoid OOM on 754GB instance
    rm(pairs_full, framework_prior, framework_current)
    if (exists("bootstrap_results")) rm(bootstrap_results)
    if (exists("sgpc_results")) rm(sgpc_results)
    if (exists("copula_fits")) rm(copula_fits)
    gc(verbose = FALSE, reset = TRUE, full = TRUE)
    # === END MEMORY CLEANUP ===
    
    # Return list with success status
    # NOTE: Return file path instead of student-level data to avoid serialization overhead
    return(result_list)
    
  }, error = function(e) {
    
    # === PROGRESS TRACKING: ERROR ===
    end_time <- Sys.time()
    elapsed <- as.numeric(difftime(end_time, overall_start, units = "mins"))
    error_msg <- sprintf("[%s] ERROR    %3d/%d: %-4s G%d->G%d (%.1f min) - %s\n",
                         format(end_time, "%H:%M:%S"),
                         i, total_conditions,
                         cond$content, cond$grade_prior, cond$grade_current,
                         elapsed, substr(as.character(e$message), 1, 50))
    cat(error_msg, file = progress_file, append = TRUE)
    # === END PROGRESS TRACKING ===
    
    return(list(
      condition_id = i,
      success = FALSE,
      error = as.character(e$message)
    ))
  })
}

################################################################################
### RUN PARALLEL ANALYSIS
################################################################################

# Define results directory for this dataset (for progress file)
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset$id)) {
  results_dir <- file.path("STEP_1_Family_Selection/results", current_dataset$id)
} else {
  results_dir <- "STEP_1_Family_Selection/results"
}
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

# Initialize progress file for real-time monitoring
progress_file <- file.path(results_dir, ".progress.txt")
if (file.exists(progress_file)) file.remove(progress_file)

# Write header
cat(paste(rep("=", 70), collapse=""), "\n", file = progress_file, append = FALSE)
cat("COPULA FAMILY SELECTION: Progress Log\n", file = progress_file, append = TRUE)
cat(paste(rep("=", 70), collapse=""), "\n", file = progress_file, append = TRUE)
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", file = progress_file, append = TRUE)
cat("Total conditions:", length(CONDITIONS), "\n", file = progress_file, append = TRUE)
cat("Copula families:", paste(COPULA_FAMILIES, collapse = ", "), "\n", file = progress_file, append = TRUE)
cat("Workers:", n_cores_use, "\n", file = progress_file, append = TRUE)
cat(paste(rep("=", 70), collapse=""), "\n\n", file = progress_file, append = TRUE)

# Check if there are any conditions to process (handles checkpoint/resume case)
SKIP_PROCESSING <- (length(CONDITIONS) == 0)

if (SKIP_PROCESSING) {
  cat("\n")
  cat("====================================================================\n")
  cat("NO CONDITIONS TO PROCESS\n")
  cat("====================================================================\n")
  cat("All conditions have already been completed (checkpoint/resume).\n")
  cat("Skipping parallel processing.\n")
  cat("====================================================================\n\n")
  
  # Initialize empty results
  all_condition_results <- list()
  duration <- 0
  
  # Clean up workers even when skipping
  daemons(0)
  cat("Mirai daemons stopped.\n\n")
  
} else {
  cat("Starting parallel processing of", length(CONDITIONS), "conditions...\n")
  cat("Progress will be shown as conditions complete.\n")
  cat("Monitor progress: tail -f", progress_file, "\n\n")
  
  start_time <- Sys.time()
  
  # Store total conditions for progress messages
  total_conditions <- length(CONDITIONS)
  
  # ==========================================================================
  # PARALLEL EXECUTION: Use mirai_map
  # ==========================================================================
  cat("Using mirai_map for parallel execution...\n")
    
    # -------------------------------------------------------------------------
    # Export process_condition, config values, and DATASETS config to daemons
    # NOTE: Data is NOT loaded here - each task loads only the dataset it needs
    # This is much more efficient than loading the combined 3.74 GB dataset
    # -------------------------------------------------------------------------
    cat("  Exporting config and DATASETS to all daemons...\n")
    cat("    (Data will be loaded PER-TASK - only the specific dataset needed)\n")
    
    init_data <- everywhere({
      # Debug: Log config export phase
      cat("[DAEMON] Starting config initialization at", format(Sys.time(), "%H:%M:%S"), "\n")
      
      # Verify required functions are available
      if (!exists("process_condition")) {
        cat("[DAEMON ERROR] process_condition not found in daemon environment\n")
        stop("process_condition not available")
      }
      cat("[DAEMON] process_condition function available\n")
      
      # Verify get_state_data is available
      if (!exists("get_state_data")) {
        cat("[DAEMON ERROR] get_state_data not found in daemon environment\n")
        stop("get_state_data not available")
      }
      cat("[DAEMON] get_state_data function available\n")
      
      # Verify DATASETS config is available
      if (!exists("DATASETS_CONFIG")) {
        cat("[DAEMON ERROR] DATASETS_CONFIG not found in daemon environment\n")
        stop("DATASETS_CONFIG not available")
      }
      cat("[DAEMON] DATASETS_CONFIG available with", length(DATASETS_CONFIG), "datasets\n")
      
      # Verify config values are available
      config_vars <- c("N_BOOTSTRAP_GOF_VALUE", "CALCULATE_SGPC_VALUE", 
                       "GENERATE_UNCERTAINTY_PLOTS_VALUE", "GENERATE_CONTOUR_PLOTS_VALUE",
                       "N_BOOTSTRAP_UNCERTAINTY_VALUE", "BOOTSTRAP_ALL_FAMILIES_VALUE",
                       "GRID_SIZE_VALUE", "UNCERTAINTY_GRID_SIZE_VALUE",
                       "SKIP_COMONOTONIC_VALUE", "COMPARISON_FAMILIES_VALUE",
                       "EXPORT_FORMATS_VALUE", "EXPORT_DPI_VALUE", "EXPORT_VERBOSE_VALUE")
      for (cv in config_vars) {
        if (!exists(cv)) {
          cat("[DAEMON ERROR] Config variable not found:", cv, "\n")
        }
      }
      cat("[DAEMON] All config variables verified\n")
      cat("[DAEMON] Config initialization complete (data loaded per-task)\n")
      
      TRUE  # Return success indicator
    },
    # Pass DATASETS config (small) instead of combined data (3.74 GB)
    DATASETS_CONFIG = DATASETS_CONFIG,
    USE_SGP_DATA_VALUE = USE_SGP_DATA_VALUE,
    IS_EC2_VALUE = IS_EC2_VALUE,
    # Pass functions and config values (all small objects)
    process_condition = process_condition,
    get_state_data = get_state_data,
    WORKSPACE_OBJECT_NAME = WORKSPACE_OBJECT_NAME,
    N_BOOTSTRAP_GOF_VALUE = N_BOOTSTRAP_GOF_VALUE,
    CALCULATE_SGPC_VALUE = CALCULATE_SGPC_VALUE,
    GENERATE_UNCERTAINTY_PLOTS_VALUE = GENERATE_UNCERTAINTY_PLOTS_VALUE,
    GENERATE_CONTOUR_PLOTS_VALUE = GENERATE_CONTOUR_PLOTS_VALUE,
    N_BOOTSTRAP_UNCERTAINTY_VALUE = N_BOOTSTRAP_UNCERTAINTY_VALUE,
    BOOTSTRAP_ALL_FAMILIES_VALUE = BOOTSTRAP_ALL_FAMILIES_VALUE,
    GRID_SIZE_VALUE = GRID_SIZE_VALUE,
    UNCERTAINTY_GRID_SIZE_VALUE = UNCERTAINTY_GRID_SIZE_VALUE,
    SKIP_COMONOTONIC_VALUE = SKIP_COMONOTONIC_VALUE,
    COMPARISON_FAMILIES_VALUE = COMPARISON_FAMILIES_VALUE,
    EXPORT_FORMATS_VALUE = EXPORT_FORMATS_VALUE,
    EXPORT_DPI_VALUE = EXPORT_DPI_VALUE,
    EXPORT_VERBOSE_VALUE = EXPORT_VERBOSE_VALUE
    )
    
    # Wait for config export to complete
    cat("  Waiting for daemon config initialization...\n")
    init_data_results <- init_data[]
    
    # Check results with detailed error reporting
    n_success <- sum(sapply(init_data_results, function(x) isTRUE(x) || identical(x, TRUE)))
    n_fail <- length(init_data_results) - n_success
    
    if (n_fail > 0) {
      cat("  WARNING: Some daemons failed config initialization (", n_fail, "/", length(init_data_results), ")\n")
      for (i in seq_along(init_data_results)) {
        if (!isTRUE(init_data_results[[i]])) {
          cat("    Daemon", i, "result:", "\n")
          if (is_mirai_error(init_data_results[[i]])) {
            cat("      MIRAI ERROR:", as.character(init_data_results[[i]]), "\n")
          } else {
            cat("      Value:", as.character(init_data_results[[i]]), "\n")
          }
        }
      }
    } else {
      cat("  ✓ Config exported to all", length(init_data_results), "daemons\n")
      cat("  ✓ process_condition function available on all daemons\n")
      cat("  ✓ DATASETS_CONFIG available (data loaded per-task)\n")
    }
    
    cat("  Daemon initialization complete. Starting mirai_map()...\n")
    
    # Use absolute path for progress file (daemons may have different cwd)
    progress_file_abs <- normalizePath(progress_file, mustWork = FALSE)
    
    # Run parallel processing with mirai_map
    # Each task loads ONLY the specific dataset it needs (not the combined 3.74 GB)
    # NOTE: Use .args to pass arguments to the function (mirai_map syntax)
    mirai_results <- mirai_map(
      .x = seq_along(CONDITIONS),
      .f = function(i, CONDITIONS, COPULA_FAMILIES, progress_file, total_conditions) {
        # Get the condition and its dataset_id
        cond <- CONDITIONS[[i]]
        dataset_id <- cond$dataset_id
        
        # Load ONLY the specific dataset needed for this condition
        # This is MUCH more efficient than loading all 4 datasets combined
        if (!is.null(dataset_id) && exists("DATASETS_CONFIG") && dataset_id %in% names(DATASETS_CONFIG)) {
          ds_config <- DATASETS_CONFIG[[dataset_id]]
          
          # Determine the file path based on USE_SGP_DATA and IS_EC2
          if (USE_SGP_DATA_VALUE && !is.null(ds_config$local_path_sgp)) {
            ds_path <- if (IS_EC2_VALUE) ds_config$ec2_path_sgp else ds_config$local_path_sgp
            ds_object_name <- ds_config$rdata_object_name_sgp
          } else {
            ds_path <- if (IS_EC2_VALUE) ds_config$ec2_path else ds_config$local_path
            ds_object_name <- ds_config$rdata_object_name
          }
          
          # Load the dataset if not already loaded or if it's a different dataset
          current_dataset_id <- if (exists(".LOADED_DATASET_ID")) .LOADED_DATASET_ID else NULL
          
          if (is.null(current_dataset_id) || current_dataset_id != dataset_id) {
            cat("[TASK", i, "] Loading dataset:", dataset_id, "from", ds_path, "\n")
            tryCatch({
              load(ds_path)
              ds_data <- get(ds_object_name)
              if (!inherits(ds_data, "data.table")) {
                ds_data <- as.data.table(ds_data)
              }
              # Assign to global for get_state_data() and downstream functions
              assign("STATE_DATA_LONG", ds_data, envir = .GlobalEnv)
              assign(".LOADED_DATASET_ID", dataset_id, envir = .GlobalEnv)
              cat("[TASK", i, "] Loaded", format(nrow(ds_data), big.mark = ","), "rows\n")
            }, error = function(e) {
              cat("[TASK", i, " ERROR] Failed to load dataset:", conditionMessage(e), "\n")
              stop(e)
            })
          }
        }
        
        # === PERIODIC GARBAGE COLLECTION ===
        # Force GC every 5 conditions to prevent memory accumulation
        # Helps stabilize memory usage across 180+ parallel workers
        if (i %% 5 == 0) {
          gc(verbose = FALSE, reset = TRUE)
        }
        # === END PERIODIC GC ===
        
        # process_condition and all dependencies are already in .GlobalEnv
        process_condition(i, cond, COPULA_FAMILIES, progress_file, total_conditions)
      },
      .args = list(
        CONDITIONS = CONDITIONS,
        COPULA_FAMILIES = COPULA_FAMILIES,
        progress_file = progress_file_abs,
        total_conditions = total_conditions
      )
    )
    
    # Collect results (blocking call - waits for all to complete)
    all_condition_results <- mirai_results[]
    
    # =========================================================================
    # Check for mirai errors in results
    # =========================================================================
    error_indices <- which(sapply(all_condition_results, is_mirai_error))
    if (length(error_indices) > 0) {
      cat("\n")
      cat("====================================================================\n")
      cat("WARNING: MIRAI ERRORS DETECTED\n")
      cat("====================================================================\n")
      cat("Errors in conditions:", paste(error_indices, collapse = ", "), "\n\n")
      
      for (idx in error_indices) {
        cat("--- Condition", idx, "---\n")
        err <- all_condition_results[[idx]]
        cat("  Error:", as.character(err), "\n")
      }
      cat("====================================================================\n\n")
    }
  
  end_time <- Sys.time()
  duration <- difftime(end_time, start_time, units = "mins")
  
  # Write final summary to progress file
  cat("\n", paste(rep("=", 70), collapse=""), "\n", file = progress_file, append = TRUE)
  cat("ANALYSIS COMPLETE\n", file = progress_file, append = TRUE)
  cat(paste(rep("=", 70), collapse=""), "\n", file = progress_file, append = TRUE)
  cat("Finished:", format(end_time, "%Y-%m-%d %H:%M:%S"), "\n", file = progress_file, append = TRUE)
  cat("Total time:", round(duration, 2), "minutes\n", file = progress_file, append = TRUE)
  cat("Average per condition:", round(duration / total_conditions, 2), "minutes\n", file = progress_file, append = TRUE)
  
  # Count results
  n_success <- sum(sapply(all_condition_results, function(x) x$success))
  n_failed <- total_conditions - n_success
  cat("Successful:", n_success, "/", total_conditions, "\n", file = progress_file, append = TRUE)
  if (n_failed > 0) {
    cat("Failed:", n_failed, "\n", file = progress_file, append = TRUE)
  }
  cat(paste(rep("=", 70), collapse=""), "\n", file = progress_file, append = TRUE)
  
  cat("\n====================================================================\n")
  cat("PARALLEL PROCESSING COMPLETE\n")
  cat("====================================================================\n")
  cat("Total time:", round(duration, 2), "minutes\n")
  cat("Average time per condition:", round(duration / length(CONDITIONS), 2), "minutes\n\n")
  
  # Stop workers
  daemons(0)
  cat("Mirai daemons stopped.\n\n")

}  # End of else block (SKIP_PROCESSING check)

################################################################################
### AGGREGATE RESULTS
################################################################################

cat("====================================================================\n")
cat("AGGREGATING RESULTS\n")
cat("====================================================================\n\n")

# Handle checkpoint/resume case where no new conditions were processed
if (SKIP_PROCESSING || length(all_condition_results) == 0) {
  cat("No new conditions were processed in this run.\n")
  cat("All results from previous runs are preserved.\n\n")
  
  # Load existing results from CSV files if they exist
  all_results <- list()
  
} else {
  # Count successes and failures
  n_success <- sum(sapply(all_condition_results, function(x) x$success))
  n_failed <- length(all_condition_results) - n_success
  
  cat("Successful conditions:", n_success, "\n")
  cat("Failed conditions:", n_failed, "\n\n")
  
  if (n_failed > 0) {
    cat("Failed conditions:\n")
    for (result in all_condition_results) {
      if (!result$success) {
        cat("  Condition", result$condition_id, ":", result$error, "\n")
      }
    }
    cat("\n")
  }
}  # End of else block (SKIP_PROCESSING check for aggregation)

################################################################################
### GENERATE RUN SUMMARY REPORT
################################################################################

# Generate comprehensive run summary by scanning condition.progress files
generate_run_summary <- function(results_dir, all_results, duration_mins) {
  
  summary_file <- file.path(results_dir, sprintf("RUN_SUMMARY_%s.txt", format(Sys.Date(), "%Y-%m-%d")))
  
  # Find all condition.progress files
  progress_files <- list.files(results_dir, pattern = "condition\\.progress$", 
                               recursive = TRUE, full.names = TRUE)
  
  # Parse timing from progress files
  step_timings <- list()
  bottlenecks <- character()
  
  for (pf in progress_files) {
    lines <- readLines(pf, warn = FALSE)
    
    # Extract step timings
    step_pattern <- "^(Step \\d+ - [^:]+):\\s+([0-9.]+) sec"
    step_lines <- grep(step_pattern, lines, value = TRUE)
    
    for (line in step_lines) {
      match <- regmatches(line, regexec(step_pattern, line))[[1]]
      if (length(match) >= 3) {
        step_name <- match[2]
        elapsed <- as.numeric(match[3])
        if (is.null(step_timings[[step_name]])) {
          step_timings[[step_name]] <- numeric()
        }
        step_timings[[step_name]] <- c(step_timings[[step_name]], elapsed)
      }
    }
    
    # Check for bottleneck
    bottleneck_line <- grep("BOTTLENECK:", lines, value = TRUE)
    if (length(bottleneck_line) > 0) {
      bottlenecks <- c(bottlenecks, bottleneck_line[1])
    }
  }
  
  # Write summary report
  sink(summary_file)
  on.exit(sink(), add = TRUE)
  
  cat(paste(rep("=", 80), collapse = ""), "\n")
  cat("COPULA SENSITIVITY ANALYSIS - RUN SUMMARY REPORT\n")
  cat(paste(rep("=", 80), collapse = ""), "\n")
  cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat("Results directory:", results_dir, "\n")
  cat("\n")
  
  # Overall statistics
  n_total <- length(all_results)
  n_success <- sum(sapply(all_results, function(x) x$success))
  n_failed <- n_total - n_success
  
  cat("OVERALL STATISTICS\n")
  cat(paste(rep("-", 80), collapse = ""), "\n")
  cat(sprintf("Total conditions:     %d\n", n_total))
  cat(sprintf("Successful:           %d (%.1f%%)\n", n_success, 100 * n_success / n_total))
  cat(sprintf("Failed:               %d (%.1f%%)\n", n_failed, 100 * n_failed / n_total))
  cat(sprintf("Total runtime:        %.1f minutes (%.1f hours)\n", duration_mins, duration_mins / 60))
  cat(sprintf("Avg per condition:    %.1f minutes\n", duration_mins / n_total))
  cat("\n")
  
  # Failed conditions detail
  if (n_failed > 0) {
    cat("FAILED CONDITIONS\n")
    cat(paste(rep("-", 80), collapse = ""), "\n")
    for (result in all_results) {
      if (!result$success) {
        cond <- CONDITIONS[[result$condition_id]]
        cat(sprintf("  - Condition %d: %s G%d->G%d %s - %s\n",
                    result$condition_id,
                    if (!is.null(cond$dataset_id)) cond$dataset_id else "unknown",
                    cond$grade_prior, cond$grade_current,
                    cond$content,
                    if (!is.null(result$error)) result$error else "Unknown error"))
      }
    }
    cat("\n")
  }
  
  # Step timing aggregation
  if (length(step_timings) > 0) {
    cat("AVERAGE STEP TIMING (across successful conditions)\n")
    cat(paste(rep("-", 80), collapse = ""), "\n")
    
    total_avg <- 0
    for (step_name in names(step_timings)) {
      timings <- step_timings[[step_name]]
      avg_secs <- mean(timings, na.rm = TRUE)
      med_secs <- median(timings, na.rm = TRUE)
      max_secs <- max(timings, na.rm = TRUE)
      total_avg <- total_avg + avg_secs
    }
    
    for (step_name in names(step_timings)) {
      timings <- step_timings[[step_name]]
      avg_secs <- mean(timings, na.rm = TRUE)
      med_secs <- median(timings, na.rm = TRUE)
      max_secs <- max(timings, na.rm = TRUE)
      pct <- if (total_avg > 0) 100 * avg_secs / total_avg else 0
      
      cat(sprintf("%-25s  avg=%6.1fs  med=%6.1fs  max=%6.1fs  [%5.1f%%]\n",
                  paste0(step_name, ":"), avg_secs, med_secs, max_secs, pct))
    }
    cat(paste(rep("-", 80), collapse = ""), "\n")
    cat(sprintf("%-25s  avg=%6.1fs\n", "TOTAL:", total_avg))
    cat("\n")
  }
  
  # Bottleneck analysis
  if (length(bottlenecks) > 0) {
    cat("BOTTLENECK ANALYSIS\n")
    cat(paste(rep("-", 80), collapse = ""), "\n")
    bottleneck_counts <- table(bottlenecks)
    for (bn in names(sort(bottleneck_counts, decreasing = TRUE))) {
      cat(sprintf("  %d conditions: %s\n", bottleneck_counts[bn], bn))
    }
    cat("\n")
  }
  
  # Best family distribution
  best_families <- sapply(all_results[sapply(all_results, function(x) x$success)], 
                          function(x) x$best_family)
  if (length(best_families) > 0) {
    cat("BEST FAMILY DISTRIBUTION\n")
    cat(paste(rep("-", 80), collapse = ""), "\n")
    family_counts <- table(best_families)
    for (fam in names(sort(family_counts, decreasing = TRUE))) {
      pct <- 100 * family_counts[fam] / length(best_families)
      cat(sprintf("  %-12s: %3d conditions (%5.1f%%)\n", fam, family_counts[fam], pct))
    }
    cat("\n")
  }
  
  cat(paste(rep("=", 80), collapse = ""), "\n")
  cat("END OF REPORT\n")
  cat(paste(rep("=", 80), collapse = ""), "\n")
  
  invisible(summary_file)
}

# Generate summary report
tryCatch({
  summary_path <- generate_run_summary(results_dir, all_condition_results, as.numeric(duration))
  cat("Run summary saved to:", summary_path, "\n\n")
}, error = function(e) {
  warning("Failed to generate run summary: ", e$message)
})

# Extract all results into single data.table
all_results <- list()
result_counter <- 0

for (condition_result in all_condition_results) {
  if (condition_result$success) {
    # Combine all family results for this condition
    for (family_result in condition_result$results) {
      result_counter <- result_counter + 1
      all_results[[result_counter]] <- family_result
    }
  }
}

if (length(all_results) == 0) {
  stop("No results to compile. Check data availability and error messages.")
}

# Combine into single data.table
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
### ADD DATASET METADATA TO RESULTS
################################################################################

# Add dataset metadata columns for multi-dataset combining
if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)) {
  cat("\n")
  cat("====================================================================\n")
  cat("ADDING DATASET METADATA TO RESULTS\n")
  cat("====================================================================\n\n")
  
  results_dt[, dataset_id := current_dataset$id]
  results_dt[, dataset_name := current_dataset$name]
  results_dt[, anonymized_state := current_dataset$anonymized_state]
  
  cat("✓ Added dataset metadata:\n")
  cat("  Dataset ID:", current_dataset$id, "\n")
  cat("  Dataset name:", current_dataset$name, "\n")
  cat("  Anonymized state:", current_dataset$anonymized_state, "\n")
  cat("  Rows:", nrow(results_dt), "\n\n")
} else {
  cat("\n⚠ Warning: current_dataset not found, skipping metadata enrichment\n\n")
}

# Save results - different handling for multi-dataset vs single-dataset mode
if (exists("MULTI_DATASET_MODE") && MULTI_DATASET_MODE) {
  
  ###############################################################################
  # MULTI-DATASET MODE: Save combined results + per-dataset results
  ###############################################################################
  
  cat("====================================================================\n")
  cat("SAVING RESULTS (MULTI-DATASET MODE)\n")
  cat("====================================================================\n\n")
  
  # Save combined results to dataset_all directory
  combined_results_dir <- "STEP_1_Family_Selection/results/dataset_all"
  dir.create(combined_results_dir, showWarnings = FALSE, recursive = TRUE)
  combined_output_file <- paste0(combined_results_dir, "/phase1_copula_family_comparison_all_datasets.csv")
  fwrite(results_dt, combined_output_file)
  cat("✓ Combined results saved to:", combined_output_file, "\n")
  
  # Also save per-dataset results for backwards compatibility
  unique_datasets <- unique(results_dt$dataset_id)
  for (ds_id in unique_datasets) {
    ds_results <- results_dt[dataset_id == ds_id]
    ds_results_dir <- paste0("STEP_1_Family_Selection/results/", ds_id)
    dir.create(ds_results_dir, showWarnings = FALSE, recursive = TRUE)
    ds_output_file <- paste0(ds_results_dir, "/phase1_copula_family_comparison.csv")
    fwrite(ds_results, ds_output_file)
    cat("✓ Dataset", ds_id, "results saved to:", ds_output_file, "\n")
  }
  
  cat("\nTotal conditions tested (all datasets):", uniqueN(paste(results_dt$dataset_id, results_dt$condition_id)), "\n")
  cat("Total copula fits:", nrow(results_dt), "\n\n")
  
  # Per-dataset summary
  cat("Conditions per dataset:\n")
  for (ds_id in unique_datasets) {
    n_cond <- uniqueN(results_dt[dataset_id == ds_id]$condition_id)
    n_rows <- nrow(results_dt[dataset_id == ds_id])
    cat("  ", ds_id, ":", n_cond, "conditions,", n_rows, "rows\n")
  }
  cat("\n")
  
} else {
  
  ###############################################################################
  # SINGLE-DATASET MODE: Original behavior
  ###############################################################################
  
  if (exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset$id)) {
    dataset_results_dir <- paste0("STEP_1_Family_Selection/results/", current_dataset$id)
    dir.create(dataset_results_dir, showWarnings = FALSE, recursive = TRUE)
    output_file <- paste0(dataset_results_dir, "/phase1_copula_family_comparison.csv")
  } else {
    # Fallback to root results directory
    dir.create("STEP_1_Family_Selection/results", showWarnings = FALSE, recursive = TRUE)
    output_file <- "STEP_1_Family_Selection/results/phase1_copula_family_comparison.csv"
  }
  fwrite(results_dt, output_file)
  
  cat("Results saved to:", output_file, "\n")
  cat("Total conditions tested:", uniqueN(results_dt$condition_id), "\n")
  cat("Total copula fits:", nrow(results_dt), "\n\n")
}

# Quick summary
cat("====================================================================\n")
cat("QUICK SUMMARY\n")
cat("====================================================================\n\n")

# Find best family per condition (min AIC within each condition), then count selections
best_families <- results_dt[, .(best_family = family[which.min(aic)]), by = condition_id]
family_selection <- best_families[, .N, by = best_family]
setnames(family_selection, "best_family", "family")
setorder(family_selection, -N)

cat("Family selection frequency (by AIC):\n")
print(family_selection)

cat("\n\nMean AIC by family:\n")
mean_aic <- results_dt[, .(mean_aic = mean(aic), sd_aic = sd(aic)), by = family]
setorder(mean_aic, mean_aic)
print(mean_aic)

# Per-dataset summary if multi-dataset
if (exists("MULTI_DATASET_MODE") && MULTI_DATASET_MODE) {
  cat("\n\nFamily selection by dataset:\n")
  family_by_dataset <- results_dt[, .(best_family = family[which.min(aic)]), 
                                   by = .(dataset_id, condition_id)]
  family_by_dataset_summary <- family_by_dataset[, .N, by = .(dataset_id, best_family)]
  setorder(family_by_dataset_summary, dataset_id, -N)
  print(family_by_dataset_summary)
}

cat("\n\nPhase 1 complete! Proceed to phase1_analysis.R for detailed analysis.\n")
cat("====================================================================\n\n")

###############################################################################
# ADD RESULTS TO ACCUMULATION LIST (FOR MULTI-DATASET COMBINING)
###############################################################################

# In multi-dataset mode, skip accumulation - results already saved in combined format
if (exists("MULTI_DATASET_MODE") && MULTI_DATASET_MODE) {
  
  cat("====================================================================\n")
  cat("RESULTS ACCUMULATION (Multi-Dataset Mode)\n")
  cat("====================================================================\n\n")
  
  # Store combined results in ALL_DATASET_RESULTS for later processing
  if (exists("ALL_DATASET_RESULTS", envir = .GlobalEnv)) {
    # Store results keyed by dataset_id
    unique_datasets <- unique(results_dt$dataset_id)
    for (ds_id in unique_datasets) {
      ds_results <- results_dt[dataset_id == ds_id]
      .GlobalEnv$ALL_DATASET_RESULTS$step1[[ds_id]] <- ds_results
    }
    cat("✓ Results stored for", length(unique_datasets), "datasets\n")
    cat("  Datasets:", paste(unique_datasets, collapse = ", "), "\n")
  }
  
  cat("  Total unique conditions:", uniqueN(paste(results_dt$dataset_id, results_dt$condition_id)), "\n")
  cat("  Total copula families tested:", length(COPULA_FAMILIES), "\n")
  cat("  Total rows:", nrow(results_dt), "\n")
  cat("  Condition type:", if (USE_EXHAUSTIVE_CONDITIONS) "EXHAUSTIVE" else "STRATEGIC SUBSET", "\n\n")
  
} else {
  
  # Single-dataset mode: original accumulation logic
  cat("====================================================================\n")
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
}

cat("Results will be combined with other datasets after all datasets complete.\n")
cat("Combined file: STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv\n\n")
