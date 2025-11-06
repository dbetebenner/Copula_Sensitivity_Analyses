# Debugging History Archive

This folder contains diagnostic scripts and documentation from debugging the GoF (Goodness-of-Fit) testing implementation between October-November 2025.

## The Problem We Solved

When initially implementing GoF testing, we encountered a bug where **all copula families returned identical p-values** (0.0455) when using `copula::gofCopula()` with parametric bootstrap. This made it impossible to meaningfully assess model fit.

## Debugging Journey

### Phase 1: Identifying the Issue
- **File:** `diagnose_pvalue_bug.R`
- Discovered that `copula::gofCopula()` with large n + many ties + parametric bootstrap produced identical p-values across all families
- Suspected the bootstrap mechanism was not properly resampling

### Phase 2: Deep Investigation
- **Files:** `diagnose_gofCopula_internals.R`, `investigate_ties_parameter.R`
- Investigated whether ties in discrete test scores were causing the issue
- Tested different approaches to breaking ties
- Discovered the bug was deeper in the `copula` package's bootstrap code

### Phase 3: Workaround Attempts
- **Files:** `verify_pobs_fix.R`, `test_gofCopula_integration.R`
- Tried using `copula::pobs()` for better pseudo-observations
- Added jitter (±0.01) to break ties - THIS WORKED but was a hack
- **Result:** Jitter fixed the immediate problem but was not a clean solution

### Phase 4: Alternative Tests
- **File:** `debug_asymptotic_call.R`
- Tested asymptotic GoF tests (N=0) to avoid bootstrap entirely
- Found these were faster but potentially less accurate

### Phase 5: Better Solution - Switch Packages
- **Files:** `test_gofCopula_package.R`, `test_gofCopula_package_install.R`, `test_gofCopula_quick.R`
- Discovered `gofCopula` package (SimonTrimborn/gofCopula on GitHub)
- Found it used Kendall's transformation-based tests (different mechanism)
- Discovered bugs in that package for t-copulas (`'length = 2' in coercion to 'logical(1)'`)

### Phase 6: Final Solution
- **Fixed bugs in `gofCopula` package:**
  - `internal_est_margin_param.R` (line 355-356)
  - `internal_param_est.R` (line 312-313)
  - Bug: `||` operator on vector comparisons for t-copula parameters
  - Fix: Wrap each comparison in `any()` before `||`

- **Result:** Clean, robust GoF testing without workarounds!

## Final Implementation (November 2025)

### What We Use Now:
- **Package:** `gofCopula` (GitHub: SimonTrimborn/gofCopula) version ≥ 0.4.4 (with our fixes)
- **Test:** `gofKendallCvM()` - Kendall's transformation-based Cramér-von Mises test
- **Bootstrap:** M=1000 for production (parametric bootstrap)
- **Pseudo-observations:** `copula::pobs()` with `ties.method="average"` (NO jitter needed!)

### Why It Works:
1. Kendall's transformation test is robust to ties
2. Different bootstrap mechanism than `copula::gofCopula()`
3. Fixed parameter boundary checking for t-copulas
4. No workarounds or hacks required

## Key Documentation

### Comprehensive Investigation:
- **`POBS_INVESTIGATION_COMPLETE.md`** - Full analysis of pseudo-observations, ties, and the p-value bug

### Bug Fixes:
- See `/Users/conet/GitHub/DBetebenner/gofCopula/main/BUGFIX_SUMMARY.md` for complete documentation of the fixes applied to the `gofCopula` package

## Lessons Learned

1. **Don't trust package internals blindly** - Both `copula::gofCopula()` and the original `gofCopula` package had bugs
2. **Jitter is a red flag** - If you need to add jitter to make something work, there's probably a deeper issue
3. **Test extensively** - We created dozens of diagnostic scripts to isolate the problem
4. **Document the journey** - This archive shows future users what we tried and why
5. **Fix upstream when possible** - We fixed bugs in `gofCopula` package rather than work around them

## Files in This Archive

### Diagnostic Scripts:
- `diagnose_pvalue_bug.R` - Initial investigation of identical p-values
- `diagnose_gofCopula_internals.R` - Deep dive into bootstrap mechanism
- `investigate_ties_parameter.R` - Testing tie-handling approaches
- `verify_pobs_fix.R` - Verification of pobs() approach
- `debug_asymptotic_call.R` - Testing asymptotic tests

### Integration Tests:
- `test_gofCopula_integration.R` - Full integration test
- `test_gofCopula_package.R` - Testing gofCopula package capabilities
- `test_gofCopula_package_install.R` - Installation and setup testing
- `test_gofCopula_quick.R` - Quick verification tests

### Documentation:
- `POBS_INVESTIGATION_COMPLETE.md` - Comprehensive investigation summary
- `README.md` (this file) - Overview of debugging journey

## Current Production Files (Not in Archive)

These files are still actively used:
- `test_gofCopula_fix.R` - Tests the fixed gofCopula package
- `test_gofCopula_ultrafast.R` - Quick M=10 test for validation
- `test_manual_M100.R` - Realistic M=100 timing test
- `run_test_ultrafast_single.R` - Single-condition test

---

**Last Updated:** November 4, 2025

**Status:** ✅ RESOLVED - Clean implementation with no workarounds

**Key Insight:** Sometimes the best fix is to fix the upstream package, not work around it.

