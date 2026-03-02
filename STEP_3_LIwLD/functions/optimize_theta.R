############################################################################
###
### Legacy Compatibility Shim
###
### This file is kept temporarily so older scripts that source
### optimize_theta.R continue to work. The primary implementation
### now lives in optimize_regime.R.
###
############################################################################

this_dir <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile)),
  error = function(e) "."
)
source(file.path(this_dir, "optimize_regime.R"))
