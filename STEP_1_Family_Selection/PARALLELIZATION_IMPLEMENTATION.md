# STEP 1 Parallelization Implementation

## Executive Summary

**Status:** ✅ Implemented and ready for testing  
**Expected Speedup:** 14-15x on EC2 c6i.4xlarge (16 cores)  
**Target Runtime:** 4-6 minutes (vs 60-90 minutes sequential)  
**Files Modified:** 2 files created, 1 file updated  

---

## Implementation Overview

### Files Created

1. **`phase1_family_selection_parallel.R`** - Main parallel implementation
   - Uses R's built-in `parallel` package (PSOCK cluster)
   - Processes 28 conditions across 15 cores (leaves 1 for system)
   - Each condition independently fits 5 copula families
   - Returns identical output format to sequential version

2. **`test_parallel_subset.R`** - Testing script
   - Tests parallel implementation with 3 conditions on 2 cores
   - Verifies output format and error handling
   - Should be run before deploying to full 28 conditions

### Files Modified

1. **`master_analysis.R`** (lines 314-334)
   - Added automatic detection of EC2 environment
   - Uses parallel version when `IS_EC2 == TRUE`
   - Falls back to sequential version for local development
   - No changes to downstream analysis steps

---

## Architecture

### Parallelization Strategy

```
Master Process
├── Initialize PSOCK cluster (15 workers)
├── Export data: STATE_DATA_LONG, WORKSPACE_OBJECT_NAME, get_state_data()
├── Export functions: create_longitudinal_pairs(), etc.
└── Distribute 28 conditions across workers
    ├── Worker 1: Conditions 1, 16, ...
    ├── Worker 2: Conditions 2, 17, ...
    ├── ...
    └── Worker 15: Conditions 15, 30, ...

Each Worker:
1. Create longitudinal pairs for assigned condition
2. Create I-spline frameworks
3. Fit 5 copula families (gaussian, t, clayton, gumbel, frank)
4. Calculate tail dependence metrics
5. Return results to master

Master Process:
1. Collect results from all workers
2. Stop cluster
3. Aggregate into single data.table
4. Calculate best family per condition
5. Save to CSV (same format as sequential)
```

### Why PSOCK Instead of Fork?

- **Cross-platform:** Works on Windows, macOS, Linux
- **Explicit data export:** More memory efficient on EC2
- **Stable:** No issues with RStudio/IDE environments
- **Reproducible:** Each worker starts with clean state

---

## Performance Analysis

### Current (Sequential)
```
Total Time: 60-90 minutes
Cores Used: 1 of 16 (6% utilization)
Memory: ~2-4 GB
Throughput: ~2-3 minutes per condition
```

### Expected (Parallel)
```
Total Time: 4-6 minutes
Cores Used: 15 of 16 (94% utilization)
Memory: ~15-20 GB (data replicated across workers)
Throughput: ~2-3 minutes per condition (15 in parallel)
Speedup: 14-15x (near-linear)
```

### Why Near-Linear Speedup?

✅ **Perfect for parallelization:**
- 28 conditions are completely independent
- No shared mutable state
- No sequential dependencies
- Equal computational complexity per condition
- Read-only data access

✅ **No bottlenecks:**
- CPU-bound workload (not I/O bound)
- Sufficient memory (32 GB >> 20 GB needed)
- No network/disk contention

❌ **Minor overhead:**
- Cluster initialization: ~5-10 seconds
- Data export to workers: ~10-20 seconds
- Result aggregation: ~1-2 seconds
- Total overhead: <1 minute

**Expected parallel efficiency:** >90%

---

## Testing Protocol

### Step 1: Test with Subset (3 conditions, 2 cores)

```r
# From R console in project root:
source("master_analysis.R")  # Loads data and functions

# Run test
source("STEP_1_Family_Selection/test_parallel_subset.R")
```

