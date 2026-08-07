###############################################################################
###
### step3_build_pstricks.R - Master build script for STEP 3 PSTricks infographic
###
### Mirrors the compile-chain pattern from:
###   Betebenner_Braun/Paper_1/Figures/Copulas/copula_R_script.R
###
### Pipeline:
###   1. Export panel-ready data files to PSTricks/data/
###   2. Compile graphic panels via latex -> dvips -E -> gs -> PDF
###   3. Compile text panels via xelatex -> PDF
###   4. Compile main assembler via xelatex
###   5. Export PNG/SVG, clean intermediates
###
### Usage (from the PSTricks/ directory):
###   source("step3_build_pstricks.R")
###
###############################################################################

# ---------------------------------------------------------------------------
# 0. Resolve paths
# ---------------------------------------------------------------------------

pstricks_dir <- tryCatch(
  {
    normalizePath(dirname(sys.frame(1)$ofile), winslash = "/", mustWork = TRUE)
  },
  error = function(e) {
    normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  }
)

data_dir <- file.path(pstricks_dir, "data")
output_dir <- file.path(pstricks_dir, "outputs")

if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# ---------------------------------------------------------------------------
# Build configuration
# ---------------------------------------------------------------------------
# Update this version string when issuing a new release artifact.
infographic_release_version <- "2.2.0"
infographic_release_stem <- "Longitudinal_Inference_Without_Longitudinal_Data"
infographic_release_pdf <- file.path(
  output_dir,
  sprintf("%s_v%s.pdf", infographic_release_stem, infographic_release_version)
)

cat("\n=== STEP 3 PSTricks Infographic Build ===\n")
cat("  PSTricks dir :", pstricks_dir, "\n")
cat("  Data dir     :", data_dir, "\n")
cat("  Output dir   :", output_dir, "\n\n")

if (Sys.which("xelatex") == "") {
  stop(
    "XeLaTeX is required but not found on PATH. ",
    "Install TeX Live XeLaTeX and retry."
  )
}

# ---------------------------------------------------------------------------
# Resolve TEXMFDIST for dvisvgm (Homebrew dvisvgm cannot find texmf.cnf on
# its own — it needs TEXMFCNF/TEXMFDIST exported in the environment so the
# PostScript headers tex.pro / texps.pro / special.pro / color.pro resolve.)
# Mirrors the pattern in ../Margins/step3_build_pstricks.R.
# ---------------------------------------------------------------------------
texmf_dist <- Sys.getenv("TEXMFDIST", unset = "")
if (!nzchar(texmf_dist) && nzchar(Sys.which("kpsewhich"))) {
  kpse_out <- system2("kpsewhich", "texmf.cnf", stdout = TRUE, stderr = FALSE)
  if (length(kpse_out) > 0 && nzchar(kpse_out[1])) {
    texmf_dist <- normalizePath(
      file.path(dirname(kpse_out[1]), ".."),
      mustWork = FALSE
    )
  }
}
dvisvgm_env_cmd <- if (nzchar(texmf_dist)) {
  sprintf(
    "export TEXMFCNF=%s/web2c && export TEXMFDIST=%s && ",
    texmf_dist,
    texmf_dist
  )
} else {
  ""
}


# ---------------------------------------------------------------------------
# 1. Export panel data (delegates to step3_export_data.R)
# ---------------------------------------------------------------------------

cat("--- Step 1: Data export ---\n")
source(file.path(pstricks_dir, "step3_export_data.R"))
cat("\n")


