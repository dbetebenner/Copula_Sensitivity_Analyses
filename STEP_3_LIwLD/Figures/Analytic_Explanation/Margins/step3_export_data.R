###############################################################################
###
### step3_export_data.R - Export panel-ready data for Margins scatter infographic
###
### Reads the intermediate CSV produced by step3_extract_pairs.R (real
### longitudinal assessment data) and generates PSTricks-ready data files
### for the compound scatter plot with layered margin strips.
###
### Pipeline:
###   step3_extract_pairs.R  -->  data/longitudinal_pairs.csv  (run once)
###   step3_export_data.R    -->  data/*.dat, data/*.tex        (run by build)
###
### Subgroup filtering is controlled by `subgroup_filter` below.
### Population = ALL students in the intermediate file (all districts).
### Subgroup   = students matching the filter (e.g., one district).
###
### Output files (consumed by step3_panel_scatter_graphic.tex):
###   - pdf_bottom_pop_norm.dat, pdf_bottom_sub_norm.dat, cdf_bottom.dat
###   - pdf_left_pop_norm.dat, pdf_left_sub_norm.dat, cdf_left.dat
###   - scatter_stayers.tex, rug_bottom.tex, rug_left.tex
###   - scatter_params.tex, axis_limits.tex, cdf_trace_points.tex
###
### Usage: source("step3_export_data.R")  (from the Margins/ directory)
###
###############################################################################

require(data.table)

script_file <- sub("^--file=", "", commandArgs(trailingOnly = FALSE)[
  grep("^--file=", commandArgs(trailingOnly = FALSE))][1])
margins_dir <- if (!is.na(script_file) && nzchar(script_file)) {
  normalizePath(dirname(script_file), winslash = "/", mustWork = TRUE)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

data_dir <- file.path(margins_dir, "data")
if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)


###############################################################################
## Configuration
###############################################################################

# Intermediate CSV from step3_extract_pairs.R
pairs_csv <- file.path(data_dir, "longitudinal_pairs.csv")

# Subgroup filter expression (evaluated within the data.table)
# Change this to target a different district/school/etc.
subgroup_filter <- quote(DISTRICT_NUMBER == "0020")

# Maximum scatter dots to render (subsample for visual clarity)
max_scatter_dots <- 400

# Maximum rug marks per axis (too many overflows TeX memory)
max_rug_stayers <- 600

# Score-axis display range.  Set to NULL for auto from data.
score_display_min <- NULL   # e.g., 200
score_display_max <- NULL   # e.g., 800

# Grid resolution for PDF/CDF curves
n_grid <- 512


###############################################################################
## Helpers
###############################################################################

write_dat <- function(x, y, filename) {
  out <- file.path(data_dir, filename)
  writeLines(paste(x, y), out)
  cat("  ", filename, "\n")
}

write_tex_lines <- function(lines, filename) {
  out <- file.path(data_dir, filename)
  writeLines(lines, out)
  cat("  ", filename, "\n")
}


###############################################################################
## 1. Load intermediate data
###############################################################################

cat("\n=== Scatter Data Export (Real Data) ===\n")

if (!file.exists(pairs_csv)) {
  stop("Intermediate CSV not found:\n  ", pairs_csv,
       "\n  Run step3_extract_pairs.R first.")
}

pairs <- fread(pairs_csv, colClasses = list(
  character = c("ID", "DISTRICT_NUMBER", "SCHOOL_NUMBER", "TYPE",
                "YEAR_PRIOR", "YEAR_CURRENT", "CONTENT_AREA")
))
cat("  Loaded", format(nrow(pairs), big.mark = ","), "records from",
    basename(pairs_csv), "\n")

# Quick sanity
stopifnot("TYPE" %in% names(pairs))
stopifnot("SCALE_SCORE_PRIOR" %in% names(pairs))
stopifnot("SCALE_SCORE_CURRENT" %in% names(pairs))


###############################################################################
## 2. Split population vs subgroup
###############################################################################

# Population = ALL data (all districts)
pop_stayers  <- pairs[TYPE == "stayer"]
pop_leavers  <- pairs[TYPE == "leaver"]
pop_entrants <- pairs[TYPE == "entrant"]

# Subgroup = filtered by subgroup_filter
sub_all      <- pairs[eval(subgroup_filter)]
sub_stayers  <- sub_all[TYPE == "stayer"]
sub_leavers  <- sub_all[TYPE == "leaver"]
sub_entrants <- sub_all[TYPE == "entrant"]

