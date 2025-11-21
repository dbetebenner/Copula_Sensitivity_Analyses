############################################################################
### Copula Contour Plot Visualization Functions
############################################################################
### Purpose: Generate high-quality contour plots comparing empirical and
### parametric copulas for visualization of copula fit quality
############################################################################

require(ggplot2)
require(data.table)
require(copula)
require(viridis)
require(gridExtra)
require(scales)

# Load wesanderson for color palettes
if (requireNamespace("wesanderson", quietly = TRUE)) {
  require(wesanderson)
}

# Load ggdensity if available for enhanced density plots
if (requireNamespace("ggdensity", quietly = TRUE)) {
  require(ggdensity)
}

# Source multi-format export utility
tryCatch({
  # Try common locations for export_plot_utils.R
  possible_paths <- c(
    "functions/export_plot_utils.R",  # From project root
    "export_plot_utils.R",            # Same directory
    "../export_plot_utils.R"          # Parent directory
  )
  sourced <- FALSE
  for (path in possible_paths) {
    if (file.exists(path)) {
      source(path, local = FALSE)
      sourced <- TRUE
      break
    }
  }
  if (!sourced) {
    warning("Could not load export_plot_utils.R - falling back to PDF-only exports")
  }
}, error = function(e) {
  warning("Could not load export_plot_utils.R - falling back to PDF-only exports")
})

#' Calculate empirical copula values on a grid
#' 
#' @param pseudo_obs Matrix of pseudo-observations (n x 2)
#' @param grid_size Number of grid points in each dimension (default 300)
#' @param method Either "ecdf" (empirical CDF) or "density" (kernel density)
#' 
#' @return List with u_grid, v_grid, and copula_values matrices
calculate_empirical_copula_grid <- function(pseudo_obs, grid_size = 300, method = "ecdf") {
  
  u_seq <- seq(0.01, 0.99, length.out = grid_size)
  v_seq <- seq(0.01, 0.99, length.out = grid_size)
  
  # Create grid
  grid <- expand.grid(u = u_seq, v = v_seq)
  
  if (method == "ecdf") {
    # Calculate empirical copula C_n(u,v) = proportion of obs <= (u,v)
    n <- nrow(pseudo_obs)
    U <- pseudo_obs[, 1]
    V <- pseudo_obs[, 2]
    
    copula_values <- sapply(1:nrow(grid), function(i) {
      sum(U <= grid$u[i] & V <= grid$v[i]) / n
    })
    
  } else if (method == "density") {
    # Use bivariate kernel density estimation for copula density
    require(ks)
    
    # Kernel density estimation
    H <- Hpi(pseudo_obs)  # Plug-in bandwidth selector
    kde_result <- kde(pseudo_obs, H = H, eval.points = as.matrix(grid))
    copula_values <- kde_result$estimate
    
    # Clamp negative values to zero (KDE can produce slightly negative values at boundaries)
    copula_values <- pmax(copula_values, 0)
    
    # Normalize to ensure it's a proper density
    copula_values <- copula_values / sum(copula_values) * grid_size^2
  }
  
  # Reshape to matrix
  copula_matrix <- matrix(copula_values, nrow = grid_size, ncol = grid_size)
  
  return(list(
    u_grid = matrix(grid$u, nrow = grid_size, ncol = grid_size),
    v_grid = matrix(grid$v, nrow = grid_size, ncol = grid_size),
    copula_values = copula_matrix,
    method = method
  ))
}

#' Calculate bootstrap uncertainty for parametric copula on a grid
#' 
#' @param bootstrap_results Bootstrap results from bootstrap_copula_estimation()
#' @param family Copula family name
#' @param grid_size Number of grid points in each dimension (default 300)
#' @param method Either "cdf" or "density"
#' 
#' @return List with point estimate, uncertainty metrics, and confidence bounds
calculate_bootstrap_uncertainty <- function(bootstrap_results, 
                                           family, 
                                           grid_size = 300,
                                           method = "cdf") {
  
  if (is.null(bootstrap_results) || is.null(bootstrap_results$bootstrap_results)) {
    warning("No bootstrap results available for uncertainty calculation")
    return(NULL)
  }
  
  # Extract bootstrap fits for this family
  # Structure: bootstrap_results$bootstrap_results[[b]]$results[[family]]
  boot_fits <- lapply(bootstrap_results$bootstrap_results, function(x) {
    if (!is.null(x) && !is.null(x$results)) {
      x$results[[family]]
    } else {
      NULL
    }
  })
  boot_fits <- boot_fits[!sapply(boot_fits, is.null)]
  
  if (length(boot_fits) < 10) {
    warning(sprintf("Insufficient bootstrap samples (%d) for %s", 
                   length(boot_fits), family))
    return(NULL)
  }
  
  cat(sprintf("  Evaluating %d bootstrap samples on %dx%d grid...\n", 
              length(boot_fits), grid_size, grid_size))
  
  # Create evaluation grid
  u_seq <- seq(0.01, 0.99, length.out = grid_size)
  v_seq <- seq(0.01, 0.99, length.out = grid_size)
  grid <- expand.grid(u = u_seq, v = v_seq)
  grid_matrix <- as.matrix(grid)
  
  # Evaluate all bootstrap copulas on grid
  n_boot <- length(boot_fits)
  boot_values <- matrix(NA, nrow = nrow(grid), ncol = n_boot)
  
  for (b in 1:n_boot) {
    if (b %% 50 == 0) cat(sprintf("    Bootstrap %d/%d...\n", b, n_boot))
    
    copula_obj <- boot_fits[[b]]$copula
    
    if (method == "cdf") {
      # Evaluate CDF
      boot_values[, b] <- pCopula(grid_matrix, copula_obj)
    } else {
      # Evaluate density
      boot_values[, b] <- dCopula(grid_matrix, copula_obj)
    }
  }
  
  # Calculate pointwise statistics
  point_estimate <- rowMeans(boot_values, na.rm = TRUE)
  uncertainty_sd <- apply(boot_values, 1, sd, na.rm = TRUE)
  lower_bound <- apply(boot_values, 1, quantile, probs = 0.05, na.rm = TRUE)
  upper_bound <- apply(boot_values, 1, quantile, probs = 0.95, na.rm = TRUE)
  
  # Reshape to matrices
  point_matrix <- matrix(point_estimate, nrow = grid_size, ncol = grid_size)
  sd_matrix <- matrix(uncertainty_sd, nrow = grid_size, ncol = grid_size)
  lower_matrix <- matrix(lower_bound, nrow = grid_size, ncol = grid_size)
  upper_matrix <- matrix(upper_bound, nrow = grid_size, ncol = grid_size)
  
  # Create uncertainty density field for gradient visualization
  # Normalize SD to [0, 1] range
  sd_normalized <- sd_matrix / max(sd_matrix, na.rm = TRUE)
  
  # Create gradient: higher uncertainty → higher opacity
  # Use inverse: we want high uncertainty to be MORE visible (darker)
  uncertainty_density <- sd_normalized
  
  cat(sprintf("  Uncertainty range: %.4f to %.4f\n", 
              min(uncertainty_sd, na.rm = TRUE), 
              max(uncertainty_sd, na.rm = TRUE)))
  
  return(list(
    u_grid = matrix(grid$u, nrow = grid_size, ncol = grid_size),
    v_grid = matrix(grid$v, nrow = grid_size, ncol = grid_size),
    point_estimate = point_matrix,
    uncertainty_sd = sd_matrix,
    uncertainty_density = uncertainty_density,
    lower_bound = lower_matrix,
    upper_bound = upper_matrix,
    n_bootstrap = n_boot,
    method = method
  ))
}

