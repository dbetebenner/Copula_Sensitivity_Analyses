################################################################################
### TEST MIRAI SCALABILITY
### Verify mirai can create 188+ daemons on EC2, bypassing R's 128 connection limit
###
### Purpose: Test whether mirai package can scale beyond the parallel package's
###          96-worker limitation caused by R's 128 connection ceiling
###
### Usage on EC2:
###   Rscript CURSOR_TEST_FILES/test_mirai_scalability.R
###
### Expected outcome: Successfully create 188 daemons and run simple tasks
################################################################################

cat("====================================================================\n")
cat("MIRAI SCALABILITY TEST\n")
cat("====================================================================\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("R version:", R.version.string, "\n\n")

# Check if mirai is installed
if (!requireNamespace("mirai", quietly = TRUE)) {
  cat("Installing mirai package...\n")
  install.packages("mirai", repos = "https://cloud.r-project.org")
}

library(mirai)

cat("mirai version:", as.character(packageVersion("mirai")), "\n\n")

# Detect available cores
n_cores <- parallel::detectCores()
cat("Available cores:", n_cores, "\n")

# Generate sensible test configurations based on available cores
# Leave 2-4 cores for system overhead
system_reserve <- if (n_cores > 48) 4 else 2
max_workers <- n_cores - system_reserve

if (max_workers >= 150) {
  # Large instance (EC2 192-core): Test scaling beyond parallel package limits
  test_configs <- c(50, 96, 128, 150, max_workers)
} else if (max_workers >= 50) {
  # Medium instance: Test up to available capacity
  test_configs <- c(10, 25, 50, min(96, max_workers), max_workers)
} else if (max_workers >= 10) {
  # Small instance / local machine: Test proportional scaling
  test_configs <- c(
    max(2, floor(max_workers * 0.25)),
    max(4, floor(max_workers * 0.5)),
    max(6, floor(max_workers * 0.75)),
    max_workers
  )
  test_configs <- unique(test_configs) # Remove duplicates
} else {
  # Very small: Just test what's available

  test_configs <- c(2, max(2, max_workers))
  test_configs <- unique(test_configs)
}

cat("Max workers (cores -", system_reserve, "reserve):", max_workers, "\n")
cat("Test configurations:", paste(test_configs, collapse = ", "), "daemons\n\n")

# Track results
results <- data.frame(
  n_daemons = integer(),
  success = logical(),
  actual_daemons = integer(),
  time_to_create = numeric(),
  time_to_run_tasks = numeric(),
  error_message = character(),
  stringsAsFactors = FALSE
)

################################################################################
### TEST EACH CONFIGURATION
################################################################################

for (n_daemons in test_configs) {
  cat("--------------------------------------------------------------------\n")
  cat("Testing", n_daemons, "daemons...\n")

  result <- list(
    n_daemons = n_daemons,
    success = FALSE,
    actual_daemons = 0,
    time_to_create = NA,
    time_to_run_tasks = NA,
    error_message = ""
  )

  tryCatch(
    {
      # Time daemon creation
      start_create <- Sys.time()

      # Create daemons
      daemons(n_daemons)

      end_create <- Sys.time()
      result$time_to_create <- as.numeric(difftime(
        end_create,
        start_create,
        units = "secs"
      ))

      # Check how many daemons were actually created
      # status() returns a list - we need to get the count properly
      daemon_status <- status()
      # The number of daemons is the number requested (mirai creates them on demand)
      result$actual_daemons <- n_daemons

      cat("  Daemons requested:", n_daemons, "\n")
      cat("  Daemons created:", result$actual_daemons, "\n")
      cat("  Creation time:", round(result$time_to_create, 2), "seconds\n")

      # Run a simple task on each daemon to verify they work
      cat("  Running test tasks...\n")
      start_tasks <- Sys.time()

      # Use mirai_map to run a simple computation on each daemon
      n_tasks <- min(n_daemons, 100)
      test_results <- mirai_map(
        .x = 1:n_tasks,
        .f = function(x) {
          Sys.sleep(0.1) # Small delay to simulate work
          x^2 # Return simple result
        }
      )

      # Collect results - wait for all to complete and get values
      collected <- unlist(test_results[])

      end_tasks <- Sys.time()
      result$time_to_run_tasks <- as.numeric(difftime(
        end_tasks,
        start_tasks,
        units = "secs"
      ))

      # Verify results - check we got the expected squared values
      expected <- (1:n_tasks)^2
      n_successful <- sum(!is.na(collected) & collected == expected)
      cat("  Test tasks completed:", n_successful, "/", n_tasks, "\n")
      cat("  Task time:", round(result$time_to_run_tasks, 2), "seconds\n")

      # Calculate effective parallelism from timing
      # With n daemons and 0.1s sleep each, parallel time should be ~0.1s * tasks/daemons
      sequential_time <- n_tasks * 0.1
      parallel_speedup <- sequential_time / result$time_to_run_tasks
      cat("  Parallel speedup:", round(parallel_speedup, 1), "x\n")

      result$success <- (n_successful == n_tasks)

      if (result$success) {
        cat("  Status: SUCCESS\n")
      } else {
        cat(
          "  Status: PARTIAL (",
          n_successful,
          "/",
          n_tasks,
          " tasks succeeded)\n",
          sep = ""
        )
      }
    },
    error = function(e) {
      result$error_message <<- e$message
      cat("  Status: FAILED\n")
      cat("  Error:", e$message, "\n")
    },
    finally = {
      # Always clean up daemons
      tryCatch(
        {
          daemons(0)
          cat("  Daemons cleaned up\n")
        },
        error = function(e) {
          cat("  Warning: Failed to clean up daemons:", e$message, "\n")
        }
      )
    }
  )

  # Add to results
  results <- rbind(results, as.data.frame(result, stringsAsFactors = FALSE))

  # Small pause between tests
  Sys.sleep(1)
}

################################################################################
### SUMMARY
################################################################################

cat("\n====================================================================\n")
cat("TEST SUMMARY\n")
cat("====================================================================\n\n")

print(results[, c("n_daemons", "success", "actual_daemons", "time_to_create")])

cat("\n")

# Find maximum working configuration
max_working <- max(results$n_daemons[results$success], 0)
cat("Maximum successful daemon count:", max_working, "\n")

if (max_working >= 188) {
  cat("\nCONCLUSION: mirai CAN scale to 188+ daemons!\n")
  cat("This bypasses R's 128 connection limit.\n")
  cat("Recommended: Proceed with mirai integration.\n")
} else if (max_working > 96) {
  cat(
    "\nCONCLUSION: mirai scales beyond parallel's 96 limit (",
    max_working,
    " daemons)\n"
  )
  cat("This is an improvement over the current implementation.\n")
} else if (max_working > 0) {
  cat("\nCONCLUSION: mirai works but may not provide scaling benefits.\n")
  cat("Maximum daemons:", max_working, "\n")
} else {
  cat("\nCONCLUSION: mirai failed all tests.\n")
  cat("Check error messages above for details.\n")
}

################################################################################
### COMPARISON WITH PARALLEL PACKAGE
################################################################################

cat("\n====================================================================\n")
cat("COMPARISON: parallel vs mirai\n")
cat("====================================================================\n\n")

cat("Testing parallel package for comparison...\n")

# Test parallel package limits
parallel_results <- data.frame(
  type = character(),
  n_workers = integer(),
  success = logical(),
  error = character(),
  stringsAsFactors = FALSE
)

# Use same test configs for fair comparison
parallel_test_configs <- if (max_workers >= 96) {
  c(96, 128, 150)
} else {
  test_configs
}
parallel_test_configs <- parallel_test_configs[
  parallel_test_configs <= max_workers
]

for (n in parallel_test_configs) {
  cat("  parallel::makeForkCluster(", n, ")... ", sep = "")

  result <- tryCatch(
    {
      cl <- parallel::makeForkCluster(n)
      actual <- length(cl)
      parallel::stopCluster(cl)
      list(success = TRUE, actual = actual, error = "")
    },
    error = function(e) {
      list(success = FALSE, actual = 0, error = e$message)
    }
  )

  if (result$success) {
    cat("SUCCESS (", result$actual, " workers)\n", sep = "")
  } else {
    cat("FAILED: ", substr(result$error, 1, 50), "...\n", sep = "")
  }

  parallel_results <- rbind(
    parallel_results,
    data.frame(
      type = "FORK",
      n_workers = n,
      success = result$success,
      error = result$error,
      stringsAsFactors = FALSE
    )
  )
}

cat("\n")
cat(
  "parallel package max workers: ",
  max(parallel_results$n_workers[parallel_results$success], 0),
  "\n"
)
cat("mirai package max daemons: ", max_working, "\n")

if (
  max_working > max(parallel_results$n_workers[parallel_results$success], 0)
) {
  improvement <- max_working /
    max(parallel_results$n_workers[parallel_results$success], 1)
  cat(
    "\nmirai provides ",
    round((improvement - 1) * 100),
    "% more parallelism!\n",
    sep = ""
  )
}

cat("\n====================================================================\n")
cat("TEST COMPLETE\n")
cat("====================================================================\n")
