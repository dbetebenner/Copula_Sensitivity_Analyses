###############################################################################
###
### step3_build_pstricks.R - Master build script for Margins infographic
###
### Pipeline:
###   1. Export panel-ready data files to data/
###   2. Compile PSTricks graphic panel via latex -> dvips -E -> gs -> PDF
###   3. Compile text panel and header band via xelatex -> PDF
###   4. Compile main assembler via xelatex
###   5. Export PNG/SVG, clean intermediates
###
### Usage (from the Margins/ directory):
###   source("step3_build_pstricks.R")
###
###############################################################################

# ---------------------------------------------------------------------------
# 0. Resolve paths
# ---------------------------------------------------------------------------

margins_dir <- tryCatch({
  normalizePath(dirname(sys.frame(1)$ofile), winslash = "/", mustWork = TRUE)
}, error = function(e) {
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
})

data_dir   <- file.path(margins_dir, "data")
output_dir <- file.path(margins_dir, "outputs")

if (!dir.exists(data_dir))   dir.create(data_dir, recursive = TRUE)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ---------------------------------------------------------------------------
# Build configuration — infographic registry
# ---------------------------------------------------------------------------
# Each entry: assembler stem, human-readable release name, semver version.
# To add a new variant, append a list() entry here.
infographics <- list(
  list(assembler    = "step3_infographic_main_1",
       release_stem = "Margins_Marginal_Transformation",
       version      = "0.3.0"),

  list(assembler    = "step3_infographic_main_2",
       release_stem = "Margins_Copula_Dependence",
       version      = "0.1.0")
)

infographic_variants <- vapply(infographics, `[[`, "", "assembler")

cat("\n=== Margins Infographic Build (Scatter Design) ===\n")
cat("  Margins dir  :", margins_dir, "\n")
cat("  Data dir     :", data_dir, "\n")
cat("  Output dir   :", output_dir, "\n\n")

if (Sys.which("xelatex") == "") {
  stop("XeLaTeX is required but not found on PATH. ",
       "Install TeX Live XeLaTeX and retry.")
}


# ---------------------------------------------------------------------------
# 1. Extract longitudinal pairs (only if intermediate CSV is missing)
# ---------------------------------------------------------------------------

pairs_csv <- file.path(margins_dir, "data", "longitudinal_pairs.csv")
if (!file.exists(pairs_csv)) {
  cat("--- Step 0: Extracting longitudinal pairs (first run) ---\n")
  source(file.path(margins_dir, "step3_extract_pairs.R"))
  cat("\n")
} else {
  cat("--- Step 0: Using existing", basename(pairs_csv),
      "(", format(file.size(pairs_csv), big.mark = ","), "bytes )\n")
}


# ---------------------------------------------------------------------------
# 1. Export panel data (transform to PSTricks format)
# ---------------------------------------------------------------------------

cat("--- Step 1: Data export ---\n")
source(file.path(margins_dir, "step3_export_data.R"))
cat("\n")


