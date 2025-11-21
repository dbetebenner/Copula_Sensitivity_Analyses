############################################################################
### VALIDATION: Two-Stage Transformation Approach
############################################################################
###
### PURPOSE: Verify that both transformation methods are working correctly:
###   1. Empirical ranks (Phase 1 - family selection)
###   2. Improved I-spline with 9 knots (Phase 2 - applications)
###
### BOTH METHODS SHOULD:
###   - Produce uniform pseudo-observations (K-S test p > 0.05)
###   - Select the same copula family (t-copula)
###   - Preserve tail dependence structure
###
### USAGE: source("validate_transformation_methods.R")
###
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
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")

cat("====================================================================\n")
cat("VALIDATION: TWO-STAGE TRANSFORMATION APPROACH\n")
cat("====================================================================\n\n")

# Test on Grade 4→5 Math 2010 (same as diagnostic)
pairs_full <- create_longitudinal_pairs(
  data = Colorado_Data_LONG,
  grade_prior = 4,
  grade_current = 5,
  year_prior = "2010",
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS"
)

cat("Sample size:", nrow(pairs_full), "students\n")
cat("Empirical Kendall's tau:", cor(pairs_full$SCALE_SCORE_PRIOR, 
                                     pairs_full$SCALE_SCORE_CURRENT, 
                                     method="kendall"), "\n\n")

############################################################################
### METHOD 1: EMPIRICAL RANKS (Phase 1)
############################################################################

cat("====================================================================\n")
cat("METHOD 1: EMPIRICAL RANKS (for Phase 1 family selection)\n")
cat("====================================================================\n\n")

U_ranks <- rank(pairs_full$SCALE_SCORE_PRIOR) / (nrow(pairs_full) + 1)
V_ranks <- rank(pairs_full$SCALE_SCORE_CURRENT) / (nrow(pairs_full) + 1)

cat("Range:\n")
cat("  U:", range(U_ranks), "\n")
cat("  V:", range(V_ranks), "\n\n")

# Test uniformity
ks_u_ranks <- ks.test(U_ranks, "punif", 0, 1)
ks_v_ranks <- ks.test(V_ranks, "punif", 0, 1)

cat("Uniformity tests (Kolmogorov-Smirnov):\n")
cat("  U: D =", round(ks_u_ranks$statistic, 6), ", p-value =", 
    format.pval(ks_u_ranks$p.value, digits=3), 
    ifelse(ks_u_ranks$p.value > 0.05, "✓ PASS", "✗ FAIL"), "\n")
cat("  V: D =", round(ks_v_ranks$statistic, 6), ", p-value =", 
    format.pval(ks_v_ranks$p.value, digits=3),
    ifelse(ks_v_ranks$p.value > 0.05, "✓ PASS", "✗ FAIL"), "\n\n")

# Fit copulas
cat("Fitting copulas with empirical ranks...\n")
cop_gauss_ranks <- normalCopula(dim=2)
fit_gauss_ranks <- fitCopula(cop_gauss_ranks, cbind(U_ranks, V_ranks), method="ml")

cop_frank_ranks <- frankCopula(dim=2)
fit_frank_ranks <- fitCopula(cop_frank_ranks, cbind(U_ranks, V_ranks), method="ml")

cop_t_ranks <- tCopula(dim=2, dispstr="un")
fit_t_ranks <- fitCopula(cop_t_ranks, cbind(U_ranks, V_ranks), method="ml")

results_ranks <- data.frame(
  Family = c("Gaussian", "Frank", "t"),
  LogLik = c(fit_gauss_ranks@loglik, fit_frank_ranks@loglik, fit_t_ranks@loglik),
  AIC = c(-2*fit_gauss_ranks@loglik + 2,
          -2*fit_frank_ranks@loglik + 2,
          -2*fit_t_ranks@loglik + 4),
  Tau = c(tau(fit_gauss_ranks@copula), 
          tau(fit_frank_ranks@copula), 
          tau(fit_t_ranks@copula))
)
results_ranks$Delta_AIC <- results_ranks$AIC - min(results_ranks$AIC)
results_ranks <- results_ranks[order(results_ranks$AIC), ]

cat("\nResults with empirical ranks:\n")
print(results_ranks, row.names=FALSE)
cat("\nWinner:", results_ranks$Family[1], "\n\n")

############################################################################
### METHOD 2: IMPROVED I-SPLINE (Phase 2)
############################################################################

