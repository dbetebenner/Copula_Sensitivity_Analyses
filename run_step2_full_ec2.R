# EC2 launcher: full STEP_2 pipeline across all 4 datasets
# Target profile: r8g.16xlarge (64 vCPU, 512 GB RAM)

# Core execution mode
BATCH_MODE <- TRUE
EC2_MODE <- TRUE
USE_PARALLEL_STEP2 <- TRUE

# Reliability / resumability
SKIP_COMPLETED <- TRUE
SKIP_COMPLETED_STEP2 <- TRUE

# Full 4-dataset STEP_2 run
DATASETS_TO_RUN <- NULL
STEPS_TO_RUN <- c(2)

# Subset OFF for production run (set to 5/25/50 for staging tests)
STEP2_MAX_CONDITIONS <- NULL
STEP2_SAMPLE_STRATEGY <- "stratified"
STEP2_SEED <- 42

# Memory controls for r8g.16xlarge
STEP2_MEMORY_PER_WORKER_GB <- 3.0
STEP2_TOTAL_MEMORY_GB <- 512

# Run master pipeline
source("master_analysis.R")
