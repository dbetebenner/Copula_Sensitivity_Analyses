############################################################################
###
### Bootstrap Uncertainty Quantification for STEP 3
###
### Three layers of uncertainty:
###   (A) Sampling uncertainty — resample prior and current (independently
###       or paired) to quantify finite-sample noise
###   (A') Linkage premium — paired vs independent resampling decomposes
###        subsampling noise (Error 1a) from cohort-mismatch noise (Error 1b)
###   (B) Copula uncertainty  — draw baseline copula parameters from
###       STEP 1 recommendation distributions
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

require(copula)


#' Bootstrap Sampling Uncertainty for Growth Regime Estimation
#'
#' Resamples the prior and current samples and re-estimates the growth regime
#' for each replicate. Supports two pairing modes:
#'
#' \describe{
#'   \item{independent}{(default) Resamples U and V with separate index vectors,
#'     simulating the TIMSS/NAEP cross-sectional design where prior and current
#'     cohorts are different students. Captures Error 1a + 1b jointly.}
#'   \item{paired}{Draws a single shared index vector applied to both U and V,
#'     preserving the implicit student-level linkage. Captures Error 1a only
#'     (subsampling variability). Requires length(u_sample) == length(v_sample)
#'     and that both vectors are aligned by student.}
#' }
#'
#' Running both modes on the same data yields the **linkage premium** — the
#' multiplicative CI inflation from independent cohort sampling — at the
#' observed N, without needing Phase B.
#'
#' @param u_sample Numeric vector. Prior-grade reference percentiles.
#' @param v_sample Numeric vector. Current-grade reference percentiles.
#' @param kernel_cache A kernel_cache object.
#' @param regime_family Character. Default "beta".
#' @param distance_fn Character. Default "wasserstein1".
#' @param n_boot Integer. Number of bootstrap replicates. Default 200.
#' @param v_grid Numeric vector. CDF evaluation grid. Default NULL (auto).
#' @param grid_resolution Integer. Grid resolution for coarse search.
#'   Default 20 (lower than estimate_regime default for speed).
#' @param seed Integer. RNG seed for reproducibility. Default NULL.
#' @param pairing Character. \code{"independent"} (default) draws separate
#'   indices for U and V; \code{"paired"} draws a single shared index.
#' @param verbose Logical. Print progress? Default TRUE.
#'
#' @return List with:
#'   \itemize{
#'     \item regime_param_draws: Matrix [n_boot, n_params] of estimated parameters
#'     \item median_sgpc_draws: Numeric vector of median SGPc from each replicate
#'     \item mean_sgpc_draws: Numeric vector of mean SGPc from each replicate
#'     \item distance_draws: Numeric vector of minimum distances
#'     \item ci_median_sgpc: 95 percent percentile CI for median SGPc
#'     \item ci_mean_sgpc: 95 percent percentile CI for mean SGPc
#'     \item se_median_sgpc: Bootstrap standard error of median SGPc
#'     \item se_mean_sgpc: Bootstrap standard error of mean SGPc
#'     \item n_boot: Number of replicates
#'     \item n_converged: Number that converged
#'     \item pairing: The pairing mode used
#'   }
#'
#' @export
bootstrap_regime <- function(u_sample, v_sample, kernel_cache,
                              regime_family = "beta",
                              distance_fn = "wasserstein1",
                              n_boot = 200,
                              v_grid = NULL,
                              grid_resolution = 20,
                              seed = NULL,
                              u_weights = NULL,
                              v_weights = NULL,
                              resample_scheme = "srs_bootstrap",
                              pairing = c("independent", "paired"),
                              verbose = TRUE) {

  pairing <- match.arg(pairing)

  if (!is.null(seed)) set.seed(seed)

  if (is.null(v_grid)) {
    v_grid <- seq(0.005, 0.995, length.out = 201)
  }

  n_u <- length(u_sample)
  n_v <- length(v_sample)
  is_paired <- identical(pairing, "paired")

  # Paired mode requires equal-length, student-aligned U and V

  if (is_paired && n_u != n_v) {
    stop("pairing='paired' requires length(u_sample) == length(v_sample) ",
         "(got ", n_u, " vs ", n_v, "). ",
         "Vectors must be student-aligned for shared-index resampling.")
  }

  resample_scheme <- tolower(resample_scheme)
  if (is.null(u_weights)) u_weights <- rep(1, n_u)
  if (is.null(v_weights)) v_weights <- rep(1, n_v)
  u_prob <- u_weights / sum(u_weights)
  v_prob <- v_weights / sum(v_weights)

  # Storage
  regime_param_list <- list()
  median_sgpc <- numeric(n_boot)
  mean_sgpc   <- numeric(n_boot)
  distances   <- numeric(n_boot)
  converged   <- logical(n_boot)

  pairing_label <- if (is_paired) "paired" else "independent"
  if (verbose) cat("Bootstrap sampling uncertainty (", pairing_label, "): ",
                   n_boot, " replicates\n", sep = "")

  for (b in seq_len(n_boot)) {
    if (verbose && (b %% 50 == 0 || b == 1)) {
      cat("  Replicate", b, "/", n_boot, "\n")
    }

    # --- Resampling: paired uses shared indices, independent uses separate ---
    if (is_paired) {
      # Shared index preserves student-level U<->V linkage
      shared_idx <- sample.int(n_u, n_u, replace = TRUE)
      u_boot <- u_sample[shared_idx]
      v_boot <- v_sample[shared_idx]
      uw_boot <- u_weights[shared_idx]
      vw_boot <- v_weights[shared_idx]
    } else if (resample_scheme == "weighted_bootstrap") {
      u_idx <- sample.int(n_u, n_u, replace = TRUE, prob = u_prob)
      v_idx <- sample.int(n_v, n_v, replace = TRUE, prob = v_prob)
      u_boot <- u_sample[u_idx]
      v_boot <- v_sample[v_idx]
      uw_boot <- u_weights[u_idx]
      vw_boot <- v_weights[v_idx]
    } else if (resample_scheme == "replicate_weights") {
      warning("replicate_weights is not implemented in STEP 3 yet; falling back to srs_bootstrap")
      u_idx <- sample.int(n_u, n_u, replace = TRUE)
      v_idx <- sample.int(n_v, n_v, replace = TRUE)
      u_boot <- u_sample[u_idx]
      v_boot <- v_sample[v_idx]
      uw_boot <- u_weights[u_idx]
      vw_boot <- v_weights[v_idx]
    } else {
      u_idx <- sample.int(n_u, n_u, replace = TRUE)
      v_idx <- sample.int(n_v, n_v, replace = TRUE)
      u_boot <- u_sample[u_idx]
      v_boot <- v_sample[v_idx]
      uw_boot <- u_weights[u_idx]
      vw_boot <- v_weights[v_idx]
    }

    res <- tryCatch({
      estimate_regime(u_boot, v_boot, kernel_cache,
                      regime_family = regime_family,
                      distance_fn = distance_fn,
                      v_grid = v_grid,
                      u_weights = uw_boot,
                      v_weights = vw_boot,
                      grid_resolution = grid_resolution,
                      verbose = FALSE)
    }, error = function(e) NULL)

    if (!is.null(res)) {
      regime_param_list[[b]] <- res$regime_param_hat
      median_sgpc[b]  <- res$regime$median * 100
      mean_sgpc[b]    <- res$regime$mean * 100
      distances[b]    <- res$distance_min
      converged[b]    <- (res$convergence == 0)
    } else {
      regime_param_list[[b]] <- rep(NA_real_, 2)
      median_sgpc[b]  <- NA_real_
      mean_sgpc[b]    <- NA_real_
      distances[b]    <- NA_real_
      converged[b]    <- FALSE
    }
  }

  regime_param_draws <- do.call(rbind, regime_param_list)
  n_converged <- sum(converged, na.rm = TRUE)
  valid <- !is.na(median_sgpc)

  if (verbose) {
    cat("  Converged:", n_converged, "/", n_boot, "\n")
    if (sum(valid) > 2) {
      cat("  Median SGPc: ", round(median(median_sgpc[valid]), 1),
          " [", round(quantile(median_sgpc[valid], 0.025), 1),
          ", ", round(quantile(median_sgpc[valid], 0.975), 1), "]\n", sep = "")
    }
  }

  list(
    regime_param_draws = regime_param_draws,
    median_sgpc_draws = median_sgpc,
    mean_sgpc_draws  = mean_sgpc,
    distance_draws   = distances,
    ci_median_sgpc   = if (sum(valid) > 2)
                         quantile(median_sgpc[valid], c(0.025, 0.975)) else c(NA, NA),
    ci_mean_sgpc     = if (sum(valid) > 2)
                         quantile(mean_sgpc[valid], c(0.025, 0.975)) else c(NA, NA),
    se_median_sgpc   = if (sum(valid) > 2) sd(median_sgpc[valid]) else NA_real_,
    se_mean_sgpc     = if (sum(valid) > 2) sd(mean_sgpc[valid]) else NA_real_,
    n_boot           = n_boot,
    n_converged      = n_converged,
    resample_scheme  = resample_scheme,
    pairing          = pairing
  )
}


