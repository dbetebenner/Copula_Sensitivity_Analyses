###############################################################################
###
### liwld_precompute.R --- Build the LIwLD interactive scenario bundle.
###
### Produces, for one canonical scenario, all six artifacts the D3 frontend
### needs (manifest.json + five panel files).  See:
###    schema/manifest.schema.json   for the data contract
###    PROJECT_PLAN.md, section 3    for the rationale
###
### Default mode reads `phase_a_analytic_payload.rds` (real, de-identified
### Phase A data).  Synthetic mode is a fallback for development:
###     STEP3_EXPORT_MODE=SYNTHETIC Rscript R/liwld_precompute.R
###
### Run from this folder:
###     Rscript R/liwld_precompute.R
###     # or, from R:
###     source("R/liwld_precompute.R")
###
### Output:
###     data/scenarios/<scenario_id>/manifest.json + 5 panel files
###
### Author: Damian Betebenner, Claude (collaborator)
### Created: 2026-05-04
###
###############################################################################

suppressPackageStartupMessages({
  if (!requireNamespace("copula", quietly = TRUE)) {
    stop("Install 'copula'.")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Install 'jsonlite'.")
  }
  if (!requireNamespace("digest", quietly = TRUE)) stop("Install 'digest'.")
})


# ---------------------------------------------------------------------------
# Polyfills (R < 4.4 lacks base::%||%)
# ---------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a


# ---------------------------------------------------------------------------
# Defensive kernel-cache builder (mirrors .create_kernel_cache_safe in
# step3_analytic_explanation.R — guards against pmin/pmax dimension drop in
# the shared helper).
# ---------------------------------------------------------------------------
.build_kernel_cache_safe <- function(
  copula_obj,
  u_grid_size = 201L,
  v_grid_size = 201L,
  boundary_buffer = 0.005,
  compute_quantile = FALSE
) {
  u_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = u_grid_size)
  v_grid <- seq(boundary_buffer, 1 - boundary_buffer, length.out = v_grid_size)

  uv_pairs <- as.matrix(expand.grid(u = u_grid, v = v_grid))
  cond_vec <- as.vector(copula::cCopula(
    uv_pairs,
    copula = copula_obj,
    indices = 2
  ))

  conditional_cdf <- matrix(
    cond_vec,
    nrow = u_grid_size,
    ncol = v_grid_size,
    byrow = FALSE
  )
  conditional_cdf[conditional_cdf < 0] <- 0
  conditional_cdf[conditional_cdf > 1] <- 1
  for (i in seq_len(u_grid_size)) {
    conditional_cdf[i, ] <- cummax(conditional_cdf[i, ])
  }

  quantile_grid <- NULL
  p_grid <- NULL
  if (isTRUE(compute_quantile)) {
    p_grid <- seq(
      boundary_buffer,
      1 - boundary_buffer,
      length.out = v_grid_size
    )
    quantile_grid <- matrix(NA_real_, nrow = u_grid_size, ncol = length(p_grid))
    for (i in seq_len(u_grid_size)) {
      cdf_row <- conditional_cdf[i, ]
      quantile_grid[i, ] <- approx(
        cdf_row,
        v_grid,
        xout = p_grid,
        method = "linear",
        rule = 2
      )$y
    }
    quantile_grid[quantile_grid < boundary_buffer] <- boundary_buffer
    quantile_grid[quantile_grid > (1 - boundary_buffer)] <- (1 -
      boundary_buffer)
  }

  copula_params <- if (inherits(copula_obj, "tCopula")) {
    list(rho = copula_obj@parameters[1], df = copula_obj@parameters[2])
  } else if (inherits(copula_obj, "normalCopula")) {
    list(rho = copula_obj@parameters[1])
  } else {
    list(param = copula_obj@parameters)
  }

  result <- list(
    u_grid = u_grid,
    v_grid = v_grid,
    conditional_cdf = conditional_cdf,
    quantile_grid = quantile_grid,
    p_grid = p_grid,
    u_grid_size = u_grid_size,
    v_grid_size = v_grid_size,
    boundary_buffer = boundary_buffer,
    copula_family = class(copula_obj)[1],
    copula_params = copula_params,
    created_at = Sys.time()
  )
  class(result) <- "kernel_cache"
  result
}


# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------
.locate_self <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args)
  if (length(m) > 0) {
    return(normalizePath(
      sub("^--file=", "", args[m[1]]),
      winslash = "/",
      mustWork = TRUE
    ))
  }
  # source() path
  this_path <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(this_path) && nzchar(this_path)) {
    return(normalizePath(this_path, winslash = "/", mustWork = TRUE))
  }
  # Last-ditch: assume we're in D3_Interactive/ or D3_Interactive/R/
  guesses <- c(
    file.path(getwd(), "R", "liwld_precompute.R"),
    file.path(getwd(), "liwld_precompute.R")
  )
  for (g in guesses) {
    if (file.exists(g)) return(normalizePath(g, winslash = "/"))
  }
  stop(
    "Could not locate liwld_precompute.R. Run via Rscript or source() with chdir=TRUE."
  )
}

self_path <- .locate_self()
r_dir <- dirname(self_path) # .../D3_Interactive/R
d3_interactive_dir <- normalizePath(file.path(r_dir, ".."), winslash = "/") # .../D3_Interactive
analytic_dir <- normalizePath(
  file.path(d3_interactive_dir, ".."),
  winslash = "/"
) # .../Analytic_Explanation
figures_dir <- normalizePath(file.path(analytic_dir, ".."), winslash = "/") # .../Figures
step3_dir <- normalizePath(file.path(figures_dir, ".."), winslash = "/") # .../STEP_3_LIwLD
project_root <- normalizePath(file.path(step3_dir, ".."), winslash = "/") # .../Copula_Sensitivity_Analyses

cat("LIwLD precompute starting...\n")
cat("  D3_Interactive:", d3_interactive_dir, "\n")
cat("  STEP_3_LIwLD  :", step3_dir, "\n")


# ---------------------------------------------------------------------------
# Load STEP 3 inference engine + local helpers
# ---------------------------------------------------------------------------
required_sources <- c(
  file.path(step3_dir, "functions", "copula_kernel_cache.R"),
  file.path(step3_dir, "functions", "regime_families.R"),
  file.path(step3_dir, "functions", "predict_v_cdf.R"),
  file.path(step3_dir, "functions", "distance_metrics.R")
)
for (src in required_sources) {
  if (!file.exists(src)) {
    stop("Required source missing: ", src)
  }
  source(src, local = FALSE)
}

source(file.path(r_dir, "induced_cdf.R"))
source(file.path(r_dir, "export_bundle.R"))


# ---------------------------------------------------------------------------
# Scenario configuration
# ---------------------------------------------------------------------------
LIWLD_PRECOMPUTE_CONFIG <- list(
  scenario_id = "liwld_phase_a_v1",
  scenario_label = "Phase A canonical (de-identified)",
  data_classification = "INTERNAL", # bump to PUBLIC after stakeholder review

  # Regime grid (45 x 30 = 1,350 cells; bilinear-interpolated client-side)
  regime_grid = list(
    m_min = 0.05,
    m_max = 0.95,
    m_n = 45L,
    k_min = 1.5,
    k_max = 60.0,
    k_n = 30L
  ),

  # V-axis grid for induced CDFs
  v_n = 200L,
  boundary_buffer = 0.005,

  # Kernel cache resolution (one-time cost; doesn't affect bundle size)
  kernel_grid_size = 201L,

  # Cohort/count overrides applied when the payload doesn't carry these
  # fields.  Edit per-scenario; the precompute will warn loudly when it
  # falls back to overrides instead of payload values.
  cohort_override = list(
    grade_prior = 5L,
    grade_current = 6L,
    year_prior = "2008",
    year_current = "2009",
    content_area = "MATHEMATICS",
    subgroup_filter = "DISTRICT_NUMBER == \"0020\""
  ),
  n_population_override = NA_integer_, # NA_integer_ -> precompute will fall back to n_subgroup with warning

  # Synthetic-mode parameters (only used when STEP3_EXPORT_MODE=SYNTHETIC)
  synthetic = list(
    seed = 20260211L,
    n_students = 3500L,
    true_regime_mean = 0.39,
    true_regime_kappa = 18,
    copula_rho = 0.72,
    copula_df = 8,
    u_alpha = 2.8,
    u_beta = 2.4
  )
)


