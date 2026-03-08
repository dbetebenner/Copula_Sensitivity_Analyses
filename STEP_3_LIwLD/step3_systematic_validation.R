############################################################################
###
### STEP 3 — Phase B: Systematic Validation
###
### Parallelization Architecture (Two-Stage):
###
###   Stage 1  — Pool setup (sequential, main process)
###              Full-pool regime estimation, copula/independence sensitivity,
###              summary row, pool registry.
###
###   Stage 2  — Replicate batches (parallel via mirai_map)
###              Flat task list: pool x bucket x rep_batch
###              Each task = rep_batch_size estimations (default 25)
###              Condition data pushed once via everywhere() before dispatch.
###
###   Daemon lifecycle (follows STEP 1 pattern):
###              - Created ONCE before the dataset loop
###              - Packages/functions loaded ONCE via everywhere()
###              - Condition data refreshed per condition via everywhere()
###              - Destroyed ONCE after all conditions complete
###
############################################################################

phaseb_start_time <- Sys.time()
cat("--- Phase B: Systematic Validation ---\n\n")

# Null-coalescing operator (defensive — may already be defined upstream)
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}

############################################################################
### B.0  Configuration
############################################################################

cfg_sys   <- STEP3_CONFIG$systematic
cfg_dist  <- STEP3_CONFIG$distance
cfg_reg   <- STEP3_CONFIG$regime
sg_col    <- STEP3_CONFIG$validation$subgroup_col

n_buckets <- sort(unique(as.integer(cfg_sys$n_buckets)))
n_buckets <- n_buckets[is.finite(n_buckets) & n_buckets > 0]
if (length(n_buckets) == 0) n_buckets <- c(1000L, 2500L, 5000L, 7500L, 10000L)

eligibility_buffer  <- ifelse(is.null(cfg_sys$eligibility_buffer),  0.10,  as.numeric(cfg_sys$eligibility_buffer))
outer_reps          <- ifelse(is.null(cfg_sys$outer_reps),           200L,  as.integer(cfg_sys$outer_reps))
rep_batch_size      <- ifelse(is.null(cfg_sys$rep_batch_size),        25L,  as.integer(cfg_sys$rep_batch_size))
allow_cluster_pools <- isTRUE(cfg_sys$allow_cluster_pools)
n_growth_strata     <- ifelse(is.null(cfg_sys$n_growth_strata),        3L,  as.integer(cfg_sys$n_growth_strata))
cluster_min_pool_n  <- ifelse(is.null(cfg_sys$cluster_min_pool_n),   500L,  as.integer(cfg_sys$cluster_min_pool_n))
use_parallel        <- isTRUE(cfg_sys$use_parallel)
seed_base           <- as.integer(STEP3_CONFIG$seed)

sensitivity_budget <- if (!is.null(STEP3_CONFIG$sensitivity$phase_b_subset_max_subgroups)) {
  as.integer(STEP3_CONFIG$sensitivity$phase_b_subset_max_subgroups)
} else {
  25L
}

# Resolve absolute paths once (daemons start in home dir)
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
RESULTS_DIR_ABS <- normalizePath(RESULTS_DIR, mustWork = FALSE)

# Progress file (tail-able from another SSH session)
phaseb_progress_file <- file.path(RESULTS_DIR_ABS, ".phase_b_progress.txt")
dir.create(RESULTS_DIR_ABS, showWarnings = FALSE, recursive = TRUE)

.plog <- function(..., ts = TRUE) {
  msg <- paste0(...)
  if (ts) msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", msg)
  cat(msg, "\n")
  cat(msg, "\n", file = phaseb_progress_file, append = TRUE)
}

# Initialise progress file header
cat(paste(rep("=", 70), collapse = ""), "\n",
    file = phaseb_progress_file, append = FALSE)
cat("PHASE B: Systematic Validation — Progress Log\n",
    file = phaseb_progress_file, append = TRUE)
cat(paste(rep("=", 70), collapse = ""), "\n",
    file = phaseb_progress_file, append = TRUE)
cat("Started:", format(phaseb_start_time, "%Y-%m-%d %H:%M:%S"), "\n",
    file = phaseb_progress_file, append = TRUE)
n_cores_total <- parallel::detectCores(logical = TRUE)
cat("CPUs available:", n_cores_total, "\n",
    file = phaseb_progress_file, append = TRUE)
cat("outer_reps:", outer_reps,
    "| rep_batch_size:", rep_batch_size,
    "| n_buckets:", paste(n_buckets, collapse = ","), "\n",
    file = phaseb_progress_file, append = TRUE)
cat("Monitor: tail -f", phaseb_progress_file, "\n",
    file = phaseb_progress_file, append = TRUE)
cat(paste(rep("=", 70), collapse = ""), "\n\n",
    file = phaseb_progress_file, append = TRUE)

# Results storage
all_results               <- list()
summary_rows              <- list()
copula_sensitivity_rows   <- list()
independence_sensitivity_rows <- list()
pool_registry_rows        <- list()
replicate_rows            <- list()
row_counter               <- 0L
copula_counter            <- 0L
independence_counter      <- 0L
pool_counter              <- 0L
rep_counter               <- 0L

############################################################################
### B.1  Daemon Initialisation (ONCE — follows STEP 1 lifecycle)
############################################################################

parallel_available <- use_parallel && requireNamespace("mirai", quietly = TRUE)
if (use_parallel && !parallel_available) {
  .plog("  WARNING: use_parallel=TRUE but `mirai` not available; falling back to sequential.")
}

b1_daemons_live <- FALSE   # track whether daemons are up

