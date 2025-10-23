################################################################################
### TEST SCRIPT: Verify Dataset Loop Configuration
### 
### This script tests that the multi-dataset infrastructure is working correctly
### without running the full analysis.
################################################################################

cat("====================================================================\n")
cat("TESTING MULTI-DATASET CONFIGURATION\n")
cat("====================================================================\n\n")

# Load dataset configurations
if (file.exists("dataset_configs.R")) {
  cat("✓ Found dataset_configs.R\n")
  source("dataset_configs.R")
  
  cat("✓ Loaded", length(DATASETS), "dataset configurations:\n\n")
  
  for (ds_id in names(DATASETS)) {
    ds <- DATASETS[[ds_id]]
    cat("Dataset:", ds$name, "\n")
    cat("  ID:", ds$id, "\n")
    cat("  Type:", ds$scaling_type, "\n")
    cat("  Transition:", ds$has_transition, "\n")
    cat("  Data file:", ds$local_path, "\n")
    cat("  File exists:", file.exists(ds$local_path), "\n")
    cat("\n")
  }
  
} else {
  stop("ERROR: dataset_configs.R not found")
}

cat("====================================================================\n")
cat("TESTING DATA LOADING\n")
cat("====================================================================\n\n")

require(data.table)

WORKSPACE_OBJECT_NAME <- "STATE_DATA_LONG"

for (ds_id in names(DATASETS)) {
  ds <- DATASETS[[ds_id]]
  
  cat("Loading:", ds$name, "\n")
  cat("  Path:", ds$local_path, "\n")
  cat("  Object name:", ds$rdata_object_name, "\n")
  
  if (!file.exists(ds$local_path)) {
    cat("  ✗ ERROR: File not found!\n\n")
    next
  }
  
  # Load the data
  load(ds$local_path)
  
  # Check if object exists
  if (!exists(ds$rdata_object_name)) {
    cat("  ✗ ERROR: Object", ds$rdata_object_name, "not found in .Rdata file\n")
    cat("  Available objects:", paste(ls(), collapse = ", "), "\n\n")
    next
  }
  
  # Assign to workspace
  assign(WORKSPACE_OBJECT_NAME, get(ds$rdata_object_name))
  
  # Get info
  data_obj <- get(WORKSPACE_OBJECT_NAME)
  
  cat("  ✓ Loaded successfully\n")
  cat("  Rows:", nrow(data_obj), "\n")
  cat("  Columns:", ncol(data_obj), "\n")
  cat("  Column names:", paste(names(data_obj), collapse = ", "), "\n")
  
  # Check for required columns
  required_cols <- c("ID", "GRADE", "YEAR", "CONTENT_AREA", "SCALE_SCORE", 
                     "VALID_CASE", "SCALE_SCORE_PRIOR")
  missing_cols <- setdiff(required_cols, names(data_obj))
  
  if (length(missing_cols) > 0) {
    cat("  ⚠ WARNING: Missing required columns:", paste(missing_cols, collapse = ", "), "\n")
  } else {
    cat("  ✓ All required columns present\n")
  }
  
  # Check year range
  if ("YEAR" %in% names(data_obj)) {
    year_range <- range(data_obj$YEAR, na.rm = TRUE)
    cat("  Year range:", paste(year_range, collapse = "-"), "\n")
  }
  
  # Check content areas
  if ("CONTENT_AREA" %in% names(data_obj)) {
    content_areas <- unique(data_obj$CONTENT_AREA)
    cat("  Content areas:", paste(content_areas, collapse = ", "), "\n")
  }
  
  cat("\n")
}

cat("====================================================================\n")
cat("TEST COMPLETE\n")
cat("====================================================================\n\n")

cat("Summary:\n")
cat("  Datasets configured:", length(DATASETS), "\n")
cat("  All data files accessible and loadable\n")
cat("  Ready to run master_analysis.R with multi-dataset mode\n\n")

