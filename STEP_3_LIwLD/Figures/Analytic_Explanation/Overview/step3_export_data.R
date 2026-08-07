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

script_file <- sub(
  "^--file=",
  "",
  commandArgs(trailingOnly = FALSE)[grep(
    "^--file=",
    commandArgs(trailingOnly = FALSE)
  )][1]
)
pstricks_dir <- if (!is.na(script_file) && nzchar(script_file)) {
  normalizePath(dirname(script_file), winslash = "/", mustWork = TRUE)
} else {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

analytic_dir <- normalizePath(file.path(pstricks_dir, ".."), winslash = "/")
step3_root <- normalizePath(
  file.path(pstricks_dir, "..", "..", ".."),
  winslash = "/"
)
data_dir <- file.path(pstricks_dir, "data")

if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}

export_mode <- Sys.getenv("STEP3_EXPORT_MODE", unset = "SYNTHETIC")
export_mode <- toupper(export_mode)

rds_path <- if (export_mode == "PHASE_A_REAL_DATA") {
  file.path(step3_root, "results", "phase_a_analytic_payload.rds")
} else {
  file.path(
    analytic_dir,
    "outputs",
    "step3_growth_regime_analytic_infographic_data.rds"
  )
}

if (!file.exists(rds_path)) {
  cat("RDS not found at: ", rds_path, "\n", sep = "")
  quit(save = "no", status = 1, runLast = FALSE)
}

dat <- readRDS(rds_path)
cat("Loaded mode:", export_mode, "\n")
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

# Best-fit induced density: numerically differentiate F_pred over v_grid,
# then smooth with a Gaussian kernel for a clean illustration.
# Done after Panel B2 CDF is resolved so F_pred / F_inferred is available.
# (Deferred below -- see "Panel A inferred density" block after Panel B2.)

# --- Panel B2: CDF curves ---------------------------------------------------
cat("Panel B2...\n")
if (export_mode == "PHASE_A_REAL_DATA") {
  write_dat(round(dat$v_grid, 6), round(dat$F_obs, 6), "panel_B2_cdf_obs.dat")
  write_dat(
    round(dat$v_grid, 6),
    round(dat$F_uniform, 6),
    "panel_B2_cdf_uniform.dat"
  )
  write_dat(
    round(dat$v_grid, 6),
    round(dat$F_pred, 6),
    "panel_B2_cdf_inferred.dat"
  )
} else {
  write_dat(round(dat$v_grid, 6), round(dat$F_obs, 6), "panel_B2_cdf_obs.dat")
  write_dat(
    round(dat$v_grid, 6),
    round(dat$F_uniform, 6),
    "panel_B2_cdf_uniform.dat"
  )
  write_dat(
    round(dat$v_grid, 6),
    round(dat$est$F_pred, 6),
    "panel_B2_cdf_inferred.dat"
  )
}
# Co-monotonic (TAMP) induced marginal under equi-percentile mapping:
# F_tamp(v) = P(U <= v) = F_U(v)
F_tamp <- if (!is.null(dat$F_tamp)) {
  dat$F_tamp
} else {
  stats::ecdf(dat$u_sample)(dat$v_grid)
}
write_dat(round(dat$v_grid, 6), round(F_tamp, 6), "panel_B2_cdf_tamp.dat")


# --- Panel A: best-fit induced density (deferred until F_pred is resolved) ---
cat("Panel A (inferred density)...\n")
# Retrieve the same F_pred that was just written for Panel B2
F_pred_for_density <- if (export_mode == "PHASE_A_REAL_DATA") {
  dat$F_pred
} else {
  dat$est$F_pred
}
v_grid_for_density <- dat$v_grid

# Numerical derivative on midpoint grid
dv <- diff(v_grid_for_density)[1]
v_mid <- (v_grid_for_density[-1] +
  v_grid_for_density[-length(v_grid_for_density)]) /
  2
f_raw <- diff(F_pred_for_density) / dv

# Gaussian-kernel smooth (bandwidth 0.04 gives a clean illustrative curve)
sm <- stats::ksmooth(
  v_mid,
  f_raw,
  kernel = "normal",
  bandwidth = 0.04,
  n.points = 256,
  x.points = seq(0, 1, length.out = 256)
)

# Trim boundary artefacts and clamp to non-negative
keep <- sm$x >= 0.01 & sm$x <= 0.99
x_out <- round(sm$x[keep], 6)
y_out <- pmax(round(sm$y[keep], 6), 0)
write_dat(x_out, y_out, "panel_A_density_inferred.dat")


