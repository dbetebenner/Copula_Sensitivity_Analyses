/* types.ts — TypeScript mirror of D3_Interactive/schema/manifest.schema.json.
 *
 * Hand-maintained for v1.  When we promote into dataimago-ai we'll switch to
 * a generated module via json-schema-to-typescript or quicktype.  Until then,
 * keep this file in lockstep with the JSON Schema — drift will surface either
 * as runtime SHA-256 mismatches or as TypeScript errors at the loader site.
 */

// ────────────────────────────────────────────────────────────────────────────
// Manifest
// ────────────────────────────────────────────────────────────────────────────

export type DataSource = 'SYNTHETIC' | 'PHASE_A_REAL_DATA';
export type DataClassification = 'PUBLIC' | 'INTERNAL' | 'RESTRICTED';
export type CopulaFamily = 't' | 'gaussian' | 'frank' | 'clayton' | 'gumbel';
export type GridScale = 'linear' | 'log';

export interface Cohort {
  grade_prior: number;
  grade_current: number;
  year_prior: string;
  year_current: string;
  content_area: string;
  subgroup_filter?: string;
}

export interface CopulaSpec {
  family: CopulaFamily;
  rho?: number;
  df?: number;
  /** Integer df used only for Panel 2 contour rendering. Statistical record uses `df`. */
  df_display?: number;
  tau?: number;
  tail_dep_lower?: number;
  tail_dep_upper?: number;
}

export interface RegimeGridSpec {
  m_min: number;
  m_max: number;
  m_n: number;
  m_scale?: 'linear';
  k_min: number;
  k_max: number;
  k_n: number;
  k_scale: GridScale;
}

export interface VGridSpec {
  v_min: number;
  v_max: number;
  v_n: number;
}

export interface RegimePoint {
  m: number;
  k: number;
  w1: number;
  m_idx?: number;
  k_idx?: number;
}

export interface ManifestFiles {
  panel_1_u: string;
  panel_2_copula: string;
  panel_3_grid: string;
  panel_5_observed_v: string;
  panel_5_induced_v: string;
}

export type ManifestFileKey = keyof ManifestFiles;

export interface BuildProvenance {
  timestamp_utc: string;
  tool: 'liwld_precompute.R';
  tool_version: string;
  r_version?: string;
  host?: string;
}

export interface Manifest {
  schema_version: '1.0.0';
  scenario_id: string;
  label: string;
  data_source: DataSource;
  data_classification: DataClassification;
  cohort: Cohort;
  n_subgroup: number;
  n_population: number;
  copula: CopulaSpec;
  regime_grid: RegimeGridSpec;
  v_grid: VGridSpec;
  argmin: Required<Pick<RegimePoint, 'm' | 'k' | 'w1' | 'm_idx' | 'k_idx'>>;
  uniform_ref: RegimePoint;
  files: ManifestFiles;
  checksums: Record<string, string>;
  build: BuildProvenance;
}

// ────────────────────────────────────────────────────────────────────────────
// Panel data shapes
// ────────────────────────────────────────────────────────────────────────────

export interface Panel1Data {
  /** Shared u-axis (length v_n by current convention). */
  u: number[];
  pdf_pop: number[];
  pdf_sub: number[];
  cdf_pop: number[];
  cdf_sub: number[];
}

export interface Panel2ContourLayer {
  level: number;
  /** Each path is an Mx2 array of (u, v) points. */
  paths: number[][][];
}
export type Panel2Data = Panel2ContourLayer[];

export interface Panel5ObservedData {
  v: number[];
  pdf_pop: number[];
  pdf_sub: number[];
  cdf_pop: number[];
  cdf_sub: number[];
}

/**
 * Panel 3 — Wasserstein surface over the (m, κ) grid.
 *   data:   Float32Array of length m_n * k_n, row-major.
 *   at(i,j) returns w1 at (m_grid[i], k_grid[j]).
 */
export interface Panel3Surface {
  data: Float32Array;
  m_n: number;
  k_n: number;
  /** Convenience accessor; w1 at integer grid index (m_idx, k_idx). */
  at: (m_idx: number, k_idx: number) => number;
}

/**
 * Panel 5 — Induced V CDF tensor over the (m, κ) grid.
 *   data:   Uint8Array of length m_n * k_n * v_n, row-major in (m, k, v).
 *   atCell  returns the v_n-length CDF for an integer regime cell as Float32.
 *   bilinear interpolates between four neighbor cells given (m_idx_f, k_idx_f).
 */
export interface Panel5InducedTensor {
  data: Uint8Array;
  m_n: number;
  k_n: number;
  v_n: number;
  /** Decode at integer cell (m_idx, k_idx). Returns a fresh Float32Array. */
  atCell: (m_idx: number, k_idx: number) => Float32Array;
  /** Bilinear-interpolate at fractional indices (in [0, m_n-1] and [0, k_n-1]). */
  bilinear: (m_idx_f: number, k_idx_f: number) => Float32Array;
}

// ────────────────────────────────────────────────────────────────────────────
// The fully-loaded scenario bundle
// ────────────────────────────────────────────────────────────────────────────

export interface Bundle {
  manifest: Manifest;
  /** The grid axes, evaluated from the manifest spec for reuse. */
  m_grid: Float64Array;
  k_grid: Float64Array;
  v_grid: Float64Array;
  panel_1: Panel1Data;
  panel_2: Panel2Data;
  panel_3: Panel3Surface;
  panel_5_observed: Panel5ObservedData;
  panel_5_induced: Panel5InducedTensor;
}
