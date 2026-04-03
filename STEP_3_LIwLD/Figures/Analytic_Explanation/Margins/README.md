# Margins Infographic

**From Scores to Pseudo-Observations: The Marginal Transformation**

This infographic explicates what is compressed into Panel A of the Overview infographic. It unpacks the following four ideas that are hidden in a single density plot:

1. **The probability-integral transform (PIT):** Conversion of random variables X and Y to pseudo-observations U and V via fixed reference CDFs, stripping out the metric structure of the assessment variables.

2. **Linkage as observed coupling:** Spaghetti plots showing linked, partially linked, and non-linked observations—making visible the distinction between longitudinal data (observed pairs) and cross-sectional data (marginals only).

3. **The distribution functions F_X^ref and F_Y^ref:** Explicit illustration of the CDF mapping with trace arrows, connecting Sklar's theorem to the practical data transformation.

4. **Subgroup versus population:** The reference CDFs are population-level, so the subgroup's marginal distribution of U is generally not uniform—it reflects the subgroup's position relative to the population baseline.

## Structure

The infographic is ~8in wide with a vertical layout:

| Component | File(s) | Compiler |
|-----------|---------|----------|
| **Title + subtitles** | `step3_infographic_main.tex` | xelatex |
| **Header band** | `step3_header_band.tex` | xelatex |
| **CDF transform** | `step3_panel_CDF_graphic.tex` | latex → dvips → gs |
| **Linked spaghetti** | `step3_panel_spaghetti_linked_graphic.tex` | latex → dvips → gs |
| **Non-linked marginals** | `step3_panel_spaghetti_unlinked_graphic.tex` | latex → dvips → gs |
| **Text (prose + math)** | `step3_panel_text.tex` | xelatex |
| **Footnotes** | In `step3_infographic_main.tex` | xelatex |

## Build

```r
# From the Margins/ directory:
source("step3_build_pstricks.R")
```

The build pipeline mirrors the Overview and Inference Error infographics:

1. `step3_export_data.R` generates synthetic data → `data/`
2. PSTricks panels: `latex` → `dvips -E` → `gs` → PDF
3. Text/header panels: `xelatex` → PDF
4. Main assembler: `xelatex` composes all PDFs → final output
5. PNG/SVG export via Ghostscript/pdf2svg

## Data

All data is synthetic (generated in `step3_export_data.R`):

- **CDF curves:** Normal CDFs representing population-level reference distributions
- **Linked pairs:** Bivariate normal with ρ = 0.80, n = 20 linked pairs
- **Orphan observations:** 3 prior-only + 2 current-only (partial linkage ~87%)
- **Marginal densities:** Kernel density estimates of pseudo-observations

## Design Choices

- **Spaghetti plot for linkage:** Horizontal lines connecting U_i to V_i make coupling visible at a glance. Orphan observations appear as × marks, naturally representing partial linkage.
- **Uniform reference:** The population Uniform(0,1) is shown as a dashed reference in the non-linked panel, highlighting that subgroup marginals deviate from uniform.
- **CDF trace arrows:** Dashed arrows in the CDF panels make the PIT visually concrete for non-technical readers. The trace uses a warm taupe (`pitTraceColor`) to avoid collision with linkage-class colors.
- **"Lose linkage" arrow:** The central arrow between the two spaghetti panels explicitly labels the transition from linked to non-linked as a loss of information.
- **Color semantics:** Color encodes meaning, not axis. Population-reference elements (CDF curves, PDF fill/border) use a grey family. Subgroup density curves use a single shared hue (`subgroupColor`) for both X and Y margins. Linkage classes (stayers, leavers, entrants) occupy a separate color channel (Zissou teal/red/amber). The PIT trace is visually distinct from all three linkage classes.

## Dependencies

Same as the other infographics:
- TeX Live (xelatex, latex, dvips)
- Ghostscript (gs)
- R (for data export)
- `dataimago.sty` (project font/style package)

## Relationship to Other Infographics

This infographic serves as a **detailed companion to Panel A** of the Overview infographic. It can be referenced when readers need more context about:

- Why pseudo-observations are used instead of raw scores
- What information is lost when linkage is absent
- How partial linkage occupies an intermediate position
- The connection to the non-linkage premium calculations in the appendix

## Version History

- **v0.1.0** — Initial design and scaffolding