# ---------------------------------------------------------------------------
# Field probes — try a list of expressions and return the first non-NULL,
# non-NA, non-empty value.  Tracks provenance for diagnostic output.
# ---------------------------------------------------------------------------
.probe <- function(..., default = NULL, label = "<field>") {
  exprs <- match.call(expand.dots = FALSE)$...
  parent <- parent.frame()
  for (i in seq_along(exprs)) {
    v <- tryCatch(eval(exprs[[i]], envir = parent), error = function(e) NULL)
    is_na_scalar <- length(v) == 1L && is.atomic(v) && is.na(v)
    if (!is.null(v) && length(v) > 0L && !is_na_scalar) {
      attr(v, "liwld_source") <- deparse(exprs[[i]])
      return(v)
    }
  }
  if (!is.null(default)) {
    attr(default, "liwld_source") <- "<default>"
    return(default)
  }
  attr(NA, "liwld_source") <- "<missing>"
  NA
}

# Parse a STEP 3 subgroup_id like "2008_G5_G6_MATHEMATICS__0020".
# Returns a named list (year_prior, grade_prior, grade_current, content_area,
# subgroup_value) or NULL when the string doesn't match the convention.
.parse_subgroup_id <- function(id) {
  if (is.null(id) || !is.character(id) || !nzchar(id)) {
    return(NULL)
  }
  pattern <- "^(\\d{4})_G(\\d+)_G(\\d+)_([A-Za-z][A-Za-z0-9]*)(?:__(.+))?$"
  m <- regmatches(id, regexec(pattern, id, perl = TRUE))[[1]]
  if (length(m) < 5L) {
    return(NULL)
  }
  list(
    year_prior = m[2],
    grade_prior = as.integer(m[3]),
    grade_current = as.integer(m[4]),
    content_area = m[5],
    subgroup_value = if (length(m) >= 6L && nzchar(m[6])) {
      m[6]
    } else {
      NA_character_
    }
  )
}

.LIWLD_COPULA_FAMILY_ENUM <- c("t", "gaussian", "frank", "clayton", "gumbel")

# Normalize an R copula class name (e.g. "tCopula", "normalCopula") to the
# manifest schema's family enum.  Returns NA when the input doesn't map to a
# supported family — callers fall through to the next probe.
.normalize_copula_family <- function(x) {
  if (is.null(x) || (length(x) == 1L && is.atomic(x) && is.na(x))) {
    return(NA_character_)
  }
  x <- tolower(as.character(x[1]))
  x <- sub("copula$", "", x)
  if (x == "normal") {
    x <- "gaussian"
  }
  if (!(x %in% .LIWLD_COPULA_FAMILY_ENUM)) {
    warning(
      "Unrecognized copula family '",
      x,
      "'; falling back.",
      call. = FALSE
    )
    return(NA_character_)
  }
  x
}

# Infer year_current from year_prior assuming sequential annual cohorts.
.next_year <- function(yp) {
  if (is.null(yp) || is.na(yp) || !grepl("^\\d{4}$", yp)) {
    return(NULL)
  }
  sprintf("%04d", as.integer(yp) + 1L)
}

# Count stayers in Margins/data/longitudinal_pairs.csv for the resolved cohort.
# This gives a real population count (n_pop ~= 53,791 for G5->G6 MATH 2008->2009),
# closer to the analyst's intent than falling back to n_subgroup.  Returns
# NULL when the CSV is missing, when data.table isn't available, or when no
# rows match the cohort.
.count_population_stayers_from_csv <- function(csv_path, cohort) {
  if (!file.exists(csv_path)) {
    return(NULL)
  }
  if (!requireNamespace("data.table", quietly = TRUE)) {
    message(
      "  (skipping CSV-based n_population: data.table package not installed)"
    )
    return(NULL)
  }

  pairs <- tryCatch(
    data.table::fread(
      csv_path,
      colClasses = list(
        character = c(
          "ID",
          "DISTRICT_NUMBER",
          "SCHOOL_NUMBER",
          "TYPE",
          "YEAR_PRIOR",
          "YEAR_CURRENT",
          "CONTENT_AREA"
        )
      ),
      showProgress = FALSE
    ),
    error = function(e) {
      message(
        "  (skipping CSV-based n_population: read error — ",
        conditionMessage(e),
        ")"
      )
      NULL
    }
  )
  if (is.null(pairs) || nrow(pairs) == 0) {
    return(NULL)
  }

  # Defensive cohort filter — works whether the CSV is single- or multi-condition.
  cohort_mask <-
    pairs[["YEAR_PRIOR"]] == as.character(cohort$year_prior) &
    pairs[["YEAR_CURRENT"]] == as.character(cohort$year_current) &
    pairs[["CONTENT_AREA"]] == as.character(cohort$content_area) &
    as.integer(pairs[["GRADE_PRIOR"]]) == as.integer(cohort$grade_prior) &
    as.integer(pairs[["GRADE_CURRENT"]]) == as.integer(cohort$grade_current)
  matched <- pairs[cohort_mask]

  if (nrow(matched) == 0L) {
    message(sprintf(
      "  (CSV had %s rows but none matched cohort %s/%s G%d->G%d %s)",
      format(nrow(pairs), big.mark = ","),
      cohort$year_prior,
      cohort$year_current,
      cohort$grade_prior,
      cohort$grade_current,
      cohort$content_area
    ))
    return(NULL)
  }

  n_pop <- as.integer(sum(matched[["TYPE"]] == "stayer"))
  if (n_pop <= 0L) {
    return(NULL)
  }
  n_pop
}

