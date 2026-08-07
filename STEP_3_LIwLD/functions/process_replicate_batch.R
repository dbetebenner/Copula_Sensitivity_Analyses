# Worker function for Phase B replicate-batch parallelisation.
# Sourced into each mirai daemon via the daemon-init everywhere() block.
# Relies on .PHASEB_* globals pushed per-condition via everywhere().
#
# Truth source: when .PHASEB_TRUE_SGPC_FULL exists (pre-loaded from STEP 2
# sgpc_emp), truth is an indexed lookup — no sgpc_engine call needed.
# Falls back to sgpc_engine if the global is NULL/missing.
#
# Linkage fraction (linkage_fraction parameter, default 1.0 = matched pairs):
#   1.0           — (default) Same student indices for both U and V.
#                    Measures subsampling variability only (Error 1a).
#   0.0           — Separate random draws for U and V, mirroring the
#                    TIMSS/NAEP cross-sectional design where prior and
#                    current cohorts are different students. Captures the
#                    full cross-sectional sampling uncertainty (Error 1a + 1b).
#   0 < lf < 1   — Partial linkage: floor(lf * N) students share indices,
#                    remaining (N - floor(lf * N)) draw separate indices.
#                    Simulates designs with partial cohort overlap.
#
# Backward compatibility:
#   The legacy `sampling_mode` parameter ("paired" / "independent") is still
#   accepted and mapped to linkage_fraction = 1.0 / 0.0 respectively.
#   When both are provided, linkage_fraction takes precedence.
#
# In independent/partial modes, per-replicate ground truth is undefined
# (incomplete student pairing), so truth is taken from
# .PHASEB_TRUE_POOL_MEDIAN / _MEAN, which are the full-pool summary
# statistics pushed per-condition via everywhere().

