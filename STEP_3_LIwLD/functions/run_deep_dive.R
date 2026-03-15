############################################################################
###
### STEP 3 — Reusable Phase A Deep-Dive Runner
###
### Extracted from step3_validation_deep_dive.R so Phase A can be run
### against arbitrary (dataset, condition, subgroup) targets.
###
############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}

run_deep_dive <- function(dataset_id = NULL,
                          condition_id = NULL,
                          subgroup_id = NULL,
                          output_dir = NULL,
                          config = STEP3_CONFIG,
                          subgroup_col = NULL,
                          use_mirai = FALSE,
                          verbose = TRUE) {
  cfg <- config
  if (is.null(cfg) || !is.list(cfg)) {
    stop("run_deep_dive(): config must be a STEP3_CONFIG-like list.")
  }
  if (is.null(cfg$validation)) {
    stop("run_deep_dive(): config$validation is missing.")
  }

  log_msg <- function(...) {
    if (isTRUE(verbose)) cat(...)
  }

  step3_root <- if (exists("STEP3_ROOT", inherits = TRUE)) {
    normalizePath(get("STEP3_ROOT", inherits = TRUE), mustWork = TRUE)
  } else if (grepl("STEP_3_LIwLD$", getwd())) {
    normalizePath(getwd(), mustWork = TRUE)
  } else {
    normalizePath(file.path(getwd(), "STEP_3_LIwLD"), mustWork = TRUE)
  }

  project_root <- if (exists("PROJECT_ROOT", inherits = TRUE)) {
    normalizePath(get("PROJECT_ROOT", inherits = TRUE), mustWork = TRUE)
  } else {
    normalizePath(dirname(step3_root), mustWork = TRUE)
  }

  anchor_path <- function(p) {
    if (!is.null(p) && nzchar(p) && !startsWith(p, "/")) file.path(project_root, p) else p
  }

  output_dir <- output_dir %||% {
    if (exists("RESULTS_DIR", inherits = TRUE)) get("RESULTS_DIR", inherits = TRUE) else file.path(step3_root, "results")
  }
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  dataset_id <- dataset_id %||% cfg$validation$dataset_id
  if (is.null(dataset_id) || !nzchar(dataset_id)) {
    stop("run_deep_dive(): dataset_id is NULL/empty and config$validation$dataset_id is not set.")
  }
  log_msg("--- Phase A: Single-Condition Deep Validation ---\n\n")
  log_msg("Dataset: ", dataset_id, "\n")

  if (!exists("DATASETS", inherits = TRUE)) {
    stop("run_deep_dive(): DATASETS object not found. Source dataset_configs.R first.")
  }
  ds_config <- DATASETS[[dataset_id]]
  if (is.null(ds_config)) {
    stop("Dataset '", dataset_id, "' not found in DATASETS.")
  }

  # Load full state dataset
  data_path <- anchor_path(ds_config$local_path)
  if (!file.exists(data_path)) data_path <- anchor_path(ds_config$ec2_path)
  if (!file.exists(data_path)) {
    stop("Data file not found for dataset '", dataset_id, "'. Checked:\n  ",
         anchor_path(ds_config$local_path), "\n  ", anchor_path(ds_config$ec2_path))
  }
  log_msg("Loading state data from: ", data_path, "\n")
  load(data_path)

  state_data_name <- ds_config$rdata_object_name
  if (exists(state_data_name)) {
    STATE_DATA <- get(state_data_name)
  } else {
    dt_names <- ls()[sapply(ls(), function(x) data.table::is.data.table(get(x)))]
    if (length(dt_names) == 0) stop("No data.table found after loading ", data_path)
    STATE_DATA <- get(dt_names[which.max(sapply(dt_names, function(x) nrow(get(x))))])
  }
  log_msg("State data loaded: ", format(nrow(STATE_DATA), big.mark = ","), " rows\n")

  # Select condition (explicit or auto)
  if (is.null(condition_id)) {
    condition_id <- cfg$validation$condition_id
  }
  if (is.null(condition_id)) {
    conditions <- get_phase1_conditions(
      dataset_id,
      phase1_results_dir = file.path(project_root, "STEP_1_Family_Selection", "results")
    )
    if (length(conditions) == 0) stop("No Phase 1 conditions found for ", dataset_id)

    preferred_content <- ""
    if (!is.null(cfg$validation$content_area)) {
      preferred_content <- toupper(as.character(cfg$validation$content_area))
    }
    cond_meta <- lapply(conditions, parse_condition_id)
    spans <- sapply(cond_meta, `[[`, "year_span")
    contents <- toupper(sapply(cond_meta, `[[`, "content_area"))
    one_year <- conditions[spans == 1]
    one_year_contents <- contents[spans == 1]
    one_year_preferred <- one_year[one_year_contents == preferred_content]

    if (length(one_year_preferred) > 0) {
      condition_id <- one_year_preferred[1]
      log_msg("Auto-selected 1-year preferred content condition: ", condition_id, "\n")
    } else if (length(one_year) > 0) {
      condition_id <- one_year[1]
      log_msg("Preferred content not found in 1-year spans; using first 1-year condition: ", condition_id, "\n")
    } else {
      condition_id <- conditions[1]
      log_msg("No 1-year conditions available; using first available condition: ", condition_id, "\n")
    }
  }

  log_msg("Condition: ", condition_id, "\n")
  cond <- parse_condition_id(condition_id)
  log_msg("  Year: ", cond$year_prior, " -> ", cond$year_current, "\n")
  log_msg("  Grades: ", cond$grade_prior, " -> ", cond$grade_current, "\n")
  log_msg("  Content: ", cond$content_area, "\n\n")

  # A.1 Longitudinal pairs
  log_msg("A.1  Extracting longitudinal pairs (ground truth)...\n")
  year_prior <- as.character(as.numeric(cond$year_current) - cond$year_span)
  pairs <- create_longitudinal_pairs(
    data = STATE_DATA,
    grade_prior = cond$grade_prior,
    grade_current = cond$grade_current,
    year_prior = year_prior,
    year_current = cond$year_current,
    content_prior = cond$content_area
  )
  log_msg("  Total longitudinal pairs: ", format(nrow(pairs), big.mark = ","), "\n")

  sg_col <- subgroup_col %||% cfg$validation$subgroup_col
  if (is.null(sg_col) || !sg_col %in% names(pairs)) {
    log_msg("  WARNING: Column '", sg_col %||% "NULL", "' not found. Trying SCHOOL_NUMBER.\n")
    sg_col <- "SCHOOL_NUMBER"
  }

  if (!sg_col %in% names(pairs)) {
    log_msg("  No subgroup column available. Using entire condition.\n")
    subgroup_id <- "ALL"
    pairs_sg <- pairs
  } else {
    if (is.null(subgroup_id)) {
      subgroup_id <- cfg$validation$subgroup_id %||% NULL
    }

    sg_sizes <- pairs[, .N, by = sg_col][order(-N)]
    log_msg("  Available subgroups (", sg_col, "): ", nrow(sg_sizes), "\n")
    log_msg("  Largest subgroup: n = ", sg_sizes$N[1], "\n")

    if (!is.null(subgroup_id)) {
      if (identical(as.character(subgroup_id), "ALL")) {
        subgroup_id <- "ALL"
        pairs_sg <- pairs
        log_msg("  Using explicit subgroup: ALL\n")
      } else {
        subgroup_id_chr <- as.character(subgroup_id)
        idx <- which(as.character(pairs[[sg_col]]) == subgroup_id_chr)
        if (length(idx) == 0) {
          stop("Explicit subgroup_id '", subgroup_id_chr, "' not found in column ", sg_col,
               " for condition ", condition_id)
        }
        pairs_sg <- pairs[idx]
        subgroup_id <- subgroup_id_chr
        log_msg("  Using explicit subgroup: ", subgroup_id, " (n = ", nrow(pairs_sg), ")\n")
      }
    } else {
      target_n <- cfg$validation$target_subgroup_n %||% 2500
      min_n <- cfg$validation$min_subgroup_n %||% 500
      big_enough <- sg_sizes[N >= min_n]
      if (nrow(big_enough) == 0) {
        log_msg("  WARNING: No subgroups meet min_n = ", min_n, "\n")
        log_msg("  Using entire condition as one subgroup.\n")
        subgroup_id <- "ALL"
        pairs_sg <- pairs
      } else {
        best_idx <- which.min(abs(big_enough$N - target_n))
        subgroup_id <- as.character(big_enough[[sg_col]][best_idx])
        pairs_sg <- pairs[as.character(get(sg_col)) == subgroup_id]
        log_msg("  Selected subgroup: ", subgroup_id, " (n = ", nrow(pairs_sg), ")\n")
      }
    }
  }
  log_msg("\n")

  # A.2 True SGPc
  log_msg("A.2  Computing true SGPc distribution from longitudinal data...\n")
  copula_mode <- cfg$copula$mode %||% "phase1_best_fit"
  p1 <- tryCatch(
    load_phase1_condition(
      dataset_id,
      condition_id,
      phase1_results_dir = file.path(project_root, "STEP_1_Family_Selection", "results")
    ),
    error = function(e) NULL
  )
  .load_canon <- function() {
    load_canonical_parameters(
      manifest_path = file.path(project_root, "STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json"),
      canonical_params_path = file.path(project_root, "STEP_1_Family_Selection/results/dataset_all/canonical_copula_parameters.csv")
    )
  }

  if (identical(copula_mode, "canonical_only")) {
    canonical <- .load_canon()
    p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
    log_msg("  Copula: canonical (", cond$content_area, ", span=", cond$year_span, ")\n")
  } else if (!is.null(p1) && !is.null(p1$best_fit_copula)) {
    p1_copula <- p1$best_fit_copula
    log_msg("  Loaded Phase 1 copula: ", class(p1_copula)[1], "\n")
  } else {
    log_msg("  WARNING: No Phase 1 copula found. Using canonical t-copula.\n")
    canonical <- .load_canon()
    p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
  }

  u_full <- rank(pairs$SCALE_SCORE_PRIOR) / (nrow(pairs) + 1)
  v_full <- rank(pairs$SCALE_SCORE_CURRENT) / (nrow(pairs) + 1)
  if (subgroup_id == "ALL") {
    sg_idx_a <- seq_len(nrow(pairs))
    u_sg <- u_full
    v_sg <- v_full
  } else {
    sg_idx_a <- which(as.character(pairs[[sg_col]]) == as.character(subgroup_id))
    u_sg <- u_full[sg_idx_a]
    v_sg <- v_full[sg_idx_a]
  }

  truth_source <- cfg$systematic$truth_source %||% "recompute"
  true_sgpc <- NULL
  if (identical(truth_source, "step2_empirical")) {
    step2_dir_raw <- cfg$systematic$step2_results_dir %||% "STEP_2_SGPc_Sensitivity/results"
    step2_dir <- anchor_path(step2_dir_raw)
    step2_file <- file.path(step2_dir, paste0("sgpc_all_variants_", dataset_id, ".rds"))
    if (file.exists(step2_file)) {
      log_msg("  Loading STEP 2 truth from: ", step2_file, "\n")
      s2 <- data.table::setDT(readRDS(step2_file))
      cond_id_match <- condition_id
      s2_cond <- s2[condition_id == cond_id_match]
      if (nrow(s2_cond) > 0 && "sgpc_emp" %in% names(s2_cond)) {
        aligned <- merge(
          data.table::data.table(ID = pairs$ID[sg_idx_a], row_idx = seq_along(sg_idx_a)),
          s2_cond[, .(ID, sgpc_emp)],
          by = "ID", all.x = TRUE, sort = FALSE
        )
        data.table::setorder(aligned, row_idx)
        pct_matched <- mean(!is.na(aligned$sgpc_emp))
        if (pct_matched >= 0.95) {
          true_sgpc <- aligned$sgpc_emp
          n_miss <- sum(is.na(true_sgpc))
          if (n_miss > 0) {
            miss_idx <- which(is.na(true_sgpc))
            true_sgpc[miss_idx] <- sgpc_engine(
              u_sg[miss_idx], v_sg[miss_idx], p1_copula, scale = "percentile"
            )
          }
          log_msg(sprintf("  STEP 2 truth loaded: %d matched (%.1f%%)\n",
                          sum(!is.na(aligned$sgpc_emp)), pct_matched * 100))
        }
      }
      rm(s2)
    }
  }
  if (is.null(true_sgpc)) {
    log_msg("  Computing true SGPc via sgpc_engine\n")
    true_sgpc <- sgpc_engine(u_sg, v_sg, p1_copula, scale = "percentile")
  }
  log_msg("  True SGPc distribution for subgroup:\n")
  log_msg("    Mean: ", round(mean(true_sgpc, na.rm = TRUE), 1), "\n")
  log_msg("    Median: ", round(median(true_sgpc, na.rm = TRUE), 1), "\n")
  log_msg("    SD: ", round(sd(true_sgpc, na.rm = TRUE), 1), "\n\n")

  # Independence diagnostics (P ⟂ U within subgroup)
  assump_cfg <- cfg$assumptions$independence
  u_bins <- as.integer(assump_cfg$u_bins)
  u_bins <- ifelse(is.na(u_bins) || u_bins < 3, 5L, u_bins)
  u_cut <- cut(
    u_sg,
    breaks = unique(as.numeric(quantile(u_sg, probs = seq(0, 1, length.out = u_bins + 1), na.rm = TRUE))),
    include.lowest = TRUE
  )
  spearman_rho <- suppressWarnings(cor(u_sg, true_sgpc, method = "spearman", use = "complete.obs"))
  kw_test <- tryCatch(kruskal.test(true_sgpc ~ u_cut), error = function(e) NULL)
  kw_p <- if (!is.null(kw_test)) as.numeric(kw_test$p.value) else NA_real_
  flag_independence_violation <- (
    (is.finite(spearman_rho) && abs(spearman_rho) > assump_cfg$max_abs_spearman) ||
      (is.finite(kw_p) && kw_p < assump_cfg$alpha)
  )
  diag_summary <- data.table::data.table(
    subgroup_id = subgroup_id,
    metric = c("spearman_rho", "kruskal_p_value", "n_bins", "flag_independence_violation"),
    value = c(spearman_rho, kw_p, u_bins, as.numeric(flag_independence_violation))
  )
  diag_bins <- data.table::data.table(
    subgroup_id = subgroup_id,
    u_bin = as.character(u_cut),
    u_bin_n = 1L,
    mean_sgpc = true_sgpc,
    median_sgpc = true_sgpc
  )[, .(
    u_bin_n = .N,
    mean_sgpc = mean(mean_sgpc, na.rm = TRUE),
    median_sgpc = median(median_sgpc, na.rm = TRUE)
  ), by = .(subgroup_id, u_bin)]
  independence_diagnostics <- data.table::rbindlist(
    list(
      data.table::data.table(
        subgroup_id = subgroup_id,
        u_bin = NA_character_,
        u_bin_n = NA_integer_,
        mean_sgpc = NA_real_,
        median_sgpc = NA_real_,
        metric = diag_summary$metric,
        value = diag_summary$value
      ),
      data.table::data.table(
        subgroup_id = diag_bins$subgroup_id,
        u_bin = diag_bins$u_bin,
        u_bin_n = diag_bins$u_bin_n,
        mean_sgpc = diag_bins$mean_sgpc,
        median_sgpc = diag_bins$median_sgpc,
        metric = "bin_summary",
        value = NA_real_
      )
    ),
    fill = TRUE
  )
  log_msg("  Independence diagnostics:\n")
  log_msg("    Spearman rho(U,SGPc_true): ", round(spearman_rho, 4), "\n")
  log_msg("    Kruskal-Wallis p-value: ", signif(kw_p, 4), "\n")
  log_msg("    Flag violation: ", flag_independence_violation, "\n\n")

  # A.3 references (built from matched pairs, not full cross-section,
  #     to keep marginals consistent with the Step 1 copula)
  log_msg("A.3  Building reference marginals (paired-data ECDFs)...\n")
  refs <- build_pairs_reference(pairs)
  log_msg("  Prior reference: n = ", refs$n_prior, "\n")
  log_msg("  Current reference: n = ", refs$n_current, "\n")

  # A.4 unlinked cross-sections
  log_msg("\nA.4  Creating cross-sectional samples (forgetting the pairing)...\n")
  prior_scores_sg <- pairs_sg$SCALE_SCORE_PRIOR
  current_scores_sg <- pairs_sg$SCALE_SCORE_CURRENT
  u_cross <- reference_cdf(prior_scores_sg, refs$ref_prior)
  v_cross <- reference_cdf(current_scores_sg, refs$ref_current)
  log_msg("  Cross-sectional prior sample:  n = ", length(u_cross), "\n")
  log_msg("  Cross-sectional current sample: n = ", length(v_cross), "\n")
  log_msg("  Note: These are independent samples — no student-level linkage.\n\n")

  # A.5 kernel
  log_msg("A.5  Building transition kernel from baseline copula...\n")
  kernel_cache <- create_kernel_cache(
    p1_copula,
    u_grid_size = cfg$kernel$u_grid_size,
    v_grid_size = cfg$kernel$v_grid_size,
    boundary_buffer = cfg$kernel$boundary_buffer,
    compute_quantile = cfg$kernel$compute_quantile
  )
  log_msg("  Kernel cache built: ", kernel_cache$copula_family, " (",
          paste(names(kernel_cache$copula_params), "=",
                round(unlist(kernel_cache$copula_params), 3), collapse = ", "), ")\n")
  log_msg("  Grid: ", cfg$kernel$u_grid_size, "x", cfg$kernel$v_grid_size, "\n\n")

  # A.6 regime fit
  log_msg("A.6  Estimating growth regime...\n\n")
  family_comparison <- compare_regime_families(
    u_sample = u_cross,
    v_sample = v_cross,
    kernel_cache = kernel_cache,
    families = cfg$regime$families,
    distance_fn = cfg$distance$primary,
    tie_tolerance = cfg$regime$tie_tolerance,
    preferred_family = cfg$regime$preferred_family,
    grid_resolution = cfg$regime$grid_resolution,
    verbose = isTRUE(verbose)
  )
  best_family <- family_comparison$best_family
  best_est <- family_comparison$results[[best_family]]
  log_msg("\n  Best regime family: ", best_family, "\n")
  log_msg("  Estimated median SGPc: ", round(best_est$regime$median * 100, 1), "\n")
  log_msg("  True median SGPc:      ", round(median(true_sgpc, na.rm = TRUE), 1), "\n")
  log_msg("  Difference:            ",
          round(best_est$regime$median * 100 - median(true_sgpc, na.rm = TRUE), 1),
          " SGP points\n\n")
  log_msg("  Estimated mean SGPc:   ", round(best_est$regime$mean * 100, 1), "\n")
  log_msg("  True mean SGPc:        ", round(mean(true_sgpc, na.rm = TRUE), 1), "\n")
  log_msg("  Difference:            ",
          round(best_est$regime$mean * 100 - mean(true_sgpc, na.rm = TRUE), 1),
          " SGP points\n\n")

  # A.7 bootstrap
  log_msg("A.7  Bootstrap uncertainty quantification...\n\n")
  boot_results <- bootstrap_regime(
    u_sample = u_cross,
    v_sample = v_cross,
    kernel_cache = kernel_cache,
    regime_family = best_family,
    distance_fn = cfg$distance$primary,
    n_boot = cfg$uncertainty$n_bootstrap,
    grid_resolution = cfg$uncertainty$bootstrap_grid_resolution,
    resample_scheme = cfg$uncertainty$resample_scheme,
    seed = cfg$seed,
    use_mirai = use_mirai,
    verbose = isTRUE(verbose)
  )
  log_msg("  Bootstrap median SGPc 95% CI (independent): ",
          paste0("[", round(boot_results$ci_median_sgpc[1], 1), ", ",
                 round(boot_results$ci_median_sgpc[2], 1), "]"), "\n")
  log_msg("  Bootstrap mean SGPc 95% CI (independent):   ",
          paste0("[", round(boot_results$ci_mean_sgpc[1], 1), ", ",
                 round(boot_results$ci_mean_sgpc[2], 1), "]"), "\n\n")

  # A.7b paired bootstrap
  log_msg("A.7b Paired bootstrap (linkage premium decomposition)...\n\n")
  boot_paired <- bootstrap_regime(
    u_sample = u_cross,
    v_sample = v_cross,
    kernel_cache = kernel_cache,
    regime_family = best_family,
    distance_fn = cfg$distance$primary,
    n_boot = cfg$uncertainty$n_bootstrap,
    grid_resolution = cfg$uncertainty$bootstrap_grid_resolution,
    resample_scheme = cfg$uncertainty$resample_scheme,
    pairing = "paired",
    seed = cfg$seed + 1L,
    use_mirai = use_mirai,
    verbose = isTRUE(verbose)
  )
  log_msg("  Bootstrap median SGPc 95% CI (paired):      ",
          paste0("[", round(boot_paired$ci_median_sgpc[1], 1), ", ",
                 round(boot_paired$ci_median_sgpc[2], 1), "]"), "\n")
  log_msg("  Bootstrap mean SGPc 95% CI (paired):        ",
          paste0("[", round(boot_paired$ci_mean_sgpc[1], 1), ", ",
                 round(boot_paired$ci_mean_sgpc[2], 1), "]"), "\n\n")

  ci_w_indep_median <- diff(as.numeric(boot_results$ci_median_sgpc))
  ci_w_paired_median <- diff(as.numeric(boot_paired$ci_median_sgpc))
  ci_w_indep_mean <- diff(as.numeric(boot_results$ci_mean_sgpc))
  ci_w_paired_mean <- diff(as.numeric(boot_paired$ci_mean_sgpc))
  phase_a_linkage_premium <- list(
    n_observed = nrow(pairs_sg),
    median = list(
      ci_paired = as.numeric(boot_paired$ci_median_sgpc),
      ci_independent = as.numeric(boot_results$ci_median_sgpc),
      ci_width_paired = round(ci_w_paired_median, 2),
      ci_width_independent = round(ci_w_indep_median, 2),
      se_paired = round(boot_paired$se_median_sgpc, 4),
      se_independent = round(boot_results$se_median_sgpc, 4),
      ci_ratio = if (is.finite(ci_w_paired_median) && ci_w_paired_median > 0)
        round(ci_w_indep_median / ci_w_paired_median, 2) else NA_real_,
      se_ratio = if (is.finite(boot_paired$se_median_sgpc) && boot_paired$se_median_sgpc > 0)
        round(boot_results$se_median_sgpc / boot_paired$se_median_sgpc, 2) else NA_real_
    ),
    mean = list(
      ci_paired = as.numeric(boot_paired$ci_mean_sgpc),
      ci_independent = as.numeric(boot_results$ci_mean_sgpc),
      ci_width_paired = round(ci_w_paired_mean, 2),
      ci_width_independent = round(ci_w_indep_mean, 2),
      se_paired = round(boot_paired$se_mean_sgpc, 4),
      se_independent = round(boot_results$se_mean_sgpc, 4),
      ci_ratio = if (is.finite(ci_w_paired_mean) && ci_w_paired_mean > 0)
        round(ci_w_indep_mean / ci_w_paired_mean, 2) else NA_real_,
      se_ratio = if (is.finite(boot_paired$se_mean_sgpc) && boot_paired$se_mean_sgpc > 0)
        round(boot_results$se_mean_sgpc / boot_paired$se_mean_sgpc, 2) else NA_real_
    ),
    description = paste0(
      "Linkage premium at N=", nrow(pairs_sg), ": independent-bootstrap CI width / paired-bootstrap CI width."
    )
  )

  # A.8 plots
  log_msg("\nA.8  Generating diagnostic plots...\n")
  viz_dir <- file.path(output_dir, "visualizations", "phase_a")
  if (!dir.exists(viz_dir)) dir.create(viz_dir, recursive = TRUE)
  sg_label <- paste0(condition_id, " / ", sg_col, " = ", subgroup_id)
  phasea_fig <- if (exists("get_phasea_figure_map", mode = "function")) {
    get_phasea_figure_map()
  } else {
    list(
      marginal_uv_density = "phasea_01_marginals_uv_density",
      objective_surface = "phasea_02a_objective_surface",
      forward_cdf_check = "phasea_02b_forward_cdf_check",
      residual_diagnostics = "phasea_02c_residual_diagnostics",
      regime_density = "phasea_03a_regime_density",
      bootstrap_median = "phasea_03b_bootstrap_median_sgpc",
      bootstrap_mean = "phasea_03c_bootstrap_mean_sgpc",
      bootstrap_combined = "phasea_03d_bootstrap_combined",
      recovery_summary = "phasea_03e_recovery_summary",
      linkage_decomposition = "phasea_03f_linkage_decomposition",
      independence_diagnostic = "phasea_04_independence_diagnostic"
    )
  }

  plot_marginal_uv_density(
    u_sample = u_cross, v_sample = v_cross, output_dir = viz_dir,
    filename = phasea_fig$marginal_uv_density,
    title = paste0("A. Unlinked Marginals — ", sg_label)
  )
  best_est$F_uniform <- predict_marginal_cdf(
    v_grid = best_est$v_grid, u_sample = u_cross,
    regime = regime_beta(0.5, 2), kernel_cache = kernel_cache
  )
  best_est$F_tamp <- ecdf(u_cross)(best_est$v_grid)
  best_est$w1_uniform <- wasserstein1(best_est$F_uniform, best_est$F_obs, best_est$v_grid)
  plot_observed_vs_predicted_cdf(
    best_est, title = paste0("B2. Forward CDF Check — ", sg_label),
    output_dir = viz_dir, filename = phasea_fig$forward_cdf_check
  )
  plot_objective_surface(
    best_est, output_dir = viz_dir, filename = phasea_fig$objective_surface,
    title = paste0("Growth Regime Surface — ", sg_label)
  )
  plot_regime_shape(
    best_est$regime, true_sgpc, title = paste0("C. Inferred Regime Density — ", sg_label),
    output_dir = viz_dir, filename = phasea_fig$regime_density, bootstrap = boot_results
  )
  plot_residual_curve(
    best_est, output_dir = viz_dir, filename = phasea_fig$residual_diagnostics,
    title = paste0("Residual Diagnostics — ", sg_label)
  )
  plot_recovery_summary(
    best_est, true_sgpc, title = paste0("Growth Regime Recovery Summary: ", sg_label),
    output_dir = viz_dir, filename = phasea_fig$recovery_summary
  )
  plot_independence_diagnostic(
    u_sample = u_sg, true_sgpc = true_sgpc, n_bins = u_bins,
    output_dir = viz_dir, filename = phasea_fig$independence_diagnostic,
    title = paste0("I. Independence Diagnostic — ", sg_label)
  )
  plot_bootstrap_sgpc(
    boot_results, measure = "median", true_sgpc = true_sgpc,
    title = paste0("Bootstrap Uncertainty: Median SGPc — ", sg_label),
    output_dir = viz_dir, filename = phasea_fig$bootstrap_median
  )
  plot_bootstrap_sgpc(
    boot_results, measure = "mean", true_sgpc = true_sgpc,
    title = paste0("Bootstrap Uncertainty: Mean SGPc — ", sg_label),
    output_dir = viz_dir, filename = phasea_fig$bootstrap_mean
  )
  plot_bootstrap_sgpc_combined(
    boot_results, true_sgpc = true_sgpc,
    title = paste0("Bootstrap Uncertainty: Median & Mean SGPc — ", sg_label),
    output_dir = viz_dir, filename = phasea_fig$bootstrap_combined
  )
  plot_linkage_decomposition(
    boot_independent = boot_results, boot_paired = boot_paired, true_sgpc = true_sgpc,
    linkage_premium = phase_a_linkage_premium,
    title = paste0("Linkage Premium Decomposition — ", sg_label),
    output_dir = viz_dir, filename = phasea_fig$linkage_decomposition
  )
  if (exists("write_phasea_legacy_aliases", mode = "function")) {
    write_phasea_legacy_aliases(
      output_dir = viz_dir,
      enable_alias = isTRUE(cfg$output$phase_a_legacy_alias_plots),
      formats = cfg$output$export_formats
    )
  }
  log_msg("  Plots saved to: ", viz_dir, "\n\n")

  # A.9 save results
  log_msg("A.9  Saving Phase A results...\n")
  phase_a_results <- list(
    condition_id = condition_id,
    condition_meta = cond,
    dataset_id = dataset_id,
    subgroup_id = subgroup_id,
    subgroup_col = sg_col,
    n_subgroup = nrow(pairs_sg),
    true_sgpc = true_sgpc,
    independence_diagnostics = independence_diagnostics,
    flag_independence_violation = flag_independence_violation,
    family_comparison = family_comparison,
    best_family = best_family,
    best_estimate = best_est,
    bootstrap = boot_results,
    bootstrap_paired = boot_paired,
    linkage_premium = phase_a_linkage_premium,
    u_sample = u_cross,
    v_sample = v_cross,
    kernel_cache = kernel_cache,
    references = list(n_prior = refs$n_prior, n_current = refs$n_current),
    copula_used = list(family = kernel_cache$copula_family, params = kernel_cache$copula_params),
    config = cfg,
    output_dir = output_dir
  )

  saveRDS(phase_a_results, file.path(output_dir, "phase_a_deep_dive.rds"))

  w1_red <- if (is.finite(best_est$w1_uniform) && best_est$w1_uniform > 0) {
    round(100 * (1 - (best_est$all_distances$wasserstein1 / best_est$w1_uniform)), 2)
  } else NA_real_

  summary_row <- data.frame(
    condition_id = condition_id,
    subgroup_id = subgroup_id,
    n_subgroup = nrow(pairs_sg),
    regime_family = best_family,
    median_sgpc_inferred = round(best_est$regime$median * 100, 2),
    mean_sgpc_inferred = round(best_est$regime$mean * 100, 2),
    median_sgpc_true = round(median(true_sgpc, na.rm = TRUE), 2),
    mean_sgpc_true = round(mean(true_sgpc, na.rm = TRUE), 2),
    median_diff = round(best_est$regime$median * 100 - median(true_sgpc, na.rm = TRUE), 2),
    mean_diff = round(best_est$regime$mean * 100 - mean(true_sgpc, na.rm = TRUE), 2),
    w1_uniform = round(best_est$w1_uniform, 6),
    w1_reduction_pct = w1_red,
    max_abs_residual = round(max(abs(best_est$F_pred - best_est$F_obs), na.rm = TRUE), 6),
    mean_abs_residual = round(mean(abs(best_est$F_pred - best_est$F_obs), na.rm = TRUE), 6),
    wasserstein1 = round(best_est$all_distances$wasserstein1, 6),
    cvm = round(best_est$all_distances$cramer_von_mises, 6),
    boot_ci_lo = round(boot_results$ci_median_sgpc[1], 1),
    boot_ci_hi = round(boot_results$ci_median_sgpc[2], 1),
    boot_ci_mean_lo = round(boot_results$ci_mean_sgpc[1], 1),
    boot_ci_mean_hi = round(boot_results$ci_mean_sgpc[2], 1),
    boot_se = round(boot_results$se_median_sgpc, 2),
    boot_paired_ci_lo = round(boot_paired$ci_median_sgpc[1], 1),
    boot_paired_ci_hi = round(boot_paired$ci_median_sgpc[2], 1),
    boot_paired_ci_mean_lo = round(boot_paired$ci_mean_sgpc[1], 1),
    boot_paired_ci_mean_hi = round(boot_paired$ci_mean_sgpc[2], 1),
    boot_paired_se = round(boot_paired$se_median_sgpc, 2),
    linkage_ci_ratio_median = phase_a_linkage_premium$median$ci_ratio,
    linkage_ci_ratio_mean = phase_a_linkage_premium$mean$ci_ratio,
    spearman_rho_u_sgpc_true = round(spearman_rho, 6),
    kruskal_p_u_bins = round(kw_p, 8),
    flag_independence_violation = flag_independence_violation,
    stringsAsFactors = FALSE
  )
  data.table::fwrite(summary_row, file.path(output_dir, "phase_a_summary.csv"))

  se_median <- if (!is.null(boot_results$se_median_sgpc)) boot_results$se_median_sgpc else NA_real_
  se_mean <- if (!is.null(boot_results$se_mean_sgpc)) boot_results$se_mean_sgpc else NA_real_
  se_paired_median <- if (!is.null(boot_paired$se_median_sgpc)) boot_paired$se_median_sgpc else NA_real_
  se_paired_mean <- if (!is.null(boot_paired$se_mean_sgpc)) boot_paired$se_mean_sgpc else NA_real_
  precision_anchor <- data.table::data.table(
    dataset_id = dataset_id,
    condition_id = condition_id,
    subgroup_id = subgroup_id,
    n0 = nrow(pairs_sg),
    pairing = c("independent", "independent", "paired", "paired"),
    measure = c("median_sgpc", "mean_sgpc", "median_sgpc", "mean_sgpc"),
    estimate = c(
      round(best_est$regime$median * 100, 2),
      round(best_est$regime$mean * 100, 2),
      round(best_est$regime$median * 100, 2),
      round(best_est$regime$mean * 100, 2)
    ),
    se0 = c(round(se_median, 4), round(se_mean, 4), round(se_paired_median, 4), round(se_paired_mean, 4)),
    ci95_lo = c(
      round(boot_results$ci_median_sgpc[1], 4),
      round(boot_results$ci_mean_sgpc[1], 4),
      round(boot_paired$ci_median_sgpc[1], 4),
      round(boot_paired$ci_mean_sgpc[1], 4)
    ),
    ci95_hi = c(
      round(boot_results$ci_median_sgpc[2], 4),
      round(boot_results$ci_mean_sgpc[2], 4),
      round(boot_paired$ci_median_sgpc[2], 4),
      round(boot_paired$ci_mean_sgpc[2], 4)
    )
  )
  precision_anchor[, ci95_width := round(ci95_hi - ci95_lo, 4)]
  data.table::fwrite(precision_anchor, file.path(output_dir, "phase_a_precision_anchor.csv"))

  phase_a_exports <- export_phase_a_figure_data(
    phase_a_results = phase_a_results,
    output_dir = output_dir,
    write_files = TRUE
  )
  export_phase_a_dir <- file.path(output_dir, "exports", "phase_a")
  if (!dir.exists(export_phase_a_dir)) dir.create(export_phase_a_dir, recursive = TRUE)
  data.table::fwrite(independence_diagnostics, file.path(export_phase_a_dir, "step3_independence_diagnostics.csv"))

  phase_a_results$figure_exports <- list(
    cdf_rows = nrow(phase_a_exports$cdf_curves),
    objective_rows = nrow(phase_a_exports$objective_surface),
    density_rows = nrow(phase_a_exports$regime_density),
    independence_rows = nrow(independence_diagnostics)
  )
  saveRDS(phase_a_results, file.path(output_dir, "phase_a_deep_dive.rds"))
  export_phase_a_manifest(phase_a_results, output_dir = output_dir, prefix = "phase_a")

  log_msg("  Saved: phase_a_deep_dive.rds, phase_a_summary.csv\n")
  log_msg("  Saved: phase_a_precision_anchor.csv\n")
  log_msg("  Saved: phase_a_analytic_payload.rds and exports/phase_a/*.csv\n")
  log_msg("  Saved: exports/phase_a/step3_independence_diagnostics.csv\n")
  log_msg("  Saved: phase_a_manifest.json, phase_a_manifest.md\n")
  log_msg("\n--- Phase A complete ---\n\n")

  return(invisible(phase_a_results))
}

cat("STEP 3 run_deep_dive.R loaded.\n")
cat("  Function: run_deep_dive(dataset_id, condition_id, subgroup_id, output_dir, ...)\n")
