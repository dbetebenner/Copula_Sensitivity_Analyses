###############################################################################
###
### induced_cdf.R --- Build the induced V-CDF tensor over the (m, kappa) grid.
###
### One pure function, build_induced_cdf_tensor(), that produces a
### [length(m_grid), length(k_grid), length(v_grid)] array of induced CDFs
### F_G(v) = E_U[ G(F_0(v | U)) ] where:
###    G = Beta(m, kappa) growth-regime CDF
###    F_0(v | U) = the conditional V-given-U CDF baked into kernel_cache
###    U = subgroup pseudo-observations (u_sample)
### (H is reserved for the joint CDF in Sklar's theorem; G carries the
### growth regime everywhere downstream.)
###
### Depends on functions sourced by the orchestrator:
###    regime_beta()                from STEP_3_LIwLD/functions/regime_families.R
###    predict_marginal_cdf()       from STEP_3_LIwLD/functions/predict_v_cdf.R
###
### Author: Damian Betebenner, Claude (collaborator)
### Created: 2026-05-04
###
###############################################################################

#' Build the induced-V CDF tensor over the regime grid.
#'
#' For each (m, kappa) cell in the regime grid, computes the induced marginal
#' V-CDF on `v_grid` by convolving the regime G = Beta(m, kappa) against the
#' conditional kernel F_0(v|U) and the empirical U distribution `u_sample`.
#'
#' This is the panel-5 backing tensor for the LIwLD interactive. At the
#' default 45 x 30 x 200 resolution, it computes ~1,350 CDF evaluations and
#' returns ~270k floats; runtime is dominated by `predict_marginal_cdf` and is
#' typically 30-90s on a laptop depending on kernel cache size.
#'
#' @param m_grid     Numeric vector of regime means in (0, 1).
#' @param k_grid     Numeric vector of regime concentrations in (0, Inf).
#' @param v_grid     Numeric vector of v-points where induced CDFs are evaluated.
#' @param u_sample   Numeric vector of subgroup pseudo-observations in (0, 1).
#' @param kernel_cache An object produced by `create_kernel_cache()` /
#'                     `.create_kernel_cache_safe()` — encodes F_0(v | U).
#' @param verbose    If TRUE, prints a one-line progress indicator every
#'                   `progress_every` cells.
#' @param progress_every Number of cells between progress prints.
#'
#' @return A list with:
#'   \item{tensor}{numeric array, dim = c(length(m_grid), length(k_grid), length(v_grid))}
#'   \item{w1}{numeric matrix, dim = c(length(m_grid), length(k_grid)),
#'             with W_1 distance to F_obs if `f_obs` was supplied (else NULL).}
#'   \item{argmin}{list(m, k, m_idx, k_idx, w1) — only if `f_obs` supplied.}
#'
#' Index conventions: tensor[i, j, ] is the induced CDF for
#'   m = m_grid[i], k = k_grid[j].
#' Row-major storage in R; the export step writes it row-major to disk.
build_induced_cdf_tensor <- function(
  m_grid,
  k_grid,
  v_grid,
  u_sample,
  kernel_cache,
  f_obs = NULL,
  verbose = TRUE,
  progress_every = 100L
) {
  stopifnot(
    is.numeric(m_grid),
    all(m_grid > 0 & m_grid < 1),
    is.numeric(k_grid),
    all(k_grid > 0),
    is.numeric(v_grid),
    all(v_grid >= 0 & v_grid <= 1),
    is.numeric(u_sample),
    all(u_sample >= 0 & u_sample <= 1),
    inherits(kernel_cache, "kernel_cache") || is.list(kernel_cache)
  )

  if (!exists("regime_beta", mode = "function")) {
    stop(
      "`regime_beta()` not found. Source STEP_3_LIwLD/functions/regime_families.R first."
    )
  }
  if (!exists("predict_marginal_cdf", mode = "function")) {
    stop(
      "`predict_marginal_cdf()` not found. Source STEP_3_LIwLD/functions/predict_v_cdf.R first."
    )
  }

  m_n <- length(m_grid)
  k_n <- length(k_grid)
  v_n <- length(v_grid)

  tensor <- array(NA_real_, dim = c(m_n, k_n, v_n))
  w1 <- if (!is.null(f_obs)) matrix(NA_real_, nrow = m_n, ncol = k_n) else NULL

  if (!is.null(f_obs) && length(f_obs) != v_n) {
    stop("length(f_obs) must equal length(v_grid).")
  }

  total_cells <- m_n * k_n
  cell_count <- 0L
  t_start <- Sys.time()

  if (verbose) {
    cat(sprintf(
      "build_induced_cdf_tensor: sweeping %d x %d = %d cells over v-grid of %d points\n",
      m_n,
      k_n,
      total_cells,
      v_n
    ))
  }

  for (i in seq_len(m_n)) {
    for (j in seq_len(k_n)) {
      regime <- regime_beta(m_grid[i], k_grid[j])
      f_h <- predict_marginal_cdf(
        v_grid = v_grid,
        u_sample = u_sample,
        regime = regime,
        kernel_cache = kernel_cache
      )

      # Defensive: monotonize and clamp.  Numerical noise in `predict_marginal_cdf`
      # can produce tiny non-monotone wobbles near 0 / 1.  We require monotone
      # nondecreasing CDFs in the visualization layer (the W_1 shaded band
      # depends on it), so enforce here.
      f_h <- pmin(pmax(f_h, 0), 1)
      f_h <- cummax(f_h)

      tensor[i, j, ] <- f_h

      if (!is.null(f_obs)) {
        # Discrete L1 distance between CDFs == 1D Wasserstein-1.
        # Trapezoidal rule on the v-grid, which need not be uniform.
        dv <- diff(v_grid)
        h_mid <- 0.5 * (abs(f_h[-1] - f_obs[-1]) + abs(f_h[-v_n] - f_obs[-v_n]))
        w1[i, j] <- sum(h_mid * dv)
      }

      cell_count <- cell_count + 1L
      if (verbose && cell_count %% progress_every == 0L) {
        elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
        rate <- cell_count / elapsed
        eta <- (total_cells - cell_count) / rate
        cat(sprintf(
          "  ... %d / %d cells (%.0f%%) | %.1f cells/s | ETA %.0fs\n",
          cell_count,
          total_cells,
          100 * cell_count / total_cells,
          rate,
          eta
        ))
      }
    }
  }

  argmin <- NULL
  if (!is.null(w1)) {
    flat_idx <- which.min(w1)
    k_idx <- ceiling(flat_idx / m_n)
    m_idx <- flat_idx - (k_idx - 1L) * m_n
    argmin <- list(
      m = m_grid[m_idx],
      k = k_grid[k_idx],
      m_idx = m_idx - 1L, # zero-based for the wire format
      k_idx = k_idx - 1L,
      w1 = w1[m_idx, k_idx]
    )
  }

  if (verbose) {
    elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
    cat(sprintf(
      "build_induced_cdf_tensor: done in %.1fs.\n",
      elapsed
    ))
    if (!is.null(argmin)) {
      cat(sprintf(
        "  argmin at (m = %.4f, kappa = %.3f) with W_1 = %.6f\n",
        argmin$m,
        argmin$k,
        argmin$w1
      ))
    }
  }

  list(tensor = tensor, w1 = w1, argmin = argmin)
}


#' Convenience: regime grid constructor matching the manifest schema.
#'
#' Produces the canonical (m_grid, k_grid) for v1: linear in m, log in kappa.
#' The grid is in *index* (interior) layout — endpoints of the half-open
#' (0, 1) interval are avoided for m and (1, Inf) for kappa.
#'
#' @param m_min,m_max,m_n  m-axis: linear grid.
#' @param k_min,k_max,k_n  kappa-axis: log10 grid.
make_regime_grid <- function(
  m_min = 0.05,
  m_max = 0.95,
  m_n = 45L,
  k_min = 1.5,
  k_max = 60.0,
  k_n = 30L
) {
  m_grid <- seq(m_min, m_max, length.out = m_n)
  k_grid <- exp(seq(log(k_min), log(k_max), length.out = k_n))
  list(
    m_grid = m_grid,
    k_grid = k_grid,
    spec = list(
      m_min = m_min,
      m_max = m_max,
      m_n = as.integer(m_n),
      m_scale = "linear",
      k_min = k_min,
      k_max = k_max,
      k_n = as.integer(k_n),
      k_scale = "log"
    )
  )
}