#' Plot empirical copula contours
#' 
#' @param empirical_grid Output from calculate_empirical_copula_grid
#' @param title Plot title
#' @param n_contours Number of contour lines to draw
#' 
#' @return ggplot object
plot_empirical_copula_contour <- function(empirical_grid, 
                                         title = "Empirical Copula",
                                         subtitle = NULL,
                                         x_label = expression(u[prior]),
                                         y_label = expression(v[current]),
                                         n_contours = 15) {
  
  # Convert to data.table for ggplot
  plot_data <- data.table(
    u = as.vector(empirical_grid$u_grid),
    v = as.vector(empirical_grid$v_grid),
    value = as.vector(empirical_grid$copula_values)
  )
  
  # Determine if we're plotting density or CDF
  is_density <- (empirical_grid$method == "density")
  is_cdf <- (empirical_grid$method == "ecdf")
  
  # For CDF plots, use specific contour breaks: 0.1, 0.2, ..., 0.9
  # For PDF plots, use bins
  if (is_cdf) {
    contour_levels <- seq(0.1, 0.9, by = 0.1)
    fill_breaks <- seq(0, 1, by = 0.1)
    n_bins <- length(fill_breaks) - 1
    
    p <- ggplot(plot_data, aes(x = u, y = v, z = value)) +
      geom_contour_filled(breaks = fill_breaks, alpha = 0.7) +
      geom_contour(color = "black", alpha = 0.5, linewidth = 0.5, breaks = contour_levels)
  } else {
    p <- ggplot(plot_data, aes(x = u, y = v, z = value)) +
      geom_contour_filled(bins = n_contours, alpha = 0.7) +
      geom_contour(color = "black", alpha = 0.5, bins = n_contours)
    n_bins <- n_contours
  }
  
  # Use wesanderson palette if available, otherwise fall back to viridis
  legend_name <- ifelse(is_density, "Density", "C(u,v)")
  legend_guide <- ifelse(is_cdf, "none", "legend")
  
  if (requireNamespace("wesanderson", quietly = TRUE)) {
    p <- p + scale_fill_manual(
      values = colorRampPalette(wes_palette("Zissou1"))(n_bins),
      name = legend_name,
      guide = legend_guide
    )
  } else {
    p <- p + scale_fill_viridis_d(
      option = "plasma",
      name = legend_name,
      guide = legend_guide
    )
  }
  
  p <- p +
    coord_equal() +
    labs(
      title = title,
      subtitle = subtitle,
      x = x_label,
      y = y_label
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      plot.margin = margin(20, 4, 7, 4, "pt"),
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 10),
      legend.position = ifelse(is_cdf, "none", "right"),
      panel.grid.minor = element_blank()
    ) +
    scale_x_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
    scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1))
  
  # For CDF plots, add inline contour labels
  if (is_cdf) {
    # Calculate label positions along the diagonal
    # For empirical copula, approximate where contours cross the diagonal
    label_data <- data.frame()
    
    for (level in contour_levels) {
      # For empirical CDF on diagonal, approximate position
      # Search the data for points near diagonal where value ≈ level
      diag_subset <- plot_data[abs(plot_data$u - plot_data$v) < 0.02, ]
      
      if (nrow(diag_subset) > 0) {
        idx <- which.min(abs(diag_subset$value - level))
        u_pos <- diag_subset$u[idx]
      } else {
        # Fallback: assume independence copula behavior on diagonal
        u_pos <- level
      }
      
      label_data <- rbind(label_data, data.frame(
        level = level,
        u = u_pos - 0.02,  # Slightly left of diagonal
        v = u_pos - 0.02,
        label = as.character(level)
      ))
    }
    
    p <- p + 
      geom_text(data = label_data,
                aes(x = u, y = v, label = label),
                size = 3,
                angle = -45,
                color = "#141410",  # Dark grey-black for contrast
                fontface = "bold",
                hjust = 0.5,
                vjust = 0,
                inherit.aes = FALSE)
  }
  
  return(p)
}

#' Plot parametric copula contours
#' 
#' @param fitted_copula Fitted copula object or copula specification
#' @param family Copula family name
#' @param grid_size Number of grid points (default 300)
#' @param plot_type Either "cdf" or "density"
#' @param title Optional plot title
#' @param sample_size Optional sample size to include in title (formatted with commas)
#' 
#' @return ggplot object
plot_parametric_copula_contour <- function(fitted_copula, 
                                          family,
                                          grid_size = 300,
                                          plot_type = "density",
                                          title = NULL,
                                          sample_size = NULL,
                                          subtitle = NULL,
                                          x_label = expression(u[prior]),
                                          y_label = expression(v[current])) {
  
  u_seq <- seq(0.01, 0.99, length.out = grid_size)
  v_seq <- seq(0.01, 0.99, length.out = grid_size)
  grid <- expand.grid(u = u_seq, v = v_seq)
  
  # Handle comonotonic copula specially
  if (family == "comonotonic") {
    if (plot_type == "cdf") {
      # Comonotonic CDF: C(u,v) = min(u,v)
      copula_values <- pmin(grid$u, grid$v)
    } else {
      # Comonotonic has infinite density along u=v diagonal
      # Approximate with very high values near diagonal
      copula_values <- ifelse(abs(grid$u - grid$v) < 0.02, 10, 0.1)
    }
  } else {
    # Standard parametric copulas
    if (plot_type == "cdf") {
      # Evaluate copula CDF
      copula_values <- pCopula(as.matrix(grid), fitted_copula)
    } else {
      # Evaluate copula density
      copula_values <- dCopula(as.matrix(grid), fitted_copula)
    }
  }
  
  # Convert to data.table
  plot_data <- data.table(
    u = grid$u,
    v = grid$v,
    value = copula_values
  )
  
  # Default title if not provided
  if (is.null(title)) {
    title_family <- tools::toTitleCase(family)
    if (plot_type == "density") {
      title_suffix <- "(PDF)"
    } else {
      title_suffix <- ""  # CDF is implicit for copula
    }
    
    # Add sample size if provided
    if (!is.null(sample_size)) {
      n_formatted <- format(sample_size, big.mark = ",", scientific = FALSE)
      title <- sprintf("%s Copula %s (n = %s)", title_family, title_suffix, n_formatted)
    } else {
      title <- sprintf("%s Copula %s", title_family, title_suffix)
    }
    title <- trimws(title)  # Remove extra whitespace
  }
  
  # For CDF plots, use specific contour breaks: 0.1, 0.2, ..., 0.9
  # For PDF plots, use bins
  if (plot_type == "cdf") {
    contour_levels <- seq(0.1, 0.9, by = 0.1)
    fill_breaks <- seq(0, 1, by = 0.1)
    n_bins <- length(fill_breaks) - 1
    
    p <- ggplot(plot_data, aes(x = u, y = v, z = value)) +
      geom_contour_filled(breaks = fill_breaks, alpha = 0.7) +
      geom_contour(color = "black", alpha = 0.5, linewidth = 0.5, breaks = contour_levels)
  } else {
    p <- ggplot(plot_data, aes(x = u, y = v, z = value)) +
      geom_contour_filled(bins = 15, alpha = 0.7) +
      geom_contour(color = "black", alpha = 0.5, bins = 15)
    n_bins <- 15
  }
  
  # Use wesanderson palette if available, otherwise fall back to viridis
  legend_name <- ifelse(plot_type == "density", "Density", "C(u,v)")
  legend_guide <- ifelse(plot_type == "cdf", "none", "legend")
  
  if (requireNamespace("wesanderson", quietly = TRUE)) {
    p <- p + scale_fill_manual(
      values = colorRampPalette(wes_palette("Zissou1"))(n_bins),
      name = legend_name,
      guide = legend_guide
    )
  } else {
    p <- p + scale_fill_viridis_d(
      option = "plasma",
      name = legend_name,
      guide = legend_guide
    )
  }
  
  p <- p +
    coord_equal() +
    labs(
      title = title,
      subtitle = subtitle,
      x = x_label,
      y = y_label
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      plot.margin = margin(20, 4, 7, 4, "pt"),
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 10),
      legend.position = ifelse(plot_type == "cdf", "none", "right"),
      panel.grid.minor = element_blank()
    ) +
    scale_x_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
    scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1))
  
  # For CDF plots, add inline contour labels
  if (plot_type == "cdf") {
    # Calculate label positions by finding where contours cross the diagonal
    # For each contour level, find the point on the diagonal
    label_data <- data.frame()
    
    for (level in contour_levels) {
      # For the diagonal u = v, the copula value is approximately the level
      # Find the u value where C(u,u) ≈ level
      
      if (family == "comonotonic") {
        # For comonotonic: C(u,v) = min(u,v), so on diagonal C(u,u) = u
        u_pos <- level
      } else {
        # For other copulas, use fitted copula
        # Search along diagonal for where C(u,u) = level
        u_test <- seq(0.05, 0.95, by = 0.01)
        if (!is.null(fitted_copula)) {
          diag_values <- pCopula(cbind(u_test, u_test), fitted_copula)
          # Find closest to level
          idx <- which.min(abs(diag_values - level))
          u_pos <- u_test[idx]
        } else {
          u_pos <- level  # Fallback
        }
      }
      
      label_data <- rbind(label_data, data.frame(
        level = level,
        u = u_pos - 0.02,  # Slightly left of diagonal
        v = u_pos - 0.02,
        label = as.character(level)
      ))
    }
    
    p <- p + 
      geom_text(data = label_data,
                aes(x = u, y = v, label = label),
                size = 3,
                angle = -45,
                color = "#141410",  # Dark grey-black for contrast
                fontface = "bold",
                hjust = 0.5,
                vjust = 0,
                inherit.aes = FALSE)
  }
  
  return(p)
}

