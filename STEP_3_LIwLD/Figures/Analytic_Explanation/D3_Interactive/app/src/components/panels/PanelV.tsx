/**
 * PanelV.tsx — Panel #5: Current pseudo-observation V distribution.
 *
 * Phase 2d:
 *   - Three curves morph simultaneously (pop, sub_obs, sub_induced @ argmin).
 *   - W₁ shaded band fades in proportional to t (CDF-mode reveal).  The band
 *     is the closed L¹ region between sub_obs_cdf and sub_induced_cdf — and
 *     in 1D the L¹ area equals the Wasserstein-1 distance.  That's the
 *     visual identity that makes the estimator legible.
 */

import { useMemo, useRef } from 'react';
import type { JSX } from 'react';

import { line as d3Line } from 'd3-shape';
import { scaleLinear } from 'd3-scale';

import { DIST_MARGINS, plotArea, useResponsiveSize, fmt2 } from '../../lib/viz';
import { useTweenedValue } from '../../lib/tween';
import { fractionalGridIndex, handleAxes } from '../../lib/handle';
import { selectHandleM, selectHandleK, useAppStore } from '../../store';
import type { Bundle } from '../../types';
import styles from './PanelV.module.css';

export interface PanelVProps {
  bundle: Bundle;
}

export function PanelV({ bundle }: PanelVProps): JSX.Element {
  const ref = useRef<HTMLDivElement>(null);
  const size = useResponsiveSize(ref);
  const { manifest, panel_5_observed: obs, panel_5_induced: ind } = bundle;

  const viewMode = useAppStore((s) => s.viewMode);
  const populationVisible = useAppStore((s) => s.populationVisible);
  // Live handle — drives the induced V CDF and the W₁ band (Phase 3).
  const handleM = useAppStore(selectHandleM);
  const handleK = useAppStore(selectHandleK);
  const t = useTweenedValue(viewMode === 'cdf' ? 1 : 0);

  const view = useMemo(() => {
    if (size.width === 0 || size.height === 0) return null;
    const area = plotArea(size, DIST_MARGINS);
    if (area.innerWidth <= 0 || area.innerHeight <= 0) return null;

    // Induced curves at the live handle position via bilinear interp.
    const axes = handleAxes(manifest);
    const { m_idx_f, k_idx_f } = fractionalGridIndex(handleM, handleK, axes);
    const inducedCdf = Array.from(ind.bilinear(m_idx_f, k_idx_f));
    const inducedPdfArr = pdfFromCdf(obs.v, inducedCdf);

    const yMax =
      Math.max(...obs.pdf_pop, ...obs.pdf_sub, ...inducedPdfArr, 1) * 1.08 || 1;

    const x = scaleLinear().domain([0, 1]).range([0, area.innerWidth]);
    const y = scaleLinear().domain([0, yMax]).range([area.innerHeight, 0]);

    const popMorph = blend(obs.pdf_pop, obs.cdf_pop, t);
    const subObsMorph = blend(obs.pdf_sub, obs.cdf_sub, t);
    const subIndMorph = blend(inducedPdfArr, inducedCdf, t);

    const lineGen = d3Line<number>()
      .x((_, i) => x(obs.v[i] ?? 0))
      .y((d) => y(d));

    return {
      area,
      x,
      y,
      yMax,
      popPath: lineGen(popMorph) ?? '',
      subObsPath: lineGen(subObsMorph) ?? '',
      subFillPath: areaUnder(obs.v, subObsMorph, x, y, area.innerHeight) ?? '',
      subInducedPath: lineGen(subIndMorph) ?? '',
      // W₁ band: closed area between sub_obs_cdf and sub_induced_cdf.  In
      // PDF mode (t=0) it's invisible; opacity rises with t.
      w1BandPath: w1Band(obs.v, obs.cdf_sub, inducedCdf, x, y) ?? '',
      bandOpacity: t * 0.55,
    };
  }, [size, obs, ind, manifest, handleM, handleK, t]);

  return (
    <div ref={ref} className={styles.host}>
      {view && (
        <svg
          width={view.area.width}
          height={view.area.height}
          viewBox={`0 0 ${view.area.width} ${view.area.height}`}
          role="img"
          aria-label={`Current V: ${viewMode.toUpperCase()} view${populationVisible ? '' : ', population hidden'}`}
        >
          <g transform={`translate(${view.area.margins.left}, ${view.area.margins.top})`}>
            <line
              x1={0}
              x2={view.area.innerWidth}
              y1={view.area.innerHeight}
              y2={view.area.innerHeight}
              className={styles.axis}
            />
            {[0, 0.25, 0.5, 0.75, 1].map((tk) => (
              <g key={tk} transform={`translate(${view.x(tk)}, ${view.area.innerHeight})`}>
                <line y2={3} className={styles.axisTick} />
                <text y={14} textAnchor="middle" className={styles.axisLabel}>
                  {fmt2(tk)}
                </text>
              </g>
            ))}

            {/* subgroup observed (filled) */}
            <path d={view.subFillPath} className={styles.subFill} />

            {/* W₁ band — only meaningful in CDF mode; opacity tracks t */}
            <path
              d={view.w1BandPath}
              className={styles.w1Band}
              style={{ opacity: view.bandOpacity }}
            />

            {/* population reference */}
            {populationVisible && <path d={view.popPath} className={styles.popLine} />}

            {/* subgroup observed */}
            <path d={view.subObsPath} className={styles.subObsLine} />

            {/* subgroup induced @ argmin */}
            <path d={view.subInducedPath} className={styles.subInducedLine} />
          </g>
        </svg>
      )}
    </div>
  );
}

