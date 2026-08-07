############################################################################
###
### SGPc Engine: Copula-based Student Growth Percentiles
###
### Core engine for computing conditional CDFs from fitted copulas.
### Designed for efficiency (millions of observations), flexibility
### (any copula type), and future integration into SGPc package.
###
### Author: dataimago
### Date: November 2025
###
############################################################################

require(copula)

#' SGPc Engine: Compute Copula-based Student Growth Percentiles
#'
#' Main entry point for computing SGPc values from any fitted copula.
#' Dispatches to the appropriate method based on copula type.
#'
#' @param u Numeric vector of prior pseudo-observations in (0,1)
#' @param v Numeric vector of current pseudo-observations in (0,1)
#' @param copula Fitted copula object (from copula package), empCopula object,
#'               or character string ("comonotonic")
#' @param scale Output scale: "percentile" (integer 1-99) or "probability" (0-1)
#' @param grid_cache Optional pre-computed interpolation grid for empCopula
#'                   (from create_sgpc_grid). If NULL and needed, computed on-the-fly.
#' @param grid_size Grid resolution for empirical copula interpolation (default 200)
#'
#' @return Numeric vector of SGPc values. If scale="percentile", integer 1-99.
#'         If scale="probability", numeric in (0,1).
#'
#' @details
#' Computes P(V <= v | U = u) using the appropriate method:
#' \itemize{
#'   \item Parametric copulas: copula::cCopula() [native, fast]
#'   \item Empirical copulas: Grid-based interpolation [fast after setup]
#'   \item Comonotonic: Step function - 1 if v >= u, 0 if v < u
#' }
#'
#' The comonotonic copula C(u,v) = min(u,v) represents perfect positive
#' dependence. The conditional CDF dC/du is a step function:
#' P(V <= v | U = u) = 1 if v >= u (rank maintained/improved), 0 otherwise.
#' This produces a bimodal SGPc distribution (all 1s and 99s), demonstrating
#' how real data deviates from the perfect dependence assumption.
#'
#' **Note:** An alternative interpretation where comonotonic yields uniform
#' SGPc = 50 (representing "exactly 1 year's growth") exists and may be
#' implemented in future versions via a parameter flag. The current step
#' function approach is mathematically grounded in the copula derivative
#' and operationally effective for sensitivity analysis. See
#' .sgpc_comonotonic() documentation for detailed discussion of both
#' interpretations.
#'
#' @examples
#' \dontrun{
#' # Parametric t-copula
#' tc <- tCopula(param = 0.7, df = 8)
#' u <- runif(1000)
#' v <- runif(1000)
#' sgpc <- sgpc_engine(u, v, tc, scale = "percentile")
#'
#' # Comonotonic (TAMP assumption)
#' sgpc_tamp <- sgpc_engine(u, v, "comonotonic", scale = "percentile")
#'
#' # Empirical Bernstein copula
#' emp_cop <- empCopula(cbind(u, v), smoothing = "beta")
#' sgpc_emp <- sgpc_engine(u, v, emp_cop, scale = "percentile")
#' }
#'
#' @export
sgpc_engine <- function(
  u,
  v,
  copula,
  scale = c("percentile", "probability"),
  grid_cache = NULL,
  grid_size = 200
) {
  scale <- match.arg(scale)

  # Input validation
  if (length(u) != length(v)) {
    stop("u and v must have the same length")
  }

  n <- length(u)
  if (n == 0) {
    return(if (scale == "percentile") integer(0) else numeric(0))
  }

  # Handle NA values - preserve them in output
  na_mask <- is.na(u) | is.na(v)

  # Initialize result vector
  cond_cdf <- rep(NA_real_, n)

  # Only process non-NA values
  if (any(!na_mask)) {
    u_valid <- u[!na_mask]
    v_valid <- v[!na_mask]

    # Clamp to valid range (avoid boundary issues)
    u_valid <- pmax(1e-10, pmin(1 - 1e-10, u_valid))
    v_valid <- pmax(1e-10, pmin(1 - 1e-10, v_valid))

    # Dispatch based on copula type
    cond_cdf_valid <- .dispatch_sgpc(
      u_valid,
      v_valid,
      copula,
      grid_cache,
      grid_size
    )

    # Store results
    cond_cdf[!na_mask] <- cond_cdf_valid
  }

  # Convert to output scale
  if (scale == "percentile") {
    # Convert to integer 1-99, handling edge cases
    result <- rep(NA_integer_, n)
    valid_cdf <- !is.na(cond_cdf)

    # Clamp to (0, 1) before scaling
    cond_cdf[valid_cdf] <- pmax(0.001, pmin(0.999, cond_cdf[valid_cdf]))

    # Scale to 1-99 (avoiding 0 and 100)
    result[valid_cdf] <- as.integer(round(cond_cdf[valid_cdf] * 98 + 1))

    # Ensure bounds
    result[valid_cdf] <- pmax(1L, pmin(99L, result[valid_cdf]))

    return(result)
  } else {
    return(cond_cdf)
  }
}


