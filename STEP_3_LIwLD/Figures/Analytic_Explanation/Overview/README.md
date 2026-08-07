# STEP 3 PSTricks Infographic (V2)

## Figure Theme

**Longitudinal Inference Without Longitudinal Data**

This title/theme is the canonical framing for the current infographic and should be preserved in downstream AI context artifacts.

Publication-grade 2x4 PSTricks/LaTeX infographic explaining how STEP 3 infers a latent growth regime $\widehat{G}_S$ from unlinked cross-sectional data.

> **Notation note.** The growth-regime CDF (and its candidate family) uses $G$ / $\mathcal{G}$ rather than $H$ / $\mathcal{H}$. This frees $H$ for the joint distribution function in Sklar's theorem, which is its conventional role and the one used in the Margins infographic and the Betebenner--Braun colloquium presentation. Earlier infographic snapshots in `V0_030126/` and `V1_030726/` predate this rename and still use $H$.

Framing used in STEP 3: **controlled canonical choices with quantified error**:
- Canonical baseline copula (from STEP 1),
- Canonical stochastically fitted growth regime (Beta family in STEP 3 production runs).

## Active panel layout

The current V2 assembly uses:
- **Top graphic row:** `A`, `B1`, `B2`, `C`
- **Bottom explanatory row:** `A`, `B1B2` (shared), `C`

| Conceptual column | Top row (graphic) | Bottom row (text artifact) |
|-------------------|-------------------|----------------------------|
| **A** | Independent U & V marginal densities (no student-level pairs) | `step3_panel_A_text.tex` |
| **B1** | Reverse-engineer regime landscape over $(m,\kappa)$ | `step3_panel_B1B2_text.tex` (shared B1/B2 narrative) |
| **B2** | Forward CDF check in v-space | `step3_panel_B1B2_text.tex` (shared B1/B2 narrative) |
| **C** | Inferred growth regime density $f_S(p)$ | `step3_panel_C_text.tex` |

## Workflow

1. **Panel A:** Observe unlinked marginals $F_U(u)$ and $F_V(v)$ (no student-level pairs).
2. **Panel B1:** Estimate subgroup regime by minimum distance over canonical Beta family:
   $\widehat{G}_S=\arg\min_{G\in\mathcal{G}_{\mathrm{Beta}}}\,W_1(F^{\mathrm{obs}}_{V,S},F_G)$.
3. **Panel B2:** Forward map with baseline kernel and candidate regime:
   $F_G(v)=\mathbb{E}_{U}\!\left[G\!\left(F_0(v\mid U)\right)\right]$.
4. **Panel C:** Display recovered density $f_S(p)=G_S'(p)$ and summary mean SGPc.

Key identifying assumption in this infographic: $P\perp U$ within subgroup.

## Quick start

```bash
cd PSTricks/
Rscript step3_build_pstricks.R
```

The build takes ~5 seconds and writes deliverables to `outputs/`:
`step3_infographic_main.pdf`, `Longitudinal_Inference_Without_Longitudinal_Data_v<version>.pdf`, `step3_infographic_main.png`, and (if a converter is installed) `step3_infographic_main.svg`.

## Prerequisites

- **R** (>= 4.0) with the `copula` package
- **TeX Live** with PSTricks packages (`pstricks`, `pst-plot`, `pst-node`)
- **Ghostscript** (`gs`) for EPS->PDF conversion
- **XeLaTeX** (`xelatex`) for text panels and final assembly
- Access to `dataimago.sty` at `../../../../../../Papers/Betebenner_Braun/Paper_1/styles/dataimago.sty`

The analytic data RDS must exist at `../outputs/step3_growth_regime_analytic_infographic_data.rds`. If it does not, first run:

```bash
cd ..
Rscript step3_analytic_explanation.R
```

### Data source modes

`step3_export_data.R` supports two source modes:

- `::SYNTHETIC::` (default): uses `../outputs/step3_growth_regime_analytic_infographic_data.rds`
- `::PHASE_A_REAL_DATA::`: uses `../../../results/phase_a_analytic_payload.rds`

Run real-data export mode with:

```bash
STEP3_EXPORT_MODE=PHASE_A_REAL_DATA Rscript step3_export_data.R
```

## Build pipeline

```
step3_export_data.R          # 1. Load RDS -> export .dat + .tex to data/
    ↓
latex -> dvips -E -> gs      # 2. Compile graphic panels (PSTricks)
xelatex + dataimago          # 3. Compile text panels (A, B1B2, C)
    ↓
xelatex + dataimago          # 4. Compile header band
    ↓
xelatex + dataimago          # 5. Assemble 2x4 main infographic
    ↓
gs -sDEVICE=png16m           # 6. Optional PNG export
```

This mirrors the compile chain in `Betebenner_Braun/Paper_1/Figures/Copulas/copula_R_script.R`.

## AI context pipeline

Generate AI-ready context artifacts for REPOMIX-style distillation:

```bash
cd PSTricks/
Rscript step3_build_ai_context.R
```

Outputs:
- `AI_CONTEXT_OVERVIEW.md` (human-readable build/context map)
- `AI_CONTEXT_REPOMIX.txt` (default plain-text packed context)
- Optional XML output: `Rscript step3_build_ai_context.R --style xml`

Notes:
- If `repomix` is installed, the script uses it.
- If not, the script falls back to an internal deterministic packer.
- Inclusion/exclusion defaults are defined in `repomix.config.json`.

## File inventory

### Source files

