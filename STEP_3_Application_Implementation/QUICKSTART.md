====================================================================
EXPERIMENT 5: QUICK START GUIDE
====================================================================

WHAT IS EXPERIMENT 5?
---------------------
The methodological validation that proves your two-stage transformation
approach is correct and identifies which smoothing methods work for Phase 2.

WHY RUN IT?
-----------
1. Validates that Phase 1 was done correctly (empirical ranks)
2. Identifies which smoothing methods are "good enough" for Phase 2
3. Provides publication-ready figures and tables
4. Justifies your entire methodological framework

PREREQUISITES
-------------
✓ Phase 1 completed (phase1_family_selection.R and phase1_analysis.R)
✓ t-copula won Phase 1 (not Frank!)
✓ Colorado_Data_LONG loaded
✓ ~1 hour of computational time available

====================================================================
RUNNING EXPERIMENT 5 (Two Simple Commands)
====================================================================

OPTION 1: Interactive (Recommended for first run)
--------------------------------------------------
cd /Users/conet/Research/Graphics_Visualizations/CDF_Investigations

R
# In R:
source("experiments/exp_5_transformation_validation.R")
source("experiments/exp_5_visualizations.R")

OPTION 2: Batch Mode (For EC2 or overnight runs)
-------------------------------------------------
cd /Users/conet/Research/Graphics_Visualizations/CDF_Investigations

# Capture output to log file
Rscript experiments/exp_5_transformation_validation.R > exp5_validation_log.txt 2>&1
Rscript experiments/exp_5_visualizations.R > exp5_visualization_log.txt 2>&1

# Check progress
tail -f exp5_validation_log.txt

====================================================================
WHAT TO EXPECT
====================================================================

TIMELINE:
---------
- Validation: ~30-45 minutes (tests 15 methods)
- Visualization: ~5-10 minutes (generates 20+ figures)
- Total: ~40-60 minutes

CONSOLE OUTPUT (validation):
----------------------------
You'll see progress for each method:

--------------------------------------------------------------------
Method 1 of 15: Empirical Ranks (n+1)
--------------------------------------------------------------------

Computing diagnostics...
Fitting copulas...

RESULTS SUMMARY:
  Classification: EXCELLENT
  Suitable for Phase 2: TRUE
  K-S p-value (combined): 0.6234
  Best copula: t (CORRECT)
  Tau bias: 0.0000
  ...

[Repeats for all 15 methods]

FINAL OUTPUT (validation):
--------------------------
====================================================================
PHASE 2 RECOMMENDATIONS:
====================================================================

The following 5 methods are SUITABLE for Phase 2:

  - Empirical Ranks (n+1)
  - I-spline (49 knots)
  - I-spline (Tail-Aware, 15 knots)
  - Q-spline (Quantile Function)
  - Kernel (Gaussian, rule-of-thumb)

