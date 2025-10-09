############################################################################
### DEBUG: WHY DOES FRANK COPULA DOMINATE?
############################################################################
###
### PURPOSE: Systematically investigate whether Frank copula genuinely
###          provides the best fit to Colorado longitudinal assessment
###          data, or if there's a subtle issue with:
###          
###          1. I-spline transformation removing tail dependence
###          2. Pseudo-observations not being truly Uniform(0,1)
###          3. Educational data genuinely lacking tail dependence
###          4. Numerical issues in copula fitting
###
### USAGE: Run this script section-by-section interactively in R.
###        Pause at each CHECKPOINT to examine output and plots.
###        This will help diagnose the source of Frank's dominance.
###
### INSTRUCTIONS:
###   1. Load this entire file: source("debug_frank_dominance.R", echo=TRUE)
###   2. OR copy/paste sections one at a time into R console
###   3. Examine plots and output at each checkpoint
###   4. Document your findings in comments at the bottom
###
############################################################################

# Load required libraries
require(data.table)
require(copula)
require(splines2)

# Load Colorado data if not already loaded
if (!exists("Colorado_Data_LONG")) {
  load("/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_Data_LONG.RData")
  Colorado_Data_LONG <- as.data.table(Colorado_Data_LONG)
}

# Source functions
source("../functions/longitudinal_pairs.R")
source("../functions/ispline_ecdf.R")

cat("====================================================================\n")
cat("DEBUG: FRANK COPULA DOMINANCE INVESTIGATION\n")
cat("====================================================================\n\n")

cat("This script will help you understand WHY Frank copula is winning.\n")
cat("Run each section carefully and examine the output.\n\n")

############################################################################
### SECTION 1: RAW DATA INSPECTION
############################################################################
###
### GOAL: Examine the raw scale score distributions to see if there's
###       visual evidence of tail dependence BEFORE any transformation.
###
### TAIL DEPENDENCE means: Students who are extreme (very high or very low)
### in one grade tend to stay extreme in the next grade. This creates
### "clustering in the corners" of a scatterplot.
###
### NO TAIL DEPENDENCE means: Extreme students regress toward the mean,
### creating a more elliptical cloud without strong corner clustering.
###
### Frank copula has NO tail dependence, so if the data also lacks it,
### Frank will naturally fit better than t-copula (which has tail dependence).
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("SECTION 1: RAW DATA INSPECTION\n")
cat("====================================================================\n\n")

# Get one representative condition for detailed analysis
# We'll use Grade 4→5 Math 2010 (same as diagnostic)
pairs_full <- create_longitudinal_pairs(
  data = Colorado_Data_LONG,
  grade_prior = 4,
  grade_current = 5,
  year_prior = "2010",
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS"
)

cat("Sample size:", nrow(pairs_full), "students\n")
cat("Prior (Grade 4) range:", range(pairs_full$SCALE_SCORE_PRIOR), "\n")
cat("Current (Grade 5) range:", range(pairs_full$SCALE_SCORE_CURRENT), "\n\n")

# Basic correlation statistics
cat("Correlation measures:\n")
cat("  Pearson r:", cor(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT, method="pearson"), "\n")
cat("  Spearman rho:", cor(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT, method="spearman"), "\n")
cat("  Kendall tau:", cor(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT, method="kendall"), "\n\n")

# Plot 1: Full scatterplot of raw scores
pdf("debug_1_raw_scores.pdf", width=10, height=10)
par(mfrow=c(2,2))

# Main scatterplot
plot(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT,
     pch=20, cex=0.3, col=rgb(0,0,0,0.3),
     xlab="Prior Score (Grade 4)",
     ylab="Current Score (Grade 5)",
     main="Raw Scores: Grade 4 → Grade 5 Math")
abline(lm(SCALE_SCORE_CURRENT ~ SCALE_SCORE_PRIOR, data=pairs_full), 
       col="red", lwd=2)
grid()

# Zoom into lower-left corner (low performers)
# If tail dependence exists, you'll see tight clustering along diagonal
low_cutoff <- quantile(pairs_full$SCALE_SCORE_PRIOR, 0.2)
plot(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT,
     xlim=range(pairs_full$SCALE_SCORE_PRIOR[pairs_full$SCALE_SCORE_PRIOR < low_cutoff]),
     ylim=range(pairs_full$SCALE_SCORE_CURRENT[pairs_full$SCALE_SCORE_PRIOR < low_cutoff]),
     pch=20, cex=0.5, col=rgb(0,0,1,0.3),
     xlab="Prior Score (Grade 4)",
     ylab="Current Score (Grade 5)",
     main="Lower Tail: Bottom 20% of Prior")
abline(0, 1, col="red", lty=2, lwd=2)
grid()

# Zoom into upper-right corner (high performers)
high_cutoff <- quantile(pairs_full$SCALE_SCORE_PRIOR, 0.8)
plot(pairs_full$SCALE_SCORE_PRIOR, pairs_full$SCALE_SCORE_CURRENT,
     xlim=range(pairs_full$SCALE_SCORE_PRIOR[pairs_full$SCALE_SCORE_PRIOR > high_cutoff]),
     ylim=range(pairs_full$SCALE_SCORE_CURRENT[pairs_full$SCALE_SCORE_PRIOR > high_cutoff]),
     pch=20, cex=0.5, col=rgb(1,0,0,0.3),
     xlab="Prior Score (Grade 4)",
     ylab="Current Score (Grade 5)",
     main="Upper Tail: Top 20% of Prior")
