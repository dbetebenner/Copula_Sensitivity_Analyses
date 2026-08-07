###############################################################################
###
### step3_build_pstricks.R - Master build script for Bi-Variate infographic
###
### Pipeline:
###   1. Export panel-ready data files to data/
###   2. Compile PSTricks graphic panels via latex -> dvips -E -> gs -> PDF
###   3. Export PNG, clean intermediates
###
### Usage (from the Bi-Variate/ directory):
###   source("step3_build_pstricks.R")
###
###############################################################################

# ---------------------------------------------------------------------------
# 0. Resolve paths
# ---------------------------------------------------------------------------

bivariate_dir <- tryCatch(
  {
    normalizePath(dirname(sys.frame(1)$ofile), winslash = "/", mustWork = TRUE)
  },
  error = function(e) {
    normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  }
)

data_dir <- file.path(bivariate_dir, "data")
output_dir <- file.path(bivariate_dir, "outputs")

if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# ---------------------------------------------------------------------------
# Build configuration — figure registry
# ---------------------------------------------------------------------------
figures <- list(
  list(
    panel = "step3_bivariate_scatter",
    release_stem = "Bivariate_Scatter_Marginals",
    version = "0.1.0"
  ),

  list(
    panel = "step3_bivariate_threepanel",
    release_stem = "Bivariate_ThreePanel_Layout",
    version = "0.1.0"
  ),

  list(
    panel = "step3_bivariate_threepanel_without_hxy",
    release_stem = "Bivariate_ThreePanel_Without_hXY",
    version = "0.1.0"
  ),

  list(
    panel = "step3_bivariate_scatter_no_title",
    release_stem = "Bivariate_Scatter_Marginals_NoTitle",
    version = "0.1.0"
  ),

  list(
    panel = "step3_bivariate_threepanel_no_title",
    release_stem = "Bivariate_ThreePanel_Layout_NoTitle",
    version = "0.1.0"
  ),

  list(
    panel = "step3_bivariate_threepanel_without_hxy_no_title",
    release_stem = "Bivariate_ThreePanel_Without_hXY_NoTitle",
    version = "0.1.0"
  )
)

cat("\n=== Bi-Variate Infographic Build ===\n")
cat("  Bi-Variate dir:", bivariate_dir, "\n")
cat("  Data dir      :", data_dir, "\n")
cat("  Output dir    :", output_dir, "\n\n")

if (Sys.which("latex") == "") {
  stop("LaTeX is required but not found on PATH.")
}


# ---------------------------------------------------------------------------
# 1. Export panel data
# ---------------------------------------------------------------------------

cat("--- Step 1: Data export ---\n")
source(file.path(bivariate_dir, "step3_export_data.R"))
cat("\n")


# ---------------------------------------------------------------------------
# 2. BoundingBox configuration
# ---------------------------------------------------------------------------

custom_bounding_boxes <- list(
  # Tight-crop bbox: c(llx, lly, urx, ury) in PostScript points
  # Initial estimates — re-measure after first build via gs -sDEVICE=bbox
  step3_bivariate_scatter = c(20, 275, 505, 795),
  step3_bivariate_threepanel = c(0, 350, 936, 795),
  step3_bivariate_threepanel_without_hxy = c(0, 350, 936, 795),
  # _no_title variants: same content minus title bar (~36pt shorter at top)
  step3_bivariate_scatter_no_title = c(20, 275, 505, 730),
  step3_bivariate_threepanel_no_title = c(0, 350, 936, 730),
  step3_bivariate_threepanel_without_hxy_no_title = c(0, 350, 936, 730)
)

apply_custom_bounding_box <- function(ps_file, bbox) {
  if (is.null(bbox)) {
    return(TRUE)
  }
  if (length(bbox) != 4 || any(!is.finite(bbox))) {
    return(FALSE)
  }

  bbox <- as.integer(round(bbox))
  if (bbox[1] >= bbox[3] || bbox[2] >= bbox[4]) {
    return(FALSE)
  }

  ps_lines <- readLines(ps_file, warn = FALSE, encoding = "UTF-8")
  bb_idx <- grep("^%%BoundingBox:", ps_lines)
  hr_idx <- grep("^%%HiResBoundingBox:", ps_lines)

  if (length(bb_idx) == 0 && length(hr_idx) == 0) {
    return(FALSE)
  }

  if (length(bb_idx) > 0) {
    ps_lines[bb_idx] <- sprintf(
      "%%%%BoundingBox: %d %d %d %d",
      bbox[1],
      bbox[2],
      bbox[3],
      bbox[4]
    )
  }

  if (length(hr_idx) > 0) {
    ps_lines[hr_idx] <- sprintf(
      "%%%%HiResBoundingBox: %.6f %.6f %.6f %.6f",
      bbox[1],
      bbox[2],
      bbox[3],
      bbox[4]
    )
  }

  writeLines(ps_lines, ps_file, useBytes = TRUE)
  TRUE
}


# ---------------------------------------------------------------------------
# 3. Compile PSTricks panels (latex -> dvips -E -> gs -> PDF)
# ---------------------------------------------------------------------------

