############################################################################
###
### STEP 3 — Phase B: Systematic Validation
###
############################################################################

cat("--- Phase B: Systematic Validation ---\n\n")

############################################################################
### B.0  Configuration
############################################################################

cfg_sys <- STEP3_CONFIG$systematic
cfg_dist <- STEP3_CONFIG$distance
cfg_reg <- STEP3_CONFIG$regime
sg_col <- STEP3_CONFIG$validation$subgroup_col
n_buckets <- sort(unique(as.integer(cfg_sys$n_buckets)))
n_buckets <- n_buckets[is.finite(n_buckets) & n_buckets > 0]
if (length(n_buckets) == 0) n_buckets <- c(1000L, 2500L, 5000L, 7500L, 10000L)
eligibility_buffer <- ifelse(is.null(cfg_sys$eligibility_buffer), 0.10, as.numeric(cfg_sys$eligibility_buffer))
outer_reps <- ifelse(is.null(cfg_sys$outer_reps), 200L, as.integer(cfg_sys$outer_reps))
allow_cluster_pools <- isTRUE(cfg_sys$allow_cluster_pools)
n_growth_strata <- ifelse(is.null(cfg_sys$n_growth_strata), 3L, as.integer(cfg_sys$n_growth_strata))
cluster_min_pool_n <- ifelse(is.null(cfg_sys$cluster_min_pool_n), 500L, as.integer(cfg_sys$cluster_min_pool_n))
use_parallel <- isTRUE(cfg_sys$use_parallel)
parallel_available <- use_parallel && requireNamespace("mirai", quietly = TRUE)
if (use_parallel && !parallel_available) {
  cat("  WARNING: use_parallel=TRUE but `mirai` not available; falling back to sequential.\n")
}

# Results storage
all_results <- list()
summary_rows <- list()
copula_sensitivity_rows <- list()
independence_sensitivity_rows <- list()
pool_registry_rows <- list()
replicate_rows <- list()
row_counter <- 0
copula_counter <- 0
independence_counter <- 0
pool_counter <- 0
rep_counter <- 0
sensitivity_budget <- if (!is.null(STEP3_CONFIG$sensitivity$phase_b_subset_max_subgroups)) {
  as.integer(STEP3_CONFIG$sensitivity$phase_b_subset_max_subgroups)
} else {
  25L
}

