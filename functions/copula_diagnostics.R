############################################################################
### Copula Diagnostics and Visualization Functions
############################################################################

require(copula)
require(grid)
require(data.table)

#' Calculate Copula Dependence Measures
#' 
#' Compute various dependence measures from fitted copula
#' 
#' @param copula_fit Fitted copula object
#' @param pseudo_obs Matrix of pseudo-observations (optional, for empirical measures)
#' 
#' @return List of dependence measures
calculate_dependence_measures <- function(copula_fit, pseudo_obs = NULL) {
  
  measures <- list()
  
  # Kendall's tau
  measures$kendall_tau <- tau(copula_fit$copula)
  
  # Spearman's rho
  measures$spearman_rho <- rho(copula_fit$copula)
  
  # Tail dependence (if supported by copula family)
  tryCatch({
    measures$lambda_lower <- lambda(copula_fit$copula)["lower"]
    measures$lambda_upper <- lambda(copula_fit$copula)["upper"]
  }, error = function(e) {
    measures$lambda_lower <<- NA
    measures$lambda_upper <<- NA
  })
  
  # Empirical measures from pseudo-observations if provided
  if (!is.null(pseudo_obs)) {
    measures$empirical_kendall <- cor(pseudo_obs[,1], pseudo_obs[,2], method = "kendall")
    measures$empirical_spearman <- cor(pseudo_obs[,1], pseudo_obs[,2], method = "spearman")
    measures$empirical_pearson <- cor(pseudo_obs[,1], pseudo_obs[,2], method = "pearson")
  }
  
  return(measures)
}


#' Plot Copula Contours
#' 
#' Create contour plot of copula density
#' 
#' @param copula_fit Fitted copula object
#' @param main Plot title
#' @param filename PDF filename (if NULL, plots to current device)
plot_copula_contours <- function(copula_fit, main = "Copula Density", filename = NULL) {
  
  if (!is.null(filename)) {
    pdf(filename, width = 6, height = 6)
  }
  
  # Create grid of u,v values
  u <- v <- seq(0.01, 0.99, length.out = 50)
  grid <- expand.grid(u = u, v = v)
  
  # Calculate copula density
  dens <- dCopula(as.matrix(grid), copula_fit$copula)
  
  # Reshape for contour plot
  dens_matrix <- matrix(dens, nrow = length(u), ncol = length(v))
  
  # Plot
  contour(u, v, dens_matrix, 
          main = main,
          xlab = "U (Prior Percentile)",
          ylab = "V (Current Percentile)",
          col = "blue",
          lwd = 1.5)
  
  # Add independence line
  abline(0, 1, col = "red", lty = 2, lwd = 1)
  
  if (!is.null(filename)) {
    dev.off()
  }
}


#' Plot Bootstrap Parameter Distribution
#' 
#' Visualize bootstrap distribution of copula parameters
#' 
#' @param bootstrap_results Output from bootstrap_copula_estimation()
#' @param true_value True parameter value (optional)
#' @param family Copula family to plot ("gaussian", "clayton", etc.)
#' @param measure "parameter" or "tau"
#' @param filename PDF filename
plot_bootstrap_distribution <- function(bootstrap_results,
                                       true_value = NULL,
                                       family = "gaussian",
                                       measure = "tau",
                                       filename = NULL) {
  
  if (!is.null(filename)) {
    pdf(filename, width = 8, height = 6)
  }
  
  # Extract values
  if (measure == "tau") {
    values <- bootstrap_results$kendall_taus[, family]
    xlab <- bquote("Kendall's" ~ tau ~ "(" * .(family) * ")")
  } else {
    values <- bootstrap_results$parameters[, family]
    xlab <- paste("Parameter (", family, ")", sep="")
  }
  
  values <- values[!is.na(values)]
  
  # Create histogram
  hist(values,
       breaks = 30,
       col = "lightblue",
       border = "white",
       main = paste("Bootstrap Distribution:", family, "copula"),
       xlab = xlab,
       ylab = "Frequency")
  
  # Add mean line
  abline(v = mean(values), col = "blue", lwd = 2, lty = 1)
  
  # Add median line
  abline(v = median(values), col = "darkblue", lwd = 2, lty = 2)
  
  # Add true value if provided
  if (!is.null(true_value)) {
    abline(v = true_value, col = "red", lwd = 2, lty = 1)
  }
  
  # Add 90% CI
  q05 <- quantile(values, 0.05)
  q95 <- quantile(values, 0.95)
  abline(v = c(q05, q95), col = "darkgreen", lwd = 1.5, lty = 3)
  
  # Add legend
  legend_items <- c("Mean", "Median", "90% CI")
  legend_cols <- c("blue", "darkblue", "darkgreen")
  legend_lty <- c(1, 2, 3)
  
  if (!is.null(true_value)) {
    legend_items <- c(legend_items, "True Value")
    legend_cols <- c(legend_cols, "red")
    legend_lty <- c(legend_lty, 1)
  }
  
  legend("topright",
         legend = legend_items,
         col = legend_cols,
         lty = legend_lty,
         lwd = 2,
         bg = "white")
  
  if (!is.null(filename)) {
    dev.off()
  }
}


