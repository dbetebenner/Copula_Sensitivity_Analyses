################################################################################
### TEST: What does the gofCopula PACKAGE support?
### NOTE: This is the GitHub package, NOT copula::gofCopula()
################################################################################

cat("====================================================================\n")
cat("TESTING: gofCopula Package Capabilities\n")
cat("====================================================================\n\n")

# Install if needed
if (!requireNamespace("devtools", quietly = TRUE)) {
  install.packages("devtools")
}

cat("Installing gofCopula package from GitHub...\n")
tryCatch({
  devtools::install_github("SimonTrimborn/gofCopula", quiet = TRUE)
  cat("✓ Installation successful\n\n")
}, error = function(e) {
  cat("✗ Installation failed:", e$message, "\n\n")
  quit(save = "no", status = 1)
})

# Load packages
library(gofCopula)  # The GitHub package
library(copula)     # For data generation
library(data.table)

cat("====================================================================\n")
cat("PACKAGE INFO\n")
cat("====================================================================\n\n")

cat("gofCopula package loaded\n")
cat("Available functions:\n")
print(ls("package:gofCopula"))
cat("\n")

cat("====================================================================\n")
cat("TEST DATA SETUP\n")
cat("====================================================================\n\n")

# Create realistic test data (smaller n for speed)
set.seed(123)
n <- 1000
cop_true <- normalCopula(0.7, dim = 2)
test_data <- rCopula(n, cop_true)

cat("Test data: n =", n, "bivariate observations\n")
cat("True copula: Gaussian with rho = 0.7\n\n")

cat("====================================================================\n")
cat("TEST 1: Available Copula Types\n")
cat("====================================================================\n\n")

# Check what copula types are documented
cat("Checking ?gofKendallCvM for supported copula types...\n\n")

cat("====================================================================\n")
cat("TEST 2: Test Each Copula Family\n")
cat("====================================================================\n\n")

# Map our family names to what gofCopula might expect
families_to_test <- list(
  gaussian = c("normal", "gaussian", "gauss"),
  t = c("t", "student"),
  clayton = c("clayton"),
  gumbel = c("gumbel"),
  frank = c("frank"),
  comonotonic = c("comonotonic", "M", "upper")
)

results <- list()

for (our_fam in names(families_to_test)) {
  cat("Testing:", our_fam, "\n")
  
  worked <- FALSE
  for (test_name in families_to_test[[our_fam]]) {
    cat("  Trying name:", test_name, "... ")
    
    result <- tryCatch({
      
      # SPECIAL HANDLING: T-copula has 2 parameters (rho, df)
      # param.est = TRUE causes issues, so pre-fit and pass parameters
      if (test_name == "t") {
        cat("(pre-fitting t-copula) ")
        t_cop <- tCopula(dim = 2)
        t_fit <- fitCopula(t_cop, test_data, method = "ml")
        
        gof_result <- gofKendallCvM(
          copula = "t",
          x = test_data,
          M = 10,
          param = coef(t_fit),      # Pass fitted params: c(rho, df)
          param.est = FALSE,         # Don't re-estimate
          margins = "ranks"
        )
      } else {
        # Standard approach for other families
        gof_result <- gofKendallCvM(
          copula = test_name,
          x = test_data,
          M = 10,
          param.est = TRUE,
          margins = "ranks"
        )
      }
      
      cat("✓ WORKS\n")
      
      results[[our_fam]] <- list(
        tested_name = test_name,
        works = TRUE,
        error = NA,
        stat = gof_result$statistic,
        pval = gof_result$p.value
      )
      
      worked <- TRUE
      TRUE  # Return TRUE to break loop
      
    }, error = function(e) {
      cat("✗ FAILED:", e$message, "\n")
      FALSE
    })
    
    # If one name works, no need to test others
    if (worked) break
  }
  
  # If no name worked, record the failure
  if (!worked) {
    results[[our_fam]] <- list(
      tested_name = NA,
      works = FALSE,
      error = "All names failed",
      stat = NA,
      pval = NA
    )
  }
  
  cat("\n")
}

cat("====================================================================\n")
cat("SUMMARY: What Works?\n")
cat("====================================================================\n\n")

working_families <- names(results)[sapply(results, function(x) x$works)]
failed_families <- names(results)[sapply(results, function(x) !x$works)]

if (length(working_families) > 0) {
  cat("Copula families that WORK with gofKendallCvM:\n\n")
  for (fam in working_families) {
    r <- results[[fam]]
    cat("  ✓", fam, "- use name:", r$tested_name, "\n")
    
    # Safe printing with checks for numeric values
    cat("     Statistic: ")
    if (is.numeric(r$stat) && !is.na(r$stat)) {
      cat(round(r$stat, 6))
    } else {
      cat("<not available>")
    }
    
    cat(" | p-value: ")
    if (is.numeric(r$pval) && !is.na(r$pval)) {
      cat(round(r$pval, 4), "\n")
    } else {
      cat("<not available>\n")
    }
  }
} else {
  cat("✗ NO families worked!\n")
}

cat("\n")

if (length(failed_families) > 0) {
  cat("Copula families that FAILED:\n\n")
  for (fam in failed_families) {
    r <- results[[fam]]
    cat("  ✗", fam, "\n")
    if (!is.na(r$error)) {
      cat("     Error:", r$error, "\n")
    }
  }
}

cat("\n====================================================================\n")
cat("RECOMMENDATION\n")
cat("====================================================================\n\n")

if (length(working_families) >= 5) {
  cat("✓✓✓ EXCELLENT! gofCopula package supports most/all families\n\n")
  cat("RECOMMENDED MAPPING:\n")
  for (fam in working_families) {
    r <- results[[fam]]
    cat("  ", fam, "->", r$tested_name, "\n")
  }
  cat("\n")
  cat("Use gofKendallCvM() as the primary GoF test for all supported families.\n")
} else if (length(working_families) > 0) {
  cat("⚠️  PARTIAL: Some families work, others need fallback\n\n")
  cat("Use gofCopula package for:", paste(working_families, collapse = ", "), "\n")
  cat("Need fallback for:", paste(failed_families, collapse = ", "), "\n")
} else {
  cat("✗ FAILED: gofCopula package doesn't work with our data\n\n")
  cat("May need to stick with copula::gofCopula() or custom implementations\n")
}

cat("\n")

