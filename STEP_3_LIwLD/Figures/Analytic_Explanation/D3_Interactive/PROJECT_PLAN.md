# LIwLD Interactive — Project Plan (v0.1)

**Working title:** *Longitudinal Inference Without Longitudinal Data — An Interactive Walkthrough*

**Owners:** Damian Betebenner (lead) · Claude (collaborator)
**Status:** v0.2 — answers integrated, beginning Phase 1 · 2026-05-04
**Sibling artifacts:** `../Overview/` (static cross-panel infographic), `../Margins/` (PIT/linkage detail), this folder (interactive web app)
**Delivery target:** Embedded HTML island inside the RevealJS deck at `~/Research/Papers/Betebenner_Braun/Paper_1/NCIEA_2026_Colloquium_Staff_Presentation.qmd`. Must run offline from disk.

---

## 0. Decisions locked in v0.2 (consolidated answers)

| # | Decision | Implication |
|---|---|---|
| Q1 | **Audience** = NCIEA 2026 colloquium colleagues; **delivery** = embedded into the existing Quarto/RevealJS deck. | Build for desktop/projector primarily. Static export must work over `file://`. Mobile fallback is nice-to-have, not required. |
| Q2 | **Single canonical scenario** at v1. | No scenario-selector chrome. URL state for handle position only. |
| Q3 | **Real Phase A data** (de-identified) is the v1 default. | `STEP3_EXPORT_MODE = PHASE_A_REAL_DATA`. Synthetic stays as a fallback for development. `data_classification = "INTERNAL"` until reviewed. |
| Q4 | **Standalone**, no dataimago coupling for v1. | `D3_Interactive/` is self-contained. Tokens are local; promotion to dataimago-design tokens is a Phase 5 task. |
| Q5 | **No copula switching in v1.** | t-copula only; ρ and df pinned from STEP 1. Panel #2 is static structure with hover crosshair only. |
| Q6 | **Global PDF↔CDF mode with animated transition**, plus a separate **population-visibility toggle**. | One global mode propagates to Panels #1, #4, #5. Begin in PDF mode showing all four densities (pop/sub × prior/current). The PDF→CDF morph is a *showcase* moment, not a chrome detail. The W₁ shaded band only renders in CDF mode (it has no meaning between densities). |
| Q7 | **W₁ readout shown two ways**: absolute `W₁ = 0.0132` *and* relative `53% of baseline`. | The absolute number anchors the math; the relative number anchors the audience's intuition. Both update live as the handle moves. |

A consequence of Q1 + Q4: **Vite + React 19 + D3 replaces Next.js for v1.** Next.js was selected against a microsite assumption that no longer holds. Vite produces a single static `dist/` directory that can be referenced by the RevealJS slide via `<iframe src="./LIwLD_Interactive/index.html">` — or even inlined if we keep the bundle small enough. Eventual promotion into dataimago-ai (which is Next.js) is mechanical because all the visualization logic lives in framework-agnostic React components.

---

## 1. Why this exists

In every presentation of STEP 3, the audience tracks the marginals story (Panel A) and even the regime-color story (Panel C), but loses traction *exactly* at the bridge: how a fixed copula plus a single growth regime *induces* a current-score distribution, and why the regime that minimizes the Wasserstein distance to the observed V is the one we declare "the inferred regime."

The static infographic compresses four moving pieces — `U`, the copula `C`, the regime `H`, and the induced `V` — into one frame. We are going to *un-compress* them: give each its own frame, make `H` directly draggable, and let the audience watch `V_induced` deform in real time as `H` slides across the (m, κ) parameter grid. The Wasserstein surface becomes the felt landscape under the user's finger.

**Audience.** Mathematically literate but copula-naïve: psychometricians, education-research statisticians, accountability-policy people, conference panels. They are comfortable with PDFs, CDFs, and "minimum distance" as an idea, but unfamiliar with copulas and Sklar's theorem operationally. The visualization must reward both casual scrubbing ("oh — that's why it gets larger as I move down-right") and careful inspection ("what is W_1 at exactly (0.39, 25)?").

**Non-goals.** This is *not* a general STEP 3 results browser. It is a single, opinionated explainer for one mathematical idea. The scenario selector (Phase 5) is for substituting demonstration data, not for ad-hoc analysis.

---

## 2. The cross-pattern, panel by panel

The PDF prototype lays out five panels in a `+` pattern. Adopting that as the canonical layout:

```
                    ┌────────────────────┐
                    │  #2 COPULA         │
                    │  C(u, v) contours  │
                    │  (t-copula, fixed  │
                    │   ρ, df from STEP 1)│
                    └────────────────────┘
┌──────────────┐    ┌────────────────────┐    ┌──────────────┐
│ #1 PRIOR U   │    │ #3 REGIME GRID     │    │ #5 CURRENT V │
│ PDF/CDF      │◀──▶│ (m, κ) heatmap     │◀──▶│ PDF/CDF      │
│ pop + sub    │    │ colored by W_1      │    │ pop observed │
│              │    │ ⬤ draggable handle │    │ sub observed │
│              │    │                    │    │ sub induced  │
└──────────────┘    └────────────────────┘    └──────────────┘
                    ┌────────────────────┐
                    │ #4 BETA DENSITY    │
                    │ g(p) = Beta(m, κ)  │
                    │ for selected handle│
                    └────────────────────┘
```