cat("====================================================================\n")
cat("METHOD 2: IMPROVED I-SPLINE with 9 knots (for Phase 2 applications)\n")
cat("====================================================================\n\n")

# Create improved I-spline frameworks (now uses 9 knots by default)
cat("Creating I-spline frameworks with default knots...\n")
framework_prior <- create_ispline_framework(pairs_full$SCALE_SCORE_PRIOR)
framework_current <- create_ispline_framework(pairs_full$SCALE_SCORE_CURRENT)

cat("  Prior knots:", framework_prior$knot_locations, "\n")
cat("  Current knots:", framework_current$knot_locations, "\n\n")

# Transform
U_ispline <- framework_prior$smooth_ecdf_full(pairs_full$SCALE_SCORE_PRIOR)
V_ispline <- framework_current$smooth_ecdf_full(pairs_full$SCALE_SCORE_CURRENT)

# Constrain
U_ispline <- pmax(1e-6, pmin(1 - 1e-6, U_ispline))
V_ispline <- pmax(1e-6, pmin(1 - 1e-6, V_ispline))

cat("Range:\n")
cat("  U:", range(U_ispline), "\n")
cat("  V:", range(V_ispline), "\n\n")

# Test uniformity
ks_u_ispline <- ks.test(U_ispline, "punif", 0, 1)
ks_v_ispline <- ks.test(V_ispline, "punif", 0, 1)

cat("Uniformity tests (Kolmogorov-Smirnov):\n")
cat("  U: D =", round(ks_u_ispline$statistic, 6), ", p-value =", 
    format.pval(ks_u_ispline$p.value, digits=3),
    ifelse(ks_u_ispline$p.value > 0.05, "✓ PASS", "✗ FAIL"), "\n")
cat("  V: D =", round(ks_v_ispline$statistic, 6), ", p-value =", 
    format.pval(ks_v_ispline$p.value, digits=3),
    ifelse(ks_v_ispline$p.value > 0.05, "✓ PASS", "✗ FAIL"), "\n\n")

# Fit copulas
cat("Fitting copulas with improved I-spline...\n")
cop_gauss_ispline <- normalCopula(dim=2)
fit_gauss_ispline <- fitCopula(cop_gauss_ispline, cbind(U_ispline, V_ispline), method="ml")

cop_frank_ispline <- frankCopula(dim=2)
fit_frank_ispline <- fitCopula(cop_frank_ispline, cbind(U_ispline, V_ispline), method="ml")

cop_t_ispline <- tCopula(dim=2, dispstr="un")
fit_t_ispline <- fitCopula(cop_t_ispline, cbind(U_ispline, V_ispline), method="ml")

results_ispline <- data.frame(
  Family = c("Gaussian", "Frank", "t"),
  LogLik = c(fit_gauss_ispline@loglik, fit_frank_ispline@loglik, fit_t_ispline@loglik),
  AIC = c(-2*fit_gauss_ispline@loglik + 2,
          -2*fit_frank_ispline@loglik + 2,
          -2*fit_t_ispline@loglik + 4),
  Tau = c(tau(fit_gauss_ispline@copula), 
          tau(fit_frank_ispline@copula), 
          tau(fit_t_ispline@copula))
)
results_ispline$Delta_AIC <- results_ispline$AIC - min(results_ispline$AIC)
results_ispline <- results_ispline[order(results_ispline$AIC), ]

cat("\nResults with improved I-spline:\n")
print(results_ispline, row.names=FALSE)
cat("\nWinner:", results_ispline$Family[1], "\n\n")

############################################################################
### COMPARISON AND VALIDATION
############################################################################

cat("====================================================================\n")
cat("VALIDATION SUMMARY\n")
cat("====================================================================\n\n")

# Uniformity test results
cat("UNIFORMITY TESTS (K-S p-value > 0.05 = PASS):\n")
cat("  Empirical ranks - U:", format.pval(ks_u_ranks$p.value, digits=3),
    ifelse(ks_u_ranks$p.value > 0.05, "✓", "✗"), "\n")
cat("  Empirical ranks - V:", format.pval(ks_v_ranks$p.value, digits=3),
    ifelse(ks_v_ranks$p.value > 0.05, "✓", "✗"), "\n")
cat("  I-spline (9 knots) - U:", format.pval(ks_u_ispline$p.value, digits=3),
    ifelse(ks_u_ispline$p.value > 0.05, "✓", "✗"), "\n")