abline(0, 1, col="red", lty=2, lwd=2)
grid()

# Marginal distributions
hist(pairs_full$SCALE_SCORE_PRIOR, breaks=50, 
     main="Prior Score Distribution", 
     xlab="Grade 4 Score", col="lightblue", border="white")
hist(pairs_full$SCALE_SCORE_CURRENT, breaks=50,
     main="Current Score Distribution",
     xlab="Grade 5 Score", col="lightgreen", border="white")

dev.off()

cat("✓ Plot saved: debug_1_raw_scores.pdf\n\n")

# Analyze extreme students' stability
# Are low performers staying low? Are high performers staying high?
quantile_prior <- quantile(pairs_full$SCALE_SCORE_PRIOR, c(0.05, 0.10, 0.90, 0.95))
quantile_current <- quantile(pairs_full$SCALE_SCORE_CURRENT, c(0.05, 0.10, 0.90, 0.95))

# Bottom 5% and 10%
extreme_low_5 <- pairs_full[SCALE_SCORE_PRIOR <= quantile_prior[1]]
extreme_low_10 <- pairs_full[SCALE_SCORE_PRIOR <= quantile_prior[2]]

# Top 5% and 10%
extreme_high_5 <- pairs_full[SCALE_SCORE_PRIOR >= quantile_prior[4]]
extreme_high_10 <- pairs_full[SCALE_SCORE_PRIOR >= quantile_prior[3]]

cat("====================================================================\n")
cat("CHECKPOINT 1: Do extreme students stay extreme?\n")
cat("====================================================================\n\n")

cat("BOTTOM 5% of students in Grade 4:\n")
cat("  Prior mean:", round(mean(extreme_low_5$SCALE_SCORE_PRIOR), 1), 
    " (percentile: 2.5)\n")
cat("  Current mean:", round(mean(extreme_low_5$SCALE_SCORE_CURRENT), 1), "\n")
cat("  Current percentile:", 
    round(100*mean(extreme_low_5$SCALE_SCORE_CURRENT < quantile_current[1]), 1), 
    "% still in bottom 5%\n")
cat("  Current percentile:", 
    round(100*mean(extreme_low_5$SCALE_SCORE_CURRENT < quantile_current[2]), 1), 
    "% still in bottom 10%\n\n")

cat("TOP 5% of students in Grade 4:\n")
cat("  Prior mean:", round(mean(extreme_high_5$SCALE_SCORE_PRIOR), 1),
    " (percentile: 97.5)\n")
cat("  Current mean:", round(mean(extreme_high_5$SCALE_SCORE_CURRENT), 1), "\n")
cat("  Current percentile:", 
    round(100*mean(extreme_high_5$SCALE_SCORE_CURRENT > quantile_current[4]), 1),
    "% still in top 5%\n")
cat("  Current percentile:",
    round(100*mean(extreme_high_5$SCALE_SCORE_CURRENT > quantile_current[3]), 1),
    "% still in top 10%\n\n")

cat("INTERPRETATION:\n")
cat("- If ~70-80%+ of extreme students stay extreme → TAIL DEPENDENCE\n")
cat("  (t-copula should win)\n")
cat("- If ~50-60% of extreme students stay extreme → NO TAIL DEPENDENCE\n")
cat("  (Frank copula should win)\n\n")

cat("YOUR OBSERVATION: ________________________________\n\n")
cat("Press Enter to continue to Section 2...")
readline()

############################################################################
### SECTION 2: I-SPLINE TRANSFORMATION CHECK
############################################################################
###
### GOAL: Verify that the I-spline transformation produces proper
###       pseudo-observations that are Uniform(0,1) distributed.
###
### WHY THIS MATTERS: If the pseudo-observations aren't truly uniform,
### the copula fits will be biased. The copula package assumes that
### U and V are both Uniform(0,1).
###
### WHAT TO LOOK FOR:
### - Histograms should be flat (uniform)
### - Q-Q plots should be straight lines
### - K-S test p-values should be > 0.05 (can't reject uniformity)
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("SECTION 2: I-SPLINE TRANSFORMATION CHECK\n")
cat("====================================================================\n\n")

# Create I-spline frameworks using the standard approach
cat("Creating I-spline frameworks...\n")
framework_prior <- create_ispline_framework(
  pairs_full$SCALE_SCORE_PRIOR,
  knot_percentiles = c(0.20, 0.40, 0.60, 0.80)
)
framework_current <- create_ispline_framework(
  pairs_full$SCALE_SCORE_CURRENT,
  knot_percentiles = c(0.20, 0.40, 0.60, 0.80)
)

cat("I-spline framework details:\n")
cat("  Knot locations (prior):", framework_prior$knot_locations, "\n")
cat("  Knot locations (current):", framework_current$knot_locations, "\n\n")

# Transform scores to pseudo-observations
cat("Transforming to pseudo-observations...\n")
U <- framework_prior$smooth_ecdf_full(pairs_full$SCALE_SCORE_PRIOR)
V <- framework_current$smooth_ecdf_full(pairs_full$SCALE_SCORE_CURRENT)