.warn_default <- function(label, value) {
  src <- attr(value, "liwld_source")
  if (identical(src, "<default>") || identical(src, "<missing>")) {
    cat(sprintf(
      "  [defaulted] %-26s -> %s  (source: %s)\n",
      label,
      paste(format(utils::head(value, 3)), collapse = ", "),
      src
    ))
  } else {
    cat(sprintf(
      "  [from payload] %-23s -> %s  (source: %s)\n",
      label,
      paste(format(utils::head(value, 3)), collapse = ", "),
      src
    ))
  }
  # strip the attribute so it doesn't leak into manifest values
  attr(value, "liwld_source") <- NULL
  value
}


# ---------------------------------------------------------------------------
# Stage 1 --- Acquire the data fixtures
#   Output of this stage:
#       u_sample (numeric in (0,1))
#       v_sample (numeric in (0,1))
#       copula_obj (copula::Copula)
#       copula_meta (family/rho/df/etc — populates manifest$copula)
#       cohort (manifest$cohort)
#       n_population, n_subgroup
# ---------------------------------------------------------------------------
export_mode <- toupper(Sys.getenv(
  "STEP3_EXPORT_MODE",
  unset = "PHASE_A_REAL_DATA"
))
cat("\nMode:", export_mode, "\n")

if (export_mode == "PHASE_A_REAL_DATA") {
  rds_path <- file.path(step3_dir, "results", "phase_a_analytic_payload.rds")
  if (!file.exists(rds_path)) {
    stop(
      "Phase A payload not found at:\n  ",
      rds_path,
      "\nSet STEP3_EXPORT_MODE=SYNTHETIC for a development run."
    )
  }
  pa <- readRDS(rds_path)
  cat("Loaded Phase A payload from:", rds_path, "\n")
  cat("Top-level fields:", paste(names(pa), collapse = ", "), "\n\n")

  u_sample <- pa$u_sample
  v_sample <- pa$v_sample

  # Parse the encoded identifiers if present.  In the canonical Phase A
  # payload, cohort metadata is *only* stored encoded in subgroup_id /
  # condition_id (e.g., "2008_G5_G6_MATHEMATICS__0020").
  sg_parsed <- .parse_subgroup_id(pa$subgroup_id)
  cond_parsed <- .parse_subgroup_id(pa$condition_id)
  if (!is.null(sg_parsed)) {
    cat(
      "Parsed subgroup_id  ->  year =",
      sg_parsed$year_prior,
      ", grades =",
      sg_parsed$grade_prior,
      "->",
      sg_parsed$grade_current,
      ", content =",
      sg_parsed$content_area,
      ", subgroup_value =",
      sg_parsed$subgroup_value,
      "\n"
    )
  }

  # ---- Copula --------------------------------------------------------------
  cat("Resolving copula metadata:\n")
  copula_family <- .warn_default(
    "copula.family",
    .probe(
      .normalize_copula_family(pa$copula_used$family),
      .normalize_copula_family(pa$config$copula_family),
      default = "t",
      label = "copula.family"
    )
  )
  copula_rho <- .warn_default(
    "copula.rho",
    .probe(
      pa$copula_used$params$rho,
      pa$config$copula_rho,
      default = 0.84,
      label = "copula.rho"
    )
  )
  copula_df <- .warn_default(
    "copula.df",
    .probe(
      pa$copula_used$params$df,
      pa$config$copula_df,
      default = 25,
      label = "copula.df"
    )
  )

  copula_meta <- list(
    family = as.character(copula_family),
    rho = as.numeric(copula_rho),
    df = as.numeric(copula_df)
  )
  if (!is.null(pa$copula_used$tau)) {
    copula_meta$tau <- pa$copula_used$tau
  }
  if (!is.null(pa$copula_used$tail_dep_lower)) {
    copula_meta$tail_dep_lower <- pa$copula_used$tail_dep_lower
  }
  if (!is.null(pa$copula_used$tail_dep_upper)) {
    copula_meta$tail_dep_upper <- pa$copula_used$tail_dep_upper
  }

  # mvtnorm::pmvt() requires integer df; preserve the true fitted df in the
  # statistical record but stash an integer for Panel 2 contour rendering.
  if (!is.integer(copula_meta$df) && copula_meta$df != round(copula_meta$df)) {
    copula_meta$df_display <- as.integer(round(copula_meta$df))
  }

  copula_obj <- copula::tCopula(
    param = as.numeric(copula_rho),
    df = as.numeric(copula_df),
    dim = 2,
    dispstr = "un",
    df.fixed = TRUE
  )

  # ---- Cohort (parsed subgroup_id wins; per-scenario override is final fallback) -
  cat("\nResolving cohort metadata:\n")
  ovr <- LIWLD_PRECOMPUTE_CONFIG$cohort_override

  yp_resolved <- as.character(.warn_default(
    "cohort.year_prior",
    .probe(
      sg_parsed$year_prior,
      cond_parsed$year_prior,
      pa$cohort$year_prior,
      pa$config$year_prior,
      pa$metadata$year_prior,
      default = ovr$year_prior,
      label = "cohort.year_prior"
    )
  ))

  # subgroup_id only encodes year_prior; year_current is conventionally +1
  yc_inferred <- .next_year(yp_resolved)
  yc_resolved <- as.character(.warn_default(
    "cohort.year_current",
    .probe(
      pa$cohort$year_current,
      pa$config$year_current,
      pa$metadata$year_current,
      yc_inferred,
      default = ovr$year_current,
      label = "cohort.year_current"
    )
  ))

  # Build a subgroup_filter expression from the encoded col/value pair when present.
  inferred_filter <- if (
    !is.null(pa$subgroup_col) &&
      !is.null(pa$subgroup_value) &&
      nzchar(pa$subgroup_col) &&
      nzchar(pa$subgroup_value)
  ) {
    sprintf('%s == "%s"', pa$subgroup_col, pa$subgroup_value)
  } else {
    NULL
  }

  cohort <- list(
    grade_prior = as.integer(.warn_default(
      "cohort.grade_prior",
      .probe(
        sg_parsed$grade_prior,
        cond_parsed$grade_prior,
        pa$cohort$grade_prior,
        pa$config$grade_prior,
        pa$metadata$grade_prior,
        default = ovr$grade_prior,
        label = "cohort.grade_prior"
      )
    )),
    grade_current = as.integer(.warn_default(
      "cohort.grade_current",
      .probe(
        sg_parsed$grade_current,
        cond_parsed$grade_current,
        pa$cohort$grade_current,
        pa$config$grade_current,
        pa$metadata$grade_current,
        default = ovr$grade_current,
        label = "cohort.grade_current"
      )
    )),
    year_prior = yp_resolved,
    year_current = yc_resolved,
    content_area = as.character(.warn_default(
      "cohort.content_area",
      .probe(
        sg_parsed$content_area,
        cond_parsed$content_area,
        pa$cohort$content_area,
        pa$config$content_area,
        pa$metadata$content_area,
        default = ovr$content_area,
        label = "cohort.content_area"
      )
    )),
    subgroup_filter = as.character(.warn_default(
      "cohort.subgroup_filter",
      .probe(
        inferred_filter,
        pa$cohort$subgroup_filter,
        pa$config$subgroup_filter,
        pa$metadata$subgroup_filter,
        default = ovr$subgroup_filter,
        label = "cohort.subgroup_filter"
      )
    ))
  )

  # ---- Counts --------------------------------------------------------------
  cat("\nResolving counts:\n")
  n_subgroup <- as.integer(.warn_default(
    "n_subgroup",
    .probe(pa$n_subgroup, length(u_sample), label = "n_subgroup")
  ))

  # Try the canonical Margins CSV next: it has the same condition's full
  # population pool, and gives a meaningful "subgroup is X of Y" context.
  margins_csv <- file.path(
    analytic_dir,
    "Margins",
    "data",
    "longitudinal_pairs.csv"
  )
  n_pop_from_csv <- .count_population_stayers_from_csv(margins_csv, cohort)

  npop_override <- LIWLD_PRECOMPUTE_CONFIG$n_population_override
  n_population_resolved <- .probe(
    n_pop_from_csv,
    pa$n_population,
    pa$config$n_population,
    pa$population_size,
    length(pa$u_sample_population),
    length(pa$u_sample_pop),
    label = "n_population"
  )
  if (
    length(n_population_resolved) == 1L &&
      is.atomic(n_population_resolved) &&
      is.na(n_population_resolved)
  ) {
    if (!is.na(npop_override)) {
      n_population_resolved <- as.integer(npop_override)
      attr(n_population_resolved, "liwld_source") <- "<config override>"
    } else {
      n_population_resolved <- as.integer(n_subgroup)
      attr(n_population_resolved, "liwld_source") <- "<fallback to n_subgroup>"
      cat(
        "  WARNING: n_population could not be derived from CSV, payload, or override.\n"
      )
      cat("           Falling back to n_subgroup.  Set\n")
      cat(
        "           LIWLD_PRECOMPUTE_CONFIG$n_population_override or run the\n"
      )
      cat(
        "           Margins extractor (Margins/step3_extract_pairs.R) to fix.\n"
      )
    }
  }
  n_population <- as.integer(.warn_default(
    "n_population",
    n_population_resolved
  ))

  # Schema enforcement: cohort.grade_prior is an integer >= 0.  Halt if NA.
  for (field in c("grade_prior", "grade_current")) {
    if (is.na(cohort[[field]])) {
      stop(
        "cohort$",
        field,
        " is NA after all probes and overrides.  ",
        "Set LIWLD_PRECOMPUTE_CONFIG$cohort_override$",
        field,
        " in liwld_precompute.R."
      )
    }
  }
  cat("\n")
} else if (export_mode == "SYNTHETIC") {
  cfg <- LIWLD_PRECOMPUTE_CONFIG$synthetic
  set.seed(cfg$seed)

  u_sample <- stats::rbeta(
    cfg$n_students,
    shape1 = cfg$u_alpha,
    shape2 = cfg$u_beta
  )

  copula_obj <- copula::tCopula(
    param = cfg$copula_rho,
    df = cfg$copula_df,
    dim = 2,
    dispstr = "un",
    df.fixed = TRUE
  )
  copula_meta <- list(family = "t", rho = cfg$copula_rho, df = cfg$copula_df)

  # Sample V via the synthetic regime, drop the linkage (cross-section).
  true_regime <- regime_beta(cfg$true_regime_mean, cfg$true_regime_kappa)
  kc_for_synth <- .build_kernel_cache_safe(
    copula_obj = copula_obj,
    u_grid_size = LIWLD_PRECOMPUTE_CONFIG$kernel_grid_size,
    v_grid_size = LIWLD_PRECOMPUTE_CONFIG$kernel_grid_size,
    boundary_buffer = LIWLD_PRECOMPUTE_CONFIG$boundary_buffer,
    compute_quantile = TRUE
  )
  latent_p <- true_regime$quantile(stats::runif(cfg$n_students))
  v_linked <- kernel_conditional_quantile(
    p = latent_p,
    u = u_sample,
    cache = kc_for_synth
  )
  v_sample <- sample(v_linked, length(v_linked), replace = FALSE)

  cohort <- list(
    grade_prior = 6L,
    grade_current = 7L,
    year_prior = "2023",
    year_current = "2024",
    content_area = "MATHEMATICS",
    subgroup_filter = sprintf("synthetic seed=%d", cfg$seed)
  )
  n_subgroup <- length(u_sample)
  n_population <- length(u_sample) # identical for synthetic
  rm(kc_for_synth, latent_p, v_linked, true_regime)
} else {
  stop(
    "Unknown STEP3_EXPORT_MODE: ",
    export_mode,
    ". Use 'PHASE_A_REAL_DATA' or 'SYNTHETIC'."
  )
}