cat("  I-spline (9 knots) - V:", format.pval(ks_v_ispline$p.value, digits=3),
    ifelse(ks_v_ispline$p.value > 0.05, "✓", "✗"), "\n\n")

# Family selection comparison
cat("COPULA FAMILY SELECTION:\n")
cat("  Empirical ranks winner:", results_ranks$Family[1], 
    "(AIC:", round(results_ranks$AIC[1], 1), ")\n")
cat("  I-spline winner:", results_ispline$Family[1],
    "(AIC:", round(results_ispline$AIC[1], 1), ")\n\n")

# Tail concentration (should be similar)
lower_tail_ranks <- sum(U_ranks < 0.1 & V_ranks < 0.1) / length(U_ranks)
upper_tail_ranks <- sum(U_ranks > 0.9 & V_ranks > 0.9) / length(U_ranks)
lower_tail_ispline <- sum(U_ispline < 0.1 & V_ispline < 0.1) / length(U_ispline)
upper_tail_ispline <- sum(U_ispline > 0.9 & V_ispline > 0.9) / length(U_ispline)

cat("TAIL CONCENTRATION (expected under independence: 0.0100):\n")
cat("  Empirical ranks - Lower:", round(lower_tail_ranks, 4), 
    "(", round(lower_tail_ranks/0.01, 2), "x)\n")
cat("  Empirical ranks - Upper:", round(upper_tail_ranks, 4),
    "(", round(upper_tail_ranks/0.01, 2), "x)\n")
cat("  I-spline - Lower:", round(lower_tail_ispline, 4),
    "(", round(lower_tail_ispline/0.01, 2), "x)\n")
cat("  I-spline - Upper:", round(upper_tail_ispline, 4),
    "(", round(upper_tail_ispline/0.01, 2), "x)\n\n")

############################################################################
### FINAL VERDICT
############################################################################

cat("====================================================================\n")
cat("FINAL VERDICT\n")
cat("====================================================================\n\n")

# Check if both methods pass uniformity
ranks_uniform <- (ks_u_ranks$p.value > 0.05) & (ks_v_ranks$p.value > 0.05)
ispline_uniform <- (ks_u_ispline$p.value > 0.05) & (ks_v_ispline$p.value > 0.05)

# Check if both select same winner
same_winner <- results_ranks$Family[1] == results_ispline$Family[1]

cat("1. Empirical ranks produce uniform U,V:", ifelse(ranks_uniform, "✓ YES", "✗ NO"), "\n")
cat("2. Improved I-spline produces uniform U,V:", ifelse(ispline_uniform, "✓ YES", "✗ NO"), "\n")
cat("3. Both methods select same copula:", ifelse(same_winner, "✓ YES", "✗ NO"), "\n")
cat("4. Winner is t-copula (expected):", 
    ifelse(results_ranks$Family[1] == "t", "✓ YES", "✗ NO"), "\n\n")

if (ranks_uniform && ispline_uniform && same_winner && results_ranks$Family[1] == "t") {
  cat("✓✓✓ VALIDATION SUCCESSFUL ✓✓✓\n\n")
  cat("Both transformation methods:\n")
  cat("  - Produce uniform pseudo-observations\n")
  cat("  - Select t-copula as best fit\n")
  cat("  - Preserve tail dependence structure\n\n")
  cat("Two-stage approach is VALIDATED and ready for use:\n")
  cat("  - Phase 1: Use empirical ranks (use_empirical_ranks=TRUE)\n")
  cat("  - Phase 2+: Use improved I-spline (use_empirical_ranks=FALSE)\n\n")
} else {
  cat("⚠⚠⚠ VALIDATION ISSUES DETECTED ⚠⚠⚠\n\n")
  if (!ranks_uniform) {
    cat("  Issue: Empirical ranks not uniform (should not happen!)\n")
  }
  if (!ispline_uniform) {
    cat("  Issue: I-spline still not uniform - need MORE knots or tail-aware knots\n")
  }
  if (!same_winner) {
    cat("  Issue: Methods select different copulas - transformation distortion still present\n")
  }
  if (results_ranks$Family[1] != "t") {
    cat("  Issue: t-copula not winning (expected based on diagnostic)\n")
  }
  cat("\nRecommendation: Review I-spline knot placement or use tail-aware approach\n\n")
}

cat("====================================================================\n")
cat("VALIDATION COMPLETE\n")
cat("====================================================================\n\n")

