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
cat(
  "Note: T-copula variants (free, df=5, df=10, df=15) test tail dependence.\n"
)
cat("====================================================================\n\n")

################################################################################
### CONFIGURATION
################################################################################

# All copula families to test
# Including comonotonic (Fréchet-Hoeffding upper bound) to show how badly
# the implicit TAMP assumption (perfect positive dependence) misfits the data
# Note: We focus on t-copula with data-driven df estimation (not fixed df)
# as preliminary results showed free df consistently dominates fixed df variants
COPULA_FAMILIES <- c(
  "gaussian",
  "t",
  "clayton",
  "gumbel",
  "frank",
  "comonotonic"
)

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
  cat(
    "  (All valid year/grade/content combinations for transition analysis)\n\n"
  )

  # Generate all valid conditions for this dataset
  CONDITIONS <- generate_exhaustive_conditions(
    current_dataset,
    max_year_span = 4
  )
} else if (
  exists("current_dataset", envir = .GlobalEnv) &&
    !is.null(current_dataset) &&
    current_dataset$id == "dataset_4"
) {
  cat("Using PANDEMIC-FOCUSED conditions for", current_dataset$name, "\n")
  cat("  Primary focus: 2019-2021 pandemic pairs vs. pre-pandemic baselines\n")
  cat("  Secondary: Strategic subset of pre/post-pandemic periods\n\n")

  # Dataset 4: Hawaii with COVID-19 gap (2020 missing)
  # Years available: 2016-2019, 2021-2025
  # Grades: 3-8, 11
  # Content: MATHEMATICS, READING

  CONDITIONS <- list(
    # ========================================================================
    # PANDEMIC PAIRS (2019-2021): Core comparison conditions
    # Testing impact of COVID disruption on dependency structure
    # ========================================================================

    # 2-year pandemic spans (G3→G5, G4→G6, G5→G7, G6→G8)
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2019",
      content = "MATHEMATICS",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2019",
      content = "READING",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2019",
      content = "MATHEMATICS",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2019",
      content = "READING",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2019",
      content = "MATHEMATICS",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2019",
      content = "READING",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 6,
      grade_current = 8,
      year_prior = "2019",
      content = "MATHEMATICS",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 6,
      grade_current = 8,
      year_prior = "2019",
      content = "READING",
      year_span = 2,
      is_pandemic_pair = TRUE
    ),

    # 3-year pandemic span (G8→G11): 2018-2021
    list(
      grade_prior = 8,
      grade_current = 11,
      year_prior = "2018",
      content = "MATHEMATICS",
      year_span = 3,
      is_pandemic_pair = TRUE
    ),
    list(
      grade_prior = 8,
      grade_current = 11,
      year_prior = "2018",
      content = "READING",
      year_span = 3,
      is_pandemic_pair = TRUE
    ),

    # ========================================================================
    # PRE-PANDEMIC BASELINES (2017-2019 / 2016-2019): Direct comparison pairs
    # Same grade spans, same time length, pre-COVID
    # ========================================================================

    # 2-year pre-pandemic baselines (2017-2019)
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2017",
      content = "MATHEMATICS",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G3_G5_MATHEMATICS"
    ),
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2017",
      content = "READING",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G3_G5_READING"
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2017",
      content = "MATHEMATICS",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G4_G6_MATHEMATICS"
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2017",
      content = "READING",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G4_G6_READING"
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2017",
      content = "MATHEMATICS",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G5_G7_MATHEMATICS"
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2017",
      content = "READING",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G5_G7_READING"
    ),
    list(
      grade_prior = 6,
      grade_current = 8,
      year_prior = "2017",
      content = "MATHEMATICS",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G6_G8_MATHEMATICS"
    ),
    list(
      grade_prior = 6,
      grade_current = 8,
      year_prior = "2017",
      content = "READING",
      year_span = 2,
      is_baseline_pair = TRUE,
      baseline_for = "2019_G6_G8_READING"
    ),

    # 3-year pre-pandemic baseline (2016-2019)
    list(
      grade_prior = 8,
      grade_current = 11,
      year_prior = "2016",
      content = "MATHEMATICS",
      year_span = 3,
      is_baseline_pair = TRUE,
      baseline_for = "2018_G8_G11_MATHEMATICS"
    ),
    list(
      grade_prior = 8,
      grade_current = 11,
      year_prior = "2016",
      content = "READING",
      year_span = 3,
      is_baseline_pair = TRUE,
      baseline_for = "2018_G8_G11_READING"
    ),

    # ========================================================================
    # STRATEGIC SUBSET: 1-YEAR SPANS
    # Pre-pandemic and post-pandemic samples for broader coverage
    # ========================================================================

    # Pre-pandemic 1-year
    list(
      grade_prior = 3,
      grade_current = 4,
      year_prior = "2016",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 4,
      grade_current = 5,
      year_prior = "2017",
      content = "READING",
      year_span = 1
    ),
    list(
      grade_prior = 5,
      grade_current = 6,
      year_prior = "2018",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 6,
      grade_current = 7,
      year_prior = "2018",
      content = "READING",
      year_span = 1
    ),
    list(
      grade_prior = 7,
      grade_current = 8,
      year_prior = "2017",
      content = "MATHEMATICS",
      year_span = 1
    ),

    # Post-pandemic 1-year
    list(
      grade_prior = 3,
      grade_current = 4,
      year_prior = "2021",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 4,
      grade_current = 5,
      year_prior = "2022",
      content = "READING",
      year_span = 1
    ),
    list(
      grade_prior = 5,
      grade_current = 6,
      year_prior = "2023",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 6,
      grade_current = 7,
      year_prior = "2024",
      content = "READING",
      year_span = 1
    ),
    list(
      grade_prior = 7,
      grade_current = 8,
      year_prior = "2023",
      content = "MATHEMATICS",
      year_span = 1
    ),

    # ========================================================================
    # STRATEGIC SUBSET: 2-YEAR SPANS (beyond pandemic pairs)
    # ========================================================================

    # Pre-pandemic 2-year (different cohorts)
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2016",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2016",
      content = "READING",
      year_span = 2
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2016",
      content = "MATHEMATICS",
      year_span = 2
    ),

    # Post-pandemic 2-year (recovery period)
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2022",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2022",
      content = "READING",
      year_span = 2
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2023",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 6,
      grade_current = 8,
      year_prior = "2023",
      content = "READING",
      year_span = 2
    ),

    # ========================================================================
    # STRATEGIC SUBSET: 3-YEAR SPANS (beyond pandemic pairs)
    # ========================================================================

    # Pre-pandemic 3-year
    list(
      grade_prior = 3,
      grade_current = 6,
      year_prior = "2016",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 4,
      grade_current = 7,
      year_prior = "2016",
      content = "READING",
      year_span = 3
    ),
    list(
      grade_prior = 5,
      grade_current = 8,
      year_prior = "2017",
      content = "MATHEMATICS",
      year_span = 3
    ),

    # Post-pandemic 3-year
    list(
      grade_prior = 3,
      grade_current = 6,
      year_prior = "2022",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 5,
      grade_current = 8,
      year_prior = "2022",
      content = "READING",
      year_span = 3
    ),

    # ========================================================================
    # STRATEGIC SUBSET: 4-YEAR SPANS
    # Note: 2016-2020 not possible (2020 missing)
    # ========================================================================

    # Post-pandemic 4-year (long-term recovery)
    list(
      grade_prior = 3,
      grade_current = 7,
      year_prior = "2021",
      content = "MATHEMATICS",
      year_span = 4
    ),
    list(
      grade_prior = 4,
      grade_current = 8,
      year_prior = "2021",
      content = "READING",
      year_span = 4
    ),
    list(
      grade_prior = 3,
      grade_current = 7,
      year_prior = "2021",
      content = "READING",
      year_span = 4
    )
  )
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
    list(
      grade_prior = 3,
      grade_current = 4,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 3,
      grade_current = 4,
      year_prior = "2010",
      content = "READING",
      year_span = 1
    ),

    # Grade 4-6 prior (existing)
    list(
      grade_prior = 4,
      grade_current = 5,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 4,
      grade_current = 5,
      year_prior = "2011",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 5,
      grade_current = 6,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 6,
      grade_current = 7,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 4,
      grade_current = 5,
      year_prior = "2010",
      content = "READING",
      year_span = 1
    ),
    list(
      grade_prior = 5,
      grade_current = 6,
      year_prior = "2010",
      content = "READING",
      year_span = 1
    ),
    list(
      grade_prior = 4,
      grade_current = 5,
      year_prior = "2010",
      content = "WRITING",
      year_span = 1
    ),

    # Grade 7 prior (middle school transition)
    list(
      grade_prior = 7,
      grade_current = 8,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 1
    ),
    list(
      grade_prior = 7,
      grade_current = 8,
      year_prior = "2010",
      content = "READING",
      year_span = 1
    ),

    # === 2-YEAR SPANS ===
    # Grade 3 prior
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 3,
      grade_current = 5,
      year_prior = "2010",
      content = "READING",
      year_span = 2
    ),

    # Grade 4-6 prior (existing)
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2011",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 6,
      grade_current = 8,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2010",
      content = "READING",
      year_span = 2
    ),
    list(
      grade_prior = 5,
      grade_current = 7,
      year_prior = "2010",
      content = "READING",
      year_span = 2
    ),
    list(
      grade_prior = 4,
      grade_current = 6,
      year_prior = "2010",
      content = "WRITING",
      year_span = 2
    ),

    # Grade 7 prior
    list(
      grade_prior = 7,
      grade_current = 9,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 2
    ),
    list(
      grade_prior = 7,
      grade_current = 9,
      year_prior = "2010",
      content = "READING",
      year_span = 2
    ),

    # === 3-YEAR SPANS ===
    # Grade 3 prior
    list(
      grade_prior = 3,
      grade_current = 6,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 3,
      grade_current = 6,
      year_prior = "2010",
      content = "READING",
      year_span = 3
    ),

    # Grade 4-6 prior (existing)
    list(
      grade_prior = 4,
      grade_current = 7,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 4,
      grade_current = 7,
      year_prior = "2009",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 5,
      grade_current = 8,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 6,
      grade_current = 9,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 4,
      grade_current = 7,
      year_prior = "2010",
      content = "READING",
      year_span = 3
    ),
    list(
      grade_prior = 5,
      grade_current = 8,
      year_prior = "2010",
      content = "READING",
      year_span = 3
    ),
    list(
      grade_prior = 4,
      grade_current = 7,
      year_prior = "2010",
      content = "WRITING",
      year_span = 3
    ),

    # Grade 7 prior
    list(
      grade_prior = 7,
      grade_current = 10,
      year_prior = "2009",
      content = "MATHEMATICS",
      year_span = 3
    ),
    list(
      grade_prior = 7,
      grade_current = 10,
      year_prior = "2009",
      content = "READING",
      year_span = 3
    ),

    # === 4-YEAR SPANS ===
    # Grade 3 prior
    list(
      grade_prior = 3,
      grade_current = 7,
      year_prior = "2009",
      content = "MATHEMATICS",
      year_span = 4
    ),
    list(
      grade_prior = 3,
      grade_current = 7,
      year_prior = "2009",
      content = "READING",
      year_span = 4
    ),

    # Grade 4-6 prior (existing + expanded)
    list(
      grade_prior = 4,
      grade_current = 8,
      year_prior = "2009",
      content = "MATHEMATICS",
      year_span = 4
    ),
    list(
      grade_prior = 4,
      grade_current = 8,
      year_prior = "2010",
      content = "MATHEMATICS",
      year_span = 4
    ),
    list(
      grade_prior = 5,
      grade_current = 9,
      year_prior = "2009",
      content = "MATHEMATICS",
      year_span = 4
    ),
    list(
      grade_prior = 6,
      grade_current = 10,
      year_prior = "2009",
      content = "MATHEMATICS",
      year_span = 4
    ),
    list(
      grade_prior = 4,
      grade_current = 8,
      year_prior = "2009",
      content = "READING",
      year_span = 4
    ),
    list(
      grade_prior = 5,
      grade_current = 9,
      year_prior = "2009",
      content = "READING",
      year_span = 4
    ),
    list(
      grade_prior = 4,
      grade_current = 8,
      year_prior = "2009",
      content = "WRITING",
      year_span = 4
    )
  )
}

