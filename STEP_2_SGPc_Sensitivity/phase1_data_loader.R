############################################################################
### Phase 1 Data Loader - Helper Functions
###
### Purpose: Load Phase 1 outputs for STEP 2 SGPc sensitivity analysis
###
### Loads:
###   - Empirical Bernstein copulas
###   - Best-fitting parametric copulas
###   - Canonical parameters
###   - Pseudo-observations
###
### Author: dataimago
### Date: January 2026
############################################################################

require(data.table)
require(copula)

#' Load Phase 1 results for a specific condition
#'
#' @param dataset_id String like "dataset_1"
#' @param condition_id String like "2021_G4_G5_MATHEMATICS"
#' @param phase1_results_dir Base directory for Phase 1 results
#' @return List with empirical_copula, best_fit_copula, copula_params
load_phase1_condition <- function(
  dataset_id,
  condition_id,
  phase1_results_dir = "STEP_1_Family_Selection/results"
) {
  condition_dir <- file.path(
    phase1_results_dir,
    dataset_id,
    "contour_plots",
    condition_id
  )

  result <- list(
    empirical_copula = NULL,
    best_fit_copula = NULL,
    copula_params = NULL,
    original_scores = NULL,
    pseudo_observations = NULL
  )

  # Load empirical copulas
  emp_file <- file.path(condition_dir, "empirical_copulas.rds")
  if (file.exists(emp_file)) {
    emp_copulas <- readRDS(emp_file)
    # Use Bernstein-smoothed copula (empCopula with beta smoothing)
    if ("beta" %in% names(emp_copulas)) {
      result$empirical_copula <- emp_copulas$beta
    } else if ("bernstein" %in% names(emp_copulas)) {
      result$empirical_copula <- emp_copulas$bernstein
    } else {
      # Take first available
      result$empirical_copula <- emp_copulas[[1]]
    }
  }

  # Load parametric copula results
  copula_file <- file.path(condition_dir, "copula_results.rds")
  if (file.exists(copula_file)) {
    copula_results <- readRDS(copula_file)

    # Store all parameters
    result$copula_params <- copula_results

    # Find best-fitting copula (lowest AIC)
    if ("t" %in% names(copula_results)) {
      best_family <- "t"
      best_result <- copula_results$t
    } else {
      # Fallback: find family with lowest AIC
      aics <- sapply(copula_results, function(x) {
        if (is.list(x) && "aic" %in% names(x)) x$aic else Inf
      })
      best_family <- names(which.min(aics))
      best_result <- copula_results[[best_family]]
    }

    # Extract the fitted copula object directly (it's already stored!)
    if (!is.null(best_result$copula)) {
      result$best_fit_copula <- best_result$copula
    } else {
      # Fallback: construct from parameters if copula object not stored
      if (
        best_family == "t" &&
          !is.null(best_result$parameter) &&
          !is.null(best_result$df)
      ) {
        result$best_fit_copula <- tCopula(
          param = best_result$parameter,
          df = best_result$df,
          dim = 2
        )
      } else if (best_family == "gaussian" && !is.null(best_result$parameter)) {
        result$best_fit_copula <- normalCopula(
          param = best_result$parameter,
          dim = 2
        )
      }
      # Add other families as needed
    }
  }

  # Load original scores (optional, for validation)
  scores_file <- file.path(condition_dir, "original_scores.rds")
  if (file.exists(scores_file)) {
    result$original_scores <- readRDS(scores_file)
  }

  # Load pseudo-observations (CRITICAL: these are the same u,v used in Phase 1 copula fitting)
  pobs_file <- file.path(condition_dir, "pseudo_observations.rds")
  if (file.exists(pobs_file)) {
    result$pseudo_observations <- readRDS(pobs_file)
  }

  return(result)
}

#' Load canonical parameters from Phase 1 manifest
#'
#' @param manifest_path Path to analysis_manifest.json
#' @param canonical_params_path Path to canonical_copula_parameters.csv
#' @return List with manifest and canonical_params data.table
load_canonical_parameters <- function(
  manifest_path = "STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json",
  canonical_params_path = "STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv"
) {
  if (!file.exists(manifest_path)) {
    stop("Manifest not found: ", manifest_path, "\nRun Phase 1 analysis first.")
  }

  if (!file.exists(canonical_params_path)) {
    stop("Canonical parameters not found: ", canonical_params_path)
  }

  manifest <- jsonlite::fromJSON(manifest_path)
  canonical_params <- fread(canonical_params_path)

  list(
    manifest = manifest,
    canonical_params = canonical_params
  )
}

