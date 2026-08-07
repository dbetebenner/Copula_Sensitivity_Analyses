/**
 * PanelU.tsx — Panel #1: Prior pseudo-observation U distribution.
 *
 * Phase 2d:
 *   - Subscribes to the global view mode (PDF ↔ CDF) and population toggle.
 *   - Animates the morph via `useTweenedValue` (cubic-out, ~480 ms).
 *   - Same x-grid for both modes; y-domain unifies to max(max(pdf), 1) so
 *     the curves occupy the same vertical space at both endpoints.
 */

import { useMemo, useRef } from 'react';
import type { JSX } from 'react';

import { line as d3Line } from 'd3-shape';
import { scaleLinear } from 'd3-scale';

import { DIST_MARGINS, plotArea, useResponsiveSize, fmt2 } from '../../lib/viz';
import { useTweenedValue } from '../../lib/tween';
import { useAppStore } from '../../store';
import type { Bundle } from '../../types';
import styles from './PanelU.module.css';

export interface PanelUProps {
  bundle: Bundle;
}

export function PanelU({ bundle }: PanelUProps): JSX.Element {
  const ref = useRef<HTMLDivElement>(null);
  const size = useResponsiveSize(ref);
  const p1 = bundle.panel_1;

  const viewMode = useAppStore((s) => s.viewMode);
  const populationVisible = useAppStore((s) => s.populationVisible);
  const t = useTweenedValue(viewMode === 'cdf' ? 1 : 0);

  const view = useMemo(() => {
    if (size.width === 0 || size.height === 0) return null;
    const area = plotArea(size, DIST_MARGINS);
    if (area.innerWidth <= 0 || area.innerHeight <= 0) return null;

    // Unified y-domain: enough headroom for either mode's max value.
    const yMax = Math.max(...p1.pdf_pop, ...p1.pdf_sub, 1) * 1.08 || 1;

    const x = scaleLinear().domain([0, 1]).range([0, area.innerWidth]);
    const y = scaleLinear().domain([0, yMax]).range([area.innerHeight, 0]);

    // Morphed values per index: y(t) = (1-t) · pdf + t · cdf.
    const popMorph = blend(p1.pdf_pop, p1.cdf_pop, t);
    const subMorph = blend(p1.pdf_sub, p1.cdf_sub, t);

    const lineGen = d3Line<number>()
      .x((_, i) => x(p1.u[i] ?? 0))
      .y((d) => y(d));

    return {
      area,
      x,
      y,
      yMax,
      popPath: lineGen(popMorph) ?? '',
      subPath: lineGen(subMorph) ?? '',
      areaPath: areaUnder(p1.u, subMorph, x, y, area.innerHeight) ?? '',
    };
  }, [size, p1, t]);

  return (
    <div ref={ref} className={styles.host}>
      {view && (
        <svg
          width={view.area.width}
          height={view.area.height}
          viewBox={`0 0 ${view.area.width} ${view.area.height}`}
          role="img"
          aria-label={`Prior U: ${viewMode.toUpperCase()} view${populationVisible ? '' : ', population hidden'}`}
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

            {/* subgroup density (filled) */}
            <path d={view.areaPath} className={styles.subFill} />

            {/* population reference */}
            {populationVisible && <path d={view.popPath} className={styles.popLine} />}

            {/* subgroup density */}
            <path d={view.subPath} className={styles.subLine} />
          </g>
        </svg>
      )}
    </div>
  );
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
