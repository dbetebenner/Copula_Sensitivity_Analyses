# Test Contour Plots - Standalone Script

## Overview

The `test_contour_plots.R` script has been updated to run **standalone** without requiring `master_analysis.R`. This allows you to quickly test and customize contour plot visualizations on a single condition.

## Changes Made

### 1. **Added Dataset Selection** (Line 56)
```r
DATASET_TO_TEST <- "dataset_1"  # Change this to test different datasets
```
You can now easily switch between:
- `"dataset_1"` - Vertically scaled data (State A)
- `"dataset_2"` - Non-vertically scaled data (State B)
- `"dataset_3"` - Transition data (State C)

### 2. **Added Automatic Data Loading** (Lines 66-93)
The script now:
- Automatically loads the selected dataset from .Rdata file
- Uses the path specified in `dataset_configs.R`
- Creates the `STATE_DATA_LONG` variable
- Validates that data loaded successfully

### 3. **Added Helper Function** (Lines 99-108)
Added `get_state_data()` function that was previously only in `master_analysis.R`

### 4. **Made Test Condition Dataset-Aware** (Lines 114-132)
The test condition now automatically uses:
- Valid grades from the selected dataset
- First available year
- First available content area

## How to Use

### Basic Usage

1. **Ensure data files exist** at paths specified in `dataset_configs.R`:
   ```r
   # Check dataset_configs.R for:
   # - dataset_1$local_path
   # - dataset_2$local_path  
   # - dataset_3$local_path
   ```

2. **Run from project root**:
   ```r
   source("STEP_1_Family_Selection/test_contour_plots.R")
   ```

3. **Find generated plots** in:
   ```
   STEP_1_Family_Selection/contour_plots/test/[year]_G[grade]_G[grade]_[content]/
   ```

### Testing Different Datasets

Edit line 56 in `test_contour_plots.R`:

```r
# Test Dataset 1 (Vertical Scale)
DATASET_TO_TEST <- "dataset_1"

# Test Dataset 2 (Non-Vertical Scale)
DATASET_TO_TEST <- "dataset_2"

# Test Dataset 3 (Transition)
DATASET_TO_TEST <- "dataset_3"
```

### Customizing Test Conditions

The script automatically selects reasonable defaults, but you can manually override by editing lines 126-132:

```r
test_condition <- list(
  grade_prior = 4,           # Change to desired prior grade
  grade_current = 5,         # Change to desired current grade
  year_prior = "2010",       # Change to desired year
  year_span = 1,             # Change to 2, 3, or 4 for longer spans
  content = "MATHEMATICS"    # Or "READING", "WRITING", "ELA"
)
```

### Customizing Plot Resolution

Line 253 controls plot quality:

```r
grid_size = 300  # Default: 300 (high quality), reduce to 100 for faster testing, increase to 500+ for publication
```

## Bootstrap Uncertainty Quantification (NEW!)

The script now includes **parametric bootstrap** to quantify parameter uncertainty and visualize it on contour plots. This addresses the question: "How confident are we in the fitted copula parameters?"

### What It Does

1. **Resamples** the observed student pairs with replacement (200 times by default)
2. **Refits** the best copula family on each bootstrap sample
3. **Evaluates** each fitted copula on a grid to get density surfaces
4. **Calculates** pointwise quantiles (e.g., 5th, 50th, 95th percentiles)
5. **Visualizes** uncertainty as:
   - **Confidence bands**: Blue/red dashed lines showing upper/lower bounds
   - **Uncertainty heatmap**: Color gradient showing coefficient of variation
   - **Quantile comparison**: Side-by-side plots of lower/point/upper estimates

### Configuration

Edit lines 279-281 in `test_contour_plots.R`:

```r
N_BOOTSTRAP <- 200        # Number of bootstrap samples (50-500 typical)
USE_PARALLEL <- TRUE      # Enable parallel processing (Mac/Linux only)
N_CORES <- NULL           # NULL = auto-detect (uses detectCores() - 1)
```

**Performance:**
- **Sequential** (USE_PARALLEL = FALSE): ~2-3 minutes for 200 bootstraps
- **Parallel** (USE_PARALLEL = TRUE): ~20-40 seconds on 8-core machine

### Output Files

Three new PDF files are generated:

1. **`[family]_copula_uncertainty_bands.pdf`** ⭐ RECOMMENDED
   - Shows point estimate (black solid line)
   - Shows 90% confidence bounds (blue/red dashed lines)
   - Wider bands = greater uncertainty in that region

2. **`[family]_copula_uncertainty_heatmap.pdf`**
   - Background color shows coefficient of variation
   - White contours show point estimate
   - Useful for identifying regions with high uncertainty

3. **`[family]_copula_uncertainty_quantiles.pdf`**
   - Three panels: Lower 5% | Point Estimate | Upper 95%
   - Shows full distribution of plausible copulas

### Interpreting Uncertainty

- **Narrow bands** (low CV): Parameters are well-identified, contours are stable
- **Wide bands** (high CV): Parameter uncertainty is substantial
- **Uniform bands**: Uncertainty is similar across the copula surface
- **Variable bands**: Some regions (e.g., tails) have more uncertainty than others

Typically, you'll see **narrower bands in the center** (where most data is) and **wider bands in the tails** (sparse data).

## Expected Output

