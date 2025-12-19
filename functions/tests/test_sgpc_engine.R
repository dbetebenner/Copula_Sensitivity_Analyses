############################################################################
###
### Unit Tests for SGPc Engine
###
### Validates SGPc calculations against known copula properties and
### ensures numerical accuracy across different copula types.
###
############################################################################

# Setup
require(copula)
require(data.table)

# Source the engine
source("../sgpc_engine.R")

cat("============================================================\n")
cat("SGPc Engine Unit Tests\n")
cat("============================================================\n\n")

test_results <- list()
test_count <- 0
pass_count <- 0

run_test <- function(name, expr) {
  test_count <<- test_count + 1
  cat(sprintf("Test %d: %s ... ", test_count, name))
  
  result <- tryCatch({
    eval(expr)
    TRUE
  }, error = function(e) {
    cat("FAILED\n")
    cat("  Error: ", e$message, "\n")
    FALSE
  })
  
  if (isTRUE(result)) {
    cat("PASSED\n")
    pass_count <<- pass_count + 1
  }
  
  test_results[[name]] <<- result
  invisible(result)
}

assert_equal <- function(a, b, tol = 1e-6, msg = "") {
  if (!isTRUE(all.equal(a, b, tolerance = tol))) {
    stop(sprintf("Assertion failed: %s\n  Expected: %s\n  Got: %s", 
                 msg, paste(head(b, 5), collapse=", "), paste(head(a, 5), collapse=", ")))
  }
}

assert_true <- function(x, msg = "") {
  if (!isTRUE(x)) {
    stop(sprintf("Assertion failed: %s expected TRUE", msg))
  }
}

assert_in_range <- function(x, lower, upper, msg = "") {
  x_valid <- x[!is.na(x)]
  if (length(x_valid) > 0 && (any(x_valid < lower) || any(x_valid > upper))) {
    stop(sprintf("Assertion failed: %s values outside [%g, %g]", msg, lower, upper))
  }
}


############################################################################
### Test 1: Basic functionality with parametric t-copula
############################################################################

run_test("Parametric t-copula basic", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  
  u <- c(0.3, 0.5, 0.7)
  v <- c(0.4, 0.6, 0.8)
  
  # Test probability scale
  sgpc_prob <- sgpc_engine(u, v, tc, scale = "probability")
  assert_in_range(sgpc_prob, 0, 1, "t-copula probability")
  assert_equal(length(sgpc_prob), 3, msg = "t-copula length")
  
  # Test percentile scale
  sgpc_pct <- sgpc_engine(u, v, tc, scale = "percentile")
  assert_in_range(sgpc_pct, 1, 99, "t-copula percentile")
  
  # Verify cCopula alignment
  expected <- as.vector(cCopula(cbind(u, v), copula = tc, indices = 2))
  assert_equal(sgpc_prob, expected, tol = 1e-6, msg = "cCopula alignment")
})


############################################################################
### Test 2: Gaussian copula
############################################################################

run_test("Parametric Gaussian copula", {
  set.seed(42)
  gc <- normalCopula(param = 0.6)
  
  u <- runif(100)
  v <- runif(100)
  
  sgpc_prob <- sgpc_engine(u, v, gc, scale = "probability")
  expected <- as.vector(cCopula(cbind(u, v), copula = gc, indices = 2))
  
  assert_equal(sgpc_prob, expected, tol = 1e-6, msg = "Gaussian cCopula alignment")
})


############################################################################
### Test 3: Clayton copula
############################################################################

run_test("Parametric Clayton copula", {
  set.seed(42)
  cc <- claytonCopula(param = 2)
  
  u <- runif(100)
  v <- runif(100)
  
  sgpc_prob <- sgpc_engine(u, v, cc, scale = "probability")
  expected <- as.vector(cCopula(cbind(u, v), copula = cc, indices = 2))
  
  assert_equal(sgpc_prob, expected, tol = 1e-6, msg = "Clayton cCopula alignment")
})


