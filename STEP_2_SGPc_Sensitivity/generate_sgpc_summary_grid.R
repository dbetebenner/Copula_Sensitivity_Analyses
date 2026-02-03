############################################################################
### STEP 2: SGPc Sensitivity Analysis - Flexible LaTeX Grid Assembly
###
### Purpose: Assemble individual plot panels into a publication-grade grid
###          Supports 2x3 layout (2 plots in row 1, 3 in row 2)
###          Adapted from STEP 1's generate_summary_grid_latex()
###
### Author: dataimago
### Date: January 2026
############################################################################

#' Generate LaTeX-based summary grid for SGPc sensitivity analysis
#' 
#' @param plot_files Named character vector of panel filenames (e.g., c(panel_a = "panel_a.pdf", ...))
#' @param output_dir Directory where plots are located and output will be saved
#' @param layout Character string specifying layout: "2x3" (default), "3x2", or "custom"
#' @param title Main figure title
#' @param compile_pdf Logical, whether to compile LaTeX to PDF
#' @param keep_tex Logical, whether to keep .tex file after compilation
#' @param export_formats Character vector of export formats (default: c("pdf", "svg", "png"))
#' @param export_dpi DPI for raster formats
#' @return Invisible list with paths to generated files
generate_sgpc_summary_grid_latex <- function(
  plot_files,
  output_dir,
  layout = "2x3",
  title = "SGPc Sensitivity to Copula Choice: A Multi-Level Analysis",
  compile_pdf = TRUE,
  keep_tex = FALSE,
  export_formats = c("pdf", "svg", "png"),
  export_dpi = 300
) {
  
  cat("====================================================================\n")
  cat("GENERATING SGPC SENSITIVITY SUMMARY GRID\n")
  cat("====================================================================\n\n")
  
  # Normalize output_dir to absolute path
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  
  cat("Configuration:\n")
  cat(sprintf("  Output directory: %s\n", output_dir))
  cat(sprintf("  Layout: %s\n", layout))
  cat(sprintf("  Number of panels: %d\n", length(plot_files)))
  cat(sprintf("  Export formats: %s\n", paste(export_formats, collapse = ", ")))
  cat("\n")
  
  # Verify all plot files exist
  cat("Verifying panel files:\n")
  all_exist <- TRUE
  for (i in seq_along(plot_files)) {
    panel_name <- names(plot_files)[i]
    panel_file <- plot_files[i]
    full_path <- file.path(output_dir, panel_file)
    
    if (file.exists(full_path)) {
      cat(sprintf("  ✓ %s: %s\n", panel_name, panel_file))
    } else {
      cat(sprintf("  ✗ %s: %s (NOT FOUND)\n", panel_name, panel_file))
      all_exist <- FALSE
    }
  }
  cat("\n")
  
  if (!all_exist) {
    stop("Some panel files not found. Generate plots first with sgpc_publication_plots.R")
  }
  
  ############################################################################
  ### BUILD LATEX DOCUMENT
  ############################################################################
  
  cat("Building LaTeX document...\n")
  
  # Document preamble
  tex_lines <- c(
    "\\documentclass[11pt]{article}",
    "",
    "% Packages",
    "\\usepackage[margin=0.5in, paperwidth=16in, paperheight=12in]{geometry}",
    "\\usepackage{graphicx}",
    "\\usepackage{caption}",
    "\\usepackage{subcaption}",
    "\\usepackage{amsmath}",
    "\\usepackage{xcolor}",
    "\\usepackage{helvet}  % Use Helvetica font",
    "\\renewcommand{\\familydefault}{\\sfdefault}",
    "",
    "% Remove page numbers",
    "\\pagestyle{empty}",
    "",
    "% Tight spacing",
    "\\setlength{\\parindent}{0pt}",
    "\\setlength{\\parskip}{0pt}",
    "\\setlength{\\fboxsep}{2pt}",
    "",
    "\\begin{document}",
    "",
    "% Main title",
    sprintf("\\begin{center}{\\Large\\bfseries %s}\\end{center}", title),
    "\\vspace{0.3cm}",
    ""
  )
  
  ############################################################################
  ### LAYOUT-SPECIFIC ASSEMBLY
  ############################################################################
  
  if (layout == "2x3") {
    # Row 1: 2 panels (A and B)
    tex_lines <- c(tex_lines,
      "% ============================================================",
      "% ROW 1: Panel A (left) + Panel B (right)",
      "% ============================================================",
      "\\noindent%",
      "\\begin{minipage}[t]{0.49\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_a"]),
      "  \\captionof{figure}{\\textbf{(A)} Individual-Level Sensitivity}",
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.49\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_b"]),
      "  \\captionof{figure}{\\textbf{(B)} Group-Level Aggregation}",
      "\\end{minipage}",
      "",
      "\\vspace{0.4cm}",
      ""
    )
    
    # Row 2: 3 panels (C, D1, D2)
    tex_lines <- c(tex_lines,
      "% ============================================================",
      "% ROW 2: Panel C (left) + Panel D1 (middle) + Panel D2 (right)",
      "% ============================================================",
      "\\noindent%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_c"]),
      "  \\captionof{figure}{\\textbf{(C)} Condition Replication}",
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_d1"]),
      "  \\captionof{figure}{\\textbf{(D1)} Rank Stability}",
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_d2"]),
      "  \\captionof{figure}{\\textbf{(D2)} Classification Stability}",
      "\\end{minipage}",
      ""
    )
    
  } else if (layout == "3x2") {
    # Alternative layout: 3 panels in row 1, 2 in row 2
    tex_lines <- c(tex_lines,
      "% ============================================================",
      "% ROW 1: 3 panels",
      "% ============================================================",
      "\\noindent%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[1]),
      sprintf("  \\captionof{figure}{\\textbf{(%s)}}", LETTERS[1]),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[2]),
      sprintf("  \\captionof{figure}{\\textbf{(%s)}}", LETTERS[2]),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[3]),
      sprintf("  \\captionof{figure}{\\textbf{(%s)}}", LETTERS[3]),
      "\\end{minipage}",
      "",
      "\\vspace{0.4cm}",
      "",
      "% ============================================================",
      "% ROW 2: 2 panels",
      "% ============================================================",
      "\\noindent%",
      "\\begin{minipage}[t]{0.49\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[4]),
      sprintf("  \\captionof{figure}{\\textbf{(%s)}}", LETTERS[4]),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.49\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[5]),
      sprintf("  \\captionof{figure}{\\textbf{(%s)}}", LETTERS[5]),
      "\\end{minipage}",
      ""
    )
  } else {
    stop("Unsupported layout: ", layout, ". Use '2x3' or '3x2'")
  }
  
  # Document closing
  tex_lines <- c(tex_lines,
    "",
    "\\end{document}"
  )
  
  ############################################################################
  ### WRITE TEX FILE
  ############################################################################
  
  tex_path <- file.path(output_dir, "sgpc_summary_grid.tex")
  writeLines(tex_lines, tex_path)
  cat(sprintf("  ✓ LaTeX source written: %s\n\n", tex_path))
  
  ############################################################################
  ### COMPILE TO PDF
  ############################################################################
  
  if (compile_pdf) {
    cat("Compiling LaTeX to PDF...\n")
    pdf_path <- file.path(output_dir, "sgpc_summary_grid.pdf")
    
    compiled <- FALSE
    
    # Try tinytex first
    if (requireNamespace("tinytex", quietly = TRUE)) {
      tryCatch({
        old_wd <- getwd()
        setwd(output_dir)
        on.exit(setwd(old_wd), add = TRUE)
        
        tinytex::pdflatex("sgpc_summary_grid.tex", pdf_file = "sgpc_summary_grid.pdf")
        compiled <- TRUE
        cat(sprintf("  ✓ PDF compiled via tinytex: %s\n", pdf_path))
      }, error = function(e) {
        cat(sprintf("  ✗ tinytex compilation failed: %s\n", e$message))
      })
    }
    
    # Try system pdflatex as fallback
    if (!compiled) {
      tryCatch({
        old_wd <- getwd()
        setwd(output_dir)
        on.exit(setwd(old_wd), add = TRUE)
        
        system2("pdflatex", 
                args = c("-interaction=nonstopmode", "sgpc_summary_grid.tex"),
                stdout = FALSE, stderr = FALSE)
        
        if (file.exists("sgpc_summary_grid.pdf")) {
          compiled <- TRUE
          cat(sprintf("  ✓ PDF compiled via system pdflatex: %s\n", pdf_path))
        }
      }, error = function(e) {
        cat(sprintf("  ✗ system pdflatex failed: %s\n", e$message))
      })
    }
    
    if (!compiled) {
      warning("PDF compilation failed. LaTeX source saved but not compiled.")
    }
    
    # Clean up auxiliary files if requested
    if (!keep_tex && compiled) {
      aux_files <- c("sgpc_summary_grid.aux", "sgpc_summary_grid.log", "sgpc_summary_grid.out")
      for (aux_file in aux_files) {
        aux_path <- file.path(output_dir, aux_file)
        if (file.exists(aux_path)) file.remove(aux_path)
      }
      cat("  ✓ Cleaned up auxiliary files\n")
    }
    
    cat("\n")
    
    ############################################################################
    ### EXPORT TO ADDITIONAL FORMATS
    ############################################################################
    
    if (compiled && length(setdiff(export_formats, "pdf")) > 0) {
      cat("Exporting to additional formats...\n")
      
      # SVG export (requires pdf2svg or Inkscape)
      if ("svg" %in% export_formats) {
        svg_path <- file.path(output_dir, "sgpc_summary_grid.svg")
        
        # Try pdf2svg first
        if (Sys.which("pdf2svg") != "") {
          system2("pdf2svg", args = c(pdf_path, svg_path))
          if (file.exists(svg_path)) {
            cat(sprintf("  ✓ SVG exported: %s\n", svg_path))
          }
        } else if (Sys.which("inkscape") != "") {
          system2("inkscape", args = c(pdf_path, "--export-filename", svg_path))
          if (file.exists(svg_path)) {
            cat(sprintf("  ✓ SVG exported (via Inkscape): %s\n", svg_path))
          }
        } else {
          cat("  ✗ SVG export skipped (pdf2svg or inkscape not found)\n")
        }
      }
      
      # PNG export (requires ImageMagick convert or pdftoppm)
      if ("png" %in% export_formats) {
        png_path <- file.path(output_dir, "sgpc_summary_grid.png")
        
        # Try ImageMagick first
        if (Sys.which("convert") != "") {
          system2("convert", 
                  args = c("-density", export_dpi, pdf_path, "-quality", "100", png_path))
          if (file.exists(png_path)) {
            cat(sprintf("  ✓ PNG exported: %s\n", png_path))
          }
        } else if (Sys.which("pdftoppm") != "") {
          system2("pdftoppm", 
                  args = c("-png", "-r", export_dpi, pdf_path, 
                          file.path(output_dir, "sgpc_summary_grid")))
          # pdftoppm adds page numbers; rename if single page
          temp_png <- file.path(output_dir, "sgpc_summary_grid-1.png")
          if (file.exists(temp_png)) {
            file.rename(temp_png, png_path)
            cat(sprintf("  ✓ PNG exported (via pdftoppm): %s\n", png_path))
          }
        } else {
          cat("  ✗ PNG export skipped (ImageMagick convert or pdftoppm not found)\n")
        }
      }
      
      cat("\n")
    }
  }
  
  ############################################################################
  ### SUMMARY
  ############################################################################
  
  cat("====================================================================\n")
  cat("SGPC SUMMARY GRID GENERATION COMPLETE\n")
  cat("====================================================================\n\n")
  
  cat("Output files:\n")
  cat(sprintf("  LaTeX source: %s\n", tex_path))
  if (compiled) {
    cat(sprintf("  PDF: %s\n", pdf_path))
    if ("svg" %in% export_formats && file.exists(file.path(output_dir, "sgpc_summary_grid.svg"))) {
      cat(sprintf("  SVG: %s\n", file.path(output_dir, "sgpc_summary_grid.svg")))
    }
    if ("png" %in% export_formats && file.exists(file.path(output_dir, "sgpc_summary_grid.png"))) {
      cat(sprintf("  PNG: %s\n", file.path(output_dir, "sgpc_summary_grid.png")))
    }
  }
  cat("\n")
  
  # Return paths invisibly
  invisible(list(
    tex = tex_path,
    pdf = if (compiled) pdf_path else NULL,
    svg = if ("svg" %in% export_formats) file.path(output_dir, "sgpc_summary_grid.svg") else NULL,
    png = if ("png" %in% export_formats) file.path(output_dir, "sgpc_summary_grid.png") else NULL
  ))
}
