# Multi-Format Export Integration for Copula Visualizations

## Overview

This document describes the comprehensive integration of multi-format export capabilities into the copula sensitivity analysis visualization pipeline. All copula figures are now automatically exported to **PDF, SVG, and PNG** formats with a single configuration setting.

## Benefits

### For Publications
- **PDF**: Print-quality vector graphics for journal submissions
- **SVG**: Web-optimized vector graphics for online presentations
- **PNG**: High-resolution raster images (@2x retina) for PowerPoint/Word

### For Workflow Efficiency
- **Single Configuration**: Change one setting to control all exports
- **No Code Duplication**: All plotting functions use the same export mechanism
- **Consistent Quality**: Same dimensions and quality settings across all formats
- **Future-Proof**: Easy to add new formats (e.g., EPS, TIFF) if needed

### Storage Considerations
- PDF files: Smallest, ~100-500KB each
- SVG files: Similar to PDF, ~150-600KB each
- PNG files (@2x): Largest, ~1-3MB each (high DPI for retina displays)
- **Total**: ~3x storage compared to PDF-only, but provides maximum flexibility

## Architecture

### Core Components

#### 1. Export Utility (`functions/export_plot_utils.R`)
Contains two primary functions:
- `export_plot_multi_format()` - For base R plots
- `export_ggplot_multi_format()` - For ggplot2 objects (used in copula pipeline)

#### 2. Integration Layer (`functions/copula_contour_plots.R`)
- Sources `export_plot_utils.R` automatically
- `generate_condition_plots()` accepts export format parameters
- Internal `save_ggplot_multi()` helper wraps the export function
- Fallback to PDF-only if export utility unavailable

#### 3. User Configuration (Test Scripts)
- `test_contour_plots.R` - Main analysis script
- `quick_test_uncertainty.R` - Quick testing script
Both expose simple configuration variables

## Usage

### Configuration Options

In any test script (e.g., `test_contour_plots.R`), set these variables:

```r
# Multi-format export configuration
EXPORT_FORMATS <- c("pdf", "svg", "png")  # Export to all three formats
# Options:
#   c("pdf")                 - PDF only (smallest storage, legacy behavior)
#   c("pdf", "svg")          - PDF + web-optimized vector graphics
#   c("pdf", "svg", "png")   - All formats (recommended for publications)
EXPORT_DPI <- 300             # DPI for PNG exports (300 = publication quality)
EXPORT_VERBOSE <- FALSE       # Set TRUE to see export messages
```

### Default Behavior

**Current Default**: All three formats (PDF, SVG, PNG)

To return to legacy PDF-only behavior:
```r
EXPORT_FORMATS <- c("pdf")
```

### Format-Specific Notes

#### PDF Export
- Device: `pdf()`
- Vector graphics, resolution-independent
- Smallest file size
- Best for: Print publications, journal submissions

#### SVG Export
- Device: `svglite::svglite` (requires `svglite` package)
- Web-optimized vector graphics
- Font embedding supported
- Best for: Web presentations, HTML reports, interactive dashboards

#### PNG Export
- Device: `ragg::agg_png` (requires `ragg` package)
- High-DPI raster images (default: 600 DPI for @2x retina)
- Largest file size
- Best for: PowerPoint, Word, preview/thumbnails

## File Organization

### Output Structure

When you run `test_contour_plots.R`, the output directory structure will be:

