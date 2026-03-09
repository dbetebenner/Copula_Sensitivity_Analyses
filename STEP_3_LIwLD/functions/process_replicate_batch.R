# Worker function for Phase B replicate-batch parallelisation.
# Sourced into each mirai daemon via the daemon-init everywhere() block.
# Relies on .PHASEB_* globals pushed per-condition via everywhere().
#
# Truth source: when .PHASEB_TRUE_SGPC_FULL exists (pre-loaded from STEP 2
# sgpc_emp), truth is an indexed lookup — no sgpc_engine call needed.
# Falls back to sgpc_engine if the global is NULL/missing.

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

  has_preloaded_truth <- exists(".PHASEB_TRUE_SGPC_FULL", inherits = TRUE) &&
                         !is.null(.PHASEB_TRUE_SGPC_FULL)

  for (ri in seq_along(reps)) {
    rep_idx <- reps[[ri]]
    set.seed(pool_seed_base + as.integer(n_bucket) * 1000L + rep_idx)
    rep_obs_idx <- sample(sg_idx, size = as.integer(n_bucket), replace = FALSE)

    if (has_preloaded_truth) {
      true_rep <- .PHASEB_TRUE_SGPC_FULL[rep_obs_idx]
    } else {
      true_rep <- sgpc_engine(
        .PHASEB_U_FULL[rep_obs_idx], .PHASEB_V_FULL[rep_obs_idx],
        .PHASEB_P1_COPULA, scale = "percentile"
      )
    }
    u_rep <- reference_cdf(.PHASEB_SS_PRIOR[rep_obs_idx],   .PHASEB_REFS$ref_prior)
    v_rep <- reference_cdf(.PHASEB_SS_CURRENT[rep_obs_idx], .PHASEB_REFS$ref_current)

    # grid_resolution for replicates: use rep_grid_resolution from regime config
    # if available (set in config_step3.R systematic$rep_grid_resolution), else
    # fall back to 15. Lower values (~10) give ~2.25x per-task speedup at the
    # cost of slightly coarser optimisation — acceptable since we average 200 reps.
    rep_grid_res <- {
      gr <- .PHASEB_CFG_REG[["rep_grid_resolution"]]
      if (is.null(gr) || !is.finite(as.numeric(gr)) || as.integer(gr) < 5L) 15L
      else as.integer(gr)
    }
    est_rep <- tryCatch(
      estimate_regime(
        u_sample        = u_rep,
        v_sample        = v_rep,
        kernel_cache    = .PHASEB_KERNEL_CACHE,
        regime_family   = .PHASEB_CFG_REG$primary_family,
        distance_fn     = .PHASEB_CFG_DIST$primary,
        grid_resolution = rep_grid_res,
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

cat("STEP 3 process_replicate_batch.R loaded.\n")
cat("  Functions: process_replicate_batch\n")
