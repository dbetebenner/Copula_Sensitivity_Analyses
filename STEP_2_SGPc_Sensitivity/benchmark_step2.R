############################################################################
### STEP_2 Local Benchmark Script
###
### Purpose: Profile STEP_2 SGPc variant computation on subsets of
### dataset_1 (largest dataset) to estimate full-run wall time and
### memory requirements for EC2 execution.
###
### Usage (from project root):
###   Rscript STEP_2_SGPc_Sensitivity/benchmark_step2.R
###   # or interactively:
###   source("STEP_2_SGPc_Sensitivity/benchmark_step2.R")
###
### Output: STEP_2_SGPc_Sensitivity/results/perf/benchmark_summary.csv
###         STEP_2_SGPc_Sensitivity/results/perf/ec2_projections.txt
###
### Author: dataimago
### Date: February 2026
############################################################################

cat("\n====================================================================\n")
cat("STEP_2 BENCHMARK: Local profiling for EC2 calibration\n")
cat("====================================================================\n\n")

# --- Configuration ---
BENCHMARK_DATASETS <- c("dataset_1")  # Focus on the bottleneck dataset
BENCHMARK_SUBSETS  <- c(5, 10, 25)    # Number of conditions per run
BENCHMARK_PARALLEL <- TRUE
BENCHMARK_SEED     <- 42

# Ensure we're in the project root
if (!file.exists("master_analysis.R")) {
  # Try to find it
  if (file.exists("../master_analysis.R")) {
    setwd("..")
  } else {
    stop("Run this script from the Copula_Sensitivity_Analyses project root.")
  }
}

# Load prerequisites
cat("Loading prerequisites...\n")
source("dataset_configs.R")
if (file.exists("dataset_configs_local.R")) source("dataset_configs_local.R")

require(data.table)
require(copula)

# Source shared functions
source("functions/sgpc_engine.R")
source("functions/longitudinal_pairs.R")
source("STEP_2_SGPc_Sensitivity/phase1_data_loader.R")

# Load canonical parameters
canonical_data <- load_canonical_parameters()
canonical_params <- canonical_data$canonical_params
manifest <- canonical_data$manifest

# Global flags expected by the computation script
IS_EC2 <- FALSE
USE_SGP_DATA <- TRUE  # Use SGP data if available

# Results accumulator
results <- list()