### Panel #1 — Prior score `U` (left)

**Shows:** Population marginal of the prior pseudo-observation `U` (uniform by construction, dashed) and the subgroup marginal of `U` (kernel density of pseudo-observations, solid). Toggle: PDF ⇄ CDF.

**Why both views:** Sklar's theorem is a CDF statement, but psychometricians read densities first. Toggling lets the speaker say "now look at the same fact in CDF form" without switching slides.

**Convention encoding (::POPULATION_REF::, ::SUBGROUP::):** Reuses the color tokens already established in the Margins infographic — population in a neutral grey family, subgroup in a single hue. No additional channels here.

**Interaction:** Hover ↔ vertical guide that propagates to Panels #2, #3, and #5 (a "what happens to a student at U = 0.35?" thread).

### Panel #2 — Copula `C(u, v)` (top)

**Shows:** Contours of the canonical t-copula CDF on the unit square (matches the Margins scatter contour data already in `data/contour_t_cdf_*.dat`). Provides the bivariate scaffolding linking #1 to #5.

**v1 scope:** Single fixed copula per scenario (t-copula, ρ and df pinned from STEP 1).

**v2 nice-to-have:** Switch among `t / frank / gaussian / clayton / gumbel`. Each option ships a precomputed contour bundle. Switching only changes which copula the regime convolves with — Panels #1, #3, #4 are unchanged structurally; Panel #5 induced curve recomputes.

**Interaction:** Crosshair on hover that mirrors the U-guide from Panel #1, showing the conditional `C(u | U=u_0)` slice. Optional "show conditional CDF" overlay.

### Panel #3 — Regime grid (center, the *interactive* heart)

**Shows:** A 2D heatmap of W_1(F_obs_V, F_G) over the (m, κ) parameter grid for the canonical Beta family of regimes. Bright = far from observed; dark = close. The argmin is marked with a small target glyph.

**Two reference markers (always visible):**
- **U(0,1) baseline regime** — fixed at the no-growth coordinate (m = 0.5, κ → 1, i.e., uniform). Label: "no-information baseline."
- **Inferred regime** — the argmin. Label: "minimum-distance regime."

**Draggable handle:** A pickup that the user moves freely. As it moves:
- Panel #4 redraws the Beta density (and CDF if toggled) for the new (m, κ).
- Panel #5 redraws `V_induced` for the new regime.
- The handle's W_1 value is shown numerically near the handle and on Panel #5's title.
- The handle snaps (with a small magnetic radius) to the U(0,1) baseline and to the argmin, so demonstrators can land on those reference points without fiddling.

**Why a grid (not a 1D slider):** The (m, κ) parameterization is *the* point. A single mean parameter would let the audience read the visualization as "find the right average growth," when in fact the *concentration* (κ) is doing equally important work — it controls regime sharpness, which controls how much V is squeezed or stretched relative to U. A 2D grid forces the audience to confront both axes.

**Aspirational extension:** Replace the grid with a richer regime family later (e.g., a flexible mixture or a non-parametric regime). For v1 we stay with Beta(m, κ) because it matches the existing STEP 3 estimator and the math people already know.

### Panel #4 — Beta regime density (bottom)

**Shows:** `g(p) = Beta(m, κ).pdf(p)` (the growth-regime density) for the currently selected handle in Panel #3. CDF toggle shows `G(p)` as in #1.

**Annotations:** Mean (vertical line at `m`), concentration label (`κ = …`), and a faint *uniform* reference (the U(0,1) regime) so the audience always sees how far the current regime departs from "no information."

**Why bottom (not right):** It is *paired* with Panel #3 — its content depends only on the handle position. Putting it directly below makes the dependency a vertical glance.

### Panel #5 — Current score `V` (right)

**Shows:** Up to four CDFs (or PDFs) of `V`:
1. Population observed `F_obs_V` (grey, dashed)
2. Subgroup observed `F_obs_V_sub` (color, solid) ← the *target*
3. Subgroup induced `F_G` for the **handle** position (color, dotted)
4. Subgroup induced `F_G` for the **argmin** position (color, solid bold) — toggleable, off by default to keep the handle the protagonist

