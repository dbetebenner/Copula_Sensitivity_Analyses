/**
 * PanelBeta.tsx — Panel #4: the growth-regime density g(p) / CDF G(p).
 *
 * Phase 2d: morphs PDF↔CDF via the global view-mode store.  The faint
 * uniform reference also morphs — it's y=1 in PDF mode (Uniform PDF) and
 * the diagonal y=p in CDF mode (Uniform CDF).
 */

import { useMemo, useRef } from 'react';
import type { JSX } from 'react';

import { line as d3Line } from 'd3-shape';
import { scaleLinear } from 'd3-scale';

import { betaCdf, betaPdf, shapeFromMK } from '../../lib/beta';
import { DIST_MARGINS, plotArea, useResponsiveSize, fmt2 } from '../../lib/viz';
import { useTweenedValue } from '../../lib/tween';
import { selectHandleM, selectHandleK, useAppStore } from '../../store';
import type { Bundle } from '../../types';
import styles from './PanelBeta.module.css';

const N_GRID = 200;

export interface PanelBetaProps {
  bundle: Bundle;
}

export function PanelBeta({ bundle: _bundle }: PanelBetaProps): JSX.Element {
  const ref = useRef<HTMLDivElement>(null);
  const size = useResponsiveSize(ref);

  // Live handle drives Beta(m, κ) — Phase 3.
  const handleM = useAppStore(selectHandleM);
  const handleK = useAppStore(selectHandleK);

  const viewMode = useAppStore((s) => s.viewMode);
  const t = useTweenedValue(viewMode === 'cdf' ? 1 : 0);

  const view = useMemo(() => {
    if (size.width === 0 || size.height === 0) return null;
    const area = plotArea(size, DIST_MARGINS);
    if (area.innerWidth <= 0 || area.innerHeight <= 0) return null;

    const { alpha, beta } = shapeFromMK(handleM, handleK);

    const ps = new Float32Array(N_GRID);
    const pdfs = new Float32Array(N_GRID);
    const cdfs = new Float32Array(N_GRID);
    for (let i = 0; i < N_GRID; i++) {
      const p = (i + 0.5) / N_GRID;
      ps[i] = p;
      pdfs[i] = betaPdf(p, alpha, beta);
      cdfs[i] = betaCdf(p, alpha, beta);
    }

    // Unified y-domain: the Beta PDF max can exceed 1 (peaked regimes), but
    // the CDF tops out at 1.  Take max of both so neither endpoint clips.
    let pdfMax = 0;
    for (let i = 0; i < N_GRID; i++) if (pdfs[i]! > pdfMax) pdfMax = pdfs[i]!;
    const yMax = Math.max(pdfMax, 1) * 1.12;

    const x = scaleLinear().domain([0, 1]).range([0, area.innerWidth]);
    const y = scaleLinear().domain([0, yMax]).range([area.innerHeight, 0]);

    // Morphed regime: blend PDF and CDF per index.
    const morphed = new Array<number>(N_GRID);
    for (let i = 0; i < N_GRID; i++) {
      morphed[i] = (1 - t) * pdfs[i]! + t * cdfs[i]!;
    }

    // Uniform reference: y=1 in PDF mode, y=p (diagonal) in CDF mode.
    const uniformRef: { x: number; y: number }[] = [];
    for (let i = 0; i < N_GRID; i++) {
      const p = ps[i]!;
      const yVal = (1 - t) * 1 + t * p;
      uniformRef.push({ x: x(p), y: y(yVal) });
    }
    const uniformRefPath = polyline(uniformRef);

    const lineGen = d3Line<number>()
      .x((_, i) => x(ps[i] ?? 0))
      .y((d) => y(d));

    const fillPath = areaUnder(ps, morphed, x, y, area.innerHeight) ?? '';
    const linePath = lineGen(morphed) ?? '';

    return {
      area,
      x,
      y,
      yMax,
      alpha,
      beta,
      uniformRefPath,
      meanX: x(handleM),
      meanLineY1: y(0),
      meanLineY2: y(yMax),
      fillPath,
      linePath,
    };
  }, [size, handleM, handleK, t]);

  return (
    <div ref={ref} className={styles.host}>
      {view && (
        <svg
          width={view.area.width}
          height={view.area.height}
          viewBox={`0 0 ${view.area.width} ${view.area.height}`}
          role="img"
          aria-label={`Beta growth regime at handle (${viewMode.toUpperCase()}): m = ${handleM.toFixed(3)}, kappa = ${handleK.toFixed(2)}`}
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

            {/* Uniform reference (y=1 ↔ y=p) — faint dashed grey */}
            <path d={view.uniformRefPath} className={styles.uniformRef} />

            {/* Beta regime — fills + line */}
            <path d={view.fillPath} className={styles.fill} />
            <path d={view.linePath} className={styles.line} />

            {/* mean vertical at p=m */}
            <line
              x1={view.meanX}
              x2={view.meanX}
              y1={view.meanLineY2}
              y2={view.meanLineY1}
              className={styles.meanLine}
            />

            <text
              x={view.area.innerWidth - 4}
              y={10}
              textAnchor="end"
              className={styles.label}
            >
              {viewMode === 'pdf' ? 'g(p)' : 'G(p)'} — Beta({fmt2(view.alpha)},{' '}
              {fmt2(view.beta)})
            </text>
          </g>
        </svg>
      )}
    </div>
  );
}

function polyline(points: { x: number; y: number }[]): string {
  if (points.length === 0) return '';
  const parts: string[] = [];
  for (let i = 0; i < points.length; i++) {
    const p = points[i]!;
    parts.push(`${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`);
  }
  return parts.join(' ');
}

function areaUnder(
  xs: Float32Array,
  ys: readonly number[],
  xScale: (v: number) => number,
  yScale: (v: number) => number,
  baseline: number,
): string | null {
  if (xs.length === 0) return null;
  const segments: string[] = [];
  segments.push(`M ${xScale(xs[0]!)} ${baseline}`);
  for (let i = 0; i < xs.length; i++) {
    segments.push(`L ${xScale(xs[i]!)} ${yScale(ys[i] ?? 0)}`);
  }
  segments.push(`L ${xScale(xs[xs.length - 1]!)} ${baseline}`);
  segments.push('Z');
  return segments.join(' ');
}
