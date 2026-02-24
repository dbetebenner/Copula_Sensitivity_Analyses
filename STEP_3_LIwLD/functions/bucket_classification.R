############################################################################
###
### Bucket Classification for STEP 3: Growth Regime Inference
###
### Policy-facing classification of subgroup growth regimes into
### low / typical / high buckets (K=3 or K=5) with uncertainty-aware
### posterior probabilities derived from bootstrap draws.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################


#' Classify a Growth Regime into Buckets
#'
#' Given a regime's median SGPc (or bootstrap draws thereof), compute the
#' probability of membership in each growth bucket.
#'
#' @param median_sgpc_draws Numeric vector of bootstrap median SGPc draws
#'   (on the 0-100 scale). If a single value, returns deterministic assignment.
#' @param k Integer. Number of buckets: 3 or 5. Default 3.
#' @param cutpoints Numeric vector of bucket boundaries (on 0-100 scale).
#'   If NULL, uses defaults from STEP3_CONFIG or plan defaults.
#'
#' @return A named list:
#'   \itemize{
#'     \item bucket_probs: Named numeric vector of bucket membership probabilities
#'     \item assigned_bucket: The bucket with highest probability
#'     \item classification_consistency: Probability of the assigned bucket
#'     \item k: Number of buckets used
#'     \item cutpoints: The cutpoints used
#'   }
#'
#' @export
classify_bucket <- function(median_sgpc_draws, k = 3, cutpoints = NULL) {

  if (is.null(cutpoints)) {
    cutpoints <- if (k == 3) {
      c(45, 55)
    } else if (k == 5) {
      c(40, 45, 55, 60)
    } else {
      stop("k must be 3 or 5")
    }
  }

  if (k == 3) {
    bucket_names <- c("Low", "Typical", "High")
  } else {
    bucket_names <- c("Very Low", "Low", "Typical", "High", "Very High")
  }

  breaks <- c(-Inf, cutpoints, Inf)
  draws <- median_sgpc_draws[!is.na(median_sgpc_draws)]

  if (length(draws) == 0) {
    probs <- rep(NA_real_, length(bucket_names))
    names(probs) <- bucket_names
    return(list(
      bucket_probs              = probs,
      assigned_bucket           = NA_character_,
      classification_consistency = NA_real_,
      k                         = k,
      cutpoints                 = cutpoints
    ))
  }

  bucket_assignment <- cut(draws, breaks = breaks, labels = bucket_names,
                           include.lowest = TRUE)
  probs <- table(factor(bucket_assignment, levels = bucket_names)) / length(draws)
  probs <- as.numeric(probs)
  names(probs) <- bucket_names

  assigned <- bucket_names[which.max(probs)]
  consistency <- max(probs)

  list(
    bucket_probs              = probs,
    assigned_bucket           = assigned,
    classification_consistency = consistency,
    k                         = k,
    cutpoints                 = cutpoints
  )
}


#' Compute Bucket Probabilities for a Subgroup
#'
#' Wrapper that computes both K=3 and K=5 classifications for a
#' single subgroup, given bootstrap draws.
#'
#' @param median_sgpc_draws Numeric vector of bootstrap median SGPc draws.
#' @param cutpoints_k3 Numeric vector. Default c(45, 55).
#' @param cutpoints_k5 Numeric vector. Default c(40, 45, 55, 60).
#'
#' @return A named list with $k3 and $k5, each from classify_bucket().
#'
#' @export
classify_subgroup_buckets <- function(median_sgpc_draws,
                                       cutpoints_k3 = c(45, 55),
                                       cutpoints_k5 = c(40, 45, 55, 60)) {
  list(
    k3 = classify_bucket(median_sgpc_draws, k = 3, cutpoints = cutpoints_k3),
    k5 = classify_bucket(median_sgpc_draws, k = 5, cutpoints = cutpoints_k5)
  )
}


#' Build Bucket Probabilities Table from Multiple Subgroups
#'
#' Given a list of subgroup results (each with bootstrap median_sgpc_draws),
#' returns a data.frame suitable for CSV export.
#'
#' @param subgroup_results Named list. Each element is a list with at least
#'   $bootstrap$median_sgpc_draws and $best_estimate$regime$median.
#' @param cutpoints_k3 Numeric vector. Default c(45, 55).
#' @param cutpoints_k5 Numeric vector. Default c(40, 45, 55, 60).
#'
#' @return A data.frame with columns: subgroup_id, median_sgpc,
#'   k3_Low, k3_Typical, k3_High, k3_assigned, k3_consistency,
#'   k5_VeryLow, k5_Low, k5_Typical, k5_High, k5_VeryHigh,
#'   k5_assigned, k5_consistency.
#'
#' @export
build_bucket_table <- function(subgroup_results,
                                cutpoints_k3 = c(45, 55),
                                cutpoints_k5 = c(40, 45, 55, 60)) {

  rows <- lapply(names(subgroup_results), function(sg_id) {
    sg <- subgroup_results[[sg_id]]

    draws <- if (!is.null(sg$bootstrap) && !is.null(sg$bootstrap$median_sgpc_draws)) {
      sg$bootstrap$median_sgpc_draws
    } else if (!is.null(sg$best_estimate)) {
      rep(sg$best_estimate$regime$median * 100, 1)
    } else {
      numeric(0)
    }

    bc <- classify_subgroup_buckets(draws, cutpoints_k3, cutpoints_k5)

    med_sgpc <- if (!is.null(sg$best_estimate)) {
      round(sg$best_estimate$regime$median * 100, 2)
    } else NA_real_

    data.frame(
      subgroup_id       = sg_id,
      median_sgpc       = med_sgpc,
      k3_Low            = round(bc$k3$bucket_probs["Low"], 4),
      k3_Typical        = round(bc$k3$bucket_probs["Typical"], 4),
      k3_High           = round(bc$k3$bucket_probs["High"], 4),
      k3_assigned       = bc$k3$assigned_bucket,
      k3_consistency    = round(bc$k3$classification_consistency, 4),
      k5_Very_Low       = round(bc$k5$bucket_probs["Very Low"], 4),
      k5_Low            = round(bc$k5$bucket_probs["Low"], 4),
      k5_Typical        = round(bc$k5$bucket_probs["Typical"], 4),
      k5_High           = round(bc$k5$bucket_probs["High"], 4),
      k5_Very_High      = round(bc$k5$bucket_probs["Very High"], 4),
      k5_assigned       = bc$k5$assigned_bucket,
      k5_consistency    = round(bc$k5$classification_consistency, 4),
      stringsAsFactors  = FALSE
    )
  })

  do.call(rbind, rows)
}


cat("STEP 3 bucket_classification.R loaded.\n")
cat("  Functions: classify_bucket, classify_subgroup_buckets, build_bucket_table\n")
