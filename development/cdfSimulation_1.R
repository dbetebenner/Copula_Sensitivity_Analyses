############################################################################
### Investigate variability in CDF of assessment data
### Context: Copula-based growth modeling using cross-sectional data
###          (e.g., 4th and 8th grade) to understand sensitivity of
###          copula inference to ECDF variability from sampling
############################################################################

# Load libraries
require(data.table)
require(splines2)
require(grid)

# Load HISTORICAL COLORADO DATA containing the following GRADE x YEAR x CONTENT_AREA combinations:
# r$> table(Colorado_Data_LONG$GRADE, Colorado_Data_LONG$YEAR, Colorado_Data_LONG$CONTENT_AREA
#     )
# , ,  = MATHEMATICS

    
#       2003  2004  2005  2006  2007  2008  2009  2010  2011  2012  2013
#   10 52539 53390 54256 55587 56696 57347 57655 57431 58095 57875 58685
#   3      0     0 56106 56460 58142 59484 61500 62467 63084 64644 64444
#   4      0     0 55983 56459 56882 58466 60091 61733 62697 63294 64590
#   5  58233 57362 56481 56395 57021 57305 59071 60311 62035 62842 63463
#   6  58350 58527 57717 56896 56787 57273 57953 59428 60660 62155 63050
#   7  58310 58743 58949 58000 57243 57270 57809 58518 59820 60971 62403
#   8  56710 58249 58677 58856 58281 57298 57640 58061 58543 59985 61070
#   9  58959 59435 60680 60487 61275 60659 60422 60597 59985 60177 61542

# , ,  = READING

    
#       2003  2004  2005  2006  2007  2008  2009  2010  2011  2012  2013
#   10 52565 53390 54265 55618 56682 57350 57669 57451 58113 57904 58686
#   3  53997 53881 54375 54666 56529 57961 60110 61155 61861 63438 63240
#   4  56322 55670 55548 55989 56575 58297 59929 61616 62576 63223 64484
#   5  58293 57398 56519 56411 57043 57294 59069 60320 62034 62871 63466
#   6  58362 58539 57736 56900 56790 57267 57953 59447 60669 62167 63051
#   7  58297 58752 58966 58008 57262 57276 57812 58507 59826 60974 62395
#   8  56732 58258 58709 58848 58327 57309 57650 58073 58567 59989 61074
#   9  59032 59450 60722 60491 61281 60646 60436 60611 60009 60179 61547

# , ,  = WRITING

    
#       2003  2004  2005  2006  2007  2008  2009  2010  2011  2012  2013
#   10 52565 53390 54265 55619 56682 57350 57669 57451 58113 57904 58696
#   3  53987 53888 54425 54722 56534 57975 60126 61232 61843 63455 63278
#   4  56322 55670 55548 55989 56575 58297 59929 61616 62576 63223 64487
#   5  58293 57398 56519 56411 57043 57294 59069 60320 62034 62871 63468
#   6  58362 58539 57736 56900 56790 57267 57953 59447 60669 62167 63053
#   7  58297 58752 58966 58008 57262 57276 57812 58507 59826 60974 62398
#   8  56732 58258 58709 58848 58327 57309 57650 58073 58567 59989 61079
#   9  59032 59450 60722 60491 61281 60646 60436 60611 60009 60179 61553
if (!exists("Colorado_Data_LONG")) {
    load("/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_Data_LONG.RData")
}

################################################################################
### SIMULATION CONFIGURATION
################################################################################
# Configure analysis based on your research context:
#
# SCENARIO 1: INFINITE POPULATION MODEL (Standard Bootstrap)
#   - Use when: Theoretical/methodological investigation of ECDF variability
#   - Use when: No specific population size is relevant
#   - Settings: POPULATION_SIZE = NULL, WITH_REPLACEMENT = TRUE
#   - Interpretation: Variability due to random sampling from theoretical distribution
#
# SCENARIO 2: FINITE POPULATION MODEL (Real-world assessment like TIMSS)
#   - Use when: Modeling specific country/state with known population
#   - Use when: Sampling without replacement from finite population
#   - Settings: POPULATION_SIZE = actual N, WITH_REPLACEMENT = FALSE
#   - Example: Germany TIMSS 2023: ~700,000 4th graders, sample ~4,400
#   - Interpretation: Variability includes Finite Population Correction (FPC)

