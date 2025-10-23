############################################################################
### MASTER ANALYSIS SCRIPT
### Copula-Based Pseudo-Growth Simulation Framework
###
### Purpose: Orchestrate complete 4-step analysis workflow from copula
###          family selection through transformation validation to sensitivity
###          analyses and final reporting
###
### Usage: 
###   - Interactive: Run step-by-step with review pauses
###   - Batch: Set BATCH_MODE <- TRUE for unattended execution
###   - EC2: Set EC2_MODE <- TRUE for parallel execution
###   - Selective: Set STEPS_TO_RUN to run specific steps only
###
### Estimated Total Runtime: 8-14 hours for all steps
############################################################################

############################################################################
### CONFIGURATION: Multi-Dataset System
############################################################################

# Load dataset configurations
cat("Loading dataset configurations from dataset_configs.R\n")
source("dataset_configs.R")
  
# Select which datasets to analyze
# Set to NULL to run all datasets, or specify vector of dataset IDs
DATASETS_TO_RUN <- NULL  # c("dataset_1", "dataset_2", "dataset_3") or NULL for all
  
if (is.null(DATASETS_TO_RUN)) {
  DATASETS_TO_RUN <- names(DATASETS)
}

cat("Multi-dataset copula sensitivity analysis\n")
cat("Datasets to analyze:", paste(DATASETS_TO_RUN, collapse = ", "), "\n")
cat("Total datasets:", length(DATASETS_TO_RUN), "\n\n")

############################################################################
### CONFIGURATION: Select which steps to run
############################################################################

# STEPS TO RUN: Set to vector of step numbers, or NULL to run all
# Examples:
#   STEPS_TO_RUN <- NULL              # Run all steps (default)
#   STEPS_TO_RUN <- c(1, 2)          # Run only STEP_1 and STEP_2
#   STEPS_TO_RUN <- c(3)             # Run only STEP_3
#   STEPS_TO_RUN <- c(2, 3, 4)       # Run STEP_2 through STEP_4
#   STEPS_TO_RUN <- 1:4              # Run all steps (same as NULL)

STEPS_TO_RUN <- 1  # Default: Run Step 1 only (safest for testing)

# Helper function to check if step should run
should_run_step <- function(step_num) {
  if (is.null(STEPS_TO_RUN)) return(TRUE)
  return(step_num %in% STEPS_TO_RUN)
}

############################################################################
### EC2/LOCAL AUTO-DETECTION
############################################################################

# Default settings (only set if not already defined by calling script)
if (!exists("BATCH_MODE")) BATCH_MODE <- FALSE
if (!exists("EC2_MODE")) EC2_MODE <- FALSE
if (!exists("SKIP_COMPLETED")) SKIP_COMPLETED <- TRUE
if (!exists("USE_PARALLEL")) USE_PARALLEL <- FALSE

# Detect if running on EC2
IS_EC2 <- grepl("ec2", Sys.info()["nodename"], ignore.case = TRUE)

if (IS_EC2) {
  cat("====================================================================\n")
  cat("DETECTED EC2 ENVIRONMENT\n")
  cat("====================================================================\n")
  BATCH_MODE <- TRUE
  EC2_MODE <- TRUE
  SKIP_COMPLETED <- FALSE
  USE_PARALLEL <- TRUE
  cat("  Batch mode: TRUE (no pauses)\n")
  cat("  Cores:", parallel::detectCores(), "\n")
  cat("====================================================================\n\n")
} else {
  # Local machine - check if sufficient resources for parallel processing
  n_cores_available <- parallel::detectCores()
  
  if (n_cores_available >= 8) {
    cat("====================================================================\n")
    cat("DETECTED HIGH-PERFORMANCE LOCAL MACHINE\n")
    cat("====================================================================\n")
    USE_PARALLEL <- TRUE
    cat("  Available cores:", n_cores_available, "\n")
    cat("  Parallel processing: ENABLED\n")
    cat("  STEP 1 speedup: 10-14x (60 min → 5-10 min)\n")
    cat("====================================================================\n\n")
  } else {
    cat("Local mode: Sequential processing (", n_cores_available, " cores)\n", sep = "")
    cat("Note: Parallel processing available with 8+ cores\n\n")
  }
}

############################################################################
### EXECUTION CONFIGURATION
############################################################################

