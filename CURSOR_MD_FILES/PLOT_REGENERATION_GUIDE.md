# Plot Regeneration Guide: Updating Visualizations Without Re-running Analysis

**Date:** 2025-10-25  
**Status:** ✅ ACTIVE GUIDE

## Quick Start: Regenerate All Plots

To regenerate all Step 1 plots without re-running the copula analysis:

```r
# From R console
source("STEP_1_Family_Selection/phase1_analysis.R")
```

**What this does:**
1. Reads existing CSV: `phase1_copula_family_comparison_all_datasets.csv`
2. Recalculates delta AIC and AIC weights (fast!)
3. Generates all plots and summaries
4. **Takes seconds, not hours**

## Why This Works

The analysis script (`phase1_analysis.R`) is **completely separated** from the computation scripts:

### **Computation Phase** (Slow - Hours)
- `phase1_family_selection.R` or `phase1_family_selection_parallel.R`
- Fits copula models to data
- Saves results to CSV files

### **Analysis/Plotting Phase** (Fast - Seconds)
- `phase1_analysis.R`
- **Reads** from CSV files
- Performs statistical summaries
- Creates all visualizations

## Workflow for Iterative Plot Refinement

### **1. Edit the Plot Code**

Open `STEP_1_Family_Selection/phase1_analysis.R` and modify the plotting section you want to refine.

**Example locations:**
- **Plot 1** (Selection frequency): Lines ~210-224
- **Plot 2** (AIC by span): Lines ~227-259
- **Plot 3** (Delta AIC distributions): Lines ~261-348
- **Plot 3b** (AIC weights): Lines ~350-369
- **Plot 4** (Tail dependence): Lines ~371-417
- **Plot 5** (Heatmap): Lines ~419-455

### **2. Regenerate Just That Plot**

You have two options:

#### **Option A: Run entire analysis script** (Recommended)
```r
source("STEP_1_Family_Selection/phase1_analysis.R")
```
- Regenerates all plots
- Ensures consistency
- Still very fast (seconds)

#### **Option B: Run just the plot section** (For rapid iteration)
```r
# Load libraries
require(data.table)
require(grid)

# Load results
results <- fread("STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv")

# Recalculate delta AIC
results[, delta_aic_vs_best := aic - min(aic), by = .(dataset_id, condition_id)]
results[, aic_weight := {
  exp_vals <- exp(-pmax(delta_aic_vs_best, 0) / 2)
  exp_vals / sum(exp_vals)
}, by = .(dataset_id, condition_id)]

# Set output directory
output_dir <- "STEP_1_Family_Selection/results/dataset_all"

# Define colors
colors <- c("#1976D2", "#2E7D32", "#D32F2F", "#F57C00", "#7B1FA2")
names(colors) <- c("gaussian", "t", "clayton", "gumbel", "frank")

# Now paste and run just the plot section you're working on
# For example, lines 261-348 for delta AIC plot
```

### **3. View the Updated Plot**

```r
# Open the PDF
system("open STEP_1_Family_Selection/results/dataset_all/phase1_delta_aic_distributions.pdf")
```

Or navigate to:
```
STEP_1_Family_Selection/results/dataset_all/phase1_*.pdf
```

### **4. Iterate**

- Edit plot code
- Re-run analysis script
- View updated plot
- Repeat until satisfied

## Current Plot Refinements

### **Delta AIC Distribution Plot** (Plot 3)

**Recent changes:**
- ✅ Horizontal orientation (copulas on y-axis)
- ✅ Log scale for delta AIC (x-axis)
- ✅ Manual axes with custom tick marks
- ✅ Right-justified family names
- ✅ mtext for labels and title
- ✅ Reference lines at Δ = 0, 10, 100
- ✅ Grid lines for easier reading
- ✅ Families ordered by median delta AIC

**Key features:**
```r
# Horizontal layout
horizontal = TRUE

# Log scale
log = "x"
delta_aic_plot = delta_aic_vs_best + 1  # Offset for log

# Manual axes
axes = FALSE
axis(1, at = ..., labels = ...)  # X-axis
axis(2, at = ..., labels = ..., hadj = 1)  # Y-axis, right-justified

# Labels via mtext
mtext("Copula Family", side = 2, line = 6.5, cex = 1.2)
mtext(expression(Delta * "AIC + 1 (log scale)"), side = 1, line = 3.5, cex = 1.2)

# Increased left margin for family names
par(mar = c(5, 8, 3, 2))
```