# ---------------------------------------------------------------------------
# 2. Compile graphic panels (PSTricks: latex -> dvips -E -> gs -> PDF)
# ---------------------------------------------------------------------------
#stop("I'm stopping here")
# Optional manual BoundingBox override (llx, lly, urx, ury) per panel.
# Set an entry to NULL (or remove it) to keep dvips/Ghostscript auto-cropping.
custom_bounding_boxes <- list(
  step3_panel_A_graphic = c(0, 522, 295, 802),
  step3_panel_B1_graphic = c(10, 505, 305, 780),
  step3_panel_B2_graphic = c(21, 510, 315, 780),
  step3_panel_C_graphic = c(0, 577, 285, 801)
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

compile_pstricks <- function(name) {
  cat(sprintf("  [PSTricks] %s ...", name))

  old_wd <- setwd(pstricks_dir)
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

  system2("dvips", c("-E", name, "-o"), stdout = FALSE, stderr = FALSE)

  dvi_file <- paste0(name, ".dvi")
  ps_file <- paste0(name, ".ps")
  pdf_file <- paste0(name, ".pdf")

  if (!file.exists(ps_file)) {
    cat(" FAIL (dvips)\n")
    return(FALSE)
  }

  bbox <- custom_bounding_boxes[[name]]
  if (!is.null(bbox)) {
    ok_bbox <- apply_custom_bounding_box(ps_file, bbox)
    if (!ok_bbox) {
      cat(" FAIL (BoundingBox)\n")
      return(FALSE)
    }
    cat(sprintf(" bbox[%d %d %d %d]", bbox[1], bbox[2], bbox[3], bbox[4]))
  }

  system2(
    "gs",
    c(
      "-q",
      "-dALLOWPSTRANSPARENCY",
      "-dBATCH",
      "-dNOPAUSE",
      "-dEPSCrop",
      "-sDEVICE=pdfwrite",
      "-dCompatibilityLevel=1.4",
      paste0("-sOutputFile=", pdf_file),
      ps_file
    ),
    stdout = FALSE,
    stderr = FALSE
  )

  if (!file.exists(pdf_file)) {
    cat(" FAIL (gs)\n")
    return(FALSE)
  }

  file.copy(pdf_file, file.path(output_dir, pdf_file), overwrite = TRUE)

  ## --- dvisvgm --------------------------------------------------------------
  ## Run on the DVI (not the PS). DVI carries TeX-native font/positioning
  ## metadata; PS-via-tex.pro would require kpathsea-aware paths that
  ## Homebrew dvisvgm cannot resolve without TEXMFCNF/TEXMFDIST. We delete
  ## any prior SVG first so a stale file cannot masquerade as success.
  if (Sys.which("dvisvgm") != "" && file.exists(dvi_file)) {
    svg_local <- paste0(name, ".svg")
    svg_out <- file.path(output_dir, svg_local)
    if (file.exists(svg_local)) {
      file.remove(svg_local)
    }
    if (file.exists(svg_out)) {
      file.remove(svg_out)
    }

    svg_cmd <- sprintf(
      "%sdvisvgm --font-format=woff2 --bbox=min --output=%s %s",
      dvisvgm_env_cmd,
      shQuote(svg_local),
      shQuote(dvi_file)
    )
    rc_svg <- system(svg_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)

    if (rc_svg == 0 && file.exists(svg_local)) {
      file.copy(svg_local, svg_out, overwrite = TRUE)
      cat(sprintf(
        " + SVG (%s bytes)",
        format(file.size(svg_local), big.mark = ",")
      ))
    } else {
      cat(sprintf(" + SVG FAIL (rc=%d)", rc_svg))
    }
  }

  cat(sprintf(" OK (%s bytes)\n", format(file.size(pdf_file), big.mark = ",")))
  TRUE
}


# ---------------------------------------------------------------------------
# 3. Compile text panels (xelatex)
# ---------------------------------------------------------------------------

compile_xelatex <- function(name) {
  cat(sprintf("  [xelatex] %s ...", name))

  old_wd <- setwd(pstricks_dir)
  on.exit(setwd(old_wd), add = TRUE)

  system2(
    "xelatex",
    c("-interaction=nonstopmode", name),
    stdout = FALSE,
    stderr = FALSE
  )
  pdf_file <- paste0(name, ".pdf")

  if (!file.exists(pdf_file)) {
    cat(" FAIL\n")
    return(FALSE)
  }

  file.copy(pdf_file, file.path(output_dir, pdf_file), overwrite = TRUE)
  cat(sprintf(" OK (%s bytes)\n", format(file.size(pdf_file), big.mark = ",")))
  TRUE
}


# ---------------------------------------------------------------------------
# 4. Build all panels
# ---------------------------------------------------------------------------

cat("--- Step 2: Compile panels ---\n")

graphic_panels <- paste0("step3_panel_", c("A", "B1", "B2", "C"), "_graphic")
text_panels <- paste0("step3_panel_", c("A", "B1B2", "C"), "_text")

ok <- TRUE
for (p in graphic_panels) {
  ok <- compile_pstricks(p) && ok
}
for (p in text_panels) {
  ok <- compile_xelatex(p) && ok
}

if (!ok) {
  warning("One or more panels failed to compile.")
}


# ---------------------------------------------------------------------------
# 5. Assemble final infographic
# ---------------------------------------------------------------------------

cat("\n--- Step 3: Assemble infographic ---\n")
compile_xelatex("step3_header_band")
compile_xelatex("step3_infographic_main")

cat("\n--- Step 4: Compile standalone panel PDFs ---\n")
compile_xelatex("step3_infographic_panel_a")
compile_xelatex("step3_infographic_panel_b1b2")
compile_xelatex("step3_infographic_panel_c")

final_pdf <- file.path(output_dir, "step3_infographic_main.pdf")
if (file.exists(final_pdf)) {
  copied <- file.copy(final_pdf, infographic_release_pdf, overwrite = TRUE)
  if (copied && file.exists(infographic_release_pdf)) {
    cat("  Release PDF:", infographic_release_pdf, "\n")
  } else {
    warning(
      "Could not create release-named PDF copy: ",
      infographic_release_pdf
    )
  }

  png_out <- file.path(output_dir, "step3_infographic_main.png")
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

  svg_out <- file.path(output_dir, "step3_infographic_main.svg")
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
  } else if (Sys.which("inkscape") != "") {
    system2(
      "inkscape",
      c("--export-type=svg", paste0("--export-filename=", svg_out), final_pdf),
      stdout = FALSE,
      stderr = FALSE
    )
    if (file.exists(svg_out)) cat("  SVG:", svg_out, "\n")
  } else {
    cat("  SVG: skipped (install pdf2svg, mutool, or inkscape)\n")
  }
}

