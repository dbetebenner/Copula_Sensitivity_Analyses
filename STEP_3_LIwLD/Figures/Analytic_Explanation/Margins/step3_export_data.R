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
max_pop_scatter_dots <- 5000   # Population background cloud (grey)
max_sub_scatter_dots <- 1000   # Subgroup foreground dots (purple)

# Maximum rug marks per axis (too many overflows TeX memory)
max_rug_stayers <- 600

# Score-axis display range.  Set to NULL for auto from data.
score_display_min <- NULL   # e.g., 200
score_display_max <- NULL   # e.g., 800

# Grid resolution for PDF/CDF curves
n_grid <- 512

# STEP 1 copula-fit results — dataset ID must match results subdirectory name
step1_dataset_id <- "dataset_1"


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
## 2b. Join STEP 1 copula-fit results for this condition
###############################################################################

step1_csv <- file.path(
  normalizePath(file.path(margins_dir, "../../../../STEP_1_Family_Selection/results"),
                mustWork = FALSE),
  step1_dataset_id, "phase1_copula_family_comparison.csv")

if (file.exists(step1_csv)) {
  cat("\nLoading STEP 1 copula-fit results...\n")
  s1 <- fread(step1_csv)

  gp  <- as.integer(pairs$GRADE_PRIOR[1])
  gc  <- as.integer(pairs$GRADE_CURRENT[1])
  yp  <- pairs$YEAR_PRIOR[1]
  yc  <- pairs$YEAR_CURRENT[1]
  ca  <- pairs$CONTENT_AREA[1]

  s1_cond <- s1[grade_prior == gp & grade_current == gc &
                year_prior == yp & year_current == yc &
                content_area == ca]

  if (nrow(s1_cond) > 0) {
    s1_best <- s1_cond[delta_aic_vs_best == 0]
    if (nrow(s1_best) > 1) s1_best <- s1_best[1]  # tie-break

    s1_second <- s1_cond[delta_aic_vs_best > 0][order(delta_aic_vs_best)][1]

    copula_family   <- s1_best$family
    copula_tau      <- s1_best$tau
    copula_rho_sp   <- round(sin(pi / 2 * copula_tau), 3)
    copula_rho_par  <- s1_best$correlation_rho
    copula_df       <- s1_best$degrees_freedom
    copula_tail_lo  <- s1_best$tail_dep_lower
    copula_tail_hi  <- s1_best$tail_dep_upper
    copula_delta_aic <- s1_second$delta_aic_vs_best
    copula_second   <- s1_second$family

    cat("  Condition  :", paste(gp, "->", gc, yp, ca), "\n")
    cat("  Best family:", copula_family, "\n")
    cat("  tau =", round(copula_tau, 3),
        " rho_s =", copula_rho_sp,
        " rho_par =", round(copula_rho_par, 3), "\n")
    cat("  df =", round(copula_df, 1),
        " lambda =", round(copula_tail_lo, 3), "\n")
    cat("  2nd family :", copula_second,
        " delta_AIC =", round(copula_delta_aic, 1), "\n")

    step1_available <- TRUE
  } else {
    cat("\n  WARNING: No STEP 1 match for condition",
        paste(gp, "->", gc, yp, ca), "— copula macros will use placeholders.\n")
    step1_available <- FALSE
  }
  rm(s1)
} else {
  cat("\n  WARNING: STEP 1 results CSV not found at:\n    ", step1_csv,
      "\n    Copula macros will use placeholders.\n")
  step1_available <- FALSE
}


###############################################################################
## 2c. Export copula CDF contour data for _2 scatter panel
###############################################################################

contours_available <- FALSE

