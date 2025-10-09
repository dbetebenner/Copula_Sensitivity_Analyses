############################################################################
### Functions for Creating Longitudinal Pairs from Colorado Data
############################################################################

#' Create Longitudinal Pairs Dataset
#' 
#' Extracts valid prior-current grade pairs for copula analysis from
#' Colorado longitudinal assessment data
#' 
#' @param data data.table with columns: ID, GRADE, YEAR, CONTENT_AREA, SCALE_SCORE
#' @param grade_prior Prior grade level
#' @param grade_current Current grade level
#' @param year_prior Prior year
#' @param year_current Current year (if NULL, calculated from year_prior and grade span)
#' @param content_prior Content area for prior grade
#' @param content_current Content area for current grade (for cross-content analysis)
#' @param min_valid_score Minimum valid scale score (to filter out missing/invalid)
#' 
#' @return data.table with columns: ID, SCALE_SCORE_PRIOR, SCALE_SCORE_CURRENT,
#'         GRADE_PRIOR, GRADE_CURRENT, YEAR_PRIOR, YEAR_CURRENT, CONTENT_PRIOR, CONTENT_CURRENT
create_longitudinal_pairs <- function(data,
                                      grade_prior,
                                      grade_current,
                                      year_prior,
                                      year_current = NULL,
                                      content_prior = "MATHEMATICS",
                                      content_current = NULL,
                                      min_valid_score = 200) {
  
  require(data.table)
  
  # Set content_current to content_prior if not specified (within-content analysis)
  if (is.null(content_current)) {
    content_current <- content_prior
  }
  
  # Calculate year_current if not specified
  if (is.null(year_current)) {
    grade_span <- grade_current - grade_prior
    year_prior_numeric <- as.numeric(year_prior)
    year_current <- as.character(year_prior_numeric + grade_span)
  }
  
  # Extract prior grade data
  data_prior <- data[GRADE == grade_prior & 
                     YEAR == year_prior & 
                     CONTENT_AREA == content_prior &
                     !is.na(SCALE_SCORE) &
                     SCALE_SCORE >= min_valid_score,
                     .(ID, SCALE_SCORE_PRIOR = SCALE_SCORE)]
  
  # Extract current grade data
  data_current <- data[GRADE == grade_current & 
                       YEAR == year_current & 
                       CONTENT_AREA == content_current &
                       !is.na(SCALE_SCORE) &
                       SCALE_SCORE >= min_valid_score,
                       .(ID, SCALE_SCORE_CURRENT = SCALE_SCORE)]
  
  # Merge on ID to get matched pairs
  pairs <- merge(data_prior, data_current, by = "ID")
  
  # Add metadata
  pairs[, `:=`(
    GRADE_PRIOR = grade_prior,
    GRADE_CURRENT = grade_current,
    YEAR_PRIOR = year_prior,
    YEAR_CURRENT = year_current,
    CONTENT_PRIOR = content_prior,
    CONTENT_CURRENT = content_current,
    GRADE_SPAN = grade_current - grade_prior,
    YEAR_SPAN = as.numeric(year_current) - as.numeric(year_prior)
  )]
  
  # Report results
  cat("Longitudinal pairs created:\n")
  cat("  Prior: Grade", grade_prior, content_prior, year_prior, 
      "- N =", nrow(data_prior), "\n")
  cat("  Current: Grade", grade_current, content_current, year_current, 
      "- N =", nrow(data_current), "\n")
  cat("  Matched pairs: N =", nrow(pairs), "\n")
  cat("  Grade span:", grade_current - grade_prior, "years\n")
  cat("  Time span:", as.numeric(year_current) - as.numeric(year_prior), "years\n\n")
  
  return(pairs)
}


#' Create Multiple Longitudinal Pair Sets
#' 
#' Create multiple longitudinal pair configurations for comprehensive analysis
#' 
#' @param data Colorado longitudinal data
#' @param configurations List of configuration lists, each with grade_prior, grade_current, etc.
#' 
#' @return List of longitudinal pair data.tables
create_multiple_pairs <- function(data, configurations) {
  
  pairs_list <- vector("list", length(configurations))
  names(pairs_list) <- sapply(configurations, function(cfg) {
    paste0("G", cfg$grade_prior, "to", cfg$grade_current, "_", 
           cfg$year_prior, "_", cfg$content_prior)
  })
  
  for (i in seq_along(configurations)) {
    cfg <- configurations[[i]]
    
    pairs_list[[i]] <- create_longitudinal_pairs(
      data = data,
      grade_prior = cfg$grade_prior,
      grade_current = cfg$grade_current,
      year_prior = cfg$year_prior,
      year_current = cfg$year_current,
      content_prior = cfg$content_prior,
      content_current = cfg$content_current,
      min_valid_score = if(!is.null(cfg$min_valid_score)) cfg$min_valid_score else 200
    )
  }
  
  return(pairs_list)
}


#' Get Available Longitudinal Configurations
#' 
#' Identify all valid grade/year/content combinations available in data
#' 
#' @param data Colorado longitudinal data
#' @param min_grade_span Minimum grade span to consider (default 1)
#' @param max_grade_span Maximum grade span to consider (default 5)
#' @param min_pairs Minimum number of matched pairs required
#' 
#' @return data.table of available configurations with sample sizes
get_available_configurations <- function(data, 
                                        min_grade_span = 1,
                                        max_grade_span = 5,
                                        min_pairs = 100) {
  
  require(data.table)
  
  # Get unique grade/year/content combinations with counts
  available <- data[!is.na(SCALE_SCORE) & SCALE_SCORE >= 200,
                   .(N = .N),
                   by = .(GRADE, YEAR, CONTENT_AREA)]
  
  setkey(available, GRADE, YEAR, CONTENT_AREA)
  
  # Create all possible prior-current combinations
  configs <- CJ(
    grade_prior = unique(available$GRADE),
    grade_current = unique(available$GRADE),
    year_prior = unique(available$YEAR),
    content_area = unique(available$CONTENT_AREA)
  )
  
  # Filter for valid grade spans
  configs <- configs[grade_current > grade_prior &
                     (grade_current - grade_prior) >= min_grade_span &
                     (grade_current - grade_prior) <= max_grade_span]
  
  # Calculate expected current year based on grade span
  configs[, year_current := as.character(as.numeric(year_prior) + 
                                         (grade_current - grade_prior))]
  
  # Check if both grades exist in the data
  configs[, valid := FALSE]
  
  for (i in 1:nrow(configs)) {
    prior_exists <- nrow(available[GRADE == configs$grade_prior[i] &
                                   YEAR == configs$year_prior[i] &
                                   CONTENT_AREA == configs$content_area[i]]) > 0
    
    current_exists <- nrow(available[GRADE == configs$grade_current[i] &
                                     YEAR == configs$year_current[i] &
                                     CONTENT_AREA == configs$content_area[i]]) > 0
    
    configs$valid[i] <- prior_exists & current_exists
  }
  
  configs <- configs[valid == TRUE]
  configs[, valid := NULL]
  
  cat("Found", nrow(configs), "valid longitudinal configurations\n")
  cat("Grade spans:", paste(sort(unique(configs$grade_current - configs$grade_prior)), 
                            collapse = ", "), "\n")
  cat("Content areas:", paste(unique(configs$content_area), collapse = ", "), "\n\n")
  
  return(configs[order(grade_prior, grade_current, year_prior, content_area)])
}
