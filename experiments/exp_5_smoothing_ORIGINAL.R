############################################################################
### Experiment 5: Sensitivity to ECDF Smoothing Method
### Question: How much does smoothing method affect copula inference?
############################################################################

# Load libraries and functions
require(data.table)
require(splines2)
require(copula)

# Load Colorado data
if (!exists("Colorado_Data_LONG")) {
  load("/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_Data_LONG.RData")
}

# Source functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
source("functions/copula_diagnostics.R")

cat("====================================================================\n")
cat("EXPERIMENT 5: SMOOTHING METHOD SENSITIVITY\n")
cat("====================================================================\n\n")

################################################################################
### ADDITIONAL SMOOTHING METHODS
################################################################################

#' Fit Hyman Spline ECDF (Alternative to I-splines)
fit_hyman_ecdf <- function(scale_scores, x_eval) {
  ecdf_obj <- ecdf(scale_scores)
  x_vals <- sort(unique(scale_scores))
  y_vals <- ecdf_obj(x_vals)
  
  smooth_ecdf <- splinefun(x_vals, y_vals, method = "hyman")
  y_smooth <- smooth_ecdf(x_eval)
  
  return(list(
    smooth_ecdf = smooth_ecdf,
    y_smooth = y_smooth
  ))
}

#' Fit Kernel Smoothed ECDF
fit_kernel_ecdf <- function(scale_scores, x_eval, bandwidth = NULL) {
  require(stats)
  
  # Use Silverman's rule of thumb if bandwidth not specified
  if (is.null(bandwidth)) {
    bandwidth <- 1.06 * sd(scale_scores) * length(scale_scores)^(-1/5)
  }
  
  # Kernel smoothed CDF
  y_smooth <- sapply(x_eval, function(x) {
    mean(pnorm((x - scale_scores) / bandwidth))
  })
  
  # Create function
  smooth_ecdf <- approxfun(x_eval, y_smooth, rule = 2)
  
  return(list(
    smooth_ecdf = smooth_ecdf,
    y_smooth = y_smooth,
    bandwidth = bandwidth
  ))
}

#' Fit Parametric ECDF (Normal approximation)
fit_parametric_ecdf <- function(scale_scores, x_eval) {
  mu <- mean(scale_scores)
  sigma <- sd(scale_scores)
  
  y_smooth <- pnorm(x_eval, mean = mu, sd = sigma)
  
  smooth_ecdf <- function(x) pnorm(x, mean = mu, sd = sigma)
  
  return(list(
    smooth_ecdf = smooth_ecdf,
    y_smooth = y_smooth,
    parameters = c(mu = mu, sigma = sigma)
  ))
}

#' Fit I-spline with More Knots
fit_ispline_moreknots <- function(scale_scores, x_eval) {
  require(splines2)
  
  # Use more knots: 10th, 20th, ..., 90th percentiles
  knot_percentiles <- seq(0.1, 0.9, by = 0.1)
  knot_locations <- quantile(scale_scores, probs = knot_percentiles)
  
  boundary_min <- min(scale_scores)
  boundary_max <- max(scale_scores)
  
  # Create I-spline basis
  ispline_basis <- iSpline(x_eval,
                           knots = knot_locations,
                           Boundary.knots = c(boundary_min, boundary_max),
                           degree = 3,
                           intercept = TRUE)
  
  # Fit to ECDF
  ecdf_obj <- ecdf(scale_scores)
  y_ecdf <- ecdf_obj(x_eval)
  
  # Use same fitting function from ispline_ecdf.R
  coef_fit <- fit_ispline_ecdf(ispline_basis, y_ecdf)
  y_smooth <- as.vector(ispline_basis %*% coef_fit)
  
  smooth_ecdf <- function(x) {
    basis_x <- iSpline(x,
                       knots = knot_locations,
                       Boundary.knots = c(boundary_min, boundary_max),
                       degree = 3,
                       intercept = TRUE)
    as.vector(basis_x %*% coef_fit)
  }
  
  return(list(
    smooth_ecdf = smooth_ecdf,
    y_smooth = y_smooth,
    n_knots = length(knot_locations)
  ))
}

################################################################################
### LOAD PHASE 1 DECISION (if available)
################################################################################

# Check if Phase 1 decision exists
if (file.exists("results/phase1_decision.RData")) {
  load("results/phase1_decision.RData")
  cat("====================================================================\n")
  cat("PHASE 2: Using families selected in Phase 1\n")
  cat("Families:", paste(phase2_families, collapse = ", "), "\n")
  cat("Rationale:", rationale, "\n")
  cat("====================================================================\n\n")
  USE_PHASE2_FAMILIES <- TRUE
} else {
  cat("Note: Phase 1 decision not found. Using all copula families.\n")
  cat("Run phase1_family_selection.R and phase1_analysis.R first\n")
  cat("for optimized family selection.\n\n")
  USE_PHASE2_FAMILIES <- FALSE
  phase2_families <- c("gaussian", "t", "clayton", "gumbel", "frank")
}

