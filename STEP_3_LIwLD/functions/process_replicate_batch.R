# Worker function for Phase B replicate-batch parallelisation.
# Sourced into each mirai daemon via the daemon-init everywhere() block.
# Relies on .PHASEB_* globals pushed per-condition via everywhere().

process_replicate_batch <- function(
  pool_idx, n_bucket, rep_start, rep_end,
  pool_seed_base,
  pool_id, pool_type,
  ds_id, condition_id,
  year_span, content_area,
  phaseb_progress_file_abs
) {
  t0 <- proc.time()[["elapsed"]]

  sg_idx <- .PHASEB_POOL_DEFS[[pool_idx]]$sg_idx
  reps   <- seq.int(rep_start, rep_end)
  rows   <- vector("list", length(reps))

  for (ri in seq_along(reps)) {
    rep_idx <- reps[[ri]]
    set.seed(pool_seed_base + as.integer(n_bucket) * 1000L + rep_idx)
    rep_obs_idx <- sample(sg_idx, size = as.integer(n_bucket), replace = FALSE)

    true_rep <- sgpc_engine(
      .PHASEB_U_FULL[rep_obs_idx], .PHASEB_V_FULL[rep_obs_idx],
      .PHASEB_P1_COPULA, scale = "percentile"
    )
    u_rep <- reference_cdf(.PHASEB_SS_PRIOR[rep_obs_idx],   .PHASEB_REFS$ref_prior)
    v_rep <- reference_cdf(.PHASEB_SS_CURRENT[rep_obs_idx], .PHASEB_REFS$ref_current)

    est_rep <- tryCatch(
      estimate_regime(
        u_sample        = u_rep,
        v_sample        = v_rep,
        kernel_cache    = .PHASEB_KERNEL_CACHE,
        regime_family   = .PHASEB_CFG_REG$primary_family,
        distance_fn     = .PHASEB_CFG_DIST$primary,
        grid_resolution = 15L,
        verbose         = FALSE
      ),
      error = function(e) NULL
    )

    true_median <- median(true_rep, na.rm = TRUE)
    true_mean   <- mean(true_rep,   na.rm = TRUE)
    if (is.null(est_rep)) {
      inferred_median <- NA_real_; inferred_mean <- NA_real_
      median_error    <- NA_real_; mean_error    <- NA_real_
      converged       <- FALSE
    } else {
      inferred_median <- as.numeric(est_rep$regime$median) * 100
      inferred_mean   <- as.numeric(est_rep$regime$mean)   * 100
      median_error    <- inferred_median - true_median
      mean_error      <- inferred_mean   - true_mean
      converged       <- TRUE
    }
    rows[[ri]] <- list(
      pool_id          = pool_id,
      pool_type        = pool_type,
      span             = year_span,
      content          = content_area,
      dataset_id       = ds_id,
      condition_id     = condition_id,
      subgroup_id      = .PHASEB_POOL_DEFS[[pool_idx]]$subgroup_id,
      n_bucket         = as.integer(n_bucket),
      n_eff_bucket     = as.numeric(n_bucket),
      outer_rep        = rep_idx,
      converged        = converged,
      inferred_median  = inferred_median,
      inferred_mean    = inferred_mean,
      true_median      = true_median,
      true_mean        = true_mean,
      median_error     = median_error,
      mean_error       = mean_error,
      abs_median_error = abs(median_error),
      abs_mean_error   = abs(mean_error)
    )
  }

  elapsed <- proc.time()[["elapsed"]] - t0
  cat(sprintf("[W%d] %s | pool=%s bkt=%d reps=%d-%d | %.1fs\n",
              Sys.getpid(), format(Sys.time(), "%H:%M:%S"),
              pool_id, n_bucket, rep_start, rep_end, elapsed))
  tryCatch(
    cat(sprintf("DONE|%s|%d|%d|%d|%.2f\n",
                pool_id, n_bucket, rep_start, rep_end, elapsed),
        file = phaseb_progress_file_abs, append = TRUE),
    error = function(e) invisible(NULL)
  )

  rbindlist(lapply(rows, as.data.table), fill = TRUE)
}