**Wasserstein highlight:** Shaded band between the subgroup-observed CDF (#2) and the handle-induced CDF (#3) representing the L¹ area, with the numeric value of W_1 displayed prominently. (Wasserstein-1 in 1D *is* the L¹ distance between CDFs — this is the most teachable visual identity in the entire piece.)

**The narrative arc the audience experiences:** "If I drag the handle to the U(0,1) baseline, the dotted curve flies way off the target. If I drag it toward the dark spot in #3, the dotted curve presses closer and closer to the target. The shaded area (the W_1 distance) is exactly what we are minimizing."

---

## 3. Mathematical & data model (the contract)

The R precompute pipeline must deliver, *per scenario*, the following bundle. JSON Schema is the source of truth; field types are illustrative.

```jsonc
// scenarios/<scenario_id>/manifest.json
{
  "scenario_id": "demo_low_growth_synth",
  "label": "Synthetic low-growth subgroup (n = 3,500)",
  "data_source": "SYNTHETIC | PHASE_A_REAL_DATA",
  "cohort": { "grade_prior": 6, "grade_current": 7, "year_prior": "2023", "year_current": "2024", "content_area": "MATHEMATICS" },
  "n_subgroup": 3500,
  "n_population": 412903,
  "copula": { "family": "t", "rho": 0.84, "df": 25 },
  "regime_grid": { "m_min": 0.05, "m_max": 0.95, "m_n": 91, "k_min": 1.0, "k_max": 60.0, "k_n": 60, "k_scale": "log" },
  "argmin": { "m": 0.39, "k": 26.4, "w1": 0.013 },
  "uniform_ref": { "m": 0.5, "k": 1.0, "w1": 0.087 },
  "files": {
    "panel_1_u": "panel1_u_curves.json",
    "panel_2_copula": "panel2_copula_contours.json",
    "panel_3_grid": "panel3_w1_surface.bin",         // Float32Array, row-major
    "panel_5_observed_v": "panel5_v_observed.json",
    "panel_5_induced_v": "panel5_v_induced.bin"      // Float32Array, [m_n, k_n, v_n]
  },
  "v_grid": { "v_min": 0.0, "v_max": 1.0, "v_n": 200 },
  "version": "1.0.0",
  "checksum_sha256": "…"
}
```

**Per-panel files:**

| Panel | File | Shape | Approx size (gzip) |
|---|---|---|---|
| #1 | `panel1_u_curves.json` | `{u: [..200..], pdf_pop, pdf_sub, cdf_pop, cdf_sub}` | < 5 KB |
| #2 | `panel2_copula_contours.json` | `[{level: 0.1, paths: [[ [u,v], … ], …]}, …]` (already produced by Margins exporter) | ~30 KB |
| #3 | `panel3_w1_surface.bin` | `Float32Array[m_n × k_n]` (91×60 = 5,460 floats) | ~15 KB |
| #5 obs | `panel5_v_observed.json` | `{v, pdf_pop, pdf_sub, cdf_pop, cdf_sub}` | < 5 KB |
| #5 ind | `panel5_v_induced.bin` | `Float32Array[m_n × k_n × v_n]` (91×60×200 = 1.09M floats) | ~3.5 MB |

The induced-V tensor is the only weight. Three mitigations:
1. **Quantize to `Float16`** (or 8-bit normalized over [0,1] with per-cell min/max) — induced CDFs are smooth so 8-bit is plenty for visual fidelity. Cuts size to ~700 KB.
2. **Lazy chunking** — split into 9 tiles by m × k blocks; fetch the tile under the cursor on demand.
3. **Resolution honesty** — for the demo, we may not need 91×60. 45×30 = 1,350 cells × 200 v-points × 1 byte ≈ 270 KB is enough for a smooth heatmap and snappy interactions.

For v1 we ship a single quantized tensor. Lazy chunking is held in reserve.

**Panel #4** needs no precomputed file — Beta density evaluations are cheap on the client (a `gamma(α+β)/gamma(α)gamma(β) · p^(α-1) · (1-p)^(β-1)` line, 200 evaluations per drag-tick).

---

## 4. Technical architecture

### 4.1 Stack

| Layer | Choice | Rationale |
|---|---|---|
| Compute (truth) | R (extension of `Margins/step3_export_data.R`) | "R as Source of Truth" — preserves the dataimago invariant. All downstream artifacts derive from R. |
| Wire format | JSON for small panels, Float32Array `.bin` for tensors | JSON for inspectability; binary for the one heavy artifact. No Apache Arrow yet — overkill for one tensor. |
| Frontend framework | **Vite 5 + React 19** *(was Next.js 15 in v0.1)* | Single static `dist/` folder that loads from `file://`. No SSR overhead. Embeddable in RevealJS via `<iframe>`. Promotion into dataimago-ai's Next.js is mechanical — all viz logic is in framework-agnostic React components. |
| Visualization library | **D3 v7 (low-level primitives)** — `d3-scale`, `d3-shape`, `d3-drag`, `d3-contour`, `d3-color`, `d3-interpolate` | We need bespoke control over the linked-panel state; Recharts would force every panel into its grammar and fight us on cross-panel hover. |
| State | **Zustand** for cross-panel shared state (handle position, hover U-guide, mode) | Simple, no provider tree, plays well with React 19. |
| Math notation | **KaTeX** (server-rendered HTML, no MathJax) | Tiny CSS, no runtime cost, no font fetching surprises. |
| Styling | Tailwind for chrome (header, controls, mode pills); inline CSS variables for visualization tokens | Keeps the SVG free of utility-class noise. |
| Storage v1 | Static files (served from `dist/data/scenarios/<id>/` or co-located with the slide deck) | Zero infra, infinite cache, works over `file://` for offline talks. |
| Storage v2 | **Turso (libSQL)** behind the dataimago dual-mode API client | Only when scenario count > ~20 or scenarios are user-uploadable. |

### 4.2 Where this lives in the dataimago topology

Two viable homes:

**Option A — Standalone subfolder of this project, no dataimago coupling.**
- Path: `STEP_3_LIwLD/Figures/Analytic_Explanation/D3_Interactive/app/`
- Pros: Self-contained, easy to commit alongside the rest of the figure pipeline. No cross-repo concerns. R script lives next to its TeX siblings.
- Cons: Misses the dataimago derivation pipeline (no automatic API/MCP/types). Re-implements brand tokens.

**Option B — Microsite under the dataimago-ai umbrella, R precompute under dataimago-rpkg.**
- The R precompute becomes a documented `dataimago-rpkg` function (e.g., `dataimago::liwld_precompute(scenario, regime_grid, copula)`) and `dataimago::ai()` derives the static JSON exports + TS types automatically. The Next.js app is a route under dataimago-ai (e.g., `apps/explainers/liwld/`) and inherits brand tokens, the dual-mode API client, and the ethical CI pipeline (contrast, motion-lint, bundle-check) for free.
- Pros: Delivers on dataimago's recursive promise — the explainer is itself dogfooding the meta-tool. Token/typography/ethics propagation comes free. Bundle budget is enforced.
- Cons: Up-front coupling, multi-repo PR.

**Recommendation:** Build v1 in Option A within this folder for fast iteration on the math/UX, but with a deliberately clean boundary — the R precompute is a single self-contained script and the frontend reads only from `./data/` over HTTP. When the math story stabilizes (Phase 4-ish), promote the R function into `dataimago-rpkg` and the app into `dataimago-ai`. The boundary discipline now makes the Phase 5 promotion mechanical.

### 4.3 Repo layout (standalone, Vite)

```
D3_Interactive/
├── PROJECT_PLAN.md                 ← this file
├── README.md
├── schema/
│   └── manifest.schema.json        ← JSON Schema, single source of truth
├── R/
│   ├── liwld_precompute.R          ← orchestrator
│   ├── induced_cdf.R               ← F_G(v) tensor over the (m, κ) grid
│   ├── wasserstein_grid.R          ← W_1 surface (or reuse stored objective_surface)
│   └── export_bundle.R             ← writes manifest.json + per-panel files + sha256
├── data/
│   └── scenarios/
│       └── liwld_phase_a_v1/       ← canonical v1 scenario (real, de-identified)
│           ├── manifest.json
│           ├── panel1_u_curves.json
│           ├── panel2_copula_contours.json
│           ├── panel3_w1_surface.bin
│           ├── panel5_v_observed.json
│           └── panel5_v_induced.bin
└── app/                            ← Vite + React 19
    ├── package.json
    ├── vite.config.ts
    ├── index.html
    ├── public/
    │   └── data/scenarios/…        ← symlink or copy of ../data/scenarios
    └── src/
        ├── main.tsx
        ├── LiwldCross.tsx          ← top-level component
        ├── panels/
        │   ├── PanelU.tsx
        │   ├── PanelCopula.tsx
        │   ├── PanelRegimeGrid.tsx
        │   ├── PanelBeta.tsx
        │   └── PanelV.tsx
        ├── store.ts                ← Zustand
        ├── data-loader.ts          ← typed manifest fetcher (verifies sha256)
        ├── math/
        │   ├── beta.ts
        │   ├── interp.ts           ← bilinear lookup in the induced-V tensor
        │   └── wasserstein.ts
        ├── styles/tokens.css       ← three-tier tokens (local for v1)
        └── types.ts                ← TS types regenerated from manifest.schema.json
```

### 4.4 Data flow per drag-tick

```
user drag (Panel #3)
  → store.setHandle(m, k)
     → PanelBeta:  re-evaluate Beta(m, k) PDF on 200 points  [pure CPU, ~0.2 ms]
     → PanelV:     lookup induced CDF tensor at [m_idx, k_idx, :]
                   bilinear-interpolate between four neighbors  [~0.1 ms]
                   redraw two SVG paths + W_1 shaded band
     → PanelRegimeGrid: redraw handle position only  [no recompute]
```

Total budget per tick: well under one frame at 60 Hz. The expensive work happens once at scenario load.

---

## 5. Look and feel

### 5.1 Layout & breakpoints

| Width | Behavior |
|---|---|
| **Embed (RevealJS slide)** | Fixed 1280 × 720 canvas (`16:9`), no chrome, no header strip, no scroll. The KaTeX strip drops to a single line. Title appears on the slide *above* the iframe, not inside it. URL flag: `?embed=1`. |
| ≥ 1280 px (standalone) | Full cross with title, KaTeX strip, mode pills. Total ~1280 × 800 px. |
| 768–1279 | Cross with slightly compressed side panels. Drops some axis labels. |
| < 768 | **Linear stack**, not cross: U → Copula → Grid → Beta → V. Drag is finger-friendly; vertical scroll between panels. The cross is sacrificed for legibility. |

The cross is a presentation/desktop visualization. Mobile is a graceful fallback for sharing, not the primary mode. **Embed mode is the v1 priority** — it must look intentional inside a slide.

### 5.2 Typography

Use the dataimago-design typography tokens once we promote (Option B). Until then, parallel tokens locally:

- Display (panel titles): **Inter Tight** 600, optical-size 18 px desktop / 16 px mobile
- Body labels: **Inter** 500, 13 px
- Numerals: **Inter** with `font-feature-settings: 'tnum' 1, 'lnum' 1` for tabular alignment in the W_1 readout
- Math (KaTeX inline): KaTeX's bundled fonts; no MathJax

### 5.3 Color (semantic, not aesthetic)

Color encodes *role*, not panel:

- ::POPULATION_REF:: — neutral grey family (slate-400 on light)
- ::SUBGROUP_OBSERVED:: — single accent hue (teal-600), used wherever an observed subgroup quantity appears
- ::SUBGROUP_INDUCED:: — same hue at lower chroma + dotted stroke (NOT a different hue — same role, different epistemic status)
- ::REGIME_HANDLE:: — a chromatically isolated highlight (orange/amber-500) with high contrast against any heatmap colormap
- ::W1_LANDSCAPE:: — a perceptually uniform sequential colormap. Default: `viridis` reversed (so the *minimum* is darkest = "where you want to go"). Diverging maps are wrong here — there is no zero-point, just better and worse.

Contrast targets: WCAG AA on every text/background pair. Heatmap meets the contrast-distinguishability test for protanopia + deuteranopia simulated. Both are dataimago ethical-CI requirements.

### 5.4 Motion

- All panel state transitions: 240 ms cubic-out (a dataimago "thoughtful" motion token).
- Handle drag: zero animation (1:1 with pointer; otherwise the audience loses the felt-causation).
- Snap to argmin / U(0,1) ref: 180 ms ease-out + a tiny haptic-style spring overshoot (20 ms, 4 px).
- Panel #5 induced-CDF redraw: D3 transition with `interpolatePath`-style path-data interpolation so the curve *deforms* rather than flickers.
- All motion respects `prefers-reduced-motion`. With reduced motion, transitions become 60 ms linear cross-fades.

### 5.5 Math rendering placement

KaTeX strips for the three load-bearing identities, displayed *outside* the cross (a slim header below the title) so they never compete with the panels for visual weight:

- Sklar: `H_(U,V)(u,v) = C(F_U(u), F_V(v))`  ← H here = the joint CDF of (U,V)
- Induced CDF: `F_G(v) = E_U[ G(F_0(v | U)) ]`  ← G = growth regime CDF
- The estimator: `Ĝ_S = argmin_{G ∈ 𝒢_Beta} W_1(F_obs_V, F_G)`

> **Notation note.** H is reserved for the joint CDF in Sklar (its traditional
> place); G carries the growth regime everywhere else; 𝒢_Beta (script-G) is
> the parametric family. Lowercase g(p) = G'(p) is the regime density. This
> separation removes the H-for-two-things ambiguity that lived in earlier
> drafts of the static infographics.

A "Show math" toggle hides the strip when projecting for non-technical audiences.

---

## 6. Interaction modes & global state

### 6.1 Global view state (always visible)

Two switches sit in the chrome strip and propagate to *every* panel that cares:

- **View: PDF ⇄ CDF** — single global toggle. Default = PDF. Animated morph (~480 ms cubic-out) on transition. The W₁ shaded band in Panel #5 cross-fades in only when CDF mode is active.
- **Reference layer: Population on/off** — toggles the population (grey-dashed) curves in Panels #1 and #5. Default = on. The audience can mute the reference to focus on the subgroup story. Panel #2 is unaffected (it's a copula, not a marginal).

The PDF→CDF morph is a designed teaching moment, not a chrome detail. Showing all four densities first (pop/sub × prior/current) and then *folding them up into CDFs* on demand is the visualization equivalent of "now watch the same fact in CDF form" — it makes Sklar's theorem feel like the natural next thing to look at, not a separate slide.

### 6.2 Interaction modes

Three modes, one toggle pill in the header:

**::TOUR_MODE::** — A scripted, self-running walkthrough. Drives the handle along a predetermined path: U(0,1) baseline → mid-grid → argmin, narrating in captions ("watch how the induced V deforms"). Pausable. ~25 seconds end-to-end. Designed to be dropped into a slide deck via screen recording or as the live page itself.

**::EXPLORE_MODE::** (default) — Free interaction. Drag handle, hover any panel, toggle PDF/CDF and Population, snap to references. Optional "reveal argmin" button if the user wants to skip ahead.

**::COMPARE_MODE::** — User pins one regime, then drags a second. Panel #5 shows two induced curves overlaid (e.g., uniform vs. argmin, or two user-chosen handles). Useful for the question "how different is *almost optimal* from *optimal*?"

Keyboard navigation: arrow keys nudge the handle by one grid cell; Shift-arrow nudges by 5; `R` snaps to argmin; `0` snaps to U(0,1) baseline; `P` toggles Population; `D`/`C` switches PDF/CDF; `space` toggles tour mode. Critical for accessible navigation and for live demos when the cursor would obscure the handle.

### 6.3 W₁ readout

Two coupled readouts in Panel #5's title strip, updating live as the handle moves:

- **Absolute:** `W₁ = 0.0132` (4 decimals, tabular numerals)
- **Relative:** `53% of baseline` (the U(0,1)-baseline W₁ is 100%; the argmin is the floor of this scale)

In PDF mode both readouts are dimmed and accompanied by a small note "switch to CDF to see distance" — the values are still computed, just visually de-emphasized.

---

## 7. Implementation roadmap (incremental, eval-after-each)

Each phase ends with an explicit "what to test before continuing" gate. No phase begins until the prior eval passes.

### Phase 0 — Specification & scenario contract (no code)
- Lock the JSON schema and binary tensor layout from §3.
- Commit one canonical scenario name (`demo_low_growth_synth`) with target argmin (m ≈ 0.39, κ ≈ 26).
- Decide Option A vs Option B (recommended Option A → promote later).

**Eval:** Schema reviewed and approved. No ambiguity about field names or units.

### Phase 1 — R precompute pipeline (`R/liwld_precompute.R`)
- Wrap and extend `Margins/step3_export_data.R`.
- Add `(m, κ)` grid sweep over the regime family.
- Vectorized `induced_cdf(m, k, v_grid, copula, F_U)` using `copula::pCopula`.
- Compute W_1 surface; locate argmin.
- Write all six bundle files; emit manifest with sha256.

**Eval:** End-to-end run on the synthetic scenario completes in < 2 min on a laptop. Argmin reproduces the existing Overview Panel B1 result to within 1 grid cell. Tensor binary round-trips losslessly to a Python loader.

### Phase 2 — Static layout, no interaction
- Scaffold Next.js 15 app.
- Implement `data-loader.ts` and load the manifest + bundle on the client.
- Render all five panels with static data — no drag yet, handle pinned at argmin.
- PDF/CDF toggle in #1, #4, #5.
- Typography, color, and motion tokens wired in.
- KaTeX strip rendered.

**Eval:** Lighthouse performance ≥ 90 on the deployed preview. All panels visible and identifiable by a domain expert without explanation. Color contrast passes WCAG AA on all text. JS bundle < 250 KB gzip.

### Phase 3 — Interactive handle in Panel #3
- Drag implementation via `d3-drag`.
- Zustand store wires handle position to Panel #4 (Beta redraw) and Panel #5 (induced V redraw).
- Bilinear interpolation in the induced-V tensor for sub-grid handle positions.
- W_1 shaded band + numeric readout in Panel #5.
- Snap-to-references with magnetic radius.
- Keyboard navigation.

**Eval:** Drag stays at 60 fps on a 4-year-old laptop. Handle and Panel #5 stay synchronized to within one frame. Snap behavior feels right (small-group user test, n ≥ 3).

### Phase 4 — Tour mode, transitions, polish
- TOUR_MODE state machine + pre-recorded path.
- COMPARE_MODE pinning.
- Smooth path-deformation transitions in Panel #5.
- Hover U-guide propagation across #1, #2, #5.
- `prefers-reduced-motion` honored.
- Mobile linear stack.

**Eval:** Live demo with the canonical scenario, recorded as a short video. Audience comprehension test (n ≥ 5) — describe the inference procedure after watching tour mode once.

### Phase 5 — (Optional, later) Multi-scenario backend
- Promote R precompute into `dataimago-rpkg`.
- Promote app into `dataimago-ai` for brand/ethics CI inheritance.
- Turso storage for many scenarios; URL-shareable state (`?scenario=...&handle=...`).
- Subgroup picker driven by Phase A real-data conditions.
- Static-mode export remains the default; live mode is opt-in via env flag.

**Eval:** A second scenario ships and works. URL state round-trips losslessly. Static-mode bundle still passes the dataimago bundle-check (< 500 KB JS).

### Phase 6 — Accessibility & equity
- Screen-reader narrative mode (live region announcing W_1 changes).
- Sonification option (optional): pitch maps to W_1 as you drag.
- Slow-network test: scenario bundle < 1 MB gzip total, loads usably on 3G.
- Constrained-device test: passable on a $200 Chromebook.

**Eval:** Independent accessibility audit. Performance equity test on a real low-end device.

---

## 8. Operational concerns

**Hosting.** v1 → Vercel (single static page + bundle). v5 → Vercel (frontend) + Turso (data) via dataimago-ai's dual-mode API client.

**Bundle budget.** 250 KB gzip JS for v1 (excluding the data tensor). dataimago's 500 KB ceiling is a hard CI gate when we promote.

**Data versioning.** Every scenario bundle includes `version` and `checksum_sha256`. Loader verifies checksum before populating the store. Mismatch → fail loud, do not render stale shapes.

<SECURITY_REVIEW>
Surfaces and mitigations:

- **Static data files** — public by design. The synthetic scenario carries no PII. The Phase A scenario is aggregate marginals + induced CDFs — no row-level student data — but we still gate it behind an explicit configuration choice rather than shipping it as the default. Add a manifest field `data_classification: "PUBLIC" | "INTERNAL" | "RESTRICTED"` that the loader respects (RESTRICTED scenarios refuse to load without an auth token, even if technically reachable).
- **URL state in COMPARE_MODE / shared links** — handle position and scenario id only. No user identifiers. URL state must be validated against the manifest's grid bounds before being applied (otherwise an attacker could craft `?m=NaN` and crash the renderer in the live event).
- **Phase 5 Turso path** — read-only from the client. All write paths (if any — e.g., user-uploaded scenarios) go through a server action with auth, never directly from the client.
- **R precompute** — runs offline against trusted local data; not a runtime surface. The output JSON is the trust boundary.
- **No runtime R server** — keeps with dataimago's "static mode for production" rule. We do not ship a live R kernel to production for this app.
</SECURITY_REVIEW>

**Caching.** Manifest + bundle: `Cache-Control: public, max-age=31536000, immutable` (filenames are content-hashed). Page shell: short cache, ETag-based revalidation.

**Telemetry.** Off by default. If we ever turn it on, only aggregate interactions (drag distances, tour completions) — never identifiers. Honors Do-Not-Track. dataimago's reflexive-practice commitment forbids treating the user as a measurement subject without consent.

---

## 9. Risks, trade-offs, alternatives considered

| Decision | Alternative considered | Why we picked this |
|---|---|---|
| Precompute the induced-V tensor | Compute `F_G(v)` live in WebAssembly | Live compute couples drag latency to copula complexity. Precompute decouples them and is simpler to ship. WASM remains an option if we add user-defined copulas. |
| Static JSON+binary, not Turso, in v1 | Turso from day 1 | One scenario doesn't need a database. Adding Turso later is mechanical because the API client is dual-mode. Premature infra is the most common cause of interactive-vis projects never shipping. |
| D3 v7 from primitives | Recharts, Visx, Observable Plot | We need cross-panel linked state with a custom drag, custom snap behavior, and custom path interpolation. Higher-level libraries fight us on each of these. |
| Beta family of regimes only | Mixture of Betas, non-parametric regime | Matches the existing STEP 3 estimator and the audience's mental model. A richer family is a separate explainer (and risks reintroducing exactly the cognitive overload we are trying to fix). |
| Cross layout | Linear top-to-bottom story | The cross makes the *dependency graph* spatial: #1 and #2 feed #3; #3 drives #4 and #5. Linear order erases this structure. Linear is the mobile fallback only. |
| Single handle | Multi-handle / scrubber | A single draggable point is the felt-causation device. Multi-handle is the COMPARE_MODE extension, not the default. |

**Largest risk:** That the audience scrubs the handle but never *sees* the connection between the dark spot in #3, the shape in #4, and the curve in #5 — the very connection the visualization exists to make. Mitigation is two-fold: (1) the W_1 shaded band in #5 is a continuous tactile reward signal; (2) TOUR_MODE narrates the connection explicitly the first time. We will validate with audience comprehension testing at the Phase 4 gate.

---

## 10. Open questions (need your input before Phase 1)

1. **Audience priority.** Is the v1 target a research talk (desktop, projector, full cross), an online microsite (cross + mobile fallback), or a classroom (must work on student laptops)? Affects how aggressively we optimize for slow devices in v1 versus deferring to Phase 6. Answer: Currently the v1 target is a research talk to colleagues, building on what I felt were comprehension issues in previous talks. I think presenting these pieces together with the interaction will give my colleagues a sense of efficacy in terms of what is going on. It's a simple idea mathematically (once you have Sklar's theorem, a copula, and distribution function language to express the transition kernel). NOTE: The ideal situation is to embed this into a revealJS presentation that I've constructed (/Users/conet/Research/Papers/Betebenner_Braun/Paper_1/NCIEA_2026_Colloquium_Staff_Presentation.qmd)
2. **Single scenario or selector at launch?** I recommend single scenario for v1 (faster, sharper story); selector arrives in Phase 5. Confirm. Answer: Yes, let's begin with a single scenario. 
3. **Synthetic vs. Phase A real data for the public demo.** The R pipeline supports both via `STEP3_EXPORT_MODE`. My instinct: ship synthetic for the public site (no policy/privacy questions, story is cleaner) and offer Phase A as a download or auth-gated scenario. Confirm. The data is de-identified and I'd like to try and do this with non-synthetic data (I believe the margin figure is using actual data which was an intention upgrade of the Margin infographic from the original Overview infographic)
4. **Brand alignment / repo home.** Option A standalone for v1 (recommended) vs. Option B in dataimago-ai from day 1. The technical work is similar; the difference is up-front coupling cost vs. promotion cost. Answer: Let's work on the standalone before we get ahead of ourselves integrating into dataimago-ai or some other dataimago property (it will eventually go into)
5. **Copula switching priority.** v1 fixes the canonical t-copula. v2 lets the audience switch (`t / frank / gaussian / clayton / gumbel`). Is switching part of the explainer story, or a separate "copula sensitivity" tool? My read is the latter — keeping #2 fixed lets #3 stay the protagonist. Answer: Yes, it is a latter "copula sensitivity" tool and not necessary at this point. 
6. **PDF vs. CDF default view.** The PDF prototype implies both are first-class. My instinct: default to **PDF** for #1 and #4 (densities are more familiar), default to **CDF** for #5 (so the W_1 shaded band is visible immediately). Confirm. Answer: This is a great question. In the presentation I'm imagining, we begin with two (actually four) densitities: Population/subgroup x prior/current. Ideally I'd like to be able to illustrate the prior/current subgroup densities to start (toggle for subgroup and population) but be able to elegantly transition to a CDF picture -- allowing the user to see the beautiful dance that is being done mathematically and orchestrated by Sklar's theorem and the growth regime. If Wassterstein-1 distance is shown, that is definitely a CDF distance and doesn't make sense with densities. 
7. **W_1 readout precision.** Three significant figures (`W₁ = 0.0132`)? Or two-digit percent of the U(0,1) baseline distance (`53% of baseline`)? Or both? Answer: Both please. 

