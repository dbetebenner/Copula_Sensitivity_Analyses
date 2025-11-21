############################################################################
### Copula Bootstrap and Estimation Functions
############################################################################

require(copula)
require(data.table)

#' Perform Goodness-of-Fit Test using copula Package
#' 
#' @param fitted_copula Fitted copula object from fitCopula()
#' @param pseudo_obs Matrix of pseudo-observations (n x 2)
#' @param n_bootstrap Number of bootstrap samples (N parameter in gofCopula)
#' @param family Family name ("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")
#' 
#' @return List with gof_statistic, gof_pvalue, gof_method
#' 
#' @details
#' Uses copula::gofCopula with Cramér-von Mises test statistic (method="Sn") 
#' and parametric bootstrap (simulation="pb"). For t-copulas, degrees of freedom 
#' are rounded to the nearest integer for compatibility. 
#' 
#' Comonotonic copula: Calculates observed CvM statistic only (no bootstrap or 
#' p-value) to quantify deviation from perfect positive dependence C(u,v) = min(u,v).
perform_gof_test <- function(fitted_copula, pseudo_obs, n_bootstrap = 1000, family = NULL) {
  
  # COMONOTONIC: Calculate observed statistic only (no bootstrap needed)
  if (!is.null(family) && family == "comonotonic") {
    tryCatch({
      # Comonotonic copula: C(u,v) = min(u,v)
      n <- nrow(pseudo_obs)
      
      # Calculate empirical copula
      U <- pseudo_obs[, 1]
      V <- pseudo_obs[, 2]
      
      # For each point (u,v), calculate empirical copula value
      C_n <- sapply(1:n, function(i) {
        sum(U <= U[i] & V <= V[i]) / n
      })
      
      # Theoretical comonotonic copula values
      C_comonotonic <- pmin(U, V)
      
      # Cramér-von Mises statistic: n * mean((C_n - C_theory)^2)
      cvm_stat <- n * mean((C_n - C_comonotonic)^2)
      
      return(list(
        gof_statistic = cvm_stat,
        gof_pvalue = NA_real_,  # No bootstrap, so no p-value
        gof_method = "comonotonic_observed_only"
      ))
    }, error = function(e) {
      return(list(
        gof_statistic = NA_real_,
        gof_pvalue = NA_real_,
        gof_method = paste0("comonotonic_failed: ", substr(e$message, 1, 50))
      ))
    })
  }
  
  # Use copula::gofCopula for all parametric families
  tryCatch({
    # For t-copula, need to round df to nearest integer for compatibility
    if (family == "t") {
      rho <- fitted_copula@parameters[1]
      df <- fitted_copula@parameters[2]
      df_rounded <- round(df)
      
      # Create t-copula with fixed, rounded df
      cop_for_gof <- tCopula(param = rho, dim = 2, df = df_rounded, df.fixed = TRUE)
    } else {
      # For other families, use fitted copula directly
      cop_for_gof <- fitted_copula
    }
    
    # Run GoF test with parametric bootstrap
    gof_result <- copula::gofCopula(
      copula = cop_for_gof,
      x = pseudo_obs,
      N = n_bootstrap,
      method = "Sn",           # Cramér-von Mises statistic (default)
      estim.method = "mpl",    # Maximum pseudo-likelihood (consistent with fitting)
      simulation = "pb",       # Parametric bootstrap
      verbose = FALSE
    )
    
    return(list(
      gof_statistic = gof_result$statistic,
      gof_pvalue = gof_result$p.value,
      gof_method = paste0("copula_gofCopula_N=", n_bootstrap)
    ))
    
  }, error = function(e) {
    error_msg <- e$message
    if (nchar(error_msg) > 100) {
      error_msg <- paste0(substr(error_msg, 1, 97), "...")
    }
    return(list(
      gof_statistic = NA_real_,
      gof_pvalue = NA_real_,
      gof_method = paste0("gof_failed: ", error_msg)
    ))
  })
}

