# Multi-Format Plot Export Workflow

## Overview

This directory contains a streamlined workflow for exporting R plots to multiple high-quality formats (PDF, SVG, PNG) with minimal code duplication. This approach is ideal for creating publication-ready figures that work seamlessly across print, web, and interactive documents.

## Files

- **`export_plot_utils.R`**: Core utility function for multi-format export
- **`Braun_Figure_3.R`**: Example implementation demonstrating the new workflow
- **`Braun_Figure_3.R.backup`**: Original 337-line script (for reference)

## Key Benefits

### 1. Dramatic Code Reduction
- **Before**: 337 lines with plot code repeated 3 times
- **After**: 125 lines with plot code written once
- **Reduction**: 63% fewer lines, much easier to maintain

### 2. DRY Principle (Don't Repeat Yourself)
- Plot logic defined in a single function
- Executed once per format automatically
- Changes propagate to all outputs consistently

### 3. AI-Friendly
- Single function call makes it trivial for AI assistants to generate multi-format exports
- Clear, documented API with sensible defaults
- Flexible enough for complex customization

### 4. Format Quality
- **PDF**: Print-quality vector graphics
- **SVG**: Web-optimized vector with font embedding (Noto Sans)
- **PNG**: Retina-ready raster (@2x by default at 200 DPI)

## Quick Start

### Basic Usage

```r
# Source the utility
source("export_plot_utils.R")

# Define your plot once
my_plot <- function() {
  plot(1:10, type = "b", pch = 19, col = "steelblue",
       main = "My Analysis", xlab = "X", ylab = "Y")
}

# Export to all three formats
export_plot_multi_format(
  plot_expr = my_plot,
  base_filename = "my_figure"
)

# Creates:
# - my_figure.pdf
# - my_figure.svg  
# - my_figure@2x.png
```

### Custom Path

```r
export_plot_multi_format(
  plot_expr = my_plot,
  base_filename = "/path/to/output/figures/analysis_2024"
)

# Creates files in the specified directory:
# - /path/to/output/figures/analysis_2024.pdf
# - /path/to/output/figures/analysis_2024.svg
# - /path/to/output/figures/analysis_2024@2x.png
```

### Selective Formats

```r
# Only export SVG and PNG (skip PDF)
export_plot_multi_format(
  plot_expr = my_plot,
  base_filename = "web_only_figure",
  formats = c("svg", "png")
)
```

### Advanced Customization

```r
export_plot_multi_format(
  plot_expr = complex_plot_function,
  base_filename = "figure",
  width = 8,
  height = 6,
  bg_transparent = FALSE,
  bg_color = "#F5F5F5",
  svg_fonts = list(sans = "Arial", serif = "Times", mono = "Courier"),
  png_res = 300,         # Higher resolution
  png_scale = 3,         # 3x retina
  png_suffix = "@3x"
)
```

## Function Parameters

### Core Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `plot_expr` | function/expression | *required* | Plot code to execute |
| `base_filename` | character | `"figure"` | Base name or full path for outputs |
| `width` | numeric | `7` | Plot width in inches |
| `height` | numeric | `7` | Plot height in inches |
| `formats` | character vector | `c("pdf", "svg", "png")` | Formats to export |

### Appearance Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `bg_transparent` | logical | `TRUE` | Use transparent background |
| `bg_color` | character | `"white"` | Background color if not transparent |

### SVG-Specific Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `svg_fonts` | list | Noto Sans (all) | Font mappings for SVG embedding |

### PNG-Specific Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `png_res` | numeric | `200` | Base resolution in DPI |
| `png_scale` | numeric | `2` | Scale multiplier for retina displays |
| `png_suffix` | character | `"@2x"` | Filename suffix for PNG |

### Other Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `verbose` | logical | `TRUE` | Print status messages |
| `...` | various | - | Additional device-specific parameters |

## Output Format Details

### PDF (.pdf)
- **Purpose**: Print-quality publications, LaTeX documents
- **Type**: Vector graphics (infinitely scalable)
- **Typical Size**: 5-15 KB for standard plots
- **Font Handling**: Uses system fonts (no embedding by default)

