############################################################################
###
### STEP 3 — LaTeX-based 2×2 Summary Grid: Metric × Copula
###
### Following the STEP 1 pattern (generate_summary_grid_latex), this
### function composes individual PDF plots into a 2×2 grid using LaTeX
### minipages and \includegraphics.  This approach gives precise control
### over layout, typography, and metadata annotations.
###
### Grid layout:
###
###            | Canonical Copula        | Best-Fit Parametric
###   ---------+-------------------------+------------------------
###   W1-opt   | CDF + Regime plots      | CDF + Regime plots
###   CvM-opt  | CDF + Regime plots      | CDF + Regime plots
###
### Each cell contains a CDF overlay and regime density plot side by side.
### A metadata sidebar summarises the key deltas across all 4 cells.
###
### Author: dataimago
### Date: March 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (!is.null(x)) x else y
}

#' Generate a LaTeX-based 2×2 Summary Grid (Metric × Copula)
#'
#' Composes individual Phase A PDF plots into a summary grid via LaTeX.
#' Each cell of the metric × copula matrix shows a CDF overlay and regime
#' density plot side by side, with a metadata panel summarising deltas.
#'
#' @param output_dir       Directory containing the individual plot PDFs.
#' @param condition_id     Character. The condition ID string.
#' @param subgroup_id      Character. The subgroup identifier.
#' @param copula_sensitivity  List from run_deep_dive (copula comparison deltas).
#' @param true_sgpc        Numeric vector of ground-truth SGPc values.
#' @param best_est         W1-optimised result under canonical copula.
#' @param best_est_cvm     CvM-optimised result under canonical copula (may be NULL).
#' @param primary_copula_label  Character label for canonical copula.
#' @param alt_copula_label      Character label for best-fit copula.
#' @param figure_map       Named list of figure filenames (from get_phasea_figure_map).
#' @param compile_pdf      Logical. Compile .tex to PDF? (default TRUE)
#' @param keep_tex         Logical. Retain .tex after compilation? (default TRUE)
#' @param fbox_sep         Integer. fbox separation in points (default 3).
#' @param export_formats   Character vector of output formats (default c("pdf","svg","png")).
#' @param export_dpi       Integer. DPI for PNG export (default 300).
#'
#' @return Invisible path to the generated PDF (or .tex if compile_pdf=FALSE).
#'
#' @export
generate_metric_copula_grid_latex <- function(
  output_dir,
  condition_id,
  subgroup_id,
  copula_sensitivity,
  true_sgpc = NULL,
  best_est = NULL,
  best_est_cvm = NULL,
  primary_copula_label = "Canonical",
  alt_copula_label = "Best-fit",
  figure_map = NULL,
  compile_pdf = TRUE,
  keep_tex = TRUE,
  fbox_sep = 3,
  export_formats = c("pdf", "svg", "png"),
  export_dpi = 300
) {
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

  cs <- copula_sensitivity
  fm <- figure_map

  # --- Determine which cells exist (PDF files) ---
  .pdf_path <- function(key) {
    if (is.null(fm[[key]])) {
      return(NULL)
    }
    p <- file.path(output_dir, paste0(fm[[key]], ".pdf"))
    if (file.exists(p)) fm[[key]] %+% ".pdf" else NULL
  }
  `%+%` <- function(a, b) paste0(a, b)

  # Helper: relative path for LaTeX \includegraphics
  rel_pdf <- function(key) {
    fname <- paste0(fm[[key]], ".pdf")
    fpath <- file.path(output_dir, fname)
    if (file.exists(fpath)) fname else NULL
  }

  # Identify available cells
  w1_canon_cdf <- rel_pdf("grid_w1_canonical_cdf")
  w1_canon_reg <- rel_pdf("grid_w1_canonical_regime")
  w1_bestfit_cdf <- rel_pdf("grid_w1_bestfit_cdf")
  w1_bestfit_reg <- rel_pdf("grid_w1_bestfit_regime")
  cvm_canon_cdf <- rel_pdf("grid_cvm_canonical_cdf")
  cvm_canon_reg <- rel_pdf("grid_cvm_canonical_regime")
  cvm_bestfit_cdf <- rel_pdf("grid_cvm_bestfit_cdf")
  cvm_bestfit_reg <- rel_pdf("grid_cvm_bestfit_regime")

  has_cvm_row <- !is.null(cvm_canon_cdf) || !is.null(cvm_bestfit_cdf)

  # --- Format numbers ---
  fmt <- function(x, digits = 1) {
    if (is.null(x) || !is.numeric(x) || is.na(x) || is.nan(x)) {
      return("--")
    }
    format(round(x, digits), nsmall = digits)
  }
  fmt6 <- function(x) fmt(x, 6)

  # --- Extract summary metrics for each cell ---
  # W1 / Canonical
  w1c_med <- if (!is.null(best_est)) best_est$regime$median * 100 else NA
  w1c_mean <- if (!is.null(best_est)) best_est$regime$mean * 100 else NA
  w1c_w1 <- if (!is.null(best_est)) best_est$all_distances$wasserstein1 else NA
  w1c_cvm <- if (!is.null(best_est)) {
    best_est$all_distances$cramer_von_mises
  } else {
    NA
  }

  # W1 / Best-fit
  alt_est <- cs$alt_best_est
  w1b_med <- if (!is.null(alt_est)) alt_est$regime$median * 100 else NA
  w1b_mean <- if (!is.null(alt_est)) alt_est$regime$mean * 100 else NA
  w1b_w1 <- if (!is.null(alt_est)) alt_est$all_distances$wasserstein1 else NA
  w1b_cvm <- if (!is.null(alt_est)) {
    alt_est$all_distances$cramer_von_mises
  } else {
    NA
  }

  # CvM / Canonical
  cvmc_med <- if (!is.null(best_est_cvm)) {
    best_est_cvm$regime$median * 100
  } else {
    NA
  }
  cvmc_mean <- if (!is.null(best_est_cvm)) {
    best_est_cvm$regime$mean * 100
  } else {
    NA
  }
  cvmc_w1 <- if (!is.null(best_est_cvm)) {
    best_est_cvm$all_distances$wasserstein1
  } else {
    NA
  }
  cvmc_cvm <- if (!is.null(best_est_cvm)) {
    best_est_cvm$all_distances$cramer_von_mises
  } else {
    NA
  }

  # CvM / Best-fit
  alt_cvm_est <- cs$alt_cvm_est
  cvmb_med <- if (!is.null(alt_cvm_est)) alt_cvm_est$regime$median * 100 else NA
  cvmb_mean <- if (!is.null(alt_cvm_est)) alt_cvm_est$regime$mean * 100 else NA
  cvmb_w1 <- if (!is.null(alt_cvm_est)) {
    alt_cvm_est$all_distances$wasserstein1
  } else {
    NA
  }
  cvmb_cvm <- if (!is.null(alt_cvm_est)) {
    alt_cvm_est$all_distances$cramer_von_mises
  } else {
    NA
  }

  # Ground truth
  true_med <- if (!is.null(true_sgpc)) median(true_sgpc, na.rm = TRUE) else NA
  true_mean <- if (!is.null(true_sgpc)) mean(true_sgpc, na.rm = TRUE) else NA

  # LaTeX-escape underscores
  esc <- function(s) gsub("_", "\\\\_", as.character(s))

  # Shorten copula labels for column headers
  short_canon <- gsub(
    "Canonical t \\(.*\\)",
    "Canonical t",
    primary_copula_label
  )
  short_bestfit <- gsub(
    "Best-fit parametric \\((.*)\\)",
    "\\1 (best-fit)",
    alt_copula_label
  )

  # --- Build LaTeX document ---
  tex <- c(
    "\\documentclass[border=5pt]{standalone}",
    "\\usepackage{graphicx}",
    "\\usepackage{xcolor}",
    "\\usepackage{amsmath,amssymb}",
    "\\usepackage{array}",
    "\\usepackage{booktabs}",
    "\\usepackage[T1]{fontenc}",
    "\\usepackage{helvet}",
    "\\renewcommand{\\familydefault}{\\sfdefault}",
    "",
    "% Colors matching STEP 3 Zissou1 palette",
    "\\definecolor{zissou-teal}{RGB}{59,154,178}",
    "\\definecolor{zissou-amber}{RGB}{225,175,0}",
    "\\definecolor{zissou-red}{RGB}{242,26,0}",
    "\\definecolor{textgray}{RGB}{60,60,60}",
    "\\definecolor{lightgray}{RGB}{245,245,245}",
    "\\definecolor{titlebg}{RGB}{20,20,16}",
    "\\definecolor{titletext}{RGB}{237,237,235}",
    "",
    "\\begin{document}",
    sprintf("\\setlength{\\fboxsep}{%dpt}", fbox_sep),
    "\\setlength{\\fboxrule}{0.4pt}",
    "",
    "\\begin{minipage}{16in}",
    "",
    "% === TITLE BAR ===",
    "\\noindent%",
    "\\colorbox{titlebg}{%",
    "\\begin{minipage}[c][0.55in][c]{0.99\\textwidth}",
    "\\centering",
    sprintf(
      "{\\color{titletext}\\Large\\bfseries STEP 3: Metric $\\times$ Copula Sensitivity Grid \\quad %s \\quad Subgroup: %s}",
      esc(condition_id),
      esc(subgroup_id)
    ),
    "\\end{minipage}%",
    "}",
    "",
    "\\vspace{0.12in}",
    ""
  )

  # --- Column headers ---
  tex <- c(
    tex,
    "% === COLUMN HEADERS ===",
    "\\noindent%",
    "\\begin{minipage}[t]{0.18\\textwidth}\\phantom{x}\\end{minipage}%",
    "\\hfill%",
    "\\begin{minipage}[t]{0.39\\textwidth}",
    sprintf(
      "\\centering{\\large\\bfseries\\color{zissou-teal} %s}",
      esc(short_canon)
    ),
    "\\end{minipage}%",
    "\\hfill%",
    "\\begin{minipage}[t]{0.39\\textwidth}",
    sprintf(
      "\\centering{\\large\\bfseries\\color{zissou-amber} %s}",
      esc(short_bestfit)
    ),
    "\\end{minipage}%",
    "",
    "\\vspace{0.08in}",
    ""
  )

  # --- Helper: emit a grid row (CDF left, Regime right in each column) ---
  .emit_row <- function(row_label, left_cdf, left_reg, right_cdf, right_reg) {
    row_lines <- c(
      "\\noindent%",
      "% Row label",
      "\\begin{minipage}[c]{0.18\\textwidth}",
      "\\vspace*{0pt}%",
      sprintf("\\centering{\\large\\bfseries\\color{textgray} %s}", row_label),
      "\\end{minipage}%",
      "\\hfill%"
    )

    # Left column (canonical)
    row_lines <- c(row_lines, "\\begin{minipage}[t]{0.39\\textwidth}%")
    if (!is.null(left_cdf) && !is.null(left_reg)) {
      row_lines <- c(
        row_lines,
        "\\centering%",
        sprintf(
          "\\fbox{\\includegraphics[width=0.48\\textwidth]{%s}}",
          left_cdf
        ),
        "\\hfill%",
        sprintf(
          "\\fbox{\\includegraphics[width=0.48\\textwidth]{%s}}",
          left_reg
        )
      )
    } else if (!is.null(left_cdf)) {
      row_lines <- c(
        row_lines,
        "\\centering%",
        sprintf(
          "\\fbox{\\includegraphics[width=0.70\\textwidth]{%s}}",
          left_cdf
        )
      )
    } else {
      row_lines <- c(
        row_lines,
        "\\centering{\\color{textgray}\\itshape Not available (single-metric mode)}"
      )
    }
    row_lines <- c(row_lines, "\\end{minipage}%", "\\hfill%")

    # Right column (best-fit)
    row_lines <- c(row_lines, "\\begin{minipage}[t]{0.39\\textwidth}%")
    if (!is.null(right_cdf) && !is.null(right_reg)) {
      row_lines <- c(
        row_lines,
        "\\centering%",
        sprintf(
          "\\fbox{\\includegraphics[width=0.48\\textwidth]{%s}}",
          right_cdf
        ),
        "\\hfill%",
        sprintf(
          "\\fbox{\\includegraphics[width=0.48\\textwidth]{%s}}",
          right_reg
        )
      )
    } else if (!is.null(right_cdf)) {
      row_lines <- c(
        row_lines,
        "\\centering%",
        sprintf(
          "\\fbox{\\includegraphics[width=0.70\\textwidth]{%s}}",
          right_cdf
        )
      )
    } else {
      row_lines <- c(
        row_lines,
        "\\centering{\\color{textgray}\\itshape Not available}"
      )
    }
    row_lines <- c(row_lines, "\\end{minipage}%", "", "\\vspace{0.10in}", "")
    row_lines
  }

  # --- W1 row ---
  tex <- c(
    tex,
    .emit_row(
      "Wasserstein-1\\\\Optimised",
      w1_canon_cdf,
      w1_canon_reg,
      w1_bestfit_cdf,
      w1_bestfit_reg
    )
  )

  # --- CvM row (only if dual-metric mode produced results) ---
  if (has_cvm_row) {
    tex <- c(
      tex,
      .emit_row(
        "Cram\\'{e}r--von Mises\\\\Optimised",
        cvm_canon_cdf,
        cvm_canon_reg,
        cvm_bestfit_cdf,
        cvm_bestfit_reg
      )
    )
  }

  # --- Summary metrics table ---
  tex <- c(
    tex,
    "\\vspace{0.08in}",
    "\\noindent\\rule{\\textwidth}{0.5pt}",
    "\\vspace{0.08in}",
    "",
    "\\noindent%",
    "\\begin{minipage}{\\textwidth}",
    "\\centering",
    "\\small",
    sprintf(
      "{\\bfseries Ground Truth:} Median SGPc = %s, Mean SGPc = %s",
      fmt(true_med),
      fmt(true_mean)
    ),
    "\\\\[0.3em]",
    "\\begin{tabular}{l cc cc cc}",
    "\\toprule",
    " & \\multicolumn{2}{c}{\\bfseries Median SGPc} & \\multicolumn{2}{c}{\\bfseries Mean SGPc} & \\multicolumn{2}{c}{\\bfseries Fit (W1 / CvM)} \\\\",
    sprintf("\\cmidrule(lr){2-3} \\cmidrule(lr){4-5} \\cmidrule(lr){6-7}"),
    sprintf(
      " & %s & %s & %s & %s & %s & %s \\\\",
      esc(short_canon),
      esc(short_bestfit),
      esc(short_canon),
      esc(short_bestfit),
      esc(short_canon),
      esc(short_bestfit)
    ),
    "\\midrule",
    sprintf(
      "W1-opt & %s & %s & %s & %s & %s / %s & %s / %s \\\\",
      fmt(w1c_med),
      fmt(w1b_med),
      fmt(w1c_mean),
      fmt(w1b_mean),
      fmt6(w1c_w1),
      fmt6(w1c_cvm),
      fmt6(w1b_w1),
      fmt6(w1b_cvm)
    )
  )

  if (has_cvm_row) {
    tex <- c(
      tex,
      sprintf(
        "CvM-opt & %s & %s & %s & %s & %s / %s & %s / %s \\\\",
        fmt(cvmc_med),
        fmt(cvmb_med),
        fmt(cvmc_mean),
        fmt(cvmb_mean),
        fmt6(cvmc_w1),
        fmt6(cvmc_cvm),
        fmt6(cvmb_w1),
        fmt6(cvmb_cvm)
      )
    )
  }

  # Deltas
  tex <- c(
    tex,
    "\\midrule",
    sprintf(
      "$\\Delta$ (copula) & \\multicolumn{2}{c}{%s SGP pts} & \\multicolumn{2}{c}{%s SGP pts} & & \\\\",
      fmt(cs$delta_median_sgpc, 2),
      fmt(cs$delta_mean_sgpc, 2)
    )
  )

  if (has_cvm_row && !is.na(w1c_med) && !is.na(cvmc_med)) {
    metric_delta_med <- cvmc_med - w1c_med
    metric_delta_mean <- cvmc_mean - w1c_mean
    tex <- c(
      tex,
      sprintf(
        "$\\Delta$ (metric) & \\multicolumn{2}{c}{%s SGP pts} & \\multicolumn{2}{c}{%s SGP pts} & & \\\\",
        fmt(metric_delta_med, 2),
        fmt(metric_delta_mean, 2)
      )
    )
  }

  tex <- c(
    tex,
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{minipage}",
    "",
    "\\end{minipage}",
    "",
    "\\end{document}"
  )

  # --- Write .tex ---
  grid_basename <- fm[["metric_copula_grid"]] %||%
    "phasea_06_metric_copula_grid"
  tex_path <- file.path(output_dir, paste0(grid_basename, ".tex"))
  writeLines(tex, tex_path)
  cat(sprintf("  LaTeX source written: %s\n", tex_path))

  # --- Compile to PDF ---
  compiled <- FALSE
  if (isTRUE(compile_pdf)) {
    pdf_path <- file.path(output_dir, paste0(grid_basename, ".pdf"))

    # Try tinytex first, then system pdflatex
    if (requireNamespace("tinytex", quietly = TRUE)) {
      tryCatch(
        {
          old_wd <- getwd()
          setwd(output_dir)
          on.exit(setwd(old_wd), add = TRUE)
          tinytex::pdflatex(
            paste0(grid_basename, ".tex"),
            pdf_file = paste0(grid_basename, ".pdf")
          )
          compiled <- TRUE
          cat(sprintf("  PDF compiled via tinytex: %s\n", pdf_path))
        },
        error = function(e) {
          warning("tinytex compilation failed: ", e$message)
        }
      )
    }

    if (!compiled && Sys.which("pdflatex") != "") {
      tryCatch(
        {
          old_wd <- getwd()
          setwd(output_dir)
          on.exit(setwd(old_wd), add = TRUE)
          status <- system2(
            "pdflatex",
            args = c("-interaction=nonstopmode", paste0(grid_basename, ".tex")),
            stdout = FALSE,
            stderr = FALSE
          )
          compiled <- identical(status, 0L)
          if (compiled) {
            cat(sprintf("  PDF compiled via system pdflatex: %s\n", pdf_path))
          } else {
            warning(sprintf("pdflatex exited with status %s", status))
          }
        },
        error = function(e) {
          warning("System pdflatex compilation failed: ", e$message)
        }
      )
    }

    if (!compiled) {
      warning(
        "Could not compile PDF. Install tinytex: ",
        "install.packages('tinytex'); tinytex::install_tinytex()"
      )
      cat("  .tex file retained for manual compilation\n")
      keep_tex <- TRUE
    }

    # Clean auxiliary files
    for (ext in c(".aux", ".log", ".out")) {
      aux <- file.path(output_dir, paste0(grid_basename, ext))
      if (file.exists(aux)) file.remove(aux)
    }

    # SVG and PNG conversion (same pattern as STEP 1)
    if (compiled && file.exists(pdf_path)) {
      if ("svg" %in% export_formats && Sys.which("pdf2svg") != "") {
        svg_path <- file.path(output_dir, paste0(grid_basename, ".svg"))
        tryCatch(
          {
            status <- system2(
              "pdf2svg",
              args = c(pdf_path, svg_path),
              stdout = FALSE,
              stderr = FALSE
            )
            if (identical(status, 0L) && file.exists(svg_path)) {
              cat(sprintf("  SVG converted: %s\n", svg_path))
            }
          },
          error = function(e) warning("pdf2svg failed: ", e$message)
        )
      }

      if ("png" %in% export_formats && Sys.which("pdftoppm") != "") {
        png_path <- file.path(output_dir, paste0(grid_basename, ".png"))
        tryCatch(
          {
            tmp_prefix <- file.path(output_dir, paste0(grid_basename, "_tmp"))
            status <- system2(
              "pdftoppm",
              args = c(
                "-png",
                "-r",
                as.character(export_dpi),
                "-singlefile",
                pdf_path,
                tmp_prefix
              ),
              stdout = FALSE,
              stderr = FALSE
            )
            tmp_png <- paste0(tmp_prefix, ".png")
            if (file.exists(tmp_png)) {
              file.rename(tmp_png, png_path)
              cat(sprintf(
                "  PNG converted (%ddpi): %s\n",
                export_dpi,
                png_path
              ))
            }
          },
          error = function(e) warning("pdftoppm failed: ", e$message)
        )
      }
    }

    # Remove .tex if not keeping
    if (!isTRUE(keep_tex) && compiled && file.exists(tex_path)) {
      file.remove(tex_path)
    }
  }

  invisible(if (compiled) pdf_path else tex_path)
}

cat("STEP 3 copula_metric_grid_latex.R loaded.\n")
cat("  Functions: generate_metric_copula_grid_latex\n")