process_replicate_batch <- function(
  pool_idx,
  n_bucket,
  rep_start,
  rep_end,
  pool_seed_base,
  pool_id,
  pool_type,
  ds_id,
  condition_id,
  year_span,
  content_area,
  phaseb_progress_file_abs,
  sampling_mode = NULL,
  linkage_fraction = NULL
) {
  t0 <- proc.time()[["elapsed"]]

  # --- Resolve linkage_fraction from explicit value or legacy sampling_mode ---
  if (is.null(linkage_fraction)) {
    if (!is.null(sampling_mode)) {
      linkage_fraction <- if (identical(sampling_mode, "paired")) 1.0 else 0.0
    } else {
      linkage_fraction <- 1.0 # default: matched pairs
    }
  }
  linkage_fraction <- as.numeric(linkage_fraction)
  stopifnot(
    is.finite(linkage_fraction),
    linkage_fraction >= 0,
    linkage_fraction <= 1
  )

  # Derive sampling_mode label for output compatibility
  sampling_mode_label <- if (linkage_fraction == 1.0) {
    "paired"
  } else if (linkage_fraction == 0.0) {
    "independent"
  } else {
    sprintf("partial_%.2f", linkage_fraction)
  }

  sg_idx <- .PHASEB_POOL_DEFS[[pool_idx]]$sg_idx
  reps <- seq.int(rep_start, rep_end)
  rows <- vector("list", length(reps))
  n_pool <- length(sg_idx)

  has_preloaded_truth <- exists(".PHASEB_TRUE_SGPC_FULL", inherits = TRUE) &&
    !is.null(.PHASEB_TRUE_SGPC_FULL)

  # For non-fully-paired modes, use full-pool truth (fixed target, not per-replicate)
  is_fully_paired <- (linkage_fraction == 1.0)
  if (!is_fully_paired) {
    pool_truth_median <- if (
      exists(".PHASEB_TRUE_POOL_MEDIAN", inherits = TRUE)
    ) {
      .PHASEB_TRUE_POOL_MEDIAN[[pool_idx]]
    } else {
      NA_real_
    }
    pool_truth_mean <- if (exists(".PHASEB_TRUE_POOL_MEAN", inherits = TRUE)) {
      .PHASEB_TRUE_POOL_MEAN[[pool_idx]]
    } else {
      NA_real_
    }
  }

  # Encode linkage_fraction into seed offset for reproducibility across fractions.
  # Multiplied by 100 and rounded to avoid floating-point seed collisions.
  lf_seed_offset <- as.integer(round(linkage_fraction * 100))

  for (ri in seq_along(reps)) {
    rep_idx <- reps[[ri]]
    set.seed(
      pool_seed_base +
        as.integer(n_bucket) * 1000L +
        rep_idx +
        lf_seed_offset * 10000L
    )

    n_bkt <- as.integer(n_bucket)
    n_linked <- as.integer(floor(linkage_fraction * n_bkt))
    n_unlinked <- n_bkt - n_linked

    if (n_linked == n_bkt) {
      # ---- Fully paired (linkage_fraction == 1.0) ----
      rep_obs_idx <- sample(sg_idx, size = n_bkt, replace = FALSE)

      if (has_preloaded_truth) {
        true_rep <- .PHASEB_TRUE_SGPC_FULL[rep_obs_idx]
      } else {
        true_rep <- sgpc_engine(
          .PHASEB_U_FULL[rep_obs_idx],
          .PHASEB_V_FULL[rep_obs_idx],
          .PHASEB_P1_COPULA,
          scale = "percentile"
        )
      }
      u_rep <- reference_cdf(
        .PHASEB_SS_PRIOR[rep_obs_idx],
        .PHASEB_REFS$ref_prior
      )
      v_rep <- reference_cdf(
        .PHASEB_SS_CURRENT[rep_obs_idx],
        .PHASEB_REFS$ref_current
      )

      true_median <- median(true_rep, na.rm = TRUE)
      true_mean <- mean(true_rep, na.rm = TRUE)
    } else if (n_linked == 0L) {
      # ---- Fully independent (linkage_fraction == 0.0) ----
      u_obs_idx <- sample(sg_idx, size = n_bkt, replace = FALSE)
      v_obs_idx <- sample(sg_idx, size = n_bkt, replace = FALSE)

      u_rep <- reference_cdf(
        .PHASEB_SS_PRIOR[u_obs_idx],
        .PHASEB_REFS$ref_prior
      )
      v_rep <- reference_cdf(
        .PHASEB_SS_CURRENT[v_obs_idx],
        .PHASEB_REFS$ref_current
      )

      true_median <- pool_truth_median
      true_mean <- pool_truth_mean
    } else {
      # ---- Partial linkage (0 < linkage_fraction < 1) ----
      # Linked portion: shared student indices preserve (U,V) dependence
      linked_idx <- sample(sg_idx, size = n_linked, replace = FALSE)
      u_linked <- reference_cdf(
        .PHASEB_SS_PRIOR[linked_idx],
        .PHASEB_REFS$ref_prior
      )
      v_linked <- reference_cdf(
        .PHASEB_SS_CURRENT[linked_idx],
        .PHASEB_REFS$ref_current
      )

      # Unlinked portion: separate draws break the pairing
      u_unlinked_idx <- sample(sg_idx, size = n_unlinked, replace = FALSE)
      v_unlinked_idx <- sample(sg_idx, size = n_unlinked, replace = FALSE)
      u_unlinked <- reference_cdf(
        .PHASEB_SS_PRIOR[u_unlinked_idx],
        .PHASEB_REFS$ref_prior
      )
      v_unlinked <- reference_cdf(
        .PHASEB_SS_CURRENT[v_unlinked_idx],
        .PHASEB_REFS$ref_current
      )

      # Concatenate linked + unlinked
      u_rep <- c(u_linked, u_unlinked)
      v_rep <- c(v_linked, v_unlinked)

      # Truth: full-pool summary (per-replicate truth undefined for mixed design)
      true_median <- pool_truth_median
      true_mean <- pool_truth_mean
    }

    # grid_resolution for replicates: use rep_grid_resolution from regime config
    # if available (set in config_step3.R systematic$rep_grid_resolution), else
    # fall back to 15. Lower values (~10) give ~2.25x per-task speedup at the
    # cost of slightly coarser optimisation — acceptable since we average 200 reps.
    rep_grid_res <- {
      gr <- .PHASEB_CFG_REG[["rep_grid_resolution"]]
      if (is.null(gr) || !is.finite(as.numeric(gr)) || as.integer(gr) < 5L) {
        15L
      } else {
        as.integer(gr)
      }
    }
    est_rep <- tryCatch(
      estimate_regime(
        u_sample = u_rep,
        v_sample = v_rep,
        kernel_cache = .PHASEB_KERNEL_CACHE,
        regime_family = .PHASEB_CFG_REG$primary_family,
        distance_fn = .PHASEB_CFG_DIST$primary,
        grid_resolution = rep_grid_res,
        verbose = FALSE
      ),
      error = function(e) NULL
    )

    if (is.null(est_rep)) {
      inferred_median <- NA_real_
      inferred_mean <- NA_real_
      median_error <- NA_real_
      mean_error <- NA_real_
      converged <- FALSE
      m_hat <- NA_real_
      kappa_hat <- NA_real_
    } else {
      inferred_median <- as.numeric(est_rep$regime$median) * 100
      inferred_mean <- as.numeric(est_rep$regime$mean) * 100
      median_error <- inferred_median - true_median
      mean_error <- inferred_mean - true_mean
      converged <- TRUE
      m_hat <- est_rep$regime_param_hat[1]
      kappa_hat <- est_rep$regime_param_hat[2]
    }
    rows[[ri]] <- list(
      pool_id = pool_id,
      pool_type = pool_type,
      span = year_span,
      content = content_area,
      dataset_id = ds_id,
      condition_id = condition_id,
      subgroup_id = .PHASEB_POOL_DEFS[[pool_idx]]$subgroup_id,
      n_bucket = as.integer(n_bucket),
      n_eff_bucket = as.numeric(n_bucket),
      outer_rep = rep_idx,
      sampling_mode = sampling_mode_label,
      linkage_fraction = linkage_fraction,
      converged = converged,
      inferred_median = inferred_median,
      inferred_mean = inferred_mean,
      true_median = true_median,
      true_mean = true_mean,
      median_error = median_error,
      mean_error = mean_error,
      abs_median_error = abs(median_error),
      abs_mean_error = abs(mean_error),
      m_hat = m_hat,
      kappa_hat = kappa_hat
    )
  }

  elapsed <- proc.time()[["elapsed"]] - t0
  cat(sprintf(
    "[W%d] %s | lf=%.2f pool=%s bkt=%d reps=%d-%d | %.1fs\n",
    Sys.getpid(),
    format(Sys.time(), "%H:%M:%S"),
    linkage_fraction,
    pool_id,
    n_bucket,
    rep_start,
    rep_end,
    elapsed
  ))
  tryCatch(
    cat(
      sprintf(
        "DONE|lf=%.2f|%s|%d|%d|%d|%.2f\n",
        linkage_fraction,
        pool_id,
        n_bucket,
        rep_start,
        rep_end,
        elapsed
      ),
      file = phaseb_progress_file_abs,
      append = TRUE
    ),
    error = function(e) invisible(NULL)
  )

  rbindlist(lapply(rows, as.data.table), fill = TRUE)
}

cat("STEP 3 process_replicate_batch.R loaded.\n")
cat(
  "  Functions: process_replicate_batch (supports linkage_fraction 0.0-1.0)\n"
)