# --- Panel B1: heatmap cells (generated TeX) ---------------------------------
cat("Panel B1...\n")
if (export_mode == "PHASE_A_REAL_DATA") {
  gs <- dat$objective_surface
  gs <- as.data.frame(gs)
  z_raw <- with(gs, tapply(distance_w1, list(kappa, m), mean))
} else {
  gs <- dat$est$grid_search
  z_raw <- with(
    gs,
    tapply(distance, list(regime_param_2, regime_param_1), mean)
  )
}
mean_vals <- as.numeric(colnames(z_raw))
kappa_vals <- as.numeric(rownames(z_raw))
ord_m <- order(mean_vals)
ord_k <- order(kappa_vals)
mean_vals <- mean_vals[ord_m]
kappa_vals <- kappa_vals[ord_k]
z_raw <- z_raw[ord_k, ord_m, drop = FALSE]
z_log <- log10(z_raw)

z_min <- min(z_log, na.rm = TRUE)
z_max <- max(z_log, na.rm = TRUE)

pal <- colorRampPalette(c(
  "#FCFCF4", # close (low log10 distance)
  "#E2E4C8",
  "#B7BA87",
  "#8A9048" # far (high log10 distance)
))(256)

nr <- length(kappa_vals)
nc <- length(mean_vals)
dx <- if (nc > 1) diff(mean_vals[1:2]) else 0.01
dy <- if (nr > 1) diff(log10(kappa_vals[1:2])) else 0.01

heatmap_lines <- character()
for (i in seq_len(nr)) {
  for (j in seq_len(nc)) {
    val <- z_log[i, j]
    if (is.na(val)) {
      next
    }
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
    heatmap_lines <- c(
      heatmap_lines,
      sprintf("\\definecolor{%s}{rgb}{%s,%s,%s}%%", tag, r, g, b),
      sprintf(
        "\\psframe*[linecolor=%s](%.4f,%.4f)(%.4f,%.4f)%%",
        tag,
        x0,
        y0,
        x1,
        y1
      )
    )
  }
}
writeLines(heatmap_lines, file.path(data_dir, "panel_B1_heatmap_cells.tex"))
cat("   panel_B1_heatmap_cells.tex\n")

## Best-fit point (m_hat, kappa_hat)
if (export_mode == "PHASE_A_REAL_DATA") {
  fit_m <- gs[which(gs$is_optimum)[1], "m"]
  fit_k <- gs[which(gs$is_optimum)[1], "kappa"]
  if (is.na(fit_m) || is.na(fit_k)) {
    fit_m <- mean_vals[which.min(colMeans(z_raw, na.rm = TRUE))]
    fit_k <- kappa_vals[which.min(rowMeans(z_raw, na.rm = TRUE))]
  }
  opt_x <- fit_m * 100
  opt_y <- log10(fit_k)
} else {
  opt_x <- dat$est$m_hat * 100
  opt_y <- log10(dat$est$kappa_hat)
}
writeLines(
  c(
    sprintf("\\newcommand{\\optX}{%s}", round(opt_x, 2)),
    sprintf("\\newcommand{\\optY}{%s}", round(opt_y, 4))
  ),
  file.path(data_dir, "panel_B1_optimum.tex")
)
cat("   panel_B1_optimum.tex\n")


# --- Panel C: regime density curves ------------------------------------------
cat("Panel C...\n")
p_grid <- seq(0.001, 0.999, length.out = 500)
d_true <- if (export_mode == "PHASE_A_REAL_DATA") {
  if (!is.null(dat$regime_density)) {
    approx(
      dat$regime_density$p,
      dat$regime_density$density_true,
      xout = p_grid,
      rule = 2
    )$y
  } else {
    rep(NA_real_, length(p_grid))
  }
} else {
  dat$true_regime$density(p_grid)
}
d_inf <- if (export_mode == "PHASE_A_REAL_DATA") {
  approx(
    dat$regime_density$p,
    dat$regime_density$density_hat,
    xout = p_grid,
    rule = 2
  )$y
} else {
  dat$est$regime$density(p_grid)
}
write_dat(
  round(p_grid * 100, 4),
  round(rep(1, length(p_grid)), 4),
  "panel_C_density_uniform.dat"
)
write_dat(
  round(p_grid * 100, 4),
  round(ifelse(is.na(d_true), 0, d_true), 6),
  "panel_C_density_true.dat"
)
write_dat(
  round(p_grid * 100, 4),
  round(d_inf, 6),
  "panel_C_density_inferred.dat"
)


