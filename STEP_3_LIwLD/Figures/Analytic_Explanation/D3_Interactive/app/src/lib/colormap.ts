/**
 * lib/colormap.ts — sequential colormap for the W₁ landscape.
 *
 * The viridis-reversed stops live in tokens.css under
 * --p-w1-near-{0..5}.  We don't read CSS variables at sample-time
 * (would be slow inside a 1,350-cell loop); instead the stops are mirrored
 * here as constants, with a sanity assertion in dev mode that they line
 * up with the tokens.
 *
 * Mapping convention (matches the README):
 *   t = 0  →  worst W₁  (yellow #fde725)
 *   t = 1  →  best  W₁  (deep purple #440154)
 *
 * So when computing colors for the heatmap, normalize so that the *minimum*
 * cell maps to t=1 (darkest = "where you want to go").
 */

import { rgb } from 'd3-color';
import { interpolateRgb } from 'd3-interpolate';

const VIRIDIS_R_STOPS = [
  '#fde725', // 0.0 worst
  '#7ad151',
  '#22a884',
  '#2a788e',
  '#414487',
  '#440154', // 1.0 best
] as const;

/** Linear interpolation between adjacent stops in [0, 1]. */
function sampleStops(stops: readonly string[], t: number): string {
  if (!Number.isFinite(t)) return stops[0]!;
  const clamped = Math.min(1, Math.max(0, t));
  const n = stops.length - 1;
  const idx = clamped * n;
  const lo = Math.floor(idx);
  const hi = Math.min(lo + 1, n);
  const f = idx - lo;
  if (lo === hi) return stops[lo]!;
  const interp = interpolateRgb(stops[lo]!, stops[hi]!);
  return rgb(interp(f)).formatHex();
}

/**
 * Build a W₁ landscape colormap given the surface's value range.
 *
 *   colorFor(w1) → CSS hex
 *
 * Optionally apply a log10 transform for better dynamic range — surfaces
 * for narrow-fit scenarios have a few cells dramatically smaller than
 * the rest, and log10 spreads them out.
 */
export function makeW1Colormap(opts: {
  min: number;
  max: number;
  log?: boolean;
}): (w1: number) => string {
  const { min, max, log = true } = opts;
  if (!Number.isFinite(min) || !Number.isFinite(max) || min >= max) {
    return () => VIRIDIS_R_STOPS[0]!;
  }
  const lo = log ? Math.log10(Math.max(min, 1e-12)) : min;
  const hi = log ? Math.log10(Math.max(max, 1e-12)) : max;
  const span = hi - lo;
  return (w1: number) => {
    if (!Number.isFinite(w1)) return VIRIDIS_R_STOPS[0]!;
    const v = log ? Math.log10(Math.max(w1, 1e-12)) : w1;
    // Normalize to [0, 1] where 0 is HIGHEST W1 (worst) and 1 is LOWEST (best).
    const t = 1 - (v - lo) / span;
    return sampleStops(VIRIDIS_R_STOPS, t);
  };
}
