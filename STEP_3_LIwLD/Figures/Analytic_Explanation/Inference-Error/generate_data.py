#!/usr/bin/env python3
"""
generate_data.py - Generate panel-ready data files for Error Budget infographic.

Python fallback for step3_export_data.R when R is not available.
Generates identical data/ files using numpy + scipy.
"""

import os
import numpy as np
from scipy import stats

np.random.seed(20260312)

data_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(data_dir, exist_ok=True)

def write_dat(x, y, filename):
    path = os.path.join(data_dir, filename)
    with open(path, "w") as f:
        for xi, yi in zip(x, y):
            f.write(f"{xi} {yi}\n")
    print(f"   {filename}")


###############################################################################
# Configuration
###############################################################################

true_m = 0.39
true_kappa = 18
true_alpha = true_kappa * true_m
true_beta_ = true_kappa * (1 - true_m)
true_mean_sgpc = true_m * 100

copula_rho = 0.72
copula_df = 8
n_main = 3500
bridge_bias = 0.4
bridge_mean_sgpc = true_mean_sgpc + bridge_bias
n_conditions = 25


###############################################################################
# Panel A: Truth benchmark density
###############################################################################

print("Panel A (truth benchmark)...")
p_grid = np.linspace(0.001, 0.999, 500)

d_true = stats.beta.pdf(p_grid, true_alpha, true_beta_)
write_dat(np.round(p_grid * 100, 4), np.round(d_true, 6), "panel_A_density_true.dat")

write_dat(np.round(p_grid * 100, 4), np.round(np.ones(len(p_grid)), 4),
          "panel_A_density_uniform.dat")

bridge_m = bridge_mean_sgpc / 100
bridge_kappa = true_kappa + 0.2
bridge_alpha = bridge_kappa * bridge_m
bridge_beta = bridge_kappa * (1 - bridge_m)
d_bridge = stats.beta.pdf(p_grid, bridge_alpha, bridge_beta)
write_dat(np.round(p_grid * 100, 4), np.round(d_bridge, 6), "panel_A_density_bridge.dat")


###############################################################################
# Panel B: Bridge accuracy across conditions
###############################################################################

print("Panel B (bridge accuracy)...")
true_means_low = np.sort(np.random.uniform(25, 35, 8))
true_means_mid = np.sort(np.random.uniform(35, 55, 9))
true_means_high = np.sort(np.random.uniform(55, 65, 8))
true_means_conditions = np.concatenate([true_means_low, true_means_mid, true_means_high])
true_means_conditions.sort()

bridge_errors = np.array([
    (50 - tm) * 0.015 + np.random.normal(0, 0.8)
    for tm in true_means_conditions
])
bridge_estimates = true_means_conditions + bridge_errors

write_dat(np.round(true_means_conditions, 2), np.round(bridge_estimates, 2),
          "panel_B_accuracy_pairs.dat")

# KDE for bridge error density
from scipy.stats import gaussian_kde
kde = gaussian_kde(bridge_errors, bw_method="silverman")
x_err = np.linspace(bridge_errors.min() - 2, bridge_errors.max() + 2, 256)
y_err = kde(x_err)
write_dat(np.round(x_err, 4), np.round(y_err, 6), "panel_B_error_density.dat")

mean_bridge_error = np.mean(bridge_errors)
median_bridge_error = np.median(bridge_errors)
mae_bridge = np.mean(np.abs(bridge_errors))
max_abs_error = np.max(np.abs(bridge_errors))
rmse_bridge = np.sqrt(np.mean(bridge_errors**2))


###############################################################################
# Panel C: Sampling worlds (minimal data)
###############################################################################

print("Panel C (sampling worlds)...")
paired_u = np.random.uniform(0.1, 0.9, 10)
paired_v = np.clip(paired_u + np.random.normal(-0.05, 0.15, 10), 0.02, 0.98)
indep_u = np.random.uniform(0.1, 0.9, 10)
indep_v = np.random.uniform(0.15, 0.85, 10)

write_dat(np.round(paired_u, 4), np.round(paired_v, 4), "panel_C_paired_sample.dat")
write_dat(np.round(indep_u, 4), np.round(indep_v, 4), "panel_C_independent_sample.dat")


###############################################################################
# Panel D: Precision operating curves
###############################################################################

print("Panel D (precision curves)...")
N_grid = np.concatenate([
    np.arange(50, 525, 25),
    np.arange(600, 1050, 50),
    np.arange(1200, 2200, 200),
    np.arange(2500, 5500, 500),
])

k_paired = 20.0
k_indep = 34.2
ci_width_paired = 3.92 * k_paired / np.sqrt(N_grid) * (1 + 2.5 / np.sqrt(N_grid))
ci_width_indep = 3.92 * k_indep / np.sqrt(N_grid) * (1 + 4.0 / np.sqrt(N_grid))

write_dat(N_grid.astype(int), np.round(ci_width_paired, 3), "panel_D_precision_paired.dat")
write_dat(N_grid.astype(int), np.round(ci_width_indep, 3), "panel_D_precision_indep.dat")

mae_paired = ci_width_paired * 0.38
mae_indep = ci_width_indep * 0.38
write_dat(N_grid.astype(int), np.round(mae_paired, 3), "panel_D_mae_paired.dat")
write_dat(N_grid.astype(int), np.round(mae_indep, 3), "panel_D_mae_indep.dat")


###############################################################################
# Panel E: Total uncertainty budget
###############################################################################

print("Panel E (total uncertainty)...")
subgroup_estimates = [32.5, 42.0, 50.5, 58.0, 67.5]
subgroup_truth = [32.0, 41.5, 50.0, 57.5, 68.0]
stress_test_hw = [1.2, 0.8, 0.5, 0.8, 1.3]

