################################################################################
### DATASET CONFIGURATIONS
### Multi-dataset copula sensitivity analysis
################################################################################

DATASETS <- list(
  
  # Dataset 1: Vertically scaled (original Colorado data)
  dataset_1 = list(
    id = "dataset_1",
    name = "Dataset 1 (Vertical Scale)",
    description = "Multi-year vertically scaled state assessment",
    anonymized_state = "State A",
    has_transition = FALSE,
    transition_year = NA,
    rdata_object_name = "Copula_Sensitivity_Data_Set_1",
    local_path = "Data/Copula_Sensitivity_Data_Set_1.Rdata",
    ec2_path = "/data/Dropbox/Damian Betebenner/TEMP/Copula_Sensitivity_Analyses/Data/Copula_Sensitivity_Data_Set_1.Rdata",
    years_available = 2005:2014,
    grades_available = 3:10,
    content_areas = c("MATHEMATICS", "READING", "WRITING"),
    
    # Year-specific scaling lookup
    scaling_by_year = data.frame(
      year = 2005:2014,
      scaling_type = rep("vertical", 10),
      stringsAsFactors = FALSE
    ),
    
    notes = "Vertically scaled across all years. Proficiency cut increases with grade."
  ),
  
  # Dataset 2: Non-vertically scaled
  dataset_2 = list(
    id = "dataset_2",
    name = "Dataset 2 (Non-Vertical Scale)",
    description = "Multi-year non-vertically scaled state assessment",
    anonymized_state = "State B",
    has_transition = FALSE,
    transition_year = NA,
    rdata_object_name = "Copula_Sensitivity_Data_Set_2",
    local_path = "Data/Copula_Sensitivity_Data_Set_2.Rdata",
    ec2_path = "/data/Dropbox/Damian Betebenner/TEMP/Copula_Sensitivity_Analyses/Data/Copula_Sensitivity_Data_Set_2.Rdata",
    years_available = 2007:2014, 
    grades_available = c(3:8, 10),
    content_areas = c("MATHEMATICS", "READING"),
    
    # Year-specific scaling lookup
    scaling_by_year = data.frame(
      year = 2007:2014,
      scaling_type = rep("non_vertical", 8),
      stringsAsFactors = FALSE
    ),
    
    notes = "Non-vertically scaled across all years. Same scale range (e.g., 400-600) for all grades."
  ),
  
  # Dataset 3: Assessment transition
  dataset_3 = list(
    id = "dataset_3",
    name = "Dataset 3 (Transition)",
    description = "Multi-year with assessment transition",
    anonymized_state = "State C",
    has_transition = TRUE,
    transition_year = 2015,
    rdata_object_name = "Copula_Sensitivity_Data_Set_3",
    local_path = "Data/Copula_Sensitivity_Data_Set_3.Rdata",
    ec2_path = "/data/Dropbox/Damian Betebenner/TEMP/Copula_Sensitivity_Analyses/Data/Copula_Sensitivity_Data_Set_3.Rdata",
    years_available = 2013:2017,
    grades_available = 3:8,
    content_areas = c("ELA", "MATHEMATICS"),
    
    # Year-specific scaling lookup with transition
    scaling_by_year = data.frame(
      year = 2013:2017,
      scaling_type = c("vertical", "vertical",           # 2013, 2014 (before transition)
                      "non_vertical", "non_vertical", "non_vertical"),  # 2015-2017 (after transition)
      stringsAsFactors = FALSE
    ),
    
    notes = "Assessment transition in 2015. Vertical scale (2013-2014) to non-vertical scale (2015-2017)."
  )
)

################################################################################
### HELPER FUNCTIONS FOR DATASET CONFIGURATION
################################################################################

#' Get scaling type for a specific year
#' 
#' @param dataset_config A dataset configuration list from DATASETS
#' @param year Year as numeric or character
#' @return Character: "vertical" or "non_vertical", or NA if year not found
get_scaling_type <- function(dataset_config, year) {
  year_num <- as.numeric(as.character(year))
  scaling_df <- dataset_config$scaling_by_year
  
  match_row <- scaling_df[scaling_df$year == year_num, ]
  
  if (nrow(match_row) == 0) {
    warning("Year ", year_num, " not found in scaling_by_year for dataset ", 
            dataset_config$id, ". Returning NA.")
    return(NA_character_)
  }
  
  return(match_row$scaling_type[1])
}