# Constrain to (0,1) - standard practice in copula estimation
U <- pmax(1e-6, pmin(1 - 1e-6, U))
V <- pmax(1e-6, pmin(1 - 1e-6, V))

cat("Pseudo-observation ranges:\n")
cat("  U (prior): [", min(U), ",", max(U), "]\n")
cat("  V (current): [", min(V), ",", max(V), "]\n\n")

# Test uniformity
ks_u <- ks.test(U, "punif", 0, 1)
ks_v <- ks.test(V, "punif", 0, 1)

cat("Kolmogorov-Smirnov tests for uniformity:\n")
cat("  U: D =", round(ks_u$statistic, 6), ", p-value =", 
    format.pval(ks_u$p.value, digits=3), "\n")
cat("  V: D =", round(ks_v$statistic, 6), ", p-value =", 
    format.pval(ks_v$p.value, digits=3), "\n\n")

# Create diagnostic plots
pdf("debug_2_pseudo_observations.pdf", width=12, height=10)
par(mfrow=c(3,3))

# Histograms - should be flat if uniform
hist(U, breaks=50, main="U (Prior) Distribution", 
     xlab="U", col="lightblue", border="white",
     ylim=c(0, max(hist(U, breaks=50, plot=FALSE)$counts)*1.2))
abline(h=length(U)/50, col="red", lwd=2, lty=2)
text(0.5, max(hist(U, breaks=50, plot=FALSE)$counts)*1.1,
     paste("K-S p =", format.pval(ks_u$p.value, digits=2)), col="red")

hist(V, breaks=50, main="V (Current) Distribution",
     xlab="V", col="lightgreen", border="white",
     ylim=c(0, max(hist(V, breaks=50, plot=FALSE)$counts)*1.2))
abline(h=length(V)/50, col="red", lwd=2, lty=2)
text(0.5, max(hist(V, breaks=50, plot=FALSE)$counts)*1.1,
     paste("K-S p =", format.pval(ks_v$p.value, digits=2)), col="red")

# Q-Q plots - should be straight line if uniform
qqplot(qunif(ppoints(length(U))), U, 
       main="U Q-Q Plot vs Uniform(0,1)",
       xlab="Theoretical Quantiles", ylab="Sample Quantiles")
abline(0, 1, col="red", lwd=2)

qqplot(qunif(ppoints(length(V))), V,
       main="V Q-Q Plot vs Uniform(0,1)",
       xlab="Theoretical Quantiles", ylab="Sample Quantiles")
abline(0, 1, col="red", lwd=2)

# Scatterplot of pseudo-observations
plot(U, V, pch=20, cex=0.3, col=rgb(0,0,0,0.3),
     main="Pseudo-Observations (U,V)",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2)
grid()

# Zoom into corners to check tail behavior
plot(U, V, xlim=c(0, 0.1), ylim=c(0, 0.1),
     pch=20, cex=0.5, col=rgb(0,0,1,0.5),
     main="Lower Tail (0-10%)",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2, lwd=2)
grid()

plot(U, V, xlim=c(0.9, 1), ylim=c(0.9, 1),
     pch=20, cex=0.5, col=rgb(1,0,0,0.5),
     main="Upper Tail (90-100%)",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2, lwd=2)
grid()

# Empirical CDF of U and V (should match y=x line)
plot(ecdf(U), main="Empirical CDF of U",
     xlab="U", ylab="F(U)", col="blue", lwd=2)
abline(0, 1, col="red", lty=2, lwd=2)

plot(ecdf(V), main="Empirical CDF of V",
     xlab="V", ylab="F(V)", col="darkgreen", lwd=2)
abline(0, 1, col="red", lty=2, lwd=2)

dev.off()

cat("✓ Plot saved: debug_2_pseudo_observations.pdf\n\n")

cat("====================================================================\n")
cat("CHECKPOINT 2: Are pseudo-observations properly uniform?\n")
cat("====================================================================\n\n")

cat("INTERPRETATION:\n")
cat("- K-S p-value < 0.05 → NOT uniform (transformation problem!)\n")
cat("- K-S p-value > 0.05 → Uniform (transformation OK)\n")
cat("- Histograms should be flat\n")
cat("- Q-Q plots should be straight lines\n")
cat("- ECDFs should match the red y=x line\n\n")

cat("YOUR OBSERVATION: ________________________________\n\n")
cat("Press Enter to continue to Section 3...")
readline()

############################################################################
### SECTION 3: TAIL DEPENDENCE VISUAL CHECK
############################################################################
###
### GOAL: Visually inspect the transformed pseudo-observations for
###       evidence of tail dependence.
###
### WHAT TO LOOK FOR:
### - Chi-plot: If line stays above 0 at high thresholds → tail dependence
###             If line drops to 0 → no tail dependence
### - Tail scatterplots: Clustering near diagonal → dependence
###                      Scattered/sparse → no dependence
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("SECTION 3: TAIL DEPENDENCE VISUAL CHECK\n")
cat("====================================================================\n\n")

cat("Creating tail dependence diagnostic plots...\n\n")