# ---------------------------------------------------------------------------
# Stage 2 --- Build the kernel cache + regime grid + v-grid
# ---------------------------------------------------------------------------
cat(
  "\nBuilding kernel cache (",
  LIWLD_PRECOMPUTE_CONFIG$kernel_grid_size,
  "x",
  LIWLD_PRECOMPUTE_CONFIG$kernel_grid_size,
  ")...\n",
  sep = ""
)

kernel_cache <- .build_kernel_cache_safe(
  copula_obj = copula_obj,
  u_grid_size = LIWLD_PRECOMPUTE_CONFIG$kernel_grid_size,
  v_grid_size = LIWLD_PRECOMPUTE_CONFIG$kernel_grid_size,
  boundary_buffer = LIWLD_PRECOMPUTE_CONFIG$boundary_buffer,
  compute_quantile = FALSE # we don't need the quantile grid for this script
)

reg <- do.call(make_regime_grid, c(LIWLD_PRECOMPUTE_CONFIG$regime_grid))
m_grid <- reg$m_grid
k_grid <- reg$k_grid

v_grid <- seq(
  LIWLD_PRECOMPUTE_CONFIG$boundary_buffer,
  1 - LIWLD_PRECOMPUTE_CONFIG$boundary_buffer,
  length.out = LIWLD_PRECOMPUTE_CONFIG$v_n
)

