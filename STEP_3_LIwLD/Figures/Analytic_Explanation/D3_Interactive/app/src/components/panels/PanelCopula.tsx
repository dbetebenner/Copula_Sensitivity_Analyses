/**
 * PanelCopula.tsx — Panel #2: copula CDF contours on the unit square.
 *
 * Phase 2c renders the 9 precomputed contour layers (levels 0.1..0.9)
 * with opacity scaling by level — deeper level = stronger line.
 *
 * Phase 4 may add a hover crosshair that mirrors a U-guide from Panel #1.
 */

import { useMemo, useRef } from 'react';
import type { JSX } from 'react';

import { scaleLinear } from 'd3-scale';

import { SQUARE_MARGINS, plotArea, useResponsiveSize, fmt2 } from '../../lib/viz';
import type { Bundle } from '../../types';
import styles from './PanelCopula.module.css';

const X_TICKS = [0, 0.25, 0.5, 0.75, 1];

export interface PanelCopulaProps {
  bundle: Bundle;
}

export function PanelCopula({ bundle }: PanelCopulaProps): JSX.Element {
  const ref = useRef<HTMLDivElement>(null);
  const size = useResponsiveSize(ref);
  const layers = bundle.panel_2;

  const view = useMemo(() => {
    if (size.width === 0 || size.height === 0) return null;
    const area = plotArea(size, SQUARE_MARGINS);
    if (area.innerWidth <= 0 || area.innerHeight <= 0) return null;

    const x = scaleLinear().domain([0, 1]).range([0, area.innerWidth]);
    const y = scaleLinear().domain([0, 1]).range([area.innerHeight, 0]); // V upward

    // Build path strings per layer.
    const paths = layers.map((layer) => {
      const segments: string[] = [];
      for (const path of layer.paths) {
        if (path.length === 0) continue;
        const head = path[0]!;
        segments.push(`M ${x(head[0]!)} ${y(head[1]!)}`);
        for (let k = 1; k < path.length; k++) {
          const pt = path[k]!;
          segments.push(`L ${x(pt[0]!)} ${y(pt[1]!)}`);
        }
      }
      return { level: layer.level, d: segments.join(' ') };
    });

    return { area, x, y, paths };
  }, [size, layers]);

  return (
    <div ref={ref} className={styles.host}>
      {view && (
        <svg
          width={view.area.width}
          height={view.area.height}
          viewBox={`0 0 ${view.area.width} ${view.area.height}`}
          role="img"
          aria-label="Copula CDF contours on the unit square (u, v)"
        >
          <g transform={`translate(${view.area.margins.left}, ${view.area.margins.top})`}>
            {/* unit-square frame */}
            <rect
              x={0}
              y={0}
              width={view.area.innerWidth}
              height={view.area.innerHeight}
              className={styles.frame}
            />

            {/* contour paths, opacity by level */}
            {view.paths.map((p) => (
              <path
                key={p.level}
                d={p.d}
                className={styles.contour}
                style={{ opacity: 0.22 + 0.6 * p.level }}
              />
            ))}

            {/* x-axis ticks */}
            <line
              x1={0}
              x2={view.area.innerWidth}
              y1={view.area.innerHeight}
              y2={view.area.innerHeight}
              className={styles.axis}
            />
            {X_TICKS.map((t) => (
              <g key={t} transform={`translate(${view.x(t)}, ${view.area.innerHeight})`}>
                <line y2={3} className={styles.axisTick} />
                <text y={14} textAnchor="middle" className={styles.axisLabel}>
                  {fmt2(t)}
                </text>
              </g>
            ))}
            <text
              x={view.area.innerWidth / 2}
              y={view.area.innerHeight + 22}
              textAnchor="middle"
              className={styles.axisName}
            >
              u
            </text>

            {/* y-axis ticks (v) */}
            <line x1={0} x2={0} y1={0} y2={view.area.innerHeight} className={styles.axis} />
            {X_TICKS.map((t) => (
              <g key={t} transform={`translate(0, ${view.y(t)})`}>
                <line x2={-3} className={styles.axisTick} />
                <text x={-6} y={3} textAnchor="end" className={styles.axisLabel}>
                  {fmt2(t)}
                </text>
              </g>
            ))}
            <text
              transform={`translate(-22, ${view.area.innerHeight / 2}) rotate(-90)`}
              textAnchor="middle"
              className={styles.axisName}
            >
              v
            </text>
          </g>
        </svg>
      )}
    </div>
  );
}
