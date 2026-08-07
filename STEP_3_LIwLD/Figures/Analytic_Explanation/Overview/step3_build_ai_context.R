###############################################################################
###
### step3_build_ai_context.R - Build AI context artifacts for PSTricks
###
### Artifacts:
###   1) AI_CONTEXT_OVERVIEW.md   (human-readable context map)
###   2) AI_CONTEXT_REPOMIX.*     (packed source context for AI agents)
###
### Usage:
###   Rscript step3_build_ai_context.R
###   Rscript step3_build_ai_context.R --style xml
###   Rscript step3_build_ai_context.R --include-archive-v1 --max-chars 1500000
###
###############################################################################

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || is.na(x[1])) y else x
}

pstricks_dir <- tryCatch(
  {
    normalizePath(dirname(sys.frame(1)$ofile), winslash = "/", mustWork = TRUE)
  },
  error = function(e) {
    normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  }
)

old_wd <- setwd(pstricks_dir)
on.exit(setwd(old_wd), add = TRUE)

args <- commandArgs(trailingOnly = TRUE)
style <- "plain"
include_archive_v1 <- FALSE
max_chars <- 1000000L
figure_theme_title <- "Longitudinal Inference Without Longitudinal Data"

i <- 1L
while (i <= length(args)) {
  arg <- args[[i]]

  if (arg == "--style" && i < length(args)) {
    style <- tolower(args[[i + 1L]])
    i <- i + 1L
  } else if (grepl("^--style=", arg)) {
    style <- tolower(sub("^--style=", "", arg))
  } else if (arg == "--include-archive-v1") {
    include_archive_v1 <- TRUE
  } else if (arg == "--max-chars" && i < length(args)) {
    max_chars <- suppressWarnings(as.integer(args[[i + 1L]]))
    i <- i + 1L
  } else if (grepl("^--max-chars=", arg)) {
    max_chars <- suppressWarnings(as.integer(sub("^--max-chars=", "", arg)))
  } else {
    stop("Unknown argument: ", arg)
  }

  i <- i + 1L
}

if (!style %in% c("plain", "xml")) {
  stop("Invalid --style value: ", style, ". Use 'plain' or 'xml'.")
}

if (is.na(max_chars) || max_chars < 10000L) {
  stop("--max-chars must be >= 10000")
}

overview_path <- file.path(pstricks_dir, "AI_CONTEXT_OVERVIEW.md")
repomix_ext <- if (style == "xml") "xml" else "txt"
repomix_path <- file.path(
  pstricks_dir,
  paste0("AI_CONTEXT_REPOMIX.", repomix_ext)
)

manifest_json <- normalizePath(
  file.path(
    pstricks_dir,
    "../../../../STEP_1_Family_Selection/results/dataset_all/analysis_manifest.json"
  ),
  winslash = "/",
  mustWork = FALSE
)

build_script <- file.path(pstricks_dir, "step3_build_pstricks.R")
main_tex <- file.path(pstricks_dir, "step3_infographic_main.tex")

source_files <- c(
  "README.md",
  "step3_build_pstricks.R",
  "step3_export_data.R",
  "step3_build_ai_context.R",
  "step3_infographic_main.tex",
  "step3_header_band.tex",
  "step3_styles.tex",
  "step3_panel_A_graphic.tex",
  "step3_panel_B1_graphic.tex",
  "step3_panel_B2_graphic.tex",
  "step3_panel_C_graphic.tex",
  "step3_panel_A_text.tex",
  "step3_panel_B1B2_text.tex",
  "step3_panel_C_text.tex",
  "repomix.config.json",
  "data/summary_metrics.tex",
  "data/axis_limits.tex",
  "data/panel_B2_cdf_tamp.dat"
)

if (include_archive_v1) {
  source_files <- c(source_files, "V1_030126/README.md")
}

existing_files <- source_files[file.exists(file.path(
  pstricks_dir,
  source_files
))]
missing_files <- setdiff(source_files, existing_files)