## Files Involved

### **Input (Read Only):**
- `STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv`
  - Contains all copula fitting results
  - 34 columns with full metadata

### **Script (Edit This):**
- `STEP_1_Family_Selection/phase1_analysis.R`
  - Modify plotting code here
  - Lines 203-455: All visualization code

### **Output (Regenerated):**
- `STEP_1_Family_Selection/results/dataset_all/phase1_*.pdf`
  - All plots
- `STEP_1_Family_Selection/results/dataset_all/phase1_decision.RData`
  - Decision for Step 2
- `STEP_1_Family_Selection/results/dataset_all/phase1_summary.txt`
  - Text summary

## Advanced: Regenerating Specific Plots Only

If you want to regenerate just one plot without running the entire script:

### **Example: Just Delta AIC Plot**

```r
# Setup (run once)
require(data.table)
results <- fread("STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv")
results[, delta_aic_vs_best := aic - min(aic), by = .(dataset_id, condition_id)]
output_dir <- "STEP_1_Family_Selection/results/dataset_all"
colors <- c("#1976D2", "#2E7D32", "#D32F2F", "#F57C00", "#7B1FA2")
names(colors) <- c("gaussian", "t", "clayton", "gumbel", "frank")

# Plot (copy from phase1_analysis.R lines 261-348)
pdf(file.path(output_dir, "phase1_delta_aic_distributions.pdf"), width = 10, height = 8)
# ... rest of plot code ...
dev.off()

# View
system("open STEP_1_Family_Selection/results/dataset_all/phase1_delta_aic_distributions.pdf")
```

## Tips for Plot Refinement

### **1. Color Palettes**
Current colors are defined at the top of the visualization section. Modify as needed:
```r
colors <- c("#1976D2", "#2E7D32", "#D32F2F", "#F57C00", "#7B1FA2")
names(colors) <- c("gaussian", "t", "clayton", "gumbel", "frank")
```

### **2. Figure Dimensions**
Adjust in the `pdf()` call:
```r
pdf(file.path(output_dir, "plot_name.pdf"), width = 10, height = 8)
```

### **3. Margins**
Control with `par(mar = c(bottom, left, top, right))`:
```r
par(mar = c(5, 8, 3, 2))  # Increased left for long labels
```

### **4. Font Sizes**
Use `cex` parameters:
- `cex.axis` - axis labels
- `cex.lab` - axis titles
- `cex.main` - main title
- `cex` in `mtext()` - custom text

### **5. Expression for Mathematical Notation**
```r
expression(Delta * "AIC")  # Δ AIC
expression(Delta * "AIC" + 1)  # Δ AIC + 1
expression(log[10](Delta * "AIC"))  # log₁₀(Δ AIC)
```

## Troubleshooting

### **Error: "object not found"**
Make sure you've loaded the data and defined variables:
```r
results <- fread("STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv")
results[, delta_aic_vs_best := aic - min(aic), by = .(dataset_id, condition_id)]
```

### **Error: "file not found"**
Check that the combined results CSV exists:
```r
file.exists("STEP_1_Family_Selection/results/dataset_all/phase1_copula_family_comparison_all_datasets.csv")
```

### **Plot looks wrong**
Reset graphics parameters:
```r
dev.off()  # Close current device
par(mfrow = c(1, 1))  # Reset to single plot
```

## When You DO Need to Re-run Analysis

You only need to re-run the copula fitting if:
- ❌ You changed the data
- ❌ You added/removed copula families
- ❌ You changed the conditions being tested
- ❌ You modified the copula fitting parameters

You do NOT need to re-run if:
- ✅ You're just changing plot aesthetics
- ✅ You're adjusting colors, labels, fonts
- ✅ You're changing plot dimensions
- ✅ You're adding reference lines
- ✅ You're modifying axis scales

## Summary

**Fast iteration workflow:**
1. Edit `phase1_analysis.R` plot code
2. Run `source("STEP_1_Family_Selection/phase1_analysis.R")`
3. View updated plots in `results/dataset_all/`
4. Repeat until publication-ready

**No need to re-run:**
- Family selection computation (hours)
- Copula fitting (computationally expensive)

**What gets regenerated:**
- All plots (seconds)
- Statistical summaries (seconds)
- Decision file (seconds)

---

**Remember:** The beauty of separating computation from visualization is that you can iterate on plot design quickly and efficiently! 🎨