if (parallel_available) {
  # EC2-aware worker count (matches STEP 1 lines 72-85)
  if (n_cores_total <= 48L) {
    n_workers <- n_cores_total - 2L
  } else {
    n_workers <- n_cores_total - 4L
  }
  n_workers <- max(2L, as.integer(n_workers))

  .plog("Initialising ", n_workers, " mirai daemons (", n_cores_total, " CPUs available)...")
  cat("  Progress file: tail -f", phaseb_progress_file, "\n")

  daemon_ok <- tryCatch({
    mirai::daemons(n = n_workers, output = TRUE, retry = FALSE)
    TRUE
  }, error = function(e) {
    .plog("  ERROR: daemon creation failed: ", e$message)
    FALSE
  })

  if (daemon_ok) {
    # ---- Phase 1 everywhere(): packages, functions, thread management ----
    .plog("  Initialising packages and functions on all daemons...")

    init_pkgs <- mirai::everywhere({
      cat("[DAEMON", Sys.getpid(), "] init at", format(Sys.time(), "%H:%M:%S"), "\n")
      tryCatch({
        setwd(PROJECT_ROOT_ABS)
      }, error = function(e) {
        cat("[DAEMON", Sys.getpid(), "] setwd failed:", conditionMessage(e), "\n")
        stop(e)
      })
      suppressPackageStartupMessages({
        library(data.table)
        library(copula)
      })
      # CRITICAL: single-threaded per daemon to prevent CPU oversubscription
      # (same pattern as STEP 1 lines 315-324)
      data.table::setDTthreads(1L)
      Sys.setenv(
        OMP_NUM_THREADS        = "1",
        MKL_NUM_THREADS        = "1",
        OPENBLAS_NUM_THREADS   = "1",
        VECLIB_MAXIMUM_THREADS = "1",
        NUMEXPR_NUM_THREADS    = "1"
      )
      # Source all required function files
      for (ff in c(
        file.path(PROJECT_ROOT_ABS, "functions/sgpc_engine.R"),
        file.path(STEP3_ROOT_ABS,   "functions/reference_marginals.R"),
        file.path(STEP3_ROOT_ABS,   "functions/copula_kernel_cache.R"),
        file.path(STEP3_ROOT_ABS,   "functions/regime_families.R"),
        file.path(STEP3_ROOT_ABS,   "functions/predict_v_cdf.R"),
        file.path(STEP3_ROOT_ABS,   "functions/distance_metrics.R"),
        file.path(STEP3_ROOT_ABS,   "functions/optimize_regime.R"),
        file.path(STEP3_ROOT_ABS,   "functions/bucket_classification.R"),
        file.path(STEP3_ROOT_ABS,   "functions/process_replicate_batch.R")
      )) {
        tryCatch(source(ff), error = function(e) {
          cat("[DAEMON", Sys.getpid(), "] ERROR sourcing", ff, ":", conditionMessage(e), "\n")
          stop(e)
        })
      }
      cat("[DAEMON", Sys.getpid(), "] ready\n")
      TRUE
    },
    PROJECT_ROOT_ABS = PROJECT_ROOT_ABS,
    STEP3_ROOT_ABS   = STEP3_ROOT_ABS)

    init_vals <- init_pkgs[]
    n_ok  <- sum(vapply(init_vals, isTRUE, logical(1)))
    n_bad <- length(init_vals) - n_ok

    if (n_bad > 0) {
      .plog("  WARNING: ", n_bad, "/", length(init_vals), " daemons failed package init.")
      for (i in seq_along(init_vals)) {
        if (!isTRUE(init_vals[[i]])) {
          cat("    Daemon", i, "result:", as.character(init_vals[[i]]), "\n")
        }
      }
    }

    b1_daemons_live <- (n_ok > 0)
    .plog("  Daemons ready: ", n_ok, "/", length(init_vals))
  }
}

############################################################################
### B.2  Helper functions
############################################################################