extract_panel_suffixes <- function(line) {
  if (is.na(line) || !nzchar(line)) {
    return(character())
  }
  c_match <- regmatches(line, regexpr("c\\([^\\)]*\\)", line))
  if (length(c_match) == 0 || !nzchar(c_match)) {
    return(character())
  }
  quoted <- regmatches(c_match, gregexpr("\"[^\"]+\"", c_match))[[1]]
  gsub("\"", "", quoted)
}

build_lines <- readLines(build_script, warn = FALSE, encoding = "UTF-8")
graphic_line <- build_lines[grepl("^graphic_panels\\s*<-", build_lines)][1] %||%
  ""
text_line <- build_lines[grepl("^text_panels\\s*<-", build_lines)][1] %||% ""
graphic_suffixes <- extract_panel_suffixes(graphic_line)
text_suffixes <- extract_panel_suffixes(text_line)

main_lines <- readLines(main_tex, warn = FALSE, encoding = "UTF-8")
uses_header_band <- any(grepl("step3_header_band\\.pdf", main_lines))
uses_b1b2_text <- any(grepl("step3_panel_B1B2_text\\.pdf", main_lines))

canonical <- list(
  available = FALSE,
  n_conditions = NA_integer_,
  n_datasets = NA_integer_,
  t_pct = NA_real_,
  frank_pct = NA_real_,
  cross = NULL
)

if (
  file.exists(manifest_json) && requireNamespace("jsonlite", quietly = TRUE)
) {
  manifest <- jsonlite::fromJSON(manifest_json)

  canonical$available <- TRUE
  canonical$n_conditions <- manifest$metadata$n_conditions %||% NA_integer_
  canonical$n_datasets <- manifest$metadata$n_datasets %||% NA_integer_

  fam <- manifest$family_selection_summary
  t_row <- fam[fam$family == "t", , drop = FALSE]
  f_row <- fam[fam$family == "frank", , drop = FALSE]
  canonical$t_pct <- if (nrow(t_row) > 0) {
    as.numeric(t_row$pct_best[1])
  } else {
    NA_real_
  }
  canonical$frank_pct <- if (nrow(f_row) > 0) {
    as.numeric(f_row$pct_best[1])
  } else {
    NA_real_
  }

  cross_entries <- manifest$parameter_recommendations$cross_stratified
  canonical$cross <- do.call(
    rbind,
    lapply(cross_entries, function(x) {
      data.frame(
        content_area = as.character(x$content_area %||% NA_character_),
        year_span = as.integer(x$year_span %||% NA_integer_),
        recommended_family = as.character(
          x$recommended_family %||% NA_character_
        ),
        rho = as.numeric(x$rho$median %||% NA_real_),
        df = as.numeric(x$df$median %||% NA_real_),
        stringsAsFactors = FALSE
      )
    })
  )
}

format_cross_table <- function(cross_df) {
  if (is.null(cross_df) || nrow(cross_df) == 0) {
    return(c(
      "| Content area | 1-year | 2-year | 3-year | 4-year |",
      "|---|---|---|---|---|",
      "| unavailable | - | - | - | - |"
    ))
  }

  spans <- sort(unique(cross_df$year_span))
  preferred_area_order <- c("MATHEMATICS", "READING", "WRITING", "ELA")
  areas <- unique(cross_df$content_area)
  areas <- c(
    intersect(preferred_area_order, areas),
    setdiff(sort(areas), preferred_area_order)
  )

  header <- c(
    "| Content area |",
    paste(sprintf("%d-year", spans), collapse = " | "),
    "|"
  )
  sep <- c("|---|", paste(rep("---", length(spans)), collapse = "|"), "|")
  lines <- c(paste0(header, collapse = ""), paste0(sep, collapse = ""))

  for (area in areas) {
    cells <- c()
    for (span in spans) {
      row <- cross_df[
        cross_df$content_area == area & cross_df$year_span == span,
        ,
        drop = FALSE
      ]
      if (nrow(row) == 0) {
        cells <- c(cells, "-")
      } else {
        cells <- c(cells, sprintf("(%.2f, %.2f)", row$rho[1], row$df[1]))
      }
    }
    lines <- c(
      lines,
      sprintf("| %s | %s |", area, paste(cells, collapse = " | "))
    )
  }

  lines
}

cross_table_lines <- format_cross_table(canonical$cross)

