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
    grid_resolution = 30,
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
    datasets    = c("dataset_1"),   # Start with dataset_1
    n_conditions_per_dataset = 10,  # Limit for speed
    n_subgroups_per_condition = 5,  # Top N largest subgroups
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
    rep_batch_size = 25L,       # replicates per parallel task (tune for granularity vs overhead)
    year_spans  = c(1, 2, 4),       # Test these spans
    content_areas = NULL,            # NULL = all available
    # "step2_empirical" = load sgpc_emp from STEP 2 outputs (no recomputation)
    # "recompute" = compute true SGPc on-the-fly via sgpc_engine (fallback)
    truth_source = "step2_empirical",
    step2_results_dir = "STEP_2_SGPc_Sensitivity/results"
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
