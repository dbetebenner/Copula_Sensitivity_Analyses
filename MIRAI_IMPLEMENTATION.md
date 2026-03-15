# mirai Parallelisation: Implementation Guide

A practical reference for using `mirai` (R package) for daemon-based parallel
computation on multi-core machines and large cloud instances. Distilled from
production use in the Copula Sensitivity Analyses project (STEP 3: LIwLD),
tested on EC2 r8g instances with 16–192 vCPUs.

---

## 1. Overview

**What mirai is.** `mirai` is an R package for minimally-invasive asynchronous
evaluation. It launches persistent background R processes ("daemons") via a
dispatcher and provides tools to push data to them (`everywhere()`), dispatch
tasks (`mirai()`, `mirai_map()`), and collect results.

**When to use it.**
- Embarrassingly parallel workloads: bootstrap replicates, Monte Carlo
  simulations, grid searches over independent cells.
- Large EC2/cloud instances (48–192+ vCPUs) where `parallel::mclapply()` hits
  scaling walls.
- Repeated task dispatch over a persistent daemon pool, avoiding per-task
  process startup costs.

**Why not `parallel::mclapply()`.**
- `mclapply` forks the main process per task, which doesn't scale beyond
  ~16 cores on most systems (fork overhead, memory duplication).
- No daemon reuse: each `mclapply` call forks fresh processes.
- No data push: the entire parent environment is duplicated per fork.
- Not available on Windows (fallback to sequential `lapply`).

---

## 2. Daemon Lifecycle

### Start once, share across phases

Daemons are expensive to create (process startup, package loading, function
sourcing). Create them once at the beginning of the pipeline and reuse across
all parallel workloads.

```r
n_cores <- parallel::detectCores(logical = TRUE)
n_workers <- max(2L, if (n_cores <= 48L) n_cores - 2L else n_cores - 4L)
mirai::daemons(n = n_workers, output = TRUE, retry = FALSE)
```

| Instance type   | vCPUs | Workers | Headroom |
|-----------------|-------|---------|----------|
| r8g.4xlarge     |    16 |      14 | 2 for main process + OS |
| r8g.12xlarge    |    48 |      46 | 2 for main process + OS |
| r8g.48xlarge    |   192 |     188 | 4 for main process + OS + monitoring |

### Init via `everywhere()`

After daemon creation, broadcast one-time setup to all daemons:

```r
init_push <- mirai::everywhere({
  suppressPackageStartupMessages({
    library(data.table)
    library(copula)
  })
  data.table::setDTthreads(1L)
  Sys.setenv(
    OMP_NUM_THREADS        = "1",
    MKL_NUM_THREADS        = "1",
    OPENBLAS_NUM_THREADS   = "1",
    VECLIB_MAXIMUM_THREADS = "1"
  )
  for (ff in fn_files_push) {
    source(ff)
  }
  TRUE
},
fn_files_push = c(
  file.path(project_root, "functions/sgpc_engine.R"),
  file.path(step3_root,   "functions/reference_marginals.R"),
  # ... all function files needed by workers
))

init_vals <- init_push[]
n_ok <- sum(vapply(init_vals, isTRUE, logical(1)))
stopifnot(n_ok == n_workers)
```

### Absolute paths required

Daemons start in the user's home directory, not the project directory. All
paths passed to `everywhere()` and worker functions must be **absolute**:

```r
STEP3_ROOT_ABS   <- normalizePath(STEP3_ROOT, mustWork = TRUE)
PROJECT_ROOT_ABS <- normalizePath(PROJECT_ROOT, mustWork = TRUE)
```

### Cleanup: explicit `daemons(0)`, never `on.exit()`

Place a single cleanup call at the very end of the script:

```r
# At the BOTTOM of run_step3.R (after all phases complete)
if (daemons_live) {
  tryCatch(mirai::daemons(0), error = function(e) NULL)
  daemons_live <- FALSE
  cat("mirai daemons shut down.\n")
}
```

See Section 3 for why `on.exit()` must not be used.

---

## 3. The `on.exit()` Trap in `source()`d Scripts

### The problem

R's `source()` evaluates each top-level expression via `eval()`. When a
top-level expression contains `on.exit()`, the handler is registered for
**that `eval()` frame** — not for the entire script. The frame exits
immediately after the expression completes, triggering the cleanup.

