############################################################################
###
### Manifest Export for STEP 3: Growth Regime Inference
###
### Generates AI-consumable JSON and human-readable Markdown manifests,
### following the pattern established by STEP 1 and STEP 2.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

require(jsonlite)


#' Export STEP 3 Manifest (JSON + Markdown)
#'
#' Writes summary results from STEP 3 growth regime inference to both
#' machine-readable JSON and human-readable Markdown formats.
#'
#' @param results List. Combined results from STEP 3 estimation. Expected
#'   structure:
#'   \itemize{
#'     \item subgroup_estimates: List of per-subgroup estimate_regime() results
#'     \item bootstrap_results: Optional bootstrap results
#'     \item copula_uncertainty_results: Optional copula uncertainty results
#'     \item config: Configuration used for the run
#'     \item metadata: List with timestamp, git_hash, seed, etc.
#'   }
#' @param output_dir Character. Directory for manifest files. Default "results".
#' @param prefix Character. Filename prefix. Default "step3".
#' @param verbose Logical. Default TRUE.
#'
#' @return Invisible list with paths to JSON and MD files.
#'
#' @export
export_step3_manifest <- function(
  results,
  output_dir = "results",
  prefix = "step3",
  verbose = TRUE
) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Build manifest structure
  manifest <- list(
    metadata = list(
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      step = "STEP_3_LIwLD",
      description = "Growth regime inference from cross-sectional data",
      n_subgroups = length(results$subgroup_estimates),
      config = results$config
    )
  )

  # Subgroup summaries
  subgroup_summaries <- lapply(
    names(results$subgroup_estimates),
    function(sg_id) {
      est <- results$subgroup_estimates[[sg_id]]
      if (is.null(est)) {
        return(NULL)
      }

      list(
        subgroup_id = sg_id,
        regime_family = est$regime$family,
        regime_param_hat = est$regime_param_hat,
        m_hat = est$m_hat,
        kappa_hat = est$kappa_hat,
        median_sgpc = round(est$regime$median * 100, 2),
        mean_sgpc = round(est$regime$mean * 100, 2),
        dispersion_sd = if (!is.null(est$regime$sd)) {
          round(est$regime$sd * 100, 2)
        } else {
          NA
        },
        dispersion_iqr = if (!is.null(est$regime$iqr)) {
          round(est$regime$iqr * 100, 2)
        } else {
          NA
        },
        entropy = if (!is.null(est$regime$entropy)) {
          round(est$regime$entropy, 4)
        } else {
          NA
        },
        concentration = if (!is.null(est$regime$concentration)) {
          round(est$regime$concentration, 2)
        } else {
          NA
        },
        distance_min = round(est$distance_min, 6),
        distances = lapply(est$all_distances, function(x) round(x, 6)),
        convergence = est$convergence
      )
    }
  )
  subgroup_summaries <- Filter(Negate(is.null), subgroup_summaries)
  manifest$subgroup_estimates <- subgroup_summaries

  # Bootstrap summary (if available)
  if (!is.null(results$bootstrap_results)) {
    boot <- results$bootstrap_results
    manifest$uncertainty <- list(
      sampling = list(
        n_boot = boot$n_boot,
        n_converged = boot$n_converged,
        ci_median_sgpc = as.numeric(boot$ci_median_sgpc),
        se_median_sgpc = round(boot$se_median_sgpc, 2)
      )
    )
  }

  # Copula uncertainty (if available)
  if (!is.null(results$copula_uncertainty_results)) {
    cop_unc <- results$copula_uncertainty_results
    manifest$uncertainty$copula <- list(
      var_copula = round(cop_unc$var_copula, 4),
      n_draws = length(cop_unc$median_sgpc_draws),
      median_sgpc_range = round(
        range(cop_unc$median_sgpc_draws, na.rm = TRUE),
        2
      )
    )
  }

  if (!is.null(results$assumption_diagnostics)) {
    manifest$assumption_diagnostics <- results$assumption_diagnostics
  }

  if (!is.null(results$sensitivity)) {
    manifest$sensitivity <- results$sensitivity
  }

  # --------------------------------------------------------------------------
  # Phase B systematic validation summary
  # Precision operating table by (n_bucket x year_span) — the primary Phase B
  # deliverable answering: "how precise is cross-sectional growth inference at
  # NAEP/TIMSS-relevant sample sizes?"
  # --------------------------------------------------------------------------
  if (!is.null(results$phase_b_systematic)) {
    manifest$phase_b_systematic <- results$phase_b_systematic
  }

  # --------------------------------------------------------------------------
  # Error source decomposition
  # Separates the two independent error sources that STEP 3 characterises:
  #   Error 1 (sampling):   precision degrades as N falls below ~5000; captured
  #                         by Phase B precision operating curves.
  #   Error 2 (inference):  bias from using canonical copula + regime family;
  #                         captured by Phase A inferred-vs-true comparison and
  #                         bootstrap variance decomposition.
  # --------------------------------------------------------------------------
  if (!is.null(results$error_sources)) {
    manifest$error_sources <- results$error_sources
  }

  # --------------------------------------------------------------------------
  # Bucket classification (K=3 / K=5)
  # Growth regime bucketing: Low (<45/40), Typical (45–55 / 40–60), High (>55/>60)
  # --------------------------------------------------------------------------
  if (!is.null(results$bucket_classification)) {
    manifest$bucket_classification <- results$bucket_classification
  }

  # Run metadata
  if (!is.null(results$metadata)) {
    manifest$run_metadata <- results$metadata
  }

  # --- Write JSON ---
  json_path <- file.path(output_dir, paste0(prefix, "_manifest.json"))
  write_json(manifest, json_path, pretty = TRUE, auto_unbox = TRUE)

  # --- Write Markdown ---
  md_path <- file.path(output_dir, paste0(prefix, "_manifest.md"))
  md_lines <- c(
    "# STEP 3: Growth Regime Inference (LIwLD) — Results Manifest",
    "",
    paste0("**Generated:** ", manifest$metadata$generated_at),
    paste0("**Subgroups analysed:** ", manifest$metadata$n_subgroups),
    "",
    "---",
    "",
    "## STEP 3 Framework",
    "",
    "STEP 3 characterises the precision and bias of **LIwLD** (Longitudinal Inference",
    "without Longitudinal Data) — cross-sectional growth regime inference using the",
    "SGPcFlow generative model. The central analytic identity is:",
    "",
    "    F_H(v) = (1/n) * sum_i H(F_0(v | u_i))",
    "",
    "where `H` is the latent growth regime (Beta distribution on [0,1]), `F_0(v|u)` is",
    "the conditional CDF from the baseline copula (fitted in STEP 1), and the estimation",
    "target is the occupancy distribution `H_S` of a subgroup `S`.",
    "",
    "### Error Source Taxonomy",
    "",
    "| Error | Source | Phase | Controlled By |",
    "|-------|--------|-------|---------------|",
    "| **Error 1a — Subsampling** | Cross-sectional sample of size N substitutes for full subgroup (paired design) | Phase B systematic (paired mode) | Increases N; degrades precision below ~5,000 students |",
    "| **Error 1b — Cohort mismatch** | Prior and current cohorts are different students (TIMSS/NAEP) | Phase B systematic (linkage_fraction = 0.0) | Linkage premium: multiplicative CI inflation vs paired; linkage_fraction sweep maps the continuous space |",
    "| **Error 2 — Inference** | Canonical copula + Beta family may not match true data-generating process | Phase A deep-dive | Robustness checks: copula sensitivity (B2), family comparison (Phase A), U-independence diagnostic |",
    "",
    "Phase A provides a full diagnostic at the observed subgroup size (N ~ 2,500–6,000).",
    "Phase B maps precision as a function of N across 200 Monte Carlo replicates per",
    "condition, directly addressing NAEP (state-level N ~ 3,000–4,000) and TIMSS",
    "(country-level N ~ 4,000+) operating conditions.",
    ""
  )

  # Phase B precision operating table (if available)
  if (!is.null(manifest$phase_b_systematic)) {
    pb <- manifest$phase_b_systematic
    md_lines <- c(
      md_lines,
      "---",
      "",
      "## Phase B: Systematic Validation Summary",
      ""
    )
    if (!is.null(pb$overview)) {
      ov <- pb$overview
      sampling_modes_str <- if (!is.null(ov$sampling_modes)) {
        paste(ov$sampling_modes, collapse = ", ")
      } else {
        "paired"
      }
      md_lines <- c(
        md_lines,
        paste0("- **Conditions tested:** ", ov$n_conditions),
        paste0("- **Subgroup-condition pairs:** ", ov$n_subgroup_conditions),
        paste0("- **Year spans:** ", paste(ov$year_spans, collapse = ", ")),
        paste0(
          "- **Content areas:** ",
          paste(ov$content_areas, collapse = ", ")
        ),
        paste0("- **N buckets:** ", paste(ov$n_buckets, collapse = ", ")),
        paste0("- **Pool types:** ", paste(ov$pool_types, collapse = ", ")),
        paste0("- **Sampling modes:** ", sampling_modes_str),
        paste0("- **Outer replicates per cell:** ", ov$outer_reps),
        paste0(
          "- **Overall convergence rate:** ",
          round(ov$overall_convergence_rate * 100, 1),
          "%"
        ),
        ""
      )
    }
    # Precision operating table by (year_span x n_bucket)
    if (!is.null(pb$precision_by_n_span)) {
      tbl <- pb$precision_by_n_span
      md_lines <- c(
        md_lines,
        "### Precision Operating Table (Median SGPc, averaged across conditions)",
        "",
        "Columns: 95% CI width | MAE | Convergence rate  —  by N bucket and year span",
        "",
        "| Year Span | N = 1,000 | N = 2,500 | N = 5,000 | N = 7,500 | N = 10,000 |",
        "|-----------|-----------|-----------|-----------|-----------|------------|"
      )
      spans <- sort(unique(sapply(tbl, `[[`, "year_span")))
      buckets_ordered <- c(1000, 2500, 5000, 7500, 10000)
      for (sp in spans) {
        cells <- sapply(buckets_ordered, function(nb) {
          row <- Filter(function(r) r$year_span == sp && r$n_bucket == nb, tbl)
          if (length(row) == 0L) {
            return("—")
          }
          r <- row[[1]]
          paste0(
            round(r$median_ci_width_95, 1),
            " / ",
            round(r$median_mae, 1),
            " / ",
            round(r$convergence_rate * 100, 0),
            "%"
          )
        })
        md_lines <- c(
          md_lines,
          paste0("| ", sp, "-yr span | ", paste(cells, collapse = " | "), " |")
        )
      }
      md_lines <- c(
        md_lines,
        "",
        "_Format: 95% CI width (SGP units) / MAE (SGP units) / convergence rate_",
        "",
        "**NAEP/TIMSS reference:** NAEP state-level N ~ 3,000–4,000 (between N=2,500",
        "and N=5,000 rows); TIMSS country-level N ~ 4,000+ (N=5,000 row is a",
        "conservative proxy). CI widths ≤ 8 SGP units meet the 'good' threshold.",
        ""
      )
    }
    # Year-span finding
    if (!is.null(pb$year_span_finding)) {
      md_lines <- c(
        md_lines,
        "### Year Span Finding",
        "",
        paste0(
          "- **Mean |median error| by span** — ",
          paste(
            names(pb$year_span_finding),
            ":",
            round(unlist(pb$year_span_finding), 2),
            collapse = "; "
          )
        ),
        ""
      )
    }

    # Linkage premium (sampling-mode decomposition)
    if (!is.null(pb$linkage_premium)) {
      lp <- pb$linkage_premium
      md_lines <- c(
        md_lines,
        "### Linkage Premium: Paired vs Independent Cohort Sampling",
        "",
        "Phase B decomposes Error 1 (sampling uncertainty) into two sub-components",
        "by running each replicate under two sampling designs:",
        "",
        "- **Paired** — same student indices for prior and current scores (longitudinal pairing preserved)",
        "- **Independent** — separate random draws for prior and current, mirroring the TIMSS/NAEP",
        "  cross-sectional design where Grade 4 and Grade 8 are different students tested in the same year",
        "",
        paste0(
          "The **linkage premium** is the multiplicative factor by which uncertainty increases ",
          "when moving from paired to independent sampling. Mean CI ratio: **",
          lp$mean_ci_ratio,
          "x**; Mean MAE ratio: **",
          lp$mean_mae_ratio,
          "x**."
        ),
        "",
        "| N Bucket | CI (Paired) | CI (Independent) | CI Ratio | MAE (Paired) | MAE (Independent) | MAE Ratio |",
        "|----------|-------------|------------------|----------|--------------|-------------------|-----------|"
      )
      for (row in lp$premium_by_n_bucket) {
        md_lines <- c(
          md_lines,
          paste0(
            "| ",
            formatC(row$n_bucket, format = "d", big.mark = ","),
            " | ",
            round(row$ci_width_95_paired, 1),
            " | ",
            round(row$ci_width_95_independent, 1),
            " | ",
            row$ci_ratio,
            "x",
            " | ",
            round(row$mae_paired, 1),
            " | ",
            round(row$mae_independent, 1),
            " | ",
            row$mae_ratio,
            "x |"
          )
        )
      }
      md_lines <- c(
        md_lines,
        "",
        "_CI = 95% confidence interval width (SGP units); MAE = mean absolute error (SGP units)._",
        "_Ratio > 1 indicates the precision cost of not having longitudinal pairing._",
        "",
        "**Implication for NAEP/TIMSS:** At NAEP state-level N (~3,000–4,000), the independent",
        "sampling mode is the operationally relevant scenario. Multiply paired-mode CI widths",
        "by the linkage premium ratio to obtain realistic uncertainty estimates for cross-sectional",
        "growth inference in assessment programmes without longitudinal tracking.",
        ""
      )

      # Precision by (year_span x n_bucket x sampling_mode) table if available
      if (!is.null(lp$precision_by_n_span_mode)) {
        md_lines <- c(
          md_lines,
          "#### Full Precision Table by Year Span, N, and Sampling Mode",
          "",
          "| Sampling Mode | Year Span | N | 95% CI Width | MAE | Convergence |",
          "|---------------|-----------|-------|--------------|------|-------------|"
        )
        for (row in lp$precision_by_n_span_mode) {
          md_lines <- c(
            md_lines,
            paste0(
              "| ",
              row$sampling_mode,
              " | ",
              row$year_span,
              " | ",
              formatC(row$n_bucket, format = "d", big.mark = ","),
              " | ",
              round(row$median_ci_width_95, 1),
              " | ",
              round(row$median_mae, 1),
              " | ",
              round(row$convergence_rate * 100, 0),
              "% |"
            )
          )
        }
        md_lines <- c(md_lines, "")
      }

      # Linkage fraction curve table (when partial fractions available)
      if (
        !is.null(lp$linkage_fraction_curve) &&
          length(lp$linkage_fraction_curve) > 0
      ) {
        md_lines <- c(
          md_lines,
          "#### Linkage Fraction Curve: CI Width by Overlap Strength",
          "",
          "The linkage_fraction parameter maps the continuous space between fully ",
          "independent (0.0) and fully paired (1.0) cohort designs. Intermediate values ",
          "simulate partial overlap (e.g., some schools retained across NAEP cycles).",
          "",
          "| Linkage Fraction | N | 95% CI Width (Median) | 95% CI Width (Mean) | MAE | Pools |",
          "|------------------|-------|----------------------|---------------------|------|-------|"
        )
        for (row in lp$linkage_fraction_curve) {
          md_lines <- c(
            md_lines,
            paste0(
              "| ",
              sprintf("%.0f%%", row$linkage_fraction * 100),
              " | ",
              formatC(row$n_bucket, format = "d", big.mark = ","),
              " | ",
              round(row$median_ci_width_95, 1),
              " | ",
              round(row$mean_ci_width_95, 1),
              " | ",
              round(row$median_mae, 1),
              " | ",
              row$n_pools,
              " |"
            )
          )
        }
        md_lines <- c(
          md_lines,
          "",
          "_CI width decreases monotonically as linkage_fraction increases from 0 to 1,_",
          "_quantifying the precision gain from partial or full cohort overlap._",
          ""
        )
      }
    }
  }

  # Subgroup estimates (Phase A showcase + any Phase B summaries)
  md_lines <- c(
    md_lines,
    "---",
    "",
    "## Phase A: Subgroup Estimates (Deep-Dive Condition)",
    ""
  )

  for (sg in subgroup_summaries) {
    md_lines <- c(
      md_lines,
      paste0("### ", sg$subgroup_id),
      paste0("- **Regime family:** ", sg$regime_family),
      paste0(
        "- **Parameters (m, κ):** ",
        paste(round(sg$regime_param_hat, 4), collapse = ", ")
      ),
      paste0("- **Inferred median SGPc:** ", sg$median_sgpc),
      paste0("- **Inferred mean SGPc:** ", sg$mean_sgpc),
      if (!is.na(sg$dispersion_sd)) {
        paste0("- **Dispersion (SD):** ", sg$dispersion_sd)
      } else {
        NULL
      },
      paste0("- **Wasserstein-1:** ", sg$distances$wasserstein1),
      paste0("- **CvM:** ", sg$distances$cramer_von_mises),
      ""
    )
  }

  # Uncertainty / error decomposition
  if (!is.null(results$bootstrap_results) || !is.null(manifest$error_sources)) {
    md_lines <- c(
      md_lines,
      "---",
      "",
      "## Uncertainty Quantification and Error Decomposition",
      ""
    )
    if (!is.null(results$bootstrap_results)) {
      boot <- results$bootstrap_results
      md_lines <- c(
        md_lines,
        "### Error 1 — Sampling Uncertainty (Phase A bootstrap at full N)",
        paste0(
          "- **Replicates:** ",
          boot$n_boot,
          " (converged: ",
          boot$n_converged,
          ")"
        ),
        paste0(
          "- **Median SGPc 95% CI:** [",
          round(boot$ci_median_sgpc[1], 1),
          ", ",
          round(boot$ci_median_sgpc[2], 1),
          "]"
        ),
        paste0("- **SE (median SGPc):** ", round(boot$se_median_sgpc, 2)),
        ""
      )
    }
    if (!is.null(manifest$error_sources)) {
      es <- manifest$error_sources
      md_lines <- c(
        md_lines,
        "### Error 2 — Inference Error (Phase A inferred vs. true at full N)",
        paste0("- **Inferred median SGPc:** ", es$inference$inferred_median),
        paste0("- **True median SGPc:** ", es$inference$true_median),
        paste0(
          "- **Median error (bias):** ",
          es$inference$median_error,
          " SGP units"
        ),
        paste0(
          "- **Mean error (bias):** ",
          es$inference$mean_error,
          " SGP units"
        ),
        "",
        "_Interpretation: Error 2 is the residual bias at full subgroup N, attributable_",
        "_to copula misspecification or regime family mismatch, not to small-sample noise._",
        ""
      )
      if (!is.null(es$variance_decomposition)) {
        vd <- es$variance_decomposition
        md_lines <- c(
          md_lines,
          "### Variance Decomposition (Phase A bootstrap)",
          paste0("- **Var(sampling):** ", round(vd$var_sampling, 4)),
          paste0("- **Var(copula param):** ", round(vd$var_copula, 4)),
          paste0("- **% sampling:** ", round(vd$pct_sampling, 1), "%"),
          paste0("- **% copula param:** ", round(vd$pct_copula, 1), "%"),
          ""
        )
      }
    }
  }

  # Bucket classification
  if (!is.null(manifest$bucket_classification)) {
    bc <- manifest$bucket_classification
    md_lines <- c(
      md_lines,
      "---",
      "",
      "## Bucket Classification",
      "",
      paste0(
        "- **K=3 thresholds:** Low < ",
        bc$cutpoints_k3[1],
        " | Typical ",
        bc$cutpoints_k3[1],
        "–",
        bc$cutpoints_k3[2],
        " | High > ",
        bc$cutpoints_k3[2]
      ),
      paste0(
        "- **K=5 thresholds:** Low < ",
        bc$cutpoints_k5[1],
        " | Low-Typ ",
        bc$cutpoints_k5[1],
        "–",
        bc$cutpoints_k5[2],
        " | Typical ",
        bc$cutpoints_k5[2],
        "–",
        bc$cutpoints_k5[3],
        " | High-Typ ",
        bc$cutpoints_k5[3],
        "–",
        bc$cutpoints_k5[4],
        " | High > ",
        bc$cutpoints_k5[4]
      ),
      paste0(
        "- **Mean K=3 classification consistency:** ",
        round(bc$mean_k3_consistency * 100, 1),
        "%"
      ),
      paste0(
        "- **Mean K=5 classification consistency:** ",
        round(bc$mean_k5_consistency * 100, 1),
        "%"
      ),
      ""
    )
    if (!is.null(bc$subgroups) && length(bc$subgroups) > 0) {
      md_lines <- c(
        md_lines,
        "| Subgroup | K=3 Bucket | K=3 Consistency | K=5 Bucket | K=5 Consistency |",
        "|----------|------------|-----------------|------------|-----------------|"
      )
      for (sg in bc$subgroups) {
        md_lines <- c(
          md_lines,
          paste0(
            "| ",
            sg$subgroup_id,
            " | ",
            sg$k3_assigned,
            " | ",
            round(sg$k3_consistency * 100, 1),
            "%",
            " | ",
            sg$k5_assigned,
            " | ",
            round(sg$k5_consistency * 100, 1),
            "% |"
          )
        )
      }
      md_lines <- c(md_lines, "")
    }
  }

  md_lines <- c(
    md_lines,
    "---",
    "",
    "## Output Files",
    "",
    "| File | Description |",
    "|------|-------------|",
    "| `phase_a_deep_dive.rds` | Full Phase A results object (best estimate, bootstrap, family comparison) |",
    "| `phase_a_analytic_payload.rds` | Notation-aligned figure payload for Phase A panel assembly |",
    "| `phase_a_precision_anchor.csv` | Phase A baseline N₀/SE₀/CI-width anchor for scaling narrative |",
    "| `phase_a_summary.csv` | One-row Phase A summary for reporting |",
    "| `phase_b_systematic_summary.csv` | Phase B per-subgroup condition summaries (all conditions run) |",
    "| `phase_b_precision_by_n.csv` | Phase B precision operating characteristics by N bucket (includes linkage_fraction and sampling_mode columns) |",
    "| `visualizations/panel_d2_precision_decomposition.*` | Phase B paired vs independent cohort precision decomposition (linkage premium) |",
    "| `phase_b_pool_registry.csv` | Phase B pooled-source registry with eligibility metadata |",
    "| `phase_b_replicates.RData` | Phase B replicate-level raw results (200 draws × N × conditions) |",
    "| `phase_b_copula_sensitivity.csv` | Phase B2 sensitivity to copula parameter variants |",
    "| `phase_b_independence_sensitivity.csv` | Phase B3 sensitivity to stratified-by-U regimes |",
    "| `step3_country_estimates.csv` | All-subgroup estimates with dispersion, entropy, distances |",
    "| `step3_uncertainty_decomposition.csv` | Variance decomposition: var_sampling, var_copula, var_family |",
    "| `step3_bucket_probabilities.csv` | K=3 and K=5 bucket membership probabilities |",
    "| `district_summary_grade.csv` | District-level model-health summary artifact |",
    "| `bucket_stability_summary.json` | Bucket classification consistency summary |",
    "| `output_contract_check.json` | Output contract validation report |",
    "| `exports/phase_a/*.csv` | Tidy figure-data exports (CDF, objective, density, fit, bootstrap, independence) |",
    "| `phase_a_manifest.json` | Phase A deep-dive manifest (machine-readable) |",
    "| `phase_a_manifest.md` | Phase A deep-dive manifest (human-readable) |",
    "| `step3_manifest.json` | This manifest (machine-readable) |",
    "| `step3_manifest.md` | This manifest (human-readable) |",
    "| `run_metadata.json` | Reproducibility metadata (R version, packages, git hash, seed) |",
    "",
    "---",
    "",
    "## How to Use These Results",
    "",
    "```r",
    '# Load manifest',
    'library(jsonlite)',
    paste0('manifest <- fromJSON("', json_path, '")'),
    '',
    '# --- Phase A point estimate ---',
    'manifest$subgroup_estimates[[1]]$median_sgpc   # inferred median SGPc',
    '',
    '# --- Phase B precision operating table (paired mode, default) ---',
    '# CI width at NAEP-scale (N ~ 3000-4000, between n=2500 and n=5000 rows):',
    'manifest$phase_b_systematic$precision_by_n_span  # list of (year_span, n_bucket, ci_width, mae, convergence)',
    '',
    '# --- Linkage premium: paired vs independent cohort sampling ---',
    '# The linkage premium quantifies the CI inflation from TIMSS/NAEP-style',
    '# cross-sectional design (independent cohorts) vs longitudinal pairing.',
    'lp <- manifest$phase_b_systematic$linkage_premium',
    'lp$mean_ci_ratio                    # mean CI multiplier across N buckets',
    'lp$premium_by_n_bucket              # per-N breakdown: ci_ratio, mae_ratio',
    'lp$precision_by_n_span_mode         # full cross-tab: (year_span x n_bucket x sampling_mode)',
    '',
    '# --- Linkage fraction curve: CI width as a function of cohort overlap ---',
    '# linkage_fraction = 1.0 (fully paired) to 0.0 (fully independent)',
    'lf_curve <- lp$linkage_fraction_curve  # list of (linkage_fraction, n_bucket, ci_width)',
    '',
    '# --- Error decomposition ---',
    'manifest$error_sources$inference   # Error 2: bias at full N',
    'manifest$error_sources$variance_decomposition   # var_sampling / var_copula split',
    '',
    '# --- Bucket classification ---',
    'manifest$bucket_classification$subgroups[[1]]$k3_assigned',
    "```",
    ""
  )

  writeLines(md_lines, md_path)

  if (verbose) {
    cat("Manifest exported:\n")
    cat("  JSON:", json_path, "\n")
    cat("  MD:  ", md_path, "\n")
  }

  invisible(list(json = json_path, md = md_path))
}


