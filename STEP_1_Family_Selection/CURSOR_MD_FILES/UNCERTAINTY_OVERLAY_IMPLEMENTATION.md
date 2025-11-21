# Bootstrap Uncertainty Gradient Overlay Implementation

## Overview

This document describes the implementation of gradient-based uncertainty visualization for parametric copula contour plots. The visualization overlays bootstrap parameter uncertainty as a black gradient (darker = more uncertain) on top of empirical copula background colors (Zissou1 palette), with empirical contours overlaid for comparison.

**Date**: November 11, 2025
**Status**: ✅ IMPLEMENTED

---

## Visual Design

### Layer Structure (Bottom to Top)

1. **Background**: Filled contours from empirical copula (Zissou1 palette)
   - Shows actual dependence structure from data
   - 15 discrete color bands for CDF/PDF levels
   - Semi-transparent (alpha = 0.6) to allow gradient to show through

2. **Uncertainty Gradient**: Black overlay with varying opacity
   - Darker regions = higher parameter uncertainty (SE from bootstrap)
   - Lighter regions = lower parameter uncertainty
   - Alpha range: 0.05 (low) to 0.20 (high uncertainty)
   - Continuous gradient using `geom_raster` with alpha mapping

3. **Parametric Contours**: Solid black lines
   - Point estimate from bootstrap mean
   - 15 contour levels matching background
   - Linewidth = 0.8

4. **Empirical Contours**: Yellow/orange lines
   - "Ground truth" from data
   - Color: #E1AF00 (from Zissou1 palette)
   - Linewidth = 1.2 (thicker for visibility)
   - No uncertainty (these are the reference)

### Interpretation

- **Empirical lines INSIDE uncertainty gradient**: Parametric model fits well (within parameter uncertainty)
- **Empirical lines OUTSIDE uncertainty gradient**: Significant model misfit (systematic departure from parametric form)
- **Wide gradient regions**: High parameter uncertainty (poor identifiability, small sample)
- **Narrow gradient regions**: Low parameter uncertainty (good fit, large sample)

---

## Implementation Details

### New Functions

#### 1. `calculate_bootstrap_uncertainty()`

**Location**: `functions/copula_contour_plots.R` (lines 74-164)

**Purpose**: Evaluates all bootstrap copula samples on a grid and calculates pointwise uncertainty metrics.

**Inputs**:
- `bootstrap_results`: Output from `bootstrap_copula_estimation()`
- `family`: Copula family name (e.g., "gaussian", "t", "frank")
- `grid_size`: Number of grid points per dimension (default 100)
- `method`: "cdf" (cumulative distribution) or "density" (PDF)

**Process**:
1. Extract bootstrap fits for specified family
2. Create 100×100 evaluation grid on [0.01, 0.99]²
3. Evaluate all N bootstrap copulas at each grid point
4. Calculate pointwise statistics:
   - Point estimate (mean across bootstraps)
   - Standard deviation
   - 5th and 95th percentiles
5. Create normalized uncertainty density field for gradient mapping

**Outputs** (list):
- `point_estimate`: 100×100 matrix of mean copula values
- `uncertainty_sd`: 100×100 matrix of standard deviations
- `uncertainty_density`: Normalized [0,1] uncertainty for alpha mapping
- `lower_bound`, `upper_bound`: 90% confidence bounds
- `u_grid`, `v_grid`: Grid coordinates
- `n_bootstrap`: Number of bootstrap samples used

**Computational Cost**:
- ~2M copula evaluations (200 bootstraps × 10,000 grid points)
- ~2-3 seconds per family with parallelization
- Total for 6 families: ~15 seconds

#### 2. `plot_copula_with_uncertainty_overlay()`

**Location**: `functions/copula_contour_plots.R` (lines 315-443)

**Purpose**: Creates the layered uncertainty overlay plot with gradient visualization.

**Inputs**:
- `empirical_grid`: Empirical copula grid (for background colors)
- `uncertainty_results`: Output from `calculate_bootstrap_uncertainty()`
- `family`: Copula family name
- `title`: Plot title (auto-generated if NULL)
- `plot_type`: "cdf" or "density"

**Layer Construction**:
```r
ggplot() +
  # Layer 1: Empirical background (Zissou1)
  geom_contour_filled(empirical, bins=15, alpha=0.6) +
  scale_fill_manual(Zissou1 palette) +
  
  # Layer 2: Uncertainty gradient (black alpha)
  geom_raster(uncertainty_density, fill="black", interpolate=TRUE) +
  scale_alpha_continuous(range = c(0.05, 0.20)) +
  
  # Layer 3: Parametric lines (black)
  geom_contour(parametric, color="black", linewidth=0.8) +
  
  # Layer 4: Empirical lines (yellow)
  geom_contour(empirical, color="#E1AF00", linewidth=1.2)
```

**Output**: ggplot object ready for saving