/**
 * Estimate PDF from CDF via centered finite difference, then Gaussian-smooth.
 *
 * The induced V CDF tensor is Uint8-quantized (~±0.5/255 ≈ ±0.002 per
 * value), and finite differentiation amplifies that noise by 1/dv (~200×
 * for our v-grid).  Without smoothing the derived PDF is dominated by
 * quantization noise — visible as ~40% spikes against the true smooth
 * signal.  A narrow Gaussian filter (σ ≈ 2.5 indices ≈ 0.012 in v-space)
 * removes the quantization without distorting real features (which span
 * 0.1+ in v-space for any reasonable Beta × t-copula combo).
 */
function pdfFromCdf(v: readonly number[], cdf: readonly number[]): number[] {
  const n = cdf.length;
  const raw = new Array<number>(n);
  for (let i = 0; i < n; i++) {
    const lo = Math.max(0, i - 1);
    const hi = Math.min(n - 1, i + 1);
    const dv = (v[hi] ?? 1) - (v[lo] ?? 0);
    raw[i] = dv > 0 ? Math.max(0, ((cdf[hi] ?? 0) - (cdf[lo] ?? 0)) / dv) : 0;
  }
  return smoothGaussian(raw, 2.5, 6);
}

/** Gaussian-weighted moving average with edge handling (renormalize at boundaries). */
function smoothGaussian(values: readonly number[], sigma: number, radius: number): number[] {
  const n = values.length;
  // Precompute kernel: w[k] = exp(-k²/2σ²)
  const weights = new Array<number>(2 * radius + 1);
  for (let k = -radius; k <= radius; k++) {
    weights[k + radius] = Math.exp(-(k * k) / (2 * sigma * sigma));
  }
  const out = new Array<number>(n);
  for (let i = 0; i < n; i++) {
    let sum = 0;
    let weightSum = 0;
    for (let k = -radius; k <= radius; k++) {
      const idx = i + k;
      if (idx >= 0 && idx < n) {
        const w = weights[k + radius]!;
        sum += (values[idx] ?? 0) * w;
        weightSum += w;
      }
    }
    out[i] = weightSum > 0 ? sum / weightSum : 0;
  }
  return out;
}

/** Per-index linear blend of two arrays of the same length. */
function blend(a: readonly number[], b: readonly number[], t: number): number[] {
  const n = Math.min(a.length, b.length);
  const out = new Array<number>(n);
  for (let i = 0; i < n; i++) {
    out[i] = (1 - t) * (a[i] ?? 0) + t * (b[i] ?? 0);
  }
  return out;
}

/** Closed L¹ region between two CDFs over the same v-grid. */
function w1Band(
  v: readonly number[],
  fA: readonly number[],
  fB: readonly number[],
  xScale: (x: number) => number,
  yScale: (y: number) => number,
): string | null {
  const n = Math.min(v.length, fA.length, fB.length);
  if (n === 0) return null;
  // Forward along fA, then back along fB → closed polygon.
  const fwd: string[] = [];
  for (let i = 0; i < n; i++) {
    const cmd = i === 0 ? 'M' : 'L';
    fwd.push(`${cmd} ${xScale(v[i] ?? 0)} ${yScale(fA[i] ?? 0)}`);
  }
  for (let i = n - 1; i >= 0; i--) {
    fwd.push(`L ${xScale(v[i] ?? 0)} ${yScale(fB[i] ?? 0)}`);
  }
  fwd.push('Z');
  return fwd.join(' ');
}

function areaUnder(
  xs: readonly number[],
  ys: readonly number[],
  xScale: (v: number) => number,
  yScale: (v: number) => number,
  baseline: number,
): string | null {
  if (xs.length === 0) return null;
  const segments: string[] = [];
  segments.push(`M ${xScale(xs[0]!)} ${baseline}`);
  for (let i = 0; i < xs.length; i++) {
    segments.push(`L ${xScale(xs[i]!)} ${yScale(ys[i]!)}`);
  }
  segments.push(`L ${xScale(xs[xs.length - 1]!)} ${baseline}`);
  segments.push('Z');
  return segments.join(' ');
}