#' Get list of all conditions for a dataset from Phase 1
#'
#' @param dataset_id String like "dataset_1"
#' @param phase1_results_dir Base directory for Phase 1 results
#' @return Character vector of condition IDs (e.g., "2021_G4_G5_MATHEMATICS")
get_phase1_conditions <- function(
  dataset_id,
  phase1_results_dir = "STEP_1_Family_Selection/results"
) {
  comparison_file <- file.path(
    phase1_results_dir,
    dataset_id,
    "phase1_copula_family_comparison.csv"
  )

  if (!file.exists(comparison_file)) {
    warning("Phase 1 comparison file not found for ", dataset_id)
    return(character(0))
  }

  comparison <- fread(comparison_file)

  # Construct condition strings from metadata columns
  # CRITICAL: Use year_current (not year_prior) because Phase 1 saves directories with current year
  # Format: {year_current}_G{grade_prior}_G{grade_current}_{content_area}
  # Example: 2017_G3_G4_MATHEMATICS (year_current=2017, grades 3→4, MATHEMATICS)
  unique_conds <- unique(comparison[, .(
    year_current,
    grade_prior,
    grade_current,
    content_area
  )])

  condition_strings <- paste0(
    unique_conds$year_current,
    "_",
    "G",
    unique_conds$grade_prior,
    "_",
    "G",
    unique_conds$grade_current,
    "_",
    unique_conds$content_area
  )

  return(condition_strings)
}

#' Load traditional SGP values (placeholder - needs actual implementation)
#'
#' @param dataset_data data.table with STATE_DATA_LONG
#' @param condition_id String like "2021_G4_G5_MATHEMATICS"
#' @return Vector of SGP values or NULL
load_traditional_sgp <- function(dataset_data, condition_id) {
  # TODO: Implement actual SGP loading or computation
  # Options:
  #   1. Load from existing SGP output files if available
  #   2. Call SGP package to compute
  #   3. Return NULL if not available

  # For now, return NULL
  return(NULL)
}

#' Batch load Phase 1 results for multiple conditions
#'
#' @param dataset_id String like "dataset_1"
#' @param condition_ids Character vector of condition IDs
#' @param phase1_results_dir Base directory
#' @param verbose Logical, print progress
#' @return Named list of Phase 1 results by condition_id
batch_load_phase1 <- function(
  dataset_id,
  condition_ids,
  phase1_results_dir = "STEP_1_Family_Selection/results",
  verbose = TRUE
) {
  results <- list()
  n_total <- length(condition_ids)

  for (i in seq_along(condition_ids)) {
    cond_id <- condition_ids[i]

    if (verbose && i %% 10 == 0) {
      cat(sprintf(
        "Loading Phase 1 results: %d/%d (%.1f%%)\n",
        i,
        n_total,
        100 * i / n_total
      ))
    }

    results[[cond_id]] <- tryCatch(
      {
        load_phase1_condition(dataset_id, cond_id, phase1_results_dir)
      },
      error = function(e) {
        if (verbose) {
          cat("  Warning: Could not load", cond_id, ":", e$message, "\n")
        }
        list(
          empirical_copula = NULL,
          best_fit_copula = NULL,
          copula_params = NULL
        )
      }
    )
  }

  if (verbose) {
    n_success <- sum(sapply(results, function(x) !is.null(x$empirical_copula)))
    cat(sprintf(
      "Loaded %d/%d conditions successfully (%.1f%%)\n",
      n_success,
      n_total,
      100 * n_success / n_total
    ))
  }

  return(results)
}

#' Extract condition metadata from condition_id
#'
#' @param condition_id String like "2017_G3_G4_MATHEMATICS"
#'   (year_current, not year_prior, to match Phase 1 directory naming)
#' @return List with year_prior, year_current, grade_prior, grade_current, content_area, year_span
parse_condition_id <- function(condition_id) {
  parts <- strsplit(condition_id, "_")[[1]]

  # CRITICAL: First part is year_current (to match Phase 1 directory structure)
  year_current <- as.integer(parts[1])
  grade_prior <- as.integer(gsub("G", "", parts[2]))
  grade_current <- as.integer(gsub("G", "", parts[3]))
  content_area <- paste(parts[4:length(parts)], collapse = "_")
  year_span <- grade_current - grade_prior

  # Calculate year_prior from year_current and year_span
  year_prior <- year_current - year_span

  list(
    year_prior = year_prior,
    year_current = year_current,
    grade_prior = grade_prior,
    grade_current = grade_current,
    content_area = content_area,
    year_span = year_span
  )
}

