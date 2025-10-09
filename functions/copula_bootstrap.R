############################################################################
### Copula Bootstrap and Estimation Functions
############################################################################

require(copula)
require(data.table)

#' Fit Copula to Longitudinal Pairs
#' 
#' Estimate copula from prior-current score pairs
#' 
#' @param scores_prior Vector of prior scale scores
#' @param scores_current Vector of current scale scores
#' @param framework_prior I-spline framework for prior scores (can be NULL if use_empirical_ranks=TRUE)
#' @param framework_current I-spline framework for current scores (can be NULL if use_empirical_ranks=TRUE)
#' @param copula_families Vector of copula families to fit ("gaussian", "t", "clayton", "gumbel", "frank")
#' @param return_best If TRUE, return only best-fitting copula; if FALSE, return all
#' @param use_empirical_ranks If TRUE, use empirical ranks for pseudo-observations (Phase 1).
#'                            If FALSE, use framework transformations (Phase 2+, requires invertibility)
#' 
#' @return List containing fitted copulas, parameters, and diagnostics
#' 
#' @details 
#' Two-stage transformation approach:
#' - Phase 1 (family selection): use_empirical_ranks=TRUE ensures uniform U,V without distortion
#' - Phase 2+ (applications): use_empirical_ranks=FALSE provides invertible transformations
#' 
#' Empirical ranks are preferred for copula family selection (Genest et al., 2009) as they:
#' - Guarantee uniform marginals
#' - Preserve rank-based dependence measures (Kendall's tau, Spearman's rho)
#' - Make no assumptions about marginal distributions
#' - Avoid distortion from insufficient smoothing
fit_copula_from_pairs <- function(scores_prior,
                                  scores_current,
                                  framework_prior,
                                  framework_current,
                                  copula_families = c("gaussian", "t", "clayton", "gumbel", "frank"),
                                  return_best = TRUE,
                                  use_empirical_ranks = FALSE) {
  
  # Transform to pseudo-observations
  if (use_empirical_ranks) {
    # Phase 1: Use empirical ranks for copula family selection
    # This ensures uniform marginals and preserves tail dependence structure
    U <- rank(scores_prior) / (length(scores_prior) + 1)
    V <- rank(scores_current) / (length(scores_current) + 1)
    
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
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        
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
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        
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
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        
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
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        
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
        fit <- fitCopula(cop, pseudo_obs, method = "ml")
        
        # Extract parameters: correlation and degrees of freedom
        rho <- fit@estimate[1]  # correlation parameter
        df <- fit@estimate[2]   # degrees of freedom
        
        # Calculate tail dependence
        tail_dep <- tryCatch({
          lambda_vals <- lambda(fit@copula)
          c(lower = lambda_vals["lower"], upper = lambda_vals["upper"])
        }, error = function(e) {
          c(lower = NA, upper = NA)
        })
        
        results[[family]] <- list(
          copula = fit@copula,
          parameter = rho,
          df = df,
          loglik = fit@loglik,
          aic = -2 * fit@loglik + 2 * length(fit@estimate),
          bic = -2 * fit@loglik + log(nrow(pseudo_obs)) * length(fit@estimate),
          kendall_tau = tau(fit@copula),
          tail_dependence_lower = tail_dep["lower"],
          tail_dependence_upper = tail_dep["upper"],
          family = "t"
        )
      }
      
    }, error = function(e) {
      warning(paste("Failed to fit", family, "copula:", e$message))
      results[[family]] <<- NULL
    })
  }
  
  # Add empirical Kendall's tau
  empirical_tau <- cor(U, V, method = "kendall")
  
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
      n_pairs = nrow(pseudo_obs)
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
#' @param copula_families Copula families to fit
#' @param with_replacement TRUE for standard bootstrap
#' @param use_empirical_ranks Use empirical ranks for transformation (default FALSE for Phase 2)
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
                                       use_empirical_ranks = FALSE) {
  
  require(data.table)
  
  # Storage for bootstrap results
  bootstrap_results <- vector("list", n_bootstrap)
  
  # Storage for summary statistics
  params <- matrix(NA, nrow = n_bootstrap, ncol = length(copula_families))
  colnames(params) <- copula_families
  taus <- matrix(NA, nrow = n_bootstrap, ncol = length(copula_families))
  colnames(taus) <- copula_families
  best_families <- character(n_bootstrap)
  
  cat("Running", n_bootstrap, "bootstrap copula estimations...\n")
  cat("  Sampling method:", sampling_method, "\n")
  cat("  Sample sizes: n_prior =", n_sample_prior, ", n_current =", n_sample_current, "\n\n")
  
  for (b in 1:n_bootstrap) {
    
    if (b %% 10 == 0) cat("  Bootstrap iteration", b, "/", n_bootstrap, "\n")
    
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
        use_empirical_ranks = use_empirical_ranks  # Pass through transformation method
      )
      
      bootstrap_results[[b]] <- cop_fit
      
      # Extract parameters for each family
      for (fam in copula_families) {
        if (!is.null(cop_fit$results[[fam]])) {
          params[b, fam] <- cop_fit$results[[fam]]$parameter
          taus[b, fam] <- cop_fit$results[[fam]]$kendall_tau
        }
      }
      
      best_families[b] <- cop_fit$best_family
      
    }, error = function(e) {
      warning(paste("Bootstrap iteration", b, "failed:", e$message))
    })
  }
  
  cat("\nBootstrap copula estimation complete!\n\n")
  
  return(list(
    bootstrap_results = bootstrap_results,
    parameters = params,
    kendall_taus = taus,
    best_families = best_families,
    config = list(
      n_sample_prior = n_sample_prior,
      n_sample_current = n_sample_current,
      n_bootstrap = n_bootstrap,
      sampling_method = sampling_method,
      copula_families = copula_families,
      with_replacement = with_replacement
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