| File | Purpose |
|------|---------|
| `step3_build_pstricks.R` | Master figure build orchestrator |
| `step3_export_data.R` | R->TeX data export (curves, heatmap, metrics) |
| `step3_build_ai_context.R` | AI context artifact build orchestrator |
| `repomix.config.json` | REPOMIX include/ignore rules for this directory |
| `step3_styles.tex` | Shared colors and notation macros |
| `step3_panel_A_graphic.tex` | PSTricks: U & V density curves |
| `step3_panel_B1_graphic.tex` | PSTricks: objective heatmap over $(m,\kappa)$ |
| `step3_panel_B2_graphic.tex` | PSTricks: CDF comparison (includes TAMP curve) |
| `step3_panel_C_graphic.tex` | PSTricks: inferred regime density |
| `step3_panel_A_text.tex` | Text: cross-sectional inputs |
| `step3_panel_B1B2_text.tex` | Text: shared B1/B2 narrative and identities |
| `step3_panel_C_text.tex` | Text: recovered growth regime interpretation |
| `step3_header_band.tex` | XeLaTeX header band (background + A/B1&B2/C labels) |
| `step3_infographic_main.tex` | Main assembler using precompiled panel PDFs |
| `step3_panel_B1_text.tex` | Legacy split text panel (not assembled in current V2) |
| `step3_panel_B2_text.tex` | Legacy split text panel (not assembled in current V2) |

### Generated data (`data/`)

| File | Contents |
|------|----------|
| `panel_A_density_U.dat` | Prior density curve (x y) |
| `panel_A_density_V.dat` | Current density curve (x y) |
| `panel_B1_heatmap_cells.tex` | R-generated `\psframe*` heatmap |
| `panel_B1_optimum.tex` | Best-fit $(\hat m,\hat\kappa)$ coordinates |
| `panel_B2_cdf_obs.dat` | Observed CDF |
| `panel_B2_cdf_uniform.dat` | Uniform-regime CDF prediction |
| `panel_B2_cdf_inferred.dat` | Inferred-regime CDF prediction |
| `panel_B2_cdf_tamp.dat` | Co-monotonic (TAMP) induced CDF, $F_U(v)$ |
| `panel_C_density_*.dat` | Regime density curves |
| `summary_metrics.tex` | LaTeX macros with computed values |
| `axis_limits.tex` | LaTeX macros with axis ranges |

### Outputs (`outputs/`)

| File | Format |
|------|--------|
| `step3_infographic_main.pdf` | Final publication infographic |
| `Longitudinal_Inference_Without_Longitudinal_Data_v<version>.pdf` | Versioned release copy of final publication infographic |
| `step3_infographic_main.png` | 300 DPI raster export |
| `step3_infographic_main.svg` | Optional vector export |
| `step3_panel_*_graphic.pdf` | Individual graphic panels |
| `step3_panel_*_text.pdf` | Individual text panels |
| `step3_header_band.pdf` | Header band artifact used by main assembler |

### AI artifacts

| File | Purpose |
|------|---------|
| `AI_CONTEXT_OVERVIEW.md` | Human-auditable context summary for agents |
| `AI_CONTEXT_REPOMIX.txt` | Plain-text packed source context (default) |
| `AI_CONTEXT_REPOMIX.xml` | Optional XML packed source context |

## Color palette

Aligned with the STEP 3 Zissou-based publication style:

- **Teal** `#3B9AB2` - prior sample / inferred regime
- **Red** `#F21A00` - current sample
- **Amber** `#E1AF00` - true synthetic regime
- **Grey** - uniform baseline and annotations

## Notation

Canonical macros defined in `step3_styles.tex`:

| Macro | Renders |
|-------|---------|
| `\GS` | $G_S$ |
| `\GShat` | $\widehat{G}_S$ |
| `\GU` | $G_U$ |
| `\FG` | $F_G$ |
| `\FGhat` | $\widehat{F}_G$ |
| `\Fobs` | $F_{\mathrm{obs}}$ |
| `\Fzero` | $F_0$ |
| `\SGPcFlow` | SGPcFlow |
| `\Wone` | $W_1$ |

### Mathematical notation

- $U,V$: prior/current reference quantiles (pseudo-observations)
- $P,P_S$: latent conditional percentile (SGPc on $[0,1]$)
- $G_S(p)=\Pr(P_S\le p)$: subgroup growth-regime CDF
- $F_0(v\mid u)=\frac{\partial}{\partial u}C_0(u,v)$: baseline conditional CDF kernel
- $Q_0(p\mid u)=F_0^{-1}(p\mid u)$: baseline conditional quantile kernel
- $F_G(v)=\mathbb{E}_{U}[G(F_0(v\mid U))]$: predicted current marginal under regime $G$
- $\mathcal{G}_{\mathrm{Beta}}=\{G_{m,\kappa}:P\sim\mathrm{Beta}(\kappa m,\kappa(1-m))\}$: candidate family
- $\widehat{G}_S=\arg\min_{G\in\mathcal{G}_{\mathrm{Beta}}}W_1(F^{\mathrm{obs}}_{V,S},F_G)$

Uniform baseline in this parameterization is $G(p)=p$ at $(m,\kappa)=(0.5,2)$, i.e. $\mathrm{Beta}(1,1)$.

The growth-regime symbol $G$ deliberately differs from the joint distribution $H$ used in Sklar's theorem (cf. the Margins infographic) — see the notation note above.

## Font behavior

The final composite is intentionally hybrid, mirroring the Copula pipeline:

- Bottom-row explanatory panels, header band, and master title/footer use XeLaTeX + `dataimago.sty` (`Noto Sans` + `Noto Sans Math`).
- Top-row PSTricks graphic panels remain on the classic `latex -> dvips -> gs` path and therefore keep Computer Modern / `sansmathfonts` glyphs for panel-internal labels.