# Chi-plot function for upper tail dependence
# This measures whether extreme values co-occur more than expected
chiplot_func <- function(u, v, n_points=100) {
  h_seq <- seq(0.5, 0.99, length=n_points)
  chi_vals <- sapply(h_seq, function(h) {
    in_tail <- (u > h) & (v > h)
    n_in_tail <- sum(in_tail)
    if(n_in_tail < 20) return(NA)
    # Chi is the conditional exceedance correlation
    # If > 0 as h→1, we have upper tail dependence
    prob_both <- n_in_tail / length(u)
    prob_u <- sum(u > h) / length(u)
    prob_v <- sum(v > h) / length(v)
    chi <- (prob_both - prob_u * prob_v) / sqrt(prob_u * (1-prob_u) * prob_v * (1-prob_v))
    return(chi)
  })
  return(list(h=h_seq, chi=chi_vals))
}

chi_result <- chiplot_func(U, V)

pdf("debug_3_tail_dependence.pdf", width=12, height=10)
par(mfrow=c(2,3))

# Lower-left tail zoom (low performers)
plot(U, V, xlim=c(0, 0.1), ylim=c(0, 0.1),
     pch=20, cex=0.8, col=rgb(0,0,1,0.5),
     main="Lower Tail: Bottom 10%",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2, lwd=2)
abline(h=0.1, v=0.1, col="gray", lty=3)
grid()
text(0.05, 0.095, 
     paste("n =", sum(U < 0.1 & V < 0.1)),
     col="blue", font=2)

# Mid-lower zoom
plot(U, V, xlim=c(0, 0.2), ylim=c(0, 0.2),
     pch=20, cex=0.6, col=rgb(0,0,1,0.3),
     main="Lower Tail: Bottom 20%",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2, lwd=2)
grid()

# Upper-right tail zoom (high performers)
plot(U, V, xlim=c(0.9, 1), ylim=c(0.9, 1),
     pch=20, cex=0.8, col=rgb(1,0,0,0.5),
     main="Upper Tail: Top 10%",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2, lwd=2)
abline(h=0.9, v=0.9, col="gray", lty=3)
grid()
text(0.95, 0.905,
     paste("n =", sum(U > 0.9 & V > 0.9)),
     col="red", font=2)

# Mid-upper zoom
plot(U, V, xlim=c(0.8, 1), ylim=c(0.8, 1),
     pch=20, cex=0.6, col=rgb(1,0,0,0.3),
     main="Upper Tail: Top 20%",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2, lwd=2)
grid()

# Chi-plot for upper tail dependence
plot(chi_result$h, chi_result$chi, type="l", lwd=2, col="darkblue",
     xlab="Threshold (h)",
     ylab="Chi (tail correlation)",
     main="Upper Tail Dependence (Chi-plot)",
     ylim=c(min(chi_result$chi, na.rm=TRUE)*1.1, 
            max(chi_result$chi, na.rm=TRUE)*1.1))
abline(h=0, col="red", lty=2, lwd=2)
grid()
text(0.7, max(chi_result$chi, na.rm=TRUE)*0.9,
     "If line > 0 as h→1:\nTail dependence present",
     col="darkblue", cex=0.9)

# Full pseudo-observations with contour
smoothScatter(U, V, nrpoints=0,
              main="Density Contours of Pseudo-Observations",
              xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2, lwd=2)
abline(h=c(0.1, 0.9), v=c(0.1, 0.9), col="gray", lty=3)

dev.off()

cat("✓ Plot saved: debug_3_tail_dependence.pdf\n\n")

# Calculate tail concentration metrics
lower_tail_conc <- sum(U < 0.1 & V < 0.1) / length(U)
upper_tail_conc <- sum(U > 0.9 & V > 0.9) / length(U)

cat("Tail concentration metrics:\n")
cat("  Lower tail (both < 10%):", round(lower_tail_conc, 4),
    " (expected under independence: 0.0100)\n")
cat("  Upper tail (both > 90%):", round(upper_tail_conc, 4),
    " (expected under independence: 0.0100)\n")
cat("  Lower tail concentration ratio:", round(lower_tail_conc / 0.01, 2), "x\n")
cat("  Upper tail concentration ratio:", round(upper_tail_conc / 0.01, 2), "x\n\n")

cat("Final chi value (h=0.99):", round(tail(na.omit(chi_result$chi), 1), 4), "\n\n")

cat("====================================================================\n")
cat("CHECKPOINT 3: Is there visual tail dependence?\n")
cat("====================================================================\n\n")

cat("INTERPRETATION:\n")
cat("- Tail concentration ratio > 3-4x → Strong tail dependence\n")
cat("- Tail concentration ratio 1.5-3x → Moderate tail dependence\n")
cat("- Tail concentration ratio < 1.5x → Weak/no tail dependence\n")
cat("- Chi plot > 0 as h→1 → Tail dependence (t-copula better)\n")
cat("- Chi plot → 0 as h→1 → No tail dependence (Frank better)\n\n")

cat("YOUR OBSERVATION: ________________________________\n\n")
cat("Press Enter to continue to Section 4...")
readline()

############################################################################
### SECTION 4: COMPARE COPULA DENSITIES
############################################################################
###
### GOAL: Fit all copulas and examine where each one assigns high
###       probability density.
###
### WHY THIS MATTERS: The copula that best matches the actual data
### density will have the highest log-likelihood.
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("SECTION 4: COMPARE COPULA FITS DIRECTLY\n")
cat("====================================================================\n\n")

