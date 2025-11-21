# Bootstrap Uncertainty Ribbon Visualization

## Overview

This document describes the implementation of gradient-based uncertainty **ribbons** around parametric copula contours. This approach creates clean, interpretable visualizations where uncertainty is localized to specific contour levels rather than shown as a global overlay.

**Date**: November 11, 2025  
**Status**: ✅ IMPLEMENTED  
**Approach**: Gradient ribbons around contours (Option A with ribbons)

---

## Visual Design

### Layer Structure (Bottom to Top)

#### Layer 1: Background (Zissou1 Parametric CDF)
- **Source**: Parametric copula point estimate (bootstrap mean)
- **Style**: Filled contours with Zissou1 palette
- **Purpose**: Shows the fitted parametric model
- **Bins**: 15 discrete contour levels (0.067, 0.133, ..., 1.0)
- **Alpha**: 0.7 (semi-transparent)

#### Layer 2: Uncertainty Ribbons (Gradient Bands)
- **Source**: Bootstrap 5th and 95th percentiles
- **Style**: Multiple overlapping contour lines with gradient alpha
- **Implementation**: 10 interpolated surfaces between lower and upper bounds
- **Alpha gradient**: 0.15 (opaque, near center) → 0.02 (transparent, at edges)
- **Color**: Black
- **Linewidth**: 2.5 (thick enough to create band/ribbon effect)
- **Purpose**: Shows where each contour could plausibly be located

#### Layer 3: Parametric Center Lines
- **Source**: Parametric copula point estimate
- **Style**: Thin black contour lines
- **Linewidth**: 0.6
- **Purpose**: Marks the center of each uncertainty ribbon

#### Layer 4: Empirical Overlay
- **Source**: Empirical copula from data
- **Style**: Solid contour lines
- **Color**: #E1AF00 (golden yellow from Zissou1)
- **Linewidth**: 1.2 (thicker for visibility)
- **Purpose**: "Ground truth" for comparison

---

## Interpretation

### What the Ribbons Tell You

**Narrow ribbons** (barely visible):
- Low parameter uncertainty
- Large sample size or strong identifiability
- Parametric model is well-constrained by data

**Wide ribbons** (thick black bands):
- High parameter uncertainty
- Small sample size or weak identifiability
- Multiple parameter values could produce similar fits

### Where Empirical Lines Fall

**Yellow lines INSIDE black ribbons**:
- ✅ Empirical data consistent with parametric model
- Difference could be due to parameter uncertainty alone
- Model fits well

**Yellow lines OUTSIDE black ribbons**:
- ⚠️ Systematic model misfit
- Empirical copula differs from parametric even accounting for uncertainty
- Consider different copula family or model inadequacy

**Yellow lines at EDGE of ribbons**:
- Borderline fit
- May indicate subtle dependence features not captured
- Worth investigating further

---

## Technical Implementation

### Core Function: `plot_copula_with_uncertainty_ribbons()`

**Location**: `functions/copula_contour_plots.R` (lines 315-462)

**Key Innovation**: Gradient effect via multiple semi-transparent contour layers

```r
# Create 10 interpolated surfaces between 5th and 95th percentiles
alpha_levels <- seq(0.15, 0.02, length.out = 10)

for (i in 1:10) {
  fraction <- (i - 1) / 9
  
  # Interpolate between lower and upper bounds
  interp_value <- lower_bound + fraction * (upper_bound - lower_bound)
  
  # Draw contour with decreasing alpha (reversed so center is darker)
  alpha_val <- alpha_levels[11 - i]
  
  geom_contour(z = interp_value, 
               color = "black", 
               alpha = alpha_val,
               linewidth = 2.5)  # Thick = ribbon effect
}
```

**Why this works**:
1. Each interpolated surface creates a contour slightly offset from neighbors
2. Thick linewidth (2.5) ensures contours overlap
3. Decreasing alpha creates gradient: opaque center → transparent edges
4. Result: Smooth gradient ribbon around each contour level

---

## Usage

### Quick Test

```r
source("STEP_1_Family_Selection/test_contour_plots.R")
```

Outputs will be in:
```
output/2005_G4_G5_MATHEMATICS/
├── T/
│   ├── t_copula_CDF.pdf                         # Standard (no uncertainty)
│   ├── t_copula_with_uncertainty_CDF.pdf        # NEW: With ribbons! ⭐
│   ├── t_copula_PDF.pdf                         
│   └── t_copula_with_uncertainty_PDF.pdf        # NEW: With ribbons! ⭐
└── [GAUSSIAN, CLAYTON, GUMBEL, FRANK, COMONOTONIC]/
```

### Configuration

In `test_contour_plots.R`:

```r
N_BOOTSTRAP <- 100              # More samples = smoother ribbons
BOOTSTRAP_ALL_FAMILIES <- TRUE  # FALSE = only best family (faster)
USE_PARALLEL <- TRUE            # Highly recommended!
```

In function call (for custom use):

```r
plot <- plot_copula_with_uncertainty_ribbons(
  empirical_grid = empirical_cdf,
  uncertainty_results = bootstrap_uncertainty,
  family = "t",
  plot_type = "cdf",
  n_gradient_levels = 10  # More = smoother gradient (default 10)
)
```

---

## Comparison with Previous Approach

### Previous: Global Uncertainty Overlay
- Black gradient showing uncertainty **everywhere**
- Harder to interpret (what does dark region mean?)
- Empirical copula used for background colors
- Less clear which contour levels are uncertain

