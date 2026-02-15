############################################################################
### STEP 2: SGPc Sensitivity Analysis - Flexible LaTeX Grid Assembly
###
### Purpose: Assemble individual plot panels into a publication-grade grid
###          Supports layouts: 2x3, 3x2, 4x2 (8-panel full figure)
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
#' @param figure_number Figure number to use for all panels (default: 3)
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
  figure_number = 3,
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
  
  # Determine page dimensions based on layout
  if (layout == "6x2") {
    page_width <- "17in"
    page_height <- "37in"
  } else if (layout == "5x2") {
    page_width <- "17in"
    page_height <- "26in"
  } else if (layout == "4x2") {
    page_width <- "17in"
    page_height <- "22in"
  } else {
    page_width <- "16in"
    page_height <- "12in"
  }
  
  # Document preamble
  tex_lines <- c(
    "\\documentclass[11pt]{article}",
    "",
    "% Packages",
    sprintf("\\usepackage[margin=0.5in, paperwidth=%s, paperheight=%s]{geometry}", page_width, page_height),
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
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (A): Individual-Level Sensitivity}}", figure_number),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.49\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_b"]),
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (B): Group-Level Aggregation}}", figure_number),
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
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (C): Condition Replication}}", figure_number),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_d1"]),
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (D1): Rank Stability}}", figure_number),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files["panel_d2"]),
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (D2): Classification Stability}}", figure_number),
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
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (%s)}}", figure_number, LETTERS[1]),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[2]),
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (%s)}}", figure_number, LETTERS[2]),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.32\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[3]),
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (%s)}}", figure_number, LETTERS[3]),
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
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (%s)}}", figure_number, LETTERS[4]),
      "\\end{minipage}%",
      "\\hfill%",
      "\\begin{minipage}[t]{0.49\\textwidth}",
      "  \\centering",
      sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[5]),
      sprintf("  \\captionof*{figure}{\\textbf{Figure %d (%s)}}", figure_number, LETTERS[5]),
      "\\end{minipage}",
      ""
    )
  } else if (layout == "4x2") {
    # 4-row, 2-column layout for 8-panel comprehensive figure
    # Row 1: Panel A (Individual ECDF) + Panel B (School ECDF)
    # Row 2: Panel C (Condition MAD) + Panel D (Rank Agreement)
    # Row 3: Panel E (Decile Stability) + Panel F (Prior Quartile)
    # Row 4: Panel G (Cross-Dataset) + Panel H (Multi-Level Aggregation)
    
    panel_labels <- c(
      panel_a = sprintf("Figure %d (A): Individual-Level Sensitivity", figure_number),
      panel_b = sprintf("Figure %d (B): School-Level Aggregation", figure_number),
      panel_c = sprintf("Figure %d (C): Condition-Level Replication", figure_number),
      panel_d = sprintf("Figure %d (D): Rank Stability", figure_number),
      panel_e = sprintf("Figure %d (E): Classification Stability", figure_number),
      panel_f = sprintf("Figure %d (F): Achievement Equity", figure_number),
      panel_g = sprintf("Figure %d (G): Cross-Dataset Generalizability", figure_number),
      panel_h = sprintf("Figure %d (H): Multi-Level Aggregation Hierarchy", figure_number)
    )
    
    # Build 4 rows of 2 panels each
    panel_names <- names(plot_files)
    row_pairs <- list(
      c(panel_names[1], panel_names[2]),
      c(panel_names[3], panel_names[4]),
      c(panel_names[5], if (length(panel_names) >= 6) panel_names[6] else NULL),
      c(if (length(panel_names) >= 7) panel_names[7] else NULL, 
        if (length(panel_names) >= 8) panel_names[8] else NULL)
    )
    
    for (row_idx in seq_along(row_pairs)) {
      pair <- row_pairs[[row_idx]]
      pair <- pair[!sapply(pair, is.null)]
      
      if (length(pair) == 0) next
      
      tex_lines <- c(tex_lines,
        sprintf("%% Row %d", row_idx),
        "\\noindent%"
      )
      
      if (length(pair) == 2) {
        label_left <- if (pair[1] %in% names(panel_labels)) panel_labels[pair[1]] else pair[1]
        label_right <- if (pair[2] %in% names(panel_labels)) panel_labels[pair[2]] else pair[2]
        
        tex_lines <- c(tex_lines,
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[1]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label_left),
          "\\end{minipage}%",
          "\\hfill%",
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[2]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label_right),
          "\\end{minipage}",
          "",
          "\\vspace{0.3cm}",
          ""
        )
      } else {
        # Single panel in a row
        label <- if (pair[1] %in% names(panel_labels)) panel_labels[pair[1]] else pair[1]
        
        tex_lines <- c(tex_lines,
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[1]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label),
          "\\end{minipage}",
          "",
          "\\vspace{0.3cm}",
          ""
        )
      }
    }
    
  } else if (layout == "5x2") {
    # 5-row, 2-column layout for 10-panel comprehensive figure
    # Row 1: Panel A + Panel B
    # Row 2: Panel C + Panel D
    # Row assignments are data-driven, with Panel E and Panel D2
    # co-located when both are available.
    
    panel_labels <- c(
      panel_a  = sprintf("Figure %d (A): Individual-Level Sensitivity", figure_number),
      panel_b  = sprintf("Figure %d (B): School-Level Aggregation", figure_number),
      panel_b2 = sprintf("Figure %d (B2): District-Level Aggregation", figure_number),
      panel_c  = sprintf("Figure %d (C): Condition-Level Replication", figure_number),
      panel_d  = sprintf("Figure %d (D): Rank Stability", figure_number),
      panel_e  = sprintf("Figure %d (E): Classification Stability", figure_number),
      panel_d2 = sprintf("Figure %d (D2): Group Classification Stability", figure_number),
      panel_f  = sprintf("Figure %d (F): Achievement Equity", figure_number),
      panel_g  = sprintf("Figure %d (G): Cross-Dataset Generalizability", figure_number),
      panel_h  = sprintf("Figure %d (H): Multi-Level Aggregation Hierarchy", figure_number),
      panel_k  = sprintf("Figure %d (K): Group-Level Rank Stability", figure_number),
      panel_i1 = sprintf("Figure %d (I1): SGPc Sensitivity Across Sample Sizes", figure_number),
      panel_i2 = sprintf("Figure %d (I2): Variance Decomposition of MAD", figure_number),
      panel_j  = sprintf("Figure %d (J): Condition N vs MAD", figure_number)
    )
    
    # Build 5 rows of 2 panels each
    panel_names <- names(plot_files)
    row_pairs <- list(
      c(panel_names[1], panel_names[2]),
      c(panel_names[3], panel_names[4]),
      c(if (length(panel_names) >= 5) panel_names[5] else NULL,
        if (length(panel_names) >= 6) panel_names[6] else NULL),
      c(if (length(panel_names) >= 7) panel_names[7] else NULL,
        if (length(panel_names) >= 8) panel_names[8] else NULL),
      c(if (length(panel_names) >= 9) panel_names[9] else NULL,
        if (length(panel_names) >= 10) panel_names[10] else NULL)
    )
    
    # Force Panel I1 and I2 onto the same row if both are present
    if (all(c("panel_i1", "panel_i2") %in% panel_names)) {
      row_has_i1 <- which(vapply(row_pairs, function(x) "panel_i1" %in% x, logical(1)))
      row_has_i2 <- which(vapply(row_pairs, function(x) "panel_i2" %in% x, logical(1)))
      if (length(row_has_i1) == 1 && length(row_has_i2) == 1 && row_has_i1 != row_has_i2) {
        pair_i1 <- row_pairs[[row_has_i1]]
        pair_i2 <- row_pairs[[row_has_i2]]
        partner_i1 <- setdiff(pair_i1, "panel_i1")
        partner_i2 <- setdiff(pair_i2, "panel_i2")
        row_pairs[[row_has_i1]] <- c("panel_i1", "panel_i2")
        row_pairs[[row_has_i2]] <- c(
          if (length(partner_i1) == 0) NULL else partner_i1[1],
          if (length(partner_i2) == 0) NULL else partner_i2[1]
        )
      }
    }

    # If both Panel E and Panel D2 are present, force them onto the same row.
    # This improves readability for the two tall classification plots.
    if (all(c("panel_e", "panel_d2") %in% panel_names)) {
      row_has_e <- which(vapply(row_pairs, function(x) "panel_e" %in% x, logical(1)))
      row_has_d2 <- which(vapply(row_pairs, function(x) "panel_d2" %in% x, logical(1)))

      if (length(row_has_e) == 1 && length(row_has_d2) == 1 && row_has_e != row_has_d2) {
        pair_e <- row_pairs[[row_has_e]]
        pair_d2 <- row_pairs[[row_has_d2]]
        partner_e <- setdiff(pair_e, "panel_e")
        partner_d2 <- setdiff(pair_d2, "panel_d2")

        row_pairs[[row_has_e]] <- c("panel_e", "panel_d2")
        row_pairs[[row_has_d2]] <- c(
          if (length(partner_e) == 0) NULL else partner_e[1],
          if (length(partner_d2) == 0) NULL else partner_d2[1]
        )
      }
    }
    
    for (row_idx in seq_along(row_pairs)) {
      pair <- row_pairs[[row_idx]]
      pair <- pair[!sapply(pair, is.null)]
      
      if (length(pair) == 0) next
      
      tex_lines <- c(tex_lines,
        sprintf("%% Row %d", row_idx),
        "\\noindent%"
      )
      
      if (length(pair) == 2) {
        label_left <- if (pair[1] %in% names(panel_labels)) panel_labels[pair[1]] else pair[1]
        label_right <- if (pair[2] %in% names(panel_labels)) panel_labels[pair[2]] else pair[2]
        
        tex_lines <- c(tex_lines,
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[1]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label_left),
          "\\end{minipage}%",
          "\\hfill%",
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[2]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label_right),
          "\\end{minipage}",
          "",
          "\\vspace{0.3cm}",
          ""
        )
      } else {
        # Single panel in a row
        label <- if (pair[1] %in% names(panel_labels)) panel_labels[pair[1]] else pair[1]
        
        tex_lines <- c(tex_lines,
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[1]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label),
          "\\end{minipage}",
          "",
          "\\vspace{0.3cm}",
          ""
        )
      }
    }
    
  } else if (layout == "6x2") {
    # 6-row, 2-column layout for 12-panel comprehensive figure
    # Row 1: Panel A (Individual ECDF) + Panel B (School ECDF)
    # Row 2: Panel B2 (District ECDF) + Panel H (Multi-level Aggregation)
    # Row 3: Panel C (Condition MAD) + Panel D (Rank Agreement)
    # Row 4: Panel E + Panel D2 when both are available
    # Row 5: Panel G (Cross-Dataset) + Panel K (Group-Level Rank Stability)
    # Row 6: Panel I1 (Sensitivity Ribbon) + Panel I2 (Variance Decomposition)
    # Row 7: Panel J (Condition N vs MAD) -- if I1/I2 split pushes J to its own row
    
    panel_labels <- c(
      panel_a  = sprintf("Figure %d (A): Individual-Level Sensitivity", figure_number),
      panel_b  = sprintf("Figure %d (B): School-Level Aggregation", figure_number),
      panel_b2 = sprintf("Figure %d (B2): District-Level Aggregation", figure_number),
      panel_c  = sprintf("Figure %d (C): Condition-Level Replication", figure_number),
      panel_d  = sprintf("Figure %d (D): Rank Stability (Individual)", figure_number),
      panel_e  = sprintf("Figure %d (E): Classification Stability", figure_number),
      panel_d2 = sprintf("Figure %d (D2): Group Classification Stability", figure_number),
      panel_f  = sprintf("Figure %d (F): Achievement Equity", figure_number),
      panel_g  = sprintf("Figure %d (G): Cross-Dataset Generalizability", figure_number),
      panel_h  = sprintf("Figure %d (H): Multi-Level Aggregation Hierarchy", figure_number),
      panel_k  = sprintf("Figure %d (K): Group-Level Rank Stability", figure_number),
      panel_i1 = sprintf("Figure %d (I1): SGPc Sensitivity Across Sample Sizes", figure_number),
      panel_i2 = sprintf("Figure %d (I2): Variance Decomposition of MAD", figure_number),
      panel_j  = sprintf("Figure %d (J): Condition N vs MAD", figure_number)
    )
    
    # Define explicit row pairings per the 6x2 layout
    pn <- names(plot_files)
    row_pairs <- list(
      c("panel_a",  "panel_b"),
      c("panel_b2", "panel_h"),
      c("panel_c",  "panel_d"),
      c("panel_e",  "panel_f"),
      c("panel_g",  "panel_k"),
      c("panel_i1", "panel_i2"),
      c("panel_j")
    )

    # If both Panel E and Panel D2 are present, pair them on the same row.
    if ("panel_d2" %in% pn) {
      row_pairs[[4]] <- c("panel_e", "panel_d2")
    }
    
    for (row_idx in seq_along(row_pairs)) {
      pair <- row_pairs[[row_idx]]
      # Only include panels that actually exist in plot_files
      pair <- pair[pair %in% pn]
      
      if (length(pair) == 0) next
      
      tex_lines <- c(tex_lines,
        sprintf("%% Row %d", row_idx),
        "\\noindent%"
      )
      
      if (length(pair) == 2) {
        label_left <- if (pair[1] %in% names(panel_labels)) panel_labels[pair[1]] else pair[1]
        label_right <- if (pair[2] %in% names(panel_labels)) panel_labels[pair[2]] else pair[2]
        
        tex_lines <- c(tex_lines,
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[1]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label_left),
          "\\end{minipage}%",
          "\\hfill%",
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[2]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label_right),
          "\\end{minipage}",
          "",
          "\\vspace{0.3cm}",
          ""
        )
      } else {
        # Single panel in a row
        label <- if (pair[1] %in% names(panel_labels)) panel_labels[pair[1]] else pair[1]
        
        tex_lines <- c(tex_lines,
          "\\begin{minipage}[t]{0.49\\textwidth}",
          "  \\centering",
          sprintf("  \\includegraphics[width=\\textwidth]{%s}", plot_files[pair[1]]),
          sprintf("  \\captionof*{figure}{\\textbf{%s}}", label),
          "\\end{minipage}",
          "",
          "\\vspace{0.3cm}",
          ""
        )
      }
    }
    
  } else {
    stop("Unsupported layout: ", layout, ". Use '2x3', '3x2', '4x2', '5x2', or '6x2'")
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