#' Internal dispatcher for SGPc calculation
#'
#' @keywords internal
.dispatch_sgpc <- function(u, v, copula, grid_cache, grid_size) {
  # Case 1: Comonotonic (string specification)
  if (is.character(copula)) {
    if (tolower(copula) == "comonotonic") {
      return(.sgpc_comonotonic(u, v))
    } else {
      stop("Unknown copula specification: ", copula)
    }
  }

  # Case 2: Empirical copula (empCopula class)
  if (inherits(copula, "empCopula")) {
    return(.sgpc_empirical(u, v, copula, grid_cache, grid_size))
  }

  # Case 3: Parametric copula (copula package objects)
  if (inherits(copula, "copula")) {
    return(.sgpc_parametric(u, v, copula))
  }

  # Unknown type
  stop("Unknown copula type: ", class(copula)[1])
}


#' SGPc for parametric copulas using cCopula
#'
#' @keywords internal
.sgpc_parametric <- function(u, v, copula) {
  # cCopula computes C(u_d | u_1, ..., u_{d-1})
  # For bivariate with indices=2: C(v | u) = P(V <= v | U = u)
  uv_matrix <- cbind(u, v)

  result <- tryCatch(
    {
      cond_cdf <- copula::cCopula(uv_matrix, copula = copula, indices = 2)
      as.vector(cond_cdf)
    },
    error = function(e) {
      warning("cCopula failed: ", e$message, ". Returning NA.")
      rep(NA_real_, length(u))
    }
  )

  return(result)
}


#' SGPc for Comonotonic Copula
#'
#' Computes the conditional CDF for the comonotonic copula C(u,v) = min(u,v).
#'
#' @param u Numeric vector of prior pseudo-observations in (0,1)
#' @param v Numeric vector of current pseudo-observations in (0,1)
#'
#' @return Numeric vector of conditional CDF values (0 or 1)
#'
#' @details
#' Mathematical derivation for C(u,v) = min(u,v):
#'
#' The conditional CDF is P(V <= v | U = u) = dC(u,v)/du:
#' \itemize{
#'   \item When v < u: C(u,v) = v (constant in u), so dC/du = 0
#'   \item When v >= u: C(u,v) = u, so dC/du = 1
#' }
#'
#' This is a step function: under perfect positive dependence, ranks are
#' preserved exactly (V = U almost surely). Therefore:
#' \itemize{
#'   \item If v >= u (student maintained or improved rank): SGPc = 100
#'   \item If v < u (student fell in rank): SGPc = 1
#' }
#'
#' For real data that doesn't follow perfect comonotonicity, this produces
#' a bimodal distribution (all values at 1 or 99), clearly showing the
#' failure of the perfect dependence assumption.
#'
#' **Note on Alternative Interpretation:**
#' An alternative interpretation of the comonotonic copula exists where
#' every student is assigned SGPc = 50 (representing "exactly 1 year's growth"
#' under perfect rank preservation). This interprets the indeterminacy at
#' v = u differently - using a "median" value rather than the derivative-based
#' step function. Both interpretations have theoretical merit:
#' \itemize{
#'   \item **Step function (current)**: Based on dC/du, produces bimodal
#'         distribution, emphasizes rank changes, effective for demonstrating
#'         TAMP assumption's extremity in sensitivity analyses
#'   \item **Constant 50**: Based on "typical growth" interpretation,
#'         produces uniform distribution, useful for growth regime inference
#'         where comonotonicity represents normative expectations
#' }
#' The current implementation uses the step function approach as it is
#' mathematically grounded in the copula derivative and operationally
#' demonstrates the practical limitations of assuming perfect dependence
#' in real assessment data. Future work may implement both interpretations
#' with a parameter flag for context-specific applications.
#'
#' @keywords internal
.sgpc_comonotonic <- function(u, v) {
  # Conditional CDF for comonotonic copula: P(V <= v | U = u) = I(v >= u)
  # This is 1 if rank maintained/improved, 0 if rank fell
  as.numeric(v >= u)
}