for (ds_id in BENCHMARK_DATASETS) {
  cat("\n====================================================================\n")
  cat("Benchmarking:", ds_id, "\n")
  cat("====================================================================\n\n")
  
  # Load dataset once (shared across subset runs)
  ds_config <- DATASETS[[ds_id]]
  if (is.null(ds_config)) {
    cat("  SKIP: no config for", ds_id, "\n")
    next
  }
  
  # Determine path
  use_sgp <- !is.null(ds_config$local_path_sgp)
  fpath <- if (use_sgp) ds_config$local_path_sgp else ds_config$local_path
  fobj  <- if (use_sgp) ds_config$rdata_object_name_sgp else ds_config$rdata_object_name
  
  if (!file.exists(fpath)) {
    cat("  SKIP: data file not found:", fpath, "\n")
    next
  }
  
  cat("Loading dataset:", fpath, "\n")
  load_start <- Sys.time()
  load(fpath)
  STATE_DATA_LONG <- get(fobj)
  if (!inherits(STATE_DATA_LONG, "data.table")) STATE_DATA_LONG <- as.data.table(STATE_DATA_LONG)
  load_secs <- as.numeric(difftime(Sys.time(), load_start, units = "secs"))
  cat(sprintf("  Loaded %s rows in %.1f s\n", format(nrow(STATE_DATA_LONG), big.mark = ","), load_secs))
  
  # Cache in global env for workers
  assign("STATE_DATA_LONG", STATE_DATA_LONG, envir = .GlobalEnv)
  assign(".LOADED_DATASET_ID", ds_id, envir = .GlobalEnv)
  assign("DATASETS", DATASETS, envir = .GlobalEnv)
  
  # Get all conditions
  all_conds <- get_phase1_conditions(ds_id)
  cat("Total conditions:", length(all_conds), "\n\n")
  
  # File size for memory estimate
  file_gb <- file.info(fpath)$size / 1024^3
  
  for (n_sub in BENCHMARK_SUBSETS) {
    cat(sprintf("\n--- Subset: %d conditions (stratified, seed=%d) ---\n", n_sub, BENCHMARK_SEED))
    
    # Set globals for the compute script
    STEP2_MAX_CONDITIONS    <- n_sub
    STEP2_SAMPLE_STRATEGY   <- "stratified"
    STEP2_SEED              <- BENCHMARK_SEED
    STEP2_MEMORY_PER_WORKER_GB <- NULL  # auto
    STEP2_TOTAL_MEMORY_GB      <- NULL  # auto
    USE_PARALLEL            <- BENCHMARK_PARALLEL
    DATASETS_TO_PROCESS     <- ds_id
    
    assign("STEP2_MAX_CONDITIONS",       STEP2_MAX_CONDITIONS,       envir = .GlobalEnv)
    assign("STEP2_SAMPLE_STRATEGY",      STEP2_SAMPLE_STRATEGY,      envir = .GlobalEnv)
    assign("STEP2_SEED",                 STEP2_SEED,                 envir = .GlobalEnv)
    assign("STEP2_MEMORY_PER_WORKER_GB", STEP2_MEMORY_PER_WORKER_GB, envir = .GlobalEnv)
    assign("STEP2_TOTAL_MEMORY_GB",      STEP2_TOTAL_MEMORY_GB,      envir = .GlobalEnv)
    assign("USE_PARALLEL",               USE_PARALLEL,               envir = .GlobalEnv)
    assign("DATASETS_TO_PROCESS",        DATASETS_TO_PROCESS,        envir = .GlobalEnv)
    
    bench_start <- Sys.time()
    
    tryCatch({
      source("STEP_2_SGPc_Sensitivity/sgpc_compute_all_variants.R")
    }, error = function(e) {
      cat("ERROR:", e$message, "\n")
    })
    
    bench_secs <- as.numeric(difftime(Sys.time(), bench_start, units = "secs"))
    
    # Read the perf log just written
    perf_file <- file.path("STEP_2_SGPc_Sensitivity/results/perf",
                           paste0("step2_perf_", ds_id, ".json"))
    perf <- if (file.exists(perf_file)) jsonlite::fromJSON(perf_file) else list()
    
    n_ok <- if (!is.null(perf$n_ok)) perf$n_ok else 0
    compute_secs <- if (!is.null(perf$compute_secs)) perf$compute_secs else bench_secs
    
    results[[length(results) + 1]] <- data.frame(
      dataset      = ds_id,
      n_subset     = n_sub,
      n_completed  = n_ok,
      compute_secs = round(compute_secs, 1),
      total_secs   = round(bench_secs, 1),
      secs_per_cond = round(if (n_ok > 0) compute_secs / n_ok else NA, 2),
      file_gb      = round(file_gb, 3),
      stringsAsFactors = FALSE
    )
    
    cat(sprintf("  Completed: %d conditions in %.1f s (%.2f s/condition)\n",
                n_ok, compute_secs,
                if (n_ok > 0) compute_secs / n_ok else NA))
    
    # Clean up results file to avoid confusion (these are benchmark artifacts)
    rds_file <- file.path("STEP_2_SGPc_Sensitivity/results",
                          paste0("sgpc_all_variants_", ds_id, ".rds"))
    if (file.exists(rds_file)) {
      new_name <- file.path("STEP_2_SGPc_Sensitivity/results",
                            paste0("sgpc_all_variants_", ds_id, "_benchmark_", n_sub, ".rds"))
      file.rename(rds_file, new_name)
      cat("  Renamed benchmark output:", basename(new_name), "\n")
    }
    
    gc(verbose = FALSE)
  }
  
  # Clean up dataset from memory
  rm(STATE_DATA_LONG, envir = .GlobalEnv)
  gc(verbose = FALSE)
}