# ---------------------------------------------------------------------------
# 2. Compile PSTricks graphic panels (latex -> dvips -E -> gs -> PDF)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# BoundingBox / paper-size table for PSTricks panels
# ---------------------------------------------------------------------------
#
# PSTricks content is PostScript specials that dvips -E cannot detect for its
# automatic bounding-box computation.  Two strategies are used:
#
#  (A) Full-page panels  — the panel fills its declared TeX geometry paper.
#      Set the entry to c(width_in, height_in) matching the \geometry directive
#      in the panel's .tex file.  dvips will be called with -T and the page
#      size; no bbox guessing is needed.
#
#  (B) Tight-crop panels — the panel is smaller than the declared paper and
#      you want a cropped EPS.  Set the entry to c(llx, lly, urx, ury) in
#      PostScript points (1 pt = 1/72 in).  dvips -E is used and the auto-
#      detected BoundingBox is replaced with these values before gs crops.
#      To find the right values: run the build once, inspect the .ps file in
#      the Margins/ directory, note the visible content extent, and adjust.
#
# Either format is distinguished by length: length-2 → full-page (strategy A),
# length-4 → tight-crop (strategy B).  Set to NULL to use dvips -E with
# whatever bounding box it auto-detects (rarely correct for PSTricks).
# ---------------------------------------------------------------------------
custom_bounding_boxes <- list(
  # Tight-crop bbox for scatter panels: c(llx, lly, urx, ury) in PostScript pts
  # dvips -E auto-detects a tiny bbox because PSTricks specials are invisible
  # to DVI bbox tracking.  These values were measured via gs -sDEVICE=bbox.
  # Re-measure after layout changes: the build prints the auto-detected bbox
  # AND the gs-measured content bbox for tuning.
  step3_panel_scatter_graphic_1 = c(0, 250, 486, 784),
  step3_panel_scatter_graphic_2 = c(0, 250, 516, 784)
)

apply_custom_bounding_box <- function(ps_file, bbox) {
  if (is.null(bbox)) return(TRUE)
  if (length(bbox) != 4 || any(!is.finite(bbox))) return(FALSE)

  bbox <- as.integer(round(bbox))
  if (bbox[1] >= bbox[3] || bbox[2] >= bbox[4]) return(FALSE)

  ps_lines <- readLines(ps_file, warn = FALSE, encoding = "UTF-8")
  bb_idx <- grep("^%%BoundingBox:", ps_lines)
  hr_idx <- grep("^%%HiResBoundingBox:", ps_lines)

  if (length(bb_idx) == 0 && length(hr_idx) == 0) return(FALSE)

  if (length(bb_idx) > 0) {
    ps_lines[bb_idx] <- sprintf(
      "%%%%BoundingBox: %d %d %d %d",
      bbox[1], bbox[2], bbox[3], bbox[4]
    )
  }

  if (length(hr_idx) > 0) {
    ps_lines[hr_idx] <- sprintf(
      "%%%%HiResBoundingBox: %.6f %.6f %.6f %.6f",
      bbox[1], bbox[2], bbox[3], bbox[4]
    )
  }

  writeLines(ps_lines, ps_file, useBytes = TRUE)
  TRUE
}