################################################################################
### FILTER CONDITIONS BY AVAILABLE CONTENT AREAS
################################################################################

# Filter out conditions with content areas not available in current dataset
if (
  exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)
) {
  available_content_areas <- current_dataset$content_areas
  original_count <- length(CONDITIONS)

  CONDITIONS <- CONDITIONS[sapply(CONDITIONS, function(cond) {
    cond$content %in% available_content_areas
  })]

  filtered_count <- original_count - length(CONDITIONS)
  if (filtered_count > 0) {
    cat("\n")
    cat(
      "====================================================================\n"
    )
    cat("CONTENT AREA FILTERING\n")
    cat(
      "====================================================================\n"
    )
    cat("Dataset:", current_dataset$name, "\n")
    cat(
      "Available content areas:",
      paste(available_content_areas, collapse = ", "),
      "\n"
    )
    cat(
      "Filtered out",
      filtered_count,
      "condition(s) with unavailable content areas\n"
    )
    cat("Remaining conditions:", length(CONDITIONS), "\n\n")
  }
}

################################################################################
### ENRICH CONDITIONS WITH DATASET METADATA
################################################################################

# Enrich each condition with dataset-specific metadata
if (
  exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset)
) {
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
    cond$prior_scaling_type <- get_scaling_type(
      current_dataset,
      cond$year_prior
    )
    cond$current_scaling_type <- get_scaling_type(current_dataset, year_current)
    cond$scaling_transition_type <- get_scaling_transition_type(
      current_dataset,
      cond$year_prior,
      year_current
    )

    # Add transition metadata
    cond$has_transition <- current_dataset$has_transition
    cond$transition_year <- if (current_dataset$has_transition) {
      current_dataset$transition_year
    } else {
      NA
    }
    cond$includes_transition_span <- crosses_transition(
      current_dataset,
      cond$year_prior,
      year_current
    )
    cond$transition_period <- get_transition_period(
      current_dataset,
      cond$year_prior,
      year_current
    )

    # Add pandemic-specific metadata (for dataset_4 / Hawaii)
    if (current_dataset$id == "dataset_4") {
      year_prior_num <- as.numeric(cond$year_prior)
      year_current_num <- as.numeric(year_current)

      # Classify pandemic period
      # 2020 was cancelled, so:
      #   - "before": Both years < 2020 (includes 2019 prior)
      #   - "during": Span crosses 2020 gap (2019 prior, 2021+ current)
      #   - "after": Both years >= 2021
      if (year_current_num < 2020) {
        cond$pandemic_period <- "before"
      } else if (year_prior_num < 2020 && year_current_num >= 2021) {
        cond$pandemic_period <- "during"
      } else {
        cond$pandemic_period <- "after"
      }

      # Set is_pandemic_pair flag (if not already set in condition definition)
      if (is.null(cond$is_pandemic_pair)) {
        cond$is_pandemic_pair <- FALSE
      }

      # Set is_baseline_pair flag (if not already set in condition definition)
      if (is.null(cond$is_baseline_pair)) {
        cond$is_baseline_pair <- FALSE
      }

      # If this is a baseline pair, ensure baseline_for is set
      # If this is a pandemic pair, create baseline_condition_id link
      if (cond$is_pandemic_pair) {
        # Create condition_id for linking to baseline
        # Format: YEAR_GPRIOR_GCURRENT_CONTENT
        cond$baseline_condition_id <- paste0(
          as.character(year_prior_num - 2),
          "_", # 2019 -> 2017, 2018 -> 2016
          "G",
          cond$grade_prior,
          "_G",
          cond$grade_current,
          "_",
          cond$content
        )
      }
    } else {
      # For non-dataset_4, these are NA
      cond$pandemic_period <- NA_character_
      cond$is_pandemic_pair <- FALSE
      cond$is_baseline_pair <- FALSE
      cond$baseline_condition_id <- NA_character_
    }

    # Update the condition in the list
    CONDITIONS[[i]] <- cond
  }

  cat("✓ Conditions enriched with dataset metadata\n")
  cat("  Dataset:", current_dataset$name, "\n")
  cat(
    "  Scaling types:",
    paste(
      unique(current_dataset$scaling_by_year$scaling_type),
      collapse = ", "
    ),
    "\n"
  )
  if (current_dataset$has_transition) {
    cat("  Transition year:", current_dataset$transition_year, "\n")
  }
  cat("\n")
} else {
  warning(
    "current_dataset not found. Conditions will not have dataset metadata."
  )
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

  cat(
    "\n====================================================================\n"
  )
  cat("Condition", i, "of", length(CONDITIONS), "\n")
  cat(
    "Year span:",
    cond$year_span,
    "year(s) |",
    "G",
    cond$grade_prior,
    "->",
    cond$grade_current,
    "\n"
  )
  cat("Years:", cond$year_prior, "->", cond$year_current, "\n")
  cat("Content:", cond$content, "\n")
  if (!is.null(cond$scaling_transition_type)) {
    cat("Scaling:", cond$scaling_transition_type, "\n")
  }
  if (
    !is.null(cond$includes_transition_span) && cond$includes_transition_span
  ) {
    cat("** CROSSES ASSESSMENT TRANSITION **\n")
  }
  cat(
    "====================================================================\n\n"
  )

  # Create longitudinal pairs
  pairs_full <- tryCatch(
    {
      create_longitudinal_pairs(
        data = get_state_data(),
        grade_prior = cond$grade_prior,
        grade_current = cond$grade_current,
        year_prior = cond$year_prior,
        content_prior = cond$content,
        content_current = cond$content
      )
    },
    error = function(e) {
      cat("Error creating pairs:", e$message, "\n")
      return(NULL)
    }
  )

  if (is.null(pairs_full) || nrow(pairs_full) < 100) {
    cat(
      "Insufficient data for this configuration (N =",
      ifelse(is.null(pairs_full), 0, nrow(pairs_full)),
      "). Skipping.\n"
    )
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
    framework_prior = framework_prior, # Still create for reference, but not used with ranks
    framework_current = framework_current,
    copula_families = COPULA_FAMILIES,
    return_best = FALSE,
    use_empirical_ranks = TRUE, # Phase 1: Use ranks to avoid I-spline distortion
    n_bootstrap_gof = if (exists("N_BOOTSTRAP_GOF", envir = .GlobalEnv)) {
      N_BOOTSTRAP_GOF
    } else {
      NULL
    }
  )

  # Generate visualization plots if requested
  if (
    exists("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv) &&
      get("GENERATE_CONTOUR_PLOTS", envir = .GlobalEnv, inherits = FALSE) &&
      !is.null(copula_fits$pseudo_obs)
  ) {
    # Prepare output directory for plots
    dataset_id <- if (!is.null(cond$dataset_id)) cond$dataset_id else "unknown"
    year_current <- if (!is.null(cond$year_current)) {
      cond$year_current
    } else {
      as.character(as.numeric(cond$year_prior) + cond$year_span)
    }

    plot_output_dir <- file.path(
      "STEP_1_Family_Selection/results",
      dataset_id,
      "contour_plots",
      sprintf(
        "%s_G%d_G%d_%s",
        cond$year_prior,
        cond$grade_prior,
        cond$grade_current,
        cond$content
      )
    )

    # Prepare condition info with dataset_number extraction and metadata enrichment
    # Get dataset config for metadata lookup
    dataset_config <- if (
      exists("DATASETS", envir = .GlobalEnv) && !is.null(DATASETS[[dataset_id]])
    ) {
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
      transition_period = if (
        !is.null(dataset_config) &&
          exists("get_transition_period", mode = "function")
      ) {
        tryCatch(
          get_transition_period(dataset_config, cond$year_prior, year_current),
          error = function(e) NA
        )
      } else {
        NA
      },
      pandemic_period = if (
        !is.null(dataset_config) &&
          exists("get_pandemic_period", mode = "function")
      ) {
        tryCatch(
          get_pandemic_period(dataset_config, cond$year_prior, year_current),
          error = function(e) NA
        )
      } else {
        NA
      },
      testing_mode_prior = if (
        !is.null(dataset_config) &&
          exists("get_testing_mode", mode = "function")
      ) {
        tryCatch(
          get_testing_mode(dataset_config, cond$year_prior),
          error = function(e) NA
        )
      } else {
        NA
      },
      testing_mode_current = if (
        !is.null(dataset_config) &&
          exists("get_testing_mode", mode = "function")
      ) {
        tryCatch(
          get_testing_mode(dataset_config, year_current),
          error = function(e) NA
        )
      } else {
        NA
      },
      has_missing_years = if (
        !is.null(dataset_config) &&
          exists("has_missing_years_in_span", mode = "function")
      ) {
        tryCatch(
          has_missing_years_in_span(
            dataset_config,
            cond$year_prior,
            year_current
          ),
          error = function(e) FALSE
        )
      } else {
        FALSE
      }
    )

    # Load empCopula objects if available
    empirical_copulas_file <- file.path(
      plot_output_dir,
      "empirical_copulas.rds"
    )
    empirical_copulas <- NULL
    if (file.exists(empirical_copulas_file)) {
      empirical_copulas <- tryCatch(
        {
          readRDS(empirical_copulas_file)
        },
        error = function(e) {
          warning(sprintf(
            "Failed to load empirical_copulas.rds: %s",
            e$message
          ))
          NULL
        }
      )
    }

    # Generate plots (wrapped in tryCatch to prevent failures from stopping analysis)
    tryCatch(
      {
        if (exists("generate_condition_plots")) {
          generate_condition_plots(
            pseudo_obs = copula_fits$pseudo_obs,
            original_scores = pairs_full[,
              .SD,
              .SDcols = intersect(
                names(pairs_full),
                c(
                  "SCALE_SCORE_PRIOR",
                  "SCALE_SCORE_CURRENT",
                  "SGP_ORDER_1",
                  "SGP"
                )
              )
            ],
            copula_results = copula_fits$results,
            best_family = copula_fits$best_family,
            output_dir = plot_output_dir,
            condition_info = condition_info,
            empirical_copulas = empirical_copulas, # NEW: Pass empCopula objects
            save_plots = TRUE,
            grid_size = 300, # High resolution for publication-quality plots
            export_formats = if (exists("EXPORT_FORMATS", envir = .GlobalEnv)) {
              EXPORT_FORMATS
            } else {
              c("pdf")
            },
            export_dpi = if (exists("EXPORT_DPI", envir = .GlobalEnv)) {
              EXPORT_DPI
            } else {
              300
            },
            export_verbose = if (exists("EXPORT_VERBOSE", envir = .GlobalEnv)) {
              EXPORT_VERBOSE
            } else {
              FALSE
            }
          )
          cat("  ✓ Plots generated successfully\n")
        } else {
          cat("  ⚠ Warning: generate_condition_plots function not found\n")
        }
      },
      error = function(e) {
        cat("  ⚠ Warning: Failed to generate plots:", e$message, "\n")
      }
    )
  }

  ##############################################################################
  ### CALCULATE SGPc (Copula-based Student Growth Percentiles)
  ##############################################################################

  if (
    exists("CALCULATE_SGPC", envir = .GlobalEnv) &&
      get("CALCULATE_SGPC", envir = .GlobalEnv, inherits = FALSE) &&
      !is.null(copula_fits$pseudo_obs) &&
      exists("sgpc_engine")
  ) {
    cat("\nCalculating SGPc for all copula families...\n")

    # Get pseudo-observations
    U <- copula_fits$pseudo_obs[, 1]
    V <- copula_fits$pseudo_obs[, 2]

    # Prepare output directory for SGPc results
    dataset_id <- if (!is.null(cond$dataset_id)) cond$dataset_id else "unknown"
    year_current <- if (!is.null(cond$year_current)) {
      cond$year_current
    } else {
      as.character(as.numeric(cond$year_prior) + cond$year_span)
    }

    sgpc_output_dir <- file.path(
      "STEP_1_Family_Selection/results",
      dataset_id,
      "sgpc",
      sprintf(
        "%s_G%d_G%d_%s",
        cond$year_prior,
        cond$grade_prior,
        cond$grade_current,
        cond$content
      )
    )
    dir.create(sgpc_output_dir, showWarnings = FALSE, recursive = TRUE)

    # Initialize SGPc data.table with row identifiers
    sgpc_results <- data.table(
      pair_idx = 1:nrow(pairs_full),
      ID = pairs_full$ID,
      YEAR_PRIOR = cond$year_prior,
      YEAR_CURRENT = year_current,
      GRADE_PRIOR = cond$grade_prior,
      GRADE_CURRENT = cond$grade_current,
      CONTENT_AREA = cond$content,
      U = U,
      V = V
    )

    # Add traditional SGP if available in the source data
    if ("SGP" %in% names(get_state_data())) {
      # Need to merge from original data based on ID + YEAR + GRADE + CONTENT
      state_data <- get_state_data()
      trad_sgp <- state_data[
        ID %in%
          pairs_full$ID &
          YEAR == year_current &
          GRADE == as.character(cond$grade_current) &
          CONTENT_AREA == cond$content,
        .(ID, SGP_traditional = SGP)
      ]
      sgpc_results <- merge(sgpc_results, trad_sgp, by = "ID", all.x = TRUE)
      cat("  ✓ Traditional SGP merged for comparison\n")
    }

    # Calculate SGPc for each parametric copula family
    for (family in COPULA_FAMILIES) {
      col_name <- paste0("SGPc_", family)

      if (!is.null(copula_fits$results[[family]])) {
        sgpc_results[[col_name]] <- tryCatch(
          {
            if (family == "comonotonic") {
              # Comonotonic uses string specification
              sgpc_engine(U, V, "comonotonic", scale = "percentile")
            } else if (!is.null(copula_fits$results[[family]]$copula)) {
              sgpc_engine(
                U,
                V,
                copula_fits$results[[family]]$copula,
                scale = "percentile"
              )
            } else {
              NA_integer_
            }
          },
          error = function(e) {
            warning(sprintf(
              "SGPc calculation failed for %s: %s",
              family,
              e$message
            ))
            rep(NA_integer_, nrow(sgpc_results))
          }
        )
        cat(sprintf("  ✓ SGPc_%s calculated\n", family))
      } else {
        sgpc_results[[col_name]] <- NA_integer_
      }
    }

    # Calculate SGPc for empirical copula (Bernstein smoothed) if available
    empirical_copulas_file <- file.path(
      plot_output_dir,
      "empirical_copulas.rds"
    )
    if (file.exists(empirical_copulas_file)) {
      empirical_copulas <- tryCatch(
        {
          readRDS(empirical_copulas_file)
        },
        error = function(e) NULL
      )

      if (
        !is.null(empirical_copulas) && !is.null(empirical_copulas$bernstein)
      ) {
        sgpc_results[["SGPc_bernstein"]] <- tryCatch(
          {
            sgpc_engine(
              U,
              V,
              empirical_copulas$bernstein,
              scale = "percentile",
              grid_size = 200
            )
          },
          error = function(e) {
            warning(sprintf(
              "SGPc calculation failed for Bernstein: %s",
              e$message
            ))
            rep(NA_integer_, nrow(sgpc_results))
          }
        )
        cat("  ✓ SGPc_bernstein calculated (empirical copula)\n")
      }
    } else {
      # Try to create empirical copula on the fly
      if (exists("fit_empirical_copulas")) {
        cat("  Creating Bernstein empirical copula...\n")
        emp_cops <- tryCatch(
          {
            fit_empirical_copulas(copula_fits$pseudo_obs, methods = "bernstein")
          },
          error = function(e) NULL
        )

        if (!is.null(emp_cops) && !is.null(emp_cops$bernstein)) {
          sgpc_results[["SGPc_bernstein"]] <- tryCatch(
            {
              sgpc_engine(
                U,
                V,
                emp_cops$bernstein,
                scale = "percentile",
                grid_size = 200
              )
            },
            error = function(e) {
              warning(sprintf(
                "SGPc calculation failed for Bernstein: %s",
                e$message
              ))
              rep(NA_integer_, nrow(sgpc_results))
            }
          )
          cat("  ✓ SGPc_bernstein calculated\n")
        }
      }
    }

    # Save SGPc results for this condition
    sgpc_file <- file.path(sgpc_output_dir, "sgpc_results.rds")
    saveRDS(sgpc_results, sgpc_file)
    cat(sprintf("  ✓ SGPc results saved: %s\n", sgpc_file))

    # Store summary statistics
    sgpc_cols <- grep("^SGPc_", names(sgpc_results), value = TRUE)
    if (length(sgpc_cols) > 0 && "SGP_traditional" %in% names(sgpc_results)) {
      cat("\n  SGPc vs Traditional SGP Correlations:\n")
      for (col in sgpc_cols) {
        valid_idx <- !is.na(sgpc_results[[col]]) &
          !is.na(sgpc_results$SGP_traditional)
        if (sum(valid_idx) > 10) {
          corr <- cor(
            sgpc_results[[col]][valid_idx],
            sgpc_results$SGP_traditional[valid_idx]
          )
          cat(sprintf(
            "    %-20s: r = %.4f (n = %d)\n",
            col,
            corr,
            sum(valid_idx)
          ))
        }
      }
    }

    cat("\n")
  }

  # Extract results for each family
  for (family in COPULA_FAMILIES) {
    if (!is.null(copula_fits$results[[family]])) {
      result_counter <- result_counter + 1

      fit <- copula_fits$results[[family]]

      # Extract tail dependence coefficients
      if (family %in% c("t", "t_df5", "t_df10", "t_df15")) {
        # All t-copula variants: use pre-calculated values from copula_bootstrap.R
        tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) {
          fit$tail_dependence_lower
        } else {
          0
        }
        tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) {
          fit$tail_dependence_upper
        } else {
          0
        }
      } else if (family == "clayton") {
        # Clayton has lower tail dependence only
        theta <- fit$parameter[1]
        tail_dep_lower <- 2^(-1 / theta)
        tail_dep_upper <- 0
      } else if (family == "gumbel") {
        # Gumbel has upper tail dependence only
        theta <- fit$parameter[1]
        tail_dep_lower <- 0
        tail_dep_upper <- 2 - 2^(1 / theta)
      } else if (family == "comonotonic") {
        # Comonotonic: use pre-calculated values
        tail_dep_lower <- if (!is.null(fit$tail_dependence_lower)) {
          fit$tail_dependence_lower
        } else {
          0
        }
        tail_dep_upper <- if (!is.null(fit$tail_dependence_upper)) {
          fit$tail_dependence_upper
        } else {
          1
        }
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
      degrees_freedom <- if (family %in% c("t", "t_df5", "t_df10", "t_df15")) {
        param_2
      } else {
        NA_real_
      }

      all_results[[result_counter]] <- data.table(
        # Dataset identifiers
        dataset_id = if (!is.null(cond$dataset_id)) {
          cond$dataset_id
        } else {
          NA_character_
        },
        dataset_name = if (!is.null(cond$dataset_name)) {
          cond$dataset_name
        } else {
          NA_character_
        },
        anonymized_state = if (!is.null(cond$anonymized_state)) {
          cond$anonymized_state
        } else {
          NA_character_
        },

        # Scaling characteristics
        prior_scaling_type = if (!is.null(cond$prior_scaling_type)) {
          cond$prior_scaling_type
        } else {
          NA_character_
        },
        current_scaling_type = if (!is.null(cond$current_scaling_type)) {
          cond$current_scaling_type
        } else {
          NA_character_
        },
        scaling_transition_type = if (!is.null(cond$scaling_transition_type)) {
          cond$scaling_transition_type
        } else {
          NA_character_
        },
        has_transition = if (!is.null(cond$has_transition)) {
          cond$has_transition
        } else {
          NA
        },
        transition_year = if (!is.null(cond$transition_year)) {
          cond$transition_year
        } else {
          NA
        },
        includes_transition_span = if (
          !is.null(cond$includes_transition_span)
        ) {
          cond$includes_transition_span
        } else {
          NA
        },
        transition_period = if (!is.null(cond$transition_period)) {
          cond$transition_period
        } else {
          NA_character_
        },

        # Condition identifiers
        condition_id = i,
        year_span = cond$year_span,
        grade_prior = cond$grade_prior,
        grade_current = cond$grade_current,
        year_prior = cond$year_prior,
        year_current = if (!is.null(cond$year_current)) {
          cond$year_current
        } else {
          as.character(as.numeric(cond$year_prior) + cond$year_span)
        },
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
        gof_statistic = if (!is.null(fit$gof_statistic)) {
          fit$gof_statistic
        } else {
          NA_real_
        },
        gof_pvalue = if (!is.null(fit$gof_pvalue)) fit$gof_pvalue else NA_real_,
        gof_pass_0.05 = if (!is.null(fit$gof_pvalue)) {
          (fit$gof_pvalue > 0.05)
        } else {
          NA
        },
        gof_method = if (!is.null(fit$gof_method)) {
          fit$gof_method
        } else {
          NA_character_
        }
      )

      cat(sprintf(
        "  %-10s: AIC = %8.2f, BIC = %8.2f, tau = %.4f\n",
        family,
        fit$aic,
        fit$bic,
        fit$kendall_tau
      ))
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

cat(
  "\n\n====================================================================\n"
)
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
if (
  exists("current_dataset", envir = .GlobalEnv) && !is.null(current_dataset$id)
) {
  dataset_results_dir <- paste0(
    "STEP_1_Family_Selection/results/",
    current_dataset$id
  )
  dir.create(dataset_results_dir, showWarnings = FALSE, recursive = TRUE)
  output_file <- paste0(
    dataset_results_dir,
    "/phase1_copula_family_comparison.csv"
  )
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
  stop(
    "ERROR: ALL_DATASET_RESULTS not found in global environment. Must be created by master_analysis.R"
  )
}

# Append to step1 results list using dataset_idx
if (!exists("dataset_idx", envir = .GlobalEnv)) {
  stop(
    "ERROR: dataset_idx not found in global environment. Must be set by master_analysis.R"
  )
}

dataset_idx_char <- as.character(dataset_idx)
# Directly assign to .GlobalEnv to avoid <<- operator issues
.GlobalEnv$ALL_DATASET_RESULTS$step1[[dataset_idx_char]] <- results_dt

cat("✓ Results stored for dataset", dataset_idx, "\n")
if (exists("CURRENT_DATASET_NAME")) {
  cat("  Dataset name:", CURRENT_DATASET_NAME, "\n")
}
cat(
  "  Dataset ID:",
  if (exists("current_dataset", envir = .GlobalEnv)) {
    current_dataset$id
  } else {
    "unknown"
  },
  "\n"
)
cat("  Total unique conditions:", uniqueN(results_dt$condition_id), "\n")
cat("  Total copula families tested:", length(COPULA_FAMILIES), "\n")
cat(
  "  Expected rows:",
  uniqueN(results_dt$condition_id),
  "×",
  length(COPULA_FAMILIES),
  "=",
  uniqueN(results_dt$condition_id) * length(COPULA_FAMILIES),
  "\n"
)
cat("  Actual rows:", nrow(results_dt), "\n")
if (
  nrow(results_dt) != uniqueN(results_dt$condition_id) * length(COPULA_FAMILIES)
) {
  cat("  ⚠ WARNING: Row count mismatch!\n")
}
cat("  Columns:", ncol(results_dt), "\n")
cat(
  "  Condition type:",
  if (USE_EXHAUSTIVE_CONDITIONS) "EXHAUSTIVE" else "STRATEGIC SUBSET",
  "\n\n"
)

cat(
  "Results will be combined with other datasets after all datasets complete.\n"
)
cat(
  "Combined file: STEP_1_Family_Selection/results/phase1_copula_family_comparison_all_datasets.csv\n\n"
)

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

cat(
  "\n\nPhase 1 complete! Proceed to phase1_analysis.R for detailed analysis.\n"
)
cat("====================================================================\n\n")
