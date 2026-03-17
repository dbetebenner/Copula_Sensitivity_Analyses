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

  # A.1b Churn Bookkeeping and Marginal Comparison
  churn_bk <- NULL
  marginal_comp <- NULL
  if (exists("compute_churn_bookkeeping", mode = "function")) {
    log_msg("A.1b Churn bookkeeping (S/L/E decomposition)...\n")
    churn_bk <- tryCatch(
      compute_churn_bookkeeping(STATE_DATA, pairs, cond, sg_col = sg_col),
      error = function(e) { log_msg("  WARNING: Churn bookkeeping failed: ", e$message, "\n"); NULL }
    )
    if (!is.null(churn_bk)) {
      cb <- churn_bk$condition
      log_msg("  Condition-level: n_S = ", format(cb$n_stayers, big.mark = ","),
              ", n_L = ", format(cb$n_leavers, big.mark = ","),
              ", n_E = ", format(cb$n_entrants, big.mark = ","), "\n")
      log_msg("  Retention: alpha = ", cb$alpha, " (prior), beta = ", cb$beta, " (current)\n")
      log_msg("  Churn type: ", cb$churn_type, "\n")
    }

    log_msg("  Marginal comparison (compositional ignorability test)...\n")
    marginal_comp <- tryCatch(
      compare_marginals_stayer_vs_all(STATE_DATA, pairs, cond),
      error = function(e) { log_msg("  WARNING: Marginal comparison failed: ", e$message, "\n"); NULL }
    )
    if (!is.null(marginal_comp)) {
      log_msg("  Gamma_U (prior)   = ", marginal_comp$gamma_prior, "\n")
      log_msg("  Gamma_V (current) = ", marginal_comp$gamma_current, "\n")
      log_msg("  Compositionally ignorable: ", marginal_comp$compositionally_ignorable, "\n")
      if (is.finite(marginal_comp$asymmetry_ratio)) {
        log_msg("  Asymmetry ratio (Gamma_V / Gamma_U) = ", marginal_comp$asymmetry_ratio, "\n")
      }
      # Upgrade churn classification if compositional drift detected
      if (!is.null(churn_bk) && !isTRUE(marginal_comp$compositionally_ignorable)) {
        churn_bk$condition$churn_type <- paste0(churn_bk$condition$churn_type, "+compositional")
        log_msg("  Updated churn type: ", churn_bk$condition$churn_type, "\n")
      }
    }
    log_msg("\n")
  }

  # A.2 True SGPc
  log_msg("A.2  Computing true SGPc distribution from longitudinal data...\n")
  copula_mode <- cfg$copula$mode %||% "comparison"
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

  # --- Copula loading: primary + optional alternative for comparison mode ---
  # In "comparison" mode we load both canonical AND per-condition best-fit.
  # The canonical copula is always the primary (honest NAEP/TIMSS setting);
  # the best-fit is the alternative whose delta quantifies copula choice impact.
  alt_copula <- NULL
  alt_copula_label <- NULL
  primary_copula_label <- NULL

  if (identical(copula_mode, "canonical_only")) {
    canonical <- .load_canon()
    p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
    primary_copula_label <- paste0("Canonical t (", cond$content_area, ", span=", cond$year_span, ")")
    log_msg("  Copula: ", primary_copula_label, "\n")

  } else if (identical(copula_mode, "comparison")) {
    # Primary = canonical (the honest setting)
    canonical <- .load_canon()
    p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
    primary_copula_label <- paste0("Canonical t (", cond$content_area, ", span=", cond$year_span, ")")
    log_msg("  Primary copula: ", primary_copula_label, "\n")

    # Alternative = per-condition best-fit from Phase 1
    if (!is.null(p1) && !is.null(p1$best_fit_copula)) {
      alt_copula <- p1$best_fit_copula
      alt_fam <- class(alt_copula)[1]
      # Extract a readable label for the best-fit copula
      alt_copula_label <- paste0("Best-fit parametric (", alt_fam, ")")
      log_msg("  Alternative copula: ", alt_copula_label, "\n")
      # Check whether canonical and best-fit are effectively the same copula
      canon_class <- class(p1_copula)[1]
      if (identical(canon_class, alt_fam)) {
        canon_params <- tryCatch(copula::getTheta(p1_copula, freeOnly = FALSE, named = TRUE),
                                 error = function(e) NULL)
        alt_params <- tryCatch(copula::getTheta(alt_copula, freeOnly = FALSE, named = TRUE),
                               error = function(e) NULL)
        if (!is.null(canon_params) && !is.null(alt_params) &&
            length(canon_params) == length(alt_params) &&
            all(abs(canon_params - alt_params) < 1e-4)) {
          log_msg("  NOTE: Canonical and best-fit copulas are identical — comparison will show zero delta.\n")
        }
      }
    } else {
      log_msg("  WARNING: No Phase 1 best-fit copula found. Comparison mode degrades to canonical_only.\n")
      copula_mode <- "canonical_only"  # graceful fallback
    }

  } else if (!is.null(p1) && !is.null(p1$best_fit_copula)) {
    # phase1_best_fit mode
    p1_copula <- p1$best_fit_copula
    primary_copula_label <- paste0("Best-fit parametric (", class(p1_copula)[1], ")")
    log_msg("  Loaded Phase 1 copula: ", primary_copula_label, "\n")
  } else {
    log_msg("  WARNING: No Phase 1 copula found. Using canonical t-copula.\n")
    canonical <- .load_canon()
    p1_copula <- create_canonical_copula(cond$year_span, cond$content_area, canonical$canonical_params)
    primary_copula_label <- paste0("Canonical t (", cond$content_area, ", span=", cond$year_span, ")")
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

  # A.6 regime fit (primary copula)
  # Resolve which metric(s) to optimize: "both", "wasserstein1", or "cvm"
  optimize_metric <- cfg$distance$optimize
  if (is.null(optimize_metric)) optimize_metric <- cfg$distance$primary
  log_msg("A.6  Estimating growth regime (optimize=", optimize_metric,
          ", copula=", primary_copula_label, ")...\n\n")
  a6_start <- Sys.time()
  family_comparison <- compare_regime_families(
    u_sample = u_cross,
    v_sample = v_cross,
    kernel_cache = kernel_cache,
    families = cfg$regime$families,
    distance_fn = optimize_metric,
    tie_tolerance = cfg$regime$tie_tolerance,
    preferred_family = cfg$regime$preferred_family,
    grid_resolution = cfg$regime$grid_resolution,
    verbose = isTRUE(verbose)
  )
  a6_elapsed <- as.numeric(difftime(Sys.time(), a6_start, units = "secs"))
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

  # Report CvM-optimized alternative if dual-metric mode was used
  best_est_cvm <- NULL
  if (!is.null(best_est$alt_metrics) && !is.null(best_est$alt_metrics$cvm)) {
    best_est_cvm <- best_est$alt_metrics$cvm
    log_msg("  --- CvM-optimized alternative ---\n")
    log_msg("  CvM median SGPc:  ", round(best_est_cvm$regime$median * 100, 1), "\n")
    log_msg("  CvM mean SGPc:    ", round(best_est_cvm$regime$mean * 100, 1), "\n")
    median_delta <- abs(best_est$regime$median - best_est_cvm$regime$median) * 100
    mean_delta <- abs(best_est$regime$mean - best_est_cvm$regime$mean) * 100
    log_msg("  W1 vs CvM delta:  |median|=", round(median_delta, 2),
            "  |mean|=", round(mean_delta, 2), " SGP points\n\n")
  } else if (!is.null(best_est$alt_metrics) && !is.null(best_est$alt_metrics$wasserstein1)) {
    # Primary was CvM; W1 is the alternative
    best_est_w1_alt <- best_est$alt_metrics$wasserstein1
    log_msg("  --- W1-optimized alternative ---\n")
    log_msg("  W1 median SGPc:   ", round(best_est_w1_alt$regime$median * 100, 1), "\n")
    log_msg("  W1 mean SGPc:     ", round(best_est_w1_alt$regime$mean * 100, 1), "\n\n")
  }
  log_msg("  A.6 elapsed: ", round(a6_elapsed, 1), "s\n\n")

  # A.6b Alternative copula regime estimation (comparison mode only)
  alt_kernel_cache <- NULL
  alt_family_comparison <- NULL
  alt_best_est <- NULL
  alt_best_family <- NULL
  copula_sensitivity <- NULL

  if (identical(copula_mode, "comparison") && !is.null(alt_copula)) {
    log_msg("A.6b Estimating growth regime under alternative copula (",
            alt_copula_label, ")...\n\n")
    a6b_start <- Sys.time()

    # Build kernel cache for the alternative copula
    alt_kernel_cache <- create_kernel_cache(
      alt_copula,
      u_grid_size = cfg$kernel$u_grid_size,
      v_grid_size = cfg$kernel$v_grid_size,
      boundary_buffer = cfg$kernel$boundary_buffer,
      compute_quantile = cfg$kernel$compute_quantile
    )
    log_msg("  Alt kernel cache built: ", alt_kernel_cache$copula_family, " (",
            paste(names(alt_kernel_cache$copula_params), "=",
                  round(unlist(alt_kernel_cache$copula_params), 3), collapse = ", "), ")\n")

    # Run regime estimation with same settings
    alt_family_comparison <- compare_regime_families(
      u_sample = u_cross,
      v_sample = v_cross,
      kernel_cache = alt_kernel_cache,
      families = cfg$regime$families,
      distance_fn = optimize_metric,
      tie_tolerance = cfg$regime$tie_tolerance,
      preferred_family = cfg$regime$preferred_family,
      grid_resolution = cfg$regime$grid_resolution,
      verbose = isTRUE(verbose)
    )
    alt_best_family <- alt_family_comparison$best_family
    alt_best_est <- alt_family_comparison$results[[alt_best_family]]

    a6b_elapsed <- as.numeric(difftime(Sys.time(), a6b_start, units = "secs"))

    # Compute copula sensitivity deltas
    median_true <- median(true_sgpc, na.rm = TRUE)
    mean_true   <- mean(true_sgpc, na.rm = TRUE)
    # Extract CvM-optimised result under alt copula (4th cell of metric × copula)
    alt_best_est_cvm <- NULL
    if (!is.null(alt_best_est$alt_metrics) && !is.null(alt_best_est$alt_metrics$cvm)) {
      alt_best_est_cvm <- alt_best_est$alt_metrics$cvm
      log_msg("  Alt copula CvM-optimised: median=",
              round(alt_best_est_cvm$regime$median * 100, 1),
              "  mean=", round(alt_best_est_cvm$regime$mean * 100, 1), "\n")
    }

    copula_sensitivity <- list(
      primary_copula_label  = primary_copula_label,
      alt_copula_label      = alt_copula_label,
      primary_copula        = p1_copula,
      alt_copula            = alt_copula,
      # W1-optimised results (primary metric)
      primary_median_sgpc   = best_est$regime$median * 100,
      alt_median_sgpc       = alt_best_est$regime$median * 100,
      primary_mean_sgpc     = best_est$regime$mean * 100,
      alt_mean_sgpc         = alt_best_est$regime$mean * 100,
      delta_median_sgpc     = (alt_best_est$regime$median - best_est$regime$median) * 100,
      delta_mean_sgpc       = (alt_best_est$regime$mean - best_est$regime$mean) * 100,
      primary_median_diff   = best_est$regime$median * 100 - median_true,
      alt_median_diff       = alt_best_est$regime$median * 100 - median_true,
      primary_mean_diff     = best_est$regime$mean * 100 - mean_true,
      alt_mean_diff         = alt_best_est$regime$mean * 100 - mean_true,
      primary_w1            = best_est$all_distances$wasserstein1,
      alt_w1                = alt_best_est$all_distances$wasserstein1,
      primary_cvm           = best_est$all_distances$cramer_von_mises,
      alt_cvm               = alt_best_est$all_distances$cramer_von_mises,
      # CvM-optimised results (secondary metric)
      primary_cvm_est       = best_est_cvm,       # canonical copula, CvM metric
      alt_cvm_est           = alt_best_est_cvm,    # best-fit copula, CvM metric
      # Full result objects for individual plot generation
      alt_best_est          = alt_best_est,
      alt_family_comparison = alt_family_comparison,
      alt_kernel_cache      = alt_kernel_cache
    )

    log_msg("\n  --- Copula sensitivity comparison ---\n")
    log_msg("  Primary (", primary_copula_label, "):\n")
    log_msg("    Median SGPc: ", round(copula_sensitivity$primary_median_sgpc, 1),
            "  (diff from truth: ", round(copula_sensitivity$primary_median_diff, 1), ")\n")
    log_msg("    Mean SGPc:   ", round(copula_sensitivity$primary_mean_sgpc, 1),
            "  (diff from truth: ", round(copula_sensitivity$primary_mean_diff, 1), ")\n")
    log_msg("    W1: ", round(copula_sensitivity$primary_w1, 6),
            "  CvM: ", round(copula_sensitivity$primary_cvm, 6), "\n")
    log_msg("  Alternative (", alt_copula_label, "):\n")
    log_msg("    Median SGPc: ", round(copula_sensitivity$alt_median_sgpc, 1),
            "  (diff from truth: ", round(copula_sensitivity$alt_median_diff, 1), ")\n")
    log_msg("    Mean SGPc:   ", round(copula_sensitivity$alt_mean_sgpc, 1),
            "  (diff from truth: ", round(copula_sensitivity$alt_mean_diff, 1), ")\n")
    log_msg("    W1: ", round(copula_sensitivity$alt_w1, 6),
            "  CvM: ", round(copula_sensitivity$alt_cvm, 6), "\n")
    log_msg("  Delta (alt - primary):\n")
    log_msg("    |Median|: ", round(abs(copula_sensitivity$delta_median_sgpc), 2), " SGP points\n")
    log_msg("    |Mean|:   ", round(abs(copula_sensitivity$delta_mean_sgpc), 2), " SGP points\n")
    log_msg("  A.6b elapsed: ", round(a6b_elapsed, 1), "s\n\n")
  }

  # A.7 bootstrap
  log_msg("A.7  Bootstrap uncertainty quantification...\n\n")
  a7_start <- Sys.time()
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
  a7_elapsed <- as.numeric(difftime(Sys.time(), a7_start, units = "secs"))
  log_msg("  Bootstrap median SGPc 95% CI (independent): ",
          paste0("[", round(boot_results$ci_median_sgpc[1], 1), ", ",
                 round(boot_results$ci_median_sgpc[2], 1), "]"), "\n")
  log_msg("  Bootstrap mean SGPc 95% CI (independent):   ",
          paste0("[", round(boot_results$ci_mean_sgpc[1], 1), ", ",
                 round(boot_results$ci_mean_sgpc[2], 1), "]"), "\n")
  log_msg("  A.7 elapsed: ", round(a7_elapsed, 1), "s\n\n")

  # A.7b paired bootstrap
  log_msg("A.7b Paired bootstrap (linkage premium decomposition)...\n\n")
  a7b_start <- Sys.time()
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
  a7b_elapsed <- as.numeric(difftime(Sys.time(), a7b_start, units = "secs"))
  log_msg("  Bootstrap median SGPc 95% CI (paired):      ",
          paste0("[", round(boot_paired$ci_median_sgpc[1], 1), ", ",
                 round(boot_paired$ci_median_sgpc[2], 1), "]"), "\n")
  log_msg("  Bootstrap mean SGPc 95% CI (paired):        ",
          paste0("[", round(boot_paired$ci_mean_sgpc[1], 1), ", ",
                 round(boot_paired$ci_mean_sgpc[2], 1), "]"), "\n")
  log_msg("  A.7b elapsed: ", round(a7b_elapsed, 1), "s\n\n")

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

  # A.7c Regime contrast and theoretical premium
  regime_contrast <- NULL
  theoretical_prem <- NULL
  if (exists("estimate_regime_all_students", mode = "function") &&
      !is.null(churn_bk) && churn_bk$condition$n_leavers + churn_bk$condition$n_entrants > 0) {
    log_msg("A.7c Regime contrast (stayer vs all-student)...\n")
    a7c_start <- Sys.time()
    regime_contrast <- tryCatch(
      estimate_regime_all_students(
        state_data      = STATE_DATA,
        condition_meta  = cond,
        refs_stayer     = refs,
        kernel_cache    = kernel_cache,
        regime_family   = best_family,
        distance_fn     = cfg$distance$primary,
        grid_resolution = cfg$estimation$grid_resolution %||% 25L,
        stayer_estimate = best_est
      ),
      error = function(e) { log_msg("  WARNING: Regime contrast failed: ", e$message, "\n"); NULL }
    )
    if (!is.null(regime_contrast)) {
      log_msg("  All-student regime: median = ", regime_contrast$median_sgpc_all,
              ", mean = ", regime_contrast$mean_sgpc_all, "\n")
      log_msg("  Stayer regime:      median = ", regime_contrast$median_sgpc_stayer,
              ", mean = ", regime_contrast$mean_sgpc_stayer, "\n")
      log_msg("  Delta median = ", regime_contrast$delta_median,
              ", delta mean = ", regime_contrast$delta_mean, " SGPc\n")
    }
    a7c_elapsed <- as.numeric(difftime(Sys.time(), a7c_start, units = "secs"))
    log_msg("  A.7c elapsed: ", round(a7c_elapsed, 1), "s\n\n")
  }

  if (exists("theoretical_linkage_premium", mode = "function") && !is.null(churn_bk)) {
    log_msg("A.7d Theoretical partial-linkage premium...\n")
    cop_rho <- tryCatch(as.numeric(p1_copula@param[1]), error = function(e) NA_real_)
    emp_alpha <- churn_bk$condition$alpha
    theoretical_prem <- theoretical_linkage_premium(emp_alpha, cop_rho)
    log_msg("  alpha = ", theoretical_prem$alpha, ", rho = ", theoretical_prem$rho, "\n")
    log_msg("  Theoretical mean-scale premium = ", theoretical_prem$mean_scale, "\n")
    log_msg("  Theoretical CDF-scale premium = ", theoretical_prem$cdf_scale, "\n")
    log_msg("  Empirical bootstrap premium (median CI ratio) = ",
            phase_a_linkage_premium$median$ci_ratio, "\n\n")
  }

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
      independence_diagnostic = "phasea_04_independence_diagnostic",
      copula_alt_forward_cdf = "phasea_05a_copula_bestfit_forward_cdf",
      copula_alt_regime_density = "phasea_05b_copula_bestfit_regime_density",
      copula_alt_recovery_summary = "phasea_05c_copula_bestfit_recovery_summary",
      copula_comparison_panel = "phasea_05d_copula_comparison_panel"
    )
  }

  # Copula label for plot subtitles — only annotate when in comparison mode
  copula_subtitle <- if (identical(copula_mode, "comparison")) {
    paste0("Copula: ", primary_copula_label)
  } else {
    NULL
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
  .cdf_title <- if (!is.null(copula_subtitle)) {
    paste0("B2. Forward CDF Check — ", sg_label, "\n", copula_subtitle)
  } else {
    paste0("B2. Forward CDF Check — ", sg_label)
  }
  plot_observed_vs_predicted_cdf(
    best_est, title = .cdf_title,
    output_dir = viz_dir, filename = phasea_fig$forward_cdf_check
  )
  plot_objective_surface(
    best_est, output_dir = viz_dir, filename = phasea_fig$objective_surface,
    title = if (!is.null(copula_subtitle)) {
      paste0("Growth Regime Surface — ", sg_label, "\n", copula_subtitle)
    } else {
      paste0("Growth Regime Surface — ", sg_label)
    }
  )
  .regime_title <- if (!is.null(copula_subtitle)) {
    paste0("C. Inferred Regime Density — ", sg_label, "\n", copula_subtitle)
  } else {
    paste0("C. Inferred Regime Density — ", sg_label)
  }
  plot_regime_shape(
    best_est$regime, true_sgpc, title = .regime_title,
    output_dir = viz_dir, filename = phasea_fig$regime_density, bootstrap = boot_results
  )
  plot_residual_curve(
    best_est, output_dir = viz_dir, filename = phasea_fig$residual_diagnostics,
    title = if (!is.null(copula_subtitle)) {
      paste0("Residual Diagnostics — ", sg_label, "\n", copula_subtitle)
    } else {
      paste0("Residual Diagnostics — ", sg_label)
    }
  )
  .recovery_title <- if (!is.null(copula_subtitle)) {
    paste0("Growth Regime Recovery Summary: ", sg_label, "\n", copula_subtitle)
  } else {
    paste0("Growth Regime Recovery Summary: ", sg_label)
  }
  plot_recovery_summary(
    best_est, true_sgpc, title = .recovery_title,
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

  # --- Churn diagnostic plots ---
  if (!is.null(churn_bk)) {
    log_msg("  Generating churn diagnostic plots...\n")
    tryCatch({
      plot_churn_decomposition(
        churn_bk, condition_label = sg_label,
        filename = phasea_fig$churn_decomposition,
        output_dir = viz_dir
      )
      if (!is.null(marginal_comp)) {
        plot_marginal_comparison(
          marginal_comp, condition_label = sg_label,
          filename = phasea_fig$marginal_comparison,
          output_dir = viz_dir
        )
      }
      if (!is.null(regime_contrast) && !is.null(regime_contrast$regime_all)) {
        plot_regime_contrast(
          regime_contrast, stayer_estimate = best_est,
          true_sgpc = true_sgpc, condition_label = sg_label,
          filename = phasea_fig$regime_contrast,
          output_dir = viz_dir
        )
      }
      plot_churn_summary_panel(
        churn_bk = churn_bk,
        marginal_comparison = marginal_comp,
        regime_contrast = regime_contrast,
        theoretical_premium = theoretical_prem,
        stayer_estimate = best_est,
        empirical_premium = phase_a_linkage_premium,
        true_sgpc = true_sgpc,
        condition_label = sg_label,
        filename = phasea_fig$churn_summary_panel,
        output_dir = viz_dir
      )
      log_msg("  Churn diagnostic plots saved.\n")
    }, error = function(e) {
      log_msg("  WARNING: Churn plot generation failed: ", e$message, "\n")
    })
  }

  # --- Copula comparison plots (comparison mode only) ---
  if (!is.null(copula_sensitivity) && !is.null(alt_best_est)) {
    log_msg("  Generating copula comparison plots...\n")
    alt_subtitle <- paste0("Copula: ", alt_copula_label)

    # Ensure alt_best_est has uniform/TAMP baselines for plotting
    alt_best_est$F_uniform <- predict_marginal_cdf(
      v_grid = alt_best_est$v_grid, u_sample = u_cross,
      regime = regime_beta(0.5, 2), kernel_cache = alt_kernel_cache
    )
    alt_best_est$F_tamp <- ecdf(u_cross)(alt_best_est$v_grid)
    alt_best_est$w1_uniform <- wasserstein1(alt_best_est$F_uniform, alt_best_est$F_obs, alt_best_est$v_grid)

    # ---- Individual plots for 2×2 grid (Metric × Copula) ----
    # These individual PDFs are composed into a LaTeX summary grid below.

    # Cell [1,1]: W1 / Canonical — CDF
    plot_observed_vs_predicted_cdf(
      best_est,
      title = paste0("CDF: W1-Optimised — ", copula_subtitle),
      output_dir = viz_dir, filename = phasea_fig$grid_w1_canonical_cdf
    )
    # Cell [1,1]: W1 / Canonical — Regime
    plot_regime_shape(
      best_est$regime, true_sgpc,
      title = paste0("Regime: W1-Optimised — ", copula_subtitle),
      output_dir = viz_dir, filename = phasea_fig$grid_w1_canonical_regime
    )

    # Cell [1,2]: W1 / Best-fit — CDF
    plot_observed_vs_predicted_cdf(
      alt_best_est,
      title = paste0("CDF: W1-Optimised — ", alt_subtitle),
      output_dir = viz_dir, filename = phasea_fig$grid_w1_bestfit_cdf
    )
    # Cell [1,2]: W1 / Best-fit — Regime
    plot_regime_shape(
      alt_best_est$regime, true_sgpc,
      title = paste0("Regime: W1-Optimised — ", alt_subtitle),
      output_dir = viz_dir, filename = phasea_fig$grid_w1_bestfit_regime
    )

    # Cell [2,1]: CvM / Canonical — if CvM-optimised estimate exists
    if (!is.null(best_est_cvm)) {
      # Ensure CvM estimate has baselines
      if (is.null(best_est_cvm$F_uniform)) {
        best_est_cvm$F_uniform <- best_est$F_uniform
        best_est_cvm$F_tamp <- best_est$F_tamp
        best_est_cvm$w1_uniform <- best_est$w1_uniform
      }
      plot_observed_vs_predicted_cdf(
        best_est_cvm,
        title = paste0("CDF: CvM-Optimised — ", copula_subtitle),
        output_dir = viz_dir, filename = phasea_fig$grid_cvm_canonical_cdf
      )
      plot_regime_shape(
        best_est_cvm$regime, true_sgpc,
        title = paste0("Regime: CvM-Optimised — ", copula_subtitle),
        output_dir = viz_dir, filename = phasea_fig$grid_cvm_canonical_regime
      )
    }

    # Cell [2,2]: CvM / Best-fit — if CvM-optimised alt estimate exists
    alt_best_est_cvm <- copula_sensitivity$alt_cvm_est
    if (!is.null(alt_best_est_cvm)) {
      if (is.null(alt_best_est_cvm$F_uniform)) {
        alt_best_est_cvm$F_uniform <- alt_best_est$F_uniform
        alt_best_est_cvm$F_tamp <- alt_best_est$F_tamp
        alt_best_est_cvm$w1_uniform <- alt_best_est$w1_uniform
      }
      plot_observed_vs_predicted_cdf(
        alt_best_est_cvm,
        title = paste0("CDF: CvM-Optimised — ", alt_subtitle),
        output_dir = viz_dir, filename = phasea_fig$grid_cvm_bestfit_cdf
      )
      plot_regime_shape(
        alt_best_est_cvm$regime, true_sgpc,
        title = paste0("Regime: CvM-Optimised — ", alt_subtitle),
        output_dir = viz_dir, filename = phasea_fig$grid_cvm_bestfit_regime
      )
    }

    # ---- Legacy individual alt copula plots (backward compat) ----
    plot_observed_vs_predicted_cdf(
      alt_best_est,
      title = paste0("B2. Forward CDF Check — ", sg_label, "\n", alt_subtitle),
      output_dir = viz_dir, filename = phasea_fig$copula_alt_forward_cdf
    )
    plot_regime_shape(
      alt_best_est$regime, true_sgpc,
      title = paste0("C. Inferred Regime Density — ", sg_label, "\n", alt_subtitle),
      output_dir = viz_dir, filename = phasea_fig$copula_alt_regime_density
    )
    plot_recovery_summary(
      alt_best_est, true_sgpc,
      title = paste0("Growth Regime Recovery Summary: ", sg_label, "\n", alt_subtitle),
      output_dir = viz_dir, filename = phasea_fig$copula_alt_recovery_summary
    )

    # ---- R-based comparison panel (backward compat) ----
    if (exists("plot_copula_comparison_panel", mode = "function")) {
      plot_copula_comparison_panel(
        primary_est = best_est,
        alt_est = alt_best_est,
        true_sgpc = true_sgpc,
        primary_label = primary_copula_label,
        alt_label = alt_copula_label,
        sensitivity = copula_sensitivity,
        title = paste0("Copula Sensitivity — ", sg_label),
        output_dir = viz_dir,
        filename = phasea_fig$copula_comparison_panel
      )
    }

    # ---- LaTeX 2×2 summary grid (Metric × Copula) ----
    if (exists("generate_metric_copula_grid_latex", mode = "function")) {
      log_msg("  Generating 2×2 metric × copula LaTeX summary grid...\n")
      tryCatch({
        generate_metric_copula_grid_latex(
          output_dir = viz_dir,
          condition_id = condition_id,
          subgroup_id = subgroup_id,
          copula_sensitivity = copula_sensitivity,
          true_sgpc = true_sgpc,
          best_est = best_est,
          best_est_cvm = best_est_cvm,
          primary_copula_label = primary_copula_label,
          alt_copula_label = alt_copula_label,
          figure_map = phasea_fig,
          compile_pdf = TRUE,
          keep_tex = TRUE,
          export_formats = cfg$output$export_formats
        )
        log_msg("  LaTeX summary grid saved.\n")
      }, error = function(e) {
        log_msg("  WARNING: LaTeX summary grid generation failed: ", e$message, "\n")
      })
    }

    log_msg("  Copula comparison plots saved.\n")
  }

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
    best_estimate_cvm = best_est_cvm,
    optimize_metric = optimize_metric,
    copula_mode = copula_mode,
    primary_copula_label = primary_copula_label,
    copula_sensitivity = copula_sensitivity,
    bootstrap = boot_results,
    bootstrap_paired = boot_paired,
    linkage_premium = phase_a_linkage_premium,
    u_sample = u_cross,
    v_sample = v_cross,
    kernel_cache = kernel_cache,
    references = list(n_prior = refs$n_prior, n_current = refs$n_current),
    copula_used = list(family = kernel_cache$copula_family, params = kernel_cache$copula_params),
    churn_bookkeeping = churn_bk,
    marginal_comparison = marginal_comp,
    regime_contrast = regime_contrast,
    theoretical_linkage_premium = theoretical_prem,
    config = cfg,
    output_dir = output_dir
  )

  saveRDS(phase_a_results, file.path(output_dir, "phase_a_deep_dive.rds"))

  w1_red <- if (is.finite(best_est$w1_uniform) && best_est$w1_uniform > 0) {
    round(100 * (1 - (best_est$all_distances$wasserstein1 / best_est$w1_uniform)), 2)
  } else NA_real_

  # CvM-optimized values (NA if single-metric mode)
  cvm_median_inferred <- if (!is.null(best_est_cvm)) round(best_est_cvm$regime$median * 100, 2) else NA_real_
  cvm_mean_inferred   <- if (!is.null(best_est_cvm)) round(best_est_cvm$regime$mean * 100, 2) else NA_real_
  cvm_median_diff     <- if (!is.null(best_est_cvm)) round(best_est_cvm$regime$median * 100 - median(true_sgpc, na.rm = TRUE), 2) else NA_real_
  cvm_mean_diff       <- if (!is.null(best_est_cvm)) round(best_est_cvm$regime$mean * 100 - mean(true_sgpc, na.rm = TRUE), 2) else NA_real_
  cvm_at_cvm_opt      <- if (!is.null(best_est_cvm)) round(best_est_cvm$all_distances$cramer_von_mises, 6) else NA_real_
  w1_at_cvm_opt       <- if (!is.null(best_est_cvm)) round(best_est_cvm$all_distances$wasserstein1, 6) else NA_real_

  # Copula sensitivity values (NA if not in comparison mode)
  cs <- copula_sensitivity
  cs_alt_median_inferred <- if (!is.null(cs)) round(cs$alt_median_sgpc, 2) else NA_real_
  cs_alt_mean_inferred   <- if (!is.null(cs)) round(cs$alt_mean_sgpc, 2) else NA_real_
  cs_alt_median_diff     <- if (!is.null(cs)) round(cs$alt_median_diff, 2) else NA_real_
  cs_alt_mean_diff       <- if (!is.null(cs)) round(cs$alt_mean_diff, 2) else NA_real_
  cs_delta_median        <- if (!is.null(cs)) round(cs$delta_median_sgpc, 2) else NA_real_
  cs_delta_mean          <- if (!is.null(cs)) round(cs$delta_mean_sgpc, 2) else NA_real_
  cs_alt_w1              <- if (!is.null(cs)) round(cs$alt_w1, 6) else NA_real_
  cs_alt_cvm             <- if (!is.null(cs)) round(cs$alt_cvm, 6) else NA_real_

  # CvM-optimised under alt copula (4th cell: NA if not in comparison mode or single-metric)
  alt_cvm_est_local <- if (!is.null(cs)) cs$alt_cvm_est else NULL
  cs_alt_cvm_median <- if (!is.null(alt_cvm_est_local)) round(alt_cvm_est_local$regime$median * 100, 2) else NA_real_
  cs_alt_cvm_mean   <- if (!is.null(alt_cvm_est_local)) round(alt_cvm_est_local$regime$mean * 100, 2) else NA_real_
  cs_alt_cvm_median_diff <- if (!is.null(alt_cvm_est_local)) round(alt_cvm_est_local$regime$median * 100 - median(true_sgpc, na.rm = TRUE), 2) else NA_real_
  cs_alt_cvm_mean_diff   <- if (!is.null(alt_cvm_est_local)) round(alt_cvm_est_local$regime$mean * 100 - mean(true_sgpc, na.rm = TRUE), 2) else NA_real_
  cs_alt_cvm_cvm    <- if (!is.null(alt_cvm_est_local)) round(alt_cvm_est_local$all_distances$cramer_von_mises, 6) else NA_real_
  cs_alt_cvm_w1     <- if (!is.null(alt_cvm_est_local)) round(alt_cvm_est_local$all_distances$wasserstein1, 6) else NA_real_

  summary_row <- data.frame(
    condition_id = condition_id,
    subgroup_id = subgroup_id,
    n_subgroup = nrow(pairs_sg),
    regime_family = best_family,
    optimize_metric = optimize_metric,
    copula_mode = copula_mode,
    primary_copula = primary_copula_label,
    # W1-optimized (primary copula)
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
    # CvM-optimized (alternative — NA if single-metric mode)
    cvm_opt_median_sgpc = cvm_median_inferred,
    cvm_opt_mean_sgpc = cvm_mean_inferred,
    cvm_opt_median_diff = cvm_median_diff,
    cvm_opt_mean_diff = cvm_mean_diff,
    cvm_opt_cvm = cvm_at_cvm_opt,
    cvm_opt_w1 = w1_at_cvm_opt,
    # Copula sensitivity: best-fit parametric vs canonical (NA if not comparison mode)
    alt_copula = if (!is.null(cs)) cs$alt_copula_label else NA_character_,
    alt_median_sgpc = cs_alt_median_inferred,
    alt_mean_sgpc = cs_alt_mean_inferred,
    alt_median_diff = cs_alt_median_diff,
    alt_mean_diff = cs_alt_mean_diff,
    copula_delta_median = cs_delta_median,
    copula_delta_mean = cs_delta_mean,
    alt_w1 = cs_alt_w1,
    alt_cvm = cs_alt_cvm,
    # CvM-optimised under best-fit copula (4th cell — NA if not comparison + dual-metric)
    alt_cvm_opt_median_sgpc = cs_alt_cvm_median,
    alt_cvm_opt_mean_sgpc = cs_alt_cvm_mean,
    alt_cvm_opt_median_diff = cs_alt_cvm_median_diff,
    alt_cvm_opt_mean_diff = cs_alt_cvm_mean_diff,
    alt_cvm_opt_cvm = cs_alt_cvm_cvm,
    alt_cvm_opt_w1 = cs_alt_cvm_w1,
    # Bootstrap CIs
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
    # Churn diagnostics
    n_prior_all = if (!is.null(churn_bk)) churn_bk$condition$n_prior_all else NA_integer_,
    n_current_all = if (!is.null(churn_bk)) churn_bk$condition$n_current_all else NA_integer_,
    n_stayers = if (!is.null(churn_bk)) churn_bk$condition$n_stayers else NA_integer_,
    n_leavers = if (!is.null(churn_bk)) churn_bk$condition$n_leavers else NA_integer_,
    n_entrants = if (!is.null(churn_bk)) churn_bk$condition$n_entrants else NA_integer_,
    alpha_retention = if (!is.null(churn_bk)) churn_bk$condition$alpha else NA_real_,
    beta_retention = if (!is.null(churn_bk)) churn_bk$condition$beta else NA_real_,
    churn_type = if (!is.null(churn_bk)) churn_bk$condition$churn_type else NA_character_,
    gamma_prior = if (!is.null(marginal_comp)) marginal_comp$gamma_prior else NA_real_,
    gamma_current = if (!is.null(marginal_comp)) marginal_comp$gamma_current else NA_real_,
    compositionally_ignorable = if (!is.null(marginal_comp)) marginal_comp$compositionally_ignorable else NA,
    regime_delta_median = if (!is.null(regime_contrast)) regime_contrast$delta_median else NA_real_,
    regime_delta_mean = if (!is.null(regime_contrast)) regime_contrast$delta_mean else NA_real_,
    theoretical_premium_mean = if (!is.null(theoretical_prem)) theoretical_prem$mean_scale else NA_real_,
    theoretical_premium_cdf = if (!is.null(theoretical_prem)) theoretical_prem$cdf_scale else NA_real_,
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
