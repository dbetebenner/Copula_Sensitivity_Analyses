############################################################################
###
### STEP 3 Configuration: Growth Regime Inference (LIw_LD)
###
### All tuneable parameters for STEP 3 in one place.
### Loaded by run_step3.R and individual analysis scripts.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIw_LD)
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
    n_param_draws = 25                      # For copula uncertainty
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
    families       = c("beta", "truncexp", "truncunif"),
    primary_family = "beta",     # Default for single-family estimation

    # Grid search resolution (per parameter dimension)
    grid_resolution = 30
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
    bootstrap_grid_resolution = 20   # Faster grid for bootstrap replicates
  ),

  # ===========================================================================
  # 6. Validation settings (Phase A: deep dive)
  # ===========================================================================
  validation = list(
    # Dataset and condition for the single-condition showcase
    dataset_id     = "dataset_1",
    condition_id   = NULL,       # NULL = auto-select large condition
    # Subgroup selection
    subgroup_col   = "DISTRICT_NUMBER",  # Column to use for subgroups
    min_subgroup_n = 100,        # Minimum students in subgroup
    target_subgroup_n = 500      # Preferred subgroup size
  ),

  # ===========================================================================
  # 7. Systematic validation settings (Phase B)
  # ===========================================================================
  systematic = list(
    datasets    = c("dataset_1"),   # Start with dataset_1
    n_conditions_per_dataset = 10,  # Limit for speed
    n_subgroups_per_condition = 5,  # Top N largest subgroups
    min_subgroup_n = 50,
    year_spans  = c(1, 2, 4),       # Test these spans
    content_areas = NULL             # NULL = all available
  ),

  # ===========================================================================
  # 8. Output settings
  # ===========================================================================
  output = list(
    export_formats     = c("pdf", "svg", "png"),
    make_publication_panels = TRUE,
    make_manifests     = TRUE,
    results_dir        = "STEP_3_LIw_LD/results"
  ),

  # ===========================================================================
  # 9. Reproducibility
  # ===========================================================================
  seed = 20260210
)


cat("STEP 3 configuration loaded.\n")
cat("  Primary regime family:", STEP3_CONFIG$regime$primary_family, "\n")
cat("  Primary distance metric:", STEP3_CONFIG$distance$primary, "\n")
cat("  Bootstrap replicates:", STEP3_CONFIG$uncertainty$n_bootstrap, "\n")