```r
# In run_step3.R (BAD - do NOT do this):
mirai::daemons(n = 188)
on.exit(mirai::daemons(0))  # <-- fires NOW, not at script end

# Everything below sees zero daemons
source("step3_validation_deep_dive.R")  # no daemons!
```

### Symptoms

- Daemons start, log output confirms N/N ready, then immediately shut down.
- Downstream code finds `mirai::status()[["connections"]] == 0`.
- Bootstrap falls back to sequential with a warning.

### Fix

**Option A (recommended):** Explicit cleanup at the bottom of the script:

```r
# ... all phases run here ...

# CLEANUP — last lines of the script
if (daemons_live) {
  tryCatch(mirai::daemons(0), error = function(e) NULL)
  daemons_live <- FALSE
}
```

**Option B:** Wrap the entire script body in a function and use `on.exit()`
inside that function (the `on.exit()` registers in the function's frame, which
persists until the function returns):

```r
run_all <- function() {
  mirai::daemons(n = n_workers)
  on.exit(mirai::daemons(0), add = TRUE)
  # ... all phases ...
}
run_all()
```

---

## 4. Data Push Pattern (`everywhere()` + `<<-`)

### Why `<<-` is required

`everywhere()` evaluates its expression in a **local task frame** on each
daemon. The parent of that frame is the daemon's `.GlobalEnv`. Regular
assignment `<-` creates a binding in the local task frame, which evaporates
when `everywhere()` completes. Super-assignment `<<-` walks up the scope
chain to `.GlobalEnv`, where the binding persists.

```r
# CORRECT: persists in daemon .GlobalEnv
mirai::everywhere({
  .BOOT_DATA     <<- data_push
  .BOOT_CONFIG   <<- config_push
  TRUE
},
data_push   = my_data,
config_push = my_config)

# WRONG: bindings evaporate after everywhere() returns
mirai::everywhere({
  .BOOT_DATA  <- data_push    # local only!
  .BOOT_CONFIG <- config_push  # local only!
})
```

### Naming convention

Prefix all daemon globals with a unique namespace to avoid collisions between
different parallel workloads running on the same daemon pool:

| Phase | Prefix | Example |
|-------|--------|---------|
| Phase A bootstrap | `.BOOT_*` | `.BOOT_U_SAMPLE`, `.BOOT_KERNEL_CACHE` |
| Phase B Stage 1   | `.PHASEB_S1_*` | `.PHASEB_S1_SS_PRIOR` |
| Phase B Stage 2   | `.PHASEB_*` | `.PHASEB_U_FULL`, `.PHASEB_POOL_DEFS` |

### Push frequency

Push data **once per logical unit of work**:
- Phase A: once per `bootstrap_regime()` call (per target)
- Phase B: once per condition (shared across all pools and replicates
  within that condition)

### Verify push success

```r
p <- mirai::everywhere({ .MY_DATA <<- x; TRUE }, x = my_data)
pv <- p[]
stopifnot(all(vapply(pv, isTRUE, logical(1))))
```

---

## 5. Task Dispatch Pattern (`mirai_map()`)

### Build a flat task list

Each element is a named list of per-task parameters:

```r
tasks <- lapply(seq_len(n_boot), function(b) list(b = b))
```

For more complex workloads (pool × bucket × rep_batch):

```r
tasks <- list()
for (pool_tag in pool_tags) {
  for (bkt in eligible_buckets) {
    for (batch_start in seq(1, n_reps, by = batch_size)) {
      batch_end <- min(batch_start + batch_size - 1, n_reps)
      tasks[[length(tasks) + 1]] <- list(
        pool_tag    = pool_tag,
        n_bucket    = bkt,
        rep_start   = batch_start,
        rep_end     = batch_end
      )
    }
  }
}
```

### Define a worker lambda

The lambda receives one task and reads `.GLOBAL_*` variables from the daemon's
`.GlobalEnv`:

```r
worker_fn <- function(task) {
  b <- task$b
  # Read pushed globals
  u_boot <- sample(.BOOT_U_SAMPLE, replace = TRUE)
  v_boot <- sample(.BOOT_V_SAMPLE, replace = TRUE)
  # Call sourced function
  res <- estimate_regime(u_boot, v_boot, .BOOT_KERNEL_CACHE, ...)
  list(mean_sgpc = res$regime$mean * 100)
}
```

### Critical: set the lambda's environment to `globalenv()`

```r
environment(worker_fn) <- globalenv()
```