# CONFIGURATION (modify these for your scenario)
POPULATION_SIZE <- NULL    # Set to actual population size or NULL for infinite
WITH_REPLACEMENT <- TRUE   # TRUE = standard bootstrap, FALSE = finite population

# Examples for different scenarios:
# Germany TIMSS: POPULATION_SIZE <- 700000, WITH_REPLACEMENT <- FALSE
# US State:      POPULATION_SIZE <- 200000, WITH_REPLACEMENT <- FALSE
# Theoretical:   POPULATION_SIZE <- NULL,   WITH_REPLACEMENT <- TRUE

cat("====================================================================\n")
cat("ECDF VARIABILITY ANALYSIS FOR COPULA SENSITIVITY\n")
cat("====================================================================\n")
if (!is.null(POPULATION_SIZE)) {
  cat("Scenario: FINITE POPULATION MODEL\n")
  cat("  Population size:", format(POPULATION_SIZE, big.mark=","), "\n")
  cat("  Sampling: WITHOUT replacement\n")
  cat("  Finite Population Correction: ENABLED\n")
} else {
  cat("Scenario: INFINITE POPULATION MODEL (Standard Bootstrap)\n")
  cat("  Sampling: WITH replacement\n")
  cat("  Interpretation: Theoretical sampling variability\n")
}
cat("====================================================================\n\n")

################################################################################
### 1. Establish Fixed Reference Framework and Baseline I-Spline ECDF
################################################################################

# Extract scale scores and remove any NAs
scale_scores <- tmp.data$SCALE_SCORE[!is.na(tmp.data$SCALE_SCORE)]
n_full <- length(scale_scores)

# Establish FIXED boundaries and knots from full dataset
# These will be used for ALL bootstrap samples to isolate shape variability
# from knot placement variability
boundary_min <- min(scale_scores)
boundary_max <- max(scale_scores)

# Fixed knot locations at 20th, 40th, 60th, 80th percentiles of full data
# These percentiles capture key distributional features for copula modeling
knot_percentiles <- c(0.20, 0.40, 0.60, 0.80)
knot_locations <- quantile(scale_scores, probs = knot_percentiles)

cat("============================================================\n")
cat("FIXED REFERENCE FRAMEWORK (from full dataset)\n")
cat("============================================================\n")
cat("Full dataset size:", n_full, "\n")
cat("Boundaries: [", boundary_min, ",", boundary_max, "]\n")
cat("Knot locations (scale scores) for I-splines:\n")
for (i in seq_along(knot_percentiles)) {
  cat(sprintf("  %d%% percentile: %.2f\n", 
              knot_percentiles[i] * 100, knot_locations[i]))
}
cat("\nNote: All bootstrap ECDFs use these FIXED knots to isolate\n")
cat("      ECDF shape variability from knot placement variability.\n")
cat("      This is critical for assessing copula sensitivity.\n")
cat("============================================================\n\n")

# Create evaluation grid for plotting and analysis
x_grid <- seq(boundary_min, boundary_max, length.out = 500)

# Create empirical CDF for full dataset
ecdf_full <- ecdf(scale_scores)
y_ecdf_full <- ecdf_full(x_grid)

# Create I-spline basis matrix using fixed knots and boundaries
# I-splines are monotone increasing by construction (integral of M-splines)
# This ensures invertibility required for Sklar's theorem / copula modeling
ispline_basis <- iSpline(x_grid, 
                         knots = knot_locations,
                         Boundary.knots = c(boundary_min, boundary_max),
                         degree = 3,
                         intercept = TRUE)