############################################################################
### Test 4: Gumbel copula
############################################################################

run_test("Parametric Gumbel copula", {
  set.seed(42)
  gc <- gumbelCopula(param = 2)
  
  u <- runif(100)
  v <- runif(100)
  
  sgpc_prob <- sgpc_engine(u, v, gc, scale = "probability")
  expected <- as.vector(cCopula(cbind(u, v), copula = gc, indices = 2))
  
  assert_equal(sgpc_prob, expected, tol = 1e-6, msg = "Gumbel cCopula alignment")
})


############################################################################
### Test 5: Frank copula
############################################################################

run_test("Parametric Frank copula", {
  set.seed(42)
  fc <- frankCopula(param = 5)
  
  u <- runif(100)
  v <- runif(100)
  
  sgpc_prob <- sgpc_engine(u, v, fc, scale = "probability")
  expected <- as.vector(cCopula(cbind(u, v), copula = fc, indices = 2))
  
  assert_equal(sgpc_prob, expected, tol = 1e-6, msg = "Frank cCopula alignment")
})


############################################################################
### Test 6: Comonotonic copula (TAMP assumption)
############################################################################

run_test("Comonotonic copula", {
  u <- c(0.2, 0.4, 0.6, 0.8)
  v <- c(0.3, 0.5, 0.7, 0.9)
  
  sgpc_prob <- sgpc_engine(u, v, "comonotonic", scale = "probability")
  
  # Comonotonic: SGPc = u (prior percentile persists)
  assert_equal(sgpc_prob, u, tol = 1e-10, msg = "Comonotonic = prior percentile")
  
  # Percentile scale
  sgpc_pct <- sgpc_engine(u, v, "comonotonic", scale = "percentile")
  expected_pct <- as.integer(round(u * 98 + 1))
  assert_equal(sgpc_pct, expected_pct, msg = "Comonotonic percentile scale")
})


############################################################################
### Test 7: NA handling
############################################################################

run_test("NA handling", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  
  u <- c(0.3, NA, 0.7, 0.5)
  v <- c(0.4, 0.6, NA, 0.8)
  
  sgpc <- sgpc_engine(u, v, tc, scale = "probability")
  
  assert_true(!is.na(sgpc[1]), "First value not NA")
  assert_true(is.na(sgpc[2]), "Second value is NA (u was NA)")
  assert_true(is.na(sgpc[3]), "Third value is NA (v was NA)")
  assert_true(!is.na(sgpc[4]), "Fourth value not NA")
})


############################################################################
### Test 8: Empty input handling
############################################################################

run_test("Empty input", {
  tc <- tCopula(param = 0.7, df = 8)
  
  sgpc_prob <- sgpc_engine(numeric(0), numeric(0), tc, scale = "probability")
  sgpc_pct <- sgpc_engine(numeric(0), numeric(0), tc, scale = "percentile")
  
  assert_equal(length(sgpc_prob), 0, msg = "Empty probability output")
  assert_equal(length(sgpc_pct), 0, msg = "Empty percentile output")
})


############################################################################
### Test 9: Empirical copula grid creation
############################################################################

run_test("Empirical copula grid creation", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  U_emp <- rCopula(1000, tc)
  
  emp_bernstein <- empCopula(U_emp, smoothing = "beta")
  
  # Create grid
  grid <- create_sgpc_grid(emp_bernstein, grid_size = 50)
  
  assert_true("u_grid" %in% names(grid), "Grid has u_grid")
  assert_true("v_grid" %in% names(grid), "Grid has v_grid")
  assert_true("conditional_matrix" %in% names(grid), "Grid has conditional_matrix")
  assert_equal(length(grid$u_grid), 50, msg = "Grid size u")
  assert_equal(length(grid$v_grid), 50, msg = "Grid size v")
  assert_true(is.matrix(grid$conditional_matrix), "Is matrix")
  assert_equal(nrow(grid$conditional_matrix), 50, msg = "Matrix rows")
  assert_equal(ncol(grid$conditional_matrix), 50, msg = "Matrix cols")
  
  # Conditional CDF should be in [0, 1]
  assert_in_range(grid$conditional_matrix, 0, 1, "Conditional matrix range")
})