---

## 11. What the next iteration of this document should add

After we settle the Section 10 questions:

- **Wireframe sketches** (low-fi) of all five panels at the desktop breakpoint, with token annotations.
- **Storyboard frames** for TOUR_MODE — exact handle path, captions, pauses.
- **Detailed type definitions** for the manifest and bundle (TypeScript + JSON Schema).
- **R function signatures** for `liwld_precompute`, `induced_cdf`, `wasserstein_grid`.
- **Acceptance test plan** for each phase gate.
- **A `wiki/decisions/` ADR** capturing the dual-storage choice, the Beta-family-only choice, and the cross-layout choice — because all three will be re-litigated by future-us if we don't pin them down.

---

*This plan is intentionally opinionated about user experience and intentionally conservative about infrastructure. The math story is the hard part; the platform should disappear behind it.*

---

## 12. Embed-into-RevealJS plan

The visualization will live inside `~/Research/Papers/Betebenner_Braun/Paper_1/NCIEA_2026_Colloquium_Staff_Presentation.qmd` as a slide. Three viable embed strategies, in increasing complexity:

**Strategy A — Iframe pointing at a sibling folder (recommended for v1).**
1. Build the Vite app: `pnpm --filter app build` → produces `D3_Interactive/app/dist/`.
2. Copy or symlink `dist/` next to the `.qmd` (e.g., `Paper_1/assets/liwld/`).
3. In the slide:
   ```html
   <section data-background-color="#ffffff">
     <h2>From observed marginals to inferred regime</h2>
     <iframe src="assets/liwld/index.html?embed=1"
             width="1280" height="720"
             style="border:0;background:transparent"
             allow="fullscreen"></iframe>
   </section>
   ```
4. The `?embed=1` flag tells the app to render in embed-mode layout (no chrome, fixed canvas).

**Pros:** Full isolation — Reveal can't break the app, the app can't break Reveal. Works over `file://`. Survives slide-deck reorganization.
**Cons:** Iframe focus management can be fiddly (keyboard nav inside the iframe doesn't reach Reveal's slide-advance keys, and vice versa). Mitigation: a small `postMessage` bridge that lets the app intercept its own keys (arrows, space) and forward everything else to the parent.

**Strategy B — Inlined HTML fragment via Quarto's `{=html}` raw block.**
- For a single-page bundle small enough to inline, paste the built HTML directly into the `.qmd`. Eliminates the iframe but couples the slide to the bundle. Only worth it if the bundle ends up tiny (< 100 KB JS).

**Strategy C — Quarto extension wrapping the app.**
- Long-term: a `dataimago` Quarto extension that exposes a `{{< liwld scenario="…" >}}` shortcode. Out of scope for v1; tracked for the eventual dataimago promotion.

**v1 commitment:** Strategy A. The Vite app reads `?embed=1` and switches to the embed layout. The build emits `dist/` with content-hashed assets that can be dropped next to any `.qmd` without modification.
