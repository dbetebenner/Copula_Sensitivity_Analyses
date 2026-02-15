############################################################################
###
### STEP 3 — Phase B: Systematic Validation
###
### Extends the Phase A single-condition showcase across multiple
### conditions and subgroups to assess:
###
###   - Recovery accuracy vs subgroup size (n = 50, 100, 200, 500+)
###   - Sensitivity to year span (1-year vs 2-year vs 4-year)
###   - Sensitivity to regime family choice
###   - Distribution of recovery errors across subgroups
###
### Sourced by run_step3.R (Phase B) or can be run standalone.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIw_LD)
###
############################################################################

cat("--- Phase B: Systematic Validation ---\n\n")

############################################################################
### B.0  Configuration
############################################################################

cfg_sys <- STEP3_CONFIG$systematic
cfg_kern <- STEP3_CONFIG$kernel
cfg_dist <- STEP3_CONFIG$distance
cfg_reg <- STEP3_CONFIG$regime
sg_col <- STEP3_CONFIG$validation$subgroup_col

# Results storage
all_results <- list()
summary_rows <- list()
row_counter <- 0


############################################################################
### B.1  Loop Over Datasets and Conditions
############################################################################

for (ds_id in cfg_sys$datasets) {

  cat("================================================================\n")
  cat("Dataset:", ds_id, "\n")
  cat("================================================================\n\n")

  # Load dataset configuration
  ds_config <- DATASETS[[ds_id]]
  if (is.null(ds_config)) {
    cat("  WARNING: Dataset '", ds_id, "' not in DATASETS. Skipping.\n\n")
    next
  }

  # Load state data
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

  # Get Phase 1 conditions for this dataset
  conditions_all <- get_phase1_conditions(ds_id)
  if (length(conditions_all) == 0) {
    cat("  WARNING: No Phase 1 conditions found. Skipping.\n\n")
    next
  }

  # Filter to desired year spans
  cond_metas <- lapply(conditions_all, parse_condition_id)
  cond_spans <- sapply(cond_metas, `[[`, "year_span")
  cond_content <- sapply(cond_metas, `[[`, "content_area")

  # Apply span filter
  if (!is.null(cfg_sys$year_spans)) {
    keep <- cond_spans %in% cfg_sys$year_spans
    conditions_all <- conditions_all[keep]
    cond_metas <- cond_metas[keep]
    cond_spans <- cond_spans[keep]
    cond_content <- cond_content[keep]
  }

  # Apply content area filter
  if (!is.null(cfg_sys$content_areas)) {
    keep <- cond_content %in% cfg_sys$content_areas
    conditions_all <- conditions_all[keep]
    cond_metas <- cond_metas[keep]
    cond_spans <- cond_spans[keep]
  }

  # Limit number of conditions
  n_conds <- min(length(conditions_all), cfg_sys$n_conditions_per_dataset)
  # Sample to get diversity of spans
  if (length(conditions_all) > n_conds) {
    # Stratified sample: pick proportionally from each span
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

  # Load canonical parameters
  canonical <- tryCatch(load_canonical_parameters(), error = function(e) NULL)

  # ------------------------------------------------------------------
  # Loop over conditions
  # ------------------------------------------------------------------

  for (ci in seq_along(conditions)) {
    condition_id <- conditions[ci]
    cond <- parse_condition_id(condition_id)

    cat("  Condition", ci, "/", length(conditions), ":", condition_id, "\n")

    # Extract longitudinal pairs
    pairs <- tryCatch({
      create_longitudinal_pairs(
        STATE_DATA, cond$grade_prior, cond$grade_current,
        cond$year_current, cond$content_area
      )
    }, error = function(e) {
      cat("    ERROR extracting pairs:", e$message, "\n")
      NULL
    })

    if (is.null(pairs) || nrow(pairs) < 50) {
      cat("    Insufficient pairs (n =", ifelse(is.null(pairs), 0, nrow(pairs)), "). Skipping.\n")
      next
    }

    # Build reference marginals
    refs <- tryCatch(
      build_condition_reference(STATE_DATA, cond),
      error = function(e) { cat("    ERROR building refs:", e$message, "\n"); NULL }
    )
    if (is.null(refs)) next

    # Load Phase 1 copula
    p1 <- tryCatch(load_phase1_condition(ds_id, condition_id), error = function(e) NULL)
    if (is.null(p1) || is.null(p1$best_fit_copula)) {
      if (!is.null(canonical)) {
        p1_copula <- create_canonical_copula(cond$year_span, cond$content_area,
                                              canonical$canonical_params)
      } else {
        cat("    No copula available. Skipping.\n")
        next
      }
    } else {
      p1_copula <- p1$best_fit_copula
    }

    # Build kernel cache
    kernel_cache <- tryCatch(
      create_kernel_cache(p1_copula, u_grid_size = 101, v_grid_size = 101,
                          compute_quantile = FALSE),
      error = function(e) { cat("    ERROR building kernel:", e$message, "\n"); NULL }
    )
    if (is.null(kernel_cache)) next

    # State-level pseudo-observations for true SGPc
    u_full <- rank(pairs$SCALE_SCORE_PRIOR) / (nrow(pairs) + 1)
    v_full <- rank(pairs$SCALE_SCORE_CURRENT) / (nrow(pairs) + 1)

    # Identify subgroups
    if (sg_col %in% names(pairs)) {
      sg_table <- pairs[, .N, by = sg_col][N >= cfg_sys$min_subgroup_n][order(-N)]
      n_sg <- min(nrow(sg_table), cfg_sys$n_subgroups_per_condition)

      if (n_sg == 0) {
        cat("    No subgroups with n >=", cfg_sys$min_subgroup_n, ". Using full condition.\n")
        subgroups <- list(list(id = "ALL", idx = seq_len(nrow(pairs))))
      } else {
        subgroups <- lapply(seq_len(n_sg), function(j) {
          sg_id <- as.character(sg_table[[sg_col]][j])
          idx <- which(pairs[[sg_col]] == sg_id)
          list(id = sg_id, idx = idx)
        })
      }
    } else {
      subgroups <- list(list(id = "ALL", idx = seq_len(nrow(pairs))))
    }

    # ------------------------------------------------------------------
    # Loop over subgroups within this condition
    # ------------------------------------------------------------------

    for (sg in subgroups) {
      sg_id <- sg$id
      sg_idx <- sg$idx
      n_sg <- length(sg_idx)

      # True SGPc
      true_sgpc <- sgpc_engine(u_full[sg_idx], v_full[sg_idx], p1_copula,
                                scale = "percentile")

      # Cross-sectional samples (reference-scaled)
      u_cross <- reference_cdf(pairs$SCALE_SCORE_PRIOR[sg_idx], refs$ref_prior)
      v_cross <- reference_cdf(pairs$SCALE_SCORE_CURRENT[sg_idx], refs$ref_current)

      # Estimate growth regime (primary family only for speed)
      est <- tryCatch({
        estimate_regime(u_cross, v_cross, kernel_cache,
                        regime_family = cfg_reg$primary_family,
                        distance_fn   = cfg_dist$primary,
                        grid_resolution = 20,  # Lower for speed
                        verbose = FALSE)
      }, error = function(e) NULL)

      if (is.null(est)) {
        cat("    Subgroup", sg_id, ": estimation failed\n")
        next
      }

      # Record results
      row_counter <- row_counter + 1
      summary_rows[[row_counter]] <- data.frame(
        dataset_id          = ds_id,
        condition_id        = condition_id,
        year_span           = cond$year_span,
        content_area        = cond$content_area,
        subgroup_id         = sg_id,
        n_subgroup          = n_sg,
        regime_family       = cfg_reg$primary_family,
        median_sgpc_inferred = round(est$regime$median * 100, 2),
        mean_sgpc_inferred  = round(est$regime$mean * 100, 2),
        median_sgpc_true    = round(median(true_sgpc, na.rm = TRUE), 2),
        mean_sgpc_true      = round(mean(true_sgpc, na.rm = TRUE), 2),
        median_diff         = round(est$regime$median * 100 -
                                    median(true_sgpc, na.rm = TRUE), 2),
        wasserstein1        = round(est$all_distances$wasserstein1, 6),
        cvm                 = round(est$all_distances$cramer_von_mises, 6),
        ks                  = round(est$all_distances$ks_distance, 6),
        theta1              = round(est$theta_hat[1], 4),
        theta2              = if (length(est$theta_hat) > 1) round(est$theta_hat[2], 4) else NA_real_,
        stringsAsFactors    = FALSE
      )

      all_results[[paste0(condition_id, "__", sg_id)]] <- list(
        estimate = est, true_sgpc = true_sgpc
      )
    }

    cat("    ", length(subgroups), "subgroups processed\n")
  }

  # Clean up dataset
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
  phase_b_summary <- rbindlist(summary_rows)

  cat("Total subgroups estimated:", nrow(phase_b_summary), "\n")
  cat("Conditions covered:", length(unique(phase_b_summary$condition_id)), "\n")

  # Key statistics
  cat("\n--- Recovery Accuracy Summary ---\n")
  cat("Median of |median_diff|:", round(median(abs(phase_b_summary$median_diff)), 2),
      "SGP points\n")
  cat("Mean of |median_diff|:", round(mean(abs(phase_b_summary$median_diff)), 2),
      "SGP points\n")
  cat("90th percentile of |median_diff|:",
      round(quantile(abs(phase_b_summary$median_diff), 0.90), 2), "SGP points\n")

  # By year span
  if ("year_span" %in% names(phase_b_summary)) {
    cat("\n--- By Year Span ---\n")
    by_span <- phase_b_summary[, .(
      n_subgroups   = .N,
      median_abs_diff = round(median(abs(median_diff)), 2),
      mean_abs_diff   = round(mean(abs(median_diff)), 2),
      median_W1       = round(median(wasserstein1), 6)
    ), by = year_span][order(year_span)]
    print(by_span)
  }

  # By subgroup size
  cat("\n--- By Subgroup Size ---\n")
  phase_b_summary[, size_bin := cut(n_subgroup,
    breaks = c(0, 100, 200, 500, 1000, Inf),
    labels = c("50-99", "100-199", "200-499", "500-999", "1000+"),
    right = FALSE)]
  by_size <- phase_b_summary[, .(
    n_subgroups   = .N,
    median_abs_diff = round(median(abs(median_diff)), 2),
    mean_abs_diff   = round(mean(abs(median_diff)), 2)
  ), by = size_bin][order(size_bin)]
  print(by_size)

  # Save
  fwrite(phase_b_summary, file.path(RESULTS_DIR, "phase_b_systematic_summary.csv"))
  saveRDS(all_results, file.path(RESULTS_DIR, "phase_b_all_results.rds"))
  cat("\n  Saved: phase_b_systematic_summary.csv, phase_b_all_results.rds\n")

} else {
  cat("No results to compile.\n")
  phase_b_summary <- data.table()
}

cat("\n--- Phase B complete ---\n\n")