cat("\n  Population:\n")
cat("    Stayers :", format(nrow(pop_stayers), big.mark = ","), "\n")
cat("    Leavers :", format(nrow(pop_leavers), big.mark = ","), "\n")
cat("    Entrants:", format(nrow(pop_entrants), big.mark = ","), "\n")
cat("\n  Subgroup (", deparse(subgroup_filter), "):\n")
cat("    Stayers :", nrow(sub_stayers), "\n")
cat("    Leavers :", nrow(sub_leavers), "\n")
cat("    Entrants:", nrow(sub_entrants), "\n")


###############################################################################
## 3. Population reference distributions (F_X^ref, F_Y^ref)
##    Fit normal to ALL students' marginals
###############################################################################

cat("\nFitting population reference distributions...\n")

all_prior_scores   <- pop_stayers$SCALE_SCORE_PRIOR
all_current_scores <- pop_stayers$SCALE_SCORE_CURRENT
# Include orphans in marginals for more accurate population reference
all_prior_scores   <- c(all_prior_scores, pop_leavers$SCALE_SCORE_PRIOR)
all_current_scores <- c(all_current_scores, pop_entrants$SCALE_SCORE_CURRENT)

pop_mu_x <- mean(all_prior_scores, na.rm = TRUE)
pop_sd_x <- sd(all_prior_scores, na.rm = TRUE)
pop_mu_y <- mean(all_current_scores, na.rm = TRUE)
pop_sd_y <- sd(all_current_scores, na.rm = TRUE)

cat("  Prior   N(", round(pop_mu_x, 1), ",", round(pop_sd_x, 1), ")\n")
cat("  Current N(", round(pop_mu_y, 1), ",", round(pop_sd_y, 1), ")\n")


###############################################################################
## 4. Score display range
###############################################################################

if (is.null(score_display_min) || is.null(score_display_max)) {
  all_scores <- c(all_prior_scores, all_current_scores)
  score_display_min <- floor(min(all_scores, na.rm = TRUE) / 50) * 50
  score_display_max <- ceiling(max(all_scores, na.rm = TRUE) / 50) * 50
}
score_min <- score_display_min
score_max <- score_display_max
cat("  Score display range:", score_min, "-", score_max, "\n")


###############################################################################
## 5. Pseudo-observations (PIT via population normal CDF)
###############################################################################

cat("\nComputing pseudo-observations...\n")

pit <- function(s, mu, sd) pnorm(s, mean = mu, sd = sd)

# Stayers
u_sub_stayers <- pit(sub_stayers$SCALE_SCORE_PRIOR, pop_mu_x, pop_sd_x)
v_sub_stayers <- pit(sub_stayers$SCALE_SCORE_CURRENT, pop_mu_y, pop_sd_y)

# Leavers (prior only)
u_sub_leavers <- pit(sub_leavers$SCALE_SCORE_PRIOR, pop_mu_x, pop_sd_x)

# Entrants (current only)
v_sub_entrants <- pit(sub_entrants$SCALE_SCORE_CURRENT, pop_mu_y, pop_sd_y)

# Clamp to (0.005, 0.995) so dots don't sit right on the frame
clamp01 <- function(x) pmax(0.005, pmin(0.995, x))
u_sub_stayers  <- clamp01(u_sub_stayers)
v_sub_stayers  <- clamp01(v_sub_stayers)
u_sub_leavers  <- clamp01(u_sub_leavers)
v_sub_entrants <- clamp01(v_sub_entrants)


###############################################################################
## 6. Subsample scatter dots for visual clarity
###############################################################################

n_stayers_actual <- nrow(sub_stayers)
n_leavers_actual <- nrow(sub_leavers)
n_entrants_actual <- nrow(sub_entrants)

if (n_stayers_actual > max_scatter_dots) {
  set.seed(42)
  idx <- sample.int(n_stayers_actual, max_scatter_dots)
  u_scatter <- u_sub_stayers[idx]
  v_scatter <- v_sub_stayers[idx]
  n_scatter <- max_scatter_dots
  cat("  Subsampled", max_scatter_dots, "of", n_stayers_actual, "stayers for scatter\n")
} else {
  u_scatter <- u_sub_stayers
  v_scatter <- v_sub_stayers
  n_scatter <- n_stayers_actual
}


