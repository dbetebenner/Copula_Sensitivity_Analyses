############################################################################
###
### STEP 3 — Churn Bookkeeping and Diagnostics
###
### Computes stayer/leaver/entrant (S/L/E) decomposition and churn
### classification for longitudinal conditions. See §45 appendix:
### "Churn as Partial Linkage."
###
### Three conceptually distinct churn types are tracked:
###
###   demographic_churn — Students genuinely move into or out of the
###       jurisdiction between occasions.  Symmetric attrition at both
###       waves (α ≈ β) is the hallmark.
###
###   observability_churn — Students remain in the system but disappear
###       from the analytic sample because the measurement process changes
###       (alternate assessments, construct shifts, reporting ID failures).
###       Asymmetric attrition concentrated at the current wave (β << α)
###       is the signature.
###
###   compositional_churn — Leavers and/or entrants have systematically
###       different score distributions from stayers.  Detected by
###       comparing stayer-only marginals to all-student marginals.
###
############################################################################

# ---- Churn Bookkeeping ------------------------------------------------

#' Compute S/L/E Decomposition for a Condition
#'
#' Given the full state data and the matched longitudinal pairs, compute
#' the stayer/leaver/entrant counts and retention fractions at both the
#' condition level and (optionally) per subgroup.
#'
#' @param state_data data.table with columns GRADE, YEAR, CONTENT_AREA,
#'   SCALE_SCORE, and the subgroup column (if requested).
#' @param pairs data.table of matched longitudinal pairs (output of
#'   \code{create_longitudinal_pairs()}).  The number of rows equals n_S.
#' @param condition_meta List with year_prior, year_current, grade_prior,
#'   grade_current, content_area (from \code{parse_condition_id()}).
#' @param sg_col Optional character.  Subgroup column name (e.g.
#'   "DISTRICT_NUMBER") for per-subgroup breakdown.
#' @param asymmetry_threshold Numeric.  If |α − β| exceeds this, the
#'   condition is flagged as asymmetric churn.  Default 0.05.
#'
#' @return List with:
#'   \item{condition}{data.table — one row with n_prior_all, n_current_all,
#'     n_stayers, n_leavers, n_entrants, alpha, beta, churn_asymmetry,
#'     churn_type}
#'   \item{subgroup}{data.table — one row per subgroup (NULL if sg_col
#'     not provided or not present in state_data)}
#'
#' @export
compute_churn_bookkeeping <- function(
  state_data,
  pairs,
  condition_meta,
  sg_col = NULL,
  asymmetry_threshold = 0.05
) {
  # ---- Condition-level counts ----
  prior_mask <- state_data$GRADE == condition_meta$grade_prior &
    state_data$YEAR == condition_meta$year_prior &
    state_data$CONTENT_AREA == condition_meta$content_area &
    !is.na(state_data$SCALE_SCORE)
  current_mask <- state_data$GRADE == condition_meta$grade_current &
    state_data$YEAR == condition_meta$year_current &
    state_data$CONTENT_AREA == condition_meta$content_area &
    !is.na(state_data$SCALE_SCORE)

  n_prior_all <- sum(prior_mask)
  n_current_all <- sum(current_mask)
  n_stayers <- nrow(pairs)
  n_leavers <- max(0L, n_prior_all - n_stayers)
  n_entrants <- max(0L, n_current_all - n_stayers)

  alpha <- if (n_prior_all > 0) n_stayers / n_prior_all else NA_real_
  beta <- if (n_current_all > 0) n_stayers / n_current_all else NA_real_

  churn_asymmetry <- if (is.finite(alpha) && is.finite(beta)) {
    abs(alpha - beta)
  } else {
    NA_real_
  }

  churn_type <- classify_churn_type(alpha, beta, asymmetry_threshold)

  condition_dt <- data.table::data.table(
    n_prior_all = n_prior_all,
    n_current_all = n_current_all,
    n_stayers = n_stayers,
    n_leavers = n_leavers,
    n_entrants = n_entrants,
    alpha = round(alpha, 4),
    beta = round(beta, 4),
    churn_asymmetry = round(churn_asymmetry, 4),
    churn_type = churn_type
  )

  # ---- Per-subgroup breakdown ----
  subgroup_dt <- NULL
  if (
    !is.null(sg_col) &&
      sg_col %in% names(state_data) &&
      sg_col %in% names(pairs)
  ) {
    prior_sub <- state_data[prior_mask, .N, by = sg_col]
    data.table::setnames(prior_sub, "N", "n_prior_all")
    current_sub <- state_data[current_mask, .N, by = sg_col]
    data.table::setnames(current_sub, "N", "n_current_all")
    stayer_sub <- pairs[, .N, by = sg_col]
    data.table::setnames(stayer_sub, "N", "n_stayers")

    subgroup_dt <- merge(prior_sub, current_sub, by = sg_col, all = TRUE)
    subgroup_dt <- merge(subgroup_dt, stayer_sub, by = sg_col, all = TRUE)

    # Replace NA with 0 for counts
    for (col in c("n_prior_all", "n_current_all", "n_stayers")) {
      data.table::set(subgroup_dt, which(is.na(subgroup_dt[[col]])), col, 0L)
    }

    subgroup_dt[, n_leavers := pmax(0L, n_prior_all - n_stayers)]
    subgroup_dt[, n_entrants := pmax(0L, n_current_all - n_stayers)]
    subgroup_dt[,
      alpha := fifelse(n_prior_all > 0, n_stayers / n_prior_all, NA_real_)
    ]
    subgroup_dt[,
      beta := fifelse(n_current_all > 0, n_stayers / n_current_all, NA_real_)
    ]
    subgroup_dt[,
      churn_asymmetry := fifelse(
        is.finite(alpha) & is.finite(beta),
        abs(alpha - beta),
        NA_real_
      )
    ]
    subgroup_dt[,
      churn_type := mapply(
        classify_churn_type,
        alpha,
        beta,
        MoreArgs = list(threshold = asymmetry_threshold)
      )
    ]

    # Round for readability
    for (col in c("alpha", "beta", "churn_asymmetry")) {
      data.table::set(
        subgroup_dt,
        j = col,
        value = round(subgroup_dt[[col]], 4)
      )
    }
  }

  list(condition = condition_dt, subgroup = subgroup_dt)
}