fmt_pct <- function(x) ifelse(is.na(x), "NA", sprintf("%.1f%%", x))
fmt_int <- function(x) ifelse(is.na(x), "NA", format(x, big.mark = ","))

overview_lines <- c(
  "# AI Context Overview: STEP 3 PSTricks",
  "",
  "This file is auto-generated by `step3_build_ai_context.R` to support AI-agent onboarding and REPOMIX distillation.",
  "",
  "## Scope",
  "",
  sprintf("- Figure theme/title: `%s`", figure_theme_title),
  "- Directory: `STEP_3_LIwLD/Figures/Analytic_Explanation/PSTricks`",
  "- Story model: infer subgroup growth regime from unlinked marginals using canonical copula kernel",
  "- Active visual grammar: top graphics `A/B1/B2/C`, bottom text `A/B1B2/C`",
  "",
  "## Build Topology (Source of Truth)",
  "",
  sprintf(
    "- `step3_build_pstricks.R` graphic suffixes: `%s`",
    paste(graphic_suffixes, collapse = ", ")
  ),
  sprintf(
    "- `step3_build_pstricks.R` text suffixes: `%s`",
    paste(text_suffixes, collapse = ", ")
  ),
  sprintf(
    "- Main assembler uses `step3_header_band.pdf`: `%s`",
    ifelse(uses_header_band, "yes", "no")
  ),
  sprintf(
    "- Main assembler uses `step3_panel_B1B2_text.pdf`: `%s`",
    ifelse(uses_b1b2_text, "yes", "no")
  ),
  "",
  "## Panel Map",
  "",
  "| Concept | Graphic artifact | Text artifact |",
  "|---|---|---|",
  "| A | `step3_panel_A_graphic.tex` | `step3_panel_A_text.tex` |",
  "| B1 | `step3_panel_B1_graphic.tex` | `step3_panel_B1B2_text.tex` (shared) |",
  "| B2 | `step3_panel_B2_graphic.tex` | `step3_panel_B1B2_text.tex` (shared) |",
  "| C | `step3_panel_C_graphic.tex` | `step3_panel_C_text.tex` |",
  "",
  "## Data Artifacts Used by Panels",
  "",
  "- `data/panel_A_density_U.dat`, `data/panel_A_density_V.dat`",
  "- `data/panel_B1_heatmap_cells.tex`, `data/panel_B1_optimum.tex`",
  "- `data/panel_B2_cdf_obs.dat`, `data/panel_B2_cdf_uniform.dat`, `data/panel_B2_cdf_inferred.dat`, `data/panel_B2_cdf_tamp.dat`",
  "- `data/panel_C_density_uniform.dat`, `data/panel_C_density_true.dat`, `data/panel_C_density_inferred.dat`",
  "- `data/summary_metrics.tex`, `data/axis_limits.tex`",
  "",
  "## Canonical Copula Provenance (STEP 1)",
  "",
  sprintf(
    "Canonical baseline selection is based on %s longitudinal conditions across %s datasets.",
    fmt_int(canonical$n_conditions),
    fmt_int(canonical$n_datasets)
  ),
  sprintf(
    "Family selection rates: `t` = %s, `frank` = %s (best AIC share).",
    fmt_pct(canonical$t_pct),
    fmt_pct(canonical$frank_pct)
  ),
  "",
  "Cross-stratified canonical `t` parameters by content area x year span (cell = `(rho, df)` medians):",
  ""
)

overview_lines <- c(overview_lines, cross_table_lines, "")

overview_lines <- c(
  overview_lines,
  "## AI Context Packaging",
  "",
  "- Primary artifact: `AI_CONTEXT_REPOMIX.txt` (`--style plain`, best default for broad agent compatibility).",
  "- Optional structured artifact: `AI_CONTEXT_REPOMIX.xml` (`--style xml`).",
  "- Preferred include/ignore behavior is encoded in `repomix.config.json`.",
  "",
  "## Regeneration",
  "",
  "```bash",
  "cd PSTricks/",
  "Rscript step3_build_ai_context.R",
  "Rscript step3_build_ai_context.R --style xml",
  "```",
  ""
)

if (length(missing_files) > 0) {
  overview_lines <- c(
    overview_lines,
    "## Missing Files During Build",
    "",
    paste0("- `", missing_files, "`"),
    ""
  )
}