cat("Fitting all copula families...\n\n")

pseudo_obs <- cbind(U, V)

# Fit Gaussian copula
cop_gauss <- normalCopula(dim = 2)
fit_gauss <- fitCopula(cop_gauss, pseudo_obs, method = "ml")
cop_gauss_fitted <- normalCopula(fit_gauss@estimate)

# Fit Frank copula
cop_frank <- frankCopula(dim = 2)
fit_frank <- fitCopula(cop_frank, pseudo_obs, method = "ml")
cop_frank_fitted <- frankCopula(fit_frank@estimate)

# Fit t-copula
cop_t <- tCopula(dim = 2, dispstr = "un")
fit_t <- fitCopula(cop_t, pseudo_obs, method = "ml")
cop_t_fitted <- tCopula(fit_t@estimate[1], df = fit_t@estimate[2], dispstr = "un")

cat("Fitted parameters:\n")
cat("  Gaussian: rho =", round(fit_gauss@estimate, 4), "\n")
cat("  Frank: theta =", round(fit_frank@estimate, 4), "\n")
cat("  t-copula: rho =", round(fit_t@estimate[1], 4), 
    ", df =", round(fit_t@estimate[2], 2), "\n\n")

# Evaluate densities at specific test points
# This shows where each copula assigns high/low probability
test_points <- expand.grid(
  u = c(0.05, 0.25, 0.50, 0.75, 0.95),
  v = c(0.05, 0.25, 0.50, 0.75, 0.95)
)

test_points$dens_gauss <- dCopula(as.matrix(test_points[,1:2]), cop_gauss_fitted)
test_points$dens_frank <- dCopula(as.matrix(test_points[,1:2]), cop_frank_fitted)
test_points$dens_t <- dCopula(as.matrix(test_points[,1:2]), cop_t_fitted)

# Calculate ratios
test_points$frank_vs_gauss <- test_points$dens_frank / test_points$dens_gauss
test_points$frank_vs_t <- test_points$dens_frank / test_points$dens_t

cat("Copula density comparisons at key points:\n")
cat("(Ratio > 1 means Frank has higher density)\n\n")
print(test_points[, c("u", "v", "dens_gauss", "dens_frank", "dens_t", 
                      "frank_vs_gauss", "frank_vs_t")])
cat("\n")

# Create visual comparison
pdf("debug_4_copula_densities.pdf", width=12, height=8)
par(mfrow=c(2,3))

# Contour plots of copula densities
u_grid <- seq(0.01, 0.99, length=50)
v_grid <- seq(0.01, 0.99, length=50)
grid_points <- expand.grid(u=u_grid, v=v_grid)

dens_gauss <- dCopula(as.matrix(grid_points), cop_gauss_fitted)
dens_frank <- dCopula(as.matrix(grid_points), cop_frank_fitted)
dens_t <- dCopula(as.matrix(grid_points), cop_t_fitted)

dens_gauss_mat <- matrix(dens_gauss, nrow=50, ncol=50)
dens_frank_mat <- matrix(dens_frank, nrow=50, ncol=50)
dens_t_mat <- matrix(dens_t, nrow=50, ncol=50)

contour(u_grid, v_grid, dens_gauss_mat, 
        main="Gaussian Copula Density",
        xlab="U", ylab="V", nlevels=10)

contour(u_grid, v_grid, dens_frank_mat,
        main="Frank Copula Density",
        xlab="U", ylab="V", nlevels=10)

contour(u_grid, v_grid, dens_t_mat,
        main="t-Copula Density",
        xlab="U", ylab="V", nlevels=10)

# Difference plots (Frank - others)
diff_frank_gauss <- dens_frank_mat - dens_gauss_mat
diff_frank_t <- dens_frank_mat - dens_t_mat

image(u_grid, v_grid, diff_frank_gauss,
      main="Frank - Gaussian\n(Red = Frank higher)",
      xlab="U", ylab="V",
      col=colorRampPalette(c("blue", "white", "red"))(20))
contour(u_grid, v_grid, diff_frank_gauss, add=TRUE, nlevels=5)

image(u_grid, v_grid, diff_frank_t,
      main="Frank - t\n(Red = Frank higher)",
      xlab="U", ylab="V",
      col=colorRampPalette(c("blue", "white", "red"))(20))
contour(u_grid, v_grid, diff_frank_t, add=TRUE, nlevels=5)

# Actual data overlay on Frank density
contour(u_grid, v_grid, dens_frank_mat,
        main="Actual Data on Frank Density",
        xlab="U", ylab="V", nlevels=10)
points(U[sample(length(U), 1000)], V[sample(length(V), 1000)],
       pch=20, cex=0.3, col=rgb(0,0,0,0.3))

dev.off()

cat("✓ Plot saved: debug_4_copula_densities.pdf\n\n")

cat("====================================================================\n")
cat("CHECKPOINT 4: Where does Frank fit better?\n")
cat("====================================================================\n\n")

cat("INTERPRETATION:\n")
cat("- Look at frank_vs_gauss and frank_vs_t ratios\n")
cat("- Ratios > 1.2 in corners (0.05, 0.95) → Frank overestimates tails\n")
cat("- Ratios > 1.2 in center (0.5, 0.5) → Frank better at central dependence\n")
cat("- Red regions in difference plots show where Frank assigns more density\n\n")

