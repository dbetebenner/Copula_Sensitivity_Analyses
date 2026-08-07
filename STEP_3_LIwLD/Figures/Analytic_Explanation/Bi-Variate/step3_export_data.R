###############################################################################
###
### step3_export_data.R - Export panel-ready data for Bi-Variate scatter figures
###
### Reads the intermediate CSV produced by step3_extract_pairs.R (in Margins/)
### and generates PSTricks-ready data files for simplified bivariate scatter
### plots with marginal densities on the scaled-score axis.
###
### Key simplifications vs Margins/:
###   - Scatter is in SCALED SCORE space (not PIT-transformed [0,1])
###   - No subgroup distinction — population stayers only
###   - No CDF panels, rug strips, or PIT trace annotations
###   - Marginal densities f_X and f_Y computed for population
###
### Output files (consumed by PSTricks .tex panels):
###   - scatter_population_scaled.tex   (scatter dots in normalized score coords)
###   - pdf_bottom_pop_scaled.dat       (f_X density, normalized coords)
###   - pdf_left_pop_scaled.dat         (f_Y density, normalized coords)
###   - bivariate_params.tex            (macro definitions)
###
### Usage: source("step3_export_data.R")  (from the Bi-Variate/ directory)
###
###############################################################################

require(data.table)

script_file <- sub(
  "^--file=",
  "",
  commandArgs(trailingOnly = FALSE)[
    grep("^--file=", commandArgs(trailingOnly = FALSE))
  ][1]
)
bivariate_dir <- if (!is.na(script_file) && nzchar(script_file)) {
  normalizePath(dirname(script_file), winslash = "/", mustWork = TRUE)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

data_dir <- file.path(bivariate_dir, "data")
if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}

# Use the same intermediate CSV from the Margins directory
margins_data_dir <- file.path(bivariate_dir, "..", "Margins", "data")


###############################################################################
## Configuration
###############################################################################

pairs_csv <- file.path(margins_data_dir, "longitudinal_pairs.csv")

# Maximum scatter dots (population only — no subgroup)
max_scatter_dots <- 4000

# Grid resolution for PDF curves
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

cat("\n=== Bi-Variate Scatter Data Export (Scaled Scores) ===\n")

if (!file.exists(pairs_csv)) {
  stop(
    "Intermediate CSV not found:\n  ",
    pairs_csv,
    "\n  Run the Margins build first to generate this file."
  )
}

pairs <- fread(
  pairs_csv,
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
  )
)
cat(
  "  Loaded",
  format(nrow(pairs), big.mark = ","),
  "records from",
  basename(pairs_csv),
  "\n"
)


###############################################################################
## 2. Population stayers only (no subgroup)
###############################################################################

pop_stayers <- pairs[TYPE == "stayer"]

cat("\n  Population stayers:", format(nrow(pop_stayers), big.mark = ","), "\n")


###############################################################################
## 3. Score display range
###############################################################################

all_prior_scores <- pop_stayers$SCALE_SCORE_PRIOR
all_current_scores <- pop_stayers$SCALE_SCORE_CURRENT

# Include leavers/entrants for more accurate marginals
pop_leavers <- pairs[TYPE == "leaver"]
pop_entrants <- pairs[TYPE == "entrant"]
all_prior_scores <- c(all_prior_scores, pop_leavers$SCALE_SCORE_PRIOR)
all_current_scores <- c(all_current_scores, pop_entrants$SCALE_SCORE_CURRENT)

all_scores <- c(all_prior_scores, all_current_scores)
score_min <- floor(min(all_scores, na.rm = TRUE) / 50) * 50
score_max <- ceiling(max(all_scores, na.rm = TRUE) / 50) * 50

cat("  Score display range:", score_min, "-", score_max, "\n")


###############################################################################
## 4. Population reference distributions
###############################################################################

cat("\nFitting population distributions...\n")

pop_mu_x <- mean(all_prior_scores, na.rm = TRUE)
pop_sd_x <- sd(all_prior_scores, na.rm = TRUE)
pop_mu_y <- mean(all_current_scores, na.rm = TRUE)
pop_sd_y <- sd(all_current_scores, na.rm = TRUE)

cat("  Prior   N(", round(pop_mu_x, 1), ",", round(pop_sd_x, 1), ")\n")
cat("  Current N(", round(pop_mu_y, 1), ",", round(pop_sd_y, 1), ")\n")

# Pearson correlation for stayers
rho_xy <- cor(pop_stayers$SCALE_SCORE_PRIOR, pop_stayers$SCALE_SCORE_CURRENT)
cat("  Pearson r =", round(rho_xy, 3), "\n")


###############################################################################
## 5. Subsample scatter dots
###############################################################################

n_stayers <- nrow(pop_stayers)
if (n_stayers > max_scatter_dots) {
  set.seed(42)
  idx <- sample.int(n_stayers, max_scatter_dots)
  x_scatter <- pop_stayers$SCALE_SCORE_PRIOR[idx]
  y_scatter <- pop_stayers$SCALE_SCORE_CURRENT[idx]
  n_scatter <- max_scatter_dots
  cat(
    "  Subsampled",
    max_scatter_dots,
    "of",
    format(n_stayers, big.mark = ","),
    "stayers for scatter\n"
  )
} else {
  x_scatter <- pop_stayers$SCALE_SCORE_PRIOR
  y_scatter <- pop_stayers$SCALE_SCORE_CURRENT
  n_scatter <- n_stayers
}

# Normalize to [0,1] for PSTricks coordinate system
x_scatter_norm <- (x_scatter - score_min) / (score_max - score_min)
y_scatter_norm <- (y_scatter - score_min) / (score_max - score_min)


###############################################################################
## 6. PDF curves (population marginals)
###############################################################################