# ---- Churn Type Classification -----------------------------------------

#' Classify Churn Type
#'
#' Labels a condition or subgroup as one of:
#'   "benign"       — high retention, roughly symmetric (α > 0.90, β > 0.90)
#'   "demographic"  — moderate attrition, roughly symmetric (|α − β| ≤ threshold)
#'   "observability"— strongly asymmetric, especially β << α (current wave loss)
#'   "mixed"        — compositional drift detected (set externally after
#'                    marginal comparison)
#'
#' @param alpha Prior retention rate n_S / n_U.
#' @param beta  Current retention rate n_S / n_V.
#' @param threshold Numeric.  Asymmetry threshold.
#'
#' @return Character scalar.
#' @export
classify_churn_type <- function(alpha, beta, threshold = 0.05) {
  if (!is.finite(alpha) || !is.finite(beta)) {
    return("unknown")
  }

  asymmetry <- abs(alpha - beta)
  min_rate <- min(alpha, beta)

  if (min_rate >= 0.90 && asymmetry <= threshold) {
    return("benign")
  }
  if (asymmetry > threshold) {
    # Asymmetric: which wave is losing students?
    if (beta < alpha - threshold) {
      return("observability") # current-wave concentrated loss
    } else if (alpha < beta - threshold) {
      return("observability_prior") # prior-wave concentrated loss (rare)
    }
  }
  return("demographic")
}


# ---- Marginal Comparison (Compositional Ignorability Test) --------------

