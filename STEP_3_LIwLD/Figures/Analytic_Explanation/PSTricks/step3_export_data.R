###############################################################################
###
### step3_export_data.R - Export panel-ready data files for PSTricks
###
### Reads the saved RDS from the analytic explanation and writes:
###   - .dat files (space-separated x y) for curve plotting
###   - .tex snippets (LaTeX macros, heatmap cells)
###
### Usage: Rscript step3_export_data.R  (from the PSTricks/ directory)
###
###############################################################################

pstricks_dir <- tryCatch({
  normalizePath(dirname(sys.frame(1)$ofile), winslash = "/", mustWork = TRUE)
}, error = function(e) {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
})

analytic_dir <- normalizePath(file.path(pstricks_dir, ".."), winslash = "/")
data_dir     <- file.path(pstricks_dir, "data")

if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)

rds_path <- file.path(analytic_dir, "outputs",
                      "step3_growth_regime_analytic_infographic_data.rds")

if (!file.exists(rds_path)) {
  stop("RDS not found at: ", rds_path,
       "\nRun step3_analytic_explanation.R first.")
}

dat <- readRDS(rds_path)
cat("Loaded:", rds_path, "\n\n")


# --- helper -----------------------------------------------------------------
write_dat <- function(x, y, filename) {
  out <- file.path(data_dir, filename)
  writeLines(paste(x, y), out)
  cat("  ", filename, "\n")
}


# --- Panel A: density curves for U and V ------------------------------------
cat("Panel A...\n")
d_u <- density(dat$u_sample, from = 0, to = 1, n = 256, bw = "SJ")
d_v <- density(dat$v_sample, from = 0, to = 1, n = 256, bw = "SJ")
write_dat(round(d_u$x, 6), round(d_u$y, 6), "panel_A_density_U.dat")
write_dat(round(d_v$x, 6), round(d_v$y, 6), "panel_A_density_V.dat")


# --- Panel B: CDF curves ----------------------------------------------------
cat("Panel B...\n")
write_dat(round(dat$v_grid, 6), round(dat$F_obs, 6),      "panel_B_cdf_obs.dat")
write_dat(round(dat$v_grid, 6), round(dat$F_uniform, 6),  "panel_B_cdf_uniform.dat")
write_dat(round(dat$v_grid, 6), round(dat$est$F_pred, 6), "panel_B_cdf_inferred.dat")


# --- Panel C: heatmap cells (generated TeX) ----------------------------------
cat("Panel C...\n")
gs     <- dat$est$grid_search
z_raw  <- with(gs, tapply(distance, list(theta2, theta1), mean))
mean_vals  <- as.numeric(colnames(z_raw))
kappa_vals <- as.numeric(rownames(z_raw))
ord_m <- order(mean_vals);  ord_k <- order(kappa_vals)
mean_vals  <- mean_vals[ord_m]
kappa_vals <- kappa_vals[ord_k]
z_raw <- z_raw[ord_k, ord_m, drop = FALSE]
z_log <- log10(z_raw)

z_min <- min(z_log, na.rm = TRUE)
z_max <- max(z_log, na.rm = TRUE)

pal <- colorRampPalette(rev(c(
  "#FFFFCC", "#FFEDA0", "#FED976", "#FEB24C",
  "#FD8D3C", "#FC4E2A", "#E31A1C", "#BD0026", "#800026"
)))(256)

nr <- length(kappa_vals);  nc <- length(mean_vals)
dx <- if (nc > 1) diff(mean_vals[1:2]) else 0.01
dy <- if (nr > 1) diff(log10(kappa_vals[1:2])) else 0.01

heatmap_lines <- character()
for (i in seq_len(nr)) {
  for (j in seq_len(nc)) {
    val <- z_log[i, j]
    if (is.na(val)) next
    idx <- max(1, min(256, round(1 + 255 * (val - z_min) / (z_max - z_min))))
    hex <- pal[idx]
    r <- round(strtoi(substr(hex, 2, 3), 16L) / 255, 3)
    g <- round(strtoi(substr(hex, 4, 5), 16L) / 255, 3)
    b <- round(strtoi(substr(hex, 6, 7), 16L) / 255, 3)
    x0 <- mean_vals[j] * 100 - dx * 50
    x1 <- mean_vals[j] * 100 + dx * 50
    y0 <- log10(kappa_vals[i]) - dy / 2
    y1 <- log10(kappa_vals[i]) + dy / 2
    tag <- paste0("hc", i, "x", j)
    heatmap_lines <- c(heatmap_lines,
      sprintf("\\definecolor{%s}{rgb}{%s,%s,%s}%%", tag, r, g, b),
      sprintf("\\psframe*[linecolor=%s](%.4f,%.4f)(%.4f,%.4f)%%",
              tag, x0, y0, x1, y1))
  }
}
writeLines(heatmap_lines, file.path(data_dir, "panel_C_heatmap_cells.tex"))
cat("   panel_C_heatmap_cells.tex\n")