**Expected output:**
```
TESTING PARALLEL IMPLEMENTATION (SUBSET)
Using 2 cores for testing
Cluster initialized successfully.

Starting parallel test...
Completed condition 1
Completed condition 2
Completed condition 3

PARALLEL TEST COMPLETE
Total time: 4-6 minutes

Successful conditions: 3 / 3
Failed conditions: 0

Results compiled successfully!
Total rows: 15  (3 conditions × 5 families)

TEST PASSED: Parallel implementation working correctly!
```

### Step 2: Compare Sequential vs Parallel (First 3 Conditions)

```r
# Run sequential version
source("STEP_1_Family_Selection/phase1_family_selection.R")
results_sequential <- fread("STEP_1_Family_Selection/results/phase1_copula_family_comparison.csv")

# Run parallel version  
source("STEP_1_Family_Selection/phase1_family_selection_parallel.R")
results_parallel <- fread("STEP_1_Family_Selection/results/phase1_copula_family_comparison.csv")

# Compare (should be identical within numerical precision)
all.equal(
  results_sequential[order(condition_id, family)],
  results_parallel[order(condition_id, family)],
  tolerance = 1e-6
)
```

### Step 3: Full Production Run (28 conditions, 15 cores)

**On EC2:**
```bash
# SSH into EC2 instance
ssh ec2-user@<instance-ip>

# Start R
R

# Run master analysis (will auto-detect EC2 and use parallel)
source("master_analysis.R")
```

**Expected behavior:**
- Detects EC2 environment automatically
- Uses parallel implementation
- Completes in 4-6 minutes
- Saves results to same location as sequential

---

## Error Handling

### Worker Failures

Each condition is wrapped in `tryCatch()`:

```r
process_condition <- function(i, cond, copula_families) {
  tryCatch({
    # ... processing logic ...
    return(list(success = TRUE, ...))
  }, error = function(e) {
    return(list(success = FALSE, error = e$message))
  })
}
```

**Result:** Failed conditions don't crash entire job; they return error status.

### Cluster Cleanup

```r
# Cluster is always stopped, even if error occurs
on.exit(stopCluster(cl))
```

**Result:** No orphaned R processes consuming resources.

### Data Availability

```r
if (is.null(pairs_full) || nrow(pairs_full) < 100) {
  return(list(success = FALSE, error = "Insufficient data"))
}
```

**Result:** Conditions with insufficient data skip gracefully.

---

## Memory Management

### Per-Worker Memory Usage

```
STATE_DATA_LONG: ~500 MB (replicated to each worker)
Longitudinal pairs: ~10-50 MB
I-spline frameworks: ~5-10 MB
Copula objects: ~1-5 MB
Total per worker: ~520-565 MB
```

### Total Memory Usage

```
15 workers × 565 MB = ~8.5 GB (worker data)
+ ~2 GB (master process)
+ ~2 GB (results aggregation)
= ~12.5 GB total

Available: 32 GB
Utilization: 39% ✅ Safe
```

---

## Validation Checklist

Before deploying to full production:

- [x] Create `phase1_family_selection_parallel.R`
- [x] Update `master_analysis.R` with EC2 detection
- [x] Create test script with subset of conditions
- [ ] **Run test script locally** (verify 3 conditions complete)
- [ ] **Compare output format** (sequential vs parallel)
- [ ] **Deploy to EC2** (run with all 28 conditions)
- [ ] **Verify timing** (should be 4-6 minutes)
- [ ] **Check downstream steps** (phase1_analysis.R should work unchanged)
- [ ] **Document actual speedup** (update this file with results)

---

## Troubleshooting

### "Cannot find function create_longitudinal_pairs"

**Cause:** Functions not exported to workers  
**Fix:** Ensure `clusterEvalQ()` sources function files correctly

```r
clusterEvalQ(cl, {
  source("functions/longitudinal_pairs.R")
  source("functions/ispline_ecdf.R")
  source("functions/copula_bootstrap.R")
})
```

### "Object STATE_DATA_LONG not found"

**Cause:** Data not exported to workers  
**Fix:** Verify `clusterExport()` includes data and configuration variables

```r
clusterExport(cl, c("STATE_DATA_LONG", "WORKSPACE_OBJECT_NAME", "get_state_data"), envir = .GlobalEnv)
```

