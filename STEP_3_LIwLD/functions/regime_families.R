############################################################################
###
### Growth Regime Families for STEP 3: Growth Regime Inference
###
### A growth regime H_theta is a distribution on [0,1] for latent
### conditional percentiles. When combined with a baseline copula
### kernel, it determines how a subgroup's current-grade marginal
### arises from their prior-grade marginal.
###
### Families implemented:
###   1. Beta(alpha, beta)  -- parameterised by (mean, concentration)
###   2. Truncated Exponential -- max-entropy under mean constraint
###   3. Truncated Uniform   -- flat but shifted
###
### Each returns a standardised "regime" object with $cdf, $quantile,
### $density, $mean, $median, $params, $family.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################


# ==========================================================================
# 1. Beta Family
# ==========================================================================

#' Create a Beta Growth Regime
#'
#' Parameterised by mean m in (0,1) and concentration kappa > 0 so that
#' alpha = m*kappa, beta = (1-m)*kappa. Uniform(0,1) is the special case
#' m = 0.5, kappa = 2.
#'
#' @param mean_val Numeric in (0,1). Mean of the Beta distribution.
#' @param kappa Numeric > 0. Concentration (alpha + beta).
#'   Higher kappa -> more peaked around the mean.
#'
#' @return A list with class "growth_regime" containing cdf, quantile,
#'   density, mean, median, params, family.
#'
#' @examples
#' \dontrun{
#' # Typical growth (centred at 0.5, moderate spread)
#' r <- regime_beta(0.50, 8)
#' r$cdf(0.5)     # ~0.50
#' r$density(0.5)  # peak value
#'
#' # High-growth regime (most mass above 0.5)
#' r_high <- regime_beta(0.65, 12)
#'
#' # Uniform baseline (max entropy)
#' r_unif <- regime_beta(0.50, 2)
#' }
#'
#' @export
regime_beta <- function(mean_val, kappa) {

  if (mean_val <= 0 || mean_val >= 1) stop("mean_val must be in (0,1)")
  if (kappa <= 0) stop("kappa must be > 0")

  alpha <- mean_val * kappa
  beta  <- (1 - mean_val) * kappa

  med  <- qbeta(0.5, shape1 = alpha, shape2 = beta)
  q25  <- qbeta(0.25, shape1 = alpha, shape2 = beta)
  q75  <- qbeta(0.75, shape1 = alpha, shape2 = beta)
  sd_p <- sqrt(alpha * beta / ((alpha + beta)^2 * (alpha + beta + 1)))

  result <- list(
    cdf      = function(p) pbeta(p, shape1 = alpha, shape2 = beta),
    quantile = function(q) qbeta(q, shape1 = alpha, shape2 = beta),
    density  = function(p) dbeta(p, shape1 = alpha, shape2 = beta),
    mean     = mean_val,
    median   = med,
    sd       = sd_p,
    iqr      = q75 - q25,
    entropy  = lbeta(alpha, beta) - (alpha - 1) * digamma(alpha) -
               (beta - 1) * digamma(beta) + (alpha + beta - 2) * digamma(alpha + beta),
    concentration = kappa,
    params   = list(alpha = alpha, beta = beta, mean = mean_val, kappa = kappa),
    family   = "beta"
  )
  class(result) <- "growth_regime"
  return(result)
}


# ==========================================================================
# 2. Truncated Exponential Family (Max-Entropy under mean constraint)
# ==========================================================================

#' Create a Truncated Exponential Growth Regime
#'
#' On [0,1], the maximum-entropy distribution with constraint E[P] = m
#' is a truncated exponential: f(p) proportional to exp(lambda * p).
#' Lambda is solved numerically to match the mean.
#'
#' @param mean_val Numeric in (0,1). Target mean.
#' @param tol Numeric. Tolerance for mean-matching. Default 1e-8.
#'
#' @return A list with class "growth_regime"
#'
#' @details
#' When mean_val = 0.5, lambda = 0 and the distribution is Uniform(0,1).
#' When mean_val > 0.5, lambda > 0 (tilted toward 1).
#' When mean_val < 0.5, lambda < 0 (tilted toward 0).
#'
#' @export
regime_truncexp <- function(mean_val, tol = 1e-8) {

  if (mean_val <= 0 || mean_val >= 1) stop("mean_val must be in (0,1)")

  # Solve for lambda such that E[P] = mean_val under f(p) propto exp(lambda*p)
  # E[P] = 1/lambda - 1/(exp(lambda)-1)  when lambda != 0
  # E[P] = 0.5 when lambda = 0

  if (abs(mean_val - 0.5) < tol) {
    # Uniform case
    lambda <- 0
  } else {
    # Numerical solve
    mean_fn <- function(lam) {
      if (abs(lam) < 1e-10) return(0.5)
      1 / lam - 1 / (exp(lam) - 1)
    }
    obj <- function(lam) (mean_fn(lam) - mean_val)^2
    opt <- optim(par = 0, fn = obj, method = "Brent",
                 lower = -50, upper = 50)
    lambda <- opt$par
  }

  # Normalising constant: integral of exp(lambda*p) from 0 to 1
  if (abs(lambda) < 1e-10) {
    log_norm <- 0  # integral = 1
    norm_const <- 1
  } else {
    norm_const <- (exp(lambda) - 1) / lambda
    log_norm <- log(norm_const)
  }

  # CDF: integral from 0 to p of exp(lambda*t)/norm
  cdf_fn <- function(p) {
    p <- pmax(0, pmin(1, p))
    if (abs(lambda) < 1e-10) return(p)
    (exp(lambda * p) - 1) / (exp(lambda) - 1)
  }

  # Density
  density_fn <- function(p) {
    p <- pmax(0, pmin(1, p))
    exp(lambda * p) / norm_const
  }

  # Quantile (inverse CDF)
  quantile_fn <- function(q) {
    q <- pmax(1e-10, pmin(1 - 1e-10, q))
    if (abs(lambda) < 1e-10) return(q)
    log(1 + q * (exp(lambda) - 1)) / lambda
  }

  med  <- quantile_fn(0.5)
  q25  <- quantile_fn(0.25)
  q75  <- quantile_fn(0.75)

  # Variance of truncated exponential on [0,1]
  if (abs(lambda) < 1e-10) {
    var_p <- 1 / 12
  } else {
    e_p2 <- 2 / lambda^2 - (2 * exp(lambda)) / (lambda * (exp(lambda) - 1)) +
             exp(lambda) / (exp(lambda) - 1)
    var_p <- max(0, e_p2 - mean_val^2)
  }

  # Differential entropy of truncated exponential
  ent <- log(norm_const) - lambda * mean_val

  result <- list(
    cdf      = Vectorize(cdf_fn),
    quantile = Vectorize(quantile_fn),
    density  = Vectorize(density_fn),
    mean     = mean_val,
    median   = med,
    sd       = sqrt(var_p),
    iqr      = q75 - q25,
    entropy  = ent,
    concentration = 1 / max(var_p, 1e-10),
    params   = list(lambda = lambda, mean = mean_val),
    family   = "truncexp"
  )
  class(result) <- "growth_regime"
  return(result)
}