cat(
  "Grid: m_n =",
  length(m_grid),
  ", k_n =",
  length(k_grid),
  ", v_n =",
  length(v_grid),
  "(total cells:",
  length(m_grid) * length(k_grid),
  ")\n"
)


# ---------------------------------------------------------------------------
# Stage 3 --- Observed V CDF (target for W_1) and induced-CDF tensor sweep
# ---------------------------------------------------------------------------
cat("\nComputing observed V CDF (subgroup)...\n")
F_obs_sub <- observed_marginal_cdf(v_grid = v_grid, v_sample = v_sample)

cat("Sweeping (m, kappa) grid...\n")
sweep <- build_induced_cdf_tensor(
  m_grid = m_grid,
  k_grid = k_grid,
  v_grid = v_grid,
  u_sample = u_sample,
  kernel_cache = kernel_cache,
  f_obs = F_obs_sub,
  verbose = TRUE,
  progress_every = 100L
)


# ---------------------------------------------------------------------------
# Stage 4 --- Reference points: argmin (already from sweep) + uniform_ref
# ---------------------------------------------------------------------------
argmin <- sweep$argmin
cat(
  "\nargmin: m =",
  round(argmin$m, 4),
  ", kappa =",
  round(argmin$k, 3),
  ", W1 =",
  round(argmin$w1, 6),
  "\n"
)

