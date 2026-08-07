###############################################################################
###
### inspect_phase_a_payload.R --- Dump the structure of the Phase A payload
### and confirm the precompute can resolve every manifest field.
###
### This mirrors the actual probe chain in liwld_precompute.R (v0.1.3+):
###   - cohort: parse `subgroup_id` / `condition_id`; infer year_current
###   - copula: normalize family ("tCopula" -> "t")
###   - n_subgroup: pa$n_subgroup
###   - n_population: count stayers in Margins/data/longitudinal_pairs.csv
###
### Run from D3_Interactive/:
###   Rscript R/inspect_phase_a_payload.R
###
### Output: top-level fields, full str() dump, and a "what the precompute
### will actually use" report — every line should read OK before running
### liwld_precompute.R.
###
###############################################################################

## Polyfill %||% for R < 4.4
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

self_path <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args)
  if (length(m) > 0) {
    return(normalizePath(
      sub("^--file=", "", args[m[1]]),
      winslash = "/",
      mustWork = TRUE
    ))
  }
  this_path <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(this_path) && nzchar(this_path)) {
    return(normalizePath(this_path, winslash = "/", mustWork = TRUE))
  }
  stop("Run via Rscript or source() with chdir = TRUE.")
})()

r_dir <- dirname(self_path)
d3_interactive_dir <- normalizePath(file.path(r_dir, ".."), winslash = "/")
analytic_dir <- normalizePath(
  file.path(d3_interactive_dir, ".."),
  winslash = "/"
)
figures_dir <- normalizePath(file.path(analytic_dir, ".."), winslash = "/")
step3_dir <- normalizePath(file.path(figures_dir, ".."), winslash = "/")

rds_path <- file.path(step3_dir, "results", "phase_a_analytic_payload.rds")
if (!file.exists(rds_path)) {
  stop("Payload not found at: ", rds_path)
}

cat("Loading:", rds_path, "\n\n")
pa <- readRDS(rds_path)

cat("=== Top-level fields ===\n")
print(names(pa))

cat("\n=== str(pa, max.level = 2) ===\n")
str(pa, max.level = 2)


# ---------------------------------------------------------------------------
# Mirror the precompute's actual probe chain.
# ---------------------------------------------------------------------------
# Helpers (kept in sync with R/liwld_precompute.R)
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
.normalize_copula_family <- function(x) {
  if (is.null(x)) {
    return(NA_character_)
  }
  x <- tolower(as.character(x[1]))
  x <- sub("copula$", "", x)
  if (x == "normal") {
    x <- "gaussian"
  }
  if (!(x %in% c("t", "gaussian", "frank", "clayton", "gumbel"))) {
    return(NA_character_)
  }
  x
}
.next_year <- function(yp) {
  if (is.null(yp) || is.na(yp) || !grepl("^\\d{4}$", yp)) {
    return(NULL)
  }
  sprintf("%04d", as.integer(yp) + 1L)
}

report <- function(label, value) {
  ok <- !is.null(value) &&
    length(value) > 0L &&
    !(length(value) == 1L && is.atomic(value) && is.na(value))
  status <- if (ok) "OK    " else "MISSING"
  shown <- if (ok) paste(format(utils::head(value, 3)), collapse = ", ") else ""
  cat(sprintf("  %s  %-40s %s\n", status, label, shown))
}

cat("\n=== What the precompute will resolve ===\n\n")

sg <- .parse_subgroup_id(pa$subgroup_id)
cond <- .parse_subgroup_id(pa$condition_id)
cat("subgroup_id parsed (", deparse(pa$subgroup_id), "):\n", sep = "")
str(sg)
cat("\ncondition_id parsed (", deparse(pa$condition_id), "):\n", sep = "")
str(cond)

cat("\nCohort:\n")
yp <- sg$year_prior %||% cond$year_prior # NB: %||% requires R >= 4.4 or rlang
yp <- if (!is.null(yp)) yp else NULL
report("year_prior", yp)
report("year_current (inferred)", .next_year(yp))
report("grade_prior", sg$grade_prior %||% cond$grade_prior)
report("grade_current", sg$grade_current %||% cond$grade_current)
report("content_area", sg$content_area %||% cond$content_area)
sg_filter <- if (!is.null(pa$subgroup_col) && !is.null(pa$subgroup_value)) {
  sprintf('%s == "%s"', pa$subgroup_col, pa$subgroup_value)
} else {
  NULL
}
report("subgroup_filter", sg_filter)

cat("\nCopula:\n")
report("family (normalized)", .normalize_copula_family(pa$copula_used$family))
report("rho", pa$copula_used$params$rho)
report("df", pa$copula_used$params$df)

cat("\nCounts:\n")
report("n_subgroup", pa$n_subgroup)

# n_population from CSV
margins_csv <- file.path(
  analytic_dir,
  "Margins",
  "data",
  "longitudinal_pairs.csv"
)
if (
  file.exists(margins_csv) && requireNamespace("data.table", quietly = TRUE)
) {
  pairs <- data.table::fread(
    margins_csv,
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
  )
  if (!is.null(sg)) {
    yc <- .next_year(sg$year_prior)
    matched <- pairs[
      pairs$YEAR_PRIOR == sg$year_prior &
        pairs$YEAR_CURRENT == yc &
        pairs$CONTENT_AREA == sg$content_area &
        as.integer(pairs$GRADE_PRIOR) == sg$grade_prior &
        as.integer(pairs$GRADE_CURRENT) == sg$grade_current
    ]
    n_pop <- as.integer(sum(matched$TYPE == "stayer"))
    cat(sprintf(
      "  CSV match: %s rows for cohort, of which %d are stayers.\n",
      format(nrow(matched), big.mark = ","),
      n_pop
    ))
    report("n_population (from CSV)", if (n_pop > 0L) n_pop else NULL)
  } else {
    cat("  Skipping CSV match: subgroup_id did not parse.\n")
  }
} else {
  cat(sprintf("  Margins CSV not at: %s\n", margins_csv))
  cat("  (Or data.table not installed.)  liwld_precompute.R will fall back\n")
  cat("  to LIWLD_PRECOMPUTE_CONFIG$n_population_override or n_subgroup.\n")
}

cat(
  "\nDone.  Every line above should read OK before running liwld_precompute.R.\n"
)