#' Create averaged canonical copula from manifest parameters
#'
#' Returns a copula object with stability metadata attached as attributes.
#' The canonical copula is the recommended parametric copula for a given
#' year_span x content_area stratum, based on STEP_1 meta-analysis across
#' 966 conditions. It is the copula used operationally for datasets like
#' TIMSS/NAEP where no empirical copula is available.
#'
#' @param year_span_val Integer 1-4
#' @param content_area_val String (e.g., "MATHEMATICS", "ELA")
#' @param canonical_params data.table from Phase 1 (canonical_copula_parameters.csv)
#' @return Copula object (usually t-copula) with attributes:
#'   - "stratum_id": the year_span x content_area stratum identifier
#'   - "overall_stability": "HIGH", "MEDIUM", or "LOW"
#'   - "n_conditions": number of conditions in this stratum
#'   - "tau_median": median Kendall's tau for this stratum
#'   - "rho_cv": coefficient of variation for rho (lower = more stable)
#'   - "df_cv": coefficient of variation for df
create_canonical_copula <- function(
  year_span_val,
  content_area_val,
  canonical_params
) {
  # Convert to uppercase for matching
  content_upper <- toupper(content_area_val)

  # Lookup parameters using base R subsetting to avoid data.table scope issues
  params <- canonical_params[
    canonical_params$year_span == year_span_val &
      toupper(canonical_params$content_area) == content_upper
  ]

  fallback_used <- FALSE
  if (nrow(params) == 0) {
    # Fallback to year_span only
    params <- canonical_params[canonical_params$year_span == year_span_val]
    fallback_used <- TRUE
    if (nrow(params) == 0) {
      stop("No canonical parameters found for year_span=", year_span_val)
    }
    # Aggregate across content areas if multiple
    if (nrow(params) > 1) {
      params <- params[1] # Take first for now
      warning(
        "Multiple params found for year_span=",
        year_span_val,
        ", using first"
      )
    }
  }

  # Extract parameters as scalar values
  family <- as.character(params$best_family[1])
  rho_val <- as.numeric(params$rho_median[1])
  df_val <- as.numeric(params$df_median[1])

  # Extract stability metadata (available in canonical_copula_parameters.csv)
  stability <- tryCatch(
    as.character(params$overall_stability[1]),
    error = function(e) NA_character_
  )
  n_cond <- tryCatch(as.integer(params$n_conditions[1]), error = function(e) {
    NA_integer_
  })
  tau_med <- tryCatch(as.numeric(params$tau_median[1]), error = function(e) {
    NA_real_
  })
  rho_cv_val <- tryCatch(as.numeric(params$rho_cv[1]), error = function(e) {
    NA_real_
  })
  df_cv_val <- tryCatch(as.numeric(params$df_cv[1]), error = function(e) {
    NA_real_
  })
  stratum <- tryCatch(as.character(params$stratum_id[1]), error = function(e) {
    paste0("year_", year_span_val, "_", tolower(content_upper))
  })

  # Create copula object based on recommended family
  # NOTE: For bivariate copulas, no dispstr parameter needed (it's only for dim > 2)
  if (family == "t") {
    copula_obj <- tCopula(
      param = rho_val,
      df = df_val,
      dim = 2
    )
  } else if (family == "gaussian") {
    copula_obj <- normalCopula(param = rho_val, dim = 2)
  } else {
    # Default to t-copula if other families (e.g., Frank recommended but
    # canonical CSV currently always reports t; see canonical_validation.R)
    copula_obj <- tCopula(
      param = rho_val,
      df = 30, # Reasonable default for non-t families
      dim = 2
    )
  }

  # Attach stability metadata as attributes for downstream use
  attr(copula_obj, "stratum_id") <- stratum
  attr(copula_obj, "overall_stability") <- stability
  attr(copula_obj, "n_conditions") <- n_cond
  attr(copula_obj, "tau_median") <- tau_med
  attr(copula_obj, "rho_cv") <- rho_cv_val
  attr(copula_obj, "df_cv") <- df_cv_val
  attr(copula_obj, "fallback_used") <- fallback_used

  return(copula_obj)
}

cat("Phase 1 data loader functions loaded successfully.\n")
cat("Available functions:\n")
cat("  - load_phase1_condition(dataset_id, condition_id)\n")
cat("  - load_canonical_parameters()\n")
cat("  - get_phase1_conditions(dataset_id)\n")
cat("  - load_traditional_sgp(dataset_data, condition_id)\n")
cat("  - batch_load_phase1(dataset_id, condition_ids)\n")
cat("  - parse_condition_id(condition_id)\n")
cat("  - create_canonical_copula(year_span, content_area, canonical_params)\n")