# Uniform regime is Beta(0.5, 2). Compute its W_1 off-grid so we have the
# exact baseline number for the relative readout, regardless of grid spacing.
uniform_regime <- regime_beta(0.5, 2)
F_uniform <- predict_marginal_cdf(
  v_grid = v_grid,
  u_sample = u_sample,
  regime = uniform_regime,
  kernel_cache = kernel_cache
)
F_uniform <- cummax(pmin(pmax(F_uniform, 0), 1))
w1_uniform <- {
  v_n <- length(v_grid)
  dv <- diff(v_grid)
  h_mid <- 0.5 *
    (abs(F_uniform[-1] - F_obs_sub[-1]) +
      abs(F_uniform[-v_n] - F_obs_sub[-v_n]))
  sum(h_mid * dv)
}
uniform_ref <- list(m = 0.5, k = 2, w1 = w1_uniform)
cat("uniform_ref: m = 0.5, kappa = 2, W1 =", round(w1_uniform, 6), "\n")


# ---------------------------------------------------------------------------
# Stage 5 --- Panel 1 and Panel 5 observed curves
# ---------------------------------------------------------------------------
cat("\nBuilding Panel 1 (U curves)...\n")
u_curve_grid <- v_grid # share the same axis convention; both live on (0,1)
u_density_sub <- stats::density(
  u_sample,
  from = 0,
  to = 1,
  n = length(u_curve_grid),
  bw = "SJ"
)
panel_1 <- list(
  u = u_curve_grid,
  pdf_pop = rep(1, length(u_curve_grid)), # uniform by construction
  pdf_sub = stats::approx(
    u_density_sub$x,
    u_density_sub$y,
    xout = u_curve_grid,
    rule = 2
  )$y,
  cdf_pop = u_curve_grid, # F(u) = u
  cdf_sub = stats::ecdf(u_sample)(u_curve_grid)
)