compile_pstricks <- function(name) {
  cat(sprintf("  [PSTricks] %s ...", name))

  old_wd <- setwd(margins_dir)
  on.exit(setwd(old_wd), add = TRUE)

  rc <- system2("latex", c("-interaction=nonstopmode", name),
                stdout = FALSE, stderr = FALSE)
  if (rc != 0) { cat(" FAIL (latex)\n"); return(FALSE) }

  ps_file  <- paste0(name, ".ps")
  pdf_file <- paste0(name, ".pdf")

  entry <- custom_bounding_boxes[[name]]
  full_page <- !is.null(entry) && length(entry) == 2   # c(w_in, h_in)
  tight_crop <- !is.null(entry) && length(entry) == 4  # c(llx, lly, urx, ury)

  ## --- dvips ----------------------------------------------------------------
  if (full_page) {
    ## Strategy A: panel fills its TeX geometry page — use explicit paper size
    dvips_args <- c("-T", paste0(entry[1], "in,", entry[2], "in"),
                    "-o", ps_file, paste0(name, ".dvi"))
    cat(sprintf(" [page %.1fx%.1fin]", entry[1], entry[2]))
  } else {
    ## Strategy B / fallback: tight-crop EPS
    dvips_args <- c("-E", paste0(name, ".dvi"), "-o", ps_file)
  }
  system2("dvips", dvips_args, stdout = FALSE, stderr = FALSE)
  if (!file.exists(ps_file)) { cat(" FAIL (dvips)\n"); return(FALSE) }

  ## --- BoundingBox override (tight-crop only) --------------------------------
  if (tight_crop) {
    ## Report dvips auto-detected bbox
    ps_lines_diag <- readLines(ps_file, warn = FALSE, n = 30)
    auto_bb <- grep("^%%BoundingBox:", ps_lines_diag, value = TRUE)
    if (length(auto_bb) > 0) cat(sprintf("\n    dvips-bbox: %s", sub("%%BoundingBox: ", "", auto_bb[1])))

    ## Measure ACTUAL content extent via gs -sDEVICE=bbox (gold standard)
    gs_bbox <- system2("gs", c("-q", "-dBATCH", "-dNOPAUSE",
                               "-dALLOWPSTRANSPARENCY",
                               "-sDEVICE=bbox", ps_file),
                       stdout = TRUE, stderr = TRUE)
    measured <- grep("^%%BoundingBox:", gs_bbox, value = TRUE)
    if (length(measured) > 0) cat(sprintf("\n    gs-content: %s", sub("%%BoundingBox: ", "", measured[1])))

    ## Apply override
    ok_bbox <- apply_custom_bounding_box(ps_file, entry)
    if (!ok_bbox) { cat(" FAIL (BoundingBox)\n"); return(FALSE) }
    cat(sprintf("\n    override:   %d %d %d %d", entry[1], entry[2], entry[3], entry[4]))
  }

  ## --- gs -> PDF ------------------------------------------------------------
  if (full_page) {
    ## Match the declared paper size exactly; no EPS crop
    w_pts <- as.integer(round(entry[1] * 72))
    h_pts <- as.integer(round(entry[2] * 72))
    gs_args <- c("-q", "-dALLOWPSTRANSPARENCY", "-dBATCH", "-dNOPAUSE",
                 "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.4",
                 "-dAutoRotatePages=/None",
                 sprintf("-dDEVICEWIDTHPOINTS=%d",  w_pts),
                 sprintf("-dDEVICEHEIGHTPOINTS=%d", h_pts),
                 "-dFIXEDMEDIA",
                 paste0("-sOutputFile=", pdf_file), ps_file)
  } else {
    ## Crop to EPS BoundingBox (auto-detected or overridden above)
    gs_args <- c("-q", "-dALLOWPSTRANSPARENCY", "-dBATCH", "-dNOPAUSE",
                 "-dEPSCrop", "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.4",
                 paste0("-sOutputFile=", pdf_file), ps_file)
  }
  system2("gs", gs_args, stdout = FALSE, stderr = FALSE)

  if (!file.exists(pdf_file)) { cat(" FAIL (gs)\n"); return(FALSE) }

  file.copy(pdf_file, file.path(output_dir, pdf_file), overwrite = TRUE)
  cat(sprintf(" OK (%s bytes)\n", format(file.size(pdf_file), big.mark = ",")))
  TRUE
}


# ---------------------------------------------------------------------------
# 3. Compile text panels (xelatex)
# ---------------------------------------------------------------------------

compile_xelatex <- function(name) {
  cat(sprintf("  [xelatex] %s ...", name))

  old_wd <- setwd(margins_dir)
  on.exit(setwd(old_wd), add = TRUE)

  system2("xelatex", c("-interaction=nonstopmode", name),
          stdout = FALSE, stderr = FALSE)
  pdf_file <- paste0(name, ".pdf")

  if (!file.exists(pdf_file)) { cat(" FAIL\n"); return(FALSE) }

  file.copy(pdf_file, file.path(output_dir, pdf_file), overwrite = TRUE)
  cat(sprintf(" OK (%s bytes)\n", format(file.size(pdf_file), big.mark = ",")))
  TRUE
}


# ---------------------------------------------------------------------------
# 4. Build all panels
# ---------------------------------------------------------------------------

cat("--- Step 2: Compile panels ---\n")

graphic_panels <- c(
  "step3_panel_scatter_graphic_1",
  "step3_panel_scatter_graphic_2"
)

text_panels <- c(
  "step3_panel_text_1",
  "step3_panel_text_2"
)