# Fit I-spline coefficients to full dataset ECDF
# Use non-negative least squares to ensure monotonicity
fit_ispline_ecdf <- function(basis_matrix, ecdf_values) {
  # Constrained least squares with non-negative coefficients
  # For I-splines with non-negative coefficients, monotonicity is guaranteed
  
  n_basis <- ncol(basis_matrix)
  
  # Objective: minimize ||basis * coef - ecdf_values||^2
  # Constraint: coef >= 0 (ensures monotonicity for I-splines)
  
  objective <- function(coef) {
    fitted <- basis_matrix %*% coef
    sum((fitted - ecdf_values)^2)
  }
  
  # Initial guess: uniform weights
  init_coef <- rep(1/n_basis, n_basis)
  
  # Optimize with non-negative constraints using L-BFGS-B
  result <- optim(par = init_coef,
                  fn = objective,
                  method = "L-BFGS-B",
                  lower = rep(0, n_basis),
                  upper = rep(Inf, n_basis))
  
  return(result$par)
}

# Fit baseline I-spline to full data
coef_full <- fit_ispline_ecdf(ispline_basis, y_ecdf_full)
y_full_smooth <- as.vector(ispline_basis %*% coef_full)

# Create function for evaluation at arbitrary points
# This function is monotone increasing and invertible (required for copulas)
smooth_ecdf_full <- function(x) {
  basis_x <- iSpline(x,
                     knots = knot_locations,
                     Boundary.knots = c(boundary_min, boundary_max),
                     degree = 3,
                     intercept = TRUE)
  as.vector(basis_x %*% coef_full)
}

cat("Baseline I-spline ECDF fitted successfully.\n")
cat("Properties: Monotone increasing, smooth (C2), invertible.\n\n")

################################################################################
### 2. Bootstrap Resampling Function with Fixed Knot Structure
################################################################################

create_bootstrap_ecdf <- function(data, n_sample, n_bootstrap = 100,
                                   knots, boundaries, x_eval,
                                   population_size = NULL,
                                   sampling_with_replacement = TRUE) {
  # data: vector of scale scores (full dataset or population proxy)
  # n_sample: sample size for each bootstrap
  # n_bootstrap: number of bootstrap resamples
  # knots: fixed knot locations (from full data)
  # boundaries: c(min, max) boundaries (from full data)
  # x_eval: evaluation grid for fitted functions
  # population_size: Total population size (NULL = infinite population model)
  # sampling_with_replacement: TRUE = standard bootstrap (infinite pop)
  #                           FALSE = finite population sampling
  
  bootstrap_ecdfs <- vector("list", n_bootstrap)
  
  # Store diagnostics to verify variability
  sample_means <- numeric(n_bootstrap)
  sample_sds <- numeric(n_bootstrap)
  sample_mins <- numeric(n_bootstrap)
  sample_maxs <- numeric(n_bootstrap)
  
  # Create I-spline basis for evaluation grid (same for all bootstraps)
  basis_eval <- iSpline(x_eval,
                        knots = knots,
                        Boundary.knots = boundaries,
                        degree = 3,
                        intercept = TRUE)
  
  for (i in 1:n_bootstrap) {
    # Sample with or without replacement based on configuration
    sample_data <- sample(data, size = n_sample, replace = sampling_with_replacement)
    
    # Store diagnostics
    sample_means[i] <- mean(sample_data)
    sample_sds[i] <- sd(sample_data)
    sample_mins[i] <- min(sample_data)
    sample_maxs[i] <- max(sample_data)
    
    # Create ECDF for this sample, evaluated on the fixed grid
    ecdf_sample <- ecdf(sample_data)
    y_ecdf_sample <- ecdf_sample(x_eval)
    
    # Fit I-spline using the FIXED knot structure
    coef_sample <- fit_ispline_ecdf(basis_eval, y_ecdf_sample)
    
    # Create function for this bootstrap sample
    # Use local() to force proper closure and avoid lazy evaluation issues
    # This ensures each function captures its own unique coefficients
    bootstrap_ecdfs[[i]] <- local({
      coef_local <- coef_sample
      function(x) {
        basis_x <- iSpline(x,
                          knots = knots,
                          Boundary.knots = boundaries,
                          degree = 3,
                          intercept = TRUE)
        as.vector(basis_x %*% coef_local)
      }
    })
  }
  
  # Print diagnostics to verify bootstrap variability
  cat("  Bootstrap diagnostics (", n_bootstrap, " samples):\n", sep="")
  cat("    Sample means - Range: [", 
      round(min(sample_means), 2), ",", round(max(sample_means), 2), 
      "], SD:", round(sd(sample_means), 2), "\n")
  cat("    Sample SDs   - Range: [", 
      round(min(sample_sds), 2), ",", round(max(sample_sds), 2), 
      "], SD:", round(sd(sample_sds), 2), "\n")
  
  # Calculate and report Finite Population Correction if applicable
  if (!sampling_with_replacement && !is.null(population_size)) {
    N <- population_size
    n <- n_sample
    fpc <- sqrt((N - n) / (N - 1))
    sampling_fraction <- n / N * 100
    
    cat("    Finite Population Correction (FPC): ", round(fpc, 4), "\n")
    cat("    Sampling fraction: ", round(sampling_fraction, 2), "%\n")
    
    if (sampling_fraction > 5) {
      cat("    Note: Sampling >5% of population - FPC is important!\n")
    } else {
      cat("    Note: Sampling <5% of population - FPC has minimal effect.\n")
    }
  }
  
  return(bootstrap_ecdfs)
}