###############################################################################
## 7. PDF and CDF curves (population and subgroup)
###############################################################################

cat("\nGenerating margin strip curves...\n")

x_grid <- seq(score_min, score_max, length.out = n_grid)
y_grid <- seq(score_min, score_max, length.out = n_grid)
x_norm <- (x_grid - score_min) / (score_max - score_min)
y_norm <- (y_grid - score_min) / (score_max - score_min)

## Population PDFs (normal)
pdf_prior_pop   <- dnorm(x_grid, mean = pop_mu_x, sd = pop_sd_x)
pdf_current_pop <- dnorm(y_grid, mean = pop_mu_y, sd = pop_sd_y)

## Population CDFs (normal)
cdf_prior   <- pnorm(x_grid, mean = pop_mu_x, sd = pop_sd_x)
cdf_current <- pnorm(y_grid, mean = pop_mu_y, sd = pop_sd_y)

## Subgroup PDFs (kernel density from actual scores)
sub_prior_scores   <- c(sub_stayers$SCALE_SCORE_PRIOR, sub_leavers$SCALE_SCORE_PRIOR)
sub_current_scores <- c(sub_stayers$SCALE_SCORE_CURRENT, sub_entrants$SCALE_SCORE_CURRENT)

if (length(sub_prior_scores) >= 10) {
  d_x <- density(sub_prior_scores, from = score_min, to = score_max, n = n_grid, bw = "SJ")
} else {
  d_x <- density(sub_prior_scores, from = score_min, to = score_max, n = n_grid)
}

if (length(sub_current_scores) >= 10) {
  d_y <- density(sub_current_scores, from = score_min, to = score_max, n = n_grid, bw = "SJ")
} else {
  d_y <- density(sub_current_scores, from = score_min, to = score_max, n = n_grid)
}


###############################################################################
## 8. Write data files for PSTricks
##    All x/y coordinates normalized to [0,1] for the margin strips
###############################################################################

cat("\nWriting PSTricks data files...\n")

# --- Bottom margin (prior scores) ---

max_pdf_bot <- max(c(d_x$y, pdf_prior_pop))
write_dat(round(x_norm, 6), round(pdf_prior_pop / max_pdf_bot, 6), "pdf_bottom_pop_norm.dat")
write_dat(round(x_norm, 6), round(d_x$y / max_pdf_bot, 6),         "pdf_bottom_sub_norm.dat")
write_dat(round(x_norm, 6), round(cdf_prior, 6),                    "cdf_bottom.dat")

# Also write raw-coord versions for backward compatibility
write_dat(round(x_grid, 2), round(pdf_prior_pop, 8),  "pdf_prior_pop.dat")
write_dat(round(d_x$x, 2),  round(d_x$y, 8),          "pdf_prior_subgroup.dat")
write_dat(round(x_grid, 2), round(cdf_prior, 6),       "cdf_Fxref.dat")

# --- Left margin (current scores, swapped axes) ---

max_pdf_left <- max(c(d_y$y, pdf_current_pop))
write_dat(round(pdf_current_pop / max_pdf_left, 6), round(y_norm, 6), "pdf_left_pop_norm.dat")
write_dat(round(d_y$y / max_pdf_left, 6),           round(y_norm, 6), "pdf_left_sub_norm.dat")
write_dat(round(cdf_current, 6),                     round(y_norm, 6), "cdf_left.dat")

# Raw-coord versions
write_dat(round(pdf_current_pop, 8), round(y_grid, 2), "pdf_current_pop.dat")
write_dat(round(d_y$y, 8),           round(d_y$x, 2),  "pdf_current_subgroup.dat")
write_dat(round(cdf_current, 6),     round(y_grid, 2), "cdf_Fyref.dat")


###############################################################################
## 9. Scatter dots (TeX snippets)
###############################################################################

cat("\nScatter dots...\n")

scatter_tex <- sprintf(
  "  \\psdot[dotsize=2.0pt,linecolor=stayerColor,fillcolor=stayerColor,dotstyle=*](%s,%s)%%",
  round(u_scatter, 4), round(v_scatter, 4))
write_tex_lines(scatter_tex, "scatter_stayers.tex")


###############################################################################
## 10. Rug marks
###############################################################################

cat("Rug marks...\n")