#' Plot parametric copula with bootstrap uncertainty ribbons
#' 
#' @param empirical_grid Empirical copula grid for overlay contours
#' @param uncertainty_results Output from calculate_bootstrap_uncertainty()
#' @param family Copula family name
#' @param title Plot title
#' @param plot_type "cdf" or "density"
#' @param n_gradient_levels Number of gradient levels for ribbon (default 10)
#' @param sample_size Sample size for title (optional)
#' 
#' @return ggplot object
plot_copula_with_uncertainty_ribbons <- function(empirical_grid,
                                                 uncertainty_results,
                                                 family,
                                                 title = NULL,
                                                 plot_type = "cdf",
                                                 n_gradient_levels = 10,
                                                 sample_size = NULL,
                                                 x_label = expression(u[prior]),
                                                 y_label = expression(v[current])) {
  
  if (is.null(uncertainty_results)) {
    warning("No uncertainty results provided, falling back to standard plot")
    return(plot_parametric_copula_contour(NULL, family, plot_type = plot_type, title = title))
  }
  
  # Prepare parametric point estimate data (for Zissou1 background)
  parametric_data <- data.table(
    u = as.vector(uncertainty_results$u_grid),
    v = as.vector(uncertainty_results$v_grid),
    value = as.vector(uncertainty_results$point_estimate)
  )
  
  # Prepare lower and upper bounds for ribbons
  lower_data <- data.table(
    u = as.vector(uncertainty_results$u_grid),
    v = as.vector(uncertainty_results$v_grid),
    value = as.vector(uncertainty_results$lower_bound)
  )
  
  upper_data <- data.table(
    u = as.vector(uncertainty_results$u_grid),
    v = as.vector(uncertainty_results$v_grid),
    value = as.vector(uncertainty_results$upper_bound)
  )
  
  # Prepare empirical data for overlay
  empirical_data <- data.table(
    u = as.vector(empirical_grid$u_grid),
    v = as.vector(empirical_grid$v_grid),
    value = as.vector(empirical_grid$copula_values)
  )
  
  # Default title - use bquote for consistent font rendering
  if (is.null(title)) {
    title_parts <- tools::toTitleCase(family)
    if (!is.null(sample_size)) {
      # Format sample size with commas
      n_formatted <- format(sample_size, big.mark = ",", scientific = FALSE)
      # Copula IS a CDF, no need to say "CDF" in title
      # Use bquote to match other plot titles
      title <- bquote(.(title_parts) ~ "Copula with Bootstrap Uncertainty" ~ 
                     "(n =" ~ .(n_formatted) * ")")
    } else {
      title <- bquote(.(title_parts) ~ "Copula with Bootstrap Uncertainty")
    }
  }
  
  # Build plot with layers
  p <- ggplot()
  
  # Define contour levels for lines: 0.1, 0.2, ..., 0.9 (9 levels)
  contour_levels <- seq(0.1, 0.9, by = 0.1)
  
  # Define breaks for filled regions: [0, 0.1], (0.1, 0.2], ..., (0.9, 1.0] (10 bins)
  fill_breaks <- seq(0, 1, by = 0.1)
  n_bins <- length(fill_breaks) - 1  # Number of bins = 10
  
  # Layer 1: Filled contours from PARAMETRIC point estimate (Zissou1 background)
  p <- p + 
    geom_contour_filled(data = parametric_data,
                       aes(x = u, y = v, z = value),
                       breaks = fill_breaks, alpha = 0.7)
  
  # Apply Zissou1 palette with 10 colors (no legend - use inline labels instead)
  if (requireNamespace("wesanderson", quietly = TRUE)) {
    p <- p + scale_fill_manual(
      values = colorRampPalette(wes_palette("Zissou1"))(n_bins),
      guide = "none"  # Remove legend - will use inline contour labels
    )
  } else {
    p <- p + scale_fill_viridis_d(
      option = "plasma",
      guide = "none"  # Remove legend - will use inline contour labels
    )
  }
  
  # Layer 2: Gradient ribbons around contours (grey)
  # Create multiple contour bands between lower and upper bounds with gradient alpha
  alpha_levels <- seq(0.20, 0.03, length.out = n_gradient_levels)
  
  for (i in 1:n_gradient_levels) {
    # Interpolate between lower and upper bounds
    fraction <- (i - 1) / (n_gradient_levels - 1)
    
    # Create intermediate bound
    interp_data <- data.table(
      u = parametric_data$u,
      v = parametric_data$v,
      value = lower_data$value + fraction * (upper_data$value - lower_data$value)
    )
    
    # Add contour band with decreasing alpha (darker near center)
    # Reverse alpha so center is darker
    alpha_val <- alpha_levels[n_gradient_levels - i + 1]
    
    p <- p +
      geom_contour(data = interp_data,
                  aes(x = u, y = v, z = value),
                  color = "grey30", 
                  alpha = alpha_val,
                  linewidth = 2.5,  # Thicker to create ribbon effect
                  breaks = contour_levels)
  }
  
  # Layer 3: Parametric point estimate contours (thin, dotted, black)
  p <- p +
    geom_contour(data = parametric_data,
                aes(x = u, y = v, z = value),
                color = "black", 
                linewidth = 0.5, 
                linetype = "solid",
                breaks = contour_levels)
  
  # Layer 4: Empirical contours (thin, solid, magenta)
  p <- p +
    geom_contour(data = empirical_data,
                aes(x = u, y = v, z = value),
                color = "magenta", 
                linewidth = 0.5,
                linetype = "solid",
                breaks = contour_levels)
  
  # Add inline contour labels along diagonal (replacing legend)
  # Calculate label positions by finding where contours cross the diagonal
  label_positions <- data.frame()
  
  for (level in contour_levels) {
    # Search along diagonal for where C(u,u) = level
    u_test <- seq(0.05, 0.95, by = 0.01)
    # Use parametric point estimate to find position
    param_grid <- parametric_data
    # Interpolate to find diagonal value
    # Simple approximation: find closest grid point to diagonal at this level
    diag_subset <- param_grid[abs(param_grid$u - param_grid$v) < 0.02, ]
    if (nrow(diag_subset) > 0) {
      idx <- which.min(abs(diag_subset$value - level))
      u_pos <- diag_subset$u[idx]
    } else {
      u_pos <- level  # Fallback
    }
    
    label_positions <- rbind(label_positions, data.frame(
      level = level,
      x = u_pos - 0.02,  # Slightly left of diagonal
      y = u_pos - 0.02,
      label = as.character(level)
    ))
  }
  
  p <- p + 
    geom_text(data = label_positions,
              aes(x = x, y = y, label = label),
              size = 3,
              angle = -45,  # Rotated to match diagonal
              color = "#141410",  # Dark grey-black for contrast
              fontface = "bold",
              hjust = 0.5,
              vjust = 0)
  
  # Formatting
  p <- p +
    coord_equal() +
    labs(
      title = title,
      subtitle = sprintf("N = %d bootstrap samples | Black = parametric | Grey bands = ± CI | Magenta = empirical",
                        uncertainty_results$n_bootstrap),
      x = x_label,
      y = y_label
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      plot.margin = margin(20, 4, 7, 4, "pt"),
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 10),
      legend.position = "none",  # No legend - using inline labels
      panel.grid.minor = element_blank()
    ) +
    scale_x_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
    scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1))
  
  return(p)
}

