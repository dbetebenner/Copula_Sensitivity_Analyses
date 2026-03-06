############################################################################
###
### Stratified Growth Regime Estimation for STEP 3
###
### Relaxes the P ⟂ U assumption by fitting separate regimes across
### bins of prior percentile U and aggregating predicted CDFs.
###
############################################################################

#' Estimate stratified growth regimes by U bins
#'
#' @param u_sample Numeric prior percentiles (0-1)
#' @param v_sample Numeric current percentiles (0-1)
#' @param kernel_cache kernel_cache object
#' @param regime_family Character regime family
#' @param distance_fn Character distance function
#' @param v_grid Optional grid for CDF evaluation
#' @param u_weights Optional prior weights
#' @param v_weights Optional current weights
#' @param n_bins Integer number of U bins
#' @param grid_resolution Integer estimation grid resolution
#' @param verbose Logical
#'
#' @return List with stratified fit results and comparison metrics
#' @export
estimate_regime_stratified <- function(u_sample, v_sample, kernel_cache,
                                       regime_family = "beta",
                                       distance_fn = "wasserstein1",
                                       v_grid = NULL,
                                       u_weights = NULL,
                                       v_weights = NULL,
                                       n_bins = 5,
                                       grid_resolution = 20,
                                       verbose = FALSE) {
  if (is.null(v_grid)) v_grid <- seq(0.005, 0.995, length.out = 201)
  n_bins <- max(2L, as.integer(n_bins))

  F_obs <- observed_marginal_cdf(v_grid, v_sample, v_weights)

  q_breaks <- unique(as.numeric(quantile(u_sample, probs = seq(0, 1, length.out = n_bins + 1), na.rm = TRUE)))
  if (length(q_breaks) < 3) {
    stop("Not enough unique quantile breaks for stratified estimation")
  }
  u_bin <- cut(u_sample, breaks = q_breaks, include.lowest = TRUE)
  levels_bin <- levels(u_bin)

  bin_results <- list()
  bin_weights <- numeric(length(levels_bin))
  names(bin_weights) <- levels_bin
  F_pred_bins <- matrix(0, nrow = length(levels_bin), ncol = length(v_grid))
  rownames(F_pred_bins) <- levels_bin

  for (k in seq_along(levels_bin)) {
    lv <- levels_bin[k]
    idx <- which(u_bin == lv)
    if (length(idx) < 25) next
    u_k <- u_sample[idx]
    # preserve cross-sectional assumption by sampling v independently
    v_k <- sample(v_sample, length(idx), replace = TRUE)
    uw_k <- if (!is.null(u_weights)) u_weights[idx] else NULL
    vw_k <- if (!is.null(v_weights)) sample(v_weights, length(idx), replace = TRUE) else NULL

    fit_k <- tryCatch(
      estimate_regime(
        u_sample = u_k,
        v_sample = v_k,
        kernel_cache = kernel_cache,
        regime_family = regime_family,
        distance_fn = distance_fn,
        v_grid = v_grid,
        u_weights = uw_k,
        v_weights = vw_k,
        grid_resolution = grid_resolution,
        verbose = FALSE,
        stratify_by_u = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(fit_k)) next

    F_k <- predict_marginal_cdf(
      v_grid = v_grid,
      u_sample = u_k,
      weights = uw_k,
      regime = fit_k$regime,
      kernel_cache = kernel_cache
    )

    w_k <- if (is.null(uw_k)) length(u_k) else sum(uw_k)
    bin_weights[lv] <- w_k
    F_pred_bins[lv, ] <- F_k
    bin_results[[lv]] <- fit_k
  }

  valid <- names(bin_results)
  if (length(valid) < 2) {
    stop("Insufficient valid bins for stratified regime estimation")
  }
  wv <- bin_weights[valid]
  wv <- wv / sum(wv)
  F_pred <- colSums(F_pred_bins[valid, , drop = FALSE] * wv)
  all_dist <- compute_all_distances(F_pred, F_obs, v_grid)

  mean_sgpc <- sum(sapply(valid, function(v) bin_results[[v]]$regime$mean * 100) * wv)
  med_sgpc <- sum(sapply(valid, function(v) bin_results[[v]]$regime$median * 100) * wv)

  list(
    stratified = TRUE,
    bins = valid,
    bin_weights = wv,
    bin_results = bin_results,
    F_pred = F_pred,
    F_obs = F_obs,
    v_grid = v_grid,
    all_distances = all_dist,
    mean_sgpc = mean_sgpc,
    median_sgpc = med_sgpc,
    distance_min = all_dist[[distance_fn]],
    convergence = 0
  )
}

cat("STEP 3 optimize_regime_stratified.R loaded.\n")
cat("  Function: estimate_regime_stratified\n")