#' Copula Parameter Uncertainty for Growth Regime Estimation
#'
#' Propagates uncertainty from the baseline copula parameter estimates
#' (from STEP 1) by drawing copula parameters from the recommendation
#' distribution and re-estimating the growth regime for each draw.
#'
#' @param u_sample Numeric vector. Prior-grade reference percentiles.
#' @param v_sample Numeric vector. Current-grade reference percentiles.
#' @param copula_param_draws List of copula parameter sets. Each element
#'   should contain $rho and $df (for t-copula). Can be generated from
#'   STEP 1 manifest IQR or from condition-level parameter distributions.
#' @param regime_family Character. Default "beta".
#' @param distance_fn Character. Default "wasserstein1".
#' @param v_grid Numeric vector. CDF evaluation grid. Default NULL.
#' @param grid_resolution Integer. Default 20.
#' @param verbose Logical. Default TRUE.
#'
#' @return List with:
#'   \itemize{
#'     \item regime_param_draws: Matrix of estimated parameters per copula draw
#'     \item median_sgpc_draws: Vector of median SGPc per copula draw
#'     \item copula_params_used: The copula parameters used for each draw
#'     \item var_copula: Variance in median SGPc due to copula uncertainty
#'   }
#'
#' @export
copula_uncertainty <- function(u_sample, v_sample,
                                copula_param_draws,
                                regime_family = "beta",
                                distance_fn = "wasserstein1",
                                v_grid = NULL,
                                grid_resolution = 20,
                                verbose = TRUE) {

  n_draws <- length(copula_param_draws)

  if (is.null(v_grid)) {
    v_grid <- seq(0.005, 0.995, length.out = 201)
  }

  regime_param_list <- list()
  median_sgpc   <- numeric(n_draws)
  copula_used   <- list()

  if (verbose) cat("Copula parameter uncertainty:", n_draws, "draws\n")

  for (m in seq_len(n_draws)) {
    if (verbose && (m %% 10 == 0 || m == 1)) {
      cat("  Draw", m, "/", n_draws, "\n")
    }

    params <- copula_param_draws[[m]]

    # Build copula from parameters
    cop <- tryCatch({
      if (!is.null(params$df)) {
        tCopula(param = params$rho, df = params$df, dispstr = "un")
      } else {
        normalCopula(param = params$rho)
      }
    }, error = function(e) NULL)

    if (is.null(cop)) {
      regime_param_list[[m]] <- rep(NA_real_, 2)
      median_sgpc[m]  <- NA_real_
      copula_used[[m]] <- params
      next
    }

    # Build kernel cache for this copula parameter set
    kc <- tryCatch(
      create_kernel_cache(cop, u_grid_size = 101, v_grid_size = 101,
                          compute_quantile = FALSE),
      error = function(e) NULL
    )

    if (is.null(kc)) {
      regime_param_list[[m]] <- rep(NA_real_, 2)
      median_sgpc[m]  <- NA_real_
      copula_used[[m]] <- params
      next
    }

    res <- tryCatch({
      estimate_regime(u_sample, v_sample, kc,
                      regime_family = regime_family,
                      distance_fn = distance_fn,
                      v_grid = v_grid,
                      grid_resolution = grid_resolution,
                      verbose = FALSE)
    }, error = function(e) NULL)

    if (!is.null(res)) {
      regime_param_list[[m]] <- res$regime_param_hat
      median_sgpc[m]  <- res$regime$median * 100
    } else {
      regime_param_list[[m]] <- rep(NA_real_, 2)
      median_sgpc[m]  <- NA_real_
    }
    copula_used[[m]] <- params
  }

  regime_param_draws <- do.call(rbind, regime_param_list)
  valid <- !is.na(median_sgpc)

  if (verbose && sum(valid) > 2) {
    cat("  Median SGPc range due to copula uncertainty: [",
        round(min(median_sgpc[valid]), 1), ", ",
        round(max(median_sgpc[valid]), 1), "]\n", sep = "")
    cat("  SD:", round(sd(median_sgpc[valid]), 2), "\n")
  }

  list(
    regime_param_draws = regime_param_draws,
    median_sgpc_draws = median_sgpc,
    copula_params_used = copula_used,
    var_copula        = if (sum(valid) > 2) var(median_sgpc[valid]) else NA_real_
  )
}