Without this, the lambda's environment is the enclosing frame where it was
defined (the main process). R would serialise that frame — which is both
wasteful and wrong, since the main process's `.GlobalEnv` is not the daemon's
`.GlobalEnv`. Setting to `globalenv()` causes R to serialise a
`GLOBALENV_SXP` sentinel, and each daemon resolves it to its own `.GlobalEnv`
where sourced functions and pushed globals live.

### Dispatch and collect

```r
mirai_res <- mirai::mirai_map(.x = tasks, .f = worker_fn)
results <- mirai_res[]  # blocks until all tasks complete
```

### Sort tasks slowest-first

For heterogeneous task sizes, sort descending by expected runtime to prevent
idle workers at the tail end:

```r
tasks <- tasks[order(-sapply(tasks, `[[`, "n_bucket"))]
```

---

## 6. Checking Daemon Status

The `mirai::status()` return structure varies across `mirai` versions:

| Field | Typical value | Notes |
|-------|--------------|-------|
| `$connections` | integer (e.g., `188L`) | **Always available.** Number of active daemon connections. |
| `$daemons` | matrix, data.frame, or character | Format varies by version; do NOT rely on `is.matrix()`. |

### Robust liveness check

```r
check_daemons_live <- function() {
  tryCatch({
    n_conn <- mirai::status()[["connections"]]
    is.numeric(n_conn) && length(n_conn) == 1L && n_conn > 0L
  }, error = function(e) FALSE)
}
```

### Anti-pattern (do NOT use)

```r
# WRONG: fails when $daemons is a data.frame or character vector
is.matrix(mirai::status()$daemons)
```

### Fallback pattern

```r
if (check_daemons_live()) {
  # parallel path
} else {
  warning("No mirai daemons detected; running sequentially.")
  # sequential fallback
}
```

---

## 7. Error Handling

`mirai_map()` does not stop on individual task failures. Failed tasks return
`miraiError` or `errorValue` objects.

### Check and replace errors

```r
results <- mirai_res[]

n_errs <- sum(vapply(results, function(x)
  inherits(x, "miraiError") || inherits(x, "errorValue"), logical(1)))

if (n_errs > 0) {
  cat("WARNING:", n_errs, "of", length(results), "tasks failed\n")
}

# Replace errors with NA sentinels
for (i in seq_along(results)) {
  if (inherits(results[[i]], "miraiError") ||
      inherits(results[[i]], "errorValue")) {
    results[[i]] <- list(
      mean_sgpc    = NA_real_,
      converged    = FALSE
    )
  }
}
```

### Why not `stop()` on error?

Stopping the pipeline discards all successful results. For bootstrap and
Monte Carlo workloads, a few failed replicates out of hundreds are acceptable
and should be logged but not fatal.

---

## 8. Thread Pinning (`data.table`, BLAS, OpenMP)

### The oversubscription problem

If N daemons each use M threads internally, total thread count = N × M.
On a 192-vCPU machine with 188 daemons, even M=2 means 376 threads competing
for 192 cores — causing massive context-switch overhead and degraded
throughput.

### Fix: pin each daemon to 1 thread

This must be done inside the `everywhere()` init block, before any computation:

```r
mirai::everywhere({
  data.table::setDTthreads(1L)
  Sys.setenv(
    OMP_NUM_THREADS        = "1",
    MKL_NUM_THREADS        = "1",
    OPENBLAS_NUM_THREADS   = "1",
    VECLIB_MAXIMUM_THREADS = "1",
    NUMEXPR_NUM_THREADS    = "1"
  )
})
```

| Environment variable | Controls |
|---------------------|----------|
| `OMP_NUM_THREADS` | OpenMP (most compiled code) |
| `MKL_NUM_THREADS` | Intel MKL (linear algebra) |
| `OPENBLAS_NUM_THREADS` | OpenBLAS (linear algebra on Linux) |
| `VECLIB_MAXIMUM_THREADS` | Apple Accelerate (macOS) |
| `NUMEXPR_NUM_THREADS` | NumExpr (Python interop, rare in R) |

`data.table::setDTthreads(1L)` is separate because `data.table` manages its
own thread pool independently of the OpenMP environment variable.

---

## 9. Batch Size Tuning

### The parameter: `rep_batch_size`

Controls how many atomic units of work are grouped into a single mirai task.
This is the most critical tuning knob for large instances.

### Trade-offs

| Batch size | Pros | Cons |
|-----------|------|------|
| **Large** (e.g., 50) | Less dispatch overhead, fewer tasks to manage | Tail-end idle workers: if total_tasks / n_workers < 2, many workers sit idle while the last few batches complete |
| **Small** (e.g., 1) | Perfect load balancing | High dispatch overhead; each mirai task has serialisation/deserialisation cost |
| **Sweet spot** | Enough tasks that `total_tasks / n_workers >= 3` rounds | Keeps all workers busy through completion |

### Recommended values by instance size

| Instance | Workers | `rep_batch_size` | Total tasks (200 reps × 5 buckets × 8 pools) | Tasks / worker |
|----------|---------|-----------------|----------------------------------------------|----------------|
| 16 vCPU  |      14 |              25 | ~192 | 13.7 |
| 48 vCPU  |      46 |              10 | ~480 | 10.4 |
| 192 vCPU |     188 |             **5** | ~960 | 5.1 |

### Rule of thumb

```
total_tasks = (n_pools × n_eligible_buckets × n_reps) / rep_batch_size
target: total_tasks / n_workers >= 3
```

If `total_tasks / n_workers < 2`, reduce `rep_batch_size`.

---

## 10. Concrete Patterns

### Pattern A: Bootstrap Parallelisation (Phase A)

Used by `bootstrap_uncertainty.R` to dispatch bootstrap replicates.

```r
bootstrap_regime_parallel <- function(u_sample, v_sample, kernel_cache,
                                      regime_family, n_boot = 200,
                                      use_mirai = TRUE, ...) {

  # 1. Check daemon liveness
  mirai_ok <- FALSE
  if (isTRUE(use_mirai) && n_boot > 1L) {
    mirai_ok <- tryCatch({
      n_conn <- mirai::status()[["connections"]]
      is.numeric(n_conn) && length(n_conn) == 1L && n_conn > 0L
    }, error = function(e) FALSE)
  }

  if (mirai_ok) {
    # 2. Push data to all daemons
    push_ok <- tryCatch({
      p <- mirai::everywhere({
        .BOOT_U_SAMPLE     <<- u_push
        .BOOT_V_SAMPLE     <<- v_push
        .BOOT_KERNEL_CACHE <<- kc_push
        .BOOT_REGIME_FAMILY <<- rf_push
        TRUE
      },
      u_push  = u_sample,
      v_push  = v_sample,
      kc_push = kernel_cache,
      rf_push = regime_family)
      pv <- p[]
      all(vapply(pv, isTRUE, logical(1)))
    }, error = function(e) FALSE)

    if (push_ok) {
      # 3. Build task list
      tasks <- lapply(seq_len(n_boot), function(b) list(b = b))

      # 4. Define worker lambda
      boot_fn <- function(task) {
        b <- task$b
        n <- length(.BOOT_U_SAMPLE)
        idx <- sample.int(n, n, replace = TRUE)
        res <- estimate_regime(
          .BOOT_U_SAMPLE[idx],
          .BOOT_V_SAMPLE[idx],
          .BOOT_KERNEL_CACHE,
          regime_family = .BOOT_REGIME_FAMILY,
          verbose = FALSE
        )
        list(mean_sgpc = res$regime$mean * 100,
             converged = (res$convergence == 0))
      }
      environment(boot_fn) <- globalenv()

      # 5. Dispatch
      mirai_res <- mirai::mirai_map(.x = tasks, .f = boot_fn)
      results <- mirai_res[]

      # 6. Handle errors
      for (i in seq_along(results)) {
        if (inherits(results[[i]], "miraiError") ||
            inherits(results[[i]], "errorValue")) {
          results[[i]] <- list(mean_sgpc = NA_real_, converged = FALSE)
        }
      }
      return(results)
    }
  }

  # 7. Sequential fallback
  lapply(seq_len(n_boot), function(b) {
    n <- length(u_sample)
    idx <- sample.int(n, n, replace = TRUE)
    res <- estimate_regime(u_sample[idx], v_sample[idx], kernel_cache,
                           regime_family = regime_family, verbose = FALSE)
    list(mean_sgpc = res$regime$mean * 100,
         converged = (res$convergence == 0))
  })
}
```

### Pattern B: Two-Stage Pool Processing (Phase B)

Used by `step3_systematic_validation.R` for systematic validation across
conditions, pools, and sample sizes.

```r
run_systematic_parallel <- function(conditions, pool_defs,
                                    n_reps, rep_batch_size, ...) {

  # --- Daemon init (one-time, in run_step3.R) ---
  # Already done: packages loaded, functions sourced, threads pinned

  for (cond in conditions) {
    # --- Per-condition data push ---
    push_ok <- tryCatch({
      cond_push <- mirai::everywhere({
        .PHASEB_U_FULL       <<- u_push
        .PHASEB_V_FULL       <<- v_push
        .PHASEB_REFS         <<- refs_push
        .PHASEB_KERNEL_CACHE <<- kc_push
        .PHASEB_POOL_DEFS    <<- pd_push
        .PHASEB_CFG_REG      <<- cfg_reg_push
        .PHASEB_CFG_DIST     <<- cfg_dist_push
        TRUE
      },
      u_push       = cond$u_full,
      v_push       = cond$v_full,
      refs_push    = cond$refs,
      kc_push      = cond$kernel_cache,
      pd_push      = cond$pool_defs,
      cfg_reg_push = STEP3_CONFIG$regime,
      cfg_dist_push = STEP3_CONFIG$distance)
      pv <- cond_push[]
      all(vapply(pv, isTRUE, logical(1)))
    }, error = function(e) FALSE)

    if (!push_ok) next

    # --- Build flat task list ---
    tasks <- list()
    for (pool in pool_defs) {
      eligible_buckets <- get_eligible_buckets(pool, n_reps)
      for (bkt in eligible_buckets) {
        for (batch_start in seq(1, n_reps, by = rep_batch_size)) {
          batch_end <- min(batch_start + rep_batch_size - 1, n_reps)
          tasks[[length(tasks) + 1]] <- list(
            pool_tag   = pool$tag,
            n_bucket   = bkt,
            rep_start  = batch_start,
            rep_end    = batch_end
          )
        }
      }
    }

    # --- Sort slowest-first ---
    tasks <- tasks[order(-sapply(tasks, `[[`, "n_bucket"))]

    # --- Define worker lambda ---
    worker_fn <- function(task) {
      process_replicate_batch(
        pool_tag   = task$pool_tag,
        n_bucket   = task$n_bucket,
        rep_start  = task$rep_start,
        rep_end    = task$rep_end,
        pool_defs  = .PHASEB_POOL_DEFS,
        u_full     = .PHASEB_U_FULL,
        v_full     = .PHASEB_V_FULL,
        refs       = .PHASEB_REFS,
        kernel_cache = .PHASEB_KERNEL_CACHE,
        cfg_reg    = .PHASEB_CFG_REG,
        cfg_dist   = .PHASEB_CFG_DIST
      )
    }
    environment(worker_fn) <- globalenv()

    # --- Dispatch ---
    mirai_res <- mirai::mirai_map(.x = tasks, .f = worker_fn)
    batch_results <- mirai_res[]

    # --- Collect and handle errors ---
    for (i in seq_along(batch_results)) {
      if (inherits(batch_results[[i]], "miraiError") ||
          inherits(batch_results[[i]], "errorValue")) {
        batch_results[[i]] <- data.table()
      }
    }
    all_reps <- rbindlist(batch_results, fill = TRUE)
  }
}
```

---

## Quick Reference Card

| Step | API | Key detail |
|------|-----|-----------|
| Start daemons | `mirai::daemons(n, output=TRUE)` | Once at pipeline start |
| Init daemons | `mirai::everywhere({...})` | Load packages, source functions, pin threads |
| Push data | `mirai::everywhere({ .X <<- val }, val = x)` | **Must use `<<-`**, not `<-` |
| Check liveness | `mirai::status()[["connections"]] > 0L` | Do NOT use `is.matrix(status()$daemons)` |
| Define lambda | `fn <- function(task) {...}` | Reads `.GLOBAL_*` from daemon `.GlobalEnv` |
| Set environment | `environment(fn) <- globalenv()` | **Required** — prevents serialising main-process frame |
| Dispatch | `mirai::mirai_map(.x = tasks, .f = fn)` | Returns immediately; `res[]` blocks |
| Collect | `results <- res[]` | Blocks until all tasks complete |
| Handle errors | `inherits(x, "miraiError")` | Replace with NA sentinels, log count |
| Cleanup | `mirai::daemons(0)` | **Explicit call at script end**, never `on.exit()` in sourced scripts |