############################################################################
### Test 10: Empirical copula SGPc via interpolation
############################################################################

run_test("Empirical copula SGPc", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  U_emp <- rCopula(5000, tc)
  
  emp_bernstein <- empCopula(U_emp, smoothing = "beta")
  
  # Test points
  u_test <- c(0.3, 0.5, 0.7)
  v_test <- c(0.4, 0.6, 0.8)
  
  # SGPc from empirical copula
  sgpc_emp <- sgpc_engine(u_test, v_test, emp_bernstein, scale = "probability", grid_size = 100)
  
  # Should be in [0, 1]
  assert_in_range(sgpc_emp, 0, 1, "Empirical SGPc range")
  
  # Should be reasonably close to parametric (within sampling error)
  sgpc_param <- sgpc_engine(u_test, v_test, tc, scale = "probability")
  
  # Allow 0.15 tolerance for sampling variability
  diffs <- abs(sgpc_emp - sgpc_param)
  assert_true(all(diffs < 0.15), "Empirical close to parametric")
})


############################################################################
### Test 11: Grid interpolation accuracy
############################################################################

run_test("Grid interpolation accuracy", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  U_emp <- rCopula(10000, tc)
  
  emp_bernstein <- empCopula(U_emp, smoothing = "beta")
  
  # Create high-resolution grid
  grid_cache <- create_sgpc_grid(emp_bernstein, grid_size = 200)
  
  # Test at grid points (should be exact within tolerance)
  # Use indices that are well within the grid
  test_indices <- c(10, 50, 100, 150)
  u_grid_test <- grid_cache$u_grid[test_indices]
  v_grid_test <- grid_cache$v_grid[test_indices]
  
  sgpc_interp <- sgpc_interpolate(u_grid_test, v_grid_test, grid_cache)
  
  # Get expected values from the diagonal of the conditional matrix at these indices
  expected <- sapply(seq_along(test_indices), function(k) {
    grid_cache$conditional_matrix[test_indices[k], test_indices[k]]
  })
  
  # Values should match grid closely at grid points (small interpolation error)
  max_diff <- max(abs(sgpc_interp - expected))
  assert_true(max_diff < 0.01, sprintf("Close at grid points (max diff: %.4f)", max_diff))
})


############################################################################
### Test 12: Batch SGPc calculation
############################################################################

run_test("Batch SGPc calculation", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  gc <- normalCopula(param = 0.6)
  cc <- claytonCopula(param = 2)
  
  copula_results <- list(
    t = list(copula = tc),
    gaussian = list(copula = gc),
    clayton = list(copula = cc)
  )
  
  u <- runif(100)
  v <- runif(100)
  
  result <- sgpc_batch(u, v, copula_results, include_comonotonic = TRUE)
  
  assert_true(is.data.table(result), "Result is data.table")
  assert_true("SGPc_t" %in% names(result), "Has SGPc_t")
  assert_true("SGPc_gaussian" %in% names(result), "Has SGPc_gaussian")
  assert_true("SGPc_clayton" %in% names(result), "Has SGPc_clayton")
  assert_true("SGPc_comonotonic" %in% names(result), "Has SGPc_comonotonic")
  assert_equal(nrow(result), 100, msg = "Correct number of rows")
})


############################################################################
### Test 13: Percentile scale bounds
############################################################################