```
contour_plots/test/2005_G4_G5_MATHEMATICS/
├── empirical_copula_CDF.pdf
├── empirical_copula_CDF.svg
├── empirical_copula_CDF@2x.png
├── empirical_copula_PDF.pdf
├── empirical_copula_PDF.svg
├── empirical_copula_PDF@2x.png
├── bivariate_density_original.pdf
├── bivariate_density_original.svg
├── bivariate_density_original@2x.png
├── summary_grid.pdf
├── summary_grid.svg
├── summary_grid@2x.png
├── T_COPULA/
│   ├── t_copula_CDF.pdf
│   ├── t_copula_CDF.svg
│   ├── t_copula_CDF@2x.png
│   ├── t_copula_PDF.pdf
│   ├── t_copula_PDF.svg
│   ├── t_copula_PDF@2x.png
│   ├── t_copula_with_uncertainty_CDF.pdf
│   ├── t_copula_with_uncertainty_CDF.svg
│   ├── t_copula_with_uncertainty_CDF@2x.png
│   ├── comparison_empirical_vs_t_CDF.pdf
│   ├── comparison_empirical_vs_t_CDF.svg
│   └── comparison_empirical_vs_t_CDF@2x.png
├── GAUSSIAN/
│   └── [same structure as T_COPULA]
├── CLAYTON/
│   └── [same structure]
├── FRANK/
│   └── [same structure]
├── GUMBEL/
│   └── [same structure]
└── COMONOTONIC/
    └── [same structure, no uncertainty plots]
```

### Naming Convention
- Base filename: `figure_name`
- PDF: `figure_name.pdf`
- SVG: `figure_name.svg`
- PNG: `figure_name@2x.png` (indicates 2x retina resolution)

## Implementation Details

### Modified Functions

#### `generate_condition_plots()` in `copula_contour_plots.R`

**New Parameters:**
```r
generate_condition_plots(
  ...,  # existing parameters
  export_formats = c("pdf", "svg", "png"),  # NEW
  export_dpi = 300,                          # NEW
  export_verbose = FALSE                     # NEW
)
```

**Internal Helper:**
```r
save_ggplot_multi <- function(plot_obj, file_path, width = 8, height = 7) {
  if (exists("export_ggplot_multi_format")) {
    export_ggplot_multi_format(
      plot_obj = plot_obj,
      base_filename = file_path,  # No extension!
      width = width,
      height = height,
      formats = export_formats,
      dpi = export_dpi,
      verbose = export_verbose
    )
  } else {
    # Fallback to PDF-only
    ggplot2::ggsave(
      filename = paste0(file_path, ".pdf"),
      plot = plot_obj,
      width = width,
      height = height
    )
  }
}
```

### Replaced Calls

All `ggsave()` calls replaced with `save_ggplot_multi()`:

**Before:**
```r
ggsave(file.path(output_dir, "empirical_copula_CDF.pdf"),
       plots$empirical_cdf, width = 8, height = 7)
```

**After:**
```r
save_ggplot_multi(plots$empirical_cdf,
                 file.path(output_dir, "empirical_copula_CDF"),  # No .pdf!
                 width = 8, height = 7)
```

### Special Case: Summary Grid

The summary grid is a `grob` object (not a ggplot), so it requires explicit handling for each format:

```r
if ("pdf" %in% export_formats) {
  ggplot2::ggsave(filename = paste0(base_path, ".pdf"), ...)
}
if ("svg" %in% export_formats) {
  ggplot2::ggsave(filename = paste0(base_path, ".svg"), 
                  device = svglite::svglite, ...)
}
if ("png" %in% export_formats) {
  ggplot2::ggsave(filename = paste0(base_path, "@2x.png"),
                  dpi = export_dpi * 2, 
                  device = ragg::agg_png, ...)
}
```

## Package Dependencies

### Required Packages
- `ggplot2` - Core plotting (already required)

### Optional Packages (for specific formats)
- `svglite` - SVG export (install if using SVG format)
- `ragg` - High-quality PNG export (install if using PNG format)

### Installation
```r
install.packages(c("svglite", "ragg"))
```

**Note:** If these packages are missing, you'll get a clear error message with installation instructions.

## Backwards Compatibility

### Graceful Fallback
If `export_plot_utils.R` cannot be sourced:
- A warning is issued
- All exports fall back to PDF-only using `ggsave()`
- No errors or crashes