# Computational settings
if (EC2_MODE) {
  N_BOOTSTRAP_PHASE2 <- 200  # More iterations for EC2
  N_CORES <- parallel::detectCores() - 1
  cat("EC2 MODE: Using", N_CORES, "cores for parallel processing\n\n")
} else if (USE_PARALLEL) {
  # Local parallel mode - use most cores but leave some for system
  n_cores_available <- parallel::detectCores()
  N_CORES <- max(1, n_cores_available - 2)  # Leave 2 cores for system
  N_BOOTSTRAP_PHASE2 <- 100
  cat("LOCAL PARALLEL MODE: Using", N_CORES, "of", n_cores_available, "cores\n")
  cat("  Bootstrap iterations:", N_BOOTSTRAP_PHASE2, "\n\n")
} else {
  N_BOOTSTRAP_PHASE2 <- 100
  N_CORES <- 1
}

# Generic workspace object name (data gets assigned to this name regardless of source)
WORKSPACE_OBJECT_NAME <- "STATE_DATA_LONG"

# Timestamp for this run
RUN_TIMESTAMP <- format(Sys.time(), "%Y%m%d_%H%M%S")

# Log file
LOG_FILE <- paste0("master_analysis_log_", RUN_TIMESTAMP, ".txt")
sink(LOG_FILE, split = TRUE)

############################################################################
### PATH MANAGEMENT AND WORKING DIRECTORY SETUP
############################################################################

# Set working directory to project root (where master_analysis.R is located)
PROJECT_ROOT <- dirname(normalizePath(sys.frame(1)$ofile))
if (is.null(PROJECT_ROOT) || PROJECT_ROOT == "") {
  # Fallback: assume we're in the project root
  PROJECT_ROOT <- getwd()
}

# Set working directory to project root
setwd(PROJECT_ROOT)

# Define key directories relative to project root
FUNCTIONS_DIR <- "functions"
DATA_DIR <- "Data"
RESULTS_DIR <- "results"

# Validate that we're in the correct directory
if (!dir.exists(FUNCTIONS_DIR)) {
  stop("ERROR: functions/ directory not found. Are you running from the project root?")
}

cat("Project root:", PROJECT_ROOT, "\n")
cat("Functions directory:", FUNCTIONS_DIR, "\n")
cat("Working directory:", getwd(), "\n\n")

############################################################################
### HELPER FUNCTIONS (DEFINED EARLY)
############################################################################

# Helper function to source files with proper path handling
source_with_path <- function(file_path, description = NULL) {
  if (is.null(description)) {
    description <- basename(file_path)
  }
  
  # Check if file exists
  if (!file.exists(file_path)) {
    stop("ERROR: File not found: ", file_path, "\n",
         "Description: ", description, "\n",
         "Current working directory: ", getwd())
  }
  
  cat("Sourcing:", description, "\n")
  source(file_path, local = FALSE)
}

# Helper function to source all function files
source_all_functions <- function() {
  function_files <- c(
    "longitudinal_pairs.R",
    "ispline_ecdf.R", 
    "copula_bootstrap.R",
    "copula_diagnostics.R",
    "transformation_diagnostics.R"
  )
  
  for (func_file in function_files) {
    func_path <- file.path(FUNCTIONS_DIR, func_file)
    source_with_path(func_path, paste("function:", func_file))
  }
}

# Helper function to get the state data (cleaner than get("STATE_DATA_LONG"))
get_state_data <- function() {
  if (!exists(WORKSPACE_OBJECT_NAME)) {
    stop("ERROR: State data not loaded. Run master_analysis.R first.")
  }
  return(get(WORKSPACE_OBJECT_NAME))
}

# Load all function files
cat("Loading function files...\n")
source_all_functions()
cat("All functions loaded successfully.\n\n")

############################################################################
### INITIALIZATION
############################################################################

# Load required libraries
require(data.table)
require(splines2)
require(copula)
require(grid)