################################################################################
### 3. Grid Graphics Visualization Function
################################################################################

plot_ecdf_bootstrap <- function(x_grid, y_full_smooth, bootstrap_ecdfs, 
                                 sample_size, filename, 
                                 population_size = NULL,
                                 with_replacement = TRUE) {
  # Evaluate all bootstrap ECDFs on the grid
  n_bootstrap <- length(bootstrap_ecdfs)
  bootstrap_matrix <- matrix(NA, nrow = length(x_grid), ncol = n_bootstrap)
  
  for (i in 1:n_bootstrap) {
    bootstrap_matrix[, i] <- bootstrap_ecdfs[[i]](x_grid)
  }
  
  # Calculate confidence bands (5th and 95th percentiles)
  lower_band <- apply(bootstrap_matrix, 1, quantile, probs = 0.05, na.rm = TRUE)
  upper_band <- apply(bootstrap_matrix, 1, quantile, probs = 0.95, na.rm = TRUE)
  
  # Open PDF device
  pdf(file.path("Figures", filename), width = 8, height = 6)
  
  # Create new page
  grid.newpage()
  
  # Set up viewport with margins
  pushViewport(viewport(
    x = 0.5, y = 0.5,
    width = 0.85, height = 0.80,
    xscale = range(x_grid),
    yscale = c(0, 1)
  ))
  
  # Draw background and axes
  grid.rect(gp = gpar(col = "black", fill = "white"))
  
  # X-axis
  grid.xaxis(gp = gpar(cex = 0.8))
  grid.text("Scale Score", y = unit(-3, "lines"), gp = gpar(cex = 0.9))
  
  # Y-axis
  grid.yaxis(gp = gpar(cex = 0.8))
  grid.text("Cumulative Probability", x = unit(-3.5, "lines"), rot = 90, 
            gp = gpar(cex = 0.9))
  
  # Title with FPC indicator
  title_text <- paste0("ECDF Bootstrap Analysis (n = ", sample_size, ")")
  if (!is.null(population_size) && !with_replacement) {
    fpc <- sqrt((population_size - sample_size) / (population_size - 1))
    title_text <- paste0(title_text, " - FPC: ", round(fpc, 4))
  }
  
  grid.text(title_text,
            y = unit(1, "npc") + unit(2.5, "lines"),
            gp = gpar(cex = 1.1, fontface = "bold"))
  
  # Plot bootstrap ECDFs with high transparency
  for (i in 1:n_bootstrap) {
    y_vals <- bootstrap_matrix[, i]
    
    grid.lines(x = x_grid, y = y_vals, default.units = "native",
               gp = gpar(col = rgb(0, 0, 1, alpha = 0.05)))
  }
  
  # Plot confidence bands
  grid.lines(x = x_grid, y = lower_band, default.units = "native",
             gp = gpar(col = rgb(1, 0, 0, alpha = 0.5), lwd = 2, lty = 2))
  grid.lines(x = x_grid, y = upper_band, default.units = "native",
             gp = gpar(col = rgb(1, 0, 0, alpha = 0.5), lwd = 2, lty = 2))
  
  # Plot full data ECDF in black (opaque)
  grid.lines(x = x_grid, y = y_full_smooth, default.units = "native",
             gp = gpar(col = "black", lwd = 2))
  
  # Add legend
  legend_x <- unit(0.02, "npc")
  legend_y <- unit(0.98, "npc")
  
  grid.text("Full Data ECDF", x = legend_x + unit(2.5, "lines"), 
            y = legend_y - unit(0, "lines"),
            just = "left", gp = gpar(cex = 0.7))
  grid.lines(x = unit.c(legend_x, legend_x + unit(2, "lines")),
             y = unit.c(legend_y - unit(0, "lines"), legend_y - unit(0, "lines")),
             gp = gpar(col = "black", lwd = 2))
  
  grid.text("Bootstrap ECDFs", x = legend_x + unit(2.5, "lines"), 
            y = legend_y - unit(1.2, "lines"),
            just = "left", gp = gpar(cex = 0.7))
  grid.lines(x = unit.c(legend_x, legend_x + unit(2, "lines")),
             y = unit.c(legend_y - unit(1.2, "lines"), legend_y - unit(1.2, "lines")),
             gp = gpar(col = rgb(0, 0, 1, alpha = 0.3), lwd = 2))
  
  grid.text("90% CI Bands", x = legend_x + unit(2.5, "lines"), 
            y = legend_y - unit(2.4, "lines"),
            just = "left", gp = gpar(cex = 0.7))
  grid.lines(x = unit.c(legend_x, legend_x + unit(2, "lines")),
             y = unit.c(legend_y - unit(2.4, "lines"), legend_y - unit(2.4, "lines")),
             gp = gpar(col = rgb(1, 0, 0, alpha = 0.5), lwd = 2, lty = 2))
  
  # Pop viewport
  popViewport()
  
  # Close device
  dev.off()
  
  # Return summary statistics
  return(list(
    lower_band = lower_band,
    upper_band = upper_band,
    bootstrap_matrix = bootstrap_matrix
  ))
}

