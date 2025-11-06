# Parallel gofCopula Implementation Plan

## Assessment Summary

**HIGHLY FEASIBLE** - The copula package's `gofCopula()` function has a simple, sequential bootstrap loop that is **trivial to parallelize**.

## Key Findings

### Current Implementation (copula v1.1.6)

File: `copula:::.gofPB` (internal function)
Bootstrap loop: Lines 67-97
Method: `vapply(1:N, function(k) {...}, NA_real_)`

**Structure**:
```r
T0 <- vapply(1:N, function(k) {
  U <- rCopula(n, C.th.n)              # 1. Simulate
  Uhat <- pobs(U, ties.method)         # 2. Pseudo-obs
  C.th.n. <- fitCopula(...)@copula     # 3. Refit
  T0. <- gofTstat(u., method, copula)  # 4. Statistic
  T0.
}, NA_real_)
```

**Parallelization difficulty**: ⭐ EASY (1/5)

---

## Implementation Options

### Option A: Local Function (IMMEDIATE USE)

**File**: `functions/gofCopula_parallel.R`

**Approach**: Copy `.gofPB` source, add `cores` parameter, replace `vapply` with `parSapply`

**Modifications**:
1. Add `cores = NULL` parameter
2. Wrap bootstrap loop in conditional:
   - If `cores > 1`: Use `parallel::parSapply()` with FORK cluster
   - If `cores = NULL` or `cores = 1`: Use original `vapply()` (sequential)
3. Remove progress bar in parallel mode (interferes with workers)

**Usage**:
```r
source("functions/gofCopula_parallel.R")

# Sequential (original)
result <- gofCopula_parallel(copula, data, N=1000)

# Parallel (new)
result <- gofCopula_parallel(copula, data, N=1000, cores=46)
```

**Time to implement**: 2-4 hours
**Time to test**: 1-2 hours
**TOTAL**: **~1 day**

**Advantages**:
- ✅ Immediate use for EC2 production run
- ✅ No dependency on package maintainers
- ✅ Full control over features

**Disadvantages**:
- ⚠️ Maintenance burden (track upstream changes)
- ⚠️ Not available to broader R community

---

### Option B: GitHub Fork + Pull Request (COMMUNITY BENEFIT)

**Repository**: https://r-forge.r-project.org/projects/copula/

**Approach**: Fork, branch, modify, test, document, PR

**Steps**:
1. **Fork repository** (R-Forge or mirror to GitHub)
2. **Create branch**: `feature/parallel-bootstrap-gof`
3. **Modify** `R/gof.R`:
   - Add `cores` parameter to `gofCopula()` signature
   - Add `cores` parameter to `.gofPB()` internal function
   - Add parallelization logic (lines 67-97)
4. **Add tests** `tests/gof-parallel.R`:
   - Verify equivalence (parallel == sequential)
   - Verify speedup (parallel faster)
   - Test edge cases (N=1, cores > N, etc.)
5. **Update documentation** `man/gofCopula.Rd`:
   - Add `cores` parameter description
   - Add performance notes
   - Add examples with parallelization
6. **Submit PR** with detailed explanation and benchmarks

**Time to implement**: 1 day
**Time to test thoroughly**: 1 day
**Time to document**: 0.5 days
**Time to PR prep**: 0.5 days
**TOTAL**: **~3 days**

**Review time**: Unknown (weeks to months)

**Advantages**:
- ✅ Benefits entire R community
- ✅ Maintainer expertise improves code
- ✅ Future-proof (included in official releases)
- ✅ Citation potential (contribution to widely-used package)

**Disadvantages**:
- ⏳ Slow (review/merge may take months)
- ⏳ May not be accepted
- ⏳ May require revisions

---

## Recommended Approach: HYBRID

**Phase 1 (This week)**: Option A - Local implementation for immediate EC2 use

**Phase 2 (Next week)**: Option B - Submit PR for community benefit

**Rationale**:
- Your production run can't wait for PR review
- Community benefits from parallelization
- You gain visibility in copula community
- Maintainers may adopt your implementation

---

## Technical Details: Parallelization Modification

### Before (Sequential):