cat("YOUR OBSERVATION: ________________________________\n\n")
cat("Press Enter to continue to Section 5...")
readline()

############################################################################
### SECTION 5: LIKELIHOOD DECOMPOSITION BY REGION
############################################################################
###
### GOAL: Break down log-likelihood by regions of the distribution
###       to see WHERE Frank is gaining its advantage.
###
### WHY THIS MATTERS: If Frank wins mostly in the center, that's
### expected (Frank is more flexible there). If Frank wins in the
### tails, that's suspicious (Frank has no tail dependence).
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("SECTION 5: LIKELIHOOD DECOMPOSITION BY REGION\n")
cat("====================================================================\n\n")

cat("Computing log-likelihood contributions by region...\n\n")

# Define regions
center <- (U > 0.25 & U < 0.75) & (V > 0.25 & V < 0.75)
tails <- ((U < 0.1) | (U > 0.9)) & ((V < 0.1) | (V > 0.9))
moderate <- !(center | tails)

cat("Region sizes:\n")
cat("  Center (25-75%): n =", sum(center), 
    " (", round(100*mean(center), 1), "%)\n")
cat("  Tails (<10% or >90%): n =", sum(tails),
    " (", round(100*mean(tails), 1), "%)\n")
cat("  Moderate (rest): n =", sum(moderate),
    " (", round(100*mean(moderate), 1), "%)\n\n")

# Calculate log-likelihood by region
ll_gauss_center <- sum(dCopula(pseudo_obs[center,], cop_gauss_fitted, log=TRUE))
ll_gauss_tails <- sum(dCopula(pseudo_obs[tails,], cop_gauss_fitted, log=TRUE))
ll_gauss_moderate <- sum(dCopula(pseudo_obs[moderate,], cop_gauss_fitted, log=TRUE))
ll_gauss_total <- fit_gauss@loglik

ll_frank_center <- sum(dCopula(pseudo_obs[center,], cop_frank_fitted, log=TRUE))
ll_frank_tails <- sum(dCopula(pseudo_obs[tails,], cop_frank_fitted, log=TRUE))
ll_frank_moderate <- sum(dCopula(pseudo_obs[moderate,], cop_frank_fitted, log=TRUE))
ll_frank_total <- fit_frank@loglik

ll_t_center <- sum(dCopula(pseudo_obs[center,], cop_t_fitted, log=TRUE))
ll_t_tails <- sum(dCopula(pseudo_obs[tails,], cop_t_fitted, log=TRUE))
ll_t_moderate <- sum(dCopula(pseudo_obs[moderate,], cop_t_fitted, log=TRUE))
ll_t_total <- fit_t@loglik

# Create summary table
ll_summary <- data.frame(
  Region = c("Center", "Tails", "Moderate", "TOTAL"),
  Gaussian = c(ll_gauss_center, ll_gauss_tails, ll_gauss_moderate, ll_gauss_total),
  Frank = c(ll_frank_center, ll_frank_tails, ll_frank_moderate, ll_frank_total),
  t = c(ll_t_center, ll_t_tails, ll_t_moderate, ll_t_total)
)

ll_summary$Frank_vs_Gauss <- ll_summary$Frank - ll_summary$Gaussian
ll_summary$Frank_vs_t <- ll_summary$Frank - ll_summary$t

cat("Log-likelihood by region:\n")
print(ll_summary)
cat("\n")

cat("====================================================================\n")
cat("CHECKPOINT 5: Where does Frank gain its advantage?\n")
cat("====================================================================\n\n")

cat("INTERPRETATION:\n")
cat("- Frank winning in CENTER: Expected (Frank more flexible)\n")
cat("- Frank winning in TAILS: Suspicious (Frank has no tail dependence)\n")
cat("- Look at Frank_vs_Gauss and Frank_vs_t columns\n")
cat("- Positive values = Frank has higher likelihood in that region\n\n")

cat("Frank's total advantage over t:", 
    round(ll_frank_total - ll_t_total, 1), "\n")
cat("Frank's advantage in center:", 
    round(ll_frank_center - ll_t_center, 1),
    " (", round(100*(ll_frank_center - ll_t_center)/(ll_frank_total - ll_t_total), 1), "%)\n")
cat("Frank's advantage in tails:",
    round(ll_frank_tails - ll_t_tails, 1),
    " (", round(100*(ll_frank_tails - ll_t_tails)/(ll_frank_total - ll_t_total), 1), "%)\n\n")

cat("YOUR OBSERVATION: ________________________________\n\n")
cat("Press Enter to continue to Section 6...")
readline()

############################################################################
### SECTION 6: SIMULATE FROM FITTED COPULAS
############################################################################
###
### GOAL: Generate synthetic data from each fitted copula and compare
###       visually to the actual data.
###
### WHY THIS MATTERS: The "best" copula should produce simulations
### that look most like the real data.
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("SECTION 6: SIMULATE FROM FITTED COPULAS\n")
cat("====================================================================\n\n")

cat("Generating simulations from fitted copulas...\n\n")

set.seed(12345)
n_sim <- 5000

