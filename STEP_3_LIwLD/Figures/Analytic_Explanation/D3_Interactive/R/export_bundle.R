###############################################################################
###
### export_bundle.R --- Write the LIwLD scenario bundle to disk.
###
### One entrypoint, write_scenario_bundle(), produces the six files described
### in schema/manifest.schema.json:
###    manifest.json
###    panel1_u_curves.json
###    panel2_copula_contours.json
###    panel3_w1_surface.bin       (Float32, row-major [m_n, k_n])
###    panel5_v_observed.json
###    panel5_v_induced.bin        (Uint8 quantized [m_n, k_n, v_n], decode = byte/255)
###
### Author: Damian Betebenner, Claude (collaborator)
### Created: 2026-05-04
###
###############################################################################

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Package 'jsonlite' is required. install.packages('jsonlite').")
}
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Package 'digest' is required. install.packages('digest').")
}

LIWLD_TOOL_VERSION <- "0.1.3" # 0.1.3: derive n_population from longitudinal_pairs.csv

#' Write Float32, row-major.
#' @keywords internal
.write_float32_bin <- function(x, path) {
  vec <- as.numeric(x)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(vec, con, size = 4L, endian = "little")
}

#' Quantize a tensor of CDF values in [0, 1] to Uint8 and write row-major.
#' Decoding is a single division: `F = byte / 255`.
#' @keywords internal
.write_uint8_cdf_bin <- function(arr, path) {
  vals <- pmin(pmax(arr, 0), 1)
  bytes <- as.integer(round(vals * 255))
  bytes <- pmin(pmax(bytes, 0L), 255L)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(as.raw(bytes), con)
}

#' Compute SHA-256 of a file's bytes (hex string).
#' @keywords internal
.sha256_file <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

#' JSON helpers: encode numeric vectors with controlled precision so file size
#' stays predictable and diffs stay readable.
#' @keywords internal
.round_vec <- function(x, digits = 6L) round(x, digits)