#' SGPc for empirical copulas using grid interpolation
#'
#' @keywords internal
.sgpc_empirical <- function(u, v, emp_copula, grid_cache, grid_size) {
  # Use provided cache or create new one
  if (is.null(grid_cache)) {
    grid_cache <- create_sgpc_grid(emp_copula, grid_size = grid_size)
  }

  # Interpolate
  result <- sgpc_interpolate(u, v, grid_cache)

  return(result)
}


#' Create Interpolation Grid for Empirical Copula
#'
#' Pre-computes the conditional CDF C(v|u) on a grid for fast interpolation.
#' One-time cost (~2 seconds) enables subsequent lookups in milliseconds.
#'
#' @param emp_copula An empCopula object (Bernstein-smoothed or raw)
#' @param grid_size Grid resolution (default 200). Higher = more accurate but slower setup.
#' @param boundary_buffer Small buffer from 0 and 1 to avoid boundary issues (default 0.005)
#'
#' @return List with components:
#' \itemize{
#'   \item u_grid: Vector of u grid points
#'   \item v_grid: Vector of v grid points
#'   \item du: Grid spacing
#'   \item conditional_matrix: Matrix of C(v|u) values [u_index, v_index]
#' }
#'
#' @details
#' Algorithm:
#' 1. Evaluate C(u,v) on a regular grid using pCopula()
#' 2. Compute ∂C/∂u via central finite differences
#' 3. Store for fast bilinear interpolation
#'
#' @export
create_sgpc_grid <- function(
  emp_copula,
  grid_size = 200,
  boundary_buffer = 0.005
) {
  if (!inherits(emp_copula, "empCopula")) {
    stop("emp_copula must be an empCopula object")
  }

  # Create grid (avoid exact 0 and 1)
  u_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = grid_size)
  v_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = grid_size)
  du <- u_grid[2] - u_grid[1]

  # Evaluate copula CDF on full grid
  uv_grid <- expand.grid(u = u_grid, v = v_grid)

  C_values <- tryCatch(
    {
      copula::pCopula(as.matrix(uv_grid), emp_copula)
    },
    error = function(e) {
      stop("Failed to evaluate pCopula on grid: ", e$message)
    }
  )

  # Reshape to matrix: C_matrix[i, j] = C(u_grid[i], v_grid[j])
  C_matrix <- matrix(
    C_values,
    nrow = grid_size,
    ncol = grid_size,
    byrow = FALSE
  )

  # Compute conditional CDF via central finite differences: ∂C/∂u
  conditional_matrix <- matrix(NA_real_, nrow = grid_size, ncol = grid_size)

  # Interior points: central difference
  for (j in 1:grid_size) {
    for (i in 2:(grid_size - 1)) {
      conditional_matrix[i, j] <- (C_matrix[i + 1, j] - C_matrix[i - 1, j]) /
        (2 * du)
    }
    # Boundary points: one-sided differences
    conditional_matrix[1, j] <- (C_matrix[2, j] - C_matrix[1, j]) / du
    conditional_matrix[grid_size, j] <- (C_matrix[grid_size, j] -
      C_matrix[grid_size - 1, j]) /
      du
  }

  # Clamp to [0, 1] while preserving matrix structure
  conditional_matrix[conditional_matrix < 0] <- 0
  conditional_matrix[conditional_matrix > 1] <- 1

  return(list(
    u_grid = u_grid,
    v_grid = v_grid,
    du = du,
    grid_size = grid_size,
    conditional_matrix = conditional_matrix
  ))
}