#' Generate Copula Parameter Draws from STEP 1 Recommendations
#'
#' Convenience function to create a list of copula parameter sets by
#' sampling from the distribution implied by the STEP 1 manifest
#' (median and IQR -> approximate Normal draws).
#'
#' @param manifest_params List with $rho (list with $median, $q25, $q75)
#'   and $df (list with $median, $q25, $q75).
#' @param n_draws Integer. Number of draws. Default 25.
#' @param seed Integer. RNG seed. Default NULL.
#'
#' @return List of n_draws parameter sets, each with $rho and $df.
#'
#' @export
generate_copula_draws <- function(manifest_params, n_draws = 25, seed = NULL) {

  if (!is.null(seed)) set.seed(seed)

  # Approximate SD from IQR: SD ~ IQR / 1.35
  rho_med <- manifest_params$rho$median
  rho_sd  <- (manifest_params$rho$q75 - manifest_params$rho$q25) / 1.35

  df_med  <- manifest_params$df$median
  df_sd   <- (manifest_params$df$q75 - manifest_params$df$q25) / 1.35

  draws <- lapply(seq_len(n_draws), function(i) {
    rho_draw <- pmax(-0.99, pmin(0.99, rnorm(1, rho_med, rho_sd)))
    df_draw  <- pmax(2, round(rnorm(1, df_med, df_sd)))
    list(rho = rho_draw, df = df_draw)
  })

  return(draws)
}


cat("STEP 3 bootstrap_uncertainty.R loaded.\n")
cat("  Functions: bootstrap_regime, copula_uncertainty, generate_copula_draws\n")
