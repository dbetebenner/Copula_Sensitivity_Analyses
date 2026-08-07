################################################################################
### CHECKPOINT UTILITIES
### Functions for detecting completed conditions and enabling resume capability
###
### Purpose: Enable resilient execution on EC2 spot instances by tracking
###          completed conditions and allowing runs to resume after interruption
###
### Usage:
###   source("functions/checkpoint_utils.R")
###   print_checkpoint_summary("STEP_1_Family_Selection/results")
###
###   # Or get completed conditions for filtering
###   completed <- get_completed_conditions("STEP_1_Family_Selection/results")
################################################################################

#' Get Completed Conditions from Results Directory
#'
#' Scans the results directory structure to identify which conditions have
#' completed successfully. A condition is considered complete when summary_grid.pdf
#' exists in its contour_plots directory.
#'
#' @param results_dir Path to results directory (default: "STEP_1_Family_Selection/results")
#' @return data.table with columns: dataset_id, year_current, grade_prior, grade_current, content_area
#'
get_completed_conditions <- function(
  results_dir = "STEP_1_Family_Selection/results"
) {
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("data.table package is required for checkpoint utilities")
  }

  # Check if results directory exists
  if (!dir.exists(results_dir)) {
    message("Results directory not found: ", results_dir)
    return(data.table::data.table(
      dataset_id = character(),
      year_current = character(),
      grade_prior = integer(),
      grade_current = integer(),
      content_area = character()
    ))
  }

  # Find all dataset directories (dataset_1, dataset_2, etc.)
  dataset_dirs <- list.dirs(results_dir, recursive = FALSE, full.names = TRUE)
  dataset_dirs <- dataset_dirs[grepl("^dataset_", basename(dataset_dirs))]

  if (length(dataset_dirs) == 0) {
    message("No dataset directories found in: ", results_dir)
    return(data.table::data.table(
      dataset_id = character(),
      year_current = character(),
      grade_prior = integer(),
      grade_current = integer(),
      content_area = character()
    ))
  }

  # Collect completed conditions
  completed_list <- list()

  for (ds_dir in dataset_dirs) {
    dataset_id <- basename(ds_dir)
    contour_dir <- file.path(ds_dir, "contour_plots")

    if (!dir.exists(contour_dir)) {
      next
    }

    # Find all condition directories
    condition_dirs <- list.dirs(
      contour_dir,
      recursive = FALSE,
      full.names = TRUE
    )

    for (cond_dir in condition_dirs) {
      # Check for summary_grid.pdf as completion marker
      summary_file <- file.path(cond_dir, "summary_grid.pdf")

      if (file.exists(summary_file)) {
        # Parse directory name: {year_current}_G{grade_prior}_G{grade_current}_{content_area}
        dir_name <- basename(cond_dir)
        pattern <- "^(\\d{4})_G(\\d+)_G(\\d+)_(.+)$"
        matches <- regmatches(dir_name, regexec(pattern, dir_name))[[1]]

        if (length(matches) == 5) {
          completed_list[[length(completed_list) + 1]] <- list(
            dataset_id = dataset_id,
            year_current = matches[2],
            grade_prior = as.integer(matches[3]),
            grade_current = as.integer(matches[4]),
            content_area = matches[5]
          )
        }
      }
    }
  }

  if (length(completed_list) == 0) {
    return(data.table::data.table(
      dataset_id = character(),
      year_current = character(),
      grade_prior = integer(),
      grade_current = integer(),
      content_area = character()
    ))
  }

  # Convert to data.table
  data.table::rbindlist(completed_list)
}


#' Create Unique Condition Key
#'
#' Creates a unique string key for matching conditions
#'
#' @param dataset_id Dataset identifier
#' @param year_current Current year (end year of span)
#' @param grade_prior Prior grade
#' @param grade_current Current grade
#' @param content_area Content area (MATHEMATICS, READING, etc.)
#' @return Character string key
#'
make_condition_key <- function(
  dataset_id,
  year_current,
  grade_prior,
  grade_current,
  content_area
) {
  paste(
    dataset_id,
    year_current,
    grade_prior,
    grade_current,
    content_area,
    sep = "|"
  )
}


