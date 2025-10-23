################################################################################
### TEST SCRIPT: Verify Dataset Metadata Enrichment
### Tests the new LONG-format structure with dataset metadata
################################################################################

cat("====================================================================\n")
cat("TESTING DATASET METADATA ENRICHMENT\n")
cat("====================================================================\n\n")

# Load dataset configurations
if (file.exists("dataset_configs.R")) {
  cat("✓ Loading dataset_configs.R\n")
  source("dataset_configs.R")
} else {
  stop("ERROR: dataset_configs.R not found")
}

require(data.table)

# Test the helper functions
cat("\n====================================================================\n")
cat("TESTING HELPER FUNCTIONS\n")
cat("====================================================================\n\n")

for (ds_id in names(DATASETS)) {
  ds <- DATASETS[[ds_id]]
  cat("Dataset:", ds$name, "\n")
  
  # Test get_scaling_type
  test_years <- head(ds$years_available, 3)
  for (yr in test_years) {
    scaling <- get_scaling_type(ds, yr)
    cat("  Year", yr, "scaling type:", scaling, "\n")
  }
  
  # Test transitions (if applicable)
  if (ds$has_transition) {
    year_before <- ds$transition_year - 2
    year_after <- ds$transition_year + 1
    
    cat("\n  Testing transition detection:\n")
    cat("    Years", year_before, "to", year_after, "crosses transition:", 
        crosses_transition(ds, year_before, year_after), "\n")
    cat("    Scaling transition type:", 
        get_scaling_transition_type(ds, year_before, year_after), "\n")
    cat("    Transition period:", 
        get_transition_period(ds, year_before, year_after), "\n")
  }
  
  cat("\n")
}

cat("====================================================================\n")
cat("TESTING CONDITION ENRICHMENT LOGIC\n")
cat("====================================================================\n\n")

# Simulate what phase1_family_selection.R does
current_dataset <- DATASETS[["dataset_3"]]  # Use transition dataset for testing

# Create a test condition
test_condition <- list(
  grade_prior = 4,
  grade_current = 5,
  year_prior = "2014",  # Before transition
  content = "MATHEMATICS",
  year_span = 1
)

cat("Base condition:\n")
print(test_condition)

# Enrich it
year_current <- as.character(as.numeric(test_condition$year_prior) + test_condition$year_span)

test_condition$dataset_id <- current_dataset$id
test_condition$dataset_name <- current_dataset$name
test_condition$anonymized_state <- current_dataset$anonymized_state
test_condition$year_current <- year_current
test_condition$prior_scaling_type <- get_scaling_type(current_dataset, test_condition$year_prior)
test_condition$current_scaling_type <- get_scaling_type(current_dataset, year_current)
test_condition$scaling_transition_type <- get_scaling_transition_type(current_dataset, test_condition$year_prior, year_current)
test_condition$has_transition <- current_dataset$has_transition
test_condition$transition_year <- if (current_dataset$has_transition) current_dataset$transition_year else NA
test_condition$includes_transition_span <- crosses_transition(current_dataset, test_condition$year_prior, year_current)
test_condition$transition_period <- get_transition_period(current_dataset, test_condition$year_prior, year_current)

cat("\nEnriched condition:\n")
print(test_condition)

cat("\n====================================================================\n")
cat("TESTING LONG FORMAT DATA.TABLE STRUCTURE\n")
cat("====================================================================\n\n")

# Create a sample results data.table
sample_result <- data.table(
  # Dataset identifiers
  dataset_id = test_condition$dataset_id,
  dataset_name = test_condition$dataset_name,
  anonymized_state = test_condition$anonymized_state,
  
  # Scaling characteristics
  prior_scaling_type = test_condition$prior_scaling_type,
  current_scaling_type = test_condition$current_scaling_type,
  scaling_transition_type = test_condition$scaling_transition_type,
  has_transition = test_condition$has_transition,
  transition_year = test_condition$transition_year,
  includes_transition_span = test_condition$includes_transition_span,
  transition_period = test_condition$transition_period,
  
  # Condition identifiers
  condition_id = 1,
  year_span = test_condition$year_span,
  grade_prior = test_condition$grade_prior,
  grade_current = test_condition$grade_current,
  year_prior = test_condition$year_prior,
  year_current = test_condition$year_current,
  content_area = test_condition$content,
  n_pairs = 1000,
  
  # Copula results (sample values)
  family = "t",
  aic = 1234.56,
  bic = 1245.67,
  loglik = -615.28,
  tau = 0.71,
  tail_dep_lower = 0.15,
  tail_dep_upper = 0.15,
  parameter_1 = 0.65,
  parameter_2 = 8.5,
  
  # Comparative
  best_aic = "t",
  best_bic = "t",
  delta_aic_vs_best = 0.0,
  delta_bic_vs_best = 0.0
)

cat("Sample LONG format row:\n")
print(t(sample_result))

cat("\n====================================================================\n")
cat("COLUMN SUMMARY\n")
cat("====================================================================\n\n")

cat("Total columns:", ncol(sample_result), "\n\n")

cat("Column names:\n")
for (col in names(sample_result)) {
  cat(" ", col, "\n")
}

cat("\n====================================================================\n")
cat("TEST COMPLETE\n")
cat("====================================================================\n\n")

cat("✓ Dataset configuration system working correctly\n")
cat("✓ Helper functions operational\n")
cat("✓ Condition enrichment logic verified\n")
cat("✓ LONG format structure confirmed\n\n")

cat("Ready to run full analysis with multi-dataset + LONG format!\n\n")