#' Fit Copula to Longitudinal Pairs
#' 
#' Estimate copula from prior-current score pairs
#' 
#' @param scores_prior Vector of prior scale scores
#' @param scores_current Vector of current scale scores
#' @param framework_prior I-spline framework for prior scores (can be NULL if use_empirical_ranks=TRUE)
#' @param framework_current I-spline framework for current scores (can be NULL if use_empirical_ranks=TRUE)
#' @param copula_families Vector of copula families to fit ("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")
#' @param return_best If TRUE, return only best-fitting copula; if FALSE, return all
#' @param use_empirical_ranks If TRUE, use empirical ranks for pseudo-observations (Phase 1).
#'                            If FALSE, use framework transformations (Phase 2+, requires invertibility)
#' @param save_copula_data If TRUE, save additional data for visualization (default FALSE)
#' @param output_dir Directory to save copula data files (required if save_copula_data=TRUE)
#' 
#' @return List containing fitted copulas, parameters, and diagnostics
#' 
#' @details 
#' Two-stage transformation approach:
#' - Phase 1 (family selection): use_empirical_ranks=TRUE uses copula::pobs() for proper pseudo-observations
#' - Phase 2+ (applications): use_empirical_ranks=FALSE provides invertible transformations
#' 
#' Phase 1 uses copula::pobs() (Genest et al., 2009) for rank-based transformation.
#' GoF testing uses copula::gofCopula with parametric bootstrap, which provides 
#' accurate p-values for assessing absolute model fit.
fit_copula_from_pairs <- function(scores_prior,
                                  scores_current,
                                  framework_prior,
                                  framework_current,
                                  copula_families = c("gaussian", "t", "clayton", "gumbel", "frank"),
                                  return_best = TRUE,
                                  use_empirical_ranks = FALSE,
                                  n_bootstrap_gof = 0,
                                  save_copula_data = FALSE,
                                  output_dir = NULL) {
  
  # Transform to pseudo-observations
  if (use_empirical_ranks) {
    # Phase 1: Use empirical ranks for copula family selection
    # Uses copula::pobs() with randomized tie-breaking (Genest et al., 2009; 
    # Kojadinovic and Yan, 2010) which:
    # - Guarantees uniform marginals via rank transformation
    # - Properly handles ties in discrete test scores via ties.method="random"
    # - Recommended for GoF testing: more accurate p-values with large n and ties
    # - Preserves rank-based dependence measures (Kendall's tau, Spearman's rho)
    # - Makes no assumptions about marginal distributions
    # - Compatible with gofCopula package's Kendall transform-based tests
    # - Requires fixed seed for reproducibility (using 314159 = first 6 digits of π)
    set.seed(314159)
    pseudo_obs_matrix <- pobs(cbind(scores_prior, scores_current), 
                              ties.method = "random")
    U <- pseudo_obs_matrix[,1]
    V <- pseudo_obs_matrix[,2]
    
  } else {
    # Phase 2+: Use framework transformations (I-spline, Q-spline, etc.)
    # These provide invertibility needed for predictions and simulations
    if (is.null(framework_prior) || is.null(framework_current)) {
      stop("framework_prior and framework_current required when use_empirical_ranks=FALSE")
    }
    
    U <- framework_prior$smooth_ecdf_full(scores_prior)
    V <- framework_current$smooth_ecdf_full(scores_current)
    
    # Constrain to (0,1) interval (handle boundary issues)
    U <- pmax(1e-6, pmin(1 - 1e-6, U))
    V <- pmax(1e-6, pmin(1 - 1e-6, V))
  }
  
  pseudo_obs <- cbind(U, V)
  
  # Fit each copula family
  results <- list()
  
  for (family in copula_families) {
    
    tryCatch({
      if (family == "gaussian") {
        # Gaussian copula
        cop <- normalCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "mpl")
        
        results[[family]] <- list(
          copula = fit@copula,
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          bic = -2 * fit@loglik + log(nrow(pseudo_obs)) * length(fit@estimate),
          kendall_tau = tau(fit@copula),  # Use copula package function for correct tau
          family = "gaussian"
        )
        
      } else if (family == "clayton") {
        # Clayton copula (lower tail dependence)
        cop <- claytonCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "mpl")
        
        results[[family]] <- list(
          copula = fit@copula,
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          bic = -2 * fit@loglik + log(nrow(pseudo_obs)) * length(fit@estimate),
          kendall_tau = fit@estimate / (fit@estimate + 2),  # Clayton tau formula
          family = "clayton"
        )
        
      } else if (family == "gumbel") {
        # Gumbel copula (upper tail dependence)
        cop <- gumbelCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "mpl")
        
        results[[family]] <- list(
          copula = fit@copula,
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          bic = -2 * fit@loglik + log(nrow(pseudo_obs)) * length(fit@estimate),
          kendall_tau = 1 - 1/fit@estimate,  # Gumbel tau formula
          family = "gumbel"
        )
        
      } else if (family == "frank") {
        # Frank copula (no tail dependence)
        cop <- frankCopula(dim = 2)
        fit <- fitCopula(cop, pseudo_obs, method = "mpl")
        
        # Frank Kendall's tau requires numerical integration, approximate here
        theta <- fit@estimate
        results[[family]] <- list(
          copula = fit@copula,
          parameter = fit@estimate,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          bic = -2 * fit@loglik + log(nrow(pseudo_obs)) * length(fit@estimate),
          kendall_tau = tau(fit@copula),  # Use copula package function
          family = "frank"
        )
        
      } else if (family == "t") {
        # Student's t copula (symmetric tail dependence)
        cop <- tCopula(dim = 2, dispstr = "un")  # unconstrained correlation
        fit <- fitCopula(cop, pseudo_obs, method = "mpl")
        
        # Extract parameters: correlation and degrees of freedom
        rho <- fit@estimate[1]  # correlation parameter
        df <- fit@estimate[2]   # degrees of freedom
        df_rounded <- round(df)  # Round for stability in plotting/evaluation
        
        # Create a new t-copula with rounded df for plotting (more stable)
        copula_rounded <- tCopula(param = rho, dim = 2, df = df_rounded, df.fixed = TRUE)
        
        # Calculate tail dependence manually (consistent with fixed df variants)
        # For t-copula: λ = 2 * t_{df+1}(-√((df+1)(1-ρ)/(1+ρ)))
        tail_dep_val <- 2 * pt(-sqrt((df + 1) * (1 - rho) / (1 + rho)), df = df + 1)
        
        results[[family]] <- list(
          copula = copula_rounded,  # Use rounded version for stability
          parameter = rho,
          df = df,  # Store original df for reporting
          df_rounded = df_rounded,  # Also store rounded version
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          bic = -2 * fit@loglik + log(nrow(pseudo_obs)) * length(fit@estimate),
          kendall_tau = tau(fit@copula),
          tail_dependence_lower = tail_dep_val,  # Now calculated manually
          tail_dependence_upper = tail_dep_val,  # Symmetric for t-copula
          family = "t"
        )
        
      } else if (family == "comonotonic") {
        # Comonotonic copula (Fréchet-Hoeffding upper bound)
        # C(u,v) = min(u,v), represents perfect positive dependence
        # This is what TAMP implicitly assumes
        
        # Kendall's tau = 1.0 by definition
        kendall_tau <- 1.0
        
        # Calculate pseudo-log-likelihood based on deviation from perfect dependence
        # For comonotonic copula, we expect U ≈ V
        # Larger deviation = worse fit = more negative log-likelihood
        deviations <- abs(U - V)
        mean_abs_deviation <- mean(deviations)
        mean_squared_deviation <- mean(deviations^2)
        
        # Pseudo-log-likelihood: penalize deviations from perfect dependence
        # Use negative of scaled squared deviations (worse fit = more negative)
        # Scale by sample size for consistency with ML-based copulas
        pseudo_loglik <- -nrow(pseudo_obs) * mean_squared_deviation * 1000
        
        # No parameters to estimate (it's a fixed copula), so k=0
        n_params <- 0
        
        results[[family]] <- list(
          copula = NULL,  # Not a fitted copula object
          parameter = NA,  # No parameters (fixed copula)
          loglik = pseudo_loglik,
          aic = -2 * pseudo_loglik + 2 * n_params,
          bic = -2 * pseudo_loglik + log(nrow(pseudo_obs)) * n_params,
          kendall_tau = kendall_tau,
          tail_dependence_lower = 1,  # Perfect lower tail dependence (U = V everywhere)
          tail_dependence_upper = 1,  # Perfect upper tail dependence (U = V everywhere)
          mean_abs_deviation = mean_abs_deviation,  # Diagnostic
          mean_squared_deviation = mean_squared_deviation,  # Diagnostic
          family = "comonotonic"
        )
      }
      
    }, error = function(e) {
      warning(paste("Failed to fit", family, "copula:", e$message))
      results[[family]] <<- NULL
    })
  }
  
  # Add Goodness-of-Fit testing if requested (n_bootstrap_gof > 0 or n_bootstrap_gof == 0 for asymptotic)
  if (!is.null(n_bootstrap_gof)) {
    for (family in names(results)) {
      if (family == "comonotonic") {
        # Special handling for comonotonic
        gof_test <- perform_gof_test(fitted_copula = NULL, 
                                     pseudo_obs = pseudo_obs,
                                     n_bootstrap = n_bootstrap_gof,
                                     family = "comonotonic")
      } else {
        # Standard parametric copulas
        gof_test <- perform_gof_test(fitted_copula = results[[family]]$copula,
                                     pseudo_obs = pseudo_obs,
                                     n_bootstrap = n_bootstrap_gof,
                                     family = family)
      }
      
      # Add GoF results to this family's results
      results[[family]]$gof_statistic <- gof_test$gof_statistic
      results[[family]]$gof_pvalue <- gof_test$gof_pvalue
      results[[family]]$gof_method <- gof_test$gof_method
    }
  }
  
  # Add empirical Kendall's tau
  empirical_tau <- cor(U, V, method = "kendall")
  
  # Save copula data for visualization if requested
  if (save_copula_data) {
    if (is.null(output_dir)) {
      warning("save_copula_data=TRUE but output_dir not specified. Skipping data save.")
    } else {
      # Create directory if it doesn't exist
      if (!dir.exists(output_dir)) {
        dir.create(output_dir, recursive = TRUE)
      }
      
      # Save pseudo-observations
      saveRDS(pseudo_obs, file = file.path(output_dir, "pseudo_observations.rds"))
      
      # Save original scores
      original_scores <- data.table(
        SCALE_SCORE_PRIOR = scores_prior,
        SCALE_SCORE_CURRENT = scores_current
      )
      saveRDS(original_scores, file = file.path(output_dir, "original_scores.rds"))
      
      # Save fitted copula results
      saveRDS(results, file = file.path(output_dir, "copula_results.rds"))
      
      # Calculate and save empirical copula grid for visualization
      if (requireNamespace("ks", quietly = TRUE)) {
        # Use our new function if available
        source_file <- system.file("functions", "copula_contour_plots.R", package = "copula")
        if (file.exists(source_file)) {
          source(source_file)
        } else if (file.exists("functions/copula_contour_plots.R")) {
          source("functions/copula_contour_plots.R")
        }
        
        if (exists("calculate_empirical_copula_grid")) {
          empirical_grid <- calculate_empirical_copula_grid(pseudo_obs, 
                                                           grid_size = 300,
                                                           method = "density")
          saveRDS(empirical_grid, file = file.path(output_dir, "empirical_copula_grid.rds"))
        }
      }
      
      cat(sprintf("  Saved copula data to: %s\n", output_dir))
    }
  }
  
  # Select best copula by AIC
  if (length(results) > 0) {
    aics <- sapply(results, function(x) x$aic)
    best_family <- names(which.min(aics))
    
    output <- list(
      results = results,
      best_family = best_family,
      best_copula = results[[best_family]],
      empirical_tau = empirical_tau,
      pseudo_obs = pseudo_obs,
      n_pairs = nrow(pseudo_obs),
      original_scores = if (save_copula_data) {
        data.table(SCALE_SCORE_PRIOR = scores_prior, SCALE_SCORE_CURRENT = scores_current)
      } else NULL
    )
    
    if (return_best) {
      return(output$best_copula)
    } else {
      return(output)
    }
  } else {
    stop("All copula fits failed")
  }
}