#' Compare Stayer-Only Marginals to All-Student Marginals
#'
#' Tests Proposition 1 from §3 of the churn appendix: if stayers, leavers,
#' and entrants have similar score distributions, churn is compositionally
#' ignorable.  Uses Wasserstein-1 distance on empirical CDFs.
#'
#' @param state_data data.table with full state data.
#' @param pairs data.table of matched pairs (stayers).
#' @param condition_meta Parsed condition metadata.
#' @param n_grid Integer.  Grid resolution for CDF comparison.  Default 500.
#'
#' @return List with:
#'   \item{gamma_prior}  {Numeric. W1 distance between all-student and
#'     stayer-only prior marginals.}
#'   \item{gamma_current}{Numeric. W1 distance between all-student and
#'     stayer-only current marginals.}
#'   \item{prior_scores_all, prior_scores_stayer, current_scores_all,
#'     current_scores_stayer}{Numeric vectors of raw scores for density
#'     plotting.}
#'   \item{compositionally_ignorable}{Logical.  TRUE if both Γ are
#'     below a practical threshold.}
#'   \item{asymmetry_ratio}{Numeric.  Γ_V / Γ_U — values >> 1
#'     indicate current-wave observability churn.}
#'
#' @export
compare_marginals_stayer_vs_all <- function(
  state_data,
  pairs,
  condition_meta,
  n_grid = 500L
) {
  # All-student scores
  prior_mask <- state_data$GRADE == condition_meta$grade_prior &
    state_data$YEAR == condition_meta$year_prior &
    state_data$CONTENT_AREA == condition_meta$content_area &
    !is.na(state_data$SCALE_SCORE)
  current_mask <- state_data$GRADE == condition_meta$grade_current &
    state_data$YEAR == condition_meta$year_current &
    state_data$CONTENT_AREA == condition_meta$content_area &
    !is.na(state_data$SCALE_SCORE)

  prior_all <- state_data$SCALE_SCORE[prior_mask]
  current_all <- state_data$SCALE_SCORE[current_mask]

  # Stayer-only scores
  prior_stayer <- pairs$SCALE_SCORE_PRIOR[!is.na(pairs$SCALE_SCORE_PRIOR)]
  current_stayer <- pairs$SCALE_SCORE_CURRENT[!is.na(pairs$SCALE_SCORE_CURRENT)]

  # Wasserstein-1 on ECDFs evaluated on common grid
  gamma_prior <- ecdf_wasserstein1(prior_all, prior_stayer, n_grid)
  gamma_current <- ecdf_wasserstein1(current_all, current_stayer, n_grid)

  # Practical threshold: W1 < 1% of the score range (min 0.01 to avoid zero)
  range_prior <- tryCatch(
    diff(range(c(prior_all, prior_stayer), na.rm = TRUE)),
    error = function(e) NA_real_
  )
  range_current <- tryCatch(
    diff(range(c(current_all, current_stayer), na.rm = TRUE)),
    error = function(e) NA_real_
  )
  thresh_prior <- max(0.01 * (range_prior %||% 1), 0.01)
  thresh_current <- max(0.01 * (range_current %||% 1), 0.01)

  ignorable <- is.finite(gamma_prior) &&
    is.finite(gamma_current) &&
    (gamma_prior <= thresh_prior) &&
    (gamma_current <= thresh_current)

  asymmetry_ratio <- if (is.finite(gamma_prior) && gamma_prior > 0) {
    gamma_current / gamma_prior
  } else {
    NA_real_
  }

  list(
    gamma_prior = round(gamma_prior, 4),
    gamma_current = round(gamma_current, 4),
    prior_scores_all = prior_all,
    prior_scores_stayer = prior_stayer,
    current_scores_all = current_all,
    current_scores_stayer = current_stayer,
    compositionally_ignorable = ignorable,
    asymmetry_ratio = round(asymmetry_ratio, 2),
    description = paste0(
      "Marginal comparison: W1(F_all, F_stayer). ",
      "Gamma_prior = ",
      round(gamma_prior, 2),
      ", ",
      "Gamma_current = ",
      round(gamma_current, 2),
      ". ",
      if (ignorable) {
        "Compositionally ignorable."
      } else {
        "Compositional drift detected."
      }
    )
  )
}


# ---- Regime Contrast (Stayer vs. All-Student Regime) --------------------