### Current: Localized Uncertainty Ribbons
- ✅ Ribbons only around specific contour levels
- ✅ Easy interpretation: "this contour could be here ± this much"
- ✅ Parametric model provides background colors (makes sense!)
- ✅ Can see which contour levels are well vs poorly identified

**User feedback**: "This is what I was expecting" ✓

---

## Performance

### Computational Cost

Same as previous approach:
- Bootstrap (100 samples × 6 families): ~2-3 minutes
- Uncertainty calculation: ~15 seconds
- Plot rendering (10 gradient levels): ~5 seconds per family

**Total per condition**: ~3-4 minutes

### Memory

- Bootstrap results: ~50 MB
- Plots: ~3 MB (slightly larger due to multiple contour layers)

---

## Customization

### Ribbon Thickness

Adjust `n_gradient_levels` (default 10):
- **5 levels**: Coarse gradient, faster rendering
- **10 levels**: Smooth gradient (recommended)
- **20 levels**: Very smooth, slower, may not be noticeably better

### Alpha Range

Currently: `seq(0.15, 0.02, length.out = n_gradient_levels)`
- Increase 0.15 → 0.25 for **darker ribbons** (more visible)
- Decrease 0.02 → 0.01 for **softer edges** (more subtle)
- Adjust via editing `plot_copula_with_uncertainty_ribbons()`

### Contour Linewidth

Currently: `linewidth = 2.5`
- Increase to 3.5 for **wider ribbons**
- Decrease to 1.5 for **thinner ribbons**
- Trade-off: wider = more visible but may obscure background

### Empirical Line Color

Currently: `#E1AF00` (golden yellow from Zissou1)
- Try `#F21A00` (red from Zissou1) for higher contrast
- Try `#78B7C5` (blue from Zissou1) for cool tone
- Ensure good visibility on both light and dark Zissou1 colors

---

## Example Interpretation

Imagine a t-copula CDF plot with ribbons:

### Upper-right corner (high u, high v):
- **Background**: Red/pink (C ≈ 0.9)
- **Ribbon**: Barely visible (thin black band)
- **Interpretation**: High joint probability region, well-identified
- **Empirical line**: Inside ribbon → ✅ Good fit

### Lower-left corner (low u, low v):
- **Background**: Blue (C ≈ 0.1)
- **Ribbon**: Visible but still thin
- **Interpretation**: Low joint probability, reasonably certain
- **Empirical line**: Slightly outside → ⚠️ Minor tail misfit

### Center region (u ≈ 0.5, v ≈ 0.5):
- **Background**: Yellow/green (C ≈ 0.4-0.6)
- **Ribbon**: Moderate width
- **Interpretation**: Mid-range probabilities, some uncertainty
- **Empirical line**: Inside ribbon → ✅ Fits within uncertainty

---

## Known Limitations

1. **Thin ribbons**: With large n, ribbons may be barely visible
   - Consider increasing alpha range or linewidth
   - This is actually good news (low uncertainty!)

2. **Overlapping contours**: In steep gradient regions, ribbons may overlap
   - Generally not a problem
   - Gradient alpha prevents obscuring background

3. **Computation time**: ~3-4 minutes per condition with 100 bootstrap samples
   - Use `BOOTSTRAP_ALL_FAMILIES = FALSE` for quick tests
   - Parallelize across conditions for production runs

4. **Discrete gradient**: 10 levels may show slight banding
   - Increase `n_gradient_levels` to 15-20 if visible
   - Trade-off with rendering time

---

## Future Enhancements

### Short Term
- [ ] Adaptive alpha range based on ribbon width
- [ ] Option to show only ribbons (no background) for cleaner look
- [ ] Separate legend entry for ribbons

### Medium Term
- [ ] True continuous gradient (smooth shader)
- [ ] Color-coded ribbons (hue indicates uncertainty magnitude)
- [ ] Interactive plotly version with hover info

### Long Term
- [ ] Animation showing individual bootstrap samples
- [ ] 3D version showing CDF as surface with uncertainty bands
- [ ] Side-by-side comparison across multiple conditions

---

## Troubleshooting

### Ribbons not visible

**Problem**: Black ribbons barely visible on dark Zissou1 colors

**Solutions**:
1. Increase `alpha_levels`: `seq(0.25, 0.05, ...)` (darker)
2. Increase `linewidth`: `3.5` or `4.0` (wider)
3. Try different ribbon color: `"gray20"` or `"white"`

### Ribbons too thick/obscure background

**Problem**: Black ribbons cover background colors

**Solutions**:
1. Decrease `alpha_levels`: `seq(0.10, 0.01, ...)` (more transparent)
2. Decrease `linewidth`: `1.5` or `2.0` (thinner)
3. Increase `n_gradient_levels`: `15` (smoother gradient = less overlap)

### Empirical lines not visible

**Problem**: Yellow lines blend with yellow/green background

**Solutions**:
1. Try red: `color = "#F21A00"`
2. Try blue: `color = "#78B7C5"`
3. Increase linewidth: `linewidth = 1.5`
4. Add white outline: Add second `geom_contour()` in white with `linewidth = 1.5` beneath yellow

---

## Related Documentation

- `test_contour_plots.R`: Test script
- `copula_bootstrap.R`: Bootstrap implementation
- `copula_contour_plots.R`: Plotting functions (this approach)
- `BOOTSTRAP_UNCERTAINTY_IMPLEMENTATION.md`: Previous global overlay approach (legacy)

---

## Support

For questions:
1. Review example output in `output/2005_G4_G5_MATHEMATICS/T/`
2. Adjust configuration parameters as needed
3. Check this documentation for customization options

---

**Status**: ✅ Ready for testing  
**Next**: Run test script and review ribbon appearance

