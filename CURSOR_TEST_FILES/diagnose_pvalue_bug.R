################################################################################
### DIAGNOSTIC: Why are all p-values identical?
################################################################################

cat("====================================================================\n")
cat("DIAGNOSTIC: Investigating identical p-value bug\n")
cat("====================================================================\n\n")

# Load functions
source("functions/longitudinal_pairs.R")
source("functions/ispline_ecdf.R")
source("functions/copula_bootstrap.R")
require(data.table)
require(copula)

# Small dataset for speed
set.seed(123)
n <- 1000
u <- runif(n)
v <- u^0.7 + rnorm(n, 0, 0.1)
v <- pnorm((v - mean(v)) / sd(v))  # Transform to uniform
pseudo_obs <- cbind(u, v)

cat("Test data: n =", n, "\n")
cat("Kendall's tau:", cor(u, v, method = "kendall"), "\n\n")

# Test each family individually with detailed output
families_to_test <- c("gaussian", "clayton", "gumbel", "frank")

results <- list()

for (fam in families_to_test) {
  cat("--------------------------------------------------------------------\n")
  cat("Testing:", fam, "\n")
  cat("--------------------------------------------------------------------\n")
  
  # Create copula
  cop <- switch(fam,
    gaussian = normalCopula(dim = 2),
    clayton = claytonCopula(dim = 2),
    gumbel = gumbelCopula(dim = 2),
    frank = frankCopula(dim = 2)
  )
  
  # Fit copula
  fit <- fitCopula(cop, pseudo_obs, method = "ml")
  cat("  Fitted parameter:", coef(fit), "\n")
  
  # Run GoF with N=10
  set.seed(999)  # Same seed for each to see if that's the issue
  gof_result <- gofCopula(fit@copula, 
                          x = pseudo_obs,
                          method = "Sn",
                          simulation = "pb",
                          N = 10,
                          verbose = FALSE)
  
  cat("  GoF statistic:", gof_result$statistic, "\n")
  cat("  GoF p-value:", gof_result$p.value, "\n")
  
  results[[fam]] <- list(
    statistic = gof_result$statistic,
    pvalue = gof_result$p.value
  )
  
  cat("\n")
}

cat("====================================================================\n")
cat("SUMMARY: Are p-values identical?\n")
cat("====================================================================\n")

pvalues <- sapply(results, function(x) x$pvalue)
statistics <- sapply(results, function(x) x$statistic)

cat("\nP-values:\n")
print(pvalues)

cat("\nTest statistics:\n")
print(statistics)

cat("\nAre all p-values identical?:", length(unique(pvalues)) == 1, "\n")

if (length(unique(pvalues)) == 1) {
  cat("\n**BUG CONFIRMED**: All p-values are identical!\n")
  cat("This suggests the bootstrap is not running properly.\n")
  cat("Possible causes:\n")
  cat("  1. Random seed not advancing between families\n")
  cat("  2. Bootstrap samples being cached/reused\n")
  cat("  3. Bug in gofCopula() with small N\n")
  cat("\nTrying with N=100 to see if issue persists...\n\n")
  
  # Retry with N=100
  results_n100 <- list()
  for (fam in families_to_test) {
    cop <- switch(fam,
      gaussian = normalCopula(dim = 2),
      clayton = claytonCopula(dim = 2),
      gumbel = gumbelCopula(dim = 2),
      frank = frankCopula(dim = 2)
    )
    
    fit <- fitCopula(cop, pseudo_obs, method = "ml")
    set.seed(999)
    gof_result <- gofCopula(fit@copula, 
                            x = pseudo_obs,
                            method = "Sn",
                            simulation = "pb",
                            N = 100,
                            verbose = FALSE)
    
    results_n100[[fam]] <- gof_result$p.value
  }
  
  pvalues_n100 <- unlist(results_n100)
  cat("P-values with N=100:\n")
  print(pvalues_n100)
  cat("\nAre all p-values identical with N=100?:", length(unique(pvalues_n100)) == 1, "\n")
}

cat("\n====================================================================\n")
cat("NOW TESTING WITHOUT set.seed() (let it vary naturally)\n")
cat("====================================================================\n\n")

results_noseed <- list()
for (fam in families_to_test) {
  cop <- switch(fam,
    gaussian = normalCopula(dim = 2),
    clayton = claytonCopula(dim = 2),
    gumbel = gumbelCopula(dim = 2),
    frank = frankCopula(dim = 2)
  )
  
  fit <- fitCopula(cop, pseudo_obs, method = "ml")
  # NO set.seed() here - let each family use different random draws
  gof_result <- gofCopula(fit@copula, 
                          x = pseudo_obs,
                          method = "Sn",
                          simulation = "pb",
                          N = 10,
                          verbose = FALSE)
  
  results_noseed[[fam]] <- gof_result$p.value
}

pvalues_noseed <- unlist(results_noseed)
cat("P-values without fixed seed:\n")
print(pvalues_noseed)
cat("\nAre all p-values identical without seed?:", length(unique(pvalues_noseed)) == 1, "\n")

cat("\n====================================================================\n")
cat("CONCLUSION\n")
cat("====================================================================\n")
if (length(unique(pvalues_noseed)) > 1) {
  cat("\n✓ FOUND THE BUG!\n")
  cat("When random seed is NOT fixed, p-values vary correctly.\n")
  cat("This means somewhere in the pipeline, set.seed() is being called\n")
  cat("and causing the same bootstrap samples to be generated.\n\n")
  cat("SOLUTION: Check for any set.seed() calls in:\n")
  cat("  - functions/copula_bootstrap.R\n")
  cat("  - functions/longitudinal_pairs.R\n") 
  cat("  - STEP_1_Family_Selection/phase1_family_selection_parallel.R\n")
  cat("  - Remove or comment out any set.seed() calls\n")
} else {
  cat("\n✗ ISSUE PERSISTS even without fixed seed\n")
  cat("This suggests a deeper bug in gofCopula() or our usage of it.\n")
}

cat("\n")