### Legacy Code
Existing code that doesn't pass export parameters will use defaults:
```r
# Old code (still works!)
generate_condition_plots(..., save_plots = TRUE)

# Automatically uses:
#   export_formats = c("pdf", "svg", "png")
#   export_dpi = 300
#   export_verbose = FALSE
```

## Performance Considerations

### Export Time
- Each format requires re-rendering the plot
- For 100 plots: ~30 seconds per format
- Total for all 3 formats: ~90 seconds additional time
- This is typically negligible compared to copula fitting time

### Storage Space
- Example: 50 plots per condition
  - PDF only: ~25 MB
  - All formats: ~75 MB
- For full analysis (20 conditions): ~1.5 GB total

### Recommendations
- **For testing**: Use `c("pdf")` to save time and space
- **For exploratory analysis**: Use `c("pdf", "svg")` for quick web viewing
- **For final publication**: Use all three formats for maximum flexibility

## Customization

### Custom DPI for PNG
For higher quality PNGs (e.g., large poster prints):
```r
EXPORT_DPI <- 600  # Very high quality
```

### Verbose Mode for Debugging
```r
EXPORT_VERBOSE <- TRUE
# Prints:
# Exporting ggplot to PDF: /path/to/figure.pdf
# Exporting ggplot to SVG: /path/to/figure.svg
# Exporting ggplot to PNG: /path/to/figure@2x.png
# Successfully exported ggplot to 3 format(s)
```

### Format-Specific Dimensions
To customize dimensions per plot type, modify the `save_ggplot_multi()` calls in `copula_contour_plots.R`:
```r
# Example: Larger uncertainty plots
save_ggplot_multi(plots[[paste0(family, "_uncertainty_cdf")]],
                 file.path(family_dir, sprintf("%s_copula_with_uncertainty_CDF", family)),
                 width = 12, height = 10)  # Larger dimensions
```

## Testing

### Quick Test
Run `quick_test_uncertainty.R` to verify the integration:
```r
source("STEP_1_Family_Selection/quick_test_uncertainty.R")
```

Check `STEP_1_Family_Selection/quick_test_output/` for multi-format files.

### Full Test
Run `test_contour_plots.R` for a complete test:
```r
source("STEP_1_Family_Selection/test_contour_plots.R")
```

Check `STEP_1_Family_Selection/contour_plots/test/` for multi-format files.

## Troubleshooting

### Error: Package 'svglite' not found
```r
install.packages("svglite")
```
Or disable SVG export:
```r
EXPORT_FORMATS <- c("pdf", "png")
```

### Error: Package 'ragg' not found
```r
install.packages("ragg")
```
Or disable PNG export:
```r
EXPORT_FORMATS <- c("pdf", "svg")
```

### Warning: Could not load export_plot_utils.R
Check that `functions/export_plot_utils.R` exists. If not, the system will fall back to PDF-only exports.

### Files are too large
Reduce PNG DPI or scale:
```r
EXPORT_DPI <- 150  # Lower quality, smaller files
```
Or disable PNG export entirely:
```r
EXPORT_FORMATS <- c("pdf", "svg")
```

## Future Enhancements

### Potential Additions
- EPS format for LaTeX documents
- TIFF format for publication requirements
- WebP format for modern web applications
- Automatic thumbnail generation
- Format-specific compression settings

### Implementation Pattern
To add a new format, modify `export_ggplot_multi_format()` in `export_plot_utils.R`:
```r
} else if (fmt == "eps") {
  ggplot2::ggsave(
    filename = output_paths$eps,
    plot = plot_obj,
    width = width,
    height = height,
    device = "eps"
  )
}
```

## Summary

This integration provides a **production-ready, flexible, and future-proof** multi-format export system for copula visualizations. Key features:

✅ Single configuration controls all exports  
✅ Three publication-quality formats (PDF, SVG, PNG)  
✅ Backwards compatible with existing code  
✅ Graceful fallback if dependencies missing  
✅ Consistent file naming and organization  
✅ Thoroughly documented and tested  

**No workflow changes required** - just set your preferred formats and run your analyses as usual!