#' Write one panel's bundle of files and the manifest.
#'
#' @param dest_dir Path to the target scenario folder. Created if missing.
#' @param scenario A list with fields:
#'   - id (chr): scenario_id (snake_case)
#'   - label (chr)
#'   - data_source (chr): "SYNTHETIC" or "PHASE_A_REAL_DATA"
#'   - data_classification (chr): "PUBLIC" / "INTERNAL" / "RESTRICTED"
#'   - cohort (list)
#'   - n_subgroup, n_population (int)
#'   - copula (list with family + params)
#' @param panel_1 list(u, pdf_pop, pdf_sub, cdf_pop, cdf_sub) all length-equal vectors.
#' @param panel_2 list of {level, paths} contour bundles.
#' @param panel_3 numeric matrix [m_n, k_n] W_1 surface.
#' @param panel_5_observed list(v, pdf_pop, pdf_sub, cdf_pop, cdf_sub) length v_n.
#' @param panel_5_induced numeric array [m_n, k_n, v_n] of induced CDFs.
#' @param regime_grid_spec list with m_min, m_max, m_n, k_min, k_max, k_n, k_scale.
#' @param v_grid numeric vector of v-axis points.
#' @param argmin list(m, k, m_idx, k_idx, w1).
#' @param uniform_ref list(m, k, m_idx, k_idx, w1).
write_scenario_bundle <- function(
  dest_dir,
  scenario,
  panel_1,
  panel_2,
  panel_3,
  panel_5_observed,
  panel_5_induced,
  regime_grid_spec,
  v_grid,
  argmin,
  uniform_ref
) {
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
  }

  # ---- File names (kept stable for the loader) ------------------------------
  files <- list(
    panel_1_u = "panel1_u_curves.json",
    panel_2_copula = "panel2_copula_contours.json",
    panel_3_grid = "panel3_w1_surface.bin",
    panel_5_observed_v = "panel5_v_observed.json",
    panel_5_induced_v = "panel5_v_induced.bin"
  )

  # ---- Panel 1: U curves ----------------------------------------------------
  p1 <- list(
    u = .round_vec(panel_1$u, 6),
    pdf_pop = .round_vec(panel_1$pdf_pop, 6),
    pdf_sub = .round_vec(panel_1$pdf_sub, 6),
    cdf_pop = .round_vec(panel_1$cdf_pop, 6),
    cdf_sub = .round_vec(panel_1$cdf_sub, 6)
  )
  writeLines(
    jsonlite::toJSON(p1, auto_unbox = TRUE, digits = 7),
    file.path(dest_dir, files$panel_1_u)
  )

  # ---- Panel 2: copula contours --------------------------------------------
  # Expects panel_2 to be a list of list(level = num, paths = list(matrix(u,v) ...))
  p2_serialized <- lapply(panel_2, function(layer) {
    list(
      level = layer$level,
      paths = lapply(layer$paths, function(pts) {
        # round to 4 dp on (u, v) — sub-pixel for any reasonable canvas size
        cbind(round(pts[, 1], 4), round(pts[, 2], 4))
      })
    )
  })
  writeLines(
    jsonlite::toJSON(p2_serialized, auto_unbox = TRUE, digits = 5),
    file.path(dest_dir, files$panel_2_copula)
  )

  # ---- Panel 3: W_1 surface ------------------------------------------------
  # Row-major write: byte 0..3 is panel_3[1,1], byte 4..7 is panel_3[1,2], …
  # i.e. scan all k for m=0, then all k for m=1, …  Matches the [m_n, k_n]
  # row-major convention promised by the schema.  R is column-major, so we
  # transpose first so that as.vector() yields the row-major bytes we want.
  .write_float32_bin(
    as.vector(t(panel_3)),
    file.path(dest_dir, files$panel_3_grid)
  )

  # ---- Panel 5 observed ----------------------------------------------------
  p5o <- list(
    v = .round_vec(panel_5_observed$v, 6),
    pdf_pop = .round_vec(panel_5_observed$pdf_pop, 6),
    pdf_sub = .round_vec(panel_5_observed$pdf_sub, 6),
    cdf_pop = .round_vec(panel_5_observed$cdf_pop, 6),
    cdf_sub = .round_vec(panel_5_observed$cdf_sub, 6)
  )
  writeLines(
    jsonlite::toJSON(p5o, auto_unbox = TRUE, digits = 7),
    file.path(dest_dir, files$panel_5_observed_v)
  )

  # ---- Panel 5 induced (quantized) -----------------------------------------
  # Wire layout: byte at offset O = m_idx * k_n * v_n + k_idx * v_n + v_idx
  # ("[m, k, v] row-major").  Decode on the client: F_G = byte / 255.
  m_n <- regime_grid_spec$m_n
  k_n <- regime_grid_spec$k_n
  v_n <- length(v_grid)

  bytes <- integer(m_n * k_n * v_n)
  pos <- 1L
  for (i in seq_len(m_n)) {
    for (j in seq_len(k_n)) {
      vals <- pmin(pmax(panel_5_induced[i, j, ], 0), 1)
      bytes[pos:(pos + v_n - 1L)] <- as.integer(round(vals * 255))
      pos <- pos + v_n
    }
  }
  bytes <- pmin(pmax(bytes, 0L), 255L)
  con <- file(file.path(dest_dir, files$panel_5_induced_v), open = "wb")
  writeBin(as.raw(bytes), con)
  close(con)

  # ---- Manifest ------------------------------------------------------------
  checksums <- list(
    panel_1_u = .sha256_file(file.path(dest_dir, files$panel_1_u)),
    panel_2_copula = .sha256_file(file.path(dest_dir, files$panel_2_copula)),
    panel_3_grid = .sha256_file(file.path(dest_dir, files$panel_3_grid)),
    panel_5_observed_v = .sha256_file(file.path(
      dest_dir,
      files$panel_5_observed_v
    )),
    panel_5_induced_v = .sha256_file(file.path(
      dest_dir,
      files$panel_5_induced_v
    ))
  )

  manifest <- list(
    schema_version = "1.0.0",
    scenario_id = scenario$id,
    label = scenario$label,
    data_source = scenario$data_source,
    data_classification = scenario$data_classification,
    cohort = scenario$cohort,
    n_subgroup = as.integer(scenario$n_subgroup),
    n_population = as.integer(scenario$n_population),
    copula = scenario$copula,
    regime_grid = regime_grid_spec,
    v_grid = list(
      v_min = min(v_grid),
      v_max = max(v_grid),
      v_n = as.integer(length(v_grid))
    ),
    argmin = argmin,
    uniform_ref = uniform_ref,
    files = files,
    checksums = checksums,
    build = list(
      timestamp_utc = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
      tool = "liwld_precompute.R",
      tool_version = LIWLD_TOOL_VERSION,
      r_version = paste0(R.version$major, ".", R.version$minor)
    )
  )

  manifest_path <- file.path(dest_dir, "manifest.json")
  writeLines(
    jsonlite::toJSON(manifest, pretty = TRUE, auto_unbox = TRUE, digits = 8),
    manifest_path
  )

  # ---- Summary report ------------------------------------------------------
  message("\nLIwLD scenario bundle written:")
  message(sprintf("  destination : %s", dest_dir))
  for (nm in names(files)) {
    fpath <- file.path(dest_dir, files[[nm]])
    sz <- file.info(fpath)$size
    message(sprintf(
      "  %-22s %8.1f KB  (sha256: %s…)",
      files[[nm]],
      sz / 1024,
      substr(checksums[[nm]], 1, 10)
    ))
  }
  manifest_sz <- file.info(manifest_path)$size
  message(sprintf("  %-22s %8.1f KB", "manifest.json", manifest_sz / 1024))

  invisible(list(manifest = manifest, manifest_path = manifest_path))
}