################################################################################
### CONFIGURATION
################################################################################

# Test configuration: Grade 4 -> 8, Mathematics, single cohort
CONFIG <- list(
  grade_prior = 4,
  grade_current = 8,
  year_prior = "2009",
  content = "MATHEMATICS"
)

SMOOTHING_METHODS <- list(
  list(name = "ispline_4knots", label = "I-spline (4 knots)", type = "ispline"),
  list(name = "ispline_9knots", label = "I-spline (9 knots)", type = "ispline_more"),
  list(name = "hyman", label = "Hyman Spline", type = "hyman"),
  list(name = "kernel", label = "Kernel Smoothing", type = "kernel"),
  list(name = "parametric", label = "Normal Approximation", type = "parametric")
)

SAMPLE_SIZES <- c(500, 1000, 2000)
N_BOOTSTRAP <- 100
COPULA_FAMILIES <- phase2_families

cat("Testing", length(SMOOTHING_METHODS), "smoothing methods:\n")
for (method in SMOOTHING_METHODS) {
  cat("  -", method$label, "\n")
}
cat("\n")

################################################################################
### PREPARE DATA
################################################################################

cat("====================================================================\n")
cat("Preparing longitudinal pairs...\n")
cat("====================================================================\n\n")

pairs_full <- create_longitudinal_pairs(
  data = Colorado_Data_LONG,
  grade_prior = CONFIG$grade_prior,
  grade_current = CONFIG$grade_current,
  year_prior = CONFIG$year_prior,
  content_prior = CONFIG$content,
  content_current = CONFIG$content
)

# Create evaluation grid (common to all methods)
x_grid <- seq(min(c(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT)),
              max(c(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT)),
              length.out = 500)

################################################################################
### TEST EACH SMOOTHING METHOD
################################################################################

all_results <- list()