### Console Output (Updated)
```
====================================================================
TEST: COPULA CONTOUR PLOT VISUALIZATION
====================================================================

Working directory: /path/to/Copula_Sensitivity_Analyses 
Loading functions...
Dataset: Dataset 1 (Vertical Scale)
  Description: Multi-year vertically scaled state assessment

Loading state data from file...
  Loaded: Copula_Sensitivity_Data_Set_1
  Rows: 245891

Test Condition:
  Grade: 4 -> 5
  Year: 2005 -> 2006
  Content: MATHEMATICS

Creating longitudinal pairs...
  Number of pairs: 12543

Fitting copulas...
  Best family: t
  Empirical Kendall's tau: 0.687

Model comparison:
        Family   AIC   BIC Delta_AIC
t            t -2134 -2119       0.0
gaussian  gaus -2098 -2088      36.0
frank    frank -2076 -2071      58.0
...

Generating visualization plots...

====================================================================
BOOTSTRAP UNCERTAINTY QUANTIFICATION
====================================================================

Running parametric bootstrap to quantify parameter uncertainty...
  Number of bootstrap samples: 200
  Parallel processing: TRUE
  Cores to use: 7

Focusing bootstrap on best-fitting family: t

Running 200 bootstrap copula estimations...
  Sampling method: paired
  Sample sizes: n_prior = 12543, n_current = 12543
  Parallel processing: ENABLED (7 cores on Unix)

Bootstrap copula estimation complete!
  Successful iterations: 200 of 200

Bootstrap completed in 35.2 seconds

Generating uncertainty visualization plots...

  Evaluating 200 bootstrap copulas on 300 x 300 grid...
  Successfully evaluated 200 of 200 bootstrap samples
  Saved: t_copula_uncertainty_bands.pdf
  Evaluating 200 bootstrap copulas on 300 x 300 grid...
  Successfully evaluated 200 of 200 bootstrap samples
  Saved: t_copula_uncertainty_heatmap.pdf
  Evaluating 200 bootstrap copulas on 300 x 300 grid...
  Successfully evaluated 200 of 200 bootstrap samples
  Saved: t_copula_uncertainty_quantiles.pdf

====================================================================
VISUALIZATION TEST COMPLETE
====================================================================

Generated plots have been saved to:
   STEP_1_Family_Selection/contour_plots/test/2005_G4_G5_MATHEMATICS 

Files created:
  - empirical_copula_density.pdf
  - gaussian_copula.pdf
  - t_copula.pdf
  - clayton_copula.pdf
  - gumbel_copula.pdf
  - frank_copula.pdf
  - comparison_empirical_vs_t.pdf
  - bivariate_density_original.pdf
  - summary_grid.pdf
  - t_copula_uncertainty_bands.pdf ⭐ NEW
  - t_copula_uncertainty_heatmap.pdf ⭐ NEW
  - t_copula_uncertainty_quantiles.pdf ⭐ NEW

Key plots to review:
  STANDARD PLOTS:
    1. empirical_copula_density.pdf - Shows actual dependence structure
    2. [family]_copula.pdf - Shows fitted parametric copulas
    3. comparison_empirical_vs_[best].pdf - Highlights regions of misfit
    4. bivariate_density_original.pdf - Original score distribution
    5. summary_grid.pdf - All key plots in one figure

  UNCERTAINTY QUANTIFICATION PLOTS (NEW!):
    6. [best]_copula_uncertainty_bands.pdf - Confidence bands (RECOMMENDED)
    7. [best]_copula_uncertainty_heatmap.pdf - Uncertainty as heatmap
    8. [best]_copula_uncertainty_quantiles.pdf - Side-by-side comparison

Bootstrap summary:
  Successful samples: 200 of 200
  Elapsed time: 35.2 seconds
  Speedup from parallelization: ~ 4.9 x
```

### Generated Plots

**Standard Copula Diagnostics:**
1. **`empirical_copula_density.pdf`** - Shows actual dependence structure from data
2. **`[family]_copula.pdf`** - Shows fitted parametric copulas (6 families)
3. **`comparison_empirical_vs_[best].pdf`** - Highlights regions of misfit
4. **`bivariate_density_original.pdf`** - Original score distribution
5. **`summary_grid.pdf`** - All key plots in one figure (best for quick review)

**Bootstrap Uncertainty Quantification:** ⭐ NEW
6. **`[best]_copula_uncertainty_bands.pdf`** - Point estimate with 90% confidence bands (RECOMMENDED)
7. **`[best]_copula_uncertainty_heatmap.pdf`** - Uncertainty shown as color gradient (CV)
8. **`[best]_copula_uncertainty_quantiles.pdf`** - Side-by-side: lower/point/upper quantiles

## Troubleshooting

### Error: "Data file not found"
- Check paths in `dataset_configs.R`
- Ensure .Rdata files exist at specified locations
- Update `local_path` in `dataset_configs.R` if files are elsewhere

### Error: "Insufficient data for test condition"
- The selected condition has < 100 student pairs
- Try a different year or grade combination
- Check data availability with: `table(STATE_DATA_LONG$YEAR, STATE_DATA_LONG$GRADE)`

### Warning: "no visible binding for WORKSPACE_OBJECT_NAME"
- These are expected R linter warnings
- They do not affect functionality
- Safe to ignore

## Next Steps

After successfully generating test plots:

1. **Review plot quality** - Check if contours are smooth and informative
2. **Customize aesthetics** - Edit `functions/copula_contour_plots.R` for styling
3. **Test with different conditions** - Try 2-year and 3-year spans
4. **Run full analysis** - Use `phase1_family_selection_parallel.R` for all conditions

## Related Files

- `dataset_configs.R` - Dataset paths and metadata
- `functions/copula_contour_plots.R` - Plotting functions (customize here)
- `test_parallel_subset.R` - Test parallel processing on multiple conditions
- `phase1_family_selection_parallel.R` - Full analysis with all conditions

