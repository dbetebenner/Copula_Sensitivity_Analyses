# Multi-Format Export - Quick Reference Card

## TL;DR

**All copula plots now automatically export to PDF, SVG, and PNG.** No code changes needed!

## Configuration (top of your test script)

```r
# === Default (All Formats) ===
EXPORT_FORMATS <- c("pdf", "svg", "png")  # Recommended for publications
EXPORT_DPI <- 300                          # Publication quality
EXPORT_VERBOSE <- FALSE                    # Quiet mode

# === PDF Only (Faster, Less Storage) ===
EXPORT_FORMATS <- c("pdf")

# === Web Optimized ===
EXPORT_FORMATS <- c("pdf", "svg")

# === Higher Quality PNG ===
EXPORT_DPI <- 600  # For large posters
```

## Output Files

```
Your plots will be saved as:
  figure_name.pdf       (print quality vector)
  figure_name.svg       (web-optimized vector)
  figure_name@2x.png    (high-res raster, 2x retina)
```

## File Sizes (Typical)

- PDF: 10-20 KB
- SVG: 20-30 KB  
- PNG: 300-600 KB

## Commands

```r
# Test the export system
source("STEP_1_Family_Selection/test_export_formats.R")

# Run your analyses (as usual)
source("STEP_1_Family_Selection/test_contour_plots.R")
source("STEP_1_Family_Selection/quick_test_uncertainty.R")
```

## Troubleshooting

**Missing package error?**
```r
install.packages(c("svglite", "ragg"))
```

**Too much storage?**
```r
EXPORT_FORMATS <- c("pdf")  # PDF only
```

**Want to see progress?**
```r
EXPORT_VERBOSE <- TRUE
```

## What Changed?

**Nothing in your workflow!** Just set your preferred formats and run your scripts.

---

📖 **Full Documentation**: See `MULTI_FORMAT_EXPORT_INTEGRATION.md`  
📋 **Implementation Details**: See `IMPLEMENTATION_SUMMARY.md`

