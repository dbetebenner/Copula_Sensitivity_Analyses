############################################################################
###
### Precision Sweep: Phase B-style Subsampling from Condition Pool
###
### Self-contained function that performs without-replacement subsampling
### across N buckets and linkage fractions.  Unlike Phase B's daemon-based
### replicate batches (which rely on .PHASEB_* globals), this function
### accepts all inputs as arguments and runs locally or via mirai.
###
### Produces the same replicate-level schema as phase_b_replicates so that
### downstream aggregation and plotting code can be shared.
###
### Author: dataimago
### Date: March 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

require(data.table)


#' Run a Precision Sweep via Subsampling from the Condition Pool
#'
#' For each combination of (n_bucket, linkage_fraction), draws \code{outer_reps}
#' without-replacement subsamples from \code{pairs}, estimates the growth regime
#' on each subsample, and computes accuracy/precision summaries.
#'
#' This implements the NAEP/TIMSS population-sampling frame: the condition pool
#' represents the population, and each subsample is a fresh draw of N students.
#'
#' @param pairs         data.table. Full condition matched pairs (must contain
#'                      SCALE_SCORE_PRIOR and SCALE_SCORE_CURRENT).
#' @param refs          List. Reference marginals from \code{build_pairs_reference()}.
#' @param kernel_cache  Precomputed kernel cache from \code{create_kernel_cache()}.
#' @param true_sgpc_full Numeric vector. True SGPc for every row of \code{pairs}.
#' @param n_buckets     Integer vector. Sample sizes to sweep.
#' @param outer_reps    Integer. Replicates per (n_bucket, linkage_fraction) cell.
#' @param linkage_fractions Numeric vector in [0, 1].
#' @param regime_family Character. Default "beta".
#' @param distance_fn   Character. Default "wasserstein1".
#' @param grid_resolution Integer. Grid resolution per replicate. Default 10.
#' @param seed          Integer. RNG seed base. Default NULL.
#' @param use_mirai     Logical. Dispatch via mirai if daemons are alive.
#' @param verbose       Logical. Print progress.
#'
#' @return Named list with:
#'   \itemize{
#'     \item \code{replicates}: data.table with one row per replicate
#'     \item \code{summary}: data.table aggregated by (n_bucket, linkage_fraction)
#'     \item \code{n_pool}: integer, total pool size
#'   }
#' @export
run_precision_sweep <- function(pairs,
                                refs,
                                kernel_cache,
                                true_sgpc_full,
                                n_buckets   = c(1000L, 2500L, 5000L, 7500L, 10000L),
                                outer_reps  = 200L,
                                linkage_fractions = c(0.0, 1.0),
                                regime_family = "beta",
                                distance_fn   = "wasserstein1",
                                grid_resolution = 10L,
                                seed = NULL,
                                use_mirai = FALSE,
                                verbose = TRUE) {

  n_pool <- nrow(pairs)
  ss_prior   <- pairs$SCALE_SCORE_PRIOR
  ss_current <- pairs$SCALE_SCORE_CURRENT

  pool_truth_median <- median(true_sgpc_full, na.rm = TRUE)
  pool_truth_mean   <- mean(true_sgpc_full,   na.rm = TRUE)

  eligibility_buffer <- 0.10
  eligible_buckets <- n_buckets[n_pool >= n_buckets * (1 + eligibility_buffer)]
  if (length(eligible_buckets) == 0) {
    if (verbose) cat("  WARNING: Pool N =", n_pool,
                     "is too small for any requested N bucket. Skipping sweep.\n")
    return(list(
      replicates = data.table(),
      summary    = data.table(),
      n_pool     = n_pool
    ))
  }

  if (verbose) {
    cat(sprintf("  Precision sweep: pool N = %s | buckets = %s | fractions = %s | reps = %d\n",
                format(n_pool, big.mark = ","),
                paste(eligible_buckets, collapse = ", "),
                paste(linkage_fractions, collapse = ", "),
                outer_reps))
  }

  task_grid <- CJ(
    n_bucket         = eligible_buckets,
    linkage_fraction = linkage_fractions,
    replicate        = seq_len(outer_reps)
  )

  seed_base <- if (!is.null(seed)) as.integer(seed) else 42L

  .run_one <- function(n_bucket, linkage_fraction, replicate) {
    lf_offset <- as.integer(round(linkage_fraction * 100))
    set.seed(seed_base + as.integer(n_bucket) * 1000L + replicate + lf_offset * 10000L)

    n_bkt      <- as.integer(n_bucket)
    n_linked   <- as.integer(floor(linkage_fraction * n_bkt))
    n_unlinked <- n_bkt - n_linked
    pool_idx   <- seq_len(n_pool)

    if (n_linked == n_bkt) {
      rep_idx <- sample(pool_idx, size = n_bkt, replace = FALSE)
      true_rep <- true_sgpc_full[rep_idx]
      u_rep <- reference_cdf(ss_prior[rep_idx],   refs$ref_prior)
      v_rep <- reference_cdf(ss_current[rep_idx], refs$ref_current)
      true_med <- median(true_rep, na.rm = TRUE)
      true_mn  <- mean(true_rep,   na.rm = TRUE)

    } else if (n_linked == 0L) {
      u_idx <- sample(pool_idx, size = n_bkt, replace = FALSE)
      v_idx <- sample(pool_idx, size = n_bkt, replace = FALSE)
      u_rep <- reference_cdf(ss_prior[u_idx],   refs$ref_prior)
      v_rep <- reference_cdf(ss_current[v_idx], refs$ref_current)
      true_med <- pool_truth_median
      true_mn  <- pool_truth_mean

    } else {
      linked_idx <- sample(pool_idx, size = n_linked, replace = FALSE)
      u_linked <- reference_cdf(ss_prior[linked_idx],   refs$ref_prior)
      v_linked <- reference_cdf(ss_current[linked_idx], refs$ref_current)

      u_unlinked_idx <- sample(pool_idx, size = n_unlinked, replace = FALSE)
      v_unlinked_idx <- sample(pool_idx, size = n_unlinked, replace = FALSE)
      u_unlinked <- reference_cdf(ss_prior[u_unlinked_idx],   refs$ref_prior)
      v_unlinked <- reference_cdf(ss_current[v_unlinked_idx], refs$ref_current)

      u_rep <- c(u_linked, u_unlinked)
      v_rep <- c(v_linked, v_unlinked)
      true_med <- pool_truth_median
      true_mn  <- pool_truth_mean
    }

    est <- tryCatch(
      estimate_regime(
        u_sample        = u_rep,
        v_sample        = v_rep,
        kernel_cache    = kernel_cache,
        regime_family   = regime_family,
        distance_fn     = distance_fn,
        grid_resolution = grid_resolution,
        verbose         = FALSE
      ),
      error = function(e) NULL
    )

    if (is.null(est)) {
      list(inferred_median = NA_real_, inferred_mean = NA_real_,
           true_median = true_med, true_mean = true_mn,
           converged = FALSE, m_hat = NA_real_, kappa_hat = NA_real_)
    } else {
      list(
        inferred_median = as.numeric(est$regime$median) * 100,
        inferred_mean   = as.numeric(est$regime$mean)   * 100,
        true_median     = true_med,
        true_mean       = true_mn,
        converged       = TRUE,
        m_hat           = round(est$m_hat, 4),
        kappa_hat       = round(est$kappa_hat, 4)
      )
    }
  }

  if (verbose) cat("  Running", nrow(task_grid), "replicate estimations...\n")

  results_list <- vector("list", nrow(task_grid))
  for (i in seq_len(nrow(task_grid))) {
    r <- task_grid[i]
    out <- .run_one(r$n_bucket, r$linkage_fraction, r$replicate)
    results_list[[i]] <- c(
      list(n_bucket = r$n_bucket, linkage_fraction = r$linkage_fraction,
           replicate = r$replicate),
      out
    )
    if (verbose && i %% 500 == 0) {
      cat(sprintf("    %d / %d replicates complete\n", i, nrow(task_grid)))
    }
  }

  replicates <- rbindlist(lapply(results_list, as.data.table), fill = TRUE)
  replicates[, `:=`(
    median_error     = inferred_median - true_median,
    mean_error       = inferred_mean   - true_mean,
    abs_median_error = abs(inferred_median - true_median),
    abs_mean_error   = abs(inferred_mean   - true_mean),
    sampling_mode    = fifelse(linkage_fraction == 1.0, "paired",
                        fifelse(linkage_fraction == 0.0, "independent",
                                sprintf("partial_%.2f", linkage_fraction)))
  )]

  summary_dt <- replicates[, .(
    n_reps             = .N,
    n_converged        = sum(converged, na.rm = TRUE),
    median_bias        = round(mean(median_error[converged == TRUE], na.rm = TRUE), 4),
    median_mae         = round(mean(abs_median_error[converged == TRUE], na.rm = TRUE), 4),
    median_ci_width_95 = round(
      quantile(inferred_median[converged == TRUE], 0.975, na.rm = TRUE) -
        quantile(inferred_median[converged == TRUE], 0.025, na.rm = TRUE), 4),
    mean_bias          = round(mean(mean_error[converged == TRUE], na.rm = TRUE), 4),
    mean_mae           = round(mean(abs_mean_error[converged == TRUE], na.rm = TRUE), 4),
    mean_ci_width_95   = round(
      quantile(inferred_mean[converged == TRUE], 0.975, na.rm = TRUE) -
        quantile(inferred_mean[converged == TRUE], 0.025, na.rm = TRUE), 4)
  ), by = .(n_bucket, linkage_fraction, sampling_mode)]

  if (verbose) {
    cat("  Sweep complete. Summary:\n")
    print(summary_dt[order(linkage_fraction, n_bucket)])
  }

  list(
    replicates = replicates,
    summary    = summary_dt,
    n_pool     = n_pool
  )
}