compile_pstricks <- function(name) {
  cat(sprintf("  [PSTricks] %s ...", name))

  old_wd <- setwd(bivariate_dir)
  on.exit(setwd(old_wd), add = TRUE)

  rc <- system2(
    "latex",
    c("-interaction=nonstopmode", name),
    stdout = FALSE,
    stderr = FALSE
  )
  if (rc != 0) {
    cat(" FAIL (latex)\n")
    return(FALSE)
  }

  ps_file <- paste0(name, ".ps")
  pdf_file <- paste0(name, ".pdf")

  entry <- custom_bounding_boxes[[name]]
  tight_crop <- !is.null(entry) && length(entry) == 4

  ## --- dvips ----------------------------------------------------------------
  dvips_args <- c("-E", paste0(name, ".dvi"), "-o", ps_file)
  system2("dvips", dvips_args, stdout = FALSE, stderr = FALSE)
  if (!file.exists(ps_file)) {
    cat(" FAIL (dvips)\n")
    return(FALSE)
  }

  ## --- BoundingBox override -------------------------------------------------
  if (tight_crop) {
    ps_lines_diag <- readLines(ps_file, warn = FALSE, n = 30)
    auto_bb <- grep("^%%BoundingBox:", ps_lines_diag, value = TRUE)
    if (length(auto_bb) > 0) {
      cat(sprintf(
        "\n    dvips-bbox: %s",
        sub("%%BoundingBox: ", "", auto_bb[1])
      ))
    }

    ## Measure ACTUAL content extent via gs -sDEVICE=bbox
    gs_bbox <- system2(
      "gs",
      c(
        "-q",
        "-dBATCH",
        "-dNOPAUSE",
        "-dALLOWPSTRANSPARENCY",
        "-sDEVICE=bbox",
        ps_file
      ),
      stdout = TRUE,
      stderr = TRUE
    )
    measured <- grep("^%%BoundingBox:", gs_bbox, value = TRUE)
    if (length(measured) > 0) {
      cat(sprintf(
        "\n    gs-content: %s",
        sub("%%BoundingBox: ", "", measured[1])
      ))
    }

    ok_bbox <- apply_custom_bounding_box(ps_file, entry)
    if (!ok_bbox) {
      cat(" FAIL (BoundingBox)\n")
      return(FALSE)
    }
    cat(sprintf(
      "\n    override:   %d %d %d %d",
      entry[1],
      entry[2],
      entry[3],
      entry[4]
    ))
  }

  ## --- gs -> PDF -----------------------------------------------------------
  gs_args <- c(
    "-q",
    "-dALLOWPSTRANSPARENCY",
    "-dBATCH",
    "-dNOPAUSE",
    "-dEPSCrop",
    "-sDEVICE=pdfwrite",
    "-dCompatibilityLevel=1.4",
    paste0("-sOutputFile=", pdf_file),
    ps_file
  )
  system2("gs", gs_args, stdout = FALSE, stderr = FALSE)

  if (!file.exists(pdf_file)) {
    cat(" FAIL (gs)\n")
    return(FALSE)
  }

  file.copy(pdf_file, file.path(output_dir, pdf_file), overwrite = TRUE)
  cat(sprintf(" OK (%s bytes)\n", format(file.size(pdf_file), big.mark = ",")))
  TRUE
}


# ---------------------------------------------------------------------------
# 4. Build all figures
# ---------------------------------------------------------------------------

cat("--- Step 2: Compile figures ---\n")

ok <- TRUE
for (fig in figures) {
  ok <- compile_pstricks(fig$panel) && ok
}

if (!ok) {
  warning("One or more figures failed to compile.")
}


# ---------------------------------------------------------------------------
# 5. Export PNG and release copies
# ---------------------------------------------------------------------------

cat("\n--- Step 3: Export outputs ---\n")

for (fig in figures) {
  stem <- fig$panel
  final_pdf <- file.path(output_dir, paste0(stem, ".pdf"))
  if (!file.exists(final_pdf)) {
    next
  }

  release_pdf <- file.path(
    output_dir,
    sprintf("%s_v%s.pdf", fig$release_stem, fig$version)
  )
  file.copy(final_pdf, release_pdf, overwrite = TRUE)
  cat("  Release PDF:", release_pdf, "\n")

  png_out <- file.path(output_dir, paste0(stem, ".png"))
  system2(
    "gs",
    c(
      "-q",
      "-dBATCH",
      "-dNOPAUSE",
      "-sDEVICE=png16m",
      "-r300",
      paste0("-sOutputFile=", png_out),
      final_pdf
    ),
    stdout = FALSE,
    stderr = FALSE
  )
  if (file.exists(png_out)) {
    cat("  PNG:", png_out, "\n")
  }

  svg_out <- file.path(output_dir, paste0(stem, ".svg"))
  if (Sys.which("pdf2svg") != "") {
    system2("pdf2svg", c(final_pdf, svg_out), stdout = FALSE, stderr = FALSE)
    if (file.exists(svg_out)) cat("  SVG:", svg_out, "\n")
  } else if (Sys.which("mutool") != "") {
    system2(
      "mutool",
      c("convert", "-o", svg_out, final_pdf),
      stdout = FALSE,
      stderr = FALSE
    )
    if (file.exists(svg_out)) cat("  SVG:", svg_out, "\n")
  } else {
    cat("  SVG: skipped (install pdf2svg or mutool)\n")
  }
}


# ---------------------------------------------------------------------------
# 6. Cleanup
# ---------------------------------------------------------------------------

cat("\n--- Cleanup ---\n")
all_stems <- vapply(figures, `[[`, "", "panel")
cleanup_suffixes <- c(
  ".aux",
  ".log",
  ".dvi",
  ".fls",
  ".fdb_latexmk",
  ".out",
  ".synctex.gz"
)
old_wd <- setwd(bivariate_dir)
for (stem in all_stems) {
  for (ext in cleanup_suffixes) {
    f <- paste0(stem, ext)
    if (file.exists(f)) file.remove(f)
  }
}
setwd(old_wd)

cat("\n=== Build complete ===\n")
for (fig in figures) {
  cat(sprintf(
    "  %s: %s\n",
    fig$release_stem,
    file.path(output_dir, paste0(fig$panel, ".pdf"))
  ))
}
cat("\n")
