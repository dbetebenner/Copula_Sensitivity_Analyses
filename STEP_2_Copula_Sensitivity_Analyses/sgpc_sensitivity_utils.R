############################################################################
### SGPc Sensitivity Utilities
### Computes sensitivity of SGPc to copula mis-specification.
############################################################################

require(data.table)
require(copula)

# Load canonical copula parameters (Step 1 output).
load_canonical_copulas <- function(file_path) {
  if (!file.exists(file_path)) {
    warning("Canonical copula file not found: ", file_path)
    return(NULL)
  }
  data.table::fread(file_path)
}

# Build canonical copula for a given year span and content area.
get_canonical_copula <- function(canonical_params, year_span, content_area) {
  if (is.null(canonical_params) || nrow(canonical_params) == 0) {
    return(NULL)
  }

  # Use local variables to avoid column name conflicts in data.table filtering
  span_val <- year_span
  content_val <- toupper(content_area)
  
  # Filter using get() or explicit column reference to avoid .. scoping issues
  row <- canonical_params[canonical_params$year_span == span_val & 
                         toupper(canonical_params$content_area) == content_val]
  if (nrow(row) == 0) {
    return(NULL)
  }

  family <- tolower(row$best_family[1])
  tau_med <- row$tau_median[1]

  if (family == "t") {
    rho <- row$rho_median[1]
    df <- round(row$df_median[1])
    return(tCopula(param = rho, df = df, df.fixed = TRUE))
  }

  if (family == "gaussian") {
    rho <- row$rho_median[1]
    return(normalCopula(param = rho, dim = 2))
  }

  if (family %in% c("clayton", "gumbel", "frank")) {
    cop <- switch(family,
      clayton = claytonCopula(dim = 2),
      gumbel = gumbelCopula(dim = 2),
      frank = frankCopula(dim = 2)
    )
    theta <- copula::iTau(cop, tau_med)
    cop@parameters <- theta
    return(cop)
  }

  return(NULL)
}

# Compute summary metrics comparing baseline vs alternative SGPc vectors.
.compute_sgpc_metrics <- function(sgpc_base, sgpc_alt) {
  ok <- !is.na(sgpc_base) & !is.na(sgpc_alt)
  if (!any(ok)) {
    return(data.table(
      n_total = 0L,
      n_tail = 0L,
      mean_abs_delta = NA_real_,
      median_abs_delta = NA_real_,
      rmse = NA_real_,
      p90_abs_delta = NA_real_,
      spearman = NA_real_,
      pearson = NA_real_,
      tail_mean_abs_delta = NA_real_,
      tail_rmse = NA_real_,
      tail_p90_abs_delta = NA_real_
    ))
  }

  base <- sgpc_base[ok]
  alt <- sgpc_alt[ok]
  delta <- alt - base
  abs_delta <- abs(delta)

  tail_mask <- base <= 10 | base >= 90
  tail_abs_delta <- abs_delta[tail_mask]

  data.table(
    n_total = length(base),
    n_tail = sum(tail_mask),
    mean_abs_delta = mean(abs_delta),
    median_abs_delta = median(abs_delta),
    rmse = sqrt(mean(delta^2)),
    p90_abs_delta = as.numeric(quantile(abs_delta, 0.9, names = FALSE)),
    spearman = suppressWarnings(cor(base, alt, method = "spearman")),
    pearson = suppressWarnings(cor(base, alt, method = "pearson")),
    tail_mean_abs_delta = if (length(tail_abs_delta) > 0) mean(tail_abs_delta) else NA_real_,
    tail_rmse = if (length(tail_abs_delta) > 0) sqrt(mean((alt[tail_mask] - base[tail_mask])^2)) else NA_real_,
    tail_p90_abs_delta = if (length(tail_abs_delta) > 0) {
      as.numeric(quantile(tail_abs_delta, 0.9, names = FALSE))
    } else {
      NA_real_
    }
  )
}

# Main SGPc sensitivity calculator.
compute_sgpc_sensitivity <- function(pseudo_obs,
                                     fitted_results,
                                     baseline_family = "t",
                                     include_empirical = TRUE,
                                     extra_copulas = NULL,
                                     grid_size = 200) {
  if (is.null(pseudo_obs) || nrow(pseudo_obs) == 0) {
    return(data.table())
  }

  if (is.null(fitted_results) || length(fitted_results) == 0) {
    return(data.table())
  }

  families <- names(fitted_results)
  if (!baseline_family %in% families) {
    baseline_family <- families[1]
  }

  u <- pseudo_obs[, 1]
  v <- pseudo_obs[, 2]

  baseline_copula <- if (baseline_family == "comonotonic") {
    "comonotonic"
  } else {
    fitted_results[[baseline_family]]$copula
  }

  sgpc_base <- sgpc_engine(u, v, baseline_copula,
                           scale = "percentile",
                           grid_size = grid_size)

  results <- list()

  for (fam in families) {
    cop <- if (fam == "comonotonic") {
      "comonotonic"
    } else {
      fitted_results[[fam]]$copula
    }

    sgpc_alt <- sgpc_engine(u, v, cop,
                            scale = "percentile",
                            grid_size = grid_size)

    metrics <- .compute_sgpc_metrics(sgpc_base, sgpc_alt)
    metrics[, `:=`(
      baseline_family = baseline_family,
      comparison_family = fam
    )]

    results[[fam]] <- metrics
  }

  if (isTRUE(include_empirical)) {
    if (!exists("fit_empirical_copulas")) {
      warning("fit_empirical_copulas function not found. Skipping empirical copula comparison.")
      warning("Make sure functions/copula_bootstrap.R is sourced properly.")
    } else {
      tryCatch({
        empirical <- fit_empirical_copulas(pseudo_obs, methods = c("raw", "bernstein"))
        for (emp_name in names(empirical)) {
          sgpc_alt <- sgpc_engine(u, v, empirical[[emp_name]],
                                  scale = "percentile",
                                  grid_size = grid_size)
          metrics <- .compute_sgpc_metrics(sgpc_base, sgpc_alt)
          metrics[, `:=`(
            baseline_family = baseline_family,
            comparison_family = paste0("empirical_", emp_name)
          )]
          results[[paste0("empirical_", emp_name)]] <- metrics
        }
      }, error = function(e) {
        warning("Error fitting empirical copulas: ", e$message)
      })
    }
  }

  if (!is.null(extra_copulas) && length(extra_copulas) > 0) {
    for (name in names(extra_copulas)) {
      cop <- extra_copulas[[name]]
      if (is.null(cop)) {
        next
      }
      sgpc_alt <- sgpc_engine(u, v, cop,
                              scale = "percentile",
                              grid_size = grid_size)
      metrics <- .compute_sgpc_metrics(sgpc_base, sgpc_alt)
      metrics[, `:=`(
        baseline_family = baseline_family,
        comparison_family = name
      )]
      results[[name]] <- metrics
    }
  }

  rbindlist(results, fill = TRUE)
}