if (step1_available) {
  cond_dir_name <- sprintf("%s_G%s_G%s_%s", yc, gp, gc, ca)
  contour_rds_dir <- file.path(
    normalizePath(file.path(margins_dir, "../../../../STEP_1_Family_Selection/results"),
                  mustWork = FALSE),
    step1_dataset_id, "contour_plots", cond_dir_name)

  copula_rds   <- file.path(contour_rds_dir, "copula_results.rds")
  emp_cop_rds  <- file.path(contour_rds_dir, "empirical_copulas.rds")

  if (file.exists(copula_rds) && file.exists(emp_cop_rds)) {
    cat("\nExporting copula CDF contour data...\n")
    require(copula)

    cr  <- readRDS(copula_rds)
    ec  <- readRDS(emp_cop_rds)
    t_cop   <- cr[[copula_family]]$copula
    emp_cop <- ec$bernstein

    n_grid <- 101L
    gseq   <- seq(0, 1, length.out = n_grid)
    uv     <- as.matrix(expand.grid(u = gseq, v = gseq))

    cat("  Evaluating t-copula CDF on", n_grid, "x", n_grid, "grid...\n")
    t_cdf_mat <- matrix(pCopula(uv, t_cop), nrow = n_grid)

    cat("  Evaluating Bernstein empirical CDF (this may take ~60s)...\n")
    emp_cdf_mat <- matrix(pCopula(uv, emp_cop), nrow = n_grid)

    contour_levels <- seq(0.1, 0.9, by = 0.1)

    write_contour_dat <- function(grid, zmat, prefix, levels) {
      for (lv in levels) {
        cl <- contourLines(grid, grid, zmat, levels = lv)
        tag <- sprintf("%03d", round(lv * 100))
        fname <- sprintf("%s_%s.dat", prefix, tag)
        if (length(cl) > 0) {
          pts <- do.call(rbind, lapply(cl, function(seg) {
            rbind(cbind(seg$x, seg$y), c(NA, NA))
          }))
          pts <- pts[!is.na(pts[,1]), , drop = FALSE]
          writeLines(paste(round(pts[,1], 6), round(pts[,2], 6)),
                     file.path(data_dir, fname))
        } else {
          writeLines("", file.path(data_dir, fname))
        }
        cat("  ", fname, "\n")
      }
    }

    cat("Writing t-copula contour .dat files...\n")
    write_contour_dat(gseq, t_cdf_mat, "contour_t_cdf", contour_levels)

    cat("Writing empirical contour .dat files...\n")
    write_contour_dat(gseq, emp_cdf_mat, "contour_emp_cdf", contour_levels)

    contours_available <- TRUE
    rm(cr, ec, t_cop, emp_cop, uv, t_cdf_mat, emp_cdf_mat)
    gc(verbose = FALSE)
  } else {
    cat("\n  WARNING: Copula RDS files not found in:\n    ", contour_rds_dir,
        "\n    Contour export skipped.\n")
  }
}


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

# Population stayers (for background scatter cloud)
u_pop_stayers <- pit(pop_stayers$SCALE_SCORE_PRIOR, pop_mu_x, pop_sd_x)
v_pop_stayers <- pit(pop_stayers$SCALE_SCORE_CURRENT, pop_mu_y, pop_sd_y)

# Subgroup stayers
u_sub_stayers <- pit(sub_stayers$SCALE_SCORE_PRIOR, pop_mu_x, pop_sd_x)
v_sub_stayers <- pit(sub_stayers$SCALE_SCORE_CURRENT, pop_mu_y, pop_sd_y)

# Leavers (prior only)
u_sub_leavers <- pit(sub_leavers$SCALE_SCORE_PRIOR, pop_mu_x, pop_sd_x)

# Entrants (current only)
v_sub_entrants <- pit(sub_entrants$SCALE_SCORE_CURRENT, pop_mu_y, pop_sd_y)

# Clamp to (0.005, 0.995) so dots don't sit right on the frame
clamp01 <- function(x) pmax(0.005, pmin(0.995, x))
u_pop_stayers  <- clamp01(u_pop_stayers)
v_pop_stayers  <- clamp01(v_pop_stayers)
u_sub_stayers  <- clamp01(u_sub_stayers)
v_sub_stayers  <- clamp01(v_sub_stayers)
u_sub_leavers  <- clamp01(u_sub_leavers)
v_sub_entrants <- clamp01(v_sub_entrants)


###############################################################################
## 6. Subsample scatter dots for visual clarity
###############################################################################

n_pop_stayers_actual <- nrow(pop_stayers)
n_stayers_actual     <- nrow(sub_stayers)
n_leavers_actual     <- nrow(sub_leavers)
n_entrants_actual    <- nrow(sub_entrants)

# Population background cloud
if (n_pop_stayers_actual > max_pop_scatter_dots) {
  set.seed(41)
  idx_pop <- sample.int(n_pop_stayers_actual, max_pop_scatter_dots)
  u_pop_scatter <- u_pop_stayers[idx_pop]
  v_pop_scatter <- v_pop_stayers[idx_pop]
  n_pop_scatter <- max_pop_scatter_dots
  cat("  Subsampled", max_pop_scatter_dots, "of",
      format(n_pop_stayers_actual, big.mark = ","), "population stayers for scatter\n")
} else {
  u_pop_scatter <- u_pop_stayers
  v_pop_scatter <- v_pop_stayers
  n_pop_scatter <- n_pop_stayers_actual
}