#' Create comparison plot between empirical and parametric copula
#' 
#' @param empirical_grid Output from calculate_empirical_copula_grid
#' @param fitted_copula Fitted copula object
#' @param family Copula family name
#' @param plot_type "side_by_side", "overlay", or "difference"
#' 
#' @return ggplot object or combined plot
plot_copula_comparison <- function(empirical_grid, 
                                  fitted_copula, 
                                  family,
                                  plot_type = "side_by_side",
                                  subtitle = NULL,
                                  x_label = expression(u[prior]),
                                  y_label = expression(v[current])) {
  
  grid_size <- nrow(empirical_grid$u_grid)
  
  if (plot_type == "difference") {
    # Calculate difference between empirical and parametric
    u_seq <- seq(0.01, 0.99, length.out = grid_size)
    v_seq <- seq(0.01, 0.99, length.out = grid_size)
    grid <- expand.grid(u = u_seq, v = v_seq)
    
    # Get parametric values
    if (family == "comonotonic") {
      if (empirical_grid$method == "density") {
        # Approximate comonotonic density
        parametric_values <- ifelse(abs(grid$u - grid$v) < 0.02, 10, 0.1)
      } else {
        parametric_values <- pmin(grid$u, grid$v)
      }
    } else {
      if (empirical_grid$method == "density") {
        parametric_values <- dCopula(as.matrix(grid), fitted_copula)
      } else {
        parametric_values <- pCopula(as.matrix(grid), fitted_copula)
      }
    }
    
    # Calculate difference
    diff_values <- as.vector(empirical_grid$copula_values) - parametric_values
    
    plot_data <- data.table(
      u = grid$u,
      v = grid$v,
      difference = diff_values
    )
    
    # Create diverging color scale centered at 0
    max_abs_diff <- max(abs(diff_values), na.rm = TRUE)
    
    # Use Zissou1-inspired diverging palette:
    # Zissou1 blue (#3B9AB2) -> off-white (#F5F5F5) -> Zissou1 red (#F21A00)
    zissou_blue <- "#3B9AB2"
    zissou_red <- "#F21A00"
    mid_color <- "#F7F7F5"  # Off-white
    
    # Create title as expression for consistent font rendering
    title_expr <- bquote("CDF Difference: Empirical -" ~ .(tools::toTitleCase(family)) ~ "Copula")
    
    p <- ggplot(plot_data, aes(x = u, y = v)) +
      geom_raster(aes(fill = difference), interpolate = TRUE) +
      geom_contour(aes(z = difference), color = "black", alpha = 0.3, bins = 15) +
      scale_fill_gradient2(
        low = zissou_blue, 
        mid = mid_color, 
        high = zissou_red,
        midpoint = 0,
        limits = c(-0.03, 0.03),  # ← Fixed range for all families
        name = "Difference\n(Emp - Par)"
      ) +
      coord_equal() +
      labs(
        title = title_expr,
        subtitle = subtitle,
        x = x_label,
        y = y_label
      ) +
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.margin = margin(20, 4, 7, 4, "pt"),
        plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = 10),
        legend.position = "right",
        panel.grid.minor = element_blank()
      ) +
      scale_x_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
      scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1))
    
    return(p)
    
  } else if (plot_type == "side_by_side") {
    # Create side-by-side plots
    p1 <- plot_empirical_copula_contour(empirical_grid, title = "Empirical Copula")
    
    plot_type_par <- ifelse(empirical_grid$method == "density", "density", "cdf")
    p2 <- plot_parametric_copula_contour(fitted_copula, family, 
                                        plot_type = plot_type_par,
                                        title = sprintf("%s Copula (Fitted)",
                                                      tools::toTitleCase(family)))
    
    # Combine plots
    combined <- grid.arrange(p1, p2, ncol = 2)
    return(combined)
    
  } else if (plot_type == "overlay") {
    # Overlay contours (more complex, requires careful handling)
    warning("Overlay plot type not yet implemented. Using side_by_side instead.")
    return(plot_copula_comparison(empirical_grid, fitted_copula, family, 
                                 plot_type = "side_by_side"))
  }
}