#' Bootstrap Copula Estimation
#' 
#' Generate bootstrap samples and estimate copulas for sensitivity analysis
#' 
#' @param pairs_data data.table with SCALE_SCORE_PRIOR and SCALE_SCORE_CURRENT
#' @param n_sample_prior Sample size for prior scores
#' @param n_sample_current Sample size for current scores
#' @param n_bootstrap Number of bootstrap iterations
#' @param framework_prior I-spline framework for prior (can be NULL if use_empirical_ranks=TRUE)
#' @param framework_current I-spline framework for current (can be NULL if use_empirical_ranks=TRUE)
#' @param sampling_method "independent" or "paired"
#' @param copula_families Copula families to fit ("gaussian", "t", "clayton", "gumbel", "frank", "comonotonic")
#' @param with_replacement TRUE for standard bootstrap
#' @param use_empirical_ranks Use empirical ranks for transformation (default FALSE for Phase 2)
#' @param use_parallel Use parallel processing (default FALSE, uses mclapply on Unix/Mac)
#' @param n_cores Number of cores to use for parallel processing (default: detectCores() - 1)
#' 
#' @return List containing bootstrap copula results
bootstrap_copula_estimation <- function(pairs_data,
                                       n_sample_prior,
                                       n_sample_current,
                                       n_bootstrap,
                                       framework_prior,
                                       framework_current,
                                       sampling_method = "paired",
                                       copula_families = c("gaussian", "t", "clayton", "gumbel", "frank"),
                                       with_replacement = TRUE,
                                       use_empirical_ranks = FALSE,
                                       use_parallel = FALSE,
                                       n_cores = NULL) {
  
  require(data.table)
  
  cat("Running", n_bootstrap, "bootstrap copula estimations...\n")
  cat("  Sampling method:", sampling_method, "\n")
  cat("  Sample sizes: n_prior =", n_sample_prior, ", n_current =", n_sample_current, "\n")
  
  # Set up parallel processing if requested
  if (use_parallel) {
    if (.Platform$OS.type == "unix") {
      require(parallel)
      if (is.null(n_cores)) {
        n_cores <- detectCores() - 1
      }
      cat("  Parallel processing: ENABLED (", n_cores, "cores on Unix)\n\n")
    } else {
      warning("Parallel processing only supported on Unix/Mac. Running sequentially.")
      use_parallel <- FALSE
      cat("  Parallel processing: DISABLED (Windows not supported)\n\n")
    }
  } else {
    cat("  Parallel processing: DISABLED\n\n")
  }
  
  # Worker function for a single bootstrap iteration
  bootstrap_worker <- function(b) {
    tryCatch({
      
      if (sampling_method == "paired") {
        # Sample complete pairs (maintains within-student correlation)
        if (with_replacement) {
          sample_ids <- sample(1:nrow(pairs_data), size = min(n_sample_prior, n_sample_current), 
                              replace = TRUE)
        } else {
          sample_ids <- sample(1:nrow(pairs_data), size = min(n_sample_prior, n_sample_current), 
                              replace = FALSE)
        }
        
        scores_prior_boot <- pairs_data$SCALE_SCORE_PRIOR[sample_ids]
        scores_current_boot <- pairs_data$SCALE_SCORE_CURRENT[sample_ids]
        
      } else if (sampling_method == "independent") {
        # Sample prior and current independently (breaks within-student correlation)
        scores_prior_boot <- sample(pairs_data$SCALE_SCORE_PRIOR, 
                                    size = n_sample_prior, 
                                    replace = with_replacement)
        scores_current_boot <- sample(pairs_data$SCALE_SCORE_CURRENT, 
                                      size = n_sample_current, 
                                      replace = with_replacement)
      }
      
      # Fit copulas to bootstrap sample
      cop_fit <- fit_copula_from_pairs(
        scores_prior = scores_prior_boot,
        scores_current = scores_current_boot,
        framework_prior = framework_prior,
        framework_current = framework_current,
        copula_families = copula_families,
        return_best = FALSE,
        use_empirical_ranks = use_empirical_ranks,
        n_bootstrap_gof = NULL  # Don't run GoF for bootstrap samples
      )
      
      # Extract parameters for each family
      params_list <- list()
      taus_list <- list()
      for (fam in copula_families) {
        if (!is.null(cop_fit$results[[fam]])) {
          params_list[[fam]] <- cop_fit$results[[fam]]$parameter
          taus_list[[fam]] <- cop_fit$results[[fam]]$kendall_tau
        } else {
          params_list[[fam]] <- NA
          taus_list[[fam]] <- NA
        }
      }
      
      return(list(
        iteration = b,
        cop_fit = cop_fit,
        params = params_list,
        taus = taus_list,
        best_family = cop_fit$best_family,
        success = TRUE
      ))
      
    }, error = function(e) {
      return(list(
        iteration = b,
        cop_fit = NULL,
        params = NULL,
        taus = NULL,
        best_family = NA,
        success = FALSE,
        error = e$message
      ))
    })
  }
  
  # Run bootstrap iterations (parallel or sequential)
  if (use_parallel) {
    # Parallel execution with progress updates
    boot_list <- mclapply(1:n_bootstrap, bootstrap_worker, mc.cores = n_cores)
  } else {
    # Sequential execution with progress updates
    boot_list <- vector("list", n_bootstrap)
    for (b in 1:n_bootstrap) {
      if (b %% 10 == 0 || b == 1) cat("  Bootstrap iteration", b, "/", n_bootstrap, "\n")
      boot_list[[b]] <- bootstrap_worker(b)
    }
  }
  
  # Compile results
  bootstrap_results <- vector("list", n_bootstrap)
  params <- matrix(NA, nrow = n_bootstrap, ncol = length(copula_families))
  colnames(params) <- copula_families
  taus <- matrix(NA, nrow = n_bootstrap, ncol = length(copula_families))
  colnames(taus) <- copula_families
  best_families <- character(n_bootstrap)
  
  n_success <- 0
  for (b in 1:n_bootstrap) {
    if (boot_list[[b]]$success) {
      n_success <- n_success + 1
      bootstrap_results[[b]] <- boot_list[[b]]$cop_fit
      best_families[b] <- boot_list[[b]]$best_family
      
      for (fam in copula_families) {
        params[b, fam] <- boot_list[[b]]$params[[fam]]
        taus[b, fam] <- boot_list[[b]]$taus[[fam]]
      }
    } else {
      warning(paste("Bootstrap iteration", b, "failed:", boot_list[[b]]$error))
    }
  }
  
  cat("\nBootstrap copula estimation complete!\n")
  cat("  Successful iterations:", n_success, "of", n_bootstrap, "\n\n")
  
  return(list(
    bootstrap_results = bootstrap_results,
    parameters = params,
    kendall_taus = taus,
    best_families = best_families,
    n_success = n_success,
    config = list(
      n_sample_prior = n_sample_prior,
      n_sample_current = n_sample_current,
      n_bootstrap = n_bootstrap,
      sampling_method = sampling_method,
      copula_families = copula_families,
      with_replacement = with_replacement,
      use_parallel = use_parallel,
      n_cores = if (use_parallel) n_cores else NA
    )
  ))
}