# Subsample stayer rug marks if needed (leavers/entrants are kept in full)
if (length(u_sub_stayers) > max_rug_stayers) {
  set.seed(123)
  rug_idx <- sample.int(length(u_sub_stayers), max_rug_stayers)
  u_rug_stayers <- u_sub_stayers[rug_idx]
  v_rug_stayers <- v_sub_stayers[rug_idx]
  cat("  Subsampled", max_rug_stayers, "of", length(u_sub_stayers),
      "stayer rug marks\n")
} else {
  u_rug_stayers <- u_sub_stayers
  v_rug_stayers <- v_sub_stayers
}

# Bottom rug: stayers + leavers in u-space
rug_bot <- c(
  sprintf("  \\psline[linecolor=stayerColor,linewidth=0.3pt](%s,0)(%s,1)%%",
          round(u_rug_stayers, 4), round(u_rug_stayers, 4)),
  sprintf("  \\psline[linecolor=leaverColor,linewidth=0.5pt](%s,0)(%s,1)%%",
          round(u_sub_leavers, 4), round(u_sub_leavers, 4))
)
write_tex_lines(rug_bot, "rug_bottom.tex")

# Left rug: stayers + entrants in v-space
rug_left <- c(
  sprintf("  \\psline[linecolor=stayerColor,linewidth=0.3pt](0,%s)(1,%s)%%",
          round(v_rug_stayers, 4), round(v_rug_stayers, 4)),
  sprintf("  \\psline[linecolor=entrantColor,linewidth=0.5pt](0,%s)(1,%s)%%",
          round(v_sub_entrants, 4), round(v_sub_entrants, 4))
)
write_tex_lines(rug_left, "rug_left.tex")


###############################################################################
## 11. Trace arrow example point
###############################################################################

cat("Trace example...\n")

# Pick a stayer near the 35th percentile of the subgroup's u distribution
idx_example <- which.min(abs(u_sub_stayers - 0.35))
x_example <- sub_stayers$SCALE_SCORE_PRIOR[idx_example]
y_example <- sub_stayers$SCALE_SCORE_CURRENT[idx_example]
u_example <- u_sub_stayers[idx_example]
v_example <- v_sub_stayers[idx_example]
x_example_norm <- (x_example - score_min) / (score_max - score_min)
y_example_norm <- (y_example - score_min) / (score_max - score_min)


###############################################################################
## 12. Generate nice score tick labels
###############################################################################

# Compute reasonable tick positions within [score_min, score_max]
score_range <- score_max - score_min
tick_step <- if (score_range > 400) 100 else if (score_range > 200) 50 else 25
tick_values <- seq(
  ceiling(score_min / tick_step) * tick_step,
  floor(score_max / tick_step) * tick_step,
  by = tick_step
)
# Normalize tick positions to [0,1]
tick_norms <- (tick_values - score_min) / (score_max - score_min)
# Keep only ticks comfortably inside [0.05, 0.95]
keep <- tick_norms > 0.05 & tick_norms < 0.95
tick_values <- tick_values[keep]
tick_norms  <- tick_norms[keep]


###############################################################################
## 13. Parameter macros for TeX
###############################################################################

cat("Parameter macros...\n")

# Grade labels for axis titles
grade_prior_label <- pairs$GRADE_PRIOR[1]
grade_current_label <- pairs$GRADE_CURRENT[1]
year_prior_label <- pairs$YEAR_PRIOR[1]
year_current_label <- pairs$YEAR_CURRENT[1]

