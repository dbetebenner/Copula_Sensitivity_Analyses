/**
 * lib/handle.ts — utilities for Phase 3's draggable regime handle.
 *
 * Three concerns:
 *   1. (m, κ) ↔ fractional grid index conversion (drives bilinear lookup).
 *   2. Snap-to-references in screen pixels (data-space distance feels wrong).
 *   3. W₁ between two CDFs on a shared v-grid (live readout for Panel #5).
 */

import type { Manifest, Bundle } from '../types';

export interface HandleAxes {
  m_min: number;
  m_max: number;
  m_n: number;
  k_min: number;
  k_max: number;
  k_n: number;
  k_scale: 'linear' | 'log';
}

/** Clamp a number into [lo, hi]. */
export function clamp(x: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, x));
}

/**
 * (m, κ) → fractional indices into the regime grid.  The bilinear-interp
 * helper on the induced tensor expects values in [0, m_n - 1] × [0, k_n - 1].
 */
export function fractionalGridIndex(
  m: number,
  k: number,
  axes: HandleAxes,
): { m_idx_f: number; k_idx_f: number } {
  const m_idx_f = ((m - axes.m_min) / (axes.m_max - axes.m_min)) * (axes.m_n - 1);
  let k_idx_f: number;
  if (axes.k_scale === 'log') {
    const lo = Math.log10(axes.k_min);
    const hi = Math.log10(axes.k_max);
    k_idx_f = ((Math.log10(k) - lo) / (hi - lo)) * (axes.k_n - 1);
  } else {
    k_idx_f = ((k - axes.k_min) / (axes.k_max - axes.k_min)) * (axes.k_n - 1);
  }
  return {
    m_idx_f: clamp(m_idx_f, 0, axes.m_n - 1),
    k_idx_f: clamp(k_idx_f, 0, axes.k_n - 1),
  };
}

/**
 * Snap the candidate handle position to a reference if the pointer is within
 * `pxRadius` of it in screen space.  Screen-distance feels right for users —
 * the slate-gray dashed ring (uniform_ref) and the amber target (argmin)
 * both light up at the same visual proximity regardless of (m, κ) scaling.
 *
 * Returns the snapped {m, k} or the input candidate if no snap fired.
 */
export function snapToReferences(
  candidate: { m: number; k: number },
  refs: Array<{ m: number; k: number }>,
  toScreen: (m: number, k: number) => { x: number; y: number },
  pxRadius: number = 12,
): { m: number; k: number } {
  const cs = toScreen(candidate.m, candidate.k);
  let best: { m: number; k: number } | null = null;
  let bestDist = pxRadius;
  for (const ref of refs) {
    const rs = toScreen(ref.m, ref.k);
    const dx = cs.x - rs.x;
    const dy = cs.y - rs.y;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d < bestDist) {
      bestDist = d;
      best = ref;
    }
  }
  return best ?? candidate;
}

/**
 * W₁ between two CDFs on a shared v-grid, via trapezoidal integration of
 * |F_A(v) - F_B(v)|.  In 1D this is the Wasserstein-1 distance — the
 * scalar the estimator minimizes, and the area of Panel #5's shaded band.
 */
export function w1FromCdfs(
  v: readonly number[],
  fA: readonly number[],
  fB: readonly number[],
): number {
  const n = Math.min(v.length, fA.length, fB.length);
  if (n < 2) return 0;
  let sum = 0;
  for (let i = 0; i < n - 1; i++) {
    const dv = (v[i + 1] ?? 0) - (v[i] ?? 0);
    const dA = Math.abs((fA[i] ?? 0) - (fB[i] ?? 0));
    const dB = Math.abs((fA[i + 1] ?? 0) - (fB[i + 1] ?? 0));
    sum += 0.5 * (dA + dB) * dv;
  }
  return sum;
}

/**
 * Convenience: the live W₁ at a handle position, computed against the
 * subgroup-observed CDF using the bundle's bilinear-interpolated induced
 * tensor.  Used for the readout in Panel #5's hint.
 */
export function w1AtHandle(bundle: Bundle, m: number, k: number): number {
  const axes = handleAxes(bundle.manifest);
  const { m_idx_f, k_idx_f } = fractionalGridIndex(m, k, axes);
  const induced = bundle.panel_5_induced.bilinear(m_idx_f, k_idx_f);
  return w1FromCdfs(bundle.panel_5_observed.v, bundle.panel_5_observed.cdf_sub, Array.from(induced));
}

/** Pull the regime-grid axes out of the manifest in the shape this lib expects. */
export function handleAxes(manifest: Manifest): HandleAxes {
  return {
    m_min: manifest.regime_grid.m_min,
    m_max: manifest.regime_grid.m_max,
    m_n: manifest.regime_grid.m_n,
    k_min: manifest.regime_grid.k_min,
    k_max: manifest.regime_grid.k_max,
    k_n: manifest.regime_grid.k_n,
    k_scale: manifest.regime_grid.k_scale,
  };
}
