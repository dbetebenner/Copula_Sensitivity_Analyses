############################################################################
###
### Export Figure-Ready Data for STEP 3 Phase A
###
### Produces notation-aligned payloads and tidy CSV exports used by:
###   - ggplot diagnostics / publication panels
###   - district summary grade artifact
###   - optional PSTricks real-data mode
###
############################################################################

require(data.table)

# Auto-source sibling dependencies when run standalone
if (!exists("regime_beta", mode = "function")) {
  .epfd_dir <- local({
    for (i in seq_len(sys.nframe())) {
      f <- tryCatch(sys.frame(i)$ofile, error = function(e) NULL)
      if (!is.null(f)) return(dirname(normalizePath(f, mustWork = FALSE)))
    }
    return("")
  })
  if (nzchar(.epfd_dir)) {
    for (.dep in c("regime_families.R", "predict_v_cdf.R",
                   "distance_metrics.R", "copula_kernel_cache.R")) {
      .f <- file.path(.epfd_dir, .dep)
      if (file.exists(.f)) source(.f, local = FALSE)
    }
  }
  rm(list = c(".epfd_dir", ".dep", ".f")[c(".epfd_dir", ".dep", ".f") %in%
    ls(envir = environment())], envir = environment())
}

safe_subgroup_id <- function(phase_a_results) {
  paste0(phase_a_results$condition_id, "__", phase_a_results$subgroup_id)
}

extract_regime_grid <- function(est) {
  gs <- est$grid_search
  if (is.null(gs) || nrow(gs) == 0) {
    return(data.table(
      m = numeric(0),
      kappa = numeric(0),
      log10_kappa = numeric(0),
      distance_w1 = numeric(0),
      is_optimum = logical(0)
    ))
  }

  m_col <- if ("m" %in% names(gs)) "m" else if ("regime_param_1" %in% names(gs)) "regime_param_1" else "theta1"
  k_col <- if ("kappa" %in% names(gs)) "kappa" else if ("regime_param_2" %in% names(gs)) "regime_param_2" else if ("theta2" %in% names(gs)) "theta2" else NA_character_
  if (is.na(k_col)) {
    return(data.table(
      m = as.numeric(gs[[m_col]]),
      kappa = NA_real_,
      log10_kappa = NA_real_,
      distance_w1 = as.numeric(gs$distance),
      is_optimum = FALSE
    ))
  }

  dt <- data.table(
    m = as.numeric(gs[[m_col]]),
    kappa = as.numeric(gs[[k_col]]),
    distance_w1 = as.numeric(gs$distance)
  )
  dt[, log10_kappa := log10(kappa)]
  dt[, is_optimum := FALSE]

  if (!is.null(est$m_hat) && !is.null(est$kappa_hat)) {
    idx <- which.min(abs(dt$m - est$m_hat) + abs(dt$kappa - est$kappa_hat))
    if (length(idx) > 0 && is.finite(idx)) dt[idx, is_optimum := TRUE]
  }
  dt[]
}