## Optimum point
opt_x <- dat$est$theta_hat[1] * 100
opt_y <- log10(dat$est$theta_hat[2])
writeLines(c(
  sprintf("\\newcommand{\\optX}{%s}", round(opt_x, 2)),
  sprintf("\\newcommand{\\optY}{%s}", round(opt_y, 4))
), file.path(data_dir, "panel_C_optimum.tex"))
cat("   panel_C_optimum.tex\n")


# --- Panel D: regime density curves ------------------------------------------
cat("Panel D...\n")
p_grid <- seq(0.001, 0.999, length.out = 500)
d_true <- dat$true_regime$density(p_grid)
d_inf  <- dat$est$regime$density(p_grid)
write_dat(round(p_grid * 100, 4), round(rep(1, length(p_grid)), 4),
          "panel_D_density_uniform.dat")
write_dat(round(p_grid * 100, 4), round(d_true, 6), "panel_D_density_true.dat")
write_dat(round(p_grid * 100, 4), round(d_inf, 6),  "panel_D_density_inferred.dat")


# --- Summary metrics (LaTeX macros) ------------------------------------------
cat("Summary metrics...\n")
w1_reduction <- 100 * (1 - dat$distances$inferred$wasserstein1 /
                            dat$distances$uniform$wasserstein1)

metrics <- c(
  sprintf("\\newcommand{\\trueRegimeMean}{%s}",      round(dat$true_regime$mean * 100, 1)),
  sprintf("\\newcommand{\\trueRegimeMedian}{%s}",    round(dat$true_regime$median * 100, 1)),
  sprintf("\\newcommand{\\inferredRegimeMean}{%s}",   round(dat$est$regime$mean * 100, 1)),
  sprintf("\\newcommand{\\inferredRegimeMedian}{%s}", round(dat$est$regime$median * 100, 1)),
  sprintf("\\newcommand{\\wOneUniform}{%s}",          round(dat$distances$uniform$wasserstein1, 4)),
  sprintf("\\newcommand{\\wOneInferred}{%s}",         round(dat$distances$inferred$wasserstein1, 4)),
  sprintf("\\newcommand{\\wOneReduction}{%s}",        round(w1_reduction, 1)),
  sprintf("\\newcommand{\\copulaRho}{%s}",            round(dat$config$copula_rho, 2)),
  sprintf("\\newcommand{\\copulaDf}{%s}",             dat$config$copula_df),
  sprintf("\\newcommand{\\nStudents}{%s}",            dat$config$n_students),
  sprintf("\\newcommand{\\inferredKappa}{%s}",        round(dat$est$theta_hat[2], 1)),
  sprintf("\\newcommand{\\trueRegimeKappa}{%s}",      dat$config$true_regime_kappa)
)
writeLines(metrics, file.path(data_dir, "summary_metrics.tex"))
cat("   summary_metrics.tex\n")


# --- Axis limits (LaTeX macros) ----------------------------------------------
cat("Axis limits...\n")
y_max_a <- max(c(d_u$y, d_v$y)) * 1.15
y_max_d <- max(c(1, d_true, d_inf)) * 1.12
x_min_c <- min(mean_vals) * 100 - dx * 50
x_max_c <- max(mean_vals) * 100 + dx * 50
y_min_c <- min(log10(kappa_vals)) - dy / 2
y_max_c <- max(log10(kappa_vals)) + dy / 2

axes <- c(
  sprintf("\\newcommand{\\panelAymax}{%s}", ceiling(y_max_a * 10) / 10),
  sprintf("\\newcommand{\\panelDymax}{%s}", ceiling(y_max_d * 10) / 10),
  sprintf("\\newcommand{\\panelCxmin}{%s}", floor(x_min_c)),
  sprintf("\\newcommand{\\panelCxmax}{%s}", ceiling(x_max_c)),
  sprintf("\\newcommand{\\panelCymin}{%s}", round(y_min_c, 2)),
  sprintf("\\newcommand{\\panelCymax}{%s}", round(y_max_c, 2)),
  sprintf("\\newcommand{\\inferredMeanVline}{%s}", round(dat$est$regime$mean * 100, 1)),
  sprintf("\\newcommand{\\trueMeanVline}{%s}", round(dat$true_regime$mean * 100, 1))
)
writeLines(axes, file.path(data_dir, "axis_limits.tex"))
cat("   axis_limits.tex\n")

cat("\nExport complete. Files in:", data_dir, "\n")