### SVG (.svg)
- **Purpose**: Web graphics, HTML reports, Quarto documents
- **Type**: Vector graphics (scalable, excellent for web)
- **Typical Size**: 10-30 KB for standard plots
- **Font Handling**: Embeds Noto Sans by default (configurable)
- **Advantage**: Works seamlessly in both HTML and Quarto
- **Note**: Font warnings are normal - fallback to Helvetica is acceptable

### PNG (@2x.png)
- **Purpose**: Retina displays, HTML embeds, presentations
- **Type**: Raster graphics (pixel-based)
- **Typical Size**: 300-800 KB for 2x retina quality
- **Resolution**: 200 DPI × 2 scale = 400 effective DPI
- **Dimensions**: 7 inches → 2800×2800 pixels for @2x

## AI Assistant Instructions

When using this utility with AI assistance, follow this pattern:

```r
# 1. Source the utility
source("export_plot_utils.R")

# 2. Define plot function with all plotting code
create_my_plot <- function() {
  # All your plot code here
  # Colors, data, axes, annotations, etc.
}

# 3. Single export call
export_plot_multi_format(
  plot_expr = create_my_plot,
  base_filename = "figure_name",
  width = 7,
  height = 7
)
```

**Key Points for AI:**
- Always define plot as a function for clarity
- Use descriptive function names (`create_scatter_plot`, `create_timeseries`, etc.)
- Call export function once per figure
- Customize only parameters that differ from defaults

## Package Requirements

The utility automatically checks for required packages:

```r
install.packages(c("svglite", "ragg"))
```

- **svglite**: For SVG export with font embedding
- **ragg**: For high-quality PNG rendering

## Troubleshooting

### Font Warnings
```
Warning: System font "Noto Sans" not found. Closest match is "Helvetica"
```
**Solution**: This is expected and acceptable. SVG will use Helvetica fallback, which is high quality.

### Figure Margins Too Large
**Solution**: This was fixed in the current version. If you see this, ensure you're using the latest `export_plot_utils.R`.

### Files Not Created
**Solution**: Check that:
1. You have write permissions to the output directory
2. The directory exists (create it if using full paths)
3. Required packages are installed

## Workflow Comparison

### Old Workflow (337 lines)
```r
# PDF section
pdf("figure.pdf", ...)
# ... 100 lines of plot code ...
dev.off()

# SVG section  
svglite("figure.svg", ...)
# ... 100 lines of plot code (DUPLICATED) ...
dev.off()

# PNG section
agg_png("figure.png", ...)
# ... 100 lines of plot code (DUPLICATED) ...
dev.off()
```

### New Workflow (125 lines)
```r
source("export_plot_utils.R")

create_plot <- function() {
  # ... 100 lines of plot code (ONCE) ...
}

export_plot_multi_format(
  plot_expr = create_plot,
  base_filename = "figure"
)
```

## Future Enhancements

Potential additions for future versions:

1. **Additional Formats**: EPS, TIFF, JPEG
2. **Theme Presets**: Pre-configured style bundles
3. **Batch Export**: Export multiple plots at once
4. **Plot Validation**: Check for accessibility issues
5. **Metadata Embedding**: Add author, date, license info
6. **Package Integration**: Bundle into an R package

## Examples in This Directory

See `Braun_Figure_3.R` for a complete working example that:
- Creates a complex NAEP trajectory plot
- Uses LaTeX math notation
- Includes custom colors and annotations
- Exports to all three formats with font embedding

Compare with `Braun_Figure_3.R.backup` to see the code reduction.

## License

This utility is provided as-is for use in the Betebenner-Braun research project and can be freely adapted for other projects.

## Questions or Issues?

If you encounter problems or have suggestions for improvements, please document them for future refinement.

---

**Created**: 2025-11-12  
**Version**: 1.0  
**Tested With**: R 4.x, svglite 2.x, ragg 1.x