#' Get Remaining Conditions (Not Yet Completed)
#'
#' Filters a CONDITIONS list to return only those not yet completed.
#'
#' @param all_conditions List of condition specifications (from CONDITIONS)
#' @param completed_conditions data.table from get_completed_conditions()
#' @return Filtered list of conditions that have not yet completed
#'
get_remaining_conditions <- function(all_conditions, completed_conditions) {
  if (nrow(completed_conditions) == 0) {
    return(all_conditions)
  }

  # Create keys for completed conditions
  completed_keys <- mapply(
    make_condition_key,
    completed_conditions$dataset_id,
    completed_conditions$year_current,
    as.integer(completed_conditions$grade_prior),
    as.integer(completed_conditions$grade_current),
    completed_conditions$content_area,
    USE.NAMES = FALSE
  )

  # Filter out completed conditions
  remaining <- list()
  skipped_count <- 0

  for (cond in all_conditions) {
    # Calculate year_current if not present
    year_current <- if (!is.null(cond$year_current)) {
      as.character(cond$year_current)
    } else {
      as.character(as.numeric(cond$year_prior) + cond$year_span)
    }

    # Get content area (might be 'content' or 'content_area')
    content_area <- if (!is.null(cond$content_area)) {
      cond$content_area
    } else if (!is.null(cond$content)) {
      cond$content
    } else {
      "UNKNOWN"
    }

    # Create key for this condition
    cond_key <- make_condition_key(
      cond$dataset_id,
      year_current,
      cond$grade_prior,
      cond$grade_current,
      content_area
    )

    if (cond_key %in% completed_keys) {
      skipped_count <- skipped_count + 1
    } else {
      remaining[[length(remaining) + 1]] <- cond
    }
  }

  if (skipped_count > 0) {
    message(
      "Checkpoint: Skipping ",
      skipped_count,
      " already-completed conditions"
    )
  }

  remaining
}


#' Print Checkpoint Summary
#'
#' Displays a formatted summary of completion progress by dataset.
#'
#' @param results_dir Path to results directory
#' @param expected_per_dataset Named vector of expected conditions per dataset (optional)
#' @param return_data If TRUE, returns the summary data instead of just printing
#' @return Invisibly returns summary data.table if return_data is TRUE
#'
print_checkpoint_summary <- function(
  results_dir = "STEP_1_Family_Selection/results",
  expected_per_dataset = NULL,
  return_data = FALSE
) {
  # Get completed conditions
  completed <- get_completed_conditions(results_dir)

  cat("====================================================================\n")
  cat("CHECKPOINT SUMMARY\n")
  cat("====================================================================\n")

  if (nrow(completed) == 0) {
    cat("No completed conditions found.\n")
    cat(
      "====================================================================\n"
    )
    if (return_data) {
      return(invisible(data.table::data.table()))
    }
    return(invisible(NULL))
  }

  # Count by dataset
  summary_dt <- completed[, .N, by = dataset_id]
  data.table::setnames(summary_dt, "N", "completed")
  data.table::setorder(summary_dt, dataset_id)

  # Add expected counts if provided
  if (!is.null(expected_per_dataset)) {
    summary_dt[, expected := expected_per_dataset[dataset_id]]
    summary_dt[, progress := sprintf("%.1f%%", 100 * completed / expected)]
  }

  # Print summary table
  cat(sprintf("%-15s %10s", "Dataset", "Completed"))
  if (!is.null(expected_per_dataset)) {
    cat(sprintf(" %10s %10s", "Expected", "Progress"))
  }
  cat("\n")

  for (i in seq_len(nrow(summary_dt))) {
    row <- summary_dt[i]
    cat(sprintf("%-15s %10d", row$dataset_id, row$completed))
    if (!is.null(expected_per_dataset)) {
      cat(sprintf(" %10d %10s", row$expected, row$progress))
    }
    cat("\n")
  }

  cat("--------------------------------------------------------------------\n")
  total_completed <- sum(summary_dt$completed)
  cat(sprintf("%-15s %10d", "TOTAL", total_completed))
  if (!is.null(expected_per_dataset)) {
    total_expected <- sum(summary_dt$expected, na.rm = TRUE)
    total_progress <- sprintf("%.1f%%", 100 * total_completed / total_expected)
    cat(sprintf(" %10d %10s", total_expected, total_progress))
    cat("\n")
    cat(
      "====================================================================\n"
    )
    remaining <- total_expected - total_completed
    cat("Remaining conditions to process:", remaining, "\n")
  } else {
    cat("\n")
  }
  cat(
    "====================================================================\n\n"
  )

  # Also show breakdown by content area
  if (nrow(completed) > 0) {
    cat("Breakdown by content area:\n")
    content_summary <- completed[, .N, by = content_area]
    data.table::setorder(content_summary, -N)
    for (i in seq_len(nrow(content_summary))) {
      cat(sprintf(
        "  %s: %d\n",
        content_summary$content_area[i],
        content_summary$N[i]
      ))
    }
    cat("\n")
  }

  if (return_data) {
    return(invisible(completed))
  }
  invisible(NULL)
}


#' Get Completion Status for a Single Condition
#'
#' Quick check if a specific condition has completed.
#'
#' @param results_dir Results directory path
#' @param dataset_id Dataset identifier
#' @param year_current Current year
#' @param grade_prior Prior grade
#' @param grade_current Current grade
#' @param content_area Content area
#' @return TRUE if completed, FALSE otherwise
#'
is_condition_completed <- function(
  results_dir,
  dataset_id,
  year_current,
  grade_prior,
  grade_current,
  content_area
) {
  condition_dir <- file.path(
    results_dir,
    dataset_id,
    "contour_plots",
    sprintf(
      "%s_G%d_G%d_%s",
      year_current,
      grade_prior,
      grade_current,
      content_area
    )
  )

  summary_file <- file.path(condition_dir, "summary_grid.pdf")
  file.exists(summary_file)
}