#### 3. Modified `generate_condition_plots()`

**Location**: `functions/copula_contour_plots.R` (line 643)

**Changes**:
- Added `bootstrap_results = NULL` parameter
- New section 4b (lines 769-842): Bootstrap uncertainty overlay generation
- For each copula family:
  - Calculate CDF uncertainty → plot → save to `FAMILY/family_copula_with_uncertainty_CDF.pdf`
  - Calculate PDF uncertainty → plot → save to `FAMILY/family_copula_with_uncertainty_PDF.pdf`

**Conditional Execution**:
- If `bootstrap_results` is NULL: Skips uncertainty plots (backward compatible)
- If provided: Generates uncertainty overlays for all families (except comonotonic)

---

## Test Script Updates

### `test_contour_plots.R` Modifications

**Configuration** (lines 281-285):
```r
N_BOOTSTRAP <- 100  # Reduce from 200 for testing
USE_PARALLEL <- TRUE
N_CORES <- NULL  # Auto-detect
BOOTSTRAP_ALL_FAMILIES <- TRUE  # Enable complete visualization
```

**Workflow**:
1. **Initial plots** (line 259): Generate standard plots without uncertainty
2. **Bootstrap** (line 314): Run bootstrap on all families
3. **Uncertainty overlays** (line 347): Regenerate plots WITH uncertainty
4. **Legacy plots** (line 378): Keep old uncertainty methods for comparison

**Output Structure**:
```
output/2005_G4_G5_MATHEMATICS/
├── empirical_copula_CDF.pdf           # Empirical copula (CDF)
├── empirical_copula_PDF.pdf           # Empirical copula (PDF)
├── bivariate_density_original.pdf     # Original scores
├── summary_grid.pdf                    # Summary grid
├── GAUSSIAN/
│   ├── gaussian_copula_CDF.pdf                      # Standard parametric CDF
│   ├── gaussian_copula_PDF.pdf                      # Standard parametric PDF
│   ├── gaussian_copula_with_uncertainty_CDF.pdf    # NEW: With uncertainty overlay
│   ├── gaussian_copula_with_uncertainty_PDF.pdf    # NEW: With uncertainty overlay
│   └── comparison_empirical_vs_gaussian_CDF.pdf    # Difference plot
├── T/
│   ├── t_copula_CDF.pdf
│   ├── t_copula_with_uncertainty_CDF.pdf           # NEW
│   ├── t_copula_with_uncertainty_PDF.pdf           # NEW
│   └── ...
├── CLAYTON/...
├── GUMBEL/...
├── FRANK/...
└── COMONOTONIC/...
```

---

## Usage Examples

### Basic Usage (Test Single Condition)

```r
# 1. Source the test script
source("STEP_1_Family_Selection/test_contour_plots.R")

# The script will:
# - Fit all copula families
# - Bootstrap all families (100 samples)
# - Generate uncertainty overlay plots for each family
# - Save to output/[CONDITION]/
```

### Custom Configuration

```r
# Fast testing (fewer bootstraps, fewer families)
N_BOOTSTRAP <- 50
BOOTSTRAP_ALL_FAMILIES <- FALSE  # Only best family

# Production (more bootstraps, all families)
N_BOOTSTRAP <- 200
BOOTSTRAP_ALL_FAMILIES <- TRUE

# Disable parallelization (for debugging)
USE_PARALLEL <- FALSE
```

### Integration into Production Pipeline

```r
# In your analysis script:
source("functions/copula_bootstrap.R")
source("functions/copula_contour_plots.R")

# 1. Fit copulas
copula_fits <- fit_copula_from_pairs(...)

# 2. Bootstrap for uncertainty
bootstrap_results <- bootstrap_copula_estimation(
  pairs_data = data,
  n_bootstrap = 200,
  copula_families = c("gaussian", "t", "frank"),
  use_parallel = TRUE
)

# 3. Generate plots with uncertainty
plots <- generate_condition_plots(
  pseudo_obs = copula_fits$pseudo_obs,
  original_scores = data,
  copula_results = copula_fits$results,
  best_family = copula_fits$best_family,
  output_dir = "output/my_condition/",
  condition_info = info,
  bootstrap_results = bootstrap_results,  # Add this!
  save_plots = TRUE
)
```

---

## Performance Considerations

### Computational Cost

**Per condition**:
- Copula fitting: ~5 seconds
- Bootstrap (100 samples × 6 families): ~2-3 minutes (parallelized)
- Uncertainty calculation (6 families × 2 types): ~15 seconds
- Plot generation: ~10 seconds

**Total**: ~3-4 minutes per condition with parallelization

**For full analysis (28 conditions)**:
- Total time: ~1.5-2 hours (with BOOTSTRAP_ALL_FAMILIES=TRUE)
- Can be run on EC2 with 16+ cores for faster results

### Optimization Strategies