#' Summarize Bootstrap Copula Results
#' 
#' Calculate summary statistics from bootstrap copula estimations
#' 
#' @param bootstrap_results Output from bootstrap_copula_estimation()
#' @param true_copula Optional true copula fit for comparison
#' 
#' @return data.table with summary statistics
summarize_bootstrap_copulas <- function(bootstrap_results, true_copula = NULL) {
  
  require(data.table)
  
  # Summary for each copula family
  families <- colnames(bootstrap_results$kendall_taus)
  
  summary_list <- list()
  
  for (fam in families) {
    
    taus <- bootstrap_results$kendall_taus[, fam]
    taus <- taus[!is.na(taus)]
    
    if (length(taus) > 0) {
      
      summary_list[[fam]] <- data.table(
        family = fam,
        n_successful = length(taus),
        tau_mean = mean(taus),
        tau_sd = sd(taus),
        tau_median = median(taus),
        tau_q05 = quantile(taus, 0.05),
        tau_q95 = quantile(taus, 0.95),
        ci_width = quantile(taus, 0.95) - quantile(taus, 0.05)
      )
      
      if (!is.null(true_copula) && !is.null(true_copula$results[[fam]])) {
        summary_list[[fam]]$tau_true <- true_copula$results[[fam]]$kendall_tau
        summary_list[[fam]]$tau_bias <- summary_list[[fam]]$tau_mean - 
                                        true_copula$results[[fam]]$kendall_tau
      }
    }
  }
  
  summary_dt <- rbindlist(summary_list)
  
  # Add model selection frequency
  best_family_counts <- table(bootstrap_results$best_families)
  summary_dt[, selection_freq := as.numeric(best_family_counts[family]) / 
                                  bootstrap_results$config$n_bootstrap]
  
  return(summary_dt)
}