#' Plot Parameter Stability by Sample Size
#' 
#' Show how copula parameter estimates stabilize with increasing sample size
#' 
#' @param results_by_size List of bootstrap_results for different sample sizes
#' @param sample_sizes Vector of sample sizes
#' @param true_value True parameter value
#' @param family Copula family
#' @param filename PDF filename
plot_parameter_stability <- function(results_by_size,
                                    sample_sizes,
                                    true_value = NULL,
                                    family = "gaussian",
                                    filename = NULL) {
  
  if (!is.null(filename)) {
    pdf(filename, width = 10, height = 6)
  }
  
  # Extract median, 5th, and 95th percentiles for each sample size
  medians <- numeric(length(sample_sizes))
  q05 <- numeric(length(sample_sizes))
  q95 <- numeric(length(sample_sizes))
  
  for (i in seq_along(sample_sizes)) {
    taus <- results_by_size[[i]]$kendall_taus[, family]
    taus <- taus[!is.na(taus)]
    
    medians[i] <- median(taus)
    q05[i] <- quantile(taus, 0.05)
    q95[i] <- quantile(taus, 0.95)
  }
  
  # Set up plot
  plot(sample_sizes, medians,
       type = "b",
       pch = 19,
       col = "blue",
       lwd = 2,
       ylim = range(c(q05, q95, true_value), na.rm = TRUE),
       xlab = "Sample Size",
       ylab = expression("Kendall's" ~ tau),
       main = paste("Parameter Stability:", family, "copula"),
       log = "x")
  
  # Add confidence bands
  polygon(c(sample_sizes, rev(sample_sizes)),
          c(q05, rev(q95)),
          col = rgb(0, 0, 1, 0.2),
          border = NA)
  
  # Add true value line
  if (!is.null(true_value)) {
    abline(h = true_value, col = "red", lwd = 2, lty = 2)
  }
  
  # Add grid
  grid()
  
  # Add legend
  legend_items <- c("Median", "90% CI")
  legend_cols <- c("blue", rgb(0, 0, 1, 0.5))
  legend_pch <- c(19, 15)
  
  if (!is.null(true_value)) {
    legend_items <- c(legend_items, "True Value")
    legend_cols <- c(legend_cols, "red")
    legend_pch <- c(legend_pch, NA)
  }
  
  legend("topright",
         legend = legend_items,
         col = legend_cols,
         pch = legend_pch,
         lty = c(1, NA, if(!is.null(true_value)) 2),
         lwd = 2,
         bg = "white")
  
  if (!is.null(filename)) {
    dev.off()
  }
}


#' Create Comprehensive Copula Sensitivity Report
#' 
#' Generate summary table and plots for copula sensitivity analysis
#' 
#' @param bootstrap_results Bootstrap results
#' @param true_copula True copula fit
#' @param output_prefix Prefix for output files
create_sensitivity_report <- function(bootstrap_results,
                                     true_copula,
                                     output_prefix = "copula_sensitivity") {
  
  require(data.table)
  
  # Create summary table
  summary_dt <- summarize_bootstrap_copulas(bootstrap_results, true_copula)
  
  # Save summary table
  fwrite(summary_dt, 
         file = paste0(output_prefix, "_summary.csv"))
  
  cat("Copula Sensitivity Summary:\n")
  print(summary_dt)
  cat("\n")
  
  # Plot distributions for each family
  for (fam in colnames(bootstrap_results$kendall_taus)) {
    if (sum(!is.na(bootstrap_results$kendall_taus[, fam])) > 0) {
      
      true_tau <- if (!is.null(true_copula$results[[fam]])) {
        true_copula$results[[fam]]$kendall_tau
      } else {
        NULL
      }
      
      plot_bootstrap_distribution(
        bootstrap_results = bootstrap_results,
        true_value = true_tau,
        family = fam,
        measure = "tau",
        filename = paste0(output_prefix, "_", fam, "_distribution.pdf")
      )
    }
  }
  
  cat("Report generated with prefix:", output_prefix, "\n")
  cat("Files created:\n")
  cat("  -", paste0(output_prefix, "_summary.csv"), "\n")
  cat("  - Distribution plots for each copula family\n\n")
  
  return(summary_dt)
}
