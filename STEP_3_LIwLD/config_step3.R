############################################################################
###
### STEP 3 Configuration: Growth Regime Inference (LIwLD)
###
### All tuneable parameters for STEP 3 in one place.
### Loaded by run_step3.R and individual analysis scripts.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

STEP3_CONFIG <- list(

  # ===========================================================================
  # 1. Reference marginals
  # ===========================================================================
  reference = list(
    # "global" = pool all students; "within_year" = year-specific ECDF
    type        = "within_year",
    n_grid      = 1000,        # Grid points for interpolation
    tail_buffer = 1e-6         # Buffer at CDF tails

  ),

  # ===========================================================================
  # 2. Baseline copula / kernel
  # ===========================================================================
  copula = list(
    family        = "t",                    # From STEP 1 selection
    params_source = "STEP_1_manifest",      # Load from Phase 1 manifest
    year_span     = NULL,                   # NULL = detect from condition
    n_param_draws = 25,                     # For copula uncertainty
    # "canonical_only" = always use canonical copula (honest NAEP/TIMSS setting)
    # "phase1_best_fit" = use per-condition best-fit copula (oracle benchmark)
    mode          = "canonical_only"
  ),

  kernel = list(
    u_grid_size     = 201,     # Grid resolution for conditional CDF
    v_grid_size     = 201,
    boundary_buffer = 0.005,
    compute_quantile = TRUE     # Also precompute Q_0(p|u)
  ),

  # ===========================================================================
  # 3. Growth regime families
  # ===========================================================================
  regime = list(
    # Canonical production choice (fast, stable, interpretable)
    families       = c("beta"),
    # Optional sensitivity families (run manually when needed)
    sensitivity_families = c("truncexp", "truncunif"),
    primary_family = "beta",
    preferred_family = "beta",
    tie_tolerance  = 1e-4,       # Prefer beta when distances are nearly tied

    # Grid search resolution (per parameter dimension)
    # Used by Phase A deep-dive and Stage 1 full-pool estimates.
    grid_resolution = 30,

    # Grid resolution for Phase B replicate batches (process_replicate_batch).
    # Lower than grid_resolution is intentional: each replicate is one of 200
    # draws so individual precision matters less than aggregate statistics.
    # 10 → 100 grid points vs 15² = 225 → ~2.25x per-task speedup.
    # Set to NULL to keep the hardcoded default of 15.
    rep_grid_resolution = 10,

    stratify_by_u = FALSE,
    stratify_bins = 5
  ),

  # ===========================================================================
  # 4. Distance metric
  # ===========================================================================
  distance = list(
    primary   = "wasserstein1",    # Optimiser objective
    secondary = "cvm",             # Reported alongside
    v_grid_n  = 201                # Number of CDF evaluation points
  ),

  # ===========================================================================
  # 5. Uncertainty quantification
  # ===========================================================================
  uncertainty = list(
    n_bootstrap     = 200,       # Sampling uncertainty replicates
    n_copula_draws  = 25,        # Copula parameter uncertainty draws
    bootstrap_grid_resolution = 20,  # Faster grid for bootstrap replicates
    resample_scheme = "srs_bootstrap" # srs_bootstrap|weighted_bootstrap|replicate_weights
  ),

  # ===========================================================================
  # 5b. Assumption diagnostics (P ⟂ U in subgroup)
  # ===========================================================================
  assumptions = list(
    independence = list(
      u_bins = 5,
      test = "kruskal",
      alpha = 0.05,
      max_abs_spearman = 0.10
    )
  ),

  # ===========================================================================
  # 6. Validation settings (Phase A: deep dive)
  # ===========================================================================
  validation = list(
    # Dataset and condition for the single-condition showcase
    dataset_id     = "dataset_1",
    condition_id   = NULL,       # NULL = auto-select large condition
    content_area   = "MATHEMATICS",  # Preferred content area for auto-selection
    # Subgroup selection
    subgroup_col   = "DISTRICT_NUMBER",  # Column to use for subgroups
    min_subgroup_n = 500,        # Minimum students in subgroup
    target_subgroup_n = 2500      # Preferred subgroup size
  ),

  # ===========================================================================
  # 7. Systematic validation settings (Phase B)
  # ===========================================================================
  systematic = list(
    # -----------------------------------------------------------------------
    # Datasets:
    #   dataset_1 / dataset_3  — same state; large districts make subgroup
    #                            selection straightforward.
    #   dataset_3 conditions   — restricted to 2016+ via condition_filters
    #                            (post-2015 assessment scale transition).
    #   dataset_2              — different state; one very large district,
    #                            one moderate district; yields ~2 eligible
    #                            districts + 3 cluster pools per condition.
    # -----------------------------------------------------------------------
    datasets    = c("dataset_1", "dataset_2", "dataset_3"),
    n_conditions_per_dataset = 10,  # Limit for speed; use NULL for "all available"
    n_subgroups_per_condition = 5,  # Top N largest subgroups (dataset_2 may yield fewer)
    min_subgroup_n = 50,
    min_n = 1000,
    n_buckets = c(1000, 2500, 5000, 7500, 10000),
    eligibility_buffer = 0.10,
    outer_reps = 200,
    use_inner_bootstrap = FALSE,
    audit_inner_bootstrap_fraction = 0.05,
    pool_types = c("district", "cluster"),
    allow_cluster_pools = TRUE,
    n_growth_strata = 3,
    cluster_min_pool_n = 500,
    use_parallel = TRUE,
    # rep_batch_size: replicates per parallel task.
    # This is the most critical tuning parameter for large EC2 instances.
    # Rule of thumb: set so that (outer_reps / rep_batch_size) * n_eligible_combos >> n_workers
    # to ensure workers stay busy and the final dispatch round is not a long tail.
    #   r8g.4xlarge  (16 vCPU,  14 workers): 25 — 192 tasks, ~2 rounds at N>5000 sizes
    #   r8g.12xlarge (48 vCPU,  46 workers): 10 — 480 tasks, good utilisation
    #   r8g.48xlarge (192 vCPU, 188 workers): 5 — 960 tasks, ~5 rounds, good utilisation
    # With batch=25 on r8g.48xlarge, only 192 tasks are dispatched to 188 workers:
    # the last 4 tasks (possibly N=10000 at ~7100s each) leave 184 workers idle.
    rep_batch_size = 5L,        # SET TO 5 FOR r8g.48xlarge; SET TO 25 FOR r8g.4xlarge
    year_spans  = c(1, 2, 4),       # Test these spans
    content_areas = c("READING", "MATHEMATICS"),  # NAEP/TIMSS-relevant domains

    # Sampling mode decomposition -----------------------------------------------
    # Phase B replicates can run under two sampling designs:
    #   "paired"      — same student indices for both U and V (original).
    #                    Measures subsampling variability only.
    #   "independent" — separate random draws for U and V, mirroring
    #                    TIMSS/NAEP where Grade 4 and Grade 8 are different
    #                    students tested in the same year.
    #                    Captures full cross-sectional sampling uncertainty.
    # When both are enabled, the precision-by-N table includes a
    # sampling_mode dimension, and the decomposition panel (panel_d2)
    # directly quantifies the "linkage premium" — the precision cost
    # of not having longitudinal pairing.
    sampling_modes = c("paired", "independent"),  # or just c("paired") to skip
    # "step2_empirical" = load sgpc_emp from STEP 2 outputs (no recomputation)
    # "recompute" = compute true SGPc on-the-fly via sgpc_engine (fallback)
    truth_source = "step2_empirical",
    step2_results_dir = "STEP_2_SGPc_Sensitivity/results",

    # Per-dataset condition filters ----------------------------------------
    # Applied after the global year_span and content_area filters.
    # Each entry is a named list; supported keys:
    #
    #   min_year  (integer): drop conditions whose year_current < min_year
    #   max_year  (integer): drop conditions whose year_current > max_year
    #
    #   year_spans (integer vector): REPLACE the global year_spans for this
    #     dataset only.  Use when certain span values are structurally
    #     impossible (e.g. dataset_3 cannot produce span=4 conditions after
    #     the 2016+ filter without crossing the assessment-scale transition).
    #
    #   content_area_aliases (named list, source -> canonical):
    #     Remap content area labels BEFORE the global content_areas filter
    #     and in all output tables.  The raw label is still used internally
    #     for data queries; the canonical label takes over afterwards.
    #     ELA -> READING: dataset_3 codes its literacy assessment as "ELA"
    #     (post-2015 name); aliasing to "READING" ensures ELA conditions pass
    #     the READING+MATHEMATICS filter and that ELA and READING form one
    #     literacy group in all downstream figures and tables.
    #
    condition_filters = list(

      # dataset_2: years 2007-2014.  The first year where span=4 SGPs exist
      # is 2011 (prior=2007 -> current=2011).  Year_current=2011 norms are
      # immature (no prior span=4 baseline); 2012+ have at least one prior
      # year of span=4 history and yield more stable estimates.
      dataset_2 = list(
        min_year = 2012
      ),

      # dataset_3: same state as dataset_1, assessment transition in 2015.
      #   - Restrict to 2016+ (post-transition scale only).
      #   - span=4 is structurally impossible: the only post-2016 span=4
      #     window (prior=2013, current=2017) crosses the 2015 transition.
      #   - Literacy is coded "ELA" in dataset_3; alias to "READING" so that
      #     ELA and READING form one literacy group in analysis outputs.
      dataset_3 = list(
        min_year             = 2016,
        year_spans           = c(1L, 2L),
        content_area_aliases = list(ELA = "READING")
      )
    )
  ),

  # ===========================================================================
  # 8. Bucket classification
  # ===========================================================================
  buckets = list(
    k3 = c(45, 55),
    k5 = c(40, 45, 55, 60)
  ),

  # ===========================================================================
  # 8b. Model-health thresholds
  # ===========================================================================
  thresholds = list(
    point_accuracy = list(
      good = 2.0,
      warn = 5.0
    ),
    w1_reduction_pct = list(
      good = 20,
      warn = 10
    ),
    residual = list(
      max_abs_good = 0.03,
      max_abs_warn = 0.05,
      mean_abs_good = 0.01,
      mean_abs_warn = 0.02
    ),
    cvm = list(
      good = 0.0010,
      warn = 0.0025
    ),
    bootstrap = list(
      max_ci_width_good = 8,
      max_ci_width_warn = 12,
      min_converged_rate_good = 0.90,
      min_converged_rate_warn = 0.85
    )
  ),

  # ===========================================================================
  # 8c. Sensitivity settings
  # ===========================================================================
  sensitivity = list(
    copula_param_quantiles = c(0.25, 0.50, 0.75),
    include_alternative_copula_families = FALSE,
    phase_b_subset_max_subgroups = 25
  ),

  # ===========================================================================
  # 9. Output settings
  # ===========================================================================
  output = list(
    export_formats     = c("pdf", "svg", "png"),
    make_publication_panels = TRUE,
    make_manifests     = TRUE,
    results_dir        = "STEP_3_LIwLD/results",
    phase_a_legacy_alias_plots = TRUE
  ),

  # ===========================================================================
  # 10. Reproducibility
  # ===========================================================================
  seed = 20260210
)


cat("STEP 3 configuration loaded.\n")
cat("  Primary regime family:", STEP3_CONFIG$regime$primary_family, "\n")
cat("  Primary distance metric:", STEP3_CONFIG$distance$primary, "\n")
cat("  Bootstrap replicates:", STEP3_CONFIG$uncertainty$n_bootstrap, "\n")