cat("====================================================================\n")
cat("COPULA-BASED PSEUDO-GROWTH SIMULATION FRAMEWORK\n")
cat("Master Analysis Script - 4-Step Sequential Workflow\n")
cat("====================================================================\n")
cat("Version: 3.0 (Restructured)\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("====================================================================\n\n")

cat("Configuration:\n")
cat("  Steps to run:", ifelse(is.null(STEPS_TO_RUN), "ALL (1, 2, 3, 4)", 
                              paste(STEPS_TO_RUN, collapse = ", ")), "\n")
cat("  Batch mode:", BATCH_MODE, "\n")
cat("  EC2 mode:", EC2_MODE, "\n")
cat("  Skip completed:", SKIP_COMPLETED, "\n")
cat("  Bootstrap iterations:", N_BOOTSTRAP_PHASE2, "\n")
cat("  Log file:", LOG_FILE, "\n\n")

############################################################################
### DATA LOADING AND DATASET LOOP
############################################################################

# Determine datasets to loop over
datasets_to_analyze <- DATASETS_TO_RUN

cat("Beginning analysis loop...\n")
cat("Number of datasets:", length(datasets_to_analyze), "\n\n")

# Initialize accumulation lists for multi-dataset results
ALL_DATASET_RESULTS <- list(
  step1 = list(),
  step2 = list(),
  step3 = list(),
  step4 = list()
)
cat("Results accumulation lists initialized\n\n")

# MAIN DATASET LOOP - Each iteration processes one complete dataset through all STEPs
for (dataset_idx in seq_along(datasets_to_analyze)) {
  
  dataset_id <- datasets_to_analyze[dataset_idx]
  
  ###########################################################################
  # DATASET-SPECIFIC CONFIGURATION
  ###########################################################################
  
  # Load configuration for this dataset
  current_dataset <- DATASETS[[dataset_id]]
  
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("DATASET ", dataset_idx, " OF ", length(datasets_to_analyze), ": ", current_dataset$name, "\n", sep="")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("ID: ", current_dataset$id, "\n", sep="")
  cat("Scaling types: ", paste(unique(current_dataset$scaling_by_year$scaling_type), collapse = " / "), "\n", sep="")
  cat("Has transition: ", current_dataset$has_transition, "\n", sep="")
  if (current_dataset$has_transition) {
    cat("Transition year: ", current_dataset$transition_year, "\n", sep="")
  }
  cat("Content areas: ", paste(current_dataset$content_areas, collapse = ", "), "\n", sep="")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
  
  # Set dataset-specific paths and names (use EC2 path if on EC2)
  CURRENT_DATA_PATH <- if (IS_EC2) current_dataset$ec2_path else current_dataset$local_path
  CURRENT_RDATA_OBJECT <- current_dataset$rdata_object_name
  CURRENT_DATASET_NAME <- current_dataset$name
  
  # Results suffix for this dataset (used in all output files)
  RESULTS_SUFFIX <- paste0("_", dataset_id)
  
  ###########################################################################
  # LOAD DATA FOR CURRENT DATASET
  ###########################################################################
  
  cat("Loading data for:", CURRENT_DATASET_NAME, "\n")
  cat("  Path:", CURRENT_DATA_PATH, "\n")
  cat("  Object name:", CURRENT_RDATA_OBJECT, "\n")
  
  # Load the .Rdata file
  load(CURRENT_DATA_PATH)
  
  # Assign to generic workspace name
  if (exists(CURRENT_RDATA_OBJECT)) {
    assign(WORKSPACE_OBJECT_NAME, get(CURRENT_RDATA_OBJECT))
  } else {
    stop("ERROR: Data table object '", CURRENT_RDATA_OBJECT, "' not found in .Rdata file.\n",
         "Expected object name: ", CURRENT_RDATA_OBJECT, "\n",
         "Available objects: ", paste(ls(), collapse = ", "))
  }
  
  # Ensure it's a data.table
  if (!inherits(get(WORKSPACE_OBJECT_NAME), "data.table")) {
    assign(WORKSPACE_OBJECT_NAME, as.data.table(get(WORKSPACE_OBJECT_NAME)))
  }
  
  cat("✓ Loaded", nrow(get(WORKSPACE_OBJECT_NAME)), "rows\n")
  cat("  Workspace object:", WORKSPACE_OBJECT_NAME, "\n")
  cat("  Results suffix:", ifelse(RESULTS_SUFFIX == "", "(none)", RESULTS_SUFFIX), "\n\n")

################################################################################
### HELPER FUNCTIONS (CONTINUED)
################################################################################

pause_for_review <- function(message, phase_name) {
  if (!BATCH_MODE) {
    cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
    cat("REVIEW CHECKPOINT:", phase_name, "\n")
    cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
    cat(message, "\n\n")
    cat("Press Enter to continue or Ctrl+C to stop...\n")
    readline()
  }
}

check_results_exist <- function(file_path, description) {
  if (file.exists(file_path)) {
    cat("✓ Found existing:", description, "\n")
    cat("  Location:", file_path, "\n")
    return(TRUE)
  }
  return(FALSE)
}

time_phase <- function(phase_name, code) {
  cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
  cat("STARTING:", phase_name, "\n")
  cat("Time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
  
  start_time <- Sys.time()
  
  result <- tryCatch({
    code
    list(success = TRUE, error = NULL)
  }, error = function(e) {
    cat("\n*** ERROR in", phase_name, "***\n")
    cat("Message:", e$message, "\n\n")
    list(success = FALSE, error = e$message)
  })
  
  end_time <- Sys.time()
  duration <- difftime(end_time, start_time, units = "mins")
  
  cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
  if (result$success) {
    cat("✓ COMPLETED:", phase_name, "\n")
  } else {
    cat("✗ FAILED:", phase_name, "\n")
    cat("Error:", result$error, "\n")
  }
  cat("Duration:", round(duration, 2), "minutes\n")
  cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
  
  return(result)
}

################################################################################
### STEP 1: COPULA FAMILY SELECTION
################################################################################

if (should_run_step(1)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 1: COPULA FAMILY SELECTION\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Background → TAMP and Copulas; Methodology → Copula Selection\n")
  cat("Objective: Identify which copula family best fits longitudinal education data\n")
  cat("Hypothesis: t-copula will dominate due to heavy tails\n")
  cat("Estimated time: 30-60 minutes\n\n")
  
  ## Step 1.1: Family Selection
  phase1_results_file <- "STEP_1_Family_Selection/results/phase1_copula_family_comparison.csv"
  
  if (SKIP_COMPLETED && check_results_exist(phase1_results_file, "Step 1 family comparison")) {
    cat("Skipping Step 1.1 (already completed)\n\n")
  } else {
    result_1_1 <- time_phase("Step 1.1: Family Selection", {
      # Use parallel version if enabled (EC2 or high-performance local)
      if (USE_PARALLEL) {
        n_cores_use <- min(N_CORES, 15)  # Cap at 15 cores for stability
        cat("Using parallel implementation (", n_cores_use, " cores)\n", sep = "")
        source_with_path("STEP_1_Family_Selection/phase1_family_selection_parallel.R", "Step 1.1: Family Selection (Parallel)")
      } else {
        cat("Using sequential implementation\n")
        source_with_path("STEP_1_Family_Selection/phase1_family_selection.R", "Step 1.1: Family Selection")
      }
    })
    
    if (!result_1_1$success) {
      stop("Step 1.1 failed. Cannot continue.")
    }
  }
  
  # Note: Step 1.2 (Analysis and Decision) will run AFTER all datasets are combined
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 1: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### STEP 2: TRANSFORMATION METHOD VALIDATION
################################################################################

if (should_run_step(2)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 2: TRANSFORMATION METHOD VALIDATION\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Methodology → Marginal Score Distribution Estimation\n")
  cat("Objective: Validate transformation methods for copula pseudo-observations\n")
  cat("THIS IS THE METHODOLOGICAL CENTERPIECE\n")
  if (USE_PARALLEL) {
    cat("Estimated time: 4-6 minutes (parallel)\n\n")
  } else {
    cat("Estimated time: 40-60 minutes (sequential)\n\n")
  }
  
  exp5_validation_results <- "STEP_2_Transformation_Validation/results/exp5_transformation_validation_summary.csv"
  exp5_full_results <- "STEP_2_Transformation_Validation/results/exp5_transformation_validation_full.RData"
  
  if (SKIP_COMPLETED && check_results_exist(exp5_validation_results, "Step 2 validation")) {
    cat("Skipping Step 2 validation (already completed)\n\n")
  } else {
    result_2_1 <- time_phase("Step 2.1: Transformation Validation", {
      # Use parallel version if enabled (EC2 or high-performance local)
      if (USE_PARALLEL) {
        cat("Using parallel implementation (", N_CORES, " cores)\n", sep = "")
        source("STEP_2_Transformation_Validation/exp_5_transformation_validation_parallel.R")
      } else {
        cat("Using sequential implementation\n")
        source("STEP_2_Transformation_Validation/exp_5_transformation_validation.R")
      }
    })
    
    if (!result_2_1$success) {
      cat("\n*** WARNING: Step 2 validation failed ***\n")
      cat("This is critical for methodological justification.\n")
      cat("Recommend stopping to investigate.\n\n")
      
      if (!BATCH_MODE) {
        cat("Continue anyway? (y/n): ")
        response <- readline()
        if (tolower(response) != "y") {
          stop("Stopping due to Step 2 failure.")
        }
      }
    }
  }
  
  # Generate visualizations
  exp5_figures_dir <- "STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation"
  
  if (SKIP_COMPLETED && dir.exists(exp5_figures_dir) && length(list.files(exp5_figures_dir)) > 0) {
    cat("✓ Skipping Step 2 visualizations (already exist)\n\n")
  } else {
    result_2_2 <- time_phase("Step 2.2: Visualization Generation", {
      source("STEP_2_Transformation_Validation/exp_5_visualizations.R")
    })
    
    if (!result_2_2$success) {
      cat("Warning: Step 2 visualizations failed but continuing.\n\n")
    }
  }
  
  ## Review Step 2 Results
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 2 RESULTS SUMMARY\n")
  cat("####################################################################\n\n")
  
  if (file.exists(exp5_validation_results)) {
    exp5_summary <- fread(exp5_validation_results)
    
    cat("Method Classification Summary:\n")
    cat("------------------------------\n")
    class_counts <- table(exp5_summary$classification)
    for (cls in c("EXCELLENT", "ACCEPTABLE", "MARGINAL", "UNACCEPTABLE")) {
      if (cls %in% names(class_counts)) {
        cat(sprintf("  %-15s: %2d methods\n", cls, class_counts[cls]))
      }
    }
    cat("\n")
    
    cat("Recommended Methods for Steps 3-4:\n")
    cat("----------------------------------\n")
    phase2_methods <- exp5_summary[use_in_phase2 == TRUE, label]
    if (length(phase2_methods) > 0) {
      for (m in phase2_methods) {
        cat("  ✓", m, "\n")
      }
    } else {
      cat("  ⚠ WARNING: No methods passed all criteria!\n")
      cat("  Recommend using empirical ranks for all analyses.\n")
    }
    cat("\n")
    
    cat("Key Findings:\n")
    cat("-------------\n")
    empirical_row <- exp5_summary[type == "empirical"][1]
    ispline_4_row <- exp5_summary[method == "ispline_4knots"]
    
    if (nrow(empirical_row) > 0) {
      cat(sprintf("  Empirical ranks: %s (K-S p=%.3f, copula=%s)\n",
                  empirical_row$classification,
                  empirical_row$ks_pvalue,
                  empirical_row$best_copula))
    }
    
    if (nrow(ispline_4_row) > 0) {
      cat(sprintf("  I-spline (4 knots): %s (K-S p=%.3f, copula=%s) ← KNOWN BAD\n",
                  ispline_4_row$classification,
                  ispline_4_row$ks_pvalue,
                  ispline_4_row$best_copula))
    }
    cat("\n")
    
    pause_for_review(
      paste0("Review Step 2 results:\n",
             "  - STEP_2_Transformation_Validation/results/exp5_*.csv\n",
             "  - STEP_2_Transformation_Validation/results/figures/\n\n",
             "Verify:\n",
             "  ✓ At least one method classified as ACCEPTABLE\n",
             "  ✓ I-spline (4 knots) = UNACCEPTABLE/MARGINAL\n\n",
             "If validation passed, we'll proceed to Step 3 (sensitivity analyses)."),
      "Step 2 Complete"
    )
  } else {
    cat("⚠ WARNING: Step 2 results not found!\n")
    cat("Cannot validate transformation methods.\n\n")
  }
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 2: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### STEP 3: SENSITIVITY ANALYSES
################################################################################

if (should_run_step(3)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 3: SENSITIVITY ANALYSES\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Application → Sensitivity Analyses\n")
  cat("Objective: Test copula parameter stability across conditions\n")
  if (USE_PARALLEL) {
    cat("Estimated time: 30-60 minutes (parallel)\n\n")
  } else {
    cat("Estimated time: 3-6 hours (sequential)\n\n")
  }
  
  # Define which experiments to run
  EXPERIMENTS_TO_RUN <- list(
    list(num = 1, name = "exp_1_grade_span", label = "Grade Span Sensitivity"),
    list(num = 2, name = "exp_2_sample_size", label = "Sample Size Effects"),
    list(num = 3, name = "exp_3_content_area", label = "Content Area Comparison"),
    list(num = 4, name = "exp_4_cohort", label = "Cohort Effects")
  )
  
  experiment_results <- list()
  
  for (exp in EXPERIMENTS_TO_RUN) {
    
    # Select parallel vs sequential script
    if (USE_PARALLEL && exp$name != "exp_2_sample_size") {
      # Use parallel version (except Exp 2 which has limited parallelization benefit)
      exp_file <- file.path("STEP_3_Sensitivity_Analyses", 
                           paste0(exp$name, "_parallel.R"))
      
      # Fall back to sequential if parallel doesn't exist
      if (!file.exists(exp_file)) {
        exp_file <- file.path("STEP_3_Sensitivity_Analyses", 
                             paste0(exp$name, ".R"))
        cat("Note: Parallel version not found, using sequential version\n")
      }
    } else {
      exp_file <- file.path("STEP_3_Sensitivity_Analyses", 
                           paste0(exp$name, ".R"))
    }
    
    exp_results_marker <- file.path("STEP_3_Sensitivity_Analyses/results", exp$name)
    
    if (!file.exists(exp_file)) {
      cat("Warning: Experiment file not found:", exp_file, "\n")
      cat("  Skipping", exp$name, "\n\n")
      next
    }
    
    # Check if results exist
    if (SKIP_COMPLETED && dir.exists(exp_results_marker)) {
      cat("✓ Skipping", exp$label, "(results exist)\n\n")
      experiment_results[[exp$name]] <- list(
        success = TRUE,
        skipped = TRUE
      )
      next
    }
    
    # Run experiment
    result <- time_phase(paste("Step 3.", exp$num, ":", exp$label), {
      source(exp_file)
    })
    
    experiment_results[[exp$name]] <- result
    
    if (!result$success) {
      cat("Warning:", exp$name, "failed but continuing with other experiments\n\n")
    }
    
    # Brief pause between experiments (unless batch mode)
    if (!BATCH_MODE && exp$num < length(EXPERIMENTS_TO_RUN)) {
      cat("Proceeding to next experiment in 5 seconds...\n")
      Sys.sleep(5)
    }
  }
  
  ## Step 3 Summary
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 3 EXPERIMENTS SUMMARY\n")
  cat("####################################################################\n\n")
  
  for (exp_name in names(experiment_results)) {
    result <- experiment_results[[exp_name]]
    status <- if (result$success) "✓ COMPLETED" else "✗ FAILED"
    if (!is.null(result$skipped) && result$skipped) status <- "○ SKIPPED"
    cat(sprintf("%-30s %s\n", exp_name, status))
  }
  cat("\n")
  
  pause_for_review(
    paste0("Review Step 3 experiment results:\n",
           "  - STEP_3_Sensitivity_Analyses/results/\n\n",
           "If experiments completed successfully, we'll proceed to Step 4 (deep dive)."),
    "Step 3 Complete"
  )
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 3: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### STEP 4: DEEP DIVE AND COMPREHENSIVE REPORTING
################################################################################

if (should_run_step(4)) {
  
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 4: DEEP DIVE AND COMPREHENSIVE REPORTING\n")
  cat("####################################################################\n\n")
  
  cat("Paper Section: Application → Case Studies; Conclusion\n")
  cat("Objective: Deep analysis of selected copula + comprehensive reporting\n")
  cat("Estimated time: 1-2 hours\n\n")
  
  # Check if t-copula was selected
  phase1_decision_file <- "STEP_1_Family_Selection/results/phase1_decision.RData"
  
  run_t_copula_deep_dive <- FALSE
  if (file.exists(phase1_decision_file)) {
    load(phase1_decision_file)
    run_t_copula_deep_dive <- ("t" %in% phase2_families)
  }
  
  if (run_t_copula_deep_dive) {
    
    cat("t-copula selected in Step 1 - running deep dive analysis\n\n")
    
    t_copula_results <- "STEP_4_Deep_Dive_Reporting/results/phase2_t_copula_deep_dive.RData"
    
    if (SKIP_COMPLETED && check_results_exist(t_copula_results, "t-copula deep dive")) {
      cat("Skipping Step 4.1 (already completed)\n\n")
    } else {
      result_4_1 <- time_phase("Step 4.1: t-Copula Deep Dive", {
        source("STEP_4_Deep_Dive_Reporting/phase2_t_copula_deep_dive.R")
      })
      
      if (!result_4_1$success) {
        cat("Warning: t-copula deep dive failed but continuing.\n\n")
      }
    }
  } else {
    cat("t-copula not selected - skipping deep dive\n\n")
  }
  
  # Comprehensive report
  comprehensive_report_file <- "STEP_4_Deep_Dive_Reporting/results/phase2_comprehensive_report.RData"
  
  if (SKIP_COMPLETED && check_results_exist(comprehensive_report_file, "comprehensive report")) {
    cat("Skipping Step 4.2 (already completed)\n\n")
  } else {
    result_4_2 <- time_phase("Step 4.2: Comprehensive Report Generation", {
      source("STEP_4_Deep_Dive_Reporting/phase2_comprehensive_report.R")
    })
    
    if (!result_4_2$success) {
      cat("Warning: Comprehensive report generation failed.\n\n")
    }
  }
  
  pause_for_review(
    paste0("Review Step 4 results:\n",
           "  - STEP_4_Deep_Dive_Reporting/results/\n\n",
           "All steps complete! Review final outputs for paper integration."),
    "Step 4 Complete"
  )
  
} else {
  cat("\n####################################################################\n")
  cat("### STEP 4: SKIPPED (not in STEPS_TO_RUN)\n")
  cat("####################################################################\n\n")
}

################################################################################
### FINAL SUMMARY
################################################################################

  ###########################################################################
  # END OF DATASET LOOP ITERATION
  ###########################################################################
  
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("COMPLETED ANALYSIS FOR: ", CURRENT_DATASET_NAME, "\n", sep="")
  cat("Dataset ", dataset_idx, " of ", length(datasets_to_analyze), " complete\n", sep="")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
  
} # END DATASET LOOP

###############################################################################
# COMBINE RESULTS FROM ALL DATASETS
###############################################################################

require(data.table)

cat("\n")
cat(paste(rep("=", 80), collapse=""), "\n", sep="")
cat("COMBINING RESULTS FROM ALL DATASETS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

# Combine STEP 1 results
if (should_run_step(1) && length(ALL_DATASET_RESULTS$step1) > 0) {
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("COMBINING STEP 1 RESULTS FROM ALL DATASETS\n")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
  
  cat("Combining results from", length(ALL_DATASET_RESULTS$step1), "datasets...\n")
  
  step1_combined <- rbindlist(ALL_DATASET_RESULTS$step1, fill = TRUE)
  
  # Save to dataset_all subdirectory
  combined_results_dir <- "STEP_1_Family_Selection/results/dataset_all"
  dir.create(combined_results_dir, showWarnings = FALSE, recursive = TRUE)
  output_file <- paste0(combined_results_dir, "/phase1_copula_family_comparison_all_datasets.csv")
  fwrite(step1_combined, output_file)
  
  cat("✓ Combined STEP 1 results saved to:", output_file, "\n\n")
  
  cat("COMBINED RESULTS SUMMARY:\n")
  cat(paste(rep("-", 70), collapse=""), "\n", sep="")
  cat("  Total datasets combined:", length(ALL_DATASET_RESULTS$step1), "\n")
  cat("  Total unique conditions:", uniqueN(step1_combined$condition_id), "\n")
  cat("  Total copula families:", uniqueN(step1_combined$family), "\n")
  cat("  Total rows (conditions × families):", nrow(step1_combined), "\n")
  cat("  Expected rows:", uniqueN(step1_combined$condition_id), "×", 
      uniqueN(step1_combined$family), "=",
      uniqueN(step1_combined$condition_id) * uniqueN(step1_combined$family), "\n")
  if (nrow(step1_combined) != uniqueN(step1_combined$condition_id) * uniqueN(step1_combined$family)) {
    cat("  ⚠ WARNING: Row count mismatch detected!\n")
  }
  cat("  Columns:", ncol(step1_combined), "\n")
  cat(paste(rep("-", 70), collapse=""), "\n\n", sep="")
  
  # Detailed summary by dataset
  cat("BREAKDOWN BY DATASET:\n")
  cat(paste(rep("-", 70), collapse=""), "\n", sep="")
  summary_table <- step1_combined[, .(
    n_conditions = uniqueN(condition_id),
    n_families = length(unique(family)),
    n_rows = .N,
    expected_rows = uniqueN(condition_id) * length(unique(family)),
    has_mismatch = .N != (uniqueN(condition_id) * length(unique(family)))
  ), by = dataset_id]
  print(summary_table)
  cat("\n")
  
  # Winners by dataset
  cat("WINNING FAMILIES BY DATASET:\n")
  cat(paste(rep("-", 70), collapse=""), "\n", sep="")
  winners_table <- step1_combined[, is_winner := (family == best_aic)
  ][is_winner == TRUE, .N, by = .(dataset_id, family)]
  setorder(winners_table, dataset_id, -N)
  print(winners_table)
  cat("\n")
  
  ###########################################################################
  # STEP 1.2: ANALYSIS AND DECISION (on combined data)
  ###########################################################################
  
  cat("\n")
  cat(paste(rep("=", 80), collapse=""), "\n", sep="")
  cat("STEP 1.2: ANALYSIS AND DECISION\n")
  cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")
  
  phase1_decision_file <- "STEP_1_Family_Selection/results/dataset_all/phase1_decision.RData"
  
  if (SKIP_COMPLETED && check_results_exist(phase1_decision_file, "Step 1 decision")) {
    cat("Skipping Step 1.2 (already completed)\n\n")
  } else {
    result_1_2 <- time_phase("Step 1.2: Analysis and Decision", {
      source_with_path("STEP_1_Family_Selection/phase1_analysis.R", "Step 1.2: Analysis and Decision")
    })
    
    if (!result_1_2$success) {
      stop("Step 1.2 failed. Cannot continue.")
    }
  }
  
  ## Review Step 1 Results
  cat("\n")
  cat("####################################################################\n")
  cat("### STEP 1 RESULTS SUMMARY\n")
  cat("####################################################################\n\n")
  
  if (file.exists(phase1_decision_file)) {
    load(phase1_decision_file)
    
    cat("DECISION:", decision, "\n")
    cat("Selected families for Step 2+:", paste(phase2_families, collapse = ", "), "\n\n")
    cat("RATIONALE:\n", rationale, "\n\n")
    
    if (file.exists("STEP_1_Family_Selection/results/dataset_all/phase1_selection_table.csv")) {
      selection_table <- fread("STEP_1_Family_Selection/results/dataset_all/phase1_selection_table.csv")
      cat("SELECTION FREQUENCY:\n")
      print(selection_table)
      cat("\n")
    }
    
    pause_for_review(
      paste0("Review Step 1 combined results:\n",
             "  - STEP_1_Family_Selection/results/dataset_all/phase1_summary.txt\n",
             "  - STEP_1_Family_Selection/results/dataset_all/phase1_*.pdf\n",
             "  - Individual dataset results in dataset_1/, dataset_2/, dataset_3/\n\n",
             "If results look good, we'll proceed to Step 2 (transformation validation)."),
      "Step 1 Complete"
    )
  } else {
    cat("WARNING: Step 1 decision file not found.\n")
    cat("Later steps may not have copula family information.\n\n")
  }
}

# Combine STEP 2 results (if applicable)
if (should_run_step(2) && length(ALL_DATASET_RESULTS$step2) > 0) {
  cat("Combining STEP 2 results from", length(ALL_DATASET_RESULTS$step2), "datasets...\n")
  step2_combined <- rbindlist(ALL_DATASET_RESULTS$step2, fill = TRUE)
  output_file <- "STEP_2_Transformation_Validation/results/exp5_transformation_validation_all_datasets.csv"
  dir.create("STEP_2_Transformation_Validation/results", showWarnings = FALSE, recursive = TRUE)
  fwrite(step2_combined, output_file)
  cat("✓ Combined STEP 2 results saved to:", output_file, "\n\n")
}

# Combine STEP 3 results (if applicable)
if (should_run_step(3) && length(ALL_DATASET_RESULTS$step3) > 0) {
  cat("Combining STEP 3 results from", length(ALL_DATASET_RESULTS$step3), "datasets...\n")
  step3_combined <- rbindlist(ALL_DATASET_RESULTS$step3, fill = TRUE)
  output_file <- "STEP_3_Sensitivity_Analyses/results/sensitivity_analyses_all_datasets.csv"
  dir.create("STEP_3_Sensitivity_Analyses/results", showWarnings = FALSE, recursive = TRUE)
  fwrite(step3_combined, output_file)
  cat("✓ Combined STEP 3 results saved to:", output_file, "\n\n")
}

# Combine STEP 4 results (if applicable)
if (should_run_step(4) && length(ALL_DATASET_RESULTS$step4) > 0) {
  cat("Combining STEP 4 results from", length(ALL_DATASET_RESULTS$step4), "datasets...\n")
  step4_combined <- rbindlist(ALL_DATASET_RESULTS$step4, fill = TRUE)
  output_file <- "STEP_4_Deep_Dive_Reporting/results/deep_dive_all_datasets.csv"
  dir.create("STEP_4_Deep_Dive_Reporting/results", showWarnings = FALSE, recursive = TRUE)
  fwrite(step4_combined, output_file)
  cat("✓ Combined STEP 4 results saved to:", output_file, "\n\n")
}

cat(paste(rep("=", 80), collapse=""), "\n\n", sep="")

###############################################################################
# ALL DATASETS COMPLETE
###############################################################################

cat("\n")
cat("====================================================================\n")
cat("MASTER ANALYSIS COMPLETE\n")
cat("====================================================================\n\n")

cat("Datasets analyzed:", length(datasets_to_analyze), "\n")
cat("  ", paste(datasets_to_analyze, collapse = "\n   "), "\n\n", sep="")

cat("Execution Summary:\n")
cat("-----------------\n")
cat("  Steps run:", ifelse(is.null(STEPS_TO_RUN), "ALL", paste(STEPS_TO_RUN, collapse = ", ")), "\n")
cat("  Batch mode:", BATCH_MODE, "\n")
cat("  Log file:", LOG_FILE, "\n\n")

cat("Output Locations:\n")
cat("-----------------\n")
if (should_run_step(1)) cat("  Step 1: STEP_1_Family_Selection/results/\n")
if (should_run_step(2)) cat("  Step 2: STEP_2_Transformation_Validation/results/\n")
if (should_run_step(3)) cat("  Step 3: STEP_3_Sensitivity_Analyses/results/\n")
if (should_run_step(4)) cat("  Step 4: STEP_4_Deep_Dive_Reporting/results/\n")
cat("\n")

cat("Next Steps:\n")
cat("-----------\n")
cat("1. Review results in each STEP_*/results/ directory\n")
cat("2. Consult METHODOLOGY_OVERVIEW.md for paper integration guidance\n")
cat("3. Use STEP_*/README.md files to understand each analysis\n")
cat("4. Generate final paper figures and tables from results\n\n")

cat("For paper draft, see:\n")
cat("  ~/Research/Papers/Betebenner_Braun/Paper_1/A_Sklar_Theoretic_Extension_of_TAMP.tex\n\n")

# Close log
sink()

cat("====================================================================\n")
cat("Master analysis log saved to:", LOG_FILE, "\n")
cat("====================================================================\n\n")
