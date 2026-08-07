############################################################################
###
### process_pool_setup.R — Stage 1 pool-level regime estimation
###
### Daemon-compatible version for parallel Stage 1 dispatch via mirai_map.
### Reads shared condition data from .PHASEB_S1_* globals pushed via
### everywhere() before Stage 1 dispatch.
###
### Sequential fallback: the main script retains the original inline
### definition that accepts all arguments explicitly.
###
### Called once per pool (district or cluster) within a condition.
### Returns: summary_row, pool_registry, copula_rows, independence_rows,
###          pool_result, eligible_buckets, seed_base offset.
###
############################################################################

process_pool_setup_daemon <- function(
  pool_idx,
  pool_id,
  pool_type,
  sg_id,
  sg_idx,
  n_sg,
  ds_id,
  condition_id,
  year_span,
  content_area,
  n_buckets,
  eligibility_buffer,
  seed_base,
  enable_copula_sensitivity = TRUE,
  enable_independence_sensitivity = TRUE,
  strata_label = NA_character_,
  n_constituent_districts = 1L,
  constituent_districts = NA_character_
) {
  # ---- Read shared data from daemon globals ----
  pairs_ss_prior <- .PHASEB_S1_SS_PRIOR
  pairs_ss_current <- .PHASEB_S1_SS_CURRENT
  refs <- .PHASEB_S1_REFS
  p1_copula <- .PHASEB_S1_P1_COPULA
  kernel_cache <- .PHASEB_S1_KERNEL_CACHE
  u_full <- .PHASEB_S1_U_FULL
  v_full <- .PHASEB_S1_V_FULL
  true_sgpc_full <- .PHASEB_S1_TRUE_SGPC_FULL
  cfg_reg <- .PHASEB_S1_CFG_REG
  cfg_dist <- .PHASEB_S1_CFG_DIST
  cfg_sys <- .PHASEB_S1_CFG_SYS
  buckets_cfg <- .PHASEB_S1_BUCKETS_CFG

  t0 <- proc.time()[["elapsed"]]

  if (n_sg < cfg_sys$min_subgroup_n) {
    return(NULL)
  }

  # ---- Truth: either preloaded or recompute ----
  if (!is.null(true_sgpc_full)) {
    true_sgpc <- true_sgpc_full[sg_idx]
  } else {
    true_sgpc <- sgpc_engine(
      u_full[sg_idx],
      v_full[sg_idx],
      p1_copula,
      scale = "percentile"
    )
  }

  # ---- Cross-sectional reference CDFs ----
  u_cross <- reference_cdf(pairs_ss_prior[sg_idx], refs$ref_prior)
  v_cross <- reference_cdf(pairs_ss_current[sg_idx], refs$ref_current)

  # ---- Full-pool regime estimation ----
  est <- tryCatch(
    estimate_regime(
      u_cross,
      v_cross,
      kernel_cache,
      regime_family = cfg_reg$primary_family,
      distance_fn = cfg_dist$primary,
      grid_resolution = 20L,
      verbose = FALSE
    ),
    error = function(e) NULL
  )
  if (is.null(est)) {
    return(NULL)
  }

  # ---- Uniform baseline comparison ----
  uniform_reg <- regime_beta(0.5, 2)
  F_uniform <- tryCatch(
    predict_marginal_cdf(
      v_grid = est$v_grid,
      u_sample = u_cross,
      regime = uniform_reg,
      kernel_cache = kernel_cache
    ),
    error = function(e) rep(NA_real_, length(est$v_grid))
  )
  w1_uniform <- if (all(is.na(F_uniform))) {
    NA_real_
  } else {
    wasserstein1(F_uniform, est$F_obs, est$v_grid)
  }
  w1_best <- est$all_distances$wasserstein1
  w1_reduction_pct <- ifelse(
    is.finite(w1_uniform) && w1_uniform > 0,
    100 * (1 - (w1_best / w1_uniform)),
    NA_real_
  )
  residual <- est$F_pred - est$F_obs

  # ---- Summary row ----
  summary_row <- data.table::data.table(
    dataset_id = ds_id,
    condition_id = condition_id,
    year_span = year_span,
    content_area = content_area,
    subgroup_id = sg_id,
    n_subgroup = n_sg,
    regime_family = cfg_reg$primary_family,
    median_sgpc_inferred = round(est$regime$median * 100, 2),
    mean_sgpc_inferred = round(est$regime$mean * 100, 2),
    median_sgpc_true = round(median(true_sgpc, na.rm = TRUE), 2),
    mean_sgpc_true = round(mean(true_sgpc, na.rm = TRUE), 2),
    median_diff = round(
      est$regime$median * 100 - median(true_sgpc, na.rm = TRUE),
      2
    ),
    mean_diff = round(est$regime$mean * 100 - mean(true_sgpc, na.rm = TRUE), 2),
    wasserstein1 = round(est$all_distances$wasserstein1, 6),
    w1_best = round(w1_best, 6),
    w1_uniform = round(w1_uniform, 6),
    w1_reduction_pct = round(w1_reduction_pct, 3),
    max_abs_residual = round(max(abs(residual), na.rm = TRUE), 6),
    mean_abs_residual = round(mean(abs(residual), na.rm = TRUE), 6),
    ci_width_median = NA_real_,
    ci_width_mean = NA_real_,
    cvm = round(est$all_distances$cramer_von_mises, 6),
    ks = round(est$all_distances$ks_distance, 6),
    regime_param_1 = round(est$regime_param_hat[1], 4),
    regime_param_2 = if (length(est$regime_param_hat) > 1) {
      round(est$regime_param_hat[2], 4)
    } else {
      NA_real_
    },
    m_hat = round(est$m_hat, 4),
    kappa_hat = round(est$kappa_hat, 4)
  )

  # ---- Pool registry ----
  pool_registry <- data.table::data.table(
    pool_id = pool_id,
    pool_type = pool_type,
    span = year_span,
    content = content_area,
    dataset_id = ds_id,
    condition_id = condition_id,
    subgroup_id = sg_id,
    n_pool_raw = n_sg,
    n_pool_eff = n_sg,
    eligibility_buffer = eligibility_buffer,
    strata_label = strata_label,
    n_constituent_districts = n_constituent_districts,
    constituent_districts = constituent_districts
  )

  eligible_buckets <- n_buckets[n_sg >= (n_buckets * (1 + eligibility_buffer))]

  # ---- Copula sensitivity (B2) ----
  copula_dt <- data.table::data.table()
  if (isTRUE(enable_copula_sensitivity)) {
    base_rho <- tryCatch(as.numeric(p1_copula@param[1]), error = function(e) {
      NA_real_
    })
    base_df <- tryCatch(as.numeric(p1_copula@df), error = function(e) NA_real_)
    rho_variants <- unique(c(base_rho, base_rho - 0.10, base_rho + 0.10))
    rho_variants <- pmax(-0.95, pmin(0.95, rho_variants))
    if (all(is.na(rho_variants))) {
      rho_variants <- 0.6
    }
    df_variants <- if (is.finite(base_df)) {
      unique(c(base_df, pmax(2, base_df - 3), base_df + 3))
    } else {
      8
    }
    cop_rows <- list()
    cop_i <- 0L
    for (rv in rho_variants) {
      for (dv in df_variants) {
        cop <- tryCatch(
          copula::tCopula(param = rv, df = dv, dispstr = "un"),
          error = function(e) NULL
        )
        if (is.null(cop)) {
          next
        }
        kc_var <- tryCatch(
          create_kernel_cache(
            cop,
            u_grid_size = 101,
            v_grid_size = 101,
            compute_quantile = FALSE
          ),
          error = function(e) NULL
        )
        if (is.null(kc_var)) {
          next
        }
        est_var <- tryCatch(
          estimate_regime(
            u_cross,
            v_cross,
            kc_var,
            regime_family = cfg_reg$primary_family,
            distance_fn = cfg_dist$primary,
            grid_resolution = 15L,
            verbose = FALSE
          ),
          error = function(e) NULL
        )
        if (is.null(est_var)) {
          next
        }
        cop_i <- cop_i + 1L
        cop_rows[[cop_i]] <- data.table::data.table(
          dataset_id = ds_id,
          condition_id = condition_id,
          subgroup_id = sg_id,
          n_subgroup = n_sg,
          copula_family = "t",
          rho = round(rv, 4),
          df = round(dv, 3),
          median_sgpc = round(est_var$regime$median * 100, 3),
          mean_sgpc = round(est_var$regime$mean * 100, 3),
          delta_median_vs_base = round(
            (est_var$regime$median - est$regime$median) * 100,
            3
          ),
          delta_mean_vs_base = round(
            (est_var$regime$mean - est$regime$mean) * 100,
            3
          ),
          w1 = round(est_var$all_distances$wasserstein1, 6),
          cvm = round(est_var$all_distances$cramer_von_mises, 6)
        )
      }
    }
    if (cop_i > 0L) copula_dt <- data.table::rbindlist(cop_rows, fill = TRUE)
  }

  # ---- Independence sensitivity (B3) ----
  independence_dt <- data.table::data.table()
  if (isTRUE(enable_independence_sensitivity)) {
    strat_fit <- tryCatch(
      estimate_regime(
        u_cross,
        v_cross,
        kernel_cache,
        regime_family = cfg_reg$primary_family,
        distance_fn = cfg_dist$primary,
        grid_resolution = 15L,
        verbose = FALSE,
        stratify_by_u = TRUE,
        stratify_bins = cfg_reg$stratify_bins
      ),
      error = function(e) NULL
    )
    if (!is.null(strat_fit)) {
      base_k3 <- classify_bucket(
        est$regime$median * 100,
        k = 3,
        cutpoints = buckets_cfg$k3
      )$assigned_bucket
      strat_k3 <- classify_bucket(
        strat_fit$median_sgpc,
        k = 3,
        cutpoints = buckets_cfg$k3
      )$assigned_bucket
      base_k5 <- classify_bucket(
        est$regime$median * 100,
        k = 5,
        cutpoints = buckets_cfg$k5
      )$assigned_bucket
      strat_k5 <- classify_bucket(
        strat_fit$median_sgpc,
        k = 5,
        cutpoints = buckets_cfg$k5
      )$assigned_bucket
      independence_dt <- data.table::data.table(
        dataset_id = ds_id,
        condition_id = condition_id,
        subgroup_id = sg_id,
        n_subgroup = n_sg,
        n_bins = length(strat_fit$bins),
        w1_single = round(est$all_distances$wasserstein1, 6),
        w1_stratified = round(strat_fit$all_distances$wasserstein1, 6),
        cvm_single = round(est$all_distances$cramer_von_mises, 6),
        cvm_stratified = round(strat_fit$all_distances$cramer_von_mises, 6),
        delta_median = round(
          strat_fit$median_sgpc - est$regime$median * 100,
          3
        ),
        delta_mean = round(strat_fit$mean_sgpc - est$regime$mean * 100, 3),
        base_k3 = base_k3,
        stratified_k3 = strat_k3,
        base_k5 = base_k5,
        stratified_k5 = strat_k5,
        k3_changed = base_k3 != strat_k3,
        k5_changed = base_k5 != strat_k5
      )
    }
  }

  elapsed <- proc.time()[["elapsed"]] - t0
  cat(sprintf(
    "[W%d] Pool %s (%s, N=%d) | median=%.1f, diff=%.1f | %.1fs\n",
    Sys.getpid(),
    pool_id,
    pool_type,
    n_sg,
    summary_row$median_sgpc_inferred,
    summary_row$median_diff,
    elapsed
  ))

  list(
    summary_row = summary_row,
    pool_registry = pool_registry,
    copula_rows = copula_dt,
    independence_rows = independence_dt,
    pool_result = list(estimate = est, true_sgpc = true_sgpc),
    pool_id = pool_id,
    subgroup_id = sg_id,
    sg_idx = sg_idx,
    pool_type = pool_type,
    eligible_buckets = eligible_buckets,
    seed_base = seed_base + sum(utf8ToInt(pool_id))
  )
}