#' Estimate Growth Regime from All-Student Cross-Sectional Marginals
#'
#' Fits the growth regime using all-student pseudo-observations rather
#' than stayer-only pairs. The difference between this and the stayer
#' regime isolates the combined effect of compositional drift and
#' observability churn.
#'
#' @param state_data data.table with full state data.
#' @param condition_meta Parsed condition metadata.
#' @param refs_stayer List with ref_prior and ref_current ECDFs built
#'   from stayers (output of \code{build_pairs_reference}).
#' @param kernel_cache Copula kernel cache.
#' @param regime_family Character. Regime family name.
#' @param distance_fn Character. Distance metric name.
#' @param grid_resolution Integer. Optimization grid resolution.
#' @param stayer_estimate Best-fit regime estimate from stayer data.
#'
#' @return List with:
#'   \item{regime_all}{The estimated regime from all-student marginals.}
#'   \item{delta_median}{Median SGPc difference (all − stayer), in SGP units.}
#'   \item{delta_mean}{Mean SGPc difference (all − stayer), in SGP units.}
#'   \item{w1_regime}{W1 distance between regime CDFs (optional).}
#'   \item{u_all, v_all}{Pseudo-observations for the all-student sample.}
#'
#' @export
estimate_regime_all_students <- function(
  state_data,
  condition_meta,
  refs_stayer,
  kernel_cache,
  regime_family,
  distance_fn,
  grid_resolution = 25L,
  stayer_estimate = NULL
) {
  # All-student scores at each wave
  prior_mask <- state_data$GRADE == condition_meta$grade_prior &
    state_data$YEAR == condition_meta$year_prior &
    state_data$CONTENT_AREA == condition_meta$content_area &
    !is.na(state_data$SCALE_SCORE)
  current_mask <- state_data$GRADE == condition_meta$grade_current &
    state_data$YEAR == condition_meta$year_current &
    state_data$CONTENT_AREA == condition_meta$content_area &
    !is.na(state_data$SCALE_SCORE)

  prior_all <- state_data$SCALE_SCORE[prior_mask]
  current_all <- state_data$SCALE_SCORE[current_mask]

  # Map all-student scores to pseudo-observations using stayer-based ECDFs.
  # This keeps the reference frame consistent: U and V are quantiles of the
  # stayer population, but now computed for all students.
  u_all <- pmin(pmax(refs_stayer$ref_prior(prior_all), 1e-6), 1 - 1e-6)
  v_all <- pmin(pmax(refs_stayer$ref_current(current_all), 1e-6), 1 - 1e-6)

  # Estimate regime from cross-sectional marginals (no pairing assumed)
  est_all <- tryCatch(
    estimate_regime(
      u_all,
      v_all,
      kernel_cache,
      regime_family = regime_family,
      distance_fn = distance_fn,
      grid_resolution = grid_resolution,
      verbose = FALSE
    ),
    error = function(e) NULL
  )

  if (is.null(est_all)) {
    return(list(
      regime_all = NULL,
      delta_median = NA_real_,
      delta_mean = NA_real_,
      w1_regime = NA_real_,
      u_all = u_all,
      v_all = v_all,
      description = "Regime estimation from all-student marginals failed."
    ))
  }

  median_all <- est_all$regime$median * 100
  mean_all <- est_all$regime$mean * 100

  delta_median <- NA_real_
  delta_mean <- NA_real_
  w1_regime <- NA_real_
  median_stayer <- NA_real_
  mean_stayer <- NA_real_

  if (!is.null(stayer_estimate)) {
    median_stayer <- stayer_estimate$regime$median * 100
    mean_stayer <- stayer_estimate$regime$mean * 100
    delta_median <- round(median_all - median_stayer, 2)
    delta_mean <- round(mean_all - mean_stayer, 2)
  }

  list(
    regime_all = est_all,
    median_sgpc_all = round(median_all, 2),
    mean_sgpc_all = round(mean_all, 2),
    median_sgpc_stayer = round(median_stayer, 2),
    mean_sgpc_stayer = round(mean_stayer, 2),
    delta_median = delta_median,
    delta_mean = delta_mean,
    w1_regime = w1_regime,
    u_all = u_all,
    v_all = v_all,
    n_prior_all = length(prior_all),
    n_current_all = length(current_all),
    description = paste0(
      "Regime contrast: all-student vs stayer-only. ",
      "Delta_median = ",
      delta_median,
      " SGPc, ",
      "Delta_mean = ",
      delta_mean,
      " SGPc."
    )
  )
}


