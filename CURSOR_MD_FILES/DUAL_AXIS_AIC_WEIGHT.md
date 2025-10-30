# Dual-Axis Enhancement: AIC Weights on Top Axis

**Date:** 2025-10-25  
**Status:** ✅ COMPLETE  
**Impact:** Enhanced interpretability with probability scale

## Summary

Added a **second axis** (top) showing **Relative AIC Weight** alongside the delta AIC scale. This provides readers with both:
- **Bottom axis**: Statistical difference (Δ AIC)
- **Top axis**: Probability interpretation (AIC weight)

## What Are AIC Weights?

AIC weights transform delta AIC into **relative probabilities**:

\[
w_i = e^{-\Delta_i/2}
\]

**Interpretation:** The probability that model *i* is the best model, relative to the reference.

## Tick Mark Selection

Strategically chosen delta values that span meaningful probability thresholds:

| Δ AIC | AIC Weight | Interpretation |
|-------|------------|----------------|
| 0 | 1.000 | Best model (100% reference) |
| 2 | 0.368 | ~37% as likely |
| 4 | 0.135 | ~14% as likely |
| 10 | 0.007 | <1% as likely |
| 20 | 5e-05 | Essentially zero |
| 50 | 3e-11 | Negligible |
| 100 | 2e-22 | Infinitesimal |
| 500 | 2e-109 | Impossible |

**Why these values?**
- Δ = 0, 2, 4: Burnham & Anderson thresholds
- Δ = 10: Traditional "essentially no support" cutoff
- Δ = 20, 50, 100, 500: Show how quickly probabilities become negligible

## Implementation Details

### **Top Axis Code** (Lines 316-329)

```r
# Add top axis (side = 3) showing AIC weights (relative probability)
# Select strategic delta values that span meaningful probability thresholds
delta_for_weights <- c(0, 2, 4, 10, 20, 50, 100, 500)
aic_weights <- exp(-delta_for_weights / 2)

axis(3,
     at = delta_for_weights + 1,  # Match the +1 offset used in plot
     labels = ifelse(aic_weights >= 0.001, 
                     sprintf("%.3f", aic_weights),
                     sprintf("%.0e", aic_weights)),  # Scientific notation for very small
     las = 1,
     cex.axis = 0.85,
     col.axis = "navy",
     col.ticks = "navy")
```

**Key features:**
- **8 tick marks** - Enough to show trend without cluttering
- **Unevenly spaced** - Matches the exponential decay of probabilities
- **Navy color** - Distinguishes from main (black) axis
- **Mixed formatting** - Regular decimals for ≥0.001, scientific notation for smaller
- **Offset handling** - Accounts for the +1 added to delta values

### **Axis Label** (Lines 362-367)

```r
mtext("Relative AIC Weight", 
      side = 3, 
      line = 2.5, 
      cex = 1.0,
      col = "navy")
```

### **Title Repositioning** (Lines 370-374)

```r
mtext(expression("Distribution of " ~ Delta * "AIC by Copula Family"), 
      side = 3, 
      line = 3.8,  # Moved up from 1.5 to make room for weight axis
      cex = 1.3, 
      font = 2)
```

## Visual Hierarchy

From top to bottom:
1. **Main title** (black, bold, line 3.8)
2. **"Relative AIC Weight"** label (navy, line 2.5)
3. **Weight axis ticks** (navy, 0.000-1.000)
4. **Plot area** (colored boxplots)
5. **Delta AIC axis ticks** (black, 0-999,999)
6. **"Δ AIC + 1 (log scale)"** label (black, line 3.5)

## Enhanced Interpretability

### **Example Readings:**

**t-copula (best fit):**
- Bottom: Δ AIC = 0
- Top: Weight = 1.000
- **Interpretation**: "Reference model, 100% relative probability"

**Gaussian copula:**
- Bottom: Δ AIC ≈ 148
- Top: Weight ≈ 10⁻³² (off scale, essentially zero)
- **Interpretation**: "Essentially zero probability of being best"

**Comonotonic copula:**
- Bottom: Δ AIC ≈ 2,000,000
- Top: Weight ≈ 0 (infinitesimal)
- **Interpretation**: "Statistically impossible to be correct"

## Publication Benefits

### **For Technical Readers:**
- Bottom axis provides precise Δ AIC values
- Familiar with AIC interpretation guidelines

### **For General Audience:**
- Top axis gives intuitive probability interpretation
- "This model has 37% relative probability" is clearer than "Δ AIC = 2"

### **For Reviewers:**
- Demonstrates thorough statistical reporting
- Shows both effect size and probability
- Makes extreme differences (comonotonic) immediately obvious

## Comparison to Single-Axis Plot

### **Before (Single Axis):**
Reader sees: *"Comonotonic has Δ AIC = 2,000,000"*  
Reader thinks: *"Is that a lot?"*

### **After (Dual Axis):**
Reader sees: *"Comonotonic has Δ AIC = 2,000,000 and weight ≈ 0"*  
Reader thinks: *"That model is impossible."*

## Technical Notes

### **Why Relative Weights?**
- We're showing **relative** to best model (which has weight = 1.0)
- Absolute weights would sum to 1.0 across ALL models
- Relative weights are more intuitive for comparing to best

### **Exponential Decay**
The relationship is exponential:
- Small differences in Δ AIC → Large changes in weight
- Δ AIC from 0→2: Weight drops 1.000 → 0.368 (63% drop)
- Δ AIC from 2→4: Weight drops 0.368 → 0.135 (63% drop again)

This is why we need **uneven spacing** - evenly spaced Δ values correspond to exponentially declining weights.

### **Scientific Notation**
For weights < 0.001, scientific notation prevents:
- "0.000" (ambiguous - how many zeros?)
- Very long decimal strings
- Confusion about magnitude

Instead: "2e-22" clearly shows the scale.

## Customization Options

### **Adjust Tick Marks:**
```r
# More ticks for detail
delta_for_weights <- c(0, 1, 2, 3, 4, 6, 8, 10, 15, 20, 30, 50, 100, 200, 500)

# Fewer ticks for simplicity
delta_for_weights <- c(0, 2, 10, 50, 100, 500)

# Focus on traditional thresholds
delta_for_weights <- c(0, 2, 4, 7, 10)
```

### **Change Color:**
```r
col.axis = "darkgreen"  # Or any color that contrasts with bottom axis
```

### **Adjust Label Positioning:**
```r
line = 2.0  # Closer to axis
line = 3.0  # Further from axis
```

## How to Regenerate

```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```

The dual-axis plot will be created at:
```
STEP_1_Family_Selection/results/dataset_all/phase1_delta_aic_distributions.pdf
```

## Files Modified

1. **`STEP_1_Family_Selection/phase1_analysis.R`**
   - Lines 316-329: Added top axis with AIC weights
   - Lines 362-367: Added axis label
   - Lines 370-374: Repositioned title

---

**Status:** Complete. Plot now features dual axes for comprehensive statistical interpretation! 📊