for (method_config in SMOOTHING_METHODS) {
  
  cat("\n====================================================================\n")
  cat("Testing Method:", method_config$label, "\n")
  cat("====================================================================\n\n")
  
  # Fit smoothed ECDFs using this method
  if (method_config$type == "ispline") {
    # Standard I-spline with 4 knots (our default method)
    framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
    framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)
    
  } else if (method_config$type == "ispline_more") {
    # I-spline with 9 knots
    fit_prior <- fit_ispline_moreknots(pairs_full$SCALE_SCORE_PRIOR, x_grid)
    fit_current <- fit_ispline_moreknots(pairs_full$SCALE_SCORE_CURRENT, x_grid)
    
    framework_prior <- list(
      smooth_ecdf_full = fit_prior$smooth_ecdf,
      y_full_smooth = fit_prior$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_PRIOR),
      boundary_max = max(pairs_full$SCALE_SCORE_PRIOR),
      n_observations = length(pairs_full$SCALE_SCORE_PRIOR)
    )
    
    framework_current <- list(
      smooth_ecdf_full = fit_current$smooth_ecdf,
      y_full_smooth = fit_current$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_CURRENT),
      boundary_max = max(pairs_full$SCALE_SCORE_CURRENT),
      n_observations = length(pairs_full$SCALE_SCORE_CURRENT)
    )
    
  } else if (method_config$type == "hyman") {
    # Hyman spline method
    fit_prior <- fit_hyman_ecdf(pairs_full$SCALE_SCORE_PRIOR, x_grid)
    fit_current <- fit_hyman_ecdf(pairs_full$SCALE_SCORE_CURRENT, x_grid)
    
    framework_prior <- list(
      smooth_ecdf_full = fit_prior$smooth_ecdf,
      y_full_smooth = fit_prior$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_PRIOR),
      boundary_max = max(pairs_full$SCALE_SCORE_PRIOR),
      n_observations = length(pairs_full$SCALE_SCORE_PRIOR)
    )
    
    framework_current <- list(
      smooth_ecdf_full = fit_current$smooth_ecdf,
      y_full_smooth = fit_current$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_CURRENT),
      boundary_max = max(pairs_full$SCALE_SCORE_CURRENT),
      n_observations = length(pairs_full$SCALE_SCORE_CURRENT)
    )
    
  } else if (method_config$type == "kernel") {
    # Kernel smoothing
    fit_prior <- fit_kernel_ecdf(pairs_full$SCALE_SCORE_PRIOR, x_grid)
    fit_current <- fit_kernel_ecdf(pairs_full$SCALE_SCORE_CURRENT, x_grid)
    
    cat("Kernel bandwidth - Prior:", round(fit_prior$bandwidth, 2), "\n")
    cat("Kernel bandwidth - Current:", round(fit_current$bandwidth, 2), "\n\n")
    
    framework_prior <- list(
      smooth_ecdf_full = fit_prior$smooth_ecdf,
      y_full_smooth = fit_prior$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_PRIOR),
      boundary_max = max(pairs_full$SCALE_SCORE_PRIOR),
      n_observations = length(pairs_full$SCALE_SCORE_PRIOR)
    )
    
    framework_current <- list(
      smooth_ecdf_full = fit_current$smooth_ecdf,
      y_full_smooth = fit_current$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_CURRENT),
      boundary_max = max(pairs_full$SCALE_SCORE_CURRENT),
      n_observations = length(pairs_full$SCALE_SCORE_CURRENT)
    )
    
  } else if (method_config$type == "parametric") {
    # Parametric (Normal)
    fit_prior <- fit_parametric_ecdf(pairs_full$SCALE_SCORE_PRIOR, x_grid)
    fit_current <- fit_parametric_ecdf(pairs_full$SCALE_SCORE_CURRENT, x_grid)
    
    cat("Normal parameters - Prior: μ =", round(fit_prior$parameters["mu"], 2),
        ", σ =", round(fit_prior$parameters["sigma"], 2), "\n")
    cat("Normal parameters - Current: μ =", round(fit_current$parameters["mu"], 2),
        ", σ =", round(fit_current$parameters["sigma"], 2), "\n\n")
    
    framework_prior <- list(
      smooth_ecdf_full = fit_prior$smooth_ecdf,
      y_full_smooth = fit_prior$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_PRIOR),
      boundary_max = max(pairs_full$SCALE_SCORE_PRIOR),
      n_observations = length(pairs_full$SCALE_SCORE_PRIOR)
    )
    
    framework_current <- list(
      smooth_ecdf_full = fit_current$smooth_ecdf,
      y_full_smooth = fit_current$y_smooth,
      x_grid = x_grid,
      boundary_min = min(pairs_full$SCALE_SCORE_CURRENT),
      boundary_max = max(pairs_full$SCALE_SCORE_CURRENT),
      n_observations = length(pairs_full$SCALE_SCORE_CURRENT)
    )
  }
  
  # Fit true copula using this smoothing method
  cat("Fitting copula from full data...\n\n")
  
  true_copula <- fit_copula_from_pairs(
    scores_prior = pairs_full$SCALE_SCORE_PRIOR,
    scores_current = pairs_full$SCALE_SCORE_CURRENT,
    framework_prior = framework_prior,
    framework_current = framework_current,
    copula_families = COPULA_FAMILIES,
    return_best = FALSE
  )
  
  cat("True Kendall's tau:", round(true_copula$empirical_tau, 4), "\n")
  cat("Best family:", true_copula$best_family, "\n\n")
  
  # Store result for this method
  all_results[[method_config$name]] <- list(
    method_config = method_config,
    true_copula = true_copula,
    framework_prior = framework_prior,
    framework_current = framework_current
  )
  
  # Save true copula fit
  output_dir <- file.path("results", "exp_5_smoothing", method_config$name)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  save(true_copula, framework_prior, framework_current,
       file = file.path(output_dir, "true_copula.RData"))
}

################################################################################
### CROSS-METHOD COMPARISON
################################################################################

cat("\n====================================================================\n")
cat("CROSS-METHOD COMPARISON\n")
cat("====================================================================\n\n")

# Create comparison table
comparison_data <- list()

for (method_name in names(all_results)) {
  result <- all_results[[method_name]]
  
  comparison_data[[length(comparison_data) + 1]] <- data.table(
    method = result$method_config$label,
    method_code = method_name,
    empirical_tau = result$true_copula$empirical_tau,
    best_family = result$true_copula$best_family,
    gaussian_tau = if(!is.null(result$true_copula$results$gaussian)) 
      result$true_copula$results$gaussian$kendall_tau else NA,
    clayton_tau = if(!is.null(result$true_copula$results$clayton)) 
      result$true_copula$results$clayton$kendall_tau else NA,
    gumbel_tau = if(!is.null(result$true_copula$results$gumbel)) 
      result$true_copula$results$gumbel$kendall_tau else NA,
    frank_tau = if(!is.null(result$true_copula$results$frank)) 
      result$true_copula$results$frank$kendall_tau else NA
  )
}

comparison_table <- rbindlist(comparison_data)

# Save comparison
output_dir <- "results/exp_5_smoothing"
fwrite(comparison_table, file = file.path(output_dir, "method_comparison.csv"))

cat("Smoothing Method Comparison:\n\n")
print(comparison_table[, .(method, empirical_tau, best_family, gaussian_tau)])