run_test("Percentile scale bounds (1-99)", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  
  # Generate many observations to test extreme values
  n <- 10000
  U <- rCopula(n, tc)
  
  sgpc_pct <- sgpc_engine(U[,1], U[,2], tc, scale = "percentile")
  
  assert_true(all(sgpc_pct >= 1, na.rm = TRUE), "All >= 1")
  assert_true(all(sgpc_pct <= 99, na.rm = TRUE), "All <= 99")
  assert_true(is.integer(sgpc_pct), "Is integer")
})


############################################################################
### Test 14: Validate pseudo-observations utility
############################################################################

run_test("Validate pseudo-observations", {
  # Valid
  assert_true(validate_pseudo_obs(c(0.3, 0.5, 0.7), c(0.4, 0.6, 0.8)), "Valid obs")
  
  # Invalid - different lengths (should warn and return FALSE)
  suppressWarnings({
    assert_true(!validate_pseudo_obs(c(0.3, 0.5), c(0.4, 0.6, 0.8)), "Different lengths")
  })
  
  # Invalid - out of range
  suppressWarnings({
    assert_true(!validate_pseudo_obs(c(0.3, 1.5, 0.7), c(0.4, 0.6, 0.8)), "Out of range")
  })
  
  # NA handling
  assert_true(validate_pseudo_obs(c(0.3, NA, 0.7), c(0.4, 0.6, NA)), "With NAs")
})


############################################################################
### Test 15: Performance benchmark
############################################################################

run_test("Performance benchmark (100k obs)", {
  set.seed(42)
  tc <- tCopula(param = 0.7, df = 8)
  
  n <- 100000
  u <- runif(n)
  v <- runif(n)
  
  # Parametric should be fast
  t_param <- system.time({
    sgpc_param <- sgpc_engine(u, v, tc, scale = "percentile")
  })["elapsed"]
  
  assert_true(t_param < 5, sprintf("Parametric < 5 seconds (got %.2f)", t_param))
  
  # Comonotonic should be very fast
  t_como <- system.time({
    sgpc_como <- sgpc_engine(u, v, "comonotonic", scale = "percentile")
  })["elapsed"]
  
  assert_true(t_como < 1, sprintf("Comonotonic < 1 second (got %.2f)", t_como))
  
  cat(sprintf("\n    Parametric: %.3fs, Comonotonic: %.3fs for %d obs\n", t_param, t_como, n))
})


############################################################################
### Test 16: SGPc summary function
############################################################################

run_test("SGPc summary function", {
  set.seed(42)
  
  # Create mock results
  n <- 1000
  sgpc_results <- data.table(
    SGPc_t = sample(1:99, n, replace = TRUE),
    SGPc_gaussian = sample(1:99, n, replace = TRUE),
    SGPc_comonotonic = sample(1:99, n, replace = TRUE)
  )
  
  # Add some NAs
  sgpc_results[sample(1:n, 50), SGPc_t := NA]
  
  # Without traditional SGP
  summary1 <- sgpc_summary(sgpc_results)
  assert_true(is.data.table(summary1), "Summary is data.table")
  assert_equal(nrow(summary1), 3, msg = "Three families")
  assert_true("mean" %in% names(summary1), "Has mean")
  assert_true("n_missing" %in% names(summary1), "Has n_missing")
  
  # With traditional SGP
  trad_sgp <- sample(1:99, n, replace = TRUE)
  summary2 <- sgpc_summary(sgpc_results, traditional_sgp = trad_sgp)
  assert_true("cor_with_SGP" %in% names(summary2), "Has correlation")
})


############################################################################
### Results Summary
############################################################################

cat("\n============================================================\n")
cat("Test Results Summary\n")
cat("============================================================\n")
cat(sprintf("Passed: %d / %d tests\n", pass_count, test_count))

if (pass_count == test_count) {
  cat("\n✓ All tests passed!\n")
} else {
  cat("\n✗ Some tests failed:\n")
  failed <- names(test_results)[!unlist(test_results)]
  for (f in failed) {
    cat(sprintf("  - %s\n", f))
  }
}

cat("\n")

