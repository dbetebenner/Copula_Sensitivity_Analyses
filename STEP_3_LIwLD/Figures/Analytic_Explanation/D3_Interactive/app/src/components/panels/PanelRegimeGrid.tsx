/**
 * PanelRegimeGrid.tsx — Panel #3: the W₁ landscape over the (m, κ) grid.
 *
 * Phase 3:
 *   - Static heatmap (45 × 30 cells) and reference markers (uniform, argmin).
 *   - LIVE draggable handle.  d3-drag on a transparent overlay rect; the
 *     handle position lives in the Zustand store and propagates to Panels
 *     #4 (Beta redraw) and #5 (induced V CDF + W₁ band).
 *   - Snap-to-references with a 12 px magnetic radius (screen distance).
 *   - Cursor: grab on hover, grabbing while dragging.
 */

import { useEffect, useMemo, useRef } from 'react';
import type { JSX } from 'react';

import { scaleLinear } from 'd3-scale';
import { drag as d3Drag } from 'd3-drag';
import { select } from 'd3-selection';

import { makeW1Colormap } from '../../lib/colormap';
import { SQUARE_MARGINS, plotArea, useResponsiveSize, fmt2 } from '../../lib/viz';
import { clamp, snapToReferences } from '../../lib/handle';
import { selectHandleM, selectHandleK, useAppStore } from '../../store';
import type { Bundle } from '../../types';
import styles from './PanelRegimeGrid.module.css';

const Y_TICKS = [2, 5, 10, 25, 60];
const X_TICKS = [0.1, 0.3, 0.5, 0.7, 0.9];
const SNAP_RADIUS_PX = 12;

export interface PanelRegimeGridProps {
  bundle: Bundle;
}