cat("\nGenerating marginal density curves...\n")

x_grid <- seq(score_min, score_max, length.out = n_grid)
y_grid <- seq(score_min, score_max, length.out = n_grid)
x_norm <- (x_grid - score_min) / (score_max - score_min)
y_norm <- (y_grid - score_min) / (score_max - score_min)

# KDE for population
d_x <- density(
  all_prior_scores,
  from = score_min,
  to = score_max,
  n = n_grid,
  bw = "SJ"
)
d_y <- density(
  all_current_scores,
  from = score_min,
  to = score_max,
  n = n_grid,
  bw = "SJ"
)


###############################################################################
## 7. Write data files
###############################################################################

cat("\nWriting PSTricks data files...\n")

# --- Bottom margin: f_X density, normalized to [0,1] y-range ---
max_pdf_x <- max(d_x$y)
write_dat(
  round(x_norm, 6),
  round(d_x$y / max_pdf_x, 6),
  "pdf_bottom_pop_scaled.dat"
)

# --- Prior density rotated: f_X in (density, score_position) orientation ---
# Used by three-panel layout left panel (f_X displayed vertically)
write_dat(
  round(d_x$y / max_pdf_x, 6),
  round(x_norm, 6),
  "pdf_prior_rotated.dat"
)

# --- f_Y density in rotated orientation (density, score) for Fig 1 left margin ---
max_pdf_y <- max(d_y$y)
write_dat(
  round(d_y$y / max_pdf_y, 6),
  round(y_norm, 6),
  "pdf_left_pop_scaled.dat"
)

# --- f_Y density upright (score, density) for three-panel right panel ---
write_dat(
  round(y_norm, 6),
  round(d_y$y / max_pdf_y, 6),
  "pdf_current_pop_scaled.dat"
)

# --- Scatter dots (normalized score coordinates) ---
scatter_tex <- sprintf(
  "  \\psdot[dotsize=1.5pt,fillcolor=scatterDotColor,linecolor=black,fillstyle=solid,opacity=0.35,dotstyle=o](%s,%s)%%",
  round(x_scatter_norm, 4),
  round(y_scatter_norm, 4)
)
write_tex_lines(scatter_tex, "scatter_population_scaled.tex")
cat("  Scatter:", n_scatter, "dots\n")

# --- Faded variant (for "without h(X,Y)" figure) ---
scatter_faded_tex <- sprintf(
  "  \\psdot[dotsize=1.5pt,fillcolor=scatterDotColor,linecolor=black,fillstyle=solid,opacity=0.05,dotstyle=o](%s,%s)%%",
  round(x_scatter_norm, 4),
  round(y_scatter_norm, 4)
)
write_tex_lines(scatter_faded_tex, "scatter_population_scaled_faded.tex")
cat("  Scatter (faded):", n_scatter, "dots\n")


###############################################################################
## 8. Score tick computation
###############################################################################

score_range <- score_max - score_min
tick_step <- if (score_range > 400) {
  100
} else if (score_range > 200) {
  50
} else {
  25
}
tick_values <- seq(
  ceiling(score_min / tick_step) * tick_step,
  floor(score_max / tick_step) * tick_step,
  by = tick_step
)
tick_norms <- (tick_values - score_min) / (score_max - score_min)
keep <- tick_norms > 0.05 & tick_norms < 0.95
tick_values <- tick_values[keep]
tick_norms <- tick_norms[keep]


###############################################################################
## 9. Parameter macros
###############################################################################

cat("Parameter macros...\n")

param_lines <- c(
  "%% Generated by step3_export_data.R (Bi-Variate) — DO NOT EDIT",
  sprintf("\\def\\popMuX{%.1f}", pop_mu_x),
  sprintf("\\def\\popSdX{%.1f}", pop_sd_x),
  sprintf("\\def\\popMuY{%.1f}", pop_mu_y),
  sprintf("\\def\\popSdY{%.1f}", pop_sd_y),
  sprintf("\\def\\rhoXY{%.3f}", rho_xy),
  sprintf("\\def\\nStayers{%s}", format(n_stayers, big.mark = ",")),
  sprintf("\\def\\nScatter{%d}", n_scatter),
  sprintf("\\def\\scoreMin{%s}", score_min),
  sprintf("\\def\\scoreMax{%s}", score_max),
  "",
  "%% Cohort metadata",
  sprintf("\\def\\gradePrior{%s}", pairs$GRADE_PRIOR[1]),
  sprintf("\\def\\gradeCurrent{%s}", pairs$GRADE_CURRENT[1]),
  sprintf("\\def\\yearPrior{%s}", pairs$YEAR_PRIOR[1]),
  sprintf("\\def\\yearCurrent{%s}", pairs$YEAR_CURRENT[1]),
  sprintf("\\def\\contentArea{%s}", pairs$CONTENT_AREA[1]),
  "",
  "%% Score tick labels (pre-computed, normalized to [0,1])",
  sprintf("\\def\\nScoreTicks{%d}", length(tick_values)),
  paste0("\\def\\scoreTickValues{", paste(tick_values, collapse = ","), "}"),
  paste0(
    "\\def\\scoreTickNorms{",
    paste(round(tick_norms, 6), collapse = ","),
    "}"
  ),
  "",
  "%% Max density values",
  sprintf("\\def\\maxPdfX{%.6f}", max_pdf_x),
  sprintf("\\def\\maxPdfY{%.6f}", max_pdf_y)
)
write_tex_lines(param_lines, "bivariate_params.tex")

cat("\n=== Bi-Variate data export complete ===\n")
cat("  Score range:", score_min, "-", score_max, "\n")
cat("  Scatter dots:", n_scatter, "\n")
cat("  Pearson r:", round(rho_xy, 3), "\n")