# ---- Stage 1: full-pool setup (runs on main process) ----
process_pool_setup <- function(
  pool, ds_id, condition_id, cond,
  pairs, refs, p1_copula, kernel_cache,
  u_full, v_full,
  cfg_reg, cfg_dist, cfg_sys,
  n_buckets, eligibility_buffer, seed_base,
  buckets_cfg,
  enable_copula_sensitivity = TRUE,
  enable_independence_sensitivity = TRUE,
  true_sgpc_full = NULL
) {
  sg_id      <- as.character(pool$id)
  sg_idx     <- pool$idx
  n_sg       <- length(sg_idx)
  if (n_sg < cfg_sys$min_subgroup_n) return(NULL)

  pool_id   <- if (!is.null(pool$pool_id))   pool$pool_id   else paste0(condition_id, "__", sg_id)
  pool_type <- if (!is.null(pool$pool_type)) pool$pool_type else "district"
  n_pool_raw <- n_sg
  n_pool_eff <- n_sg

  if (!is.null(true_sgpc_full)) {
    true_sgpc <- true_sgpc_full[sg_idx]
  } else {
    true_sgpc <- sgpc_engine(u_full[sg_idx], v_full[sg_idx], p1_copula, scale = "percentile")
  }
  u_cross   <- reference_cdf(pairs$SCALE_SCORE_PRIOR[sg_idx],   refs$ref_prior)
  v_cross   <- reference_cdf(pairs$SCALE_SCORE_CURRENT[sg_idx], refs$ref_current)

  est <- tryCatch(
    estimate_regime(u_cross, v_cross, kernel_cache,
                    regime_family  = cfg_reg$primary_family,
                    distance_fn    = cfg_dist$primary,
                    grid_resolution = 20L,
                    verbose = FALSE),
    error = function(e) NULL
  )
  if (is.null(est)) return(NULL)

  uniform_reg    <- regime_beta(0.5, 2)
  F_uniform      <- tryCatch(
    predict_marginal_cdf(v_grid = est$v_grid, u_sample = u_cross,
                         regime = uniform_reg, kernel_cache = kernel_cache),
    error = function(e) rep(NA_real_, length(est$v_grid))
  )
  w1_uniform     <- if (all(is.na(F_uniform))) NA_real_ else wasserstein1(F_uniform, est$F_obs, est$v_grid)
  w1_best        <- est$all_distances$wasserstein1
  w1_reduction_pct <- ifelse(is.finite(w1_uniform) && w1_uniform > 0,
                              100 * (1 - (w1_best / w1_uniform)), NA_real_)
  residual       <- est$F_pred - est$F_obs

  summary_row <- data.table(
    dataset_id           = ds_id,
    condition_id         = condition_id,
    year_span            = cond$year_span,
    content_area         = cond$content_area,
    subgroup_id          = sg_id,
    n_subgroup           = n_sg,
    regime_family        = cfg_reg$primary_family,
    median_sgpc_inferred = round(est$regime$median * 100, 2),
    mean_sgpc_inferred   = round(est$regime$mean   * 100, 2),
    median_sgpc_true     = round(median(true_sgpc, na.rm = TRUE), 2),
    mean_sgpc_true       = round(mean(true_sgpc,   na.rm = TRUE), 2),
    median_diff          = round(est$regime$median * 100 - median(true_sgpc, na.rm = TRUE), 2),
    mean_diff            = round(est$regime$mean   * 100 - mean(true_sgpc,   na.rm = TRUE), 2),
    wasserstein1         = round(est$all_distances$wasserstein1, 6),
    w1_best              = round(w1_best, 6),
    w1_uniform           = round(w1_uniform, 6),
    w1_reduction_pct     = round(w1_reduction_pct, 3),
    max_abs_residual     = round(max(abs(residual),  na.rm = TRUE), 6),
    mean_abs_residual    = round(mean(abs(residual), na.rm = TRUE), 6),
    ci_width_median      = NA_real_,
    ci_width_mean        = NA_real_,
    cvm                  = round(est$all_distances$cramer_von_mises, 6),
    ks                   = round(est$all_distances$ks_distance, 6),
    regime_param_1       = round(est$regime_param_hat[1], 4),
    regime_param_2       = if (length(est$regime_param_hat) > 1) round(est$regime_param_hat[2], 4) else NA_real_,
    m_hat                = round(est$m_hat,    4),
    kappa_hat            = round(est$kappa_hat, 4)
  )

  pool_registry <- data.table(
    pool_id               = pool_id,
    pool_type             = pool_type,
    span                  = cond$year_span,
    content               = cond$content_area,
    dataset_id            = ds_id,
    condition_id          = condition_id,
    subgroup_id           = sg_id,
    n_pool_raw            = n_pool_raw,
    n_pool_eff            = n_pool_eff,
    eligibility_buffer    = eligibility_buffer,
    strata_label          = if (!is.null(pool$strata_label))             as.character(pool$strata_label)             else NA_character_,
    n_constituent_districts = if (!is.null(pool$n_constituent_districts)) as.integer(pool$n_constituent_districts)   else 1L,
    constituent_districts = if (!is.null(pool$constituent_districts))     as.character(pool$constituent_districts)   else as.character(sg_id)
  )

  eligible_buckets  <- n_buckets[n_pool_raw >= (n_buckets * (1 + eligibility_buffer))]

  # ---- Copula sensitivity ----
  copula_dt <- data.table()
  if (isTRUE(enable_copula_sensitivity)) {
    base_rho    <- tryCatch(as.numeric(p1_copula@param[1]), error = function(e) NA_real_)
    base_df     <- tryCatch(as.numeric(p1_copula@df),       error = function(e) NA_real_)
    rho_variants <- unique(c(base_rho, base_rho - 0.10, base_rho + 0.10))
    rho_variants <- pmax(-0.95, pmin(0.95, rho_variants))
    if (all(is.na(rho_variants))) rho_variants <- 0.6
    df_variants  <- if (is.finite(base_df)) unique(c(base_df, pmax(2, base_df - 3), base_df + 3)) else 8
    cop_rows <- list()
    cop_i    <- 0L
    for (rv in rho_variants) {
      for (dv in df_variants) {
        cop    <- tryCatch(copula::tCopula(param = rv, df = dv, dispstr = "un"), error = function(e) NULL)
        if (is.null(cop)) next
        kc_var <- tryCatch(create_kernel_cache(cop, u_grid_size = 101, v_grid_size = 101, compute_quantile = FALSE), error = function(e) NULL)
        if (is.null(kc_var)) next
        est_var <- tryCatch(
          estimate_regime(u_cross, v_cross, kc_var,
                          regime_family   = cfg_reg$primary_family,
                          distance_fn     = cfg_dist$primary,
                          grid_resolution = 15L, verbose = FALSE),
          error = function(e) NULL
        )
        if (is.null(est_var)) next
        cop_i <- cop_i + 1L
        cop_rows[[cop_i]] <- data.table(
          dataset_id          = ds_id,
          condition_id        = condition_id,
          subgroup_id         = sg_id,
          n_subgroup          = n_sg,
          copula_family       = "t",
          rho                 = round(rv, 4),
          df                  = round(dv, 3),
          median_sgpc         = round(est_var$regime$median * 100, 3),
          mean_sgpc           = round(est_var$regime$mean   * 100, 3),
          delta_median_vs_base = round((est_var$regime$median - est$regime$median) * 100, 3),
          delta_mean_vs_base  = round((est_var$regime$mean   - est$regime$mean)   * 100, 3),
          w1                  = round(est_var$all_distances$wasserstein1, 6),
          cvm                 = round(est_var$all_distances$cramer_von_mises, 6)
        )
      }
    }
    if (cop_i > 0L) copula_dt <- rbindlist(cop_rows, fill = TRUE)
  }

  # ---- Independence sensitivity ----
  independence_dt <- data.table()
  if (isTRUE(enable_independence_sensitivity)) {
    strat_fit <- tryCatch(
      estimate_regime(u_cross, v_cross, kernel_cache,
                      regime_family   = cfg_reg$primary_family,
                      distance_fn     = cfg_dist$primary,
                      grid_resolution = 15L, verbose = FALSE,
                      stratify_by_u   = TRUE,
                      stratify_bins   = cfg_reg$stratify_bins),
      error = function(e) NULL
    )
    if (!is.null(strat_fit)) {
      base_k3  <- classify_bucket(est$regime$median * 100, k = 3, cutpoints = buckets_cfg$k3)$assigned_bucket
      strat_k3 <- classify_bucket(strat_fit$median_sgpc,   k = 3, cutpoints = buckets_cfg$k3)$assigned_bucket
      base_k5  <- classify_bucket(est$regime$median * 100, k = 5, cutpoints = buckets_cfg$k5)$assigned_bucket
      strat_k5 <- classify_bucket(strat_fit$median_sgpc,   k = 5, cutpoints = buckets_cfg$k5)$assigned_bucket
      independence_dt <- data.table(
        dataset_id       = ds_id,
        condition_id     = condition_id,
        subgroup_id      = sg_id,
        n_subgroup       = n_sg,
        n_bins           = length(strat_fit$bins),
        w1_single        = round(est$all_distances$wasserstein1,      6),
        w1_stratified    = round(strat_fit$all_distances$wasserstein1, 6),
        cvm_single       = round(est$all_distances$cramer_von_mises,  6),
        cvm_stratified   = round(strat_fit$all_distances$cramer_von_mises, 6),
        delta_median     = round(strat_fit$median_sgpc - est$regime$median * 100, 3),
        delta_mean       = round(strat_fit$mean_sgpc   - est$regime$mean   * 100, 3),
        base_k3          = base_k3,
        stratified_k3    = strat_k3,
        base_k5          = base_k5,
        stratified_k5    = strat_k5,
        k3_changed       = base_k3 != strat_k3,
        k5_changed       = base_k5 != strat_k5
      )
    }
  }

  list(
    summary_row      = summary_row,
    pool_registry    = pool_registry,
    copula_rows      = copula_dt,
    independence_rows = independence_dt,
    pool_result      = list(estimate = est, true_sgpc = true_sgpc),
    pool_id          = pool_id,
    subgroup_id      = sg_id,
    sg_idx           = sg_idx,
    pool_type        = pool_type,
    eligible_buckets = eligible_buckets,
    seed_base        = seed_base + sum(utf8ToInt(pool_id))
  )
}