# Subgroup foreground dots
if (n_stayers_actual > max_sub_scatter_dots) {
  set.seed(42)
  idx_sub <- sample.int(n_stayers_actual, max_sub_scatter_dots)
  u_sub_scatter <- u_sub_stayers[idx_sub]
  v_sub_scatter <- v_sub_stayers[idx_sub]
  n_sub_scatter <- max_sub_scatter_dots
  cat("  Subsampled", max_sub_scatter_dots, "of", n_stayers_actual, "subgroup stayers for scatter\n")
} else {
  u_sub_scatter <- u_sub_stayers
  v_sub_scatter <- v_sub_stayers
  n_sub_scatter <- n_stayers_actual
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
## 9. Scatter dots (TeX snippets) — two layers
###############################################################################

cat("\nScatter dots...\n")

# Population background cloud (grey, smaller dots)
pop_scatter_tex <- sprintf(
  "  \\psdot[dotsize=1.5pt,linecolor=populationRef,fillcolor=populationRef,dotstyle=*](%s,%s)%%",
  round(u_pop_scatter, 4), round(v_pop_scatter, 4))
write_tex_lines(pop_scatter_tex, "scatter_population.tex")
cat("  Population:", n_pop_scatter, "dots\n")

# Subgroup foreground dots (purple, larger dots)
sub_scatter_tex <- sprintf(
  "  \\psdot[dotsize=2.0pt,linecolor=subgroupColor,fillcolor=subgroupColor,dotstyle=*](%s,%s)%%",
  round(u_sub_scatter, 4), round(v_sub_scatter, 4))
write_tex_lines(sub_scatter_tex, "scatter_subgroup.tex")
cat("  Subgroup:", n_sub_scatter, "dots\n")

# Variant _2: smaller, lighter dots so contour lines are prominent
pop_scatter_tex_2 <- sprintf(
  "  \\psdot[dotsize=0.8pt,linecolor=populationRef,fillcolor=populationRef,dotstyle=*](%s,%s)%%",
  round(u_pop_scatter, 4), round(v_pop_scatter, 4))
write_tex_lines(pop_scatter_tex_2, "scatter_population_2.tex")

sub_scatter_tex_2 <- sprintf(
  "  \\psdot[dotsize=1.0pt,linecolor=subgroupColor,fillcolor=subgroupColor,dotstyle=*](%s,%s)%%",
  round(u_sub_scatter, 4), round(v_sub_scatter, 4))
write_tex_lines(sub_scatter_tex_2, "scatter_subgroup_2.tex")
cat("  _2 variants (smaller dots) written\n")


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
## 10b. Rug density curves (replaces rug tick marks in the panel)
###############################################################################

cat("Rug density curves...\n")

u_grid_01 <- seq(0, 1, length.out = n_grid)

# --- Bottom strip (u-axis) ---
# Subgroup density: stayers + leavers, normalized to U(0,1) = 1.0
u_sub_all  <- c(u_sub_stayers, u_sub_leavers)
d_u_sub    <- density(u_sub_all, from = 0, to = 1, n = n_grid)
write_dat(round(u_grid_01, 6), round(d_u_sub$y, 6), "rug_bottom_sub_kde.dat")

# Smoothed P(leaver | u) via loess
u_combined  <- c(u_sub_stayers, u_sub_leavers)
leaver_ind  <- c(rep(0L, length(u_sub_stayers)), rep(1L, length(u_sub_leavers)))
fit_u       <- loess(leaver_ind ~ u_combined, span = 0.3, surface = "direct")
prop_leaver <- pmax(0, pmin(1, predict(fit_u, newdata = u_grid_01)))
write_dat(round(u_grid_01, 6), round(prop_leaver, 6), "rug_bottom_leaver_prop.dat")

# --- Left strip (v-axis) ---
# Subgroup density: stayers + entrants, normalized to U(0,1) = 1.0
# Rotated orientation: columns are (density_value, v_coord)
v_sub_all  <- c(v_sub_stayers, v_sub_entrants)
d_v_sub    <- density(v_sub_all, from = 0, to = 1, n = n_grid)
write_dat(round(d_v_sub$y, 6), round(u_grid_01, 6), "rug_left_sub_kde.dat")

# Smoothed P(entrant | v) via loess
v_combined   <- c(v_sub_stayers, v_sub_entrants)
entrant_ind  <- c(rep(0L, length(v_sub_stayers)), rep(1L, length(v_sub_entrants)))
fit_v        <- loess(entrant_ind ~ v_combined, span = 0.3, surface = "direct")
prop_entrant <- pmax(0, pmin(1, predict(fit_v, newdata = u_grid_01)))
write_dat(round(prop_entrant, 6), round(u_grid_01, 6), "rug_left_entrant_prop.dat")

# rug_density_params.tex no longer carries macros
writeLines(character(0), file.path(data_dir, "rug_density_params.tex"))
cat("  rug_density_params.tex \n")

cat("  Bottom strip: subgroup n =", length(u_sub_all),
    " leavers n =", length(u_sub_leavers), "\n")
cat("  Left strip:   subgroup n =", length(v_sub_all),
    " entrants n =", length(v_sub_entrants), "\n")
cat("  Leaver proportion range: [",
    round(min(prop_leaver, na.rm=TRUE), 3), ",",
    round(max(prop_leaver, na.rm=TRUE), 3), "]\n")
cat("  Entrant proportion range: [",
    round(min(prop_entrant, na.rm=TRUE), 3), ",",
    round(max(prop_entrant, na.rm=TRUE), 3), "]\n")


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
  sprintf("\\def\\nPopStayers{%s}",  format(nrow(pop_stayers),  big.mark = ",")),
  sprintf("\\def\\nPopLeavers{%s}",  format(nrow(pop_leavers),  big.mark = ",")),
  sprintf("\\def\\nPopEntrants{%s}", format(nrow(pop_entrants), big.mark = ",")),
  sprintf("\\def\\popAlpha{%.2f}",
          nrow(pop_stayers) / (nrow(pop_stayers) + nrow(pop_leavers))),
  sprintf("\\def\\popBeta{%.2f}",
          nrow(pop_stayers) / (nrow(pop_stayers) + nrow(pop_entrants))),
  sprintf("\\def\\nStayers{%s}",  format(n_stayers_actual,  big.mark = ",")),
  sprintf("\\def\\nLeavers{%s}",  format(n_leavers_actual,  big.mark = ",")),
  sprintf("\\def\\nEntrants{%s}", format(n_entrants_actual, big.mark = ",")),
  sprintf("\\def\\subAlpha{%.2f}",
          n_stayers_actual / (n_stayers_actual + n_leavers_actual)),
  sprintf("\\def\\subBeta{%.2f}",
          n_stayers_actual / (n_stayers_actual + n_entrants_actual)),
  sprintf("\\def\\nPopScatter{%d}", n_pop_scatter),
  sprintf("\\def\\nSubScatter{%d}", n_sub_scatter),
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
  sprintf("\\def\\exampleURound{%s}", formatC(round(u_example, 2), format = "f", digits = 2)),
  sprintf("\\def\\exampleVRound{%s}", formatC(round(v_example, 2), format = "f", digits = 2)),
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
  sprintf("\\def\\maxPdfCurrent{%s}", round(max(d_y$y) * 1.1, 6)),
  "",
  "%% STEP 1 copula-fit results",
  if (step1_available) c(
    sprintf("\\def\\copulaFamily{%s}",       copula_family),
    sprintf("\\def\\copulaTau{%.3f}",         copula_tau),
    sprintf("\\def\\copulaRhoSp{%.3f}",       copula_rho_sp),
    sprintf("\\def\\copulaRhoPar{%.3f}",      copula_rho_par),
    sprintf("\\def\\copulaDf{%.1f}",           copula_df),
    sprintf("\\def\\copulaTailLo{%.3f}",       copula_tail_lo),
    sprintf("\\def\\copulaTailHi{%.3f}",       copula_tail_hi),
    sprintf("\\def\\copulaDeltaAIC{%.1f}",     copula_delta_aic),
    sprintf("\\def\\copulaSecondFamily{%s}",
            paste0(toupper(substring(copula_second, 1, 1)),
                   substring(copula_second, 2)))
  ) else c(
    "\\def\\copulaFamily{--}",
    "\\def\\copulaTau{--}",
    "\\def\\copulaRhoSp{--}",
    "\\def\\copulaRhoPar{--}",
    "\\def\\copulaDf{--}",
    "\\def\\copulaTailLo{--}",
    "\\def\\copulaTailHi{--}",
    "\\def\\copulaDeltaAIC{--}",
    "\\def\\copulaSecondFamily{--}"
  )
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
  sprintf("\\def\\nLinked{%s}",  format(n_stayers_actual,                          big.mark = ",")),
  sprintf("\\def\\nOrphanU{%s}", format(n_leavers_actual,                          big.mark = ",")),
  sprintf("\\def\\nOrphanV{%s}", format(n_entrants_actual,                         big.mark = ",")),
  sprintf("\\def\\nTotalU{%s}",  format(n_stayers_actual + n_leavers_actual,       big.mark = ",")),
  sprintf("\\def\\nTotalV{%s}",  format(n_stayers_actual + n_entrants_actual,      big.mark = ",")),
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
cat("  Scatter dots: pop =", n_pop_scatter, ", sub =", n_sub_scatter, "\n")
cat("  Rug marks: bottom =", length(u_sub_stayers) + length(u_sub_leavers),
    " left =", length(v_sub_stayers) + length(v_sub_entrants), "\n")