export_phase_a_figure_data <- function(phase_a_results,
                                       output_dir = "results",
                                       write_files = TRUE) {
  stopifnot(is.list(phase_a_results))

  est <- phase_a_results$best_estimate
  stopifnot(!is.null(est))
  stopifnot(!is.null(est$v_grid), !is.null(est$F_obs), !is.null(est$F_pred))

  subgroup_id <- safe_subgroup_id(phase_a_results)
  kernel_cache <- phase_a_results$kernel_cache
  u_sample <- phase_a_results$u_sample
  v_sample <- phase_a_results$v_sample

  has_kernel <- !is.null(kernel_cache) && inherits(kernel_cache, "kernel_cache")
  has_u <- !is.null(u_sample) && length(u_sample) > 0

  if (has_kernel && has_u) {
    uniform_regime <- regime_beta(0.5, 2)
    F_uniform <- predict_marginal_cdf(
      v_grid = est$v_grid,
      u_sample = u_sample,
      weights = NULL,
      regime = uniform_regime,
      kernel_cache = kernel_cache
    )
  } else {
    message("  kernel_cache or u_sample unavailable; F_uniform set to NA")
    F_uniform <- rep(NA_real_, length(est$v_grid))
  }

  F_tamp <- if (has_u) ecdf(u_sample)(est$v_grid) else rep(NA_real_, length(est$v_grid))
  residual <- est$F_pred - est$F_obs

  cdf_curves <- data.table(
    subgroup_id = subgroup_id,
    v = est$v_grid,
    F_obs = est$F_obs,
    F_pred = est$F_pred,
    F_uniform = F_uniform,
    F_tamp = F_tamp,
    residual = residual
  )

  objective_surface <- extract_regime_grid(est)
  objective_surface[, subgroup_id := subgroup_id]
  setcolorder(objective_surface, c("subgroup_id", "m", "kappa", "log10_kappa", "distance_w1", "is_optimum"))

  p_grid <- seq(0.001, 0.999, length.out = 500)
  density_hat <- est$regime$density(p_grid)
  density_uniform <- rep(1, length(p_grid))
  density_true <- if (!is.null(phase_a_results$true_sgpc)) {
    kd <- density(phase_a_results$true_sgpc / 100, from = 0.001, to = 0.999, n = 500, bw = "SJ")
    approx(kd$x, kd$y, xout = p_grid, rule = 2)$y
  } else {
    rep(NA_real_, length(p_grid))
  }

  regime_density <- data.table(
    subgroup_id = subgroup_id,
    p = p_grid,
    density_hat = density_hat,
    density_uniform = density_uniform,
    density_true = density_true
  )

  w1_uniform <- if (all(is.na(F_uniform))) NA_real_ else wasserstein1(F_uniform, est$F_obs, est$v_grid)
  w1_best <- est$all_distances$wasserstein1
  fit_metrics <- data.table(
    subgroup_id = subgroup_id,
    w1_uniform = w1_uniform,
    w1_best = w1_best,
    w1_reduction_pct = ifelse(isTRUE(w1_uniform > 0), 100 * (1 - (w1_best / w1_uniform)), NA_real_),
    cvm = est$all_distances$cramer_von_mises,
    max_abs_residual = max(abs(residual), na.rm = TRUE),
    mean_abs_residual = mean(abs(residual), na.rm = TRUE)
  )

  boot <- phase_a_results$bootstrap
  bootstrap_draws <- if (!is.null(boot) && !is.null(boot$median_sgpc_draws)) {
    data.table(
      subgroup_id = subgroup_id,
      boot_id = seq_along(boot$median_sgpc_draws),
      m_hat = if (!is.null(boot$m_draws)) boot$m_draws else NA_real_,
      kappa_hat = if (!is.null(boot$kappa_draws)) boot$kappa_draws else NA_real_,
      median_sgpc = boot$median_sgpc_draws,
      mean_sgpc = if (!is.null(boot$mean_sgpc_draws)) boot$mean_sgpc_draws else NA_real_,
      converged = !is.na(boot$median_sgpc_draws)
    )
  } else {
    data.table(
      subgroup_id = character(0),
      boot_id = integer(0),
      m_hat = numeric(0),
      kappa_hat = numeric(0),
      median_sgpc = numeric(0),
      mean_sgpc = numeric(0),
      converged = logical(0)
    )
  }

  bootstrap_summary <- if (!is.null(boot)) {
    data.table(
      subgroup_id = subgroup_id,
      ci95_median_lo = boot$ci_median_sgpc[1],
      ci95_median_hi = boot$ci_median_sgpc[2],
      ci95_mean_lo = boot$ci_mean_sgpc[1],
      ci95_mean_hi = boot$ci_mean_sgpc[2],
      se_median = boot$se_median_sgpc,
      n_boot = boot$n_boot,
      n_converged = boot$n_converged
    )
  } else {
    data.table(
      subgroup_id = subgroup_id,
      ci95_median_lo = NA_real_,
      ci95_median_hi = NA_real_,
      ci95_mean_lo = NA_real_,
      ci95_mean_hi = NA_real_,
      se_median = NA_real_,
      n_boot = NA_integer_,
      n_converged = NA_integer_
    )
  }

  kernel_slices <- data.table()
  quantile_slices <- data.table()
  if (has_kernel && has_u) {
    u_q <- as.numeric(quantile(u_sample, probs = c(0.1, 0.5, 0.9), na.rm = TRUE))
    u_lbl <- c("u_q10", "u_q50", "u_q90")
    for (i in seq_along(u_q)) {
      u_val <- rep(u_q[i], length(est$v_grid))
      kernel_slices <- rbind(
        kernel_slices,
        data.table(
          subgroup_id = subgroup_id,
          slice = u_lbl[i],
          u = u_q[i],
          v = est$v_grid,
          F0 = kernel_conditional_cdf(v = est$v_grid, u = u_val, cache = kernel_cache)
        )
      )
    }
    if (!is.null(kernel_cache$quantile_grid)) {
      p_grid_small <- seq(0.01, 0.99, length.out = 199)
      for (i in seq_along(u_q)) {
        u_val <- rep(u_q[i], length(p_grid_small))
        quantile_slices <- rbind(
          quantile_slices,
          data.table(
            subgroup_id = subgroup_id,
            slice = u_lbl[i],
            u = u_q[i],
            p = p_grid_small,
            Q0 = kernel_conditional_quantile(p = p_grid_small, u = u_val, cache = kernel_cache)
          )
        )
      }
    }
  }

  payload <- list(
    subgroup_id = subgroup_id,
    condition_id = phase_a_results$condition_id,
    dataset_id = phase_a_results$dataset_id,
    subgroup_col = phase_a_results$subgroup_col,
    subgroup_value = phase_a_results$subgroup_id,
    n_subgroup = phase_a_results$n_subgroup,
    assumption = "P_independent_of_U_within_subgroup",
    u_sample = u_sample,
    v_sample = v_sample,
    v_grid = est$v_grid,
    F_obs = est$F_obs,
    F_pred = est$F_pred,
    F_uniform = F_uniform,
    F_tamp = F_tamp,
    fit_metrics = fit_metrics,
    objective_surface = objective_surface,
    kernel_slices = kernel_slices,
    quantile_slices = quantile_slices,
    regime_density = regime_density,
    bootstrap_summary = bootstrap_summary,
    independence_diagnostics = phase_a_results$independence_diagnostics,
    flag_independence_violation = isTRUE(phase_a_results$flag_independence_violation),
    copula_used = phase_a_results$copula_used,
    seed = phase_a_results$config$seed
  )

  if (isTRUE(write_files)) {
    export_dir <- file.path(output_dir, "exports", "phase_a")
    if (!dir.exists(export_dir)) dir.create(export_dir, recursive = TRUE)

    saveRDS(payload, file.path(output_dir, "phase_a_analytic_payload.rds"))
    fwrite(cdf_curves, file.path(export_dir, "step3_cdf_curves.csv"))
    fwrite(objective_surface, file.path(export_dir, "step3_objective_surface.csv"))
    fwrite(regime_density, file.path(export_dir, "step3_regime_density.csv"))
    fwrite(fit_metrics, file.path(export_dir, "step3_fit_metrics.csv"))
    fwrite(bootstrap_draws, file.path(export_dir, "step3_bootstrap_draws.csv"))
    fwrite(bootstrap_summary, file.path(export_dir, "step3_bootstrap_summary.csv"))
    if (!is.null(phase_a_results$independence_diagnostics)) {
      fwrite(as.data.table(phase_a_results$independence_diagnostics), file.path(export_dir, "step3_independence_diagnostics.csv"))
    }
    if (nrow(kernel_slices) > 0) fwrite(kernel_slices, file.path(export_dir, "step3_kernel_slices.csv"))
    if (nrow(quantile_slices) > 0) fwrite(quantile_slices, file.path(export_dir, "step3_quantile_slices.csv"))
  }

  list(
    payload = payload,
    cdf_curves = cdf_curves,
    objective_surface = objective_surface,
    regime_density = regime_density,
    fit_metrics = fit_metrics,
    bootstrap_draws = bootstrap_draws,
    bootstrap_summary = bootstrap_summary,
    kernel_slices = kernel_slices,
    quantile_slices = quantile_slices
  )
}

cat("STEP 3 export_phase_a_figure_data.R loaded.\n")
cat("  Function: export_phase_a_figure_data\n")