################################################################################
### 4. Generate Plots for All Sample Sizes
################################################################################

# Define sample sizes to analyze
# These span realistic TIMSS-like scenarios from small samples to large
sample_sizes <- c(50, 100, 250, 500, 1000, 2500, 4000)
n_bootstrap <- 100

# Storage for results
results_list <- vector("list", length(sample_sizes))
names(results_list) <- paste0("n", sample_sizes)

cat("Generating bootstrap analyses and plots...\n\n")

for (i in seq_along(sample_sizes)) {
  n_sample <- sample_sizes[i]
  
  cat("Processing sample size n =", n_sample, "...\n")
  
  # Check if sample size exceeds data size when sampling without replacement
  if (!WITH_REPLACEMENT && n_sample > n_full) {
    cat("  WARNING: Sample size (", n_sample, ") exceeds data size (", n_full, 
        "). Skipping.\n\n", sep="")
    next
  }
  
  # Generate bootstrap ECDFs using FIXED knot structure
  boot_ecdfs <- create_bootstrap_ecdf(
    data = scale_scores,
    n_sample = n_sample,
    n_bootstrap = n_bootstrap,
    knots = knot_locations,
    boundaries = c(boundary_min, boundary_max),
    x_eval = x_grid,
    population_size = POPULATION_SIZE,
    sampling_with_replacement = WITH_REPLACEMENT
  )
  
  # Create filename
  filename <- file.path("Figures", paste0("ecdf_n", n_sample, ".pdf"))
  
  # Create plot and get summary statistics
  results <- plot_ecdf_bootstrap(
    x_grid = x_grid,
    y_full_smooth = y_full_smooth,
    bootstrap_ecdfs = boot_ecdfs, 
    sample_size = n_sample,
    filename = filename,
    population_size = POPULATION_SIZE,
    with_replacement = WITH_REPLACEMENT
  )
  
  results_list[[i]] <- results
  
  cat("  Saved:", filename, "\n\n")
}

cat("All plots generated successfully!\n\n")

################################################################################
### 5. Summary Statistics
################################################################################

cat("====================================================================\n")
cat("VARIABILITY ANALYSIS SUMMARY\n")
cat("====================================================================\n\n")