```r
T0 <- vapply(1:N, function(k) {
  U <- rCopula(n, C.th.n)
  Uhat <- pobs(U, ties.method = ties.method)
  Uhat.fit <- if (ties == FALSE || ties.method == fit.ties.meth) Uhat
              else pobs(U, ties.method = fit.ties.meth)
  C.th.n. <- if (test.method == "family") {
    fitCopula(copula, Uhat.fit, method = estim.method, 
              estimate.variance = FALSE, ...)@copula
  } else copula
  u. <- if (doTrafo) {
    switch(trafo.method,
           cCopula = do.call(cCopula, c(list(Uhat, copula = C.th.n.), trafoArgs)),
           htrafo = do.call(htrafo, c(list(Uhat, copula = C.th.n.), trafoArgs)))
  } else Uhat
  T0. <- if (method == "Sn") {
    gofTstat(u., method = method, copula = C.th.n., useR = useR)
  } else gofTstat(u., method = method)
  if (verbose) setTxtProgressBar(pb, k + 1)
  T0.
}, NA_real_)
```

### After (Parallel):

```r
if (!is.null(cores) && cores > 1) {
  # Parallel bootstrap
  cl <- makeCluster(cores, type = "FORK")
  on.exit(stopCluster(cl), add = TRUE)
  
  # FORK workers inherit environment, but explicit export is safer
  clusterExport(cl, c("n", "C.th.n", "ties", "d", "ir", "ties.method",
                      "fit.ties.meth", "copula", "estim.method", "doTrafo",
                      "trafo.method", "trafoArgs", "method", "useR", "test.method"),
                envir = environment())
  
  # Export required functions
  clusterEvalQ(cl, library(copula))
  
  T0 <- parSapply(cl, 1:N, function(k) {
    U <- rCopula(n, C.th.n)
    if (ties) {
      for (i in 1:d) {
        U <- U[order(U[, i]), ]
        U[, i] <- U[ir[, i], i]
      }
    }
    Uhat <- pobs(U, ties.method = ties.method)
    Uhat.fit <- if (ties == FALSE || ties.method == fit.ties.meth) Uhat
                else pobs(U, ties.method = fit.ties.meth)
    C.th.n. <- if (test.method == "family") {
      fitCopula(copula, Uhat.fit, method = estim.method, 
                estimate.variance = FALSE)@copula
    } else copula
    u. <- if (doTrafo) {
      switch(trafo.method,
             cCopula = do.call(cCopula, c(list(Uhat, copula = C.th.n.), trafoArgs)),
             htrafo = do.call(htrafo, c(list(Uhat, copula = C.th.n.), trafoArgs)))
    } else Uhat
    T0. <- if (method == "Sn") {
      gofTstat(u., method = method, copula = C.th.n., useR = useR)
    } else gofTstat(u., method = method)
    T0.
  })
  
  stopCluster(cl)
  
} else {
  # Sequential bootstrap (original code)
  T0 <- vapply(1:N, function(k) {
    # ... original code unchanged ...
  }, NA_real_)
}
```

**Changes**:
1. Add `cores` parameter check
2. Initialize FORK cluster (memory-efficient for Unix)
3. Export required variables and load copula library on workers
4. Replace `vapply` with `parSapply` 
5. Remove progress bar (incompatible with parallel)
6. Clean up cluster on exit

**Backward compatibility**: ✅ 100% (sequential if `cores = NULL` or `cores = 1`)

---

## Expected Performance Gains

### Laptop (12 cores available → 10 for bootstrap)

**Current (sequential)**:
- N=1000 bootstrap: ~10.4 sec per condition
- 21 conditions: ~3.6 minutes

**With parallelization (10 cores)**:
- N=1000 bootstrap: ~1.2 sec per condition (8-9x speedup)
- 21 conditions: ~25 seconds

**Speedup**: **8-9x**

---

### EC2 (48 cores available → 46 for bootstrap, single condition)

**Current (sequential)**:
- N=1000 bootstrap: ~10.4 sec

**With parallelization (46 cores)**:
- N=1000 bootstrap: ~0.25 sec (40-45x speedup)

**Speedup**: **40-45x**

---

### EC2 Production (48 cores, 129 conditions, nested parallelization)

**Current (sequential + condition parallelization)**:
- 6 conditions in parallel, N=1000 sequential per condition
- Estimated: 2-3 hours