# ==========================================================================
# 3. Truncated Uniform Family
# ==========================================================================

#' Create a Truncated Uniform Growth Regime
#'
#' Uniform distribution on [lower, upper] subset of [0,1].
#' Useful for stress-testing "flat but shifted" regimes.
#'
#' @param lower Numeric in [0,1). Lower bound.
#' @param upper Numeric in (0,1]. Upper bound. Must be > lower.
#'
#' @return A list with class "growth_regime"
#'
#' @export
regime_truncunif <- function(lower = 0, upper = 1) {

  if (lower < 0 || lower >= 1) stop("lower must be in [0,1)")
  if (upper <= 0 || upper > 1) stop("upper must be in (0,1]")
  if (upper <= lower) stop("upper must be > lower")

  width <- upper - lower
  mean_val <- (lower + upper) / 2

  cdf_fn <- function(p) {
    p <- pmax(0, pmin(1, p))
    pmax(0, pmin(1, (p - lower) / width))
  }

  density_fn <- function(p) {
    ifelse(p >= lower & p <= upper, 1 / width, 0)
  }

  quantile_fn <- function(q) {
    q <- pmax(0, pmin(1, q))
    lower + q * width
  }

  sd_p <- width / sqrt(12)
  q25  <- lower + 0.25 * width
  q75  <- lower + 0.75 * width
  ent  <- log(width)

  result <- list(
    cdf      = Vectorize(cdf_fn),
    quantile = Vectorize(quantile_fn),
    density  = Vectorize(density_fn),
    mean     = mean_val,
    median   = mean_val,
    sd       = sd_p,
    iqr      = q75 - q25,
    entropy  = ent,
    concentration = 1 / max(sd_p^2, 1e-10),
    params   = list(lower = lower, upper = upper),
    family   = "truncunif"
  )
  class(result) <- "growth_regime"
  return(result)
}


# ==========================================================================
# Utility: Create regime from theta vector (for optimizer interface)
# ==========================================================================

#' Create a Growth Regime from a Parameter Vector
#'
#' Dispatcher that creates a regime object from a named family and parameter
#' vector. Used by the optimizer so it can work in a generic theta-space.
#'
#' @param family Character. One of "beta", "truncexp", "truncunif".
#' @param theta Numeric vector of parameters:
#'   \itemize{
#'     \item beta: c(mean, kappa)
#'     \item truncexp: c(mean)
#'     \item truncunif: c(lower, upper)
#'   }
#'
#' @return A growth_regime object
#'
#' @export
create_regime <- function(family, theta) {

  family <- tolower(family)

  switch(family,
    beta = {
      if (length(theta) != 2) stop("Beta regime requires theta = c(mean, kappa)")
      regime_beta(theta[1], theta[2])
    },
    truncexp = {
      if (length(theta) != 1) stop("Truncexp regime requires theta = c(mean)")
      regime_truncexp(theta[1])
    },
    truncunif = {
      if (length(theta) != 2) stop("Truncunif regime requires theta = c(lower, upper)")
      regime_truncunif(theta[1], theta[2])
    },
    stop("Unknown regime family: ", family)
  )
}


#' Print Method for Growth Regime Objects
#'
#' @param x A growth_regime object
#' @param ... Ignored
#' @export
print.growth_regime <- function(x, ...) {
  cat("Growth Regime:", x$family, "\n")
  cat("  Mean:          ", sprintf("%.4f", x$mean), "\n")
  cat("  Median:        ", sprintf("%.4f", x$median), "\n")
  cat("  SD:            ", sprintf("%.4f", x$sd), "\n")
  cat("  IQR:           ", sprintf("%.4f", x$iqr), "\n")
  cat("  Entropy:       ", sprintf("%.4f", x$entropy), "\n")
  cat("  Concentration: ", sprintf("%.2f", x$concentration), "\n")
  cat("  Params: ", paste(names(x$params), "=",
      sprintf("%.4f", unlist(x$params)), collapse = ", "), "\n")
}


cat("STEP 3 regime_families.R loaded.\n")
cat("  Functions: regime_beta, regime_truncexp, regime_truncunif, create_regime\n")