#' Plot Precision Sweep N-Operating Curve
#'
#' Generates a CI-width vs N panel with paired and independent lines from
#' subsampling, and optional bootstrap anchor points from Phase A (A.7/A.7b).
#'
#' @param sweep_summary  data.table from \code{run_precision_sweep()$summary}.
#' @param bootstrap_anchor Optional data.table from phase_a_precision_anchor.csv.
#' @param title           Character. Plot title.
#' @param sampling_context Character or NULL. Footnote caption for sampling frame.
#' @param output_dir      Character. Directory for output.
#' @param filename        Character. Base filename (no extension).
#' @return Invisible ggplot object.
#' @export
plot_precision_sweep <- function(sweep_summary,
                                 bootstrap_anchor = NULL,
                                 title = "Precision Sweep: CI Width vs N (Subsampling)",
                                 sampling_context = NULL,
                                 output_dir = "results/visualizations",
                                 filename = "phasea_08_precision_sweep") {

  require(ggplot2)

  if (nrow(sweep_summary) == 0) {
    cat("  plot_precision_sweep(): no data to plot.\n")
    return(invisible(NULL))
  }

  sweep_summary[, mode_label := fifelse(
    linkage_fraction == 1.0, "Paired (subsampling)",
    fifelse(linkage_fraction == 0.0, "Independent (subsampling)",
            sprintf("Partial %.0f%% (subsampling)", linkage_fraction * 100))
  )]

  p_mean <- ggplot(sweep_summary, aes(x = n_bucket, y = mean_ci_width_95,
                                       color = mode_label, shape = mode_label)) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.5)

  p_median <- ggplot(sweep_summary, aes(x = n_bucket, y = median_ci_width_95,
                                         color = mode_label, shape = mode_label)) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.5)

  mode_colors <- c(
    "Paired (subsampling)"      = STEP3_COLORS$predicted,
    "Independent (subsampling)" = STEP3_COLORS$true_value,
    "Paired (bootstrap)"        = STEP3_COLORS$predicted,
    "Independent (bootstrap)"   = STEP3_COLORS$true_value
  )

  if (!is.null(bootstrap_anchor) && nrow(bootstrap_anchor) > 0) {
    n_obs <- bootstrap_anchor$n0[1]
    for (meas in c("mean_sgpc", "median_sgpc")) {
      target_plot <- if (meas == "mean_sgpc") "mean" else "median"
      for (pair_mode in c("independent", "paired")) {
        row <- bootstrap_anchor[pairing == pair_mode & measure == meas]
        if (nrow(row) == 1) {
          lbl <- paste0(tools::toTitleCase(pair_mode), " (bootstrap)")
          ci_w <- row$ci95_width
          anchor_df <- data.frame(x = n_obs, y = ci_w, mode_label = lbl,
                                  stringsAsFactors = FALSE)
          hline_layer <- geom_hline(yintercept = ci_w, linetype = "dotted",
                                    linewidth = 0.5, color = mode_colors[[lbl]])
          point_layer <- geom_point(data = anchor_df,
                                    aes(x = x, y = y),
                                    color = mode_colors[[lbl]],
                                    shape = 4, size = 3.5, stroke = 1.2,
                                    inherit.aes = FALSE)
          label_layer <- annotate("text",
                                  x = n_obs, y = ci_w,
                                  label = sprintf("  Bootstrap @ N=%s", format(n_obs, big.mark = ",")),
                                  hjust = 0, vjust = -0.5, size = 2.8,
                                  color = mode_colors[[lbl]])
          if (target_plot == "mean") {
            p_mean <- p_mean + hline_layer + point_layer + label_layer
          } else {
            p_median <- p_median + hline_layer + point_layer + label_layer
          }
        }
      }
    }
  }

  shared_scales <- list(
    scale_color_manual(values = mode_colors, name = "Sampling Mode"),
    scale_shape_manual(values = c(
      "Paired (subsampling)" = 16,
      "Independent (subsampling)" = 17,
      "Paired (bootstrap)" = 4,
      "Independent (bootstrap)" = 4
    ), name = "Sampling Mode"),
    scale_x_continuous(labels = scales::comma, breaks = sort(unique(sweep_summary$n_bucket))),
    theme_publication(base_size = 9),
    theme(legend.position = "bottom", legend.title = element_blank())
  )

  p_mean <- p_mean + shared_scales +
    labs(title = "Mean SGPc",
         x = "Sample Size (N)",
         y = "95% CI Width \u2014 Mean SGPc")

  p_median <- p_median + shared_scales +
    labs(title = "Median SGPc",
         x = "Sample Size (N)",
         y = "95% CI Width \u2014 Median SGPc")

  combined <- p_median | p_mean
  caption_theme <- if (!is.null(sampling_context)) {
    theme(plot.caption = element_text(size = 7, color = "grey50",
                                      hjust = 0, margin = margin(t = 6)))
  } else {
    theme()
  }
  combined <- combined + plot_annotation(
    title = title,
    subtitle = paste0(
      "N-operating curve: how 95% CI width changes with sample size ",
      "under without-replacement subsampling from condition pool"),
    caption = sampling_context,
    theme = theme(
      plot.title = element_text(face = "bold", size = 14, hjust = 0),
      plot.subtitle = element_text(size = 10, hjust = 0, color = "grey40")
    ) + caption_theme
  )

  save_plot_multi(combined, filename, output_dir,
                  width = PLOT_WIDTH * 1.6, height = PLOT_HEIGHT + 0.5)
  invisible(combined)
}
