############################################################################
### DIAGNOSTIC: Check Copula Fitting and Pseudo-Observations
### Purpose: Verify copula fits are working correctly after bug fixes
############################################################################

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
source("../functions/copula_bootstrap.R")

cat("====================================================================\n")
cat("DIAGNOSTIC: COPULA FITTING VERIFICATION\n")
cat("====================================================================\n\n")

# Get one condition for testing (Grade 4→5, Math, 2010)
pairs_full <- create_longitudinal_pairs(
  data = Colorado_Data_LONG,
  grade_prior = 4,
  grade_current = 5,
  year_prior = "2010",
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS"
)

cat("Sample size:", nrow(pairs_full), "\n")
cat("Prior range:", range(pairs_full$SCALE_SCORE_PRIOR), "\n")
cat("Current range:", range(pairs_full$SCALE_SCORE_CURRENT), "\n\n")

# Create I-spline frameworks
framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)

# Transform to pseudo-observations
U <- framework_prior$smooth_ecdf_full(pairs_full$SCALE_SCORE_PRIOR)
V <- framework_current$smooth_ecdf_full(pairs_full$SCALE_SCORE_CURRENT)

# Constrain to (0,1)
U <- pmax(1e-6, pmin(1 - 1e-6, U))
V <- pmax(1e-6, pmin(1 - 1e-6, V))

cat("Pseudo-observations summary:\n")
cat("  U range:", range(U), "\n")
cat("  V range:", range(V), "\n")
cat("  Empirical tau:", cor(U, V, method = "kendall"), "\n\n")

# Plot pseudo-observations
pdf("diagnostic_pseudo_obs.pdf", width = 8, height = 8)
par(mfrow = c(2, 2))

# Main scatter plot
plot(U, V, pch = 20, cex = 0.3, col = rgb(0, 0, 0, 0.3),
     main = "Pseudo-Observations (U,V)",
     xlab = "U (Prior)", ylab = "V (Current)")
abline(0, 1, col = "red", lty = 2)
grid()

# Marginal histograms
hist(U, breaks = 50, main = "Marginal: U (Prior)", 
     xlab = "U", col = "lightblue", border = "white")
abline(v = c(0, 1), col = "red", lty = 2)

hist(V, breaks = 50, main = "Marginal: V (Current)", 
     xlab = "V", col = "lightgreen", border = "white")
abline(v = c(0, 1), col = "red", lty = 2)

# Tail concentration
plot(U, V, pch = 20, cex = 0.5, col = rgb(0, 0, 0, 0.5),
     xlim = c(0, 0.2), ylim = c(0, 0.2),
     main = "Lower Tail (Zoom)",
     xlab = "U (Prior)", ylab = "V (Current)")
abline(0, 1, col = "red", lty = 2)
grid()

dev.off()
cat("✓ Plot saved to: diagnostic_pseudo_obs.pdf\n\n")

############################################################################
### TEST COPULA FITTING DIRECTLY
############################################################################

cat("====================================================================\n")
cat("TESTING COPULA FITTING\n")
cat("====================================================================\n\n")

pseudo_obs <- cbind(U, V)

# Test each copula family
cat("GAUSSIAN COPULA:\n")
cop_gauss <- normalCopula(dim = 2)
fit_gauss <- fitCopula(cop_gauss, pseudo_obs, method = "ml")
cat("  Parameter (rho):", fit_gauss@estimate, "\n")
cat("  Kendall's tau (tau(copula)):", tau(fit_gauss@copula), "\n")
cat("  Kendall's tau (cor method):", cor(U, V, method = "kendall"), "\n")
cat("  Log-likelihood:", fit_gauss@loglik, "\n")
cat("  AIC:", -2 * fit_gauss@loglik + 2, "\n\n")

cat("FRANK COPULA:\n")
cop_frank <- frankCopula(dim = 2)
fit_frank <- fitCopula(cop_frank, pseudo_obs, method = "ml")
cat("  Parameter (theta):", fit_frank@estimate, "\n")
cat("  Kendall's tau (tau(copula)):", tau(fit_frank@copula), "\n")
cat("  Kendall's tau (from theta formula):", 
    1 - 4/fit_frank@estimate * (1 - copula::debye1(fit_frank@estimate)), "\n")