# Create summary table
summary_stats <- data.table(
  sample_size = sample_sizes,
  mean_band_width = NA_real_,
  median_band_width = NA_real_,
  max_band_width = NA_real_,
  mae_25th = NA_real_,
  mae_50th = NA_real_,
  mae_75th = NA_real_
)

# Add FPC column if applicable
if (!is.null(POPULATION_SIZE) && !WITH_REPLACEMENT) {
  summary_stats$fpc <- NA_real_
  summary_stats$sampling_fraction_pct <- NA_real_
}

# Calculate percentile indices
idx_25 <- which.min(abs(y_full_smooth - 0.25))
idx_50 <- which.min(abs(y_full_smooth - 0.50))
idx_75 <- which.min(abs(y_full_smooth - 0.75))

for (i in seq_along(sample_sizes)) {
  results <- results_list[[i]]
  
  # Skip if no results (e.g., sample size too large)
  if (is.null(results)) next
  
  # Confidence band width
  band_width <- results$upper_band - results$lower_band
  summary_stats$mean_band_width[i] <- mean(band_width, na.rm = TRUE)
  summary_stats$median_band_width[i] <- median(band_width, na.rm = TRUE)
  summary_stats$max_band_width[i] <- max(band_width, na.rm = TRUE)
  
  # Mean absolute error at key percentiles
  boot_matrix <- results$bootstrap_matrix
  mae_25 <- mean(abs(boot_matrix[idx_25, ] - y_full_smooth[idx_25]), na.rm = TRUE)
  mae_50 <- mean(abs(boot_matrix[idx_50, ] - y_full_smooth[idx_50]), na.rm = TRUE)
  mae_75 <- mean(abs(boot_matrix[idx_75, ] - y_full_smooth[idx_75]), na.rm = TRUE)
  
  summary_stats$mae_25th[i] <- mae_25
  summary_stats$mae_50th[i] <- mae_50
  summary_stats$mae_75th[i] <- mae_75
  
  # Calculate FPC if applicable
  if (!is.null(POPULATION_SIZE) && !WITH_REPLACEMENT) {
    N <- POPULATION_SIZE
    n <- sample_sizes[i]
    if (n <= N) {
      summary_stats$fpc[i] <- sqrt((N - n) / (N - 1))
      summary_stats$sampling_fraction_pct[i] <- (n / N) * 100
    }
  }
}

print(summary_stats)

cat("\n")
cat("Column Definitions:\n")
cat("- sample_size: Number of observations in each bootstrap sample\n")
cat("- mean_band_width: Average width of 90% confidence bands across all scale scores\n")
cat("- median_band_width: Median width of 90% confidence bands\n")
cat("- max_band_width: Maximum width of 90% confidence bands\n")
cat("- mae_XXth: Mean absolute error at the XXth percentile\n")

if (!is.null(POPULATION_SIZE) && !WITH_REPLACEMENT) {
  cat("- fpc: Finite Population Correction factor\n")
  cat("- sampling_fraction_pct: Percentage of population sampled\n")
  cat("\nNote: FPC accounts for finite population. Values closer to 1.0 mean\n")
  cat("      minimal correction (large population relative to sample).\n")
}

cat("\n")
cat("Interpretation for Copula Modeling:\n")
cat("- Smaller band widths indicate more stable marginal ECDFs\n")
cat("- This directly affects copula parameter estimation reliability\n")
cat("- For cross-sectional growth (4th vs 8th grade), consider minimum\n")
cat("  sample sizes where band widths become acceptably small\n")
cat("- MAE at percentiles shows where ECDF variability is greatest\n")
cat("====================================================================\n")

################################################################################
### 6. Additional Output for Copula Analysis
################################################################################

# Save key objects for potential copula modeling
# These smooth, monotone ECDFs can be inverted for Sklar's theorem

cat("\nKey objects available for copula modeling:\n")
cat("- smooth_ecdf_full: Baseline smoothed ECDF function (invertible)\n")
cat("- results_list: Bootstrap results for each sample size\n")
cat("- knot_locations: Fixed knot positions used for all ECDFs\n")
cat("- All ECDFs are monotone increasing, smooth (C2), and invertible\n")
cat("- Ready for use in Sklar's theorem / copula construction\n")
