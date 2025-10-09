# Insights Log

## 2025-10-08: Directory Restructuring Complete
- Organized analysis into 4 sequential steps
- Created comprehensive documentation (2,200+ lines)
- Established clear paper integration pathway
- Ready for EC2 execution and GitHub publication

## 2025-10-07: Experiment 5 Transformation Validation
- Tested 15 transformation methods
- Kernel Gaussian emerged as best "acceptable" method
- Discrete data prevents perfect uniformity (expected)
- Decision: Use kernel Gaussian for Phase 2 applications

## 2025-10-06: Two-Stage Transformation Methodology
- Discovered I-spline with insufficient knots causes Frank false positive
- Implemented two-stage approach:
  - Phase 1: Empirical ranks for family selection
  - Phase 2: Improved smoothing for applications
- Validated with debug_frank_dominance.R

## 2025-10-05: Critical Bug Fixes
- Gaussian copula tau calculation (was using rho instead of tau)
- Field naming in phase1_family_selection.R (tau vs kendall_tau)
- These bugs masked t-copula's true dominance

## Earlier: Framework Development
- Established I-spline framework with fixed reference
- Implemented copula bootstrap with FPC
- Created comprehensive diagnostic functions