param_lines <- c(
  "%% Generated by step3_export_data.R — DO NOT EDIT",
  sprintf("\\def\\popMuX{%.1f}", pop_mu_x),
  sprintf("\\def\\popSdX{%.1f}", pop_sd_x),
  sprintf("\\def\\popMuY{%.1f}", pop_mu_y),
  sprintf("\\def\\popSdY{%.1f}", pop_sd_y),
  sprintf("\\def\\nStayers{%d}", n_stayers_actual),
  sprintf("\\def\\nLeavers{%d}", n_leavers_actual),
  sprintf("\\def\\nEntrants{%d}", n_entrants_actual),
  sprintf("\\def\\nScatter{%d}", n_scatter),
  sprintf("\\def\\matchRate{%s}",
          round(n_stayers_actual / max(n_stayers_actual + n_leavers_actual,
                                       n_stayers_actual + n_entrants_actual) * 100, 0)),
  sprintf("\\def\\scoreMin{%s}", score_min),
  sprintf("\\def\\scoreMax{%s}", score_max),
  "",
  "%% Cohort metadata",
  sprintf("\\def\\gradePrior{%s}", grade_prior_label),
  sprintf("\\def\\gradeCurrent{%s}", grade_current_label),
  sprintf("\\def\\yearPrior{%s}", year_prior_label),
  sprintf("\\def\\yearCurrent{%s}", year_current_label),
  sprintf("\\def\\contentArea{%s}", pairs$CONTENT_AREA[1]),
  "",
  "%% Trace arrow example point",
  sprintf("\\def\\exampleX{%s}", round(x_example, 1)),
  sprintf("\\def\\exampleY{%s}", round(y_example, 1)),
  sprintf("\\def\\exampleU{%s}", round(u_example, 4)),
  sprintf("\\def\\exampleV{%s}", round(v_example, 4)),
  sprintf("\\def\\exampleXnorm{%s}", round(x_example_norm, 6)),
  sprintf("\\def\\exampleYnorm{%s}", round(y_example_norm, 6)),
  "",
  "%% Score tick labels (pre-computed, normalized to [0,1])",
  sprintf("\\def\\nScoreTicks{%d}", length(tick_values)),
  paste0("\\def\\scoreTickValues{",
         paste(tick_values, collapse = ","), "}"),
  paste0("\\def\\scoreTickNorms{",
         paste(round(tick_norms, 6), collapse = ","), "}"),
  "",
  "%% Max density values (for reference)",
  sprintf("\\def\\maxPdfPrior{%s}", round(max(d_x$y) * 1.1, 6)),
  sprintf("\\def\\maxPdfCurrent{%s}", round(max(d_y$y) * 1.1, 6))
)
write_tex_lines(param_lines, "scatter_params.tex")

# Backward-compatibility files
axis_lines <- c(
  sprintf("\\def\\xScoreMin{%s}", score_min),
  sprintf("\\def\\xScoreMax{%s}", score_max),
  sprintf("\\def\\yScoreMin{%s}", score_min),
  sprintf("\\def\\yScoreMax{%s}", score_max),
  "\\def\\cdfYmax{1.05}"
)
write_tex_lines(axis_lines, "axis_limits.tex")

trace_lines <- c(
  sprintf("\\def\\exampleX{%s}", round(x_example, 1)),
  sprintf("\\def\\exampleY{%s}", round(y_example, 1)),
  sprintf("\\def\\exampleU{%s}", round(u_example, 4)),
  sprintf("\\def\\exampleV{%s}", round(v_example, 4)),
  sprintf("\\def\\nLinked{%d}", n_stayers_actual),
  sprintf("\\def\\nOrphanU{%d}", n_leavers_actual),
  sprintf("\\def\\nOrphanV{%d}", n_entrants_actual),
  sprintf("\\def\\nTotalU{%d}", n_stayers_actual + n_leavers_actual),
  sprintf("\\def\\nTotalV{%d}", n_stayers_actual + n_entrants_actual),
  sprintf("\\def\\linkageRate{%s}",
          round(n_stayers_actual / max(n_stayers_actual + n_leavers_actual,
                                       n_stayers_actual + n_entrants_actual) * 100, 0)),
  sprintf("\\def\\copulaRho{%s}", round(cor(sub_stayers$SCALE_SCORE_PRIOR,
                                             sub_stayers$SCALE_SCORE_CURRENT), 3)),
  sprintf("\\def\\muX{%s}", round(mean(sub_stayers$SCALE_SCORE_PRIOR), 1)),
  sprintf("\\def\\muY{%s}", round(mean(sub_stayers$SCALE_SCORE_CURRENT), 1)),
  sprintf("\\def\\sdX{%s}", round(sd(sub_stayers$SCALE_SCORE_PRIOR), 1)),
  sprintf("\\def\\sdY{%s}", round(sd(sub_stayers$SCALE_SCORE_CURRENT), 1))
)
write_tex_lines(trace_lines, "cdf_trace_points.tex")


cat("\n=== Scatter data export complete ===\n")
cat("  Score range:", score_min, "-", score_max, "\n")
cat("  Scatter dots:", n_scatter, "of", n_stayers_actual, "stayers\n")
cat("  Rug marks: bottom =", length(u_sub_stayers) + length(u_sub_leavers),
    " left =", length(v_sub_stayers) + length(v_sub_entrants), "\n")