Note: `WORKSPACE_OBJECT_NAME` must be exported because `get_state_data()` references it internally.

### Cluster initialization hangs

**Cause:** PSOCK cluster requires open ports  
**Fix:** Check firewall settings on EC2

```bash
# Allow internal communication (should be enabled by default)
sudo iptables -L
```

### Workers use too much memory

**Cause:** Data replication across 15 workers  
**Fix:** Reduce number of workers

```r
n_cores_use <- 10  # Instead of 15
```

### Results differ from sequential version

**Cause:** Numerical precision or random number generation  
**Expected:** Differences <1e-6 are acceptable  
**Action:** Compare with tolerance:

```r
all.equal(results_seq, results_par, tolerance = 1e-6)
```

---

## Future Enhancements

### Phase 2: Within-Condition Parallelization

Currently: Each condition fits 5 families sequentially  
Enhancement: Parallelize 5 families within each condition

```
Current: 28 conditions in parallel, 5 families per condition sequential
Future:  28 conditions × 5 families = 140 parallel tasks
```

**Benefit:** Could further reduce runtime from 4-6 min to 1-2 min  
**Cost:** More complex cluster management (nested parallelization)

### Phase 2: Load Balancing

Currently: Using `parLapply()` (static task assignment)  
Enhancement: Use `parLapplyLB()` (dynamic load balancing)

**Benefit:** Better handling if some conditions take longer  
**Cost:** Minimal (just change function name)

```r
# Current
all_condition_results <- parLapply(cl, X, fun)

# Enhanced
all_condition_results <- parLapplyLB(cl, X, fun)  # LB = Load Balancing
```

### Phase 2: Progress Tracking

Currently: No real-time progress updates  
Enhancement: Use shared file or database for progress

```r
# Enhanced version
process_condition_with_progress <- function(i, cond, ...) {
  result <- process_condition(i, cond, ...)
  write(paste("Completed:", i, "at", Sys.time()), 
        file = "progress.log", append = TRUE)
  return(result)
}
```

### Phase 3: Resumable Processing

Currently: Must restart if job fails  
Enhancement: Save intermediate results, resume from last completed

```r
# Check for existing partial results
completed <- list.files("results/partial", pattern = "condition_\\d+\\.RData")
pending <- setdiff(1:28, parse_number(completed))

# Process only pending conditions
```

---

## Next Steps for Parallelization

After STEP 1 success, parallelize:

### STEP 2: Transformation Validation (Similar Structure)
- **Workload:** 15 transformation methods tested independently
- **Expected speedup:** 10-15x
- **Implementation effort:** Low (copy STEP 1 pattern)

### STEP 3: Sensitivity Experiments (More Complex)
- **Workload:** 4 experiments, each with 1000 bootstrap iterations
- **Expected speedup:** 15x (parallelize bootstrap iterations)
- **Implementation effort:** Medium (nested loops)

### STEP 4: Reporting (Not Parallelizable)
- **Workload:** Generate plots and tables
- **Expected speedup:** None (I/O bound, not CPU bound)

---

## Conclusion

**Status:** ✅ Ready for testing

**Implementation:** Complete and follows R best practices

**Risk:** Low - Uses stable base R packages, comprehensive error handling

**Next Action:** Run `test_parallel_subset.R` to verify on local machine before deploying to EC2

**Expected Impact:**
- STEP 1 runtime: 60-90 min → 4-6 min (14-15x faster)
- Total analysis pipeline: 8-14 hours → 1-2 hours (with all steps parallelized)
- EC2 cost savings: ~$5-10 per run (reduced instance time)

---

## References

- R Parallel Computing Documentation: `?parallel::makeCluster`
- PSOCK vs Fork: https://stat.ethz.ch/R-manual/R-devel/library/parallel/doc/parallel.pdf
- Copula Package: https://cran.r-project.org/package=copula
- EC2 Instance Specs: c6i.4xlarge (16 vCPUs, 32 GB RAM)