# ---- Stage 2 worker: one replicate batch (runs inside mirai daemon) ----
# NOTE: u_full, v_full, pairs_ss_prior, pairs_ss_current, refs, kernel_cache,
#       p1_copula, pool_defs, cfg_reg, cfg_dist are pushed via everywhere()
#       per-condition before mirai_map() is called.
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
  # Append completion record to shared progress file
  tryCatch(
    cat(sprintf("DONE|%s|%d|%d|%d|%.2f\n",
                pool_id, n_bucket, rep_start, rep_end, elapsed),
        file = phaseb_progress_file_abs, append = TRUE),
    error = function(e) invisible(NULL)
  )

  rbindlist(lapply(rows, as.data.table), fill = TRUE)
}

############################################################################
### B.3  Loop Over Datasets and Conditions
############################################################################

total_conditions_run <- 0L

for (ds_id in cfg_sys$datasets) {

  cat("================================================================\n")
  cat("Dataset:", ds_id, "\n")
  cat("================================================================\n\n")
  .plog("Dataset: ", ds_id)

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
  .plog("  Dataset loaded: ", format(nrow(STATE_DATA), big.mark = ","), " rows")

  conditions_all <- get_phase1_conditions(ds_id)
  if (length(conditions_all) == 0) {
    cat("  WARNING: No Phase 1 conditions found. Skipping.\n\n")
    next
  }

  cond_metas   <- lapply(conditions_all, parse_condition_id)
  cond_spans   <- sapply(cond_metas, `[[`, "year_span")
  cond_content <- sapply(cond_metas, `[[`, "content_area")

  if (!is.null(cfg_sys$year_spans)) {
    keep         <- cond_spans %in% cfg_sys$year_spans
    conditions_all <- conditions_all[keep]
    cond_spans   <- cond_spans[keep]
    cond_content <- cond_content[keep]
  }
  if (!is.null(cfg_sys$content_areas)) {
    keep         <- cond_content %in% cfg_sys$content_areas
    conditions_all <- conditions_all[keep]
    cond_spans   <- cond_spans[keep]
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
    conditions  <- conditions_all[sampled_idx]
  } else {
    conditions  <- conditions_all
  }

  cat("  Selected", length(conditions), "conditions for validation\n\n")
  .plog("  Conditions selected: ", length(conditions))
  canonical <- tryCatch(load_canonical_parameters(), error = function(e) NULL)

  # Load STEP 2 pre-computed SGPc variants for truth (sgpc_emp) reuse
  truth_source   <- cfg_sys$truth_source %||% "recompute"
  copula_mode    <- STEP3_CONFIG$copula$mode %||% "phase1_best_fit"
  step2_variants <- NULL
  if (identical(truth_source, "step2_empirical")) {
    step2_dir_raw <- cfg_sys$step2_results_dir %||% "STEP_2_SGPc_Sensitivity/results"
    step2_dir <- if (startsWith(step2_dir_raw, "/")) {
      step2_dir_raw
    } else {
      file.path(PROJECT_ROOT_ABS, step2_dir_raw)
    }
    step2_file <- file.path(step2_dir, paste0("sgpc_all_variants_", ds_id, ".rds"))
    if (file.exists(step2_file)) {
      cat("  Loading STEP 2 variants from:", step2_file, "\n")
      step2_variants <- readRDS(step2_file)
      data.table::setDT(step2_variants)
      data.table::setkey(step2_variants, condition_id, ID)
      cat("  STEP 2 variants loaded:", format(nrow(step2_variants), big.mark = ","),
          "rows,", length(unique(step2_variants$condition_id)), "conditions\n")
      .plog("  STEP 2 truth source loaded: ", format(nrow(step2_variants), big.mark = ","), " rows")
    } else {
      cat("  WARNING: STEP 2 file not found:", step2_file, " — will recompute truth\n")
      truth_source <- "recompute"
    }
  }
  if (identical(copula_mode, "canonical_only")) {
    cat("  Copula mode: CANONICAL ONLY (honest NAEP/TIMSS setting)\n")
  } else {
    cat("  Copula mode:", copula_mode, "\n")
  }

  n_conditions_ds <- length(conditions)

  for (ci in seq_along(conditions)) {
    condition_id   <- conditions[ci]
    cond           <- parse_condition_id(condition_id)
    cond_t0        <- Sys.time()
    total_conditions_run <- total_conditions_run + 1L

    cat(sprintf("  Condition %d / %d : %s\n", ci, n_conditions_ds, condition_id))
    .plog(sprintf("Condition %d/%d: %s", ci, n_conditions_ds, condition_id))

    year_prior <- as.character(as.numeric(cond$year_current) - cond$year_span)
    pairs <- tryCatch(
      create_longitudinal_pairs(
        data          = STATE_DATA,
        grade_prior   = cond$grade_prior,
        grade_current = cond$grade_current,
        year_prior    = year_prior,
        year_current  = cond$year_current,
        content_prior = cond$content_area
      ),
      error = function(e) { cat("    ERROR extracting pairs:", e$message, "\n"); NULL }
    )
    if (is.null(pairs) || nrow(pairs) < 50) {
      cat("    Insufficient pairs (n =", ifelse(is.null(pairs), 0, nrow(pairs)), "). Skipping.\n")
      next
    }

    refs <- tryCatch(
      build_condition_reference(STATE_DATA, cond),
      error = function(e) { cat("    ERROR building refs:", e$message, "\n"); NULL }
    )
    if (is.null(refs)) next

    # --- Copula selection: canonical_only vs phase1_best_fit ---
    p1 <- tryCatch(load_phase1_condition(ds_id, condition_id), error = function(e) NULL)
    if (identical(copula_mode, "canonical_only")) {
      if (!is.null(canonical)) {
        p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
        cat("    Copula: canonical (", cond$content_area, ", span=", cond$year_span, ")\n")
      } else {
        cat("    No canonical params available. Skipping.\n"); next
      }
    } else {
      if (!is.null(p1) && !is.null(p1$best_fit_copula)) {
        p1_copula <- p1$best_fit_copula
        cat("    Copula: phase1 best-fit\n")
      } else if (!is.null(canonical)) {
        p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
        cat("    Copula: canonical fallback\n")
      } else {
        cat("    No copula available. Skipping.\n"); next
      }
    }

    kernel_cache <- tryCatch(
      create_kernel_cache(p1_copula, u_grid_size = 101, v_grid_size = 101, compute_quantile = FALSE),
      error = function(e) { cat("    ERROR building kernel:", e$message, "\n"); NULL }
    )
    if (is.null(kernel_cache)) next

    u_full <- rank(pairs$SCALE_SCORE_PRIOR)   / (nrow(pairs) + 1)
    v_full <- rank(pairs$SCALE_SCORE_CURRENT) / (nrow(pairs) + 1)

    # --- Truth alignment: load pre-computed sgpc_emp from STEP 2 or recompute ---
    true_sgpc_full <- NULL
    if (identical(truth_source, "step2_empirical") && !is.null(step2_variants)) {
      cond_id_match <- condition_id
      s2_cond <- step2_variants[condition_id == cond_id_match]
      if (nrow(s2_cond) > 0 && "sgpc_emp" %in% names(s2_cond)) {
        s2_cols <- c("ID", "sgpc_emp")
        if (all(c("SCALE_SCORE_PRIOR", "SCALE_SCORE_CURRENT") %in% names(s2_cond)))
          s2_cols <- c(s2_cols, "SCALE_SCORE_PRIOR", "SCALE_SCORE_CURRENT")
        aligned <- merge(
          data.table::data.table(
            ID = pairs$ID, row_idx = seq_len(nrow(pairs)),
            ss_prior_s3 = pairs$SCALE_SCORE_PRIOR,
            ss_current_s3 = pairs$SCALE_SCORE_CURRENT),
          s2_cond[, ..s2_cols],
          by = "ID", all.x = TRUE, sort = FALSE)
        data.table::setorder(aligned, row_idx)
        pct_matched <- mean(!is.na(aligned$sgpc_emp))
        if (pct_matched >= 0.95) {
          if ("SCALE_SCORE_PRIOR" %in% names(aligned)) {
            score_ok <- aligned[!is.na(sgpc_emp),
              mean(ss_prior_s3 == SCALE_SCORE_PRIOR & ss_current_s3 == SCALE_SCORE_CURRENT,
                   na.rm = TRUE)]
            if (!is.na(score_ok) && score_ok < 0.99) {
              cat(sprintf("    QA FAIL: %.1f%% score mismatch between STEP 2 and STEP 3 pairs — recomputing\n",
                          (1 - score_ok) * 100))
              pct_matched <- 0
            }
          }
        }
        if (pct_matched >= 0.95) {
          true_sgpc_full <- aligned$sgpc_emp
          if (pct_matched < 1.0) {
            n_miss <- sum(is.na(true_sgpc_full))
            cat(sprintf("    STEP 2 truth: %.1f%% matched (%d missing, imputed via sgpc_engine)\n",
                        pct_matched * 100, n_miss))
            miss_idx <- which(is.na(true_sgpc_full))
            true_sgpc_full[miss_idx] <- sgpc_engine(
              u_full[miss_idx], v_full[miss_idx], p1_copula, scale = "percentile")
          } else {
            cat(sprintf("    STEP 2 truth: 100%% matched (n=%d)\n", length(true_sgpc_full)))
          }
        } else if (pct_matched > 0) {
          cat(sprintf("    STEP 2 truth: only %.1f%% matched — falling back to recompute\n",
                      pct_matched * 100))
        }
      } else {
        cat("    STEP 2 truth: condition not found in STEP 2 data — recomputing\n")
      }
    }
    if (is.null(true_sgpc_full)) {
      cat("    Computing true SGPc via sgpc_engine (recompute mode)\n")
      true_sgpc_full <- sgpc_engine(u_full, v_full, p1_copula, scale = "percentile")
    }

    # Build pools
    district_pools <- list()
    if (sg_col %in% names(pairs)) {
      sg_table <- pairs[, .N, by = sg_col][N >= cfg_sys$min_subgroup_n][order(-N)]
      n_sg     <- min(nrow(sg_table), cfg_sys$n_subgroups_per_condition)
      if (n_sg == 0) {
        district_pools <- list(list(id = "ALL", idx = seq_len(nrow(pairs)),
                                    pool_id = paste0(condition_id, "__ALL"),
                                    pool_type = "district",
                                    constituent_districts = "ALL",
                                    n_constituent_districts = 1L))
      } else {
        district_pools <- lapply(seq_len(n_sg), function(j) {
          sg_id_j <- as.character(sg_table[[sg_col]][j])
          list(id = sg_id_j, idx = which(pairs[[sg_col]] == sg_id_j),
               pool_id = paste0(condition_id, "__", sg_id_j),
               pool_type = "district",
               constituent_districts = sg_id_j,
               n_constituent_districts = 1L)
        })
      }
    } else {
      district_pools <- list(list(id = "ALL", idx = seq_len(nrow(pairs)),
                                  pool_id = paste0(condition_id, "__ALL"),
                                  pool_type = "district",
                                  constituent_districts = "ALL",
                                  n_constituent_districts = 1L))
    }

    cluster_pools <- list()
    if (allow_cluster_pools && (sg_col %in% names(pairs))) {
      cluster_build <- tryCatch(
        build_cluster_pools(pairs = pairs, sg_col = sg_col,
                            u_full = u_full, v_full = v_full,
                            p1_copula = p1_copula, condition_id = condition_id,
                            n_growth_strata = n_growth_strata,
                            min_pool_n = cluster_min_pool_n),
        error = function(e) { cat("    WARNING: cluster pool build failed:", e$message, "\n"); NULL }
      )
      if (!is.null(cluster_build) && length(cluster_build$pools) > 0) {
        cluster_pools <- cluster_build$pools
      }
    }

    subgroups <- c(district_pools, cluster_pools)
    cat("    Pools prepared:", length(subgroups),
        "(district =", length(district_pools),
        ", cluster =", length(cluster_pools), ")\n")
    .plog(sprintf("  Stage 1: %d pools (%d district, %d cluster)",
                  length(subgroups), length(district_pools), length(cluster_pools)))
    if (length(subgroups) == 0) next

    ##################################################################
    ### Stage 1: Full-pool setup (sequential, main process)
    ##################################################################
    s1_t0 <- proc.time()[["elapsed"]]

    pool_setups   <- list()
    n_pool_ok     <- 0L

    for (pi in seq_along(subgroups)) {
      pool <- subgroups[[pi]]
      cat(sprintf("      [Pool %d/%d] %s (%s, N=%d)...",
                  pi, length(subgroups),
                  pool$pool_id %||% paste0(condition_id, "__", pool$id),
                  pool$pool_type %||% "district",
                  length(pool$idx)))
      ps_t0 <- proc.time()[["elapsed"]]
      setup <- process_pool_setup(
        pool = pool, ds_id = ds_id, condition_id = condition_id, cond = cond,
        pairs = pairs, refs = refs, p1_copula = p1_copula,
        kernel_cache = kernel_cache, u_full = u_full, v_full = v_full,
        cfg_reg = cfg_reg, cfg_dist = cfg_dist, cfg_sys = cfg_sys,
        n_buckets = n_buckets, eligibility_buffer = eligibility_buffer,
        seed_base = seed_base, buckets_cfg = STEP3_CONFIG$buckets,
        enable_copula_sensitivity     = identical(pool$pool_type, "district"),
        enable_independence_sensitivity = identical(pool$pool_type, "district"),
        true_sgpc_full = true_sgpc_full
      )
      ps_elapsed <- proc.time()[["elapsed"]] - ps_t0
      if (!is.null(setup)) {
        n_pool_ok <- n_pool_ok + 1L
        pool_setups[[pi]] <- setup
        cat(sprintf(" median=%.1f, diff=%.1f, %.1fs\n",
                    setup$summary_row$median_sgpc_inferred,
                    setup$summary_row$median_diff,
                    ps_elapsed))
        # Accumulate Stage 1 outputs immediately
        row_counter  <- row_counter  + 1L
        summary_rows[[row_counter]] <- setup$summary_row
        pool_counter <- pool_counter + 1L
        pool_registry_rows[[pool_counter]] <- setup$pool_registry
        all_results[[setup$pool_id]] <- setup$pool_result
        if (nrow(setup$copula_rows) > 0 && copula_counter < sensitivity_budget) {
          copula_counter <- copula_counter + 1L
          copula_sensitivity_rows[[copula_counter]] <- setup$copula_rows
        }
        if (nrow(setup$independence_rows) > 0 && independence_counter < sensitivity_budget) {
          independence_counter <- independence_counter + 1L
          independence_sensitivity_rows[[independence_counter]] <- setup$independence_rows
        }
      } else {
        cat(" SKIPPED\n")
      }
    }

    s1_elapsed <- proc.time()[["elapsed"]] - s1_t0
    s1_recoveries <- sapply(pool_setups[!sapply(pool_setups, is.null)],
                             function(x) abs(x$summary_row$median_diff))
    .plog(sprintf("  Stage 1 complete: %d/%d pools | median |diff|=%.2f SGP pts | %.1fs",
                  n_pool_ok, length(subgroups),
                  if (length(s1_recoveries) > 0) median(s1_recoveries) else NA_real_,
                  s1_elapsed))

    ##################################################################
    ### Stage 2: Replicate batches (parallel via mirai_map)
    ##################################################################

    # Build flat task list: (pool_idx, n_bucket, rep_start, rep_end)
    tasks <- list()
    pool_defs_for_workers <- list()
    ti <- 0L

    for (pi in seq_along(pool_setups)) {
      setup <- pool_setups[[pi]]
      if (is.null(setup)) next
      # pool definition for worker environment
      pool_defs_for_workers[[pi]] <- list(
        sg_idx     = setup$sg_idx,
        subgroup_id = setup$subgroup_id
      )
      for (nb in setup$eligible_buckets) {
        for (rb_start in seq(1L, outer_reps, by = rep_batch_size)) {
          rb_end <- min(rb_start + rep_batch_size - 1L, outer_reps)
          ti <- ti + 1L
          tasks[[ti]] <- list(
            pool_idx       = pi,
            n_bucket       = as.integer(nb),
            rep_start      = rb_start,
            rep_end        = rb_end,
            pool_seed_base = setup$seed_base,
            pool_id        = setup$pool_id,
            pool_type      = setup$pool_type,
            ds_id          = ds_id,
            condition_id   = condition_id,
            year_span      = cond$year_span,
            content_area   = cond$content_area
          )
        }
      }
    }

    n_tasks <- length(tasks)
    .plog(sprintf("  Stage 2: %d replicate tasks dispatched (%d workers, reps=%d, batch=%d)",
                  n_tasks, if (b1_daemons_live) n_workers else 1L,
                  outer_reps, rep_batch_size))

    if (n_tasks == 0) {
      cat("    No eligible buckets for any pool. Skipping Stage 2.\n")
      next
    }

    s2_t0 <- proc.time()[["elapsed"]]

    batch_results <- list()

    if (b1_daemons_live && n_tasks > 1L) {
      # Push condition data to all daemons (shared, not per-task)
      # When true_sgpc_full is pre-loaded from STEP 2, push it instead of
      # u_full/v_full/p1_copula (which are only needed for truth recomputation).
      push_ok <- tryCatch({
        cond_push <- mirai::everywhere({
          .PHASEB_TRUE_SGPC_FULL <- true_sgpc_push
          .PHASEB_U_FULL       <- u_full_push
          .PHASEB_V_FULL       <- v_full_push
          .PHASEB_SS_PRIOR     <- ss_prior_push
          .PHASEB_SS_CURRENT   <- ss_current_push
          .PHASEB_REFS         <- refs_push
          .PHASEB_KERNEL_CACHE <- kernel_cache_push
          .PHASEB_P1_COPULA    <- p1_copula_push
          .PHASEB_POOL_DEFS    <- pool_defs_push
          .PHASEB_CFG_REG      <- cfg_reg_push
          .PHASEB_CFG_DIST     <- cfg_dist_push
          TRUE
        },
        true_sgpc_push     = true_sgpc_full,
        u_full_push        = u_full,
        v_full_push        = v_full,
        ss_prior_push      = pairs$SCALE_SCORE_PRIOR,
        ss_current_push    = pairs$SCALE_SCORE_CURRENT,
        refs_push          = refs,
        kernel_cache_push  = kernel_cache,
        p1_copula_push     = p1_copula,
        pool_defs_push     = pool_defs_for_workers,
        cfg_reg_push       = cfg_reg,
        cfg_dist_push      = cfg_dist
        )
        push_vals <- cond_push[]
        all(vapply(push_vals, isTRUE, logical(1)))
      }, error = function(e) {
        cat("    WARNING: condition data push failed:", e$message, "\n")
        FALSE
      })

      if (isTRUE(push_ok)) {
        # process_replicate_batch is sourced into daemon globalenv at daemon
        # init (functions/process_replicate_batch.R). No runtime push needed.
        # baseenv() on the lambda ensures name lookups use the daemon's own
        # search path rather than a frozen snapshot of the main session.
        pf_abs <- normalizePath(phaseb_progress_file, mustWork = FALSE)
        worker_lambda <- function(task, pf) {
          process_replicate_batch(
            pool_idx               = task$pool_idx,
            n_bucket               = task$n_bucket,
            rep_start              = task$rep_start,
            rep_end                = task$rep_end,
            pool_seed_base         = task$pool_seed_base,
            pool_id                = task$pool_id,
            pool_type              = task$pool_type,
            ds_id                  = task$ds_id,
            condition_id           = task$condition_id,
            year_span              = task$year_span,
            content_area           = task$content_area,
            phaseb_progress_file_abs = pf
          )
        }
        environment(worker_lambda) <- baseenv()

        mirai_res <- mirai::mirai_map(
          .x     = tasks,
          .f     = worker_lambda,
          .args  = list(pf = pf_abs)
        )
        batch_results <- mirai_res[]

        # Count completions and print first few error messages for diagnosis
        n_done  <- sum(!sapply(batch_results, function(x)
          inherits(x, "miraiError") || inherits(x, "errorValue") || is.null(x)))
        n_errs  <- n_tasks - n_done
        .plog(sprintf("  Stage 2 complete: %d/%d tasks | %.1fs%s",
                      n_done, n_tasks,
                      proc.time()[["elapsed"]] - s2_t0,
                      if (n_errs > 0) paste0(" | ERRORS: ", n_errs) else ""))
        if (n_errs > 0) {
          err_shown <- 0L
          for (bi in seq_along(batch_results)) {
            res <- batch_results[[bi]]
            if (inherits(res, "miraiError") || inherits(res, "errorValue")) {
              cat(sprintf("    [Task %d error] %s\n", bi, as.character(res)))
              err_shown <- err_shown + 1L
              if (err_shown >= 3L) break
            }
          }
        }
      } else {
        cat("    WARNING: condition push failed; falling back to sequential for Stage 2.\n")
        batch_results <- NULL
      }
    }

    # Sequential fallback for Stage 2
    if (length(batch_results) == 0) {
      # Populate daemon globals in main session for sequential run
      .PHASEB_TRUE_SGPC_FULL <- true_sgpc_full
      .PHASEB_U_FULL       <- u_full
      .PHASEB_V_FULL       <- v_full
      .PHASEB_SS_PRIOR     <- pairs$SCALE_SCORE_PRIOR
      .PHASEB_SS_CURRENT   <- pairs$SCALE_SCORE_CURRENT
      .PHASEB_REFS         <- refs
      .PHASEB_KERNEL_CACHE <- kernel_cache
      .PHASEB_P1_COPULA    <- p1_copula
      .PHASEB_POOL_DEFS    <- pool_defs_for_workers
      .PHASEB_CFG_REG      <- cfg_reg
      .PHASEB_CFG_DIST     <- cfg_dist

      pf_abs <- normalizePath(phaseb_progress_file, mustWork = FALSE)
      cat("    Running", n_tasks, "replicate tasks sequentially...\n")
      batch_results <- lapply(seq_along(tasks), function(ti) {
        if (ti %% 20 == 0L || ti == 1L) {
          cat(sprintf("      task %d/%d\n", ti, n_tasks))
        }
        task <- tasks[[ti]]
        tryCatch(
          process_replicate_batch(
            pool_idx               = task$pool_idx,
            n_bucket               = task$n_bucket,
            rep_start              = task$rep_start,
            rep_end                = task$rep_end,
            pool_seed_base         = task$pool_seed_base,
            pool_id                = task$pool_id,
            pool_type              = task$pool_type,
            ds_id                  = task$ds_id,
            condition_id           = task$condition_id,
            year_span              = task$year_span,
            content_area           = task$content_area,
            phaseb_progress_file_abs = pf_abs
          ),
          error = function(e) {
            cat("      ERROR task", ti, ":", e$message, "\n")
            NULL
          }
        )
      })
      s2_elapsed <- proc.time()[["elapsed"]] - s2_t0
      .plog(sprintf("  Stage 2 complete (sequential): %d tasks | %.1fs", n_tasks, s2_elapsed))
    }

    # Collect replicate rows
    n_reps_collected <- 0L
    for (br in batch_results) {
      if (is.null(br) || inherits(br, "miraiError") || inherits(br, "errorValue")) next
      if (is.data.table(br) && nrow(br) > 0) {
        rep_counter <- rep_counter + 1L
        replicate_rows[[rep_counter]] <- br
        n_reps_collected <- n_reps_collected + nrow(br)
      }
    }

    cond_elapsed <- as.numeric(difftime(Sys.time(), cond_t0, units = "secs"))
    .plog(sprintf("  Condition %d/%d DONE | %d replicates | %.1fs | ETA: ~%.0f min remaining",
                  ci, n_conditions_ds, n_reps_collected, cond_elapsed,
                  (cond_elapsed * (n_conditions_ds - ci)) / 60))
    cat(sprintf("    %d pools processed, %d replicates collected, %.1fs\n",
                n_pool_ok, n_reps_collected, cond_elapsed))
  }  # end condition loop

  rm(STATE_DATA)
  gc(verbose = FALSE)
}  # end dataset loop