#' Export Run Metadata
#'
#' Writes a run_metadata.json file capturing the computational environment
#' and configuration for reproducibility.
#'
#' @param config List. STEP 3 configuration.
#' @param output_dir Character. Default "results".
#' @param seed Integer. RNG seed used. Default NULL.
#'
#' @return Invisible path to metadata file.
#'
#' @export
export_run_metadata <- function(config, output_dir = "results", seed = NULL) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  metadata <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform,
    packages = list(
      copula = as.character(packageVersion("copula")),
      data.table = as.character(packageVersion("data.table")),
      jsonlite = as.character(packageVersion("jsonlite"))
    ),
    rng_seed = seed,
    config = config
  )

  # Attempt git hash
  git_hash <- tryCatch(
    {
      system("git rev-parse --short HEAD", intern = TRUE, ignore.stderr = TRUE)
    },
    error = function(e) "unknown"
  )
  metadata$git_hash <- git_hash

  path <- file.path(output_dir, "run_metadata.json")
  write_json(metadata, path, pretty = TRUE, auto_unbox = TRUE)

  invisible(path)
}

#' Export Phase A Deep-Dive Manifest (JSON + Markdown)
#'
#' Writes a comprehensive, Phase A-specific manifest capturing the condition,
#' subgroup, true vs inferred SGPc summaries, family comparison, uncertainty,
#' and key output artifacts.
#'
#' @param phase_a_results List. Object saved by step3_validation_deep_dive.R.
#' @param output_dir Character. Directory for manifest files. Default "results".
#' @param prefix Character. Filename prefix. Default "phase_a".
#' @param verbose Logical. Default TRUE.
#'
#' @return Invisible list with paths to JSON and MD files.
#'
#' @export
export_phase_a_manifest <- function(
  phase_a_results,
  output_dir = "results",
  prefix = "phase_a",
  verbose = TRUE
) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  best_est <- phase_a_results$best_estimate
  true_sgpc <- phase_a_results$true_sgpc
  boot <- phase_a_results$bootstrap
  fam_comp <- phase_a_results$family_comparison$comparison

  true_mean <- mean(true_sgpc, na.rm = TRUE)
  true_median <- median(true_sgpc, na.rm = TRUE)
  inferred_mean <- best_est$regime$mean * 100
  inferred_median <- best_est$regime$median * 100

  manifest <- list(
    metadata = list(
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      step = "STEP_3_LIwLD_PHASE_A",
      description = "Single-condition deep-dive validation manifest"
    ),
    condition = list(
      dataset_id = phase_a_results$dataset_id,
      condition_id = phase_a_results$condition_id,
      condition_meta = phase_a_results$condition_meta,
      subgroup_id = phase_a_results$subgroup_id,
      subgroup_col = phase_a_results$subgroup_col,
      n_subgroup = phase_a_results$n_subgroup,
      references = phase_a_results$references,
      copula_used = phase_a_results$copula_used
    ),
    estimation = list(
      best_family = phase_a_results$best_family,
      best_params = as.numeric(best_est$regime_param_hat),
      m_hat = best_est$m_hat,
      kappa_hat = best_est$kappa_hat,
      distance_metric = best_est$distance_metric,
      distance_min = best_est$distance_min,
      distances = best_est$all_distances
    ),
    sgpc_summary = list(
      inferred = list(
        mean = round(inferred_mean, 2),
        median = round(inferred_median, 2)
      ),
      true = list(
        mean = round(true_mean, 2),
        median = round(true_median, 2)
      ),
      differences = list(
        mean_diff = round(inferred_mean - true_mean, 2),
        median_diff = round(inferred_median - true_median, 2)
      )
    ),
    assumption_diagnostics = list(
      flag_independence_violation = isTRUE(
        phase_a_results$flag_independence_violation
      ),
      spearman_rho = if (!is.null(phase_a_results$independence_diagnostics)) {
        as.numeric(phase_a_results$independence_diagnostics[
          phase_a_results$independence_diagnostics$metric == "spearman_rho",
          "value"
        ][1])
      } else {
        NA_real_
      },
      kruskal_p_value = if (
        !is.null(phase_a_results$independence_diagnostics)
      ) {
        as.numeric(phase_a_results$independence_diagnostics[
          phase_a_results$independence_diagnostics$metric == "kruskal_p_value",
          "value"
        ][1])
      } else {
        NA_real_
      }
    ),
    uncertainty = list(
      sampling_independent = list(
        description = "Error 1a+1b: independent resampling of U and V (cross-sectional design)",
        n_boot = boot$n_boot,
        n_converged = boot$n_converged,
        ci_median_sgpc = as.numeric(boot$ci_median_sgpc),
        ci_mean_sgpc = as.numeric(boot$ci_mean_sgpc),
        se_median_sgpc = as.numeric(boot$se_median_sgpc)
      ),
      # Backward compat alias
      sampling = list(
        n_boot = boot$n_boot,
        n_converged = boot$n_converged,
        ci_median_sgpc = as.numeric(boot$ci_median_sgpc),
        ci_mean_sgpc = as.numeric(boot$ci_mean_sgpc),
        se_median_sgpc = as.numeric(boot$se_median_sgpc)
      )
    ),
    family_comparison = fam_comp
  )

  # Add paired bootstrap and linkage premium if available
  boot_paired <- phase_a_results$bootstrap_paired
  if (!is.null(boot_paired)) {
    manifest$uncertainty$sampling_paired <- list(
      description = "Error 1a only: paired resampling preserving student-level U<->V linkage",
      n_boot = boot_paired$n_boot,
      n_converged = boot_paired$n_converged,
      ci_median_sgpc = as.numeric(boot_paired$ci_median_sgpc),
      ci_mean_sgpc = as.numeric(boot_paired$ci_mean_sgpc),
      se_median_sgpc = as.numeric(boot_paired$se_median_sgpc)
    )
  }
  if (!is.null(phase_a_results$linkage_premium)) {
    manifest$linkage_premium <- phase_a_results$linkage_premium
  }

  # Churn diagnostics
  if (!is.null(phase_a_results$churn_bookkeeping)) {
    cb <- phase_a_results$churn_bookkeeping$condition
    manifest$churn_diagnostics <- list(
      n_prior_all = cb$n_prior_all,
      n_current_all = cb$n_current_all,
      n_stayers = cb$n_stayers,
      n_leavers = cb$n_leavers,
      n_entrants = cb$n_entrants,
      alpha_retention = cb$alpha,
      beta_retention = cb$beta,
      churn_asymmetry = cb$churn_asymmetry,
      churn_type = cb$churn_type
    )
  }
  if (!is.null(phase_a_results$marginal_comparison)) {
    if (is.null(manifest$churn_diagnostics)) {
      manifest$churn_diagnostics <- list()
    }
    mc <- phase_a_results$marginal_comparison
    manifest$churn_diagnostics$marginal_comparison <- list(
      gamma_prior = mc$gamma_prior,
      gamma_current = mc$gamma_current,
      compositionally_ignorable = mc$compositionally_ignorable,
      asymmetry_ratio = mc$asymmetry_ratio
    )
  }
  if (!is.null(phase_a_results$regime_contrast)) {
    if (is.null(manifest$churn_diagnostics)) {
      manifest$churn_diagnostics <- list()
    }
    rc <- phase_a_results$regime_contrast
    manifest$churn_diagnostics$regime_contrast <- list(
      delta_median = rc$delta_median,
      delta_mean = rc$delta_mean,
      median_sgpc_stayer = rc$median_sgpc_stayer,
      median_sgpc_all = rc$median_sgpc_all,
      mean_sgpc_stayer = rc$mean_sgpc_stayer,
      mean_sgpc_all = rc$mean_sgpc_all
    )
  }
  if (!is.null(phase_a_results$theoretical_linkage_premium)) {
    if (is.null(manifest$churn_diagnostics)) {
      manifest$churn_diagnostics <- list()
    }
    tp <- phase_a_results$theoretical_linkage_premium
    manifest$churn_diagnostics$theoretical_premium <- list(
      alpha = tp$alpha,
      rho = tp$rho,
      tau = tp$tau,
      mean_scale = tp$mean_scale,
      cdf_scale = tp$cdf_scale
    )
  }

  manifest$output_files <- list(
    phase_a_rds = file.path(output_dir, "phase_a_deep_dive.rds"),
    phase_a_analytic_payload = file.path(
      output_dir,
      "phase_a_analytic_payload.rds"
    ),
    phase_a_summary_csv = file.path(output_dir, "phase_a_summary.csv"),
    phase_a_precision_anchor_csv = file.path(
      output_dir,
      "phase_a_precision_anchor.csv"
    ),
    independence_diagnostics_csv = file.path(
      output_dir,
      "exports",
      "phase_a",
      "step3_independence_diagnostics.csv"
    ),
    phasea_01_marginals = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_01_marginals_uv_density.pdf"
    ),
    phasea_02a_objective = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_02a_objective_surface.pdf"
    ),
    phasea_02b_cdf = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_02b_forward_cdf_check.pdf"
    ),
    phasea_02c_residual = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_02c_residual_diagnostics.pdf"
    ),
    phasea_03a_regime = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_03a_regime_density.pdf"
    ),
    phasea_03e_recovery = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_03e_recovery_summary.pdf"
    ),
    phasea_03f_linkage = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_03f_linkage_decomposition.pdf"
    ),
    phasea_04_independence = file.path(
      output_dir,
      "visualizations",
      "phase_a",
      "phasea_04_independence_diagnostic.pdf"
    )
  )
  manifest$config <- phase_a_results$config

  json_path <- file.path(output_dir, paste0(prefix, "_manifest.json"))
  write_json(manifest, json_path, pretty = TRUE, auto_unbox = TRUE)

  md_path <- file.path(output_dir, paste0(prefix, "_manifest.md"))
  md_lines <- c(
    "# STEP 3 Phase A Deep-Dive Manifest",
    "",
    paste0("**Generated:** ", manifest$metadata$generated_at),
    "",
    "## Condition and Subgroup",
    "",
    paste0("- **Dataset:** ", manifest$condition$dataset_id),
    paste0("- **Condition:** ", manifest$condition$condition_id),
    paste0(
      "- **Subgroup:** ",
      manifest$condition$subgroup_col,
      " = ",
      manifest$condition$subgroup_id
    ),
    paste0("- **Subgroup n:** ", manifest$condition$n_subgroup),
    paste0("- **Baseline copula:** ", manifest$condition$copula_used$family),
    "",
    "## Canonical Choices",
    "",
    "- Canonical baseline copula (STEP 1 template)",
    "- Canonical stochastically fitted growth regime (STEP 3 selection policy)",
    "",
    "## Estimation Summary",
    "",
    paste0("- **Best family:** ", manifest$estimation$best_family),
    paste0(
      "- **Parameters:** ",
      paste(round(manifest$estimation$best_params, 4), collapse = ", ")
    ),
    paste0("- **Distance metric:** ", manifest$estimation$distance_metric),
    paste0(
      "- **Distance minimum:** ",
      round(manifest$estimation$distance_min, 6)
    ),
    "",
    "## SGPc Summary",
    "",
    paste0("- **Inferred mean SGPc:** ", manifest$sgpc_summary$inferred$mean),
    paste0("- **True mean SGPc:** ", manifest$sgpc_summary$true$mean),
    paste0(
      "- **Mean difference:** ",
      manifest$sgpc_summary$differences$mean_diff
    ),
    paste0(
      "- **Inferred median SGPc:** ",
      manifest$sgpc_summary$inferred$median
    ),
    paste0("- **True median SGPc:** ", manifest$sgpc_summary$true$median),
    paste0(
      "- **Median difference:** ",
      manifest$sgpc_summary$differences$median_diff
    ),
    "",
    "## Assumption Diagnostics (P ⟂ U)",
    "",
    paste0(
      "- **Flag independence violation:** ",
      manifest$assumption_diagnostics$flag_independence_violation
    ),
    paste0(
      "- **Spearman rho(U,SGPc_true):** ",
      round(manifest$assumption_diagnostics$spearman_rho, 4)
    ),
    paste0(
      "- **Kruskal-Wallis p-value:** ",
      signif(manifest$assumption_diagnostics$kruskal_p_value, 4)
    ),
    "",
    "## Uncertainty (Bootstrap)",
    "",
    "### Independent Bootstrap (Error 1a + 1b)",
    "",
    "Resamples prior and current scores with **separate** index vectors,",
    "simulating the TIMSS/NAEP cross-sectional design.",
    "",
    paste0(
      "- **Replicates:** ",
      manifest$uncertainty$sampling$n_boot,
      " (converged: ",
      manifest$uncertainty$sampling$n_converged,
      ")"
    ),
    paste0(
      "- **Mean SGPc 95% CI:** [",
      round(manifest$uncertainty$sampling$ci_mean_sgpc[1], 1),
      ", ",
      round(manifest$uncertainty$sampling$ci_mean_sgpc[2], 1),
      "]"
    ),
    paste0(
      "- **Median SGPc 95% CI:** [",
      round(manifest$uncertainty$sampling$ci_median_sgpc[1], 1),
      ", ",
      round(manifest$uncertainty$sampling$ci_median_sgpc[2], 1),
      "]"
    ),
    paste0(
      "- **Median SGPc SE:** ",
      round(manifest$uncertainty$sampling$se_median_sgpc, 2)
    ),
    ""
  )

  # Paired bootstrap section (if available)
  if (!is.null(manifest$uncertainty$sampling_paired)) {
    sp <- manifest$uncertainty$sampling_paired
    md_lines <- c(
      md_lines,
      "### Paired Bootstrap (Error 1a only)",
      "",
      "Resamples prior and current scores with a **shared** index vector,",
      "preserving the student-level U<->V linkage. Isolates subsampling variability.",
      "",
      paste0(
        "- **Replicates:** ",
        sp$n_boot,
        " (converged: ",
        sp$n_converged,
        ")"
      ),
      paste0(
        "- **Mean SGPc 95% CI:** [",
        round(sp$ci_mean_sgpc[1], 1),
        ", ",
        round(sp$ci_mean_sgpc[2], 1),
        "]"
      ),
      paste0(
        "- **Median SGPc 95% CI:** [",
        round(sp$ci_median_sgpc[1], 1),
        ", ",
        round(sp$ci_median_sgpc[2], 1),
        "]"
      ),
      paste0("- **Median SGPc SE:** ", round(sp$se_median_sgpc, 2)),
      ""
    )
  }

  # Linkage premium section (if available)
  if (!is.null(manifest$linkage_premium)) {
    lp <- manifest$linkage_premium
    md_lines <- c(
      md_lines,
      "### Linkage Premium at Observed N",
      "",
      paste0(
        "The linkage premium quantifies the CI inflation from breaking the ",
        "student-level pairing. At N=",
        format(lp$n_observed, big.mark = ","),
        ":"
      ),
      "",
      "| Measure | CI Width (Paired) | CI Width (Independent) | CI Ratio | SE Ratio |",
      "|---------|-------------------|------------------------|----------|----------|",
      paste0(
        "| Median SGPc | ",
        lp$median$ci_width_paired,
        " | ",
        lp$median$ci_width_independent,
        " | ",
        lp$median$ci_ratio,
        "x",
        " | ",
        lp$median$se_ratio,
        "x |"
      ),
      paste0(
        "| Mean SGPc | ",
        lp$mean$ci_width_paired,
        " | ",
        lp$mean$ci_width_independent,
        " | ",
        lp$mean$ci_ratio,
        "x",
        " | ",
        lp$mean$se_ratio,
        "x |"
      ),
      "",
      "_Ratio > 1 indicates the precision cost of not having longitudinal pairing._",
      "_This single-N anchor complements Phase B's Panel D2, which maps the premium across N values._",
      ""
    )
  }

  # Churn diagnostics markdown section
  if (!is.null(manifest$churn_diagnostics)) {
    cd <- manifest$churn_diagnostics
    md_lines <- c(
      md_lines,
      "## Churn Diagnostics (S/L/E Decomposition)",
      "",
      "Student churn creates partial linkage: some students are stayers (S, observed at both waves),",
      "some are leavers (L, prior wave only), some are entrants (E, current wave only).",
      "",
      "| Quantity | Value |",
      "|----------|-------|",
      paste0(
        "| Prior wave (all students) | ",
        format(cd$n_prior_all, big.mark = ","),
        " |"
      ),
      paste0(
        "| Current wave (all students) | ",
        format(cd$n_current_all, big.mark = ","),
        " |"
      ),
      paste0(
        "| Stayers (matched pairs) | ",
        format(cd$n_stayers, big.mark = ","),
        " |"
      ),
      paste0(
        "| Leavers (prior only) | ",
        format(cd$n_leavers, big.mark = ","),
        " |"
      ),
      paste0(
        "| Entrants (current only) | ",
        format(cd$n_entrants, big.mark = ","),
        " |"
      ),
      paste0("| Alpha (prior retention) | ", cd$alpha_retention, " |"),
      paste0("| Beta (current retention) | ", cd$beta_retention, " |"),
      paste0("| Churn type | ", cd$churn_type, " |"),
      ""
    )
    if (!is.null(cd$marginal_comparison)) {
      mcc <- cd$marginal_comparison
      md_lines <- c(
        md_lines,
        "### Compositional Ignorability Test",
        "",
        "Wasserstein-1 distances between all-student and stayer-only marginals:",
        "",
        paste0("- **Gamma_U (prior):** ", mcc$gamma_prior),
        paste0("- **Gamma_V (current):** ", mcc$gamma_current),
        paste0(
          "- **Compositionally ignorable:** ",
          mcc$compositionally_ignorable
        ),
        if (is.finite(mcc$asymmetry_ratio %||% NA_real_)) {
          paste0(
            "- **Asymmetry ratio (Gamma_V / Gamma_U):** ",
            mcc$asymmetry_ratio,
            if (mcc$asymmetry_ratio > 2) {
              " _(possible observability churn)_"
            } else {
              ""
            }
          )
        } else {
          NULL
        },
        ""
      )
    }
    if (!is.null(cd$regime_contrast)) {
      rcc <- cd$regime_contrast
      md_lines <- c(
        md_lines,
        "### Regime Contrast (Stayer vs All-Student)",
        "",
        paste0(
          "- **Stayer regime:** median = ",
          rcc$median_sgpc_stayer,
          ", mean = ",
          rcc$mean_sgpc_stayer
        ),
        paste0(
          "- **All-student regime:** median = ",
          rcc$median_sgpc_all,
          ", mean = ",
          rcc$mean_sgpc_all
        ),
        paste0("- **Delta median:** ", rcc$delta_median, " SGPc"),
        paste0("- **Delta mean:** ", rcc$delta_mean, " SGPc"),
        ""
      )
    }
    if (!is.null(cd$theoretical_premium)) {
      tpc <- cd$theoretical_premium
      md_lines <- c(
        md_lines,
        "### Theoretical Partial-Linkage Premium",
        "",
        paste0(
          "At alpha = ",
          tpc$alpha,
          ", rho = ",
          tpc$rho,
          " (tau = ",
          tpc$tau,
          "):"
        ),
        "",
        paste0("- **Mean-scale SE multiplier:** ", tpc$mean_scale),
        paste0("- **CDF-scale SE multiplier:** ", tpc$cdf_scale),
        ""
      )
    }
  }

  md_lines <- c(
    md_lines,
    "## Family Comparison",
    "",
    "| Family | Distance | Mean SGPc | Median SGPc | Params |",
    "|--------|----------|-----------|-------------|--------|"
  )

  for (i in seq_len(nrow(fam_comp))) {
    md_lines <- c(
      md_lines,
      paste0(
        "| ",
        fam_comp$family[i],
        " | ",
        round(fam_comp$distance[i], 6),
        " | ",
        round(fam_comp$mean_sgpc[i], 2),
        " | ",
        round(fam_comp$median_sgpc[i], 2),
        " | ",
        fam_comp$params[i],
        " |"
      )
    )
  }

  md_lines <- c(
    md_lines,
    "",
    "## Output Files",
    "",
    "| File | Description |",
    "|------|-------------|",
    "| `phase_a_deep_dive.rds` | Full Phase A results object |",
    "| `phase_a_analytic_payload.rds` | Notation-aligned payload for figure assembly |",
    "| `exports/phase_a/step3_independence_diagnostics.csv` | Independence diagnostics and U-bin summaries |",
    "| `phase_a_summary.csv` | One-row summary for reporting |",
    "| `phase_a_manifest.json` | Machine-readable Phase A manifest |",
    "| `phase_a_manifest.md` | Human-readable Phase A manifest |",
    "| `visualizations/phase_a/phasea_03f_linkage_decomposition.*` | Paired vs independent bootstrap overlay (linkage premium) |",
    "| `visualizations/phase_a/panel_*.{pdf,svg,png}` | Phase A diagnostic panels |",
    ""
  )

  writeLines(md_lines, md_path)

  if (verbose) {
    cat("Phase A manifest exported:\n")
    cat("  JSON:", json_path, "\n")
    cat("  MD:  ", md_path, "\n")
  }

  invisible(list(json = json_path, md = md_path))
}


cat("STEP 3 manifest_export.R loaded.\n")
cat(
  "  Functions: export_step3_manifest, export_phase_a_manifest, export_run_metadata\n"
)