**With nested parallelization (6 conditions × 7 bootstrap cores each)**:
- Outer loop: 6 conditions in parallel
- Inner loop: 7 bootstrap cores per condition
- Estimated: **5-8 minutes**

**Speedup**: **20-35x overall**

---

## Testing Plan

### Test 1: Equivalence

**Verify parallel gives same results as sequential**

```r
set.seed(314159)
data <- rCopula(1000, tCopula(0.75, dim=2, df=47, df.fixed=TRUE))
copula <- tCopula(dim=2, df.fixed=TRUE)

# Sequential
t1 <- system.time({
  r1 <- gofCopula_parallel(copula, data, N=100, cores=1)
})

# Parallel
t2 <- system.time({
  r2 <- gofCopula_parallel(copula, data, N=100, cores=10)
})

# Compare
cat("Observed stat diff:", abs(r1$statistic - r2$statistic), "\n")
cat("P-value diff:      ", abs(r1$p.value - r2$p.value), "\n")
cat("Speedup:           ", t1[3] / t2[3], "x\n")

stopifnot(abs(r1$statistic - r2$statistic) < 1e-10)  # Exact match
```

**Acceptance**: Observed statistics identical, p-values similar (stochastic)

---

### Test 2: Performance Scaling

**Measure speedup with different core counts**

```r
cores_to_test <- c(1, 2, 4, 6, 8, 10)
times <- numeric(length(cores_to_test))

for (i in seq_along(cores_to_test)) {
  nc <- cores_to_test[i]
  times[i] <- system.time({
    gofCopula_parallel(copula, data, N=100, cores=nc)
  })[3]
  cat(sprintf("%2d cores: %6.2f sec\n", nc, times[i]))
}

# Plot speedup curve
speedup <- times[1] / times
efficiency <- speedup / cores_to_test
plot(cores_to_test, speedup, type="b", main="Parallel Speedup")
abline(0, 1, lty=2, col="red")  # Ideal linear speedup
```

**Acceptance**: Near-linear speedup up to 8-10 cores

---

### Test 3: Edge Cases

```r
# Edge case 1: N < cores (more workers than work)
result <- gofCopula_parallel(copula, data, N=5, cores=10)
stopifnot(!is.na(result$statistic))

# Edge case 2: Very large N
result <- gofCopula_parallel(copula, data, N=5000, cores=10)
stopifnot(!is.na(result$statistic))

# Edge case 3: Small sample size
data_small <- rCopula(50, copula)
result <- gofCopula_parallel(copula, data_small, N=100, cores=10)
stopifnot(!is.na(result$statistic))
```

**Acceptance**: All edge cases complete without errors

---

## Next Steps

### Immediate (This Week):

1. ✅ **Assess feasibility** ← DONE (this document)
2. ⬜ **Create `functions/gofCopula_parallel.R`** (2-3 hours)
3. ⬜ **Test equivalence** (1 hour)
4. ⬜ **Test performance** (1 hour)
5. ⬜ **Integrate into `copula_bootstrap.R`** (1 hour)
6. ⬜ **Run EC2 production** (5-10 minutes)

**TOTAL TIME**: **1 day** → EC2 run Friday

---

### Future (Next Week):

1. ⬜ **Fork copula repository**
2. ⬜ **Create feature branch**
3. ⬜ **Port local version to package**
4. ⬜ **Add comprehensive tests**
5. ⬜ **Update documentation**
6. ⬜ **Submit pull request with benchmarks**

**TOTAL TIME**: **3 days** → PR submitted by end of next week

---

## Conclusion

**VERDICT: HIGHLY FEASIBLE** ✅

The copula package's bootstrap loop is **perfectly suited for parallelization**:
- Simple structure (`vapply` over independent iterations)
- No complex dependencies or side effects
- Easy modification (< 50 lines of additional code)
- Massive performance gains (8-45x speedup)

**Recommendation**: 
1. Implement local version TODAY for immediate EC2 use
2. Submit PR NEXT WEEK for community benefit

**Expected outcome**: 
- EC2 production run: **5-10 minutes** (vs. 2-3 hours)
- Community contribution: Benefit thousands of copula users
- Academic credit: Citation in widely-used R package