sim_gauss <- rCopula(n_sim, cop_gauss_fitted)
sim_frank <- rCopula(n_sim, cop_frank_fitted)
sim_t <- rCopula(n_sim, cop_t_fitted)

# Calculate correlations from simulations
cat("Kendall's tau comparison:\n")
cat("  Actual data:", round(cor(U, V, method="kendall"), 4), "\n")
cat("  Gaussian simulation:", round(cor(sim_gauss[,1], sim_gauss[,2], method="kendall"), 4), "\n")
cat("  Frank simulation:", round(cor(sim_frank[,1], sim_frank[,2], method="kendall"), 4), "\n")
cat("  t simulation:", round(cor(sim_t[,1], sim_t[,2], method="kendall"), 4), "\n\n")

pdf("debug_6_simulations.pdf", width=12, height=10)
par(mfrow=c(2,2))

# Actual data (subsample for clarity)
sample_idx <- sample(length(U), 5000)
plot(U[sample_idx], V[sample_idx],
     pch=20, cex=0.3, col=rgb(0,0,0,0.3),
     xlim=c(0,1), ylim=c(0,1),
     main="Actual Data",
     xlab="U (Prior)", ylab="V (Current)")
abline(0, 1, col="red", lty=2)
grid()

# Gaussian simulation
plot(sim_gauss[,1], sim_gauss[,2],
     pch=20, cex=0.3, col=rgb(0,0,1,0.3),
     xlim=c(0,1), ylim=c(0,1),
     main=paste0("Gaussian Simulation (tau = ", 
                 round(cor(sim_gauss[,1], sim_gauss[,2], method="kendall"), 3), ")"),
     xlab="U", ylab="V")
abline(0, 1, col="red", lty=2)
grid()

# Frank simulation
plot(sim_frank[,1], sim_frank[,2],
     pch=20, cex=0.3, col=rgb(0,0.5,0,0.3),
     xlim=c(0,1), ylim=c(0,1),
     main=paste0("Frank Simulation (tau = ",
                 round(cor(sim_frank[,1], sim_frank[,2], method="kendall"), 3), ")"),
     xlab="U", ylab="V")
abline(0, 1, col="red", lty=2)
grid()

# t-copula simulation
plot(sim_t[,1], sim_t[,2],
     pch=20, cex=0.3, col=rgb(1,0,0,0.3),
     xlim=c(0,1), ylim=c(0,1),
     main=paste0("t-Copula Simulation (tau = ",
                 round(cor(sim_t[,1], sim_t[,2], method="kendall"), 3), 
                 ", df = ", round(fit_t@estimate[2], 1), ")"),
     xlab="U", ylab="V")
abline(0, 1, col="red", lty=2)
grid()

dev.off()

cat("✓ Plot saved: debug_6_simulations.pdf\n\n")

cat("====================================================================\n")
cat("CHECKPOINT 6: Which simulation looks most like actual data?\n")
cat("====================================================================\n\n")

cat("INTERPRETATION:\n")
cat("- Compare corner clustering in simulations vs actual data\n")
cat("- All should have similar Kendall's tau\n")
cat("- Look for: Same degree of scatter in corners?\n")
cat("             Same overall cloud shape?\n\n")

cat("YOUR OBSERVATION: ________________________________\n\n")
cat("Press Enter to continue to Section 7...")
readline()

############################################################################
### SECTION 7: NON-SMOOTHED PSEUDO-OBSERVATIONS (CRITICAL TEST)
############################################################################
###
### GOAL: Refit copulas using simple empirical ranks instead of
###       I-spline smoothed pseudo-observations.
###
### WHY THIS IS THE MOST IMPORTANT TEST: If Frank still wins with
### simple ranks, then it's a genuine data feature. If Frank loses
### with simple ranks, then the I-spline smoothing is causing the issue.
###
############################################################################

cat("\n")
cat("====================================================================\n")
cat("SECTION 7: NON-SMOOTHED PSEUDO-OBSERVATIONS TEST\n")
cat("====================================================================\n\n")

cat("This is the CRITICAL test!\n\n")

cat("Refitting copulas using empirical ranks (no I-spline)...\n\n")

# Use simple empirical ranks - the most basic pseudo-observations
U_empirical <- rank(pairs_full$SCALE_SCORE_PRIOR) / (nrow(pairs_full) + 1)
V_empirical <- rank(pairs_full$SCALE_SCORE_CURRENT) / (nrow(pairs_full) + 1)

cat("Empirical rank summary:\n")
cat("  U range:", range(U_empirical), "\n")
cat("  V range:", range(V_empirical), "\n")
cat("  Empirical tau:", cor(U_empirical, V_empirical, method="kendall"), "\n\n")

# Fit copulas to empirical ranks
cat("Fitting Gaussian copula...\n")
cop_gauss_emp <- normalCopula(dim=2)
fit_gauss_emp <- fitCopula(cop_gauss_emp, cbind(U_empirical, V_empirical), method="ml")

cat("Fitting Frank copula...\n")
cop_frank_emp <- frankCopula(dim=2)
fit_frank_emp <- fitCopula(cop_frank_emp, cbind(U_empirical, V_empirical), method="ml")