# --- Save benchmark summary ---
perf_dir <- "STEP_2_SGPc_Sensitivity/results/perf"
if (!dir.exists(perf_dir)) dir.create(perf_dir, recursive = TRUE, showWarnings = FALSE)

if (length(results) > 0) {
  bench_df <- do.call(rbind, results)
  
  summary_file <- file.path(perf_dir, "benchmark_summary.csv")
  write.csv(bench_df, summary_file, row.names = FALSE)
  cat("\n\nBenchmark summary saved:", summary_file, "\n")
  print(bench_df)
  
  # --- EC2 Projections ---
  proj_file <- file.path(perf_dir, "ec2_projections.txt")
  
  sink(proj_file)
  cat("====================================================================\n")
  cat("EC2 RUNTIME PROJECTIONS (from local benchmark)\n")
  cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
  cat("====================================================================\n\n")
  
  # Use median secs_per_cond for projection
  med_rate <- median(bench_df$secs_per_cond, na.rm = TRUE)
  
  cat(sprintf("Observed throughput: %.2f seconds/condition (median across subsets)\n\n", med_rate))
  
  # Dataset condition counts (from Phase 1)
  ds_counts <- c(dataset_1 = 510, dataset_2 = 194, dataset_3 = 80, dataset_4 = 182)
  
  cat("--- Projected SEQUENTIAL runtimes (1 core) ---\n")
  for (ds in names(ds_counts)) {
    n <- ds_counts[ds]
    hours <- (n * med_rate) / 3600
    cat(sprintf("  %s: %d conditions × %.1f s = %.1f hours\n", ds, n, med_rate, hours))
  }
  total_seq_hours <- sum(ds_counts * med_rate) / 3600
  cat(sprintf("  TOTAL: %.1f hours\n\n", total_seq_hours))
  
  cat("--- Projected PARALLEL runtimes (scaling from local benchmark) ---\n")
  cat("  (Assumes linear speedup with workers; actual overhead ~10-20%)\n\n")
  
  local_cores <- parallel::detectCores() - 2
  for (ec2_cores in c(16, 32, 64, 96, 192)) {
    speedup <- ec2_cores / max(1, local_cores) 
    est_hours <- total_seq_hours / speedup * 1.15  # 15% overhead
    cat(sprintf("  %3d cores: ~%.1f hours  (speedup %.1fx vs %d local cores)\n",
                ec2_cores, est_hours, speedup, local_cores))
  }
  
  cat("\n--- Memory Recommendations ---\n")
  cat(sprintf("  dataset_1 file: %.2f GB (in-memory ~%.1f GB per worker)\n",
              bench_df$file_gb[1], bench_df$file_gb[1] * 7 + 0.5))
  cat("  Recommended EC2 instance:\n")
  cat("    r8g.24xlarge  (96 vCPU, 768 GB) — safe for all datasets in parallel\n")
  cat("    r8g.12xlarge  (48 vCPU, 384 GB) — adequate, may need fewer workers for dataset_1\n")
  cat("    m8g.metal-48xl (192 vCPU, 768 GB) — fastest, same as STEP_1 run\n\n")
  
  cat("--- Subset Testing Recipe (on EC2) ---\n")
  cat("  1. STEP2_MAX_CONDITIONS <- 10  # Quick smoke test (~2-5 min)\n")
  cat("  2. STEP2_MAX_CONDITIONS <- 50  # Medium validation (~15-30 min)\n")
  cat("  3. STEP2_MAX_CONDITIONS <- NULL # Full run\n")
  cat("====================================================================\n")
  sink()
  
  cat("\nEC2 projections saved:", proj_file, "\n")
  cat(readLines(proj_file), sep = "\n")
} else {
  cat("\nNo benchmark results collected.\n")
}

cat("\n====================================================================\n")
cat("BENCHMARK COMPLETE\n")
cat("====================================================================\n")
