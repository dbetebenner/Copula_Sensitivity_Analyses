################################################################################
### INVESTIGATE: Does the 'ties' parameter cause identical p-values?
################################################################################

require(copula)

cat("====================================================================\n")
cat("INVESTIGATION: ties=TRUE parameter in gofCopula()\n")
cat("====================================================================\n\n")

cat("HYPOTHESIS: Large datasets with ties=TRUE may cause gofCopula()\n")
cat("to use the same bootstrap reference for all families.\n\n")

# Load data
cat("Loading data...\n")
load("Data/Copula_Sensitivity_Data_Set_2.Rdata")
source("functions/longitudinal_pairs.R")
require(data.table)

# Create pairs
pairs_data <- create_longitudinal_pairs(
  Copula_Sensitivity_Data_Set_2,
  content_prior = "MATHEMATICS",
  content_current = "MATHEMATICS",
  grade_prior = 4,
  grade_current = 5,
  year_prior = 2010,
  year_current = 2011
)

# Create pseudo-observations
n <- nrow(pairs_data)
U <- rank(pairs_data$SCALE_SCORE_PRIOR) / (n + 1)
V <- rank(pairs_data$SCALE_SCORE_CURRENT) / (n + 1)
pseudo_obs <- cbind(U, V)

cat("  Sample size: n =", n, "\n")
cat("  Checking for ties in pseudo_obs:\n")
cat("    U unique values:", length(unique(U)), "(should be", n, ")\n")
cat("    V unique values:", length(unique(V)), "(should be", n, ")\n")

if (length(unique(U)) < n || length(unique(V)) < n) {
  cat("\n✗ TIES DETECTED in pseudo-observations!\n")
  cat("This should NEVER happen with rank/(n+1) transformation.\n")
  cat("This indicates a bug in how pseudo_obs are created.\n\n")
} else {
  cat("\n✓ No ties in pseudo-observations (as expected)\n\n")
}

cat("====================================================================\n")
cat("TEST 1: Try with smaller subset (no ties possible)\n")
cat("====================================================================\n\n")

# Subset to n=1000 for speed
set.seed(123)
idx <- sample(1:n, 1000)
pseudo_obs_subset <- pseudo_obs[idx, ]

cat("Testing with n=1000 subset...\n\n")

families_to_test <- list(
  gaussian = normalCopula(dim = 2),
  clayton = claytonCopula(dim = 2),
  frank = frankCopula(dim = 2)
)

pvals_subset <- list()

for (fname in names(families_to_test)) {
  fit <- fitCopula(families_to_test[[fname]], pseudo_obs_subset, method = "ml")
  
  gof <- gofCopula(fit@copula, 
                   x = pseudo_obs_subset,
                   method = "Sn",
                   simulation = "pb",
                   N = 10,
                   verbose = FALSE)
  
  pvals_subset[[fname]] <- gof$p.value
  cat("  ", fname, "p-value:", gof$p.value, "\n")
}

cat("\nAre p-values identical with n=1000?:", length(unique(unlist(pvals_subset))) == 1, "\n\n")

cat("====================================================================\n")
cat("TEST 2: Try with full dataset but N=100 bootstraps\n")
cat("====================================================================\n\n")

cat("Testing with full n=28567, N=100 bootstraps...\n\n")

pvals_n100 <- list()

for (fname in names(families_to_test)) {
  fit <- fitCopula(families_to_test[[fname]], pseudo_obs, method = "ml")
  
  gof <- gofCopula(fit@copula, 
                   x = pseudo_obs,
                   method = "Sn",
                   simulation = "pb",
                   N = 100,
                   verbose = FALSE)
  
  pvals_n100[[fname]] <- gof$p.value
  cat("  ", fname, "p-value:", gof$p.value, "\n")
}

cat("\nAre p-values identical with N=100?:", length(unique(unlist(pvals_n100))) == 1, "\n\n")

cat("====================================================================\n")
cat("TEST 3: Check if sample size causes the issue\n")
cat("====================================================================\n\n")

sample_sizes <- c(100, 500, 1000, 5000, 10000)

cat("Testing different sample sizes with N=10 bootstraps...\n\n")

for (ss in sample_sizes) {
  idx <- sample(1:n, ss)
  pseudo_ss <- pseudo_obs[idx, ]
  
  # Fit gaussian only (for speed)
  fit_g <- fitCopula(normalCopula(dim = 2), pseudo_ss, method = "ml")
  fit_c <- fitCopula(claytonCopula(dim = 2), pseudo_ss, method = "ml")
  
  gof_g <- gofCopula(fit_g@copula, x = pseudo_ss, method = "Sn", 
                     simulation = "pb", N = 10, verbose = FALSE)
  gof_c <- gofCopula(fit_c@copula, x = pseudo_ss, method = "Sn", 
                     simulation = "pb", N = 10, verbose = FALSE)
  
  cat("  n =", sprintf("%5d", ss), "| Gaussian:", sprintf("%.4f", gof_g$p.value), 
      "| Clayton:", sprintf("%.4f", gof_c$p.value), 
      "| Same?:", gof_g$p.value == gof_c$p.value, "\n")
}

cat("\n====================================================================\n")
cat("CONCLUSION\n")
cat("====================================================================\n\n")

cat("If p-values are identical across families for large n but not small n,\n")
cat("then there's a bug in copula::gofCopula() with large sample sizes.\n\n")

cat("If they vary for ALL sample sizes in these tests, then the issue\n")
cat("is specific to our pipeline (how pseudo_obs are created/passed).\n\n")