#' Fast Bilinear Interpolation for SGPc
#'
#' Given query points (u, v), interpolates the conditional CDF C(v|u)
#' from a pre-computed grid.
#'
#' @param u Numeric vector of query u values in (0, 1)
#' @param v Numeric vector of query v values in (0, 1)
#' @param grid_cache Output from create_sgpc_grid()
#'
#' @return Numeric vector of interpolated C(v|u) values
#'
#' @details
#' Uses bilinear interpolation for smooth results. Points outside the
#' grid boundaries are clamped to the nearest grid edge.
#'
#' @export
sgpc_interpolate <- function(u, v, grid_cache) {
  if (
    is.null(grid_cache) ||
      !all(c("u_grid", "v_grid", "conditional_matrix") %in% names(grid_cache))
  ) {
    stop("Invalid grid_cache. Use create_sgpc_grid() to create one.")
  }

  u_grid <- grid_cache$u_grid
  v_grid <- grid_cache$v_grid
  du <- grid_cache$du
  grid_size <- grid_cache$grid_size
  cond_mat <- grid_cache$conditional_matrix

  n <- length(u)
  result <- numeric(n)

  # Find grid cell indices
  u_idx <- findInterval(u, u_grid)
  v_idx <- findInterval(v, v_grid)

  # Clamp to valid range [1, grid_size-1] for interpolation
  u_idx <- pmax(1L, pmin(grid_size - 1L, u_idx))
  v_idx <- pmax(1L, pmin(grid_size - 1L, v_idx))

  # Interpolation weights
  u_frac <- (u - u_grid[u_idx]) / du
  v_frac <- (v - v_grid[v_idx]) / du

  # Clamp fractions to [0, 1]
  u_frac <- pmax(0, pmin(1, u_frac))
  v_frac <- pmax(0, pmin(1, v_frac))

  # Bilinear interpolation
  # f(u,v) ≈ (1-s)(1-t)f(i,j) + s(1-t)f(i+1,j) + (1-s)t*f(i,j+1) + st*f(i+1,j+1)
  result <- (1 - u_frac) *
    (1 - v_frac) *
    cond_mat[cbind(u_idx, v_idx)] +
    u_frac * (1 - v_frac) * cond_mat[cbind(u_idx + 1L, v_idx)] +
    (1 - u_frac) * v_frac * cond_mat[cbind(u_idx, v_idx + 1L)] +
    u_frac * v_frac * cond_mat[cbind(u_idx + 1L, v_idx + 1L)]

  # Clamp to [0, 1]
  result <- pmax(0, pmin(1, result))

  return(result)
}


#' Batch SGPc Calculation for Multiple Copula Families
#'
#' Efficiently computes SGPc for all fitted copula families in one pass.
#'
#' @param u Numeric vector of prior pseudo-observations
#' @param v Numeric vector of current pseudo-observations
#' @param copula_results List of fitted copula results (from fit_copula_from_pairs)
#' @param empirical_copulas Optional list of empCopula objects (bernstein, raw)
#' @param scale Output scale: "percentile" or "probability"
#' @param include_comonotonic Logical, whether to include comonotonic SGPc
#'
#' @return data.table with columns for each copula family's SGPc
#'
#' @export
sgpc_batch <- function(
  u,
  v,
  copula_results,
  empirical_copulas = NULL,
  scale = "percentile",
  include_comonotonic = TRUE
) {
  require(data.table)

  n <- length(u)
  result <- data.table(
    row_id = 1:n
  )

  # Parametric copulas
  parametric_families <- c("gaussian", "t", "clayton", "gumbel", "frank")

  for (family in parametric_families) {
    col_name <- paste0("SGPc_", family)

    if (
      !is.null(copula_results[[family]]) &&
        !is.null(copula_results[[family]]$copula)
    ) {
      result[[col_name]] <- tryCatch(
        {
          sgpc_engine(u, v, copula_results[[family]]$copula, scale = scale)
        },
        error = function(e) {
          warning("SGPc calculation failed for ", family, ": ", e$message)
          rep(NA_integer_, n)
        }
      )
    } else {
      result[[col_name]] <- NA_integer_
    }
  }

  # Comonotonic
  if (include_comonotonic) {
    result[["SGPc_comonotonic"]] <- sgpc_engine(
      u,
      v,
      "comonotonic",
      scale = scale
    )
  }

  # Empirical copulas
  if (!is.null(empirical_copulas)) {
    # Bernstein-smoothed
    if (!is.null(empirical_copulas$bernstein)) {
      result[["SGPc_bernstein"]] <- tryCatch(
        {
          sgpc_engine(u, v, empirical_copulas$bernstein, scale = scale)
        },
        error = function(e) {
          warning("SGPc calculation failed for Bernstein: ", e$message)
          rep(NA_integer_, n)
        }
      )
    }

    # Raw empirical (if we want to include it)
    if (!is.null(empirical_copulas$raw)) {
      result[["SGPc_raw"]] <- tryCatch(
        {
          sgpc_engine(u, v, empirical_copulas$raw, scale = scale)
        },
        error = function(e) {
          warning("SGPc calculation failed for raw empirical: ", e$message)
          rep(NA_integer_, n)
        }
      )
    }
  }

  # Remove row_id helper column
  result[, row_id := NULL]

  return(result)
}


