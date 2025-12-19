# Empirical Copula Plotting Enhancement

## Summary

Updated the phase1 analysis pipeline to generate comprehensive empirical copula visualizations, including individual plots for Raw (Deheuvels), Bernstein, and KDE methods, plus comparison plots.

## Changes Made

### 1. Updated `functions/copula_contour_plots.R`

#### Added `empirical_copulas` parameter to `generate_condition_plots()`
- New optional parameter to accept a list of `empCopula` objects
- Default value: `NULL` (backward compatible)

#### Enhanced empirical copula plotting section (lines 1183-1304)
When `empirical_copulas` is provided (contains Raw and Bernstein objects), the function now generates:

1. **Raw Empirical Copula CDF** (`raw_empirical_copula_CDF.{pdf,svg,png}`)
   - Step-function empirical copula (Deheuvels method)
   - Uses `pCopula()` on the `empCopula` object with `smoothing = NULL`
   - No legend, inline quantile labels (0.1-0.9)

2. **Bernstein Empirical Copula CDF** (`bernstein_empirical_copula_CDF.{pdf,svg,png}`)
   - Smoothed empirical copula using Bernstein polynomials
   - Uses `pCopula()` on the `empCopula` object with `smoothing = "beta"`
   - No legend, inline quantile labels (0.1-0.9)

3. **Comparison: Bernstein vs Raw** (`comparison_bernstein_vs_raw_CDF.{pdf,svg,png}`)
   - CDF difference heatmap: Bernstein - Raw
   - Zissou1 color scheme (blue-white-red)
   - Color scale fixed to [-0.001, +0.001]
   - Shows smoothing effect of Bernstein polynomials

4. **Comparison: Raw vs KDE** (`comparison_raw_vs_KDE_CDF.{pdf,svg,png}`)
   - CDF difference heatmap: Raw (empCopula) - KDE (custom implementation)
   - Zissou1 color scheme (blue-white-red)
   - Color scale fixed to [-0.01, +0.01]
   - Compares the `copula` package implementation with custom KDE

All plots include:
- Dynamic titles with Greek τ (tau) and formatted sample size
- Consistent subtitles with content area, years, and grades
- Axis labels with subscripted grades (e.g., u_{Grade 4})
- Transparent backgrounds for SVG
- Multi-format export (PDF, SVG, PNG)

### 2. Updated `STEP_1_Family_Selection/phase1_family_selection_parallel.R`

**Lines 516-543**: Added empirical copula loading and passing
```r
# Load empCopula objects if available
empirical_copulas_file <- file.path(plot_output_dir, "empirical_copulas.rds")
empirical_copulas <- NULL
if (file.exists(empirical_copulas_file)) {
  empirical_copulas <- tryCatch({
    readRDS(empirical_copulas_file)
  }, error = function(e) {
    warning(sprintf("Failed to load empirical_copulas.rds: %s", e$message))
    NULL
  })
}

# Pass to generate_condition_plots
generate_condition_plots(
  # ... other parameters ...
  empirical_copulas = empirical_copulas,  # NEW
  # ...
)
```

### 3. Updated `STEP_1_Family_Selection/phase1_family_selection.R`

**Lines 327-356**: Same changes as parallel version
- Load `empirical_copulas.rds` from the output directory
- Pass `empirical_copulas` parameter to `generate_condition_plots()`
- Graceful error handling if file doesn't exist

### 4. Updated `STEP_1_Family_Selection/test_contour_plots.R`

**Lines 278-289**: Added empirical copula loading before first plot generation
**Line 300**: Added `empirical_copulas` parameter to first `generate_condition_plots()` call
**Line 393**: Added `empirical_copulas` parameter to second `generate_condition_plots()` call (with bootstrap)

## Output Structure

When phase1 scripts run, each condition directory will now contain:

```
STEP_1_Family_Selection/results/{dataset_id}/contour_plots/{condition}/
├── empirical_copulas.rds                       # Saved empCopula objects
├── empirical_copula_CDF.{pdf,svg,png}         # KDE method (existing)
├── empirical_copula_PDF.{pdf,svg,png}         # KDE method (existing)
├── raw_empirical_copula_CDF.{pdf,svg,png}     # NEW: Raw/Deheuvels
├── bernstein_empirical_copula_CDF.{pdf,svg,png} # NEW: Bernstein smoothed
├── comparison_bernstein_vs_raw_CDF.{pdf,svg,png} # NEW: Bernstein - Raw
├── comparison_raw_vs_KDE_CDF.{pdf,svg,png}    # NEW: Raw - KDE
├── comparison_empirical_vs_t_CDF.{pdf,svg,png} # Best parametric vs KDE
├── bivariate_density.{pdf,svg,png}
├── t_copula_CDF.{pdf,svg,png}
├── t_copula_PDF.{pdf,svg,png}
├── gaussian_copula_CDF.{pdf,svg,png}
└── ... (other parametric families)
```

## Empirical Copula Methods Comparison

| Method | Class | Smoothing | Use Case | Plot Files |
|--------|-------|-----------|----------|------------|
| **KDE** | Custom | Kernel density | Legacy comparison | `empirical_copula_*.pdf` |
| **Raw** | `empCopula` | None (step function) | Parametric comparison baseline | `raw_empirical_copula_*.pdf` |
| **Bernstein** | `empCopula` | Beta polynomials | SGPc calculations | `bernstein_empirical_copula_*.pdf` |

### Differences to Expect

1. **Bernstein vs Raw**: Very small differences (typically < 0.001)
   - Bernstein smooths out the step function
   - Better boundary behavior
   - Suitable for derivative calculations

2. **Raw vs KDE**: Slightly larger differences (typically < 0.01)
   - KDE uses bandwidth selection for smoothing
   - Different mathematical approaches to smoothing
   - Both are valid empirical copula estimates

## Backward Compatibility

- All changes are backward compatible
- If `empirical_copulas = NULL` (default), only KDE plots are created
- Existing scripts that don't pass `empirical_copulas` will work unchanged
- No changes to existing plot filenames or formats

## Testing

Run the test script to verify all plots are generated correctly:

```r
source("STEP_1_Family_Selection/test_empirical_copulas.R")
```

Expected console output:
```
✓ Loaded empirical copula objects (Raw, Bernstein)
  - Generating additional empirical copula method plots...
    • Raw empirical copula CDF
    • Bernstein empirical copula CDF
    • Comparison: Bernstein vs Raw
    • Comparison: Raw vs KDE
```

## Next Steps

1. Run `test_empirical_copulas.R` to confirm all plots generate correctly
2. Run a small subset of `phase1_family_selection.R` conditions to verify integration
3. Review comparison plots to understand empirical copula method differences
4. Decide which empirical copula method to use for SGPc calculations (recommendation: Bernstein)

## Notes

- All empirical copula plots use the same grid resolution (`grid_size = 300`)
- Color scales for comparison plots are fixed for consistent visual comparison
- Transparent backgrounds in SVG format for publication use
- Greek letter τ (tau) rendered consistently across all plots using `bquote()`