OUTPUT FILES:
-------------
STEP_2_Transformation_Validation/results/exp5_transformation_validation_summary.csv     (Quick reference)
STEP_2_Transformation_Validation/results/exp5_transformation_validation_full.RData      (Complete results)
STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/*.pdf           (20+ figures)

====================================================================
WHAT TO CHECK
====================================================================

1. EMPIRICAL RANKS SHOULD PASS
   Look for: Classification: EXCELLENT
   If not: Something is wrong, review Phase 1 results

2. I-SPLINE (4 KNOTS) SHOULD FAIL
   Look for: Classification: UNACCEPTABLE or MARGINAL
   Look for: Best copula: frank (WRONG)
   This validates the bug we found!

3. AT LEAST 2-3 METHODS SHOULD PASS
   Look for: Classification: ACCEPTABLE or EXCELLENT
   Look for: Best copula: t (CORRECT)
   These are your Phase 2 candidates

4. KEY FIGURES TO REVIEW
   - uniformity_forest_plot.pdf (Which methods have uniform U,V?)
   - tradeoff_space.pdf (Which methods are in top-right quadrant?)
   - ispline_4knots_dashboard.pdf (See WHY it fails)
   - empirical_n_plus_1_dashboard.pdf (See GOLD STANDARD)

====================================================================
INTERPRETING RESULTS
====================================================================

CLASSIFICATION MEANINGS:
------------------------
EXCELLENT    = Pass all 3 tiers → Use in Phase 2 (preferred)
ACCEPTABLE   = Pass Tier 1+2 → Use in Phase 2 (ok)
MARGINAL     = Pass Tier 1 only → Use with caution
UNACCEPTABLE = Fail Tier 1 → Do NOT use

TIER 1 (Critical - Must Pass):
- Selects correct copula (t-copula, not Frank)
- Tau within ±5% of empirical
- Tail structure preserved

TIER 2 (Important - Should Pass):
- K-S test p > 0.01 (pseudo-observations uniform)
- CvM < 0.05
- No excessive ties

TIER 3 (Nice to Have):
- K-S test p > 0.05 (standard threshold)
- Invertible
- Fast

====================================================================
QUICK REVIEW COMMANDS (After Run Completes)
====================================================================

# Load summary table
results <- fread("results/exp5_transformation_validation_summary.csv")

# How many methods passed?
table(results$classification)

# Which methods are suitable for Phase 2?
results[use_in_phase2 == TRUE, .(label, classification, ks_pvalue)]

# Which methods selected the WRONG copula?
results[copula_correct == FALSE, .(label, best_copula)]

# Show best methods by K-S p-value
results[order(-ks_pvalue), .(label, classification, ks_pvalue, tau_bias)]

# Load full results for deep dive
load("results/exp5_transformation_validation_full.RData")
names(all_results)  # List all methods

# Examine a specific method
method_name <- "ispline_4knots"
all_results[[method_name]]$classification$details
all_results[[method_name]]$uniformity

====================================================================
TROUBLESHOOTING
====================================================================

ISSUE: All methods fail (even empirical ranks)
CAUSE: Data problem or Phase 1 incorrect
ACTION: 
  - Check Phase 1 results (should be t-copula winning)
  - Verify Colorado_Data_LONG loaded correctly
  - Review pairs_full (should have ~58K observations)

ISSUE: Script crashes on a specific method
CAUSE: Method implementation error or data edge case
ACTION:
  - Script will skip failed methods automatically
  - Check console output for ERROR messages
  - Review which method failed and why

ISSUE: All I-spline methods fail
CAUSE: Possible splines2 package version issue
ACTION:
  - Check: packageVersion("splines2")
  - Should be: >= 0.4.0
  - Update if needed: install.packages("splines2")

ISSUE: Figures look strange
CAUSE: Too many/few methods or plotting issue
ACTION:
  - Check number of methods in all_results
  - Review par() settings in exp_5_visualizations.R
  - Try regenerating individual figure type

====================================================================
NEXT STEPS AFTER EXPERIMENT 5
====================================================================

1. REVIEW RESULTS
   - Check classifications
   - Review key figures
   - Verify empirical ranks = EXCELLENT
   - Verify I-spline (4 knots) = UNACCEPTABLE

2. SELECT PHASE 2 METHOD
   Choose from methods with use_in_phase2 = TRUE
   
   Recommendation:
   - For invertibility → Q-spline
   - For accuracy → I-spline (Tail-Aware, 15 knots)
   - For simplicity → Empirical ranks (no analytic inverse)

3. UPDATE PHASE 2 EXPERIMENTS
   Modify experiments 1-4 to use selected method
   
   If using Q-spline:
   - Replace create_ispline_framework() with fit_qspline()
   - Update transformation calls

4. GENERATE PAPER MATERIALS
   - Export summary_table to LaTeX
   - Select 2-3 key figures for main text
   - Move rest to supplementary
   - Draft methods section text

5. RUN PHASE 2 EXPERIMENTS
   Now with validated transformation method!

====================================================================
FOR YOUR PAPER
====================================================================

Key Finding to Report:
----------------------
"Marginal transformation method validation (N=15 methods) revealed
that insufficient smoothing flexibility (I-spline with <20 knots)
caused non-uniform pseudo-observations (K-S p<0.001) and incorrect
copula selection (Frank vs. t, ΔAIC=2,423), validating our two-stage
approach: empirical ranks for family selection and carefully validated
smoothing for invertible applications."

Tables to Include:
------------------
Table 1: Method classification summary (results[, 1:8])
Table S1: Complete diagnostic metrics (full summary_table)

Figures to Include:
-------------------
Figure 1 (Main): tradeoff_space.pdf
Figure 2 (Main): uniformity_forest_plot.pdf
Figure S1 (Supp): Key methods comparison
Figure S2 (Supp): ispline_4knots_dashboard.pdf (shows the problem)
Figure S3 (Supp): empirical_n_plus_1_dashboard.pdf (gold standard)

====================================================================
READY TO RUN!
====================================================================

Current status of Phase 1: ⏳ Running...

When Phase 1 completes:
1. Review Phase 1 results
2. If t-copula won → Run Experiment 5
3. If Frank won → Something wrong, investigate

Commands to run Experiment 5:
cd /Users/conet/Research/Graphics_Visualizations/CDF_Investigations
R
source("experiments/exp_5_transformation_validation.R")
source("experiments/exp_5_visualizations.R")

Estimated time: 40-60 minutes
Estimated review: 1-2 hours

This will be the centerpiece of your methodological contribution!

====================================================================