process_phaseb_pool_worker <- function(
  pool,
  ds_id,
  condition_id,
  cond,
  pairs,
  refs,
  p1_copula,
  kernel_cache,
  u_full,
  v_full,
  cfg_reg,
  cfg_dist,
  cfg_sys,
  n_buckets,
  eligibility_buffer,
  outer_reps,
  seed_base,
  buckets_cfg,
  enable_copula_sensitivity = TRUE,
  enable_independence_sensitivity = TRUE
) {
  sg_id <- as.character(pool$id)
  sg_idx <- pool$idx
  n_sg <- length(sg_idx)
  if (n_sg < cfg_sys$min_subgroup_n) {
    return(NULL)
  }

  pool_id <- if (!is.null(pool$pool_id)) pool$pool_id else paste0(condition_id, "__", sg_id)
  pool_type <- if (!is.null(pool$pool_type)) pool$pool_type else "district"
  n_pool_raw <- n_sg
  n_pool_eff <- n_sg

  true_sgpc <- sgpc_engine(u_full[sg_idx], v_full[sg_idx], p1_copula, scale = "percentile")
  u_cross <- reference_cdf(pairs$SCALE_SCORE_PRIOR[sg_idx], refs$ref_prior)
  v_cross <- reference_cdf(pairs$SCALE_SCORE_CURRENT[sg_idx], refs$ref_current)

  est <- tryCatch({
    estimate_regime(
      u_cross,
      v_cross,
      kernel_cache,
      regime_family = cfg_reg$primary_family,
      distance_fn = cfg_dist$primary,
      grid_resolution = 20,
      verbose = FALSE
    )
  }, error = function(e) NULL)

  if (is.null(est)) return(NULL)

  uniform_reg <- regime_beta(0.5, 2)
  F_uniform <- tryCatch(
    predict_marginal_cdf(v_grid = est$v_grid, u_sample = u_cross, regime = uniform_reg, kernel_cache = kernel_cache),
    error = function(e) rep(NA_real_, length(est$v_grid))
  )
  w1_uniform <- if (all(is.na(F_uniform))) NA_real_ else wasserstein1(F_uniform, est$F_obs, est$v_grid)
  w1_best <- est$all_distances$wasserstein1
  w1_reduction_pct <- ifelse(is.finite(w1_uniform) && w1_uniform > 0, 100 * (1 - (w1_best / w1_uniform)), NA_real_)
  residual <- est$F_pred - est$F_obs

  summary_row <- data.table(
    dataset_id = ds_id,
    condition_id = condition_id,
    year_span = cond$year_span,
    content_area = cond$content_area,
    subgroup_id = sg_id,
    n_subgroup = n_sg,
    regime_family = cfg_reg$primary_family,
    median_sgpc_inferred = round(est$regime$median * 100, 2),
    mean_sgpc_inferred = round(est$regime$mean * 100, 2),
    median_sgpc_true = round(median(true_sgpc, na.rm = TRUE), 2),
    mean_sgpc_true = round(mean(true_sgpc, na.rm = TRUE), 2),
    median_diff = round(est$regime$median * 100 - median(true_sgpc, na.rm = TRUE), 2),
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
    regime_param_2 = if (length(est$regime_param_hat) > 1) round(est$regime_param_hat[2], 4) else NA_real_,
    m_hat = round(est$m_hat, 4),
    kappa_hat = round(est$kappa_hat, 4)
  )

  pool_registry <- data.table(
    pool_id = pool_id,
    pool_type = pool_type,
    span = cond$year_span,
    content = cond$content_area,
    dataset_id = ds_id,
    condition_id = condition_id,
    subgroup_id = sg_id,
    n_pool_raw = n_pool_raw,
    n_pool_eff = n_pool_eff,
    eligibility_buffer = eligibility_buffer,
    strata_label = if (!is.null(pool$strata_label)) as.character(pool$strata_label) else NA_character_,
    n_constituent_districts = if (!is.null(pool$n_constituent_districts)) as.integer(pool$n_constituent_districts) else 1L,
    constituent_districts = if (!is.null(pool$constituent_districts)) as.character(pool$constituent_districts) else as.character(sg_id)
  )

  rep_rows <- list()
  rep_i <- 0L
  eligible_buckets <- n_buckets[n_pool_raw >= (n_buckets * (1 + eligibility_buffer))]
  if (length(eligible_buckets) > 0) {
    pool_seed_base <- seed_base + sum(utf8ToInt(pool_id))
    for (n_bucket in eligible_buckets) {
      for (rep_idx in seq_len(outer_reps)) {
        set.seed(pool_seed_base + as.integer(n_bucket) * 1000L + rep_idx)
        rep_obs_idx <- sample(sg_idx, size = as.integer(n_bucket), replace = FALSE)
        true_rep <- sgpc_engine(u_full[rep_obs_idx], v_full[rep_obs_idx], p1_copula, scale = "percentile")
        u_rep <- reference_cdf(pairs$SCALE_SCORE_PRIOR[rep_obs_idx], refs$ref_prior)
        v_rep <- reference_cdf(pairs$SCALE_SCORE_CURRENT[rep_obs_idx], refs$ref_current)

        est_rep <- tryCatch(
          estimate_regime(
            u_sample = u_rep,
            v_sample = v_rep,
            kernel_cache = kernel_cache,
            regime_family = cfg_reg$primary_family,
            distance_fn = cfg_dist$primary,
            grid_resolution = 15,
            verbose = FALSE
          ),
          error = function(e) NULL
        )

        true_median <- median(true_rep, na.rm = TRUE)
        true_mean <- mean(true_rep, na.rm = TRUE)
        if (is.null(est_rep)) {
          inferred_median <- NA_real_
          inferred_mean <- NA_real_
          median_error <- NA_real_
          mean_error <- NA_real_
          converged <- FALSE
        } else {
          inferred_median <- as.numeric(est_rep$regime$median) * 100
          inferred_mean <- as.numeric(est_rep$regime$mean) * 100
          median_error <- inferred_median - true_median
          mean_error <- inferred_mean - true_mean
          converged <- TRUE
        }

        rep_i <- rep_i + 1L
        rep_rows[[rep_i]] <- data.table(
          pool_id = pool_id,
          pool_type = pool_type,
          span = cond$year_span,
          content = cond$content_area,
          dataset_id = ds_id,
          condition_id = condition_id,
          subgroup_id = sg_id,
          n_bucket = as.integer(n_bucket),
          n_eff_bucket = as.numeric(n_bucket),
          outer_rep = rep_idx,
          converged = converged,
          inferred_median = inferred_median,
          inferred_mean = inferred_mean,
          true_median = true_median,
          true_mean = true_mean,
          median_error = median_error,
          mean_error = mean_error,
          abs_median_error = abs(median_error),
          abs_mean_error = abs(mean_error)
        )
      }
    }
  }
  replicate_dt <- if (length(rep_rows) > 0) rbindlist(rep_rows, fill = TRUE) else data.table()

  copula_dt <- data.table()
  if (isTRUE(enable_copula_sensitivity)) {
    cop_rows <- list()
    cop_i <- 0L
    base_rho <- tryCatch(as.numeric(p1_copula@param[1]), error = function(e) NA_real_)
    base_df <- tryCatch(as.numeric(p1_copula@df), error = function(e) NA_real_)
    rho_variants <- unique(c(base_rho, base_rho - 0.10, base_rho + 0.10))
    rho_variants <- pmax(-0.95, pmin(0.95, rho_variants))
    if (all(is.na(rho_variants))) rho_variants <- 0.6
    df_variants <- if (is.finite(base_df)) unique(c(base_df, pmax(2, base_df - 3), base_df + 3)) else c(8)

    for (rv in rho_variants) {
      for (dv in df_variants) {
        cop <- tryCatch(copula::tCopula(param = rv, df = dv, dispstr = "un"), error = function(e) NULL)
        if (is.null(cop)) next
        kc_var <- tryCatch(create_kernel_cache(cop, u_grid_size = 101, v_grid_size = 101, compute_quantile = FALSE), error = function(e) NULL)
        if (is.null(kc_var)) next
        est_var <- tryCatch(
          estimate_regime(
            u_sample = u_cross,
            v_sample = v_cross,
            kernel_cache = kc_var,
            regime_family = cfg_reg$primary_family,
            distance_fn = cfg_dist$primary,
            grid_resolution = 15,
            verbose = FALSE
          ),
          error = function(e) NULL
        )
        if (is.null(est_var)) next

        cop_i <- cop_i + 1L
        cop_rows[[cop_i]] <- data.table(
          dataset_id = ds_id,
          condition_id = condition_id,
          subgroup_id = sg_id,
          n_subgroup = n_sg,
          copula_family = "t",
          rho = round(rv, 4),
          df = round(dv, 3),
          median_sgpc = round(est_var$regime$median * 100, 3),
          mean_sgpc = round(est_var$regime$mean * 100, 3),
          delta_median_vs_base = round((est_var$regime$median - est$regime$median) * 100, 3),
          delta_mean_vs_base = round((est_var$regime$mean - est$regime$mean) * 100, 3),
          w1 = round(est_var$all_distances$wasserstein1, 6),
          cvm = round(est_var$all_distances$cramer_von_mises, 6)
        )
      }
    }
    if (length(cop_rows) > 0) copula_dt <- rbindlist(cop_rows, fill = TRUE)
  }

  independence_dt <- data.table()
  if (isTRUE(enable_independence_sensitivity)) {
    strat_fit <- tryCatch(
      estimate_regime(
        u_sample = u_cross,
        v_sample = v_cross,
        kernel_cache = kernel_cache,
        regime_family = cfg_reg$primary_family,
        distance_fn = cfg_dist$primary,
        grid_resolution = 15,
        verbose = FALSE,
        stratify_by_u = TRUE,
        stratify_bins = cfg_reg$stratify_bins
      ),
      error = function(e) NULL
    )
    if (!is.null(strat_fit)) {
      base_k3 <- classify_bucket(est$regime$median * 100, k = 3, cutpoints = buckets_cfg$k3)$assigned_bucket
      strat_k3 <- classify_bucket(strat_fit$median_sgpc, k = 3, cutpoints = buckets_cfg$k3)$assigned_bucket
      base_k5 <- classify_bucket(est$regime$median * 100, k = 5, cutpoints = buckets_cfg$k5)$assigned_bucket
      strat_k5 <- classify_bucket(strat_fit$median_sgpc, k = 5, cutpoints = buckets_cfg$k5)$assigned_bucket
      independence_dt <- data.table(
        dataset_id = ds_id,
        condition_id = condition_id,
        subgroup_id = sg_id,
        n_subgroup = n_sg,
        n_bins = length(strat_fit$bins),
        w1_single = round(est$all_distances$wasserstein1, 6),
        w1_stratified = round(strat_fit$all_distances$wasserstein1, 6),
        cvm_single = round(est$all_distances$cramer_von_mises, 6),
        cvm_stratified = round(strat_fit$all_distances$cramer_von_mises, 6),
        delta_median = round(strat_fit$median_sgpc - est$regime$median * 100, 3),
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

  list(
    summary_row = summary_row,
    pool_registry = pool_registry,
    replicate_rows = replicate_dt,
    copula_rows = copula_dt,
    independence_rows = independence_dt,
    pool_result = list(estimate = est, true_sgpc = true_sgpc),
    pool_id = pool_id,
    subgroup_id = sg_id
  )
}

############################################################################
### B.1  Loop Over Datasets and Conditions
############################################################################

for (ds_id in cfg_sys$datasets) {

  cat("================================================================\n")
  cat("Dataset:", ds_id, "\n")
  cat("================================================================\n\n")

  ds_config <- DATASETS[[ds_id]]
  if (is.null(ds_config)) {
    cat("  WARNING: Dataset '", ds_id, "' not in DATASETS. Skipping.\n\n")
    next
  }

  data_path <- ds_config$local_path
  if (!file.exists(data_path)) data_path <- ds_config$ec2_path
  if (!file.exists(data_path)) {
    cat("  WARNING: Data file not found. Skipping.\n\n")
    next
  }

  cat("  Loading data from:", data_path, "\n")
  load(data_path)
  state_data_name <- ds_config$rdata_object_name
  if (exists(state_data_name)) {
    STATE_DATA <- get(state_data_name)
  } else {
    dt_names <- ls()[sapply(ls(), function(x) is.data.table(get(x)))]
    STATE_DATA <- get(dt_names[which.max(sapply(dt_names, function(x) nrow(get(x))))])
  }
  cat("  Loaded:", format(nrow(STATE_DATA), big.mark = ","), "rows\n")

  conditions_all <- get_phase1_conditions(ds_id)
  if (length(conditions_all) == 0) {
    cat("  WARNING: No Phase 1 conditions found. Skipping.\n\n")
    next
  }

  cond_metas <- lapply(conditions_all, parse_condition_id)
  cond_spans <- sapply(cond_metas, `[[`, "year_span")
  cond_content <- sapply(cond_metas, `[[`, "content_area")

  if (!is.null(cfg_sys$year_spans)) {
    keep <- cond_spans %in% cfg_sys$year_spans
    conditions_all <- conditions_all[keep]
    cond_spans <- cond_spans[keep]
    cond_content <- cond_content[keep]
  }

  if (!is.null(cfg_sys$content_areas)) {
    keep <- cond_content %in% cfg_sys$content_areas
    conditions_all <- conditions_all[keep]
    cond_spans <- cond_spans[keep]
  }

  n_conds <- min(length(conditions_all), cfg_sys$n_conditions_per_dataset)
  if (length(conditions_all) > n_conds) {
    sampled_idx <- c()
    for (sp in unique(cond_spans)) {
      sp_idx <- which(cond_spans == sp)
      n_pick <- max(1, round(n_conds * length(sp_idx) / length(cond_spans)))
      sampled_idx <- c(sampled_idx, sample(sp_idx, min(n_pick, length(sp_idx))))
    }
    sampled_idx <- head(sampled_idx, n_conds)
    conditions <- conditions_all[sampled_idx]
  } else {
    conditions <- conditions_all
  }

  cat("  Selected", length(conditions), "conditions for validation\n\n")
  canonical <- tryCatch(load_canonical_parameters(), error = function(e) NULL)

  for (ci in seq_along(conditions)) {
    condition_id <- conditions[ci]
    cond <- parse_condition_id(condition_id)
    cat("  Condition", ci, "/", length(conditions), ":", condition_id, "\n")

    year_prior <- as.character(as.numeric(cond$year_current) - cond$year_span)
    pairs <- tryCatch({
      create_longitudinal_pairs(
        data = STATE_DATA,
        grade_prior = cond$grade_prior,
        grade_current = cond$grade_current,
        year_prior = year_prior,
        year_current = cond$year_current,
        content_prior = cond$content_area
      )
    }, error = function(e) {
      cat("    ERROR extracting pairs:", e$message, "\n")
      NULL
    })

    if (is.null(pairs) || nrow(pairs) < 50) {
      cat("    Insufficient pairs (n =", ifelse(is.null(pairs), 0, nrow(pairs)), "). Skipping.\n")
      next
    }

    refs <- tryCatch(
      build_condition_reference(STATE_DATA, cond),
      error = function(e) { cat("    ERROR building refs:", e$message, "\n"); NULL }
    )
    if (is.null(refs)) next

    p1 <- tryCatch(load_phase1_condition(ds_id, condition_id), error = function(e) NULL)
    if (is.null(p1) || is.null(p1$best_fit_copula)) {
      if (!is.null(canonical)) {
        p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
      } else {
        cat("    No copula available. Skipping.\n")
        next
      }
    } else {
      p1_copula <- p1$best_fit_copula
    }

    kernel_cache <- tryCatch(
      create_kernel_cache(p1_copula, u_grid_size = 101, v_grid_size = 101, compute_quantile = FALSE),
      error = function(e) { cat("    ERROR building kernel:", e$message, "\n"); NULL }
    )
    if (is.null(kernel_cache)) next

    u_full <- rank(pairs$SCALE_SCORE_PRIOR) / (nrow(pairs) + 1)
    v_full <- rank(pairs$SCALE_SCORE_CURRENT) / (nrow(pairs) + 1)

    district_pools <- list()
    if (sg_col %in% names(pairs)) {
      sg_table <- pairs[, .N, by = sg_col][N >= cfg_sys$min_subgroup_n][order(-N)]
      n_sg <- min(nrow(sg_table), cfg_sys$n_subgroups_per_condition)
      if (n_sg == 0) {
        district_pools <- list(list(
          id = "ALL",
          idx = seq_len(nrow(pairs)),
          pool_id = paste0(condition_id, "__ALL"),
          pool_type = "district",
          constituent_districts = "ALL",
          n_constituent_districts = 1L
        ))
      } else {
        district_pools <- lapply(seq_len(n_sg), function(j) {
          sg_id <- as.character(sg_table[[sg_col]][j])
          idx <- which(pairs[[sg_col]] == sg_id)
          list(
            id = sg_id,
            idx = idx,
            pool_id = paste0(condition_id, "__", sg_id),
            pool_type = "district",
            constituent_districts = sg_id,
            n_constituent_districts = 1L
          )
        })
      }
    } else {
      district_pools <- list(list(
        id = "ALL",
        idx = seq_len(nrow(pairs)),
        pool_id = paste0(condition_id, "__ALL"),
        pool_type = "district",
        constituent_districts = "ALL",
        n_constituent_districts = 1L
      ))
    }

    cluster_pools <- list()
    if (allow_cluster_pools && (sg_col %in% names(pairs))) {
      cluster_build <- tryCatch(
        build_cluster_pools(
          pairs = pairs,
          sg_col = sg_col,
          u_full = u_full,
          v_full = v_full,
          p1_copula = p1_copula,
          condition_id = condition_id,
          n_growth_strata = n_growth_strata,
          min_pool_n = cluster_min_pool_n
        ),
        error = function(e) {
          cat("    WARNING: cluster pool build failed:", e$message, "\n")
          NULL
        }
      )
      if (!is.null(cluster_build) && length(cluster_build$pools) > 0) {
        cluster_pools <- cluster_build$pools
      }
    }

    subgroups <- c(district_pools, cluster_pools)
    cat("    Pools prepared:", length(subgroups),
        "(district =", length(district_pools),
        ", cluster =", length(cluster_pools), ")\n")
    if (length(subgroups) == 0) next

    pool_results <- list()
    if (parallel_available && length(subgroups) > 1) {
      n_workers <- max(1L, min(length(subgroups), as.integer(parallel::detectCores(logical = TRUE) - 1L)))
      if (!is.finite(n_workers) || n_workers < 1L) n_workers <- 1L
      cat("    Running pools in parallel with mirai workers:", n_workers, "\n")

      PROJECT_ROOT_ABS <- if (exists("PROJECT_ROOT", inherits = TRUE)) {
        normalizePath(PROJECT_ROOT, mustWork = TRUE)
      } else {
        normalizePath(getwd(), mustWork = TRUE)
      }
      STEP3_ROOT_ABS <- if (exists("STEP3_ROOT", inherits = TRUE)) {
        normalizePath(STEP3_ROOT, mustWork = TRUE)
      } else {
        normalizePath(file.path(PROJECT_ROOT_ABS, "STEP_3_LIwLD"), mustWork = TRUE)
      }

      mirai::daemons(n = n_workers, dispatcher = FALSE)
      init_ok <- tryCatch({
        init_workers <- mirai::everywhere({
          suppressPackageStartupMessages({
            library(data.table)
            library(copula)
          })
          setwd(PROJECT_ROOT_ABS)
          source(file.path(PROJECT_ROOT_ABS, "functions/sgpc_engine.R"))
          source(file.path(STEP3_ROOT_ABS, "functions/reference_marginals.R"))
          source(file.path(STEP3_ROOT_ABS, "functions/copula_kernel_cache.R"))
          source(file.path(STEP3_ROOT_ABS, "functions/regime_families.R"))
          source(file.path(STEP3_ROOT_ABS, "functions/predict_v_cdf.R"))
          source(file.path(STEP3_ROOT_ABS, "functions/distance_metrics.R"))
          source(file.path(STEP3_ROOT_ABS, "functions/optimize_regime.R"))
          source(file.path(STEP3_ROOT_ABS, "functions/bucket_classification.R"))
          TRUE
        }, PROJECT_ROOT_ABS = PROJECT_ROOT_ABS, STEP3_ROOT_ABS = STEP3_ROOT_ABS)
        init_vals <- init_workers[]
        all(vapply(init_vals, isTRUE, logical(1)))
      }, error = function(e) FALSE)

      if (isTRUE(init_ok)) {
        mirai_results <- mirai::mirai_map(
          .x = subgroups,
          .f = function(pool, worker_fn, ds_id, condition_id, cond, pairs, refs, p1_copula, kernel_cache, u_full, v_full, cfg_reg, cfg_dist, cfg_sys, n_buckets, eligibility_buffer, outer_reps, seed_base, buckets_cfg) {
            worker_fn(
              pool = pool,
              ds_id = ds_id,
              condition_id = condition_id,
              cond = cond,
              pairs = pairs,
              refs = refs,
              p1_copula = p1_copula,
              kernel_cache = kernel_cache,
              u_full = u_full,
              v_full = v_full,
              cfg_reg = cfg_reg,
              cfg_dist = cfg_dist,
              cfg_sys = cfg_sys,
              n_buckets = n_buckets,
              eligibility_buffer = eligibility_buffer,
              outer_reps = outer_reps,
              seed_base = seed_base,
              buckets_cfg = buckets_cfg,
              enable_copula_sensitivity = identical(pool$pool_type, "district"),
              enable_independence_sensitivity = identical(pool$pool_type, "district")
            )
          },
          .args = list(
            worker_fn = process_phaseb_pool_worker,
            ds_id = ds_id,
            condition_id = condition_id,
            cond = cond,
            pairs = pairs,
            refs = refs,
            p1_copula = p1_copula,
            kernel_cache = kernel_cache,
            u_full = u_full,
            v_full = v_full,
            cfg_reg = cfg_reg,
            cfg_dist = cfg_dist,
            cfg_sys = cfg_sys,
            n_buckets = n_buckets,
            eligibility_buffer = eligibility_buffer,
            outer_reps = outer_reps,
            seed_base = STEP3_CONFIG$seed,
            buckets_cfg = STEP3_CONFIG$buckets
          )
        )
        pool_results <- mirai_results[]
      } else {
        cat("    WARNING: mirai worker init failed; falling back to sequential for this condition.\n")
      }
      mirai::daemons(0)
    }

    if (length(pool_results) == 0) {
      pool_results <- lapply(subgroups, function(pool) {
        process_phaseb_pool_worker(
          pool = pool,
          ds_id = ds_id,
          condition_id = condition_id,
          cond = cond,
          pairs = pairs,
          refs = refs,
          p1_copula = p1_copula,
          kernel_cache = kernel_cache,
          u_full = u_full,
          v_full = v_full,
          cfg_reg = cfg_reg,
          cfg_dist = cfg_dist,
          cfg_sys = cfg_sys,
          n_buckets = n_buckets,
          eligibility_buffer = eligibility_buffer,
          outer_reps = outer_reps,
          seed_base = STEP3_CONFIG$seed,
          buckets_cfg = STEP3_CONFIG$buckets,
          enable_copula_sensitivity = identical(pool$pool_type, "district"),
          enable_independence_sensitivity = identical(pool$pool_type, "district")
        )
      })
    }

    n_processed <- 0L
    for (res in pool_results) {
      if (is.null(res) || inherits(res, "miraiError") || inherits(res, "errorValue")) next

      row_counter <- row_counter + 1L
      summary_rows[[row_counter]] <- res$summary_row
      pool_counter <- pool_counter + 1L
      pool_registry_rows[[pool_counter]] <- res$pool_registry
      if (nrow(res$replicate_rows) > 0) {
        rep_counter <- rep_counter + 1L
        replicate_rows[[rep_counter]] <- res$replicate_rows
      }
      if (nrow(res$copula_rows) > 0 && copula_counter < sensitivity_budget) {
        copula_counter <- copula_counter + 1L
        copula_sensitivity_rows[[copula_counter]] <- res$copula_rows
      }
      if (nrow(res$independence_rows) > 0 && independence_counter < sensitivity_budget) {
        independence_counter <- independence_counter + 1L
        independence_sensitivity_rows[[independence_counter]] <- res$independence_rows
      }
      all_results[[res$pool_id]] <- res$pool_result
      n_processed <- n_processed + 1L
    }

    cat("    ", n_processed, "pools processed\n")
  }

  rm(STATE_DATA)
  gc(verbose = FALSE)
}

############################################################################
### B.2  Compile and Save Results
############################################################################

cat("\n================================================================\n")
cat("Compiling Phase B results...\n")
cat("================================================================\n\n")

if (length(summary_rows) > 0) {
  phase_b_summary <- rbindlist(summary_rows, fill = TRUE)
  phase_b_pool_registry <- if (length(pool_registry_rows) > 0) unique(rbindlist(pool_registry_rows, fill = TRUE)) else data.table()
  phase_b_replicates <- if (length(replicate_rows) > 0) rbindlist(replicate_rows, fill = TRUE) else data.table()

  cat("Total subgroups estimated:", nrow(phase_b_summary), "\n")
  cat("Conditions covered:", length(unique(phase_b_summary$condition_id)), "\n")
  cat("Total pools registered:", nrow(phase_b_pool_registry), "\n")
  cat("Total Phase B replicates:", nrow(phase_b_replicates), "\n")

  cat("\n--- Recovery Accuracy Summary ---\n")
  cat("Median of |median_diff|:", round(median(abs(phase_b_summary$median_diff)), 2), "SGP points\n")
  cat("Mean of |median_diff|:", round(mean(abs(phase_b_summary$median_diff)), 2), "SGP points\n")
  cat("Median of |mean_diff|:", round(median(abs(phase_b_summary$mean_diff)), 2), "SGP points\n")
  cat("Mean of |mean_diff|:", round(mean(abs(phase_b_summary$mean_diff)), 2), "SGP points\n")
  cat("90th percentile of |median_diff|:", round(quantile(abs(phase_b_summary$median_diff), 0.90), 2), "SGP points\n")
  cat("90th percentile of |mean_diff|:", round(quantile(abs(phase_b_summary$mean_diff), 0.90), 2), "SGP points\n")

  if ("year_span" %in% names(phase_b_summary)) {
    cat("\n--- By Year Span ---\n")
    by_span <- phase_b_summary[, .(
      n_subgroups = .N,
      median_abs_diff = round(median(abs(median_diff)), 2),
      mean_abs_diff = round(mean(abs(median_diff)), 2),
      median_abs_mean_diff = round(median(abs(mean_diff)), 2),
      mean_abs_mean_diff = round(mean(abs(mean_diff)), 2),
      median_W1 = round(median(wasserstein1), 6)
    ), by = year_span][order(year_span)]
    print(by_span)
  }

  cat("\n--- By Subgroup Size ---\n")
  phase_b_summary[, size_bin := cut(
    n_subgroup,
    breaks = c(0, 100, 200, 500, 1000, Inf),
    labels = c("50-99", "100-199", "200-499", "500-999", "1000+"),
    right = FALSE
  )]
  by_size <- phase_b_summary[, .(
    n_subgroups = .N,
    median_abs_diff = round(median(abs(median_diff)), 2),
    mean_abs_diff = round(mean(abs(median_diff)), 2),
    median_abs_mean_diff = round(median(abs(mean_diff)), 2),
    mean_abs_mean_diff = round(mean(abs(mean_diff)), 2)
  ), by = size_bin][order(size_bin)]
  print(by_size)

  fwrite(phase_b_summary, file.path(RESULTS_DIR, "phase_b_systematic_summary.csv"))
  fwrite(phase_b_pool_registry, file.path(RESULTS_DIR, "phase_b_pool_registry.csv"))
  save(phase_b_replicates, file = file.path(RESULTS_DIR, "phase_b_replicates.RData"))

  if (nrow(phase_b_replicates) > 0) {
    phase_b_precision_by_n <- phase_b_replicates[, .(
      n_reps = .N,
      n_converged = sum(converged, na.rm = TRUE),
      N_eff_bucket = round(median(n_eff_bucket, na.rm = TRUE), 2),
      median_bias = round(mean(median_error[converged %in% TRUE], na.rm = TRUE), 4),
      median_mae = round(mean(abs_median_error[converged %in% TRUE], na.rm = TRUE), 4),
      median_rmse = round(sqrt(mean((median_error[converged %in% TRUE])^2, na.rm = TRUE)), 4),
      median_ci_width_90 = round(
        quantile(inferred_median[converged %in% TRUE], 0.95, na.rm = TRUE) -
          quantile(inferred_median[converged %in% TRUE], 0.05, na.rm = TRUE), 4
      ),
      median_ci_width_95 = round(
        quantile(inferred_median[converged %in% TRUE], 0.975, na.rm = TRUE) -
          quantile(inferred_median[converged %in% TRUE], 0.025, na.rm = TRUE), 4
      ),
      mean_bias = round(mean(mean_error[converged %in% TRUE], na.rm = TRUE), 4),
      mean_mae = round(mean(abs_mean_error[converged %in% TRUE], na.rm = TRUE), 4),
      mean_rmse = round(sqrt(mean((mean_error[converged %in% TRUE])^2, na.rm = TRUE)), 4),
      mean_ci_width_90 = round(
        quantile(inferred_mean[converged %in% TRUE], 0.95, na.rm = TRUE) -
          quantile(inferred_mean[converged %in% TRUE], 0.05, na.rm = TRUE), 4
      ),
      mean_ci_width_95 = round(
        quantile(inferred_mean[converged %in% TRUE], 0.975, na.rm = TRUE) -
          quantile(inferred_mean[converged %in% TRUE], 0.025, na.rm = TRUE), 4
      )
    ), by = .(pool_id, pool_type, span, content, n_bucket)]
  } else {
    phase_b_precision_by_n <- data.table(
      pool_id = character(),
      pool_type = character(),
      span = integer(),
      content = character(),
      n_bucket = integer(),
      n_reps = integer(),
      n_converged = integer(),
      N_eff_bucket = numeric(),
      median_bias = numeric(),
      median_mae = numeric(),
      median_rmse = numeric(),
      median_ci_width_90 = numeric(),
      median_ci_width_95 = numeric(),
      mean_bias = numeric(),
      mean_mae = numeric(),
      mean_rmse = numeric(),
      mean_ci_width_90 = numeric(),
      mean_ci_width_95 = numeric()
    )
  }
  fwrite(phase_b_precision_by_n, file.path(RESULTS_DIR, "phase_b_precision_by_n.csv"))

  saveRDS(all_results, file.path(RESULTS_DIR, "phase_b_all_results.rds"))
  phase_b_copula_sensitivity <- if (length(copula_sensitivity_rows) > 0) rbindlist(copula_sensitivity_rows, fill = TRUE) else data.table()
  phase_b_independence_sensitivity <- if (length(independence_sensitivity_rows) > 0) rbindlist(independence_sensitivity_rows, fill = TRUE) else data.table()
  fwrite(phase_b_copula_sensitivity, file.path(RESULTS_DIR, "phase_b_copula_sensitivity.csv"))
  fwrite(phase_b_independence_sensitivity, file.path(RESULTS_DIR, "phase_b_independence_sensitivity.csv"))

  cat("\n  Saved: phase_b_systematic_summary.csv, phase_b_pool_registry.csv, phase_b_precision_by_n.csv\n")
  cat("  Saved: phase_b_replicates.RData, phase_b_all_results.rds\n")
  cat("  Saved: phase_b_copula_sensitivity.csv, phase_b_independence_sensitivity.csv\n")
} else {
  cat("No results to compile.\n")
  phase_b_summary <- data.table()
}

cat("\n--- Phase B complete ---\n\n")