# Tear down daemons ONCE after all conditions (STEP 1 lifecycle pattern)
if (b1_daemons_live) {
  mirai::daemons(0)
  .plog("Daemons stopped.")
}

############################################################################
### B.4  Compile and Save Results
############################################################################

cat("\n================================================================\n")
cat("Compiling Phase B results...\n")
cat("================================================================\n\n")
.plog("Compiling Phase B results...")

if (length(summary_rows) > 0) {
  phase_b_summary      <- rbindlist(summary_rows,      fill = TRUE)
  phase_b_pool_registry <- if (length(pool_registry_rows) > 0) unique(rbindlist(pool_registry_rows, fill = TRUE)) else data.table()
  phase_b_replicates   <- if (length(replicate_rows)   > 0) rbindlist(replicate_rows,   fill = TRUE) else data.table()

  cat("Total subgroups estimated:", nrow(phase_b_summary), "\n")
  cat("Conditions covered:", length(unique(phase_b_summary$condition_id)), "\n")
  cat("Total pools registered:", nrow(phase_b_pool_registry), "\n")
  cat("Total Phase B replicates:", nrow(phase_b_replicates), "\n")

  cat("\n--- Recovery Accuracy Summary ---\n")
  cat("Median of |median_diff|:", round(median(abs(phase_b_summary$median_diff)), 2), "SGP points\n")
  cat("Mean of |median_diff|:",   round(mean(abs(phase_b_summary$median_diff)),   2), "SGP points\n")
  cat("Median of |mean_diff|:",   round(median(abs(phase_b_summary$mean_diff)),   2), "SGP points\n")
  cat("Mean of |mean_diff|:",     round(mean(abs(phase_b_summary$mean_diff)),     2), "SGP points\n")
  cat("90th percentile of |median_diff|:", round(quantile(abs(phase_b_summary$median_diff), 0.90), 2), "SGP points\n")
  cat("90th percentile of |mean_diff|:",   round(quantile(abs(phase_b_summary$mean_diff),   0.90), 2), "SGP points\n")

  if ("year_span" %in% names(phase_b_summary)) {
    cat("\n--- By Year Span ---\n")
    by_span <- phase_b_summary[, .(
      n_subgroups          = .N,
      median_abs_diff      = round(median(abs(median_diff)), 2),
      mean_abs_diff        = round(mean(abs(median_diff)),   2),
      median_abs_mean_diff = round(median(abs(mean_diff)),   2),
      mean_abs_mean_diff   = round(mean(abs(mean_diff)),     2),
      median_W1            = round(median(wasserstein1),     6)
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
    n_subgroups          = .N,
    median_abs_diff      = round(median(abs(median_diff)), 2),
    mean_abs_diff        = round(mean(abs(median_diff)),   2),
    median_abs_mean_diff = round(median(abs(mean_diff)),   2),
    mean_abs_mean_diff   = round(mean(abs(mean_diff)),     2)
  ), by = size_bin][order(size_bin)]
  print(by_size)

  fwrite(phase_b_summary,       file.path(RESULTS_DIR, "phase_b_systematic_summary.csv"))
  fwrite(phase_b_pool_registry, file.path(RESULTS_DIR, "phase_b_pool_registry.csv"))
  save(phase_b_replicates,      file = file.path(RESULTS_DIR, "phase_b_replicates.RData"))

  if (nrow(phase_b_replicates) > 0) {
    phase_b_precision_by_n <- phase_b_replicates[, .(
      n_reps            = .N,
      n_converged       = sum(converged, na.rm = TRUE),
      N_eff_bucket      = round(median(n_eff_bucket, na.rm = TRUE), 2),
      median_bias       = round(mean(median_error[converged %in% TRUE],       na.rm = TRUE), 4),
      median_mae        = round(mean(abs_median_error[converged %in% TRUE],   na.rm = TRUE), 4),
      median_rmse       = round(sqrt(mean((median_error[converged %in% TRUE])^2, na.rm = TRUE)), 4),
      median_ci_width_90 = round(
        quantile(inferred_median[converged %in% TRUE], 0.95, na.rm = TRUE) -
          quantile(inferred_median[converged %in% TRUE], 0.05, na.rm = TRUE), 4),
      median_ci_width_95 = round(
        quantile(inferred_median[converged %in% TRUE], 0.975, na.rm = TRUE) -
          quantile(inferred_median[converged %in% TRUE], 0.025, na.rm = TRUE), 4),
      mean_bias         = round(mean(mean_error[converged %in% TRUE],         na.rm = TRUE), 4),
      mean_mae          = round(mean(abs_mean_error[converged %in% TRUE],     na.rm = TRUE), 4),
      mean_rmse         = round(sqrt(mean((mean_error[converged %in% TRUE])^2, na.rm = TRUE)), 4),
      mean_ci_width_90  = round(
        quantile(inferred_mean[converged %in% TRUE], 0.95, na.rm = TRUE) -
          quantile(inferred_mean[converged %in% TRUE], 0.05, na.rm = TRUE), 4),
      mean_ci_width_95  = round(
        quantile(inferred_mean[converged %in% TRUE], 0.975, na.rm = TRUE) -
          quantile(inferred_mean[converged %in% TRUE], 0.025, na.rm = TRUE), 4)
    ), by = .(pool_id, pool_type, span, content, n_bucket)]
  } else {
    phase_b_precision_by_n <- data.table(
      pool_id = character(), pool_type = character(),
      span = integer(), content = character(), n_bucket = integer(),
      n_reps = integer(), n_converged = integer(), N_eff_bucket = numeric(),
      median_bias = numeric(), median_mae = numeric(), median_rmse = numeric(),
      median_ci_width_90 = numeric(), median_ci_width_95 = numeric(),
      mean_bias = numeric(), mean_mae = numeric(), mean_rmse = numeric(),
      mean_ci_width_90 = numeric(), mean_ci_width_95 = numeric()
    )
  }
  fwrite(phase_b_precision_by_n, file.path(RESULTS_DIR, "phase_b_precision_by_n.csv"))

  saveRDS(all_results, file.path(RESULTS_DIR, "phase_b_all_results.rds"))
  phase_b_copula_sensitivity      <- if (length(copula_sensitivity_rows)   > 0) rbindlist(copula_sensitivity_rows,      fill = TRUE) else data.table()
  phase_b_independence_sensitivity <- if (length(independence_sensitivity_rows) > 0) rbindlist(independence_sensitivity_rows, fill = TRUE) else data.table()
  fwrite(phase_b_copula_sensitivity,       file.path(RESULTS_DIR, "phase_b_copula_sensitivity.csv"))
  fwrite(phase_b_independence_sensitivity, file.path(RESULTS_DIR, "phase_b_independence_sensitivity.csv"))

  cat("\n  Saved: phase_b_systematic_summary.csv, phase_b_pool_registry.csv, phase_b_precision_by_n.csv\n")
  cat("  Saved: phase_b_replicates.RData, phase_b_all_results.rds\n")
  cat("  Saved: phase_b_copula_sensitivity.csv, phase_b_independence_sensitivity.csv\n")
} else {
  cat("No results to compile.\n")
  phase_b_summary <- data.table()
}

phaseb_elapsed <- difftime(Sys.time(), phaseb_start_time, units = "mins")
.plog(sprintf("Phase B COMPLETE | %.1f minutes | %d conditions processed",
              as.numeric(phaseb_elapsed), total_conditions_run))

cat(sprintf("\n--- Phase B complete (%.1f minutes) ---\n\n", as.numeric(phaseb_elapsed)))