#' Determine if a year span crosses an assessment transition
#' 
#' @param dataset_config A dataset configuration list from DATASETS
#' @param year_prior Starting year (prior observation)
#' @param year_current Ending year (current observation)
#' @return Logical: TRUE if span crosses transition, FALSE otherwise
crosses_transition <- function(dataset_config, year_prior, year_current) {
  if (!dataset_config$has_transition || is.na(dataset_config$transition_year)) {
    return(FALSE)
  }
  
  year_prior_num <- as.numeric(as.character(year_prior))
  year_current_num <- as.numeric(as.character(year_current))
  transition_year <- dataset_config$transition_year
  
  # Crosses if prior is before transition and current is at/after transition
  return(year_prior_num < transition_year && year_current_num >= transition_year)
}

#' Get descriptive scaling transition type
#' 
#' @param dataset_config A dataset configuration list from DATASETS
#' @param year_prior Starting year
#' @param year_current Ending year
#' @return Character: "vertical_to_vertical", "vertical_to_non_vertical", etc.
get_scaling_transition_type <- function(dataset_config, year_prior, year_current) {
  prior_type <- get_scaling_type(dataset_config, year_prior)
  current_type <- get_scaling_type(dataset_config, year_current)
  
  if (is.na(prior_type) || is.na(current_type)) {
    return(NA_character_)
  }
  
  # Create descriptive label
  return(paste0(prior_type, "_to_", current_type))
}

#' Get transition period label for a year span
#' 
#' @param dataset_config A dataset configuration list from DATASETS
#' @param year_prior Starting year
#' @param year_current Ending year
#' @return Character: "before", "during", "after", or NA
get_transition_period <- function(dataset_config, year_prior, year_current) {
  if (!dataset_config$has_transition || is.na(dataset_config$transition_year)) {
    return(NA_character_)
  }
  
  year_prior_num <- as.numeric(as.character(year_prior))
  year_current_num <- as.numeric(as.character(year_current))
  transition_year <- dataset_config$transition_year
  
  if (year_current_num < transition_year) {
    return("before")
  } else if (year_prior_num >= transition_year) {
    return("after")
  } else {
    return("during")  # Spans the transition
  }
}

#' Generate exhaustive conditions for a dataset
#' 
#' Creates all valid longitudinal pairs for years, grades, and content areas
#' in a dataset. Used for detailed analysis, especially for transition datasets.
#' 
#' @param dataset_config A dataset configuration list from DATASETS
#' @param max_year_span Maximum years between observations (default 4)
#' @return List of condition specifications
#' 
#' @examples
#' conditions <- generate_exhaustive_conditions(DATASETS$dataset_3, max_year_span = 4)
generate_exhaustive_conditions <- function(dataset_config, max_year_span = 4) {
  
  years <- dataset_config$years_available
  grades <- dataset_config$grades_available
  content_areas <- dataset_config$content_areas
  
  conditions <- list()
  condition_id <- 1
  
  cat("Generating exhaustive conditions for:", dataset_config$name, "\n")
  cat("  Years:", paste(range(years), collapse = "-"), "\n")
  cat("  Grades:", paste(range(grades), collapse = "-"), "\n")
  cat("  Content areas:", paste(content_areas, collapse = ", "), "\n")
  cat("  Max year span:", max_year_span, "\n\n")
  
  # Loop through all valid combinations
  for (year_span in 1:max_year_span) {
    for (year_prior in years) {
      year_current <- year_prior + year_span
      
      # Check if current year is available in dataset
      if (!(year_current %in% years)) {
        next
      }
      
      for (grade_prior in grades) {
        grade_current <- grade_prior + year_span
        
        # Check if current grade is available
        if (!(grade_current %in% grades)) {
          next
        }
        
        for (content in content_areas) {
          # Create condition
          conditions[[condition_id]] <- list(
            grade_prior = grade_prior,
            grade_current = grade_current,
            year_prior = as.character(year_prior),
            content = content,
            year_span = year_span
          )
          
          condition_id <- condition_id + 1
        }
      }
    }
  }
  
  cat("✓ Generated", length(conditions), "exhaustive conditions\n\n")
  
  return(conditions)
}
