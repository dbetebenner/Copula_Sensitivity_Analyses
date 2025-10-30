# Plot Customization: Wes Anderson Color Palette & Pretty Labels

**Date:** 2025-10-25  
**Status:** ✅ COMPLETE  
**Impact:** Enhanced visual aesthetics for publication

## Summary

Updated the delta AIC distribution plot (Plot 3) with:
1. **Wes Anderson Zissou1 color palette** - Beautiful gradient from best to worst fit
2. **Pretty copula family labels** - Proper capitalization and formatting
3. **Enhanced margins** - More space for longer family names

## Changes Made

### 1. Added wesanderson Package (Line 8)

```r
require(data.table)
require(grid)
require(wesanderson)  # For Zissou1 color palette
```

**Installation (if needed):**
```r
install.packages("wesanderson")
```

### 2. Pretty Family Name Labels (Lines 278-292)

Created a mapping for professional-looking copula names:

```r
pretty_names <- c(
  "t" = "t",
  "t_df15" = "t (df = 15)",
  "t_df10" = "t (df = 10)",
  "t_df5" = "t (df = 5)",
  "gaussian" = "Gaussian",
  "frank" = "Frank",
  "clayton" = "Clayton",
  "gumbel" = "Gumbel",
  "comonotonic" = "Comonotonic"
)
```

**Key improvements:**
- ✅ Proper names capitalized (Gaussian, Frank, Clayton, Gumbel, Comonotonic)
- ✅ T-copula variants formatted as "t (df = 15)" instead of "t_df15"
- ✅ Standard t-copula remains lowercase "t" (mathematical convention)

### 3. Zissou1 Color Palette (Lines 294-296)

```r
# Generate Zissou1 color palette (reversed for best->worst gradient)
n_families <- length(family_order)
zissou_colors <- rev(wes_palette("Zissou1", n_families, type = "continuous"))
```

**Color gradient:**
- Uses `type = "continuous"` for smooth color transitions
- `rev()` reverses the palette so best fit = cooler colors, worst fit = warmer colors
- Automatically adjusts to number of families (9 in current analysis)

**Zissou1 palette characteristics:**
- Named after "The Life Aquatic with Steve Zissou"
- Gradient: Cool blues/teals → Warm reds/oranges
- Professional and publication-ready
- Colorblind-friendly gradient

### 4. Updated Margins (Line 267)

```r
par(mar = c(5, 10, 3, 2))  # Increased left margin from 8 to 10
```

**Why:** Longer labels like "t (df = 15)" need more horizontal space than "t_df15"

### 5. Applied Colors to Boxplot (Line 302)

```r
boxplot(...
        col = zissou_colors,  # Changed from colors[family_order]
        ...)
```

### 6. Updated Y-axis Labels (Line 320)

```r
axis(2, 
     at = 1:length(family_order),
     labels = family_labels,  # Changed from family_order
     las = 1,
     hadj = 1,  # Right justify
     cex.axis = 1.0,
     tick = FALSE)
```

## Visual Impact

### **Before:**
- Generic color scheme
- Raw family names: "t_df15", "gaussian", "comonotonic"
- Less professional appearance

### **After:**
- Beautiful Zissou1 gradient (cool → warm = best → worst)
- Professional labels: "t (df = 15)", "Gaussian", "Comonotonic"
- Publication-ready aesthetics

## Example Color Ordering (Best → Worst)

Assuming typical ordering by median delta AIC:

| Rank | Family | Color | Delta AIC |
|------|--------|-------|-----------|
| 1 (Best) | t | Cool teal/blue | 0 |
| 2 | t (df = 15) | Blue-teal | ~72 |
| 3 | Gaussian | Teal | ~148 |
| 4 | t (df = 10) | Teal-green | ~301 |
| 5 | Frank | Green-yellow | ~1,467 |
| 6 | t (df = 5) | Yellow-orange | ~1,524 |
| 7 | Gumbel | Orange | ~10,355 |
| 8 | Clayton | Red-orange | ~28,524 |
| 9 (Worst) | Comonotonic | Warm red | ~2,238,399 |

The color gradient **visually reinforces** the statistical story: cooler colors = better fit, warmer colors = worse fit.

## How to Regenerate

Simply run:
```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```

The script will:
1. Load the wesanderson package
2. Generate the Zissou1 palette
3. Create pretty labels
4. Produce the updated plot

**Time:** Seconds (no copula refitting needed)

## Customization Options

### **Try Different Palettes**

Wes Anderson offers many options:

```r
# Royal Tenenbaums
zissou_colors <- rev(wes_palette("Royal1", n_families, type = "continuous"))

# Darjeeling Limited
zissou_colors <- rev(wes_palette("Darjeeling1", n_families, type = "continuous"))

# Moonrise Kingdom
zissou_colors <- rev(wes_palette("Moonrise2", n_families, type = "continuous"))

# Fantastic Mr. Fox
zissou_colors <- rev(wes_palette("FantasticFox1", n_families, type = "continuous"))

# Grand Budapest Hotel
zissou_colors <- rev(wes_palette("GrandBudapest1", n_families, type = "continuous"))
```

View all palettes:
```r
library(wesanderson)
names(wes_palettes)
```

### **Adjust Capitalization**

Modify the `pretty_names` mapping:

```r
# All caps for emphasis
"gaussian" = "GAUSSIAN"

# Title case
"frank" = "Frank Copula"

# Abbreviated
"t_df15" = "t (15)"
```

### **Change Color Direction**

Remove `rev()` to flip the gradient:
```r
# Warm colors for best fit, cool for worst
zissou_colors <- wes_palette("Zissou1", n_families, type = "continuous")
```

## Package Dependencies

**New dependency:**
```r
install.packages("wesanderson")
```

**All dependencies for phase1_analysis.R:**
- `data.table` - Data manipulation
- `grid` - Graphics functions
- `wesanderson` - Color palettes

## Files Modified

1. **`STEP_1_Family_Selection/phase1_analysis.R`**
   - Line 8: Added `require(wesanderson)`
   - Lines 267, 278-296, 302, 320: Updated plot code

## Next Steps

### **For Publication:**
1. Generate the plot with these settings
2. Review colors and labels
3. Adjust palette if needed for journal requirements
4. Export at appropriate resolution (default PDF is vector, perfect for publication)

### **For Presentations:**
Consider alternative palettes:
- **Zissou1**: Professional, good for papers
- **Darjeeling1**: High contrast, good for slides
- **Royal1**: Sophisticated, good for formal presentations
- **Moonrise2**: Soft, good for posters

## Notes

### **Why Zissou1?**
- Professional appearance
- Clear gradient structure
- Colorblind-accessible gradient
- Widely recognized in data visualization community
- Named after a Wes Anderson film (cultural reference)

### **Why rev()?**
- Conventional: Cool colors (blue/teal) = good/positive
- Conventional: Warm colors (red/orange) = bad/negative
- Matches intuitive color psychology
- Reinforces the statistical story visually

### **Mathematical Conventions**
- Standard t-copula stays lowercase "t" (mathematical symbol)
- Named copulas capitalized (Frank, Clayton, Gumbel)
- Descriptive term capitalized (Gaussian, Comonotonic)

---

**Status:** Complete. Plot now features beautiful Zissou1 gradient with professional labels! 🎨