############################################################################
### Utility Functions
############################################################################

#' Validate Pseudo-Observations
#'
#' Check that pseudo-observations are valid (in (0,1) interval)
#'
#' @param u Numeric vector
#' @param v Numeric vector
#' @param strict If TRUE, values must be strictly in (0,1). If FALSE, [0,1] allowed.
#'
#' @return Logical, TRUE if valid
#'
#' @export
validate_pseudo_obs <- function(u, v, strict = TRUE) {
  if (length(u) != length(v)) {
    warning("u and v have different lengths")
    return(FALSE)
  }

  # Check for non-NA values
  u_valid <- u[!is.na(u)]
  v_valid <- v[!is.na(v)]

  if (strict) {
    u_ok <- all(u_valid > 0 & u_valid < 1)
    v_ok <- all(v_valid > 0 & v_valid < 1)
  } else {
    u_ok <- all(u_valid >= 0 & u_valid <= 1)
    v_ok <- all(v_valid >= 0 & v_valid <= 1)
  }

  if (!u_ok) {
    warning("u contains values outside (0,1)")
    return(FALSE)
  }

  if (!v_ok) {
    warning("v contains values outside (0,1)")
    return(FALSE)
  }

  return(TRUE)
}


#' Summary Statistics for SGPc Results
#'
#' @param sgpc_results data.table from sgpc_batch() or similar
#' @param traditional_sgp Optional vector of traditional SGP values for comparison
#'
#' @return data.table with summary statistics
#'
#' @export
sgpc_summary <- function(sgpc_results, traditional_sgp = NULL) {
  require(data.table)

  sgpc_cols <- names(sgpc_results)[grepl("^SGPc_", names(sgpc_results))]

  summary_list <- lapply(sgpc_cols, function(col) {
    vals <- sgpc_results[[col]]
    valid_vals <- vals[!is.na(vals)]

    data.table(
      family = gsub("^SGPc_", "", col),
      n_valid = length(valid_vals),
      n_missing = sum(is.na(vals)),
      mean = mean(valid_vals),
      sd = sd(valid_vals),
      min = min(valid_vals),
      q25 = quantile(valid_vals, 0.25),
      median = median(valid_vals),
      q75 = quantile(valid_vals, 0.75),
      max = max(valid_vals)
    )
  })

  summary_dt <- rbindlist(summary_list)

  # Add correlation with traditional SGP if provided
  if (!is.null(traditional_sgp)) {
    correlations <- sapply(sgpc_cols, function(col) {
      valid_idx <- !is.na(sgpc_results[[col]]) & !is.na(traditional_sgp)
      if (sum(valid_idx) > 10) {
        cor(sgpc_results[[col]][valid_idx], traditional_sgp[valid_idx])
      } else {
        NA_real_
      }
    })
    summary_dt[, cor_with_SGP := correlations]
  }

  return(summary_dt)
}