# Calculate variability across methods
tau_range <- range(comparison_table$empirical_tau)
tau_sd <- sd(comparison_table$empirical_tau)
tau_cv <- tau_sd / mean(comparison_table$empirical_tau) * 100

cat("\nVariability Across Smoothing Methods:\n")
cat("  Mean tau:", round(mean(comparison_table$empirical_tau), 4), "\n")
cat("  SD of tau:", round(tau_sd, 4), "\n")
cat("  Range:", round(tau_range[1], 4), "to", round(tau_range[2], 4), "\n")
cat("  Coefficient of variation:", round(tau_cv, 2), "%\n\n")

# Create comparison plot
pdf(file.path(output_dir, "method_comparison.pdf"), width = 12, height = 8)

par(mfrow = c(2, 2))

# Plot 1: Empirical tau by method
barplot(comparison_table$empirical_tau,
        names.arg = 1:nrow(comparison_table),
        col = rainbow(nrow(comparison_table)),
        main = expression("Kendall's" ~ tau ~ "by Smoothing Method"),
        ylab = expression("Empirical Kendall's" ~ tau),
        ylim = c(min(comparison_table$empirical_tau) * 0.95, 
                 max(comparison_table$empirical_tau) * 1.05))
legend("topright", legend = comparison_table$method, 
       fill = rainbow(nrow(comparison_table)), cex = 0.7, bg = "white")
grid()

# Plot 2: Gaussian copula tau by method
barplot(comparison_table$gaussian_tau,
        names.arg = 1:nrow(comparison_table),
        col = rainbow(nrow(comparison_table)),
        main = expression("Gaussian Copula" ~ tau ~ "by Method"),
        ylab = expression("Kendall's" ~ tau),
        ylim = c(min(comparison_table$gaussian_tau, na.rm = TRUE) * 0.95, 
                 max(comparison_table$gaussian_tau, na.rm = TRUE) * 1.05))
grid()

# Plot 3: Method selection consistency
family_table <- table(comparison_table$best_family)
barplot(family_table,
        col = c("lightblue", "lightcoral", "lightgreen", "lightyellow")[1:length(family_table)],
        main = "Best Copula Family by Method",
        ylab = "Count",
        xlab = "Copula Family")
grid()

# Plot 4: All copula families comparison
plot(1:nrow(comparison_table), comparison_table$gaussian_tau,
     type = "b", pch = 19, col = "blue", lwd = 2, ylim = c(0.5, 0.9),
     xlab = "Method", ylab = expression("Kendall's" ~ tau),
     main = "All Copula Families Across Methods",
     xaxt = "n")
lines(1:nrow(comparison_table), comparison_table$clayton_tau, 
      type = "b", pch = 17, col = "red", lwd = 2)
lines(1:nrow(comparison_table), comparison_table$gumbel_tau, 
      type = "b", pch = 15, col = "darkgreen", lwd = 2)
lines(1:nrow(comparison_table), comparison_table$frank_tau, 
      type = "b", pch = 18, col = "purple", lwd = 2)
axis(1, at = 1:nrow(comparison_table), labels = 1:nrow(comparison_table))
legend("bottomleft", 
       legend = c("Gaussian", "Clayton", "Gumbel", "Frank"),
       col = c("blue", "red", "darkgreen", "purple"),
       lty = 1, pch = c(19, 17, 15, 18), lwd = 2, bg = "white")
grid()

dev.off()

cat("\n====================================================================\n")
cat("EXPERIMENT 5 COMPLETE\n")
cat("====================================================================\n\n")

cat("Key Findings:\n")
cat("- Tested", length(SMOOTHING_METHODS), "different smoothing methods\n")
cat("- Variability in tau across methods:", round(tau_sd, 4), 
    "(", round(tau_cv, 2), "% CV)\n")

if (tau_cv < 1) {
  cat("\nCONCLUSION: Smoothing method has MINIMAL impact on copula estimation.\n")
  cat("           Results are robust to smoothing choice.\n")
  cat("           I-spline method is validated.\n")
} else if (tau_cv < 3) {
  cat("\nCONCLUSION: Smoothing method has MODEST impact on copula estimation.\n")
  cat("           I-spline method is reasonable but consider sensitivity.\n")
} else {
  cat("\nCONCLUSION: Smoothing method has SUBSTANTIAL impact on copula estimation.\n")
  cat("           Choice of smoothing method matters. Further investigation needed.\n")
}

cat("\n- Results saved to: results/exp_5_smoothing/\n\n")

# Save workspace
save(all_results, comparison_table,
     file = file.path(output_dir, "smoothing_experiment.RData"))

cat("Workspace saved for further analysis.\n\n")