# ---- Theoretical Partial-Linkage Premium --------------------------------

#' Compute Theoretical SE Multiplier for Partial Linkage
#'
#' From §5 of the churn appendix:
#'   Π_partial(s, ρ) ≈ sqrt((1 − s*ρ) / (1 − ρ))
#' and the CDF-scale version using Kendall's τ:
#'   Π_partial_CDF(s, ρ) ≈ sqrt((1 − s*τ(ρ)) / (1 − τ(ρ)))
#'
#' @param alpha Numeric. Stayer fraction (retention rate).
#' @param rho Numeric. Copula correlation parameter.
#'
#' @return List with mean_scale and cdf_scale multipliers.
#' @export
theoretical_linkage_premium <- function(alpha, rho) {
  if (!is.finite(alpha) || !is.finite(rho)) {
    return(list(
      mean_scale = NA_real_,
      cdf_scale = NA_real_,
      tau = NA_real_,
      alpha = alpha,
      rho = rho
    ))
  }

  tau <- (2 / pi) * asin(rho)

  mean_scale <- if (abs(1 - rho) > 1e-10) {
    sqrt((1 - alpha * rho) / (1 - rho))
  } else {
    NA_real_
  }

  cdf_scale <- if (abs(1 - tau) > 1e-10) {
    sqrt((1 - alpha * tau) / (1 - tau))
  } else {
    NA_real_
  }

  list(
    mean_scale = round(mean_scale, 4),
    cdf_scale = round(cdf_scale, 4),
    tau = round(tau, 4),
    alpha = round(alpha, 4),
    rho = round(rho, 4),
    description = paste0(
      "Theoretical premium at alpha=",
      round(alpha, 3),
      ", rho=",
      round(rho, 3),
      ": mean-scale=",
      round(mean_scale, 3),
      ", CDF-scale=",
      round(cdf_scale, 3)
    )
  )
}


# ---- Utility: Wasserstein-1 between two sample ECDFs -------------------

#' Wasserstein-1 Distance between Two Empirical Samples
#'
#' Evaluates both sample ECDFs on a common grid and computes W1 via
#' trapezoidal integration of |F1 − F2|.
#'
#' @param x Numeric vector (sample 1).
#' @param y Numeric vector (sample 2).
#' @param n_grid Grid resolution.
#'
#' @return Numeric scalar.
#' @keywords internal
ecdf_wasserstein1 <- function(x, y, n_grid = 500L) {
  x <- x[!is.na(x)]
  y <- y[!is.na(y)]
  if (length(x) < 2 || length(y) < 2) {
    return(NA_real_)
  }
  rng <- range(c(x, y), na.rm = TRUE)
  if (!is.finite(rng[1]) || !is.finite(rng[2]) || rng[1] == rng[2]) {
    return(NA_real_)
  }
  grid <- seq(rng[1], rng[2], length.out = n_grid)
  F1 <- ecdf(x)(grid)
  F2 <- ecdf(y)(grid)
  # Trapezoidal integration of |F1 − F2|
  diffs <- abs(F1 - F2)
  dx <- diff(grid)
  sum(dx * (diffs[-length(diffs)] + diffs[-1]) / 2)
}


# ---- Source confirmation ------------------------------------------------
cat("STEP 3 churn_bookkeeping.R loaded.\n")
cat("  Functions: compute_churn_bookkeeping, classify_churn_type,\n")
cat("             compare_marginals_stayer_vs_all,\n")
cat("             estimate_regime_all_students,\n")
cat("             theoretical_linkage_premium, ecdf_wasserstein1\n")
