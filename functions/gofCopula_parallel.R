################################################################################
# Parallel Bootstrap for copula::gofCopula()
################################################################################
#
# Purpose: Override copula package's sequential bootstrap with parallel version
# Usage: source("functions/gofCopula_parallel.R") before calling gofCopula()
#
# Changes from copula v1.1-6:
#   - Added 'cores' parameter to .gofPB() and gofCopula()
#   - Parallel bootstrap using parSapply() when cores > 1
#   - Auto-detects FORK (Unix) vs PSOCK (Windows) clusters
#   - 100% backward compatible (cores=NULL → sequential)
#
################################################################################

# Load required package
library(parallel)

# Source the modified gofCopula.R from the forked package
source("/Users/conet/GitHub/DBetebenner/copula/main/R/gofCopula.R")

cat("✓ Parallel gofCopula() loaded successfully\n")
cat("  Usage: gofCopula(..., cores=46) for parallel bootstrap\n")
cat("  Usage: gofCopula(..., cores=NULL) for sequential (default)\n\n")