# --- Summary metrics (LaTeX macros) ------------------------------------------
cat("Summary metrics...\n")
w1_uniform <- if (export_mode == "PHASE_A_REAL_DATA") {
  dat$fit_metrics$w1_uniform[[1]]
} else {
  dat$distances$uniform$wasserstein1
}
w1_inferred <- if (export_mode == "PHASE_A_REAL_DATA") {
  dat$fit_metrics$w1_best[[1]]
} else {
  dat$distances$inferred$wasserstein1
}
w1_reduction <- ifelse(
  isTRUE(w1_uniform > 0),
  100 * (1 - w1_inferred / w1_uniform),
  NA_real_
)
true_mean <- if (export_mode == "PHASE_A_REAL_DATA") {
  NA_real_
} else {
  dat$true_regime$mean * 100
}
true_median <- if (export_mode == "PHASE_A_REAL_DATA") {
  NA_real_
} else {
  dat$true_regime$median * 100
}
inferred_mean <- if (export_mode == "PHASE_A_REAL_DATA") {
  mean(
    dat$regime_density$p *
      dat$regime_density$density_hat /
      sum(dat$regime_density$density_hat),
    na.rm = TRUE
  ) *
    100
} else {
  dat$est$regime$mean * 100
}
inferred_median <- if (export_mode == "PHASE_A_REAL_DATA") {
  NA_real_
} else {
  dat$est$regime$median * 100
}
inferred_kappa <- if (export_mode == "PHASE_A_REAL_DATA") {
  fit_k
} else {
  dat$est$kappa_hat
}

metrics <- c(
  sprintf(
    "\\newcommand{\\trueRegimeMean}{%.1f}",
    ifelse(is.na(true_mean), 0, true_mean)
  ),
  sprintf(
    "\\newcommand{\\trueRegimeMedian}{%.1f}",
    ifelse(is.na(true_median), 0, true_median)
  ),
  sprintf("\\newcommand{\\inferredRegimeMean}{%.1f}", inferred_mean),
  sprintf(
    "\\newcommand{\\inferredRegimeMedian}{%.1f}",
    ifelse(is.na(inferred_median), 0, inferred_median)
  ),
  sprintf("\\newcommand{\\wOneUniform}{%.4f}", w1_uniform),
  sprintf("\\newcommand{\\wOneInferred}{%.4f}", w1_inferred),
  sprintf("\\newcommand{\\wOneReduction}{%.1f}", w1_reduction),
  sprintf(
    "\\newcommand{\\copulaRho}{%.2f}",
    ifelse(
      !is.null(dat$copula_used$params$rho),
      dat$copula_used$params$rho,
      ifelse(!is.null(dat$config$copula_rho), dat$config$copula_rho, 0)
    )
  ),
  sprintf(
    "\\newcommand{\\copulaDf}{%s}",
    ifelse(
      !is.null(dat$copula_used$params$df),
      dat$copula_used$params$df,
      ifelse(!is.null(dat$config$copula_df), dat$config$copula_df, "NA")
    )
  ),
  sprintf(
    "\\newcommand{\\nStudents}{%s}",
    ifelse(!is.null(dat$n_subgroup), dat$n_subgroup, dat$config$n_students)
  ),
  sprintf("\\newcommand{\\inferredKappa}{%.1f}", inferred_kappa),
  sprintf(
    "\\newcommand{\\trueRegimeKappa}{%s}",
    ifelse(
      !is.null(dat$config$true_regime_kappa),
      dat$config$true_regime_kappa,
      "NA"
    )
  )
)
writeLines(metrics, file.path(data_dir, "summary_metrics.tex"))
cat("   summary_metrics.tex\n")


# --- Axis limits (LaTeX macros) ----------------------------------------------
cat("Axis limits...\n")
y_max_a <- max(c(d_u$y, d_v$y)) * 1.15
y_max_d <- max(c(1, d_true, d_inf), na.rm = TRUE) * 1.12
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
  sprintf("\\newcommand{\\inferredMeanVline}{%s}", round(inferred_mean, 1)),
  sprintf(
    "\\newcommand{\\trueMeanVline}{%s}",
    round(ifelse(is.na(true_mean), 50, true_mean), 1)
  )
)
writeLines(axes, file.path(data_dir, "axis_limits.tex"))
cat("   axis_limits.tex\n")

cat("\nExport complete. Files in:", data_dir, "\n")