cat("Building Panel 5 observed (V curves)...\n")
v_density_sub <- stats::density(
  v_sample,
  from = 0,
  to = 1,
  n = length(v_grid),
  bw = "SJ"
)
panel_5_observed <- list(
  v = v_grid,
  pdf_pop = rep(1, length(v_grid)),
  pdf_sub = stats::approx(
    v_density_sub$x,
    v_density_sub$y,
    xout = v_grid,
    rule = 2
  )$y,
  cdf_pop = v_grid, # F(v) = v
  cdf_sub = F_obs_sub
)


# ---------------------------------------------------------------------------
# Stage 6 --- Panel 2 copula contours
# ---------------------------------------------------------------------------
cat("Building Panel 2 (copula contours)...\n")
contour_n <- 81L
gseq <- seq(0, 1, length.out = contour_n)
uv <- as.matrix(expand.grid(u = gseq, v = gseq))

# copula::pCopula() on a tCopula ultimately calls mvtnorm::pmvt(), which
# *requires* integer (or Inf) degrees of freedom.  Fitted Phase A payloads
# routinely carry a non-integer df (the MLE).  cCopula() — used by the
# kernel cache and all statistical sweeps — has a closed form and is
# unaffected.  The contour grid is purely a visual artifact, so we build
# a display-only copula with df rounded to the nearest positive integer
# and leave copula_obj / copula_meta untouched (the manifest still
# records the true fitted df).
copula_for_contours <- copula_obj
if (inherits(copula_obj, "tCopula")) {
  df_val <- copula_obj@parameters[2]
  if (
    is.finite(df_val) && abs(df_val - round(df_val)) > .Machine$double.eps^0.5
  ) {
    df_int <- max(1L, as.integer(round(df_val)))
    cat(sprintf(
      "  Note: rounding df = %.4f -> %d for contour rendering only\n",
      df_val,
      df_int
    ))
    copula_for_contours <- copula::tCopula(
      param = copula_obj@parameters[1],
      df = df_int,
      dim = 2,
      dispstr = "un",
      df.fixed = TRUE
    )
    # Surface the rounded df on the manifest so the D3 frontend can show
    # both the fitted df and the integer df used for the contour render
    # (e.g., in the Panel 2 tooltip: "df = 7.30 (contours: 7)").
    copula_meta$df_display <- df_int
  }
}

cat("  Evaluating copula CDF on", contour_n, "x", contour_n, "grid...\n")
cdf_mat <- matrix(
  copula::pCopula(uv, copula_for_contours),
  nrow = contour_n,
  ncol = contour_n
)

contour_levels <- seq(0.1, 0.9, by = 0.1)
panel_2 <- lapply(contour_levels, function(lv) {
  cl <- grDevices::contourLines(gseq, gseq, cdf_mat, levels = lv)
  paths <- lapply(cl, function(seg) cbind(seg$x, seg$y))
  list(level = lv, paths = paths)
})


# ---------------------------------------------------------------------------
# Stage 7 --- Write the bundle
# ---------------------------------------------------------------------------
scenario_dir <- file.path(
  d3_interactive_dir,
  "data",
  "scenarios",
  LIWLD_PRECOMPUTE_CONFIG$scenario_id
)

scenario_meta <- list(
  id = LIWLD_PRECOMPUTE_CONFIG$scenario_id,
  label = LIWLD_PRECOMPUTE_CONFIG$scenario_label,
  data_source = export_mode,
  data_classification = LIWLD_PRECOMPUTE_CONFIG$data_classification,
  cohort = cohort,
  n_subgroup = n_subgroup,
  n_population = n_population,
  copula = copula_meta
)

cat("\nWriting bundle to:", scenario_dir, "\n")
res <- write_scenario_bundle(
  dest_dir = scenario_dir,
  scenario = scenario_meta,
  panel_1 = panel_1,
  panel_2 = panel_2,
  panel_3 = sweep$w1,
  panel_5_observed = panel_5_observed,
  panel_5_induced = sweep$tensor,
  regime_grid_spec = reg$spec,
  v_grid = v_grid,
  argmin = argmin,
  uniform_ref = uniform_ref
)

cat("\nDone.  Manifest at:\n  ", res$manifest_path, "\n", sep = "")