#' Plot bivariate density of original scores
#' 
#' @param scores_prior Vector of prior scale scores
#' @param scores_current Vector of current scale scores
#' @param title Plot title
#' @param subtitle Plot subtitle (optional)
#' @param n_bins Number of bins for 2D histogram
#' @param sample_size Sample size for title (optional)
#' 
#' @return ggplot object
plot_bivariate_density <- function(scores_prior, 
                                  scores_current,
                                  title = "Original Score Distribution",
                                  subtitle = NULL,
                                  x_label = "Prior Scale Score",
                                  y_label = "Latter Scale Score",
                                  n_bins = 60,
                                  sample_size = NULL) {
  
  plot_data <- data.table(
    prior = scores_prior,
    current = scores_current
  )
  
  # Create title as expression for consistent font rendering with other plots
  if (!is.null(sample_size)) {
    n_formatted <- format(sample_size, big.mark = ",", scientific = FALSE)
    title <- bquote(.(title) ~ "(n =" ~ .(n_formatted) * ")")
  }
  
  # Create 2D density plot
  p <- ggplot(plot_data, aes(x = prior, y = current)) +
    geom_bin2d(bins = n_bins) +
    geom_smooth(method = "lm", color = "red", se = FALSE, linetype = "dashed") +
    scale_fill_viridis_c(option = "viridis", alpha = 0.5, name = "Count") +
    labs(
      title = title,
      subtitle = subtitle,
      x = x_label,
      y = y_label
    ) +
    theme_minimal() +
    theme(
      plot.background = element_rect(fill = "transparent", color = NA),
      panel.background = element_rect(fill = "transparent", color = NA),
      plot.margin = margin(20, 4, 7, 4, "pt"),
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 10),
      legend.position = "right",
      panel.grid.minor = element_blank()
    )
  
  # Add correlation annotation
  corr_value <- cor(scores_prior, scores_current, use = "complete.obs")
  tau_value <- cor(scores_prior, scores_current, method = "kendall", use = "complete.obs")
  
  # Create labels with Greek tau using plotmath - build as character strings
  corr_str <- sprintf("%.3f", corr_value)
  tau_str <- sprintf("%.3f", tau_value)
  
  # Build plotmath expressions as character strings (not call objects)
  # These will be parsed by annotate() when parse=TRUE
  label_expr_r <- sprintf("\"Pearson \" * italic(r) * \" = %s\"", corr_str)
  label_expr_tau <- sprintf("\"Kendall's \" * tau * \" = %s\"", tau_str)
  
  # Add two separate text annotations
  p <- p + 
    annotate("text", x = min(scores_prior) + 15, y = max(scores_current) - 15,
            label = label_expr_r,
            hjust = 0, vjust = 1, size = 3.5, parse = TRUE) +
    annotate("text", x = min(scores_prior) + 15, y = max(scores_current) - 30,
            label = label_expr_tau,
            hjust = 0, vjust = 1, size = 3.5, parse = TRUE)
  
  return(p)
}

#' Create summary grid of all plots for a condition
#' 
#' @param plots List of individual plots
#' @param condition_info Information about the condition
#' @param layout Layout specification (e.g., "2x3", "3x3")
#' 
#' @return Combined grid plot
create_condition_summary_grid <- function(plots, 
                                         condition_info,
                                         layout = "2x3") {
  
  # Determine grid dimensions
  if (layout == "2x3") {
    ncol_grid <- 3
    nrow_grid <- 2
  } else if (layout == "3x3") {
    ncol_grid <- 3
    nrow_grid <- 3
  } else {
    ncol_grid <- 3
    nrow_grid <- ceiling(length(plots) / 3)
  }
  
  # Create title for the grid
  # Format content area with SGP::capwords if available
  content_formatted <- if (requireNamespace("SGP", quietly = TRUE)) {
    SGP::capwords(condition_info$content)
  } else {
    tools::toTitleCase(tolower(condition_info$content))
  }
  
  main_title <- sprintf("Copula Analysis: Data Set %s, Year %s->%s, Grade %d->%d, %s",
                       condition_info$dataset_number,
                       condition_info$year_prior,
                       condition_info$year_current,
                       condition_info$grade_prior,
                       condition_info$grade_current,
                       content_formatted)
  
  # Create grid with title using arrangeGrob (doesn't draw, just creates grob)
  grid_plot <- do.call(gridExtra::arrangeGrob, c(plots, 
                                                  ncol = ncol_grid,
                                                  top = main_title))
  
  return(grid_plot)
}