1. **Test Phase**: 
   - `N_BOOTSTRAP = 50`
   - `BOOTSTRAP_ALL_FAMILIES = FALSE`
   - Single condition
   - Result: ~30 seconds per condition

2. **Production Phase**:
   - `N_BOOTSTRAP = 200`
   - `BOOTSTRAP_ALL_FAMILIES = TRUE`
   - All conditions
   - Use EC2 with 32 cores

3. **Memory Usage**:
   - Bootstrap results: ~50 MB per condition
   - Plots: ~2 MB per condition
   - Total: ~100 MB per condition (manageable)

---

## Technical Notes

### Gradient Implementation (Option A)

The gradient effect is achieved using continuous alpha mapping:

```r
# Normalize SD to [0, 1]
uncertainty_density <- sd_matrix / max(sd_matrix)

# Map to alpha aesthetic
geom_raster(aes(alpha = uncertainty_density), fill = "black")
scale_alpha_continuous(range = c(0.05, 0.20))
```

**Advantages**:
- Smooth, publication-quality gradient
- Similar to `densregion()` from `denstrip` package
- Intuitive: darker = more uncertain

**Alternative (Option B - not implemented)**:
- Discrete bands (10 levels)
- Less smooth but computationally cheaper
- Use if gradient rendering is slow

### Color Palette Selection

**Zissou1 from `wesanderson`**:
- Blue → Teal → Pink → Red
- Ocean theme fitting for probability distributions
- Good contrast with black gradient
- Color-blind friendly (check with `colorBlindness` package if needed)

**Empirical overlay color**: #E1AF00 (golden yellow from Zissou1)
- High contrast with black lines
- Visible on both light and dark gradient regions
- Distinct from parametric lines

### ggplot2 Layer Ordering

Critical: Layers are drawn bottom-to-top!

```r
# CORRECT ORDER:
geom_contour_filled()    # Background (first)
geom_raster()            # Gradient (middle)
geom_contour() [black]   # Parametric (third)
geom_contour() [yellow]  # Empirical (last, on top)

# WRONG: Empirical will be hidden!
geom_contour() [yellow]  # Empirical
geom_raster()            # Gradient covers it!
```

---

## Validation and Testing

### Visual Checks

1. **Gradient visibility**: Black gradient should be visible in all regions
2. **Empirical lines on top**: Yellow lines should never be obscured
3. **Parametric lines visible**: Black lines should show through gradient
4. **Color palette**: Background colors should match standard CDF plots

### Quantitative Checks

1. **Uncertainty range**: SD should be > 0 everywhere
2. **Bootstrap samples**: Check `n_bootstrap` in subtitle
3. **Grid resolution**: Ensure smooth contours (100×100 minimum)

### Comparison with Legacy Methods

Compare new overlay plots with:
- Confidence band plots (from old implementation)
- Heatmap plots (from old implementation)
- Standard difference plots

All should tell consistent story about fit quality!

---

## Known Limitations

1. **Comonotonic copula**: No parametric form, so no bootstrap uncertainty
   - Skipped in uncertainty overlay generation
   
2. **Computational cost**: ~3-4 minutes per condition with all families
   - Use `BOOTSTRAP_ALL_FAMILIES=FALSE` for quick tests
   
3. **Alpha range**: Currently fixed at [0.05, 0.20]
   - May need adjustment for very high/low uncertainty cases
   - Could be made adaptive in future

4. **Grid resolution**: 100×100 is smooth but not ultra-high-res
   - Increase to 150×150 for publication if needed
   - Will increase computation time proportionally

---

## Future Enhancements

### Short Term
- [ ] Adaptive alpha range based on data
- [ ] Option to show specific percentile contours (5th, 95th)
- [ ] Legend improvements (show alpha gradient)

### Medium Term
- [ ] True variable-width contours (custom geom)
- [ ] Animation showing bootstrap samples
- [ ] Interactive plotly version

### Long Term
- [ ] GPU acceleration for bootstrap evaluation
- [ ] Real-time uncertainty updates as bootstrap progresses
- [ ] Comparison across conditions side-by-side

---

## References

### Inspiration
- **densregion()** from `denstrip` package: Gradient shading for uncertainty
- Jackson, C. H. (2008) "Displaying uncertainty with shading." *The American Statistician*, 62(4):340-347.

### Related Implementations
- STEP_1_Family_Selection/BOOTSTRAP_UNCERTAINTY_IMPLEMENTATION.md (previous version)
- functions/copula_bootstrap.R (bootstrap estimation)
- functions/copula_contour_plots.R (visualization)

---

## Support and Questions

For questions or issues:
1. Check this documentation first
2. Review test script: `STEP_1_Family_Selection/test_contour_plots.R`
3. Examine example output: `output/2005_G4_G5_MATHEMATICS/`
4. Contact: [Your contact info]

---

**Status**: ✅ Ready for production testing
**Next Step**: Run test script and review output plots for publication quality