cat("  Log-likelihood:", fit_frank@loglik, "\n")
cat("  AIC:", -2 * fit_frank@loglik + 2, "\n\n")

cat("T-COPULA:\n")
cop_t <- tCopula(dim = 2, dispstr = "un")
fit_t <- fitCopula(cop_t, pseudo_obs, method = "ml")
cat("  Parameter (rho):", fit_t@estimate[1], "\n")
cat("  Degrees of freedom:", fit_t@estimate[2], "\n")
cat("  Kendall's tau (tau(copula)):", tau(fit_t@copula), "\n")
cat("  Log-likelihood:", fit_t@loglik, "\n")
cat("  AIC:", -2 * fit_t@loglik + 2 * 2, "\n\n")

cat("CLAYTON COPULA:\n")
cop_clay <- claytonCopula(dim = 2)
fit_clay <- fitCopula(cop_clay, pseudo_obs, method = "ml")
cat("  Parameter (theta):", fit_clay@estimate, "\n")
cat("  Kendall's tau (tau(copula)):", tau(fit_clay@copula), "\n")
cat("  Kendall's tau (from formula):", fit_clay@estimate / (fit_clay@estimate + 2), "\n")
cat("  Log-likelihood:", fit_clay@loglik, "\n")
cat("  AIC:", -2 * fit_clay@loglik + 2, "\n\n")

cat("GUMBEL COPULA:\n")
cop_gumb <- gumbelCopula(dim = 2)
fit_gumb <- fitCopula(cop_gumb, pseudo_obs, method = "ml")
cat("  Parameter (theta):", fit_gumb@estimate, "\n")
cat("  Kendall's tau (tau(copula)):", tau(fit_gumb@copula), "\n")
cat("  Kendall's tau (from formula):", 1 - 1/fit_gumb@estimate, "\n")
cat("  Log-likelihood:", fit_gumb@loglik, "\n")
cat("  AIC:", -2 * fit_gumb@loglik + 2, "\n\n")

cat("====================================================================\n")
cat("COMPARISON SUMMARY\n")
cat("====================================================================\n\n")

results_compare <- data.frame(
  Family = c("Gaussian", "Frank", "t", "Clayton", "Gumbel"),
  LogLik = c(fit_gauss@loglik, fit_frank@loglik, fit_t@loglik, 
             fit_clay@loglik, fit_gumb@loglik),
  AIC = c(-2*fit_gauss@loglik + 2, -2*fit_frank@loglik + 2, 
          -2*fit_t@loglik + 4, -2*fit_clay@loglik + 2, 
          -2*fit_gumb@loglik + 2),
  Tau = c(tau(fit_gauss@copula), tau(fit_frank@copula), tau(fit_t@copula),
          tau(fit_clay@copula), tau(fit_gumb@copula))
)

results_compare$Delta_AIC <- results_compare$AIC - min(results_compare$AIC)
results_compare <- results_compare[order(results_compare$AIC), ]

print(results_compare)

cat("\n====================================================================\n")
cat("EXPECTED RESULTS:\n")
cat("====================================================================\n")
cat("- All copulas should report similar Kendall's tau (~0.85-0.90)\n")
cat("- t-copula or Gaussian should have best AIC (not Frank)\n")
cat("- AIC differences should be small (< 100), not thousands\n")
cat("- Frank parameter (theta) should be moderate (5-15 range)\n\n")

cat("Best family by AIC:", results_compare$Family[1], "\n")
cat("Second best:", results_compare$Family[2], "\n")
cat("Difference:", results_compare$Delta_AIC[2], "\n\n")

if (results_compare$Family[1] == "Frank" && results_compare$Delta_AIC[2] > 1000) {
  cat("⚠️  WARNING: Frank copula still dominating with large AIC advantage.\n")
  cat("    This suggests the bug fixes may not be working correctly.\n")
  cat("    Please review the copula fitting code.\n\n")
} else {
  cat("✓ Results look reasonable! Frank is not dominating.\n\n")
}

cat("====================================================================\n")
cat("DIAGNOSTIC COMPLETE\n")
cat("====================================================================\n\n")