export function PanelRegimeGrid({ bundle }: PanelRegimeGridProps): JSX.Element {
  const ref = useRef<HTMLDivElement>(null);
  const overlayRef = useRef<SVGRectElement>(null);

  const size = useResponsiveSize(ref);
  const { manifest, panel_3, m_grid, k_grid } = bundle;

  const handleM = useAppStore(selectHandleM);
  const handleK = useAppStore(selectHandleK);
  const setHandle = useAppStore((s) => s.setHandle);

  const view = useMemo(() => {
    if (size.width === 0 || size.height === 0) return null;
    const area = plotArea(size, SQUARE_MARGINS);
    if (area.innerWidth <= 0 || area.innerHeight <= 0) return null;

    const { m_n, k_n, m_min, m_max, k_min, k_max } = manifest.regime_grid;
    const dm = (m_max - m_min) / (m_n - 1);
    const dlk = (Math.log10(k_max) - Math.log10(k_min)) / (k_n - 1);

    const x = scaleLinear()
      .domain([m_min - dm / 2, m_max + dm / 2])
      .range([0, area.innerWidth]);
    const y = scaleLinear()
      .domain([Math.log10(k_min) - dlk / 2, Math.log10(k_max) + dlk / 2])
      .range([area.innerHeight, 0]);

    const cellW = area.innerWidth / m_n;
    const cellH = area.innerHeight / k_n;

    let lo = Number.POSITIVE_INFINITY;
    let hi = 0;
    for (let i = 0; i < panel_3.data.length; i++) {
      const v = panel_3.data[i];
      if (v === undefined || !Number.isFinite(v)) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (!Number.isFinite(lo)) lo = manifest.argmin.w1;
    const colorFor = makeW1Colormap({ min: lo, max: hi, log: true });

    const cells: { x: number; y: number; w: number; h: number; fill: string }[] = [];
    for (let i = 0; i < m_n; i++) {
      for (let j = 0; j < k_n; j++) {
        const w1 = panel_3.at(i, j);
        const cx = x(m_grid[i] ?? m_min);
        const cy = y(Math.log10(k_grid[j] ?? k_min));
        cells.push({
          x: cx - cellW / 2,
          y: cy - cellH / 2,
          w: cellW,
          h: cellH,
          fill: colorFor(w1),
        });
      }
    }

    return {
      area,
      x,
      y,
      cells,
      argminPx: { x: x(manifest.argmin.m), y: y(Math.log10(manifest.argmin.k)) },
      uniformPx: { x: x(manifest.uniform_ref.m), y: y(Math.log10(manifest.uniform_ref.k)) },
    };
  }, [size, manifest, panel_3, m_grid, k_grid]);

  // Pixel position of the live handle.
  const handlePx = useMemo(() => {
    if (!view) return null;
    return { x: view.x(handleM), y: view.y(Math.log10(handleK)) };
  }, [view, handleM, handleK]);

  // ---- Drag wiring -----------------------------------------------------------
  // d3-drag normalizes pointer/touch into a single event stream and exposes
  // event.x / event.y in the container's coordinate system (the parent <svg>).
  // Subtracting the inner-plot translate gives us inner-plot coords; from
  // there it's invert + clamp + snap.
  useEffect(() => {
    const overlay = overlayRef.current;
    if (!overlay || !view) return;

    const refs = [
      { m: manifest.argmin.m, k: manifest.argmin.k },
      { m: manifest.uniform_ref.m, k: manifest.uniform_ref.k },
    ];

    const positionFromXY = (containerX: number, containerY: number): { m: number; k: number } => {
      const px = containerX - view.area.margins.left;
      const py = containerY - view.area.margins.top;
      const m = clamp(view.x.invert(px), manifest.regime_grid.m_min, manifest.regime_grid.m_max);
      const log10k = view.y.invert(py);
      const k = clamp(
        Math.pow(10, log10k),
        manifest.regime_grid.k_min,
        manifest.regime_grid.k_max,
      );
      const toScreen = (mm: number, kk: number) => ({
        x: view.x(mm),
        y: view.y(Math.log10(kk)),
      });
      return snapToReferences({ m, k }, refs, toScreen, SNAP_RADIUS_PX);
    };

    const dragBehavior = d3Drag<SVGRectElement, unknown>()
      .on('start', (event) => {
        const next = positionFromXY(event.x, event.y);
        setHandle(next.m, next.k);
        select(overlay).style('cursor', 'grabbing');
      })
      .on('drag', (event) => {
        const next = positionFromXY(event.x, event.y);
        setHandle(next.m, next.k);
      })
      .on('end', () => {
        select(overlay).style('cursor', 'grab');
      });

    select(overlay).call(dragBehavior);
    return () => {
      select(overlay).on('.drag', null);
    };
  }, [view, manifest, setHandle]);

  return (
    <div ref={ref} className={styles.host}>
      {view && (
        <svg
          width={view.area.width}
          height={view.area.height}
          viewBox={`0 0 ${view.area.width} ${view.area.height}`}
          role="img"
          aria-label="Wasserstein-1 surface; drag the amber handle to explore the (m, κ) regime grid"
        >
          <g transform={`translate(${view.area.margins.left}, ${view.area.margins.top})`}>
            <g>
              {view.cells.map((c, idx) => (
                <rect
                  key={idx}
                  x={c.x}
                  y={c.y}
                  width={c.w}
                  height={c.h}
                  fill={c.fill}
                  shapeRendering="crispEdges"
                />
              ))}
            </g>

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
              m
            </text>

            {/* y-axis ticks */}
            <line x1={0} x2={0} y1={0} y2={view.area.innerHeight} className={styles.axis} />
            {Y_TICKS.filter(
              (k) =>
                k >= manifest.regime_grid.k_min - 0.001 &&
                k <= manifest.regime_grid.k_max + 0.001,
            ).map((k) => (
              <g key={k} transform={`translate(0, ${view.y(Math.log10(k))})`}>
                <line x2={-3} className={styles.axisTick} />
                <text x={-6} y={3} textAnchor="end" className={styles.axisLabel}>
                  {k}
                </text>
              </g>
            ))}
            <text
              transform={`translate(-22, ${view.area.innerHeight / 2}) rotate(-90)`}
              textAnchor="middle"
              className={styles.axisName}
            >
              κ
            </text>

            {/* uniform_ref reference marker (static) */}
            <g transform={`translate(${view.uniformPx.x}, ${view.uniformPx.y})`}>
              <circle r={5} className={styles.markerUniform} />
              <text x={8} y={3} className={styles.markerLabelLight}>
                U(0,1)
              </text>
            </g>

            {/* argmin reference marker (static; live handle is separate).
                Label reads "Ĝ_S" — matches the estimator notation in the
                KaTeX strip above (Ĝ_S = arg min over the Beta family).
                Anchored on the LEFT of the marker so it doesn't collide
                with the U(0,1) label, which sits just below-right of here
                in the canonical Phase A scenario. */}
            <g transform={`translate(${view.argminPx.x}, ${view.argminPx.y})`}>
              <circle r={4} className={styles.markerArgminRef} />
              <line x1={-6} x2={6} className={styles.markerArgminCross} />
              <line y1={-6} y2={6} className={styles.markerArgminCross} />
              <text
                x={-9}
                y={3}
                textAnchor="end"
                className={`${styles.markerLabelLight} ${styles.markerLabelMath}`}
                aria-label="argmin (G-hat sub S)"
              >
                {'Ĝ'}
                <tspan dy={3} fontSize="0.72em">
                  S
                </tspan>
              </text>
            </g>

            {/* Drag overlay — invisible, captures pointer events. */}
            <rect
              ref={overlayRef}
              x={0}
              y={0}
              width={view.area.innerWidth}
              height={view.area.innerHeight}
              className={styles.dragOverlay}
            />

            {/* Live handle (drawn last so it sits on top of the markers). */}
            {handlePx && (
              <g
                transform={`translate(${handlePx.x}, ${handlePx.y})`}
                className={styles.handle}
                aria-hidden="true"
              >
                <circle r={11} className={styles.handleHalo} />
                <circle r={6} className={styles.handleDot} />
              </g>
            )}
          </g>
        </svg>
      )}
    </div>
  );
}