cat("Fitting t-copula...\n")
cop_t_emp <- tCopula(dim=2, dispstr="un")
fit_t_emp <- fitCopula(cop_t_emp, cbind(U_empirical, V_empirical), method="ml")

cat("Fitting Clayton copula...\n")
cop_clay_emp <- claytonCopula(dim=2)
fit_clay_emp <- fitCopula(cop_clay_emp, cbind(U_empirical, V_empirical), method="ml")

cat("Fitting Gumbel copula...\n")
cop_gumb_emp <- gumbelCopula(dim=2)
fit_gumb_emp <- fitCopula(cop_gumb_emp, cbind(U_empirical, V_empirical), method="ml")

cat("\n")

# Create comparison table
empirical_results <- data.frame(
  Family = c("Gaussian", "Frank", "t", "Clayton", "Gumbel"),
  LogLik = c(fit_gauss_emp@loglik, fit_frank_emp@loglik, fit_t_emp@loglik,
             fit_clay_emp@loglik, fit_gumb_emp@loglik),
  AIC = c(-2*fit_gauss_emp@loglik + 2, 
          -2*fit_frank_emp@loglik + 2,
          -2*fit_t_emp@loglik + 4,  # t has 2 parameters
          -2*fit_clay_emp@loglik + 2,
          -2*fit_gumb_emp@loglik + 2),
  Tau = c(tau(fit_gauss_emp@copula), tau(fit_frank_emp@copula), 
          tau(fit_t_emp@copula), tau(fit_clay_emp@copula), 
          tau(fit_gumb_emp@copula))
)

empirical_results$Delta_AIC <- empirical_results$AIC - min(empirical_results$AIC)
empirical_results <- empirical_results[order(empirical_results$AIC), ]

cat("====================================================================\n")
cat("RESULTS: EMPIRICAL RANKS (NO I-SPLINE SMOOTHING)\n")
cat("====================================================================\n\n")

print(empirical_results)
cat("\n")

# Compare with I-spline results
ispline_results <- data.frame(
  Family = c("Gaussian", "Frank", "t"),
  LogLik = c(fit_gauss@loglik, fit_frank@loglik, fit_t@loglik),
  AIC = c(-2*fit_gauss@loglik + 2,
          -2*fit_frank@loglik + 2,
          -2*fit_t@loglik + 4)
)
ispline_results$Delta_AIC <- ispline_results$AIC - min(ispline_results$AIC)

cat("Comparison: I-spline vs Empirical Ranks\n")
cat("========================================\n\n")
cat("WITH I-SPLINE SMOOTHING:\n")
print(ispline_results)
cat("\n")
cat("WITHOUT I-SPLINE (EMPIRICAL RANKS):\n")
print(empirical_results)
cat("\n")

cat("====================================================================\n")
cat("CHECKPOINT 7: CRITICAL FINDING!\n")
cat("====================================================================\n\n")

cat("INTERPRETATION:\n")
cat("- If Frank STILL wins with empirical ranks:\n")
cat("  → Frank is the CORRECT model for this data\n")
cat("  → Educational data genuinely lacks tail dependence\n")
cat("  → This is a real scientific finding!\n\n")

cat("- If Frank LOSES with empirical ranks:\n")
cat("  → I-spline smoothing is removing tail dependence\n")
cat("  → Need to fix/improve I-spline approach\n")
cat("  → Consider using empirical ranks instead\n\n")

winner_ispline <- ispline_results$Family[1]
winner_empirical <- empirical_results$Family[1]

cat("Winner with I-spline:", winner_ispline, "\n")
cat("Winner with empirical ranks:", winner_empirical, "\n\n")

if (winner_ispline == winner_empirical && winner_ispline == "Frank") {
  cat("✓ CONCLUSION: Frank copula is genuinely the best model!\n")
  cat("  Educational assessment data lacks tail dependence.\n")
  cat("  This suggests students' relative positions are not stable\n")
  cat("  in the extreme tails - i.e., high and low performers\n")
  cat("  show more regression toward the mean than expected.\n\n")
} else if (winner_ispline == "Frank" && winner_empirical != "Frank") {
  cat("⚠ CONCLUSION: I-spline smoothing is causing Frank to win!\n")
  cat("  The smoothing is likely removing tail dependence structure.\n")
  cat("  Recommendation: Use empirical ranks or less aggressive smoothing.\n\n")
} else {
  cat("? INCONCLUSIVE: Results differ but Frank doesn't win with I-spline.\n")
  cat("  This is unexpected. Review both fitting procedures.\n\n")
}

cat("YOUR FINAL OBSERVATION: ________________________________\n\n")

############################################################################
### END OF DIAGNOSTIC
############################################################################

cat("\n")
cat("====================================================================\n")
cat("DIAGNOSTIC COMPLETE\n")
cat("====================================================================\n\n")

cat("Summary of generated files:\n")
cat("  1. debug_1_raw_scores.pdf\n")
cat("  2. debug_2_pseudo_observations.pdf\n")
cat("  3. debug_3_tail_dependence.pdf\n")
cat("  4. debug_4_copula_densities.pdf\n")
cat("  5. debug_6_simulations.pdf\n\n")

cat("Review all plots and your observations at each checkpoint.\n")
cat("The answer to 'Why does Frank win?' should now be clear!\n\n")

cat("====================================================================\n")