#' Master function to generate all plots for one condition
#' 
#' @param pseudo_obs Matrix of pseudo-observations
#' @param original_scores data.table with SCALE_SCORE_PRIOR and SCALE_SCORE_CURRENT
#' @param copula_results List of fitted copula results for all families
#' @param best_family Name of best-fitting family
#' @param output_dir Directory to save plots
#' @param condition_info Metadata about the condition
#' @param bootstrap_results Bootstrap results for uncertainty visualization (optional)
#' @param save_plots Whether to save plots to disk
#' @param grid_size Grid size for copula evaluation (default 300)
#' @param export_formats Character vector of formats: "pdf", "svg", "png". Default: all three
#' @param export_dpi Numeric. Base DPI for raster outputs. Default: 300
#' @param export_verbose Logical. Print export messages? Default: FALSE
#' 
#' @return List of generated plots
generate_condition_plots <- function(pseudo_obs,
                                   original_scores,
                                   copula_results,
                                   best_family,
                                   output_dir,
                                   condition_info,
                                   bootstrap_results = NULL,
                                   save_plots = TRUE,
                                   grid_size = 300,
                                   export_formats = c("pdf", "svg", "png"),
                                   export_dpi = 300,
                                   export_verbose = FALSE) {
  
  # Create output directory if needed
  if (save_plots && !dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Helper function to save ggplot in multiple formats
  # Falls back to PDF-only if export_ggplot_multi_format is not available
  save_ggplot_multi <- function(plot_obj, file_path, width = 6, height = 7) {
    if (exists("export_ggplot_multi_format")) {
      export_ggplot_multi_format(
        plot_obj = plot_obj,
        base_filename = file_path,
        width = width,
        height = height,
        formats = export_formats,
        dpi = export_dpi,
        verbose = export_verbose
      )
    } else {
      # Fallback to PDF-only using ggsave
      ggplot2::ggsave(
        filename = paste0(file_path, ".pdf"),
        plot = plot_obj,
        width = width,
        height = height,
        device = "pdf"
      )
    }
  }
  
  # Create descriptive subtitle and axis labels from condition_info
  create_plot_labels <- function(condition_info) {
    # Format content area with SGP::capwords if available
    content_formatted <- if (requireNamespace("SGP", quietly = TRUE)) {
      SGP::capwords(condition_info$content)
    } else {
      tools::toTitleCase(tolower(condition_info$content))
    }
    
    # Subtitle: For example: "Mathematics | 2005 Grade 4 → 2006 Grade 5"
    subtitle <- sprintf("%s | %s Grade %d -> %s Grade %d",
                       content_formatted,
                       condition_info$year_prior,
                       condition_info$grade_prior,
                       condition_info$year_current,
                       condition_info$grade_current)
    
    # Axis labels with grade-specific subscripts
    x_label <- bquote(u[.(paste("Grade", condition_info$grade_prior))])
    y_label <- bquote(v[.(paste("Grade", condition_info$grade_current))])
    
    return(list(subtitle = subtitle, x_label = x_label, y_label = y_label))
  }
  
  # Generate labels
  labels <- create_plot_labels(condition_info)
  
  # Initialize plot list
  plots <- list()
  
  cat(sprintf("Generating copula contour plots for: %s\n", 
             basename(output_dir)))
  
  # 1. Calculate empirical copula grids (both CDF and PDF)
  cat("  - Computing empirical copula CDF...\n")
  empirical_grid_cdf <- calculate_empirical_copula_grid(pseudo_obs, 
                                                        grid_size = grid_size,
                                                        method = "ecdf")
  
  cat("  - Computing empirical copula PDF...\n")
  empirical_grid_pdf <- calculate_empirical_copula_grid(pseudo_obs, 
                                                        grid_size = grid_size,
                                                        method = "density")
  
  # 2. Plot empirical copula (CDF and PDF versions)
  # Calculate Kendall's tau from pseudo-observations for empirical titles
  n_pairs <- nrow(original_scores)
  n_formatted <- format(n_pairs, big.mark = ",", scientific = FALSE)
  empirical_tau <- cor(pseudo_obs[, 1], pseudo_obs[, 2], method = "kendall")
  tau_value_emp <- sprintf("%.3f", empirical_tau)
  
  # Create titles with tau and n (matching parametric copula format)
  title_empirical_cdf <- bquote(
    "Empirical Copula (" * tau * " = " * .(tau_value_emp) * ", n = " * .(n_formatted) * ")"
  )
  title_empirical_pdf <- bquote(
    "Empirical Copula (PDF) (" * tau * " = " * .(tau_value_emp) * ", n = " * .(n_formatted) * ")"
  )
  
  plots$empirical_cdf <- plot_empirical_copula_contour(empirical_grid_cdf, 
                                                       title = title_empirical_cdf,
                                                       subtitle = labels$subtitle,
                                                       x_label = labels$x_label,
                                                       y_label = labels$y_label)
  plots$empirical_pdf <- plot_empirical_copula_contour(empirical_grid_pdf, 
                                                       title = title_empirical_pdf,
                                                       subtitle = labels$subtitle,
                                                       x_label = labels$x_label,
                                                       y_label = labels$y_label)
  
  if (save_plots) {
    # Save to main directory (multi-format)
    save_ggplot_multi(plots$empirical_cdf,
                     file.path(output_dir, "empirical_copula_CDF"),
                     width = 7, height = 7)  # No legend (removed for CDF consistency)
    save_ggplot_multi(plots$empirical_pdf,
                     file.path(output_dir, "empirical_copula_PDF"),
                     width = 8.5, height = 7)  # Has legend
  }
  
  # 3. Plot each fitted parametric copula (both CDF and PDF)
  cat("  - Generating parametric copula plots (CDF and PDF for each family)...\n")
  for (family in names(copula_results)) {
    if (!is.null(copula_results[[family]])) {
      
      # Create family-specific subdirectory
      family_dir <- file.path(output_dir, toupper(family))
      if (save_plots && !dir.exists(family_dir)) {
        dir.create(family_dir, recursive = TRUE)
      }
      
      # Get fitted copula
      if (family == "comonotonic") {
        fitted_cop <- NULL  # Special handling for comonotonic
      } else {
        fitted_cop <- copula_results[[family]]$copula
      }
      
      # Format tau value for title (n_pairs and n_formatted already defined above)
      tau_value <- sprintf("%.3f", copula_results[[family]]$kendall_tau)
      
      # Generate CDF plot (copula IS a CDF, no need to say "CDF")
      # Use bquote() for proper Greek tau rendering in PDF export
      title_expr <- bquote(
        .(tools::toTitleCase(family)) ~ " Copula (" * tau * " = " * .(tau_value) * ", n = " * .(n_formatted) * ")"
      )
      
      plots[[paste0(family, "_cdf")]] <- plot_parametric_copula_contour(
        fitted_cop, 
        family,
        grid_size = grid_size,
        plot_type = "cdf",
        title = title_expr,
        sample_size = n_pairs,
        subtitle = labels$subtitle,
        x_label = labels$x_label,
        y_label = labels$y_label
      )
      
      # Generate PDF plot (explicitly label as PDF/density)
      title_expr_pdf <- bquote(
        .(tools::toTitleCase(family)) ~ " Copula Density Function (PDF) (" * tau * " = " * .(tau_value) * ", n = " * .(n_formatted) * ")"
      )
      
      plots[[paste0(family, "_pdf")]] <- plot_parametric_copula_contour(
        fitted_cop, 
        family,
        grid_size = grid_size,
        plot_type = "density",
        title = title_expr_pdf,
        sample_size = n_pairs,
        subtitle = labels$subtitle,
        x_label = labels$x_label,
        y_label = labels$y_label
      )
      
      if (save_plots) {
        # Save to family subdirectory (multi-format)
        save_ggplot_multi(plots[[paste0(family, "_cdf")]],
                         file.path(family_dir, sprintf("%s_copula_CDF", family)),
                         width = 7, height = 7)  # No legend (removed for CDF)
        save_ggplot_multi(plots[[paste0(family, "_pdf")]],
                         file.path(family_dir, sprintf("%s_copula_PDF", family)),
                         width = 8.5, height = 7)  # Has legend
      }
    }
  }
  
  # 4. Create comparison plots (empirical vs each parametric family)
  cat("  - Creating comparison plots (empirical vs parametric for each family)...\n")
  
  for (family in names(copula_results)) {
    if (!is.null(copula_results[[family]])) {
      
      family_dir <- file.path(output_dir, toupper(family))
      
      if (family != "comonotonic") {
        fitted_copula <- copula_results[[family]]$copula
      } else {
        fitted_copula <- NULL
      }
      
      # Create comparison plot (CDF difference)
      plots[[paste0("comparison_", family)]] <- plot_copula_comparison(
        empirical_grid_cdf,
        fitted_copula,
        family,
        plot_type = "difference",
        subtitle = labels$subtitle,
        x_label = labels$x_label,
        y_label = labels$y_label
      )
      
      if (save_plots) {
        save_ggplot_multi(plots[[paste0("comparison_", family)]],
                         file.path(family_dir, sprintf("comparison_empirical_vs_%s_CDF", family)),
                         width = 8.5, height = 7)  # Has legend
      }
    }
  }
  
  # 4b. Add bootstrap uncertainty overlay plots if bootstrap results available
  if (!is.null(bootstrap_results)) {
    cat("  - Creating bootstrap uncertainty overlay plots...\n")
    
    # Get sample size for title
    n_sample <- nrow(original_scores)
    
    for (family in names(copula_results)) {
      if (!is.null(copula_results[[family]]) && family != "comonotonic") {
        
        cat(sprintf("    Processing %s family...\n", family))
        family_dir <- file.path(output_dir, toupper(family))
        
        # Calculate bootstrap uncertainty for CDF
        cat("      Calculating CDF uncertainty...\n")
        uncertainty_cdf <- calculate_bootstrap_uncertainty(
          bootstrap_results = bootstrap_results,
          family = family,
          grid_size = grid_size,
          method = "cdf"
        )
        
        if (!is.null(uncertainty_cdf)) {
          # Create ribbon plot with gradient uncertainty (CDF)
          plots[[paste0(family, "_uncertainty_cdf")]] <- 
            plot_copula_with_uncertainty_ribbons(
              empirical_grid = empirical_grid_cdf,
              uncertainty_results = uncertainty_cdf,
              family = family,
              plot_type = "cdf",
              n_gradient_levels = 10,
              sample_size = n_sample,
              x_label = labels$x_label,
              y_label = labels$y_label
            )
          
          if (save_plots) {
            save_ggplot_multi(plots[[paste0(family, "_uncertainty_cdf")]],
                             file.path(family_dir, sprintf("%s_copula_with_uncertainty_CDF", family)),
                             width = 7, height = 7)  # No legend (square for coord_equal)
          }
        } else {
          cat("      WARNING: No uncertainty results for", family, "CDF\n")
        }
        
        # Note: PDF uncertainty plots are skipped - the ribbon visualization 
        # is designed for CDFs (bounded [0,1]) and doesn't translate well to 
        # unbounded PDF values. Standard PDF plots without uncertainty are sufficient.
      }
    }
    
    cat("  - Bootstrap uncertainty plots complete!\n")
  } else {
    cat("  - No bootstrap results provided, skipping uncertainty plots\n")
  }
  
  # 5. Plot original bivariate density
  cat("  - Creating bivariate density plot of original scores...\n")
  
  # Create specific labels with year and grade info
  x_label <- sprintf("%s Grade %d", condition_info$year_prior, condition_info$grade_prior)
  y_label <- sprintf("%s Grade %d", condition_info$year_current, condition_info$grade_current)
  
  plots$original <- plot_bivariate_density(
    original_scores$SCALE_SCORE_PRIOR,
    original_scores$SCALE_SCORE_CURRENT,
    title = "Original Score Distribution",
    subtitle = labels$subtitle,
    x_label = x_label,
    y_label = y_label,
    sample_size = n_pairs
  )
  
  if (save_plots) {
    save_ggplot_multi(plots$original,
                     file.path(output_dir, "bivariate_density_original"),
                     width = 8.5, height = 7)  # Has legend
  }
  
  # 6. Create summary grid (using CDF plots for key comparisons)
  cat("  - Creating summary grid...\n")
  
  # Select plots for grid (limit to 6 most important) - use CDF versions
  grid_plots <- list(
    plots$empirical_cdf,
    plots[[paste0(best_family, "_cdf")]],
    plots[[paste0("comparison_", best_family)]],
    plots$original
  )
  
  # Add other families if space allows (use CDF versions)
  other_families <- setdiff(names(copula_results), c(best_family, "comonotonic"))
  for (i in seq_along(other_families)) {
    if (length(grid_plots) < 6) {
      plot_name <- paste0(other_families[i], "_cdf")
      if (!is.null(plots[[plot_name]])) {
        grid_plots[[length(grid_plots) + 1]] <- plots[[plot_name]]
      }
    }
  }
  
  summary_grid <- create_condition_summary_grid(
    grid_plots,
    condition_info,
    layout = "2x3"
  )
  
  if (save_plots) {
    # Summary grid is a grob (not ggplot), need different handling for each format
    base_path <- file.path(output_dir, "summary_grid")
    
    # PDF
    if ("pdf" %in% export_formats) {
      ggplot2::ggsave(
        filename = paste0(base_path, ".pdf"),
        plot = summary_grid,
        width = 18,
        height = 12,
        device = "pdf"
      )
    }
    
    # SVG
    if ("svg" %in% export_formats) {
      ggplot2::ggsave(
        filename = paste0(base_path, ".svg"),
        plot = summary_grid,
        width = 18,
        height = 12,
        device = svglite::svglite,
        bg = "transparent"
      )
    }
    
    # PNG
    if ("png" %in% export_formats) {
      ggplot2::ggsave(
        filename = paste0(base_path, "@2x.png"),
        plot = summary_grid,
        width = 18,
        height = 12,
        dpi = export_dpi * 2,
        device = ragg::agg_png
      )
    }
  }
  
  plots$summary_grid <- summary_grid
  
  cat("  - Complete!\n\n")
  
  return(plots)
}

#' Create comparison matrix across multiple conditions
#' 
#' @param condition_dirs Vector of directories containing condition results
#' @param output_file Path for output PDF
#' @param plot_type Type of plots to compare
#' 
#' @return None (saves to file)
create_cross_condition_comparison <- function(condition_dirs,
                                             output_file,
                                             plot_type = "empirical") {
  
  # Implementation for creating matrix of plots across conditions
  # This would load saved data from each condition and create comparison
  # To be implemented based on specific needs
  
  warning("Cross-condition comparison not yet fully implemented")
}

# Additional utility functions

#' Check if ggdensity package is available and suggest installation
check_ggdensity <- function() {
  if (!requireNamespace("ggdensity", quietly = TRUE)) {
    message("Note: The 'ggdensity' package can provide enhanced density visualizations.")
    message("Install with: install.packages('ggdensity')")
    message("Proceeding with standard ggplot2 methods.")
    return(FALSE)
  }
  return(TRUE)
}

#' Use ggdensity for enhanced contour plots if available
#' 
#' @param data Data for plotting
#' @param ... Additional arguments
#' 
#' @return ggplot object
plot_with_ggdensity <- function(data, ...) {
  if (check_ggdensity()) {
    require(ggdensity)
    # Use ggdensity-specific functions
    # Implementation depends on specific ggdensity API
  } else {
    # Fall back to standard ggplot2
    warning("Using standard ggplot2 instead of ggdensity")
  }
}

#' Plot Parametric Copula Contours with Bootstrap Uncertainty
#' 
#' Visualizes copula density with uncertainty bands derived from parametric bootstrap.
#' Shows how parameter uncertainty affects the copula density across the unit square.
#' 
#' @param fitted_copula Fitted copula object (point estimate)
#' @param bootstrap_results Output from bootstrap_copula_estimation()
#' @param family Copula family name ("gaussian", "t", "clayton", "gumbel", "frank")
#' @param grid_size Number of grid points in each dimension (default 300)
#' @param uncertainty_method Visualization method:
#'   - "confidence_band": Show upper/lower quantile contours (default, most intuitive)
#'   - "uncertainty_heatmap": Show CV as background heatmap
#'   - "quantiles": Side-by-side comparison of lower/point/upper
#' @param alpha Confidence level (default 0.90 for 90% bands)
#' @param title Optional custom title
#' 
#' @return ggplot object with uncertainty visualization
#' 
#' @details
#' The bootstrap results should come from bootstrap_copula_estimation() with 
#' sampling_method="paired" to preserve within-student correlation structure.
#' 
#' For each bootstrap sample:
#' 1. Evaluates copula density on grid
#' 2. Calculates pointwise quantiles across bootstrap samples
#' 3. Visualizes uncertainty as bands or heatmaps
#' 
#' Wider bands indicate greater parameter uncertainty in that region.
#' 
#' @examples
#' # After running bootstrap_copula_estimation():
#' plot_copula_with_uncertainty(
#'   fitted_copula = copula_fits$results$t$copula,
#'   bootstrap_results = boot_results,
#'   family = "t",
#'   uncertainty_method = "confidence_band",
#'   alpha = 0.90
#' )
plot_copula_with_uncertainty <- function(fitted_copula,
                                        bootstrap_results,
                                        family,
                                        grid_size = 300,
                                        uncertainty_method = "confidence_band",
                                        alpha = 0.90,
                                        title = NULL,
                                        subtitle = NULL,
                                        x_label = expression(u[prior]),
                                        y_label = expression(v[current])) {
  
  require(ggplot2)
  require(data.table)
  require(copula)
  
  # Create evaluation grid
  u_seq <- seq(0.01, 0.99, length.out = grid_size)
  v_seq <- seq(0.01, 0.99, length.out = grid_size)
  grid <- expand.grid(u = u_seq, v = v_seq)
  grid_matrix <- as.matrix(grid)
  
  # Evaluate point estimate (original fit)
  density_point <- dCopula(grid_matrix, fitted_copula)
  
  # Evaluate on each bootstrap copula
  n_bootstrap <- length(bootstrap_results$bootstrap_results)
  density_boot_matrix <- matrix(NA, nrow = nrow(grid), ncol = n_bootstrap)
  
  cat("  Evaluating", n_bootstrap, "bootstrap copulas on", grid_size, "x", grid_size, "grid...\n")
  
  n_success <- 0
  for (b in 1:n_bootstrap) {
    boot_result <- bootstrap_results$bootstrap_results[[b]]
    if (!is.null(boot_result) && !is.null(boot_result$results[[family]])) {
      boot_cop <- boot_result$results[[family]]$copula
      if (!is.null(boot_cop)) {
        tryCatch({
          density_boot_matrix[, b] <- dCopula(grid_matrix, boot_cop)
          n_success <- n_success + 1
        }, error = function(e) {
          # Skip failed evaluations
        })
      }
    }
  }
  
  cat("  Successfully evaluated", n_success, "of", n_bootstrap, "bootstrap samples\n")
  
  if (n_success < 10) {
    warning("Too few successful bootstrap evaluations (<10). Uncertainty estimates may be unreliable.")
  }
  
  # Calculate quantiles at each grid point
  lower_quantile <- (1 - alpha) / 2
  upper_quantile <- 1 - lower_quantile
  
  density_lower <- apply(density_boot_matrix, 1, quantile, 
                        probs = lower_quantile, na.rm = TRUE)
  density_upper <- apply(density_boot_matrix, 1, quantile, 
                        probs = upper_quantile, na.rm = TRUE)
  density_median <- apply(density_boot_matrix, 1, median, na.rm = TRUE)
  
  # Calculate coefficient of variation as uncertainty measure
  density_sd <- apply(density_boot_matrix, 1, sd, na.rm = TRUE)
  density_cv <- density_sd / pmax(abs(density_point), 1e-6)  # Avoid division by zero
  
  # Create plot data
  plot_data <- data.table(
    u = grid$u,
    v = grid$v,
    density_point = density_point,
    density_lower = density_lower,
    density_upper = density_upper,
    density_median = density_median,
    density_cv = pmin(density_cv, 2)  # Cap at 2 for visualization
  )
  
  # Default title - use bquote for consistent font rendering
  if (is.null(title)) {
    title <- bquote(.(tools::toTitleCase(family)) ~ "Copula with" ~ 
                   .(round(alpha * 100)) * "% Confidence Bands")
  }
  
  ## VISUALIZATION OPTIONS
  
  if (uncertainty_method == "confidence_band") {
    # Option 1: Confidence bands (RECOMMENDED)
    p <- ggplot(plot_data, aes(x = u, y = v)) +
      # Filled contours for point estimate (base layer)
      geom_contour_filled(aes(z = density_point), alpha = 0.5, bins = 15) +
      scale_fill_viridis_d(option = "plasma", name = "Density") +
      # Lower bound contours (dashed blue)
      geom_contour(aes(z = density_lower), color = "blue", 
                  alpha = 0.6, linetype = "dashed", linewidth = 0.6, bins = 10) +
      # Upper bound contours (dashed red)
      geom_contour(aes(z = density_upper), color = "red", 
                  alpha = 0.6, linetype = "dashed", linewidth = 0.6, bins = 10) +
      # Point estimate (solid black)
      geom_contour(aes(z = density_point), color = "black", linewidth = 0.8, bins = 15) +
      coord_equal() +
      labs(
        title = title,
        subtitle = if (!is.null(subtitle)) subtitle else sprintf("Based on %d bootstrap samples (paired resampling)", n_success),
        x = x_label,
        y = y_label,
        caption = "Black = Point estimate | Blue/Red dashed = Confidence bounds"
      ) +
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.margin = margin(20, 4, 7, 4, "pt"),
        plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = 10),
        legend.position = "right",
        panel.grid.minor = element_blank()
      ) +
      scale_x_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
      scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1))
    
  } else if (uncertainty_method == "uncertainty_heatmap") {
    # Option 2: Show uncertainty as heatmap
    p <- ggplot(plot_data, aes(x = u, y = v)) +
      # Uncertainty as background
      geom_raster(aes(fill = density_cv), alpha = 0.8) +
      scale_fill_viridis_c(option = "magma", name = "CV\n(Uncertainty)", 
                          limits = c(0, 2), oob = scales::squish) +
      # Point estimate contours overlaid
      geom_contour(aes(z = density_point), color = "white", linewidth = 0.6, bins = 15) +
      coord_equal() +
      labs(
        title = paste(title, "- Uncertainty Heatmap"),
        subtitle = if (!is.null(subtitle)) subtitle else "Higher values = greater parameter uncertainty",
        x = x_label,
        y = y_label
      ) +
      theme_minimal() +
      theme(
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.margin = margin(20, 4, 7, 4, "pt"),
        plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = 10),
        legend.position = "right"
      ) +
      scale_x_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
      scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1))
    
  } else if (uncertainty_method == "quantiles") {
    # Option 3: Side-by-side quantile plots
    require(gridExtra)
    
    base_theme <- theme_minimal() +
      theme(
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.margin = margin(20, 4, 7, 4, "pt"),
        plot.title = element_text(hjust = 0.5, size = 11, face = "bold"),
        legend.position = "right",
        panel.grid.minor = element_blank()
      )
    
    p1 <- ggplot(plot_data, aes(x = u, y = v, z = density_lower)) +
      geom_contour_filled(bins = 15, alpha = 0.7) +
      geom_contour(color = "black", alpha = 0.5, bins = 15) +
      scale_fill_viridis_d(option = "plasma", name = "Density") +
      coord_equal() +
      labs(title = sprintf("Lower %d%%", round(lower_quantile * 100)),
           x = x_label, y = y_label) +
      base_theme +
      scale_x_continuous(breaks = seq(0, 1, 0.2)) +
      scale_y_continuous(breaks = seq(0, 1, 0.2))
    
    p2 <- ggplot(plot_data, aes(x = u, y = v, z = density_point)) +
      geom_contour_filled(bins = 15, alpha = 0.7) +
      geom_contour(color = "black", alpha = 0.5, bins = 15) +
      scale_fill_viridis_d(option = "plasma", name = "Density") +
      coord_equal() +
      labs(title = "Point Estimate",
           x = x_label, y = y_label) +
      base_theme +
      scale_x_continuous(breaks = seq(0, 1, 0.2)) +
      scale_y_continuous(breaks = seq(0, 1, 0.2))
    
    p3 <- ggplot(plot_data, aes(x = u, y = v, z = density_upper)) +
      geom_contour_filled(bins = 15, alpha = 0.7) +
      geom_contour(color = "black", alpha = 0.5, bins = 15) +
      scale_fill_viridis_d(option = "plasma", name = "Density") +
      coord_equal() +
      labs(title = sprintf("Upper %d%%", round(upper_quantile * 100)),
           x = x_label, y = y_label) +
      base_theme +
      scale_x_continuous(breaks = seq(0, 1, 0.2)) +
      scale_y_continuous(breaks = seq(0, 1, 0.2))
    
    p <- grid.arrange(p1, p2, p3, ncol = 3,
                     top = grid::textGrob(
                       sprintf("%s Copula - Bootstrap Quantiles (%d samples)", 
                              tools::toTitleCase(family), n_success),
                       gp = grid::gpar(fontsize = 14, fontface = "bold")
                     ))
  }
  
  return(p)
}