idx500 = np.where(N_grid == 500)[0]
sampling_hw_indep = ci_width_indep[idx500[0]] / 2 if len(idx500) > 0 else 3.0

lines = []
for i in range(5):
    bias = subgroup_estimates[i] - subgroup_truth[i]
    lines.append(f"{i+1} {subgroup_estimates[i]} {subgroup_truth[i]} "
                 f"{round(sampling_hw_indep, 2)} {round(bias, 2)} {stress_test_hw[i]}")
with open(os.path.join(data_dir, "panel_E_uncertainty_budget.dat"), "w") as f:
    f.write("\n".join(lines) + "\n")
print("   panel_E_uncertainty_budget.dat")


###############################################################################
# Summary metrics (LaTeX macros)
###############################################################################

print("Summary metrics...")

ci_paired_500 = ci_width_paired[idx500[0]] if len(idx500) > 0 else 3.5
ci_indep_500 = ci_width_indep[idx500[0]] if len(idx500) > 0 else 6.0
sampling_hw_paired = ci_paired_500 / 2

metrics = [
    f"\\providecommand{{\\trueRegimeMean}}{{{true_mean_sgpc:.1f}}}",
    f"\\providecommand{{\\bridgeMean}}{{{bridge_mean_sgpc:.1f}}}",
    f"\\providecommand{{\\bridgeBias}}{{{bridge_bias:.1f}}}",
    f"\\providecommand{{\\meanBridgeError}}{{{mean_bridge_error:.2f}}}",
    f"\\providecommand{{\\medianBridgeError}}{{{median_bridge_error:.2f}}}",
    f"\\providecommand{{\\maeBridge}}{{{mae_bridge:.2f}}}",
    f"\\providecommand{{\\maxAbsError}}{{{max_abs_error:.1f}}}",
    f"\\providecommand{{\\rmseBridge}}{{{rmse_bridge:.2f}}}",
    f"\\providecommand{{\\nConditions}}{{{n_conditions}}}",
    f"\\providecommand{{\\nMain}}{{{n_main:,}}}",
    f"\\providecommand{{\\copulaRho}}{{{copula_rho:.2f}}}",
    f"\\providecommand{{\\copulaDf}}{{{copula_df}}}",
    f"\\providecommand{{\\trueKappa}}{{{true_kappa}}}",
    f"\\providecommand{{\\trueAlpha}}{{{true_alpha:.1f}}}",
    f"\\providecommand{{\\trueBeta}}{{{true_beta_:.1f}}}",
    f"\\providecommand{{\\samplingHWpaired}}{{{sampling_hw_paired:.1f}}}",
    f"\\providecommand{{\\samplingHWindep}}{{{round(sampling_hw_indep, 1):.1f}}}",
    f"\\providecommand{{\\ciWidthPairedFiveH}}{{{ci_paired_500:.1f}}}",
    f"\\providecommand{{\\ciWidthIndepFiveH}}{{{ci_indep_500:.1f}}}",
]

with open(os.path.join(data_dir, "summary_metrics.tex"), "w") as f:
    f.write("\n".join(metrics) + "\n")
print("   summary_metrics.tex")


###############################################################################
# Axis limits (LaTeX macros)
###############################################################################

print("Axis limits...")

y_max_a = max(d_true.max(), d_bridge.max()) * 1.15
y_max_b = y_err.max() * 1.15
x_range_b = (x_err.min(), x_err.max())
max_ci_width = ci_width_indep.max() * 1.05
max_N = int(N_grid.max())

axes = [
    f"\\providecommand{{\\panelAymax}}{{{np.ceil(y_max_a * 10) / 10}}}",
    f"\\providecommand{{\\panelBymax}}{{{np.ceil(y_max_b * 10) / 10}}}",
    f"\\providecommand{{\\panelBxmin}}{{{int(np.floor(x_range_b[0]))}}}",
    f"\\providecommand{{\\panelBxmax}}{{{int(np.ceil(x_range_b[1]))}}}",
    f"\\providecommand{{\\panelDymax}}{{{int(np.ceil(max_ci_width))}}}",
    f"\\providecommand{{\\panelDxmax}}{{{max_N}}}",
    f"\\providecommand{{\\trueMeanVline}}{{{round(true_mean_sgpc, 1)}}}",
    f"\\providecommand{{\\bridgeMeanVline}}{{{round(bridge_mean_sgpc, 1)}}}",
]

with open(os.path.join(data_dir, "axis_limits.tex"), "w") as f:
    f.write("\n".join(axes) + "\n")
print("   axis_limits.tex")


###############################################################################
# Panel B: accuracy markers (PSTricks arrows)
###############################################################################

print("Panel B (accuracy markers)...")
marker_lines = []
for i, (tm, be) in enumerate(zip(true_means_conditions, bridge_estimates)):
    y_pos = i + 1
    err = be - tm
    col = "zissouTeal" if err >= 0 else "zissouRed"
    marker_lines.append(
        f"\\psline[linecolor={col},linewidth=0.8pt]{{->}}"
        f"({tm:.2f},{y_pos})({be:.2f},{y_pos})%"
    )
    marker_lines.append(
        f"\\pscircle*[linecolor=zissouAmber]({tm:.2f},{y_pos}){{0.15}}%"
    )

with open(os.path.join(data_dir, "panel_B_accuracy_markers.tex"), "w") as f:
    f.write("\n".join(marker_lines) + "\n")
print("   panel_B_accuracy_markers.tex")


print(f"\nExport complete. Files in: {data_dir}")