ok <- TRUE
for (p in graphic_panels) ok <- compile_pstricks(p) && ok
for (p in text_panels)    ok <- compile_xelatex(p)  && ok

if (!ok) warning("One or more panels failed to compile.")


# ---------------------------------------------------------------------------
# 5. Assemble final infographic
# ---------------------------------------------------------------------------

cat("\n--- Step 3: Assemble infographics ---\n")
compile_xelatex("step3_header_band_1")
compile_xelatex("step3_header_band_2")

export_outputs <- function(stem, release_pdf = NULL) {
  final_pdf <- file.path(output_dir, paste0(stem, ".pdf"))
  if (!file.exists(final_pdf)) return(invisible(NULL))

  if (!is.null(release_pdf)) {
    copied <- file.copy(final_pdf, release_pdf, overwrite = TRUE)
    if (copied && file.exists(release_pdf)) cat("  Release PDF:", release_pdf, "\n")
  }

  png_out <- file.path(output_dir, paste0(stem, ".png"))
  system2("gs", c("-q", "-dBATCH", "-dNOPAUSE", "-sDEVICE=png16m",
                  "-r300", paste0("-sOutputFile=", png_out), final_pdf),
          stdout = FALSE, stderr = FALSE)
  if (file.exists(png_out)) cat("  PNG:", png_out, "\n")

  svg_out <- file.path(output_dir, paste0(stem, ".svg"))
  if (Sys.which("pdf2svg") != "") {
    system2("pdf2svg", c(final_pdf, svg_out), stdout = FALSE, stderr = FALSE)
    if (file.exists(svg_out)) cat("  SVG:", svg_out, "\n")
  } else if (Sys.which("mutool") != "") {
    system2("mutool", c("convert", "-o", svg_out, final_pdf),
            stdout = FALSE, stderr = FALSE)
    if (file.exists(svg_out)) cat("  SVG:", svg_out, "\n")
  } else if (Sys.which("inkscape") != "") {
    system2("inkscape", c("--export-type=svg",
                          paste0("--export-filename=", svg_out),
                          final_pdf),
            stdout = FALSE, stderr = FALSE)
    if (file.exists(svg_out)) cat("  SVG:", svg_out, "\n")
  } else {
    cat("  SVG: skipped (install pdf2svg, mutool, or inkscape)\n")
  }
}

for (ig in infographics) {
  compile_xelatex(ig$assembler)
  release_pdf <- file.path(output_dir,
    sprintf("%s_v%s.pdf", ig$release_stem, ig$version))
  export_outputs(ig$assembler, release_pdf = release_pdf)
}


# ---------------------------------------------------------------------------
# 6. Cleanup
# ---------------------------------------------------------------------------

cat("\n--- Cleanup ---\n")
all_stems <- c(graphic_panels, text_panels,
               "step3_header_band_1", "step3_header_band_2",
               infographic_variants)
cleanup_suffixes <- c(".aux", ".log", ".dvi", ".fls", ".fdb_latexmk", ".out", ".synctex.gz")
old_wd <- setwd(margins_dir)
for (stem in all_stems) {
  for (ext in cleanup_suffixes) {
    f <- paste0(stem, ext)
    if (file.exists(f)) file.remove(f)
  }
}
setwd(old_wd)

cat("\n=== Build complete ===\n")
for (ig in infographics) {
  tag <- sub("step3_infographic_main_", "", ig$assembler)
  release_name <- sprintf("%s_v%s", ig$release_stem, ig$version)
  cat(sprintf("  [_%s]  PDF: %s\n", tag, file.path(output_dir, paste0(ig$assembler, ".pdf"))))
  cat(sprintf("         PNG: %s\n", file.path(output_dir, paste0(ig$assembler, ".png"))))
  cat(sprintf("     Release: %s\n", file.path(output_dir, paste0(release_name, ".pdf"))))
}
cat("\n")