writeLines(overview_lines, overview_path, useBytes = TRUE)

build_plain_fallback <- function(rel_files, max_len) {
  out <- c(
    "# AI_CONTEXT_REPOMIX (Fallback Plain Pack)",
    "",
    "Generated by `step3_build_ai_context.R` because `repomix` was unavailable or failed.",
    "",
    sprintf("Root: %s", pstricks_dir),
    ""
  )

  bytes_used <- sum(nchar(out, type = "bytes")) + length(out)
  truncated <- FALSE

  for (rel in rel_files) {
    abs <- file.path(pstricks_dir, rel)
    if (!file.exists(abs)) {
      next
    }
    lines <- readLines(abs, warn = FALSE, encoding = "UTF-8")
    block <- c(
      sprintf("===== BEGIN FILE: %s =====", rel),
      lines,
      sprintf("===== END FILE: %s =====", rel),
      ""
    )
    block_bytes <- sum(nchar(block, type = "bytes")) + length(block)
    if ((bytes_used + block_bytes) > max_len) {
      truncated <- TRUE
      break
    }
    out <- c(out, block)
    bytes_used <- bytes_used + block_bytes
  }

  if (truncated) {
    out <- c(
      out,
      sprintf(
        "[TRUNCATED] Bundle reached --max-chars limit (%s bytes).",
        format(max_len, big.mark = ",")
      )
    )
  }

  out
}

xml_cdata_safe <- function(x) {
  gsub("]]>", "]]]]><![CDATA[>", x, fixed = TRUE)
}

build_xml_fallback <- function(rel_files, max_len) {
  body <- c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<repomix_fallback>",
    sprintf("  <root>%s</root>", pstricks_dir),
    "  <files>"
  )

  bytes_used <- sum(nchar(body, type = "bytes")) + length(body)
  truncated <- FALSE

  for (rel in rel_files) {
    abs <- file.path(pstricks_dir, rel)
    if (!file.exists(abs)) {
      next
    }

    txt <- paste(
      readLines(abs, warn = FALSE, encoding = "UTF-8"),
      collapse = "\n"
    )
    txt <- xml_cdata_safe(txt)

    block <- c(
      sprintf("    <file path=\"%s\"><![CDATA[", rel),
      txt,
      "]]></file>"
    )

    block_bytes <- sum(nchar(block, type = "bytes")) + length(block)
    if ((bytes_used + block_bytes) > max_len) {
      truncated <- TRUE
      break
    }

    body <- c(body, block)
    bytes_used <- bytes_used + block_bytes
  }

  body <- c(body, "  </files>")
  if (truncated) {
    body <- c(
      body,
      sprintf(
        "  <note>TRUNCATED at %s bytes (--max-chars).</note>",
        format(max_len, big.mark = ",")
      )
    )
  }
  body <- c(body, "</repomix_fallback>")
  body
}

repomix_bin <- Sys.which("repomix")
used_repomix <- FALSE

if (nzchar(repomix_bin)) {
  repomix_args <- c("--style", style, "--output", basename(repomix_path))
  status <- suppressWarnings(system2(
    repomix_bin,
    repomix_args,
    stdout = FALSE,
    stderr = FALSE
  ))
  used_repomix <- is.integer(status) &&
    status == 0L &&
    file.exists(repomix_path)
}

if (!used_repomix) {
  fallback_lines <- if (style == "xml") {
    build_xml_fallback(existing_files, max_chars)
  } else {
    build_plain_fallback(existing_files, max_chars)
  }
  writeLines(fallback_lines, repomix_path, useBytes = TRUE)
}

cat("\n=== STEP 3 AI Context Build ===\n")
cat("PSTricks dir          :", pstricks_dir, "\n")
cat("Overview artifact     :", overview_path, "\n")
cat("Packed context artifact:", repomix_path, "\n")
cat(
  "Pack method           :",
  if (used_repomix) "repomix" else "fallback",
  "\n"
)
cat("Style                 :", style, "\n")
cat("Include archive V1    :", include_archive_v1, "\n")
cat("Max chars             :", format(max_chars, big.mark = ","), "\n\n")
