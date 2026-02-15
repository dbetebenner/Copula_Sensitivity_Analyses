############################################################################
###
### Copula Kernel Cache for STEP 3: Growth Regime Inference
###
### Precomputes the baseline transition kernel F_0(v|u) = dC(u,v)/du
### on a grid for fast repeated evaluation. Also provides the inverse
### (quantile kernel) Q_0(p|u) = F_0^{-1}(p|u).
###
### Leverages create_sgpc_grid() and sgpc_interpolate() from the shared
### sgpc_engine.R where possible, but extends with:
###   - Quantile kernel (inverse of conditional CDF)
###   - Parametric copula support via cCopula()
###   - Metadata for traceability
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIw_LD)
###
############################################################################

require(copula)


#' Create a Transition Kernel Cache
#'
#' Precomputes F_0(v|u) = P(V <= v | U = u) on a regular grid for a
#' given copula. Also computes the quantile kernel Q_0(p|u).
#'
#' @param copula_obj A fitted copula object (from the copula package)
#' @param u_grid_size Integer. Number of grid points along u axis. Default 201.
#' @param v_grid_size Integer. Number of grid points along v axis. Default 201.
#' @param boundary_buffer Numeric. Buffer from 0 and 1. Default 0.005.
#' @param compute_quantile Logical. Also precompute Q_0(p|u)? Default TRUE.
#'
#' @return List with class "kernel_cache":
#'   \itemize{
#'     \item u_grid: Numeric vector of u grid points
#'     \item v_grid: Numeric vector of v grid points
#'     \item conditional_cdf: Matrix [u_idx, v_idx] of F_0(v|u) values
#'     \item quantile_grid: Matrix [u_idx, p_idx] of Q_0(p|u) values (if requested)
#'     \item p_grid: Numeric vector of probability grid points (for quantile)
#'     \item copula_family: Character string identifying the copula
#'     \item copula_params: Named list of copula parameters
#'     \item created_at: Timestamp
#'   }
#'
#' @details
#' For parametric copulas, uses copula::cCopula() which computes the exact
#' conditional CDF analytically. This is more precise than the finite-difference
#' approach used for empirical copulas in sgpc_engine.R.
#'
#' @examples
#' \dontrun{
#' tc <- tCopula(param = 0.7, df = 8)
#' cache <- create_kernel_cache(tc)
#' # Fast lookup: P(V <= 0.5 | U = 0.3)
#' kernel_conditional_cdf(0.5, 0.3, cache)
#' }
#'
#' @export
create_kernel_cache <- function(copula_obj,
                                 u_grid_size = 201,
                                 v_grid_size = 201,
                                 boundary_buffer = 0.005,
                                 compute_quantile = TRUE) {

  if (!inherits(copula_obj, "copula")) {
    stop("copula_obj must be a copula-class object (e.g., tCopula, normalCopula)")
  }

  # Build grids
  u_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = u_grid_size)
  v_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = v_grid_size)

  # --- Conditional CDF: F_0(v | u) via cCopula ---
  # Expand to all (u, v) pairs
  uv_pairs <- as.matrix(expand.grid(u = u_grid, v = v_grid))

  cond_cdf_vec <- tryCatch({
    copula::cCopula(uv_pairs, copula = copula_obj, indices = 2)
  }, error = function(e) {
    stop("cCopula failed: ", e$message)
  })

  # Reshape into matrix: [u_idx, v_idx]
  conditional_cdf <- matrix(cond_cdf_vec, nrow = u_grid_size, ncol = v_grid_size,
                             byrow = FALSE)

  # Clamp to [0, 1] and enforce monotonicity in v for each u-row
  conditional_cdf <- pmax(0, pmin(1, conditional_cdf))
  for (i in seq_len(u_grid_size)) {
    conditional_cdf[i, ] <- cummax(conditional_cdf[i, ])
  }

  # --- Quantile kernel: Q_0(p | u) by inverting F_0(v | u) ---
  quantile_grid <- NULL
  p_grid <- NULL

  if (compute_quantile) {
    p_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = v_grid_size)
    quantile_grid <- matrix(NA_real_, nrow = u_grid_size, ncol = length(p_grid))

    for (i in seq_len(u_grid_size)) {
      cdf_row <- conditional_cdf[i, ]
      # Invert: for each p, find v such that F_0(v|u) = p
      quantile_grid[i, ] <- approx(cdf_row, v_grid, xout = p_grid,
                                    method = "linear", rule = 2)$y
    }
    quantile_grid <- pmax(boundary_buffer, pmin(1 - boundary_buffer, quantile_grid))
  }

  # Extract copula metadata
  copula_family <- class(copula_obj)[1]
  copula_params <- list()
  if (inherits(copula_obj, "tCopula")) {
    copula_params <- list(rho = copula_obj@parameters[1],
                          df  = copula_obj@parameters[2])
  } else if (inherits(copula_obj, "normalCopula")) {
    copula_params <- list(rho = copula_obj@parameters[1])
  } else {
    copula_params <- list(param = copula_obj@parameters)
  }

  result <- list(
    u_grid          = u_grid,
    v_grid          = v_grid,
    conditional_cdf = conditional_cdf,
    quantile_grid   = quantile_grid,
    p_grid          = p_grid,
    u_grid_size     = u_grid_size,
    v_grid_size     = v_grid_size,
    boundary_buffer = boundary_buffer,
    copula_family   = copula_family,
    copula_params   = copula_params,
    created_at      = Sys.time()
  )
  class(result) <- "kernel_cache"
  return(result)
}