# Per-panel SVGs are emitted inline by compile_pstricks() (DVI-based, with
# TEXMFCNF/TEXMFDIST exported so dvisvgm can resolve tex.pro et al.). The
# previous "Step 5b" loop ran dvisvgm on the .ps and silently failed because
# Homebrew dvisvgm could not find texmf.cnf — yet the loop reported success
# whenever any prior SVG file lingered on disk. That trap is gone now.

# ---------------------------------------------------------------------------
# 6. Cleanup
# ---------------------------------------------------------------------------

cat("\n--- Cleanup ---\n")
all_stems <- c(
  graphic_panels,
  text_panels,
  "step3_header_band",
  "step3_infographic_main",
  "step3_infographic_panel_a",
  "step3_infographic_panel_b1b2",
  "step3_infographic_panel_c"
)
# Also remove .ps and .svg intermediates from the source dir; the
# canonical SVG copies live under outputs/.
cleanup_suffixes <- c(
  ".aux",
  ".log",
  ".dvi",
  ".fls",
  ".fdb_latexmk",
  ".out",
  ".pdf",
  ".ps",
  ".svg"
)
old_wd <- setwd(pstricks_dir)
for (stem in all_stems) {
  for (ext in cleanup_suffixes) {
    f <- paste0(stem, ext)
    if (file.exists(f)) file.remove(f)
  }
}
setwd(old_wd)

cat("\n=== Build complete ===\n")
cat("Final PDF :", file.path(output_dir, "step3_infographic_main.pdf"), "\n")
cat("Final PNG :", file.path(output_dir, "step3_infographic_main.png"), "\n\n")