#' Look Up Conditional CDF from Kernel Cache
#'
#' Fast bilinear interpolation of F_0(v | u) from a precomputed grid.
#'
#' @param v Numeric vector of current pseudo-observations in (0,1)
#' @param u Numeric vector of prior pseudo-observations in (0,1)
#' @param cache A kernel_cache object from create_kernel_cache()
#'
#' @return Numeric vector of F_0(v | u) values in [0,1]
#'
#' @export
kernel_conditional_cdf <- function(v, u, cache) {

  if (!inherits(cache, "kernel_cache")) {
    stop("cache must be a kernel_cache object")
  }

  u_grid <- cache$u_grid
  v_grid <- cache$v_grid
  cond_mat <- cache$conditional_cdf
  gs_u <- cache$u_grid_size
  gs_v <- cache$v_grid_size
  du <- u_grid[2] - u_grid[1]
  dv <- v_grid[2] - v_grid[1]

  # Clamp inputs
  u <- pmax(u_grid[1], pmin(u_grid[gs_u], u))
  v <- pmax(v_grid[1], pmin(v_grid[gs_v], v))

  # Find grid cell indices
  u_idx <- findInterval(u, u_grid)
  v_idx <- findInterval(v, v_grid)
  u_idx <- pmax(1L, pmin(gs_u - 1L, u_idx))
  v_idx <- pmax(1L, pmin(gs_v - 1L, v_idx))

  # Interpolation weights
  u_frac <- pmax(0, pmin(1, (u - u_grid[u_idx]) / du))
  v_frac <- pmax(0, pmin(1, (v - v_grid[v_idx]) / dv))

  # Bilinear interpolation
  result <- (1 - u_frac) * (1 - v_frac) * cond_mat[cbind(u_idx, v_idx)] +
            u_frac * (1 - v_frac) * cond_mat[cbind(u_idx + 1L, v_idx)] +
            (1 - u_frac) * v_frac * cond_mat[cbind(u_idx, v_idx + 1L)] +
            u_frac * v_frac * cond_mat[cbind(u_idx + 1L, v_idx + 1L)]

  pmax(0, pmin(1, result))
}


#' Look Up Conditional Quantile from Kernel Cache
#'
#' Fast bilinear interpolation of Q_0(p | u) from a precomputed grid.
#' This is the inverse of kernel_conditional_cdf.
#'
#' @param p Numeric vector of probabilities in (0,1)
#' @param u Numeric vector of prior pseudo-observations in (0,1)
#' @param cache A kernel_cache object with compute_quantile = TRUE
#'
#' @return Numeric vector of Q_0(p | u) values in (0,1)
#'
#' @export
kernel_conditional_quantile <- function(p, u, cache) {

  if (!inherits(cache, "kernel_cache")) {
    stop("cache must be a kernel_cache object")
  }
  if (is.null(cache$quantile_grid)) {
    stop("Kernel cache was created without quantile grid. Use compute_quantile = TRUE.")
  }

  u_grid <- cache$u_grid
  p_grid <- cache$p_grid
  q_mat  <- cache$quantile_grid
  gs_u   <- cache$u_grid_size
  gs_p   <- length(p_grid)
  du     <- u_grid[2] - u_grid[1]
  dp     <- p_grid[2] - p_grid[1]

  # Clamp inputs
  u <- pmax(u_grid[1], pmin(u_grid[gs_u], u))
  p <- pmax(p_grid[1], pmin(p_grid[gs_p], p))

  # Find grid cell indices
  u_idx <- pmax(1L, pmin(gs_u - 1L, findInterval(u, u_grid)))
  p_idx <- pmax(1L, pmin(gs_p - 1L, findInterval(p, p_grid)))

  u_frac <- pmax(0, pmin(1, (u - u_grid[u_idx]) / du))
  p_frac <- pmax(0, pmin(1, (p - p_grid[p_idx]) / dp))

  result <- (1 - u_frac) * (1 - p_frac) * q_mat[cbind(u_idx, p_idx)] +
            u_frac * (1 - p_frac) * q_mat[cbind(u_idx + 1L, p_idx)] +
            (1 - u_frac) * p_frac * q_mat[cbind(u_idx, p_idx + 1L)] +
            u_frac * p_frac * q_mat[cbind(u_idx + 1L, p_idx + 1L)]

  pmax(cache$boundary_buffer, pmin(1 - cache$boundary_buffer, result))
}


cat("STEP 3 copula_kernel_cache.R loaded.\n")
cat("  Functions: create_kernel_cache, kernel_conditional_cdf,\n")
cat("             kernel_conditional_quantile\n")
