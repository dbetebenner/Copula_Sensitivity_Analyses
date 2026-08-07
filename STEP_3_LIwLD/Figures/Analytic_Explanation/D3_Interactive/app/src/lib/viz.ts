/**
 * lib/viz.ts — visualization utilities shared across panels.
 *
 * Three things:
 *   1. useResponsiveSize — observe container size with ResizeObserver.
 *   2. PANEL_MARGINS — shared margin presets so axes line up across panels.
 *   3. tickValues / formatPercent — small label helpers.
 */

import { useEffect, useState } from 'react';
import type { RefObject } from 'react';

/** Pixel size with sub-pixel precision (the value we get back from ResizeObserver). */
export interface Size {
  width: number;
  height: number;
}

/**
 * Track the bounding box of `ref.current` reactively.
 * Returns `{ width: 0, height: 0 }` until the element mounts.
 */
export function useResponsiveSize<E extends Element>(ref: RefObject<E | null>): Size {
  const [size, setSize] = useState<Size>({ width: 0, height: 0 });

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const obs = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const cr = entry.contentRect;
        setSize({ width: cr.width, height: cr.height });
      }
    });
    obs.observe(el);
    // Seed initial size synchronously.
    const rect = el.getBoundingClientRect();
    setSize({ width: rect.width, height: rect.height });
    return () => obs.disconnect();
  }, [ref]);

  return size;
}

/**
 * Margin preset for distribution panels (Panels 1, 4, 5) — narrow on top/right
 * to maximize plot area; reasonable on bottom/left for tick labels.
 */
export const DIST_MARGINS = { top: 8, right: 8, bottom: 22, left: 28 } as const;

/**
 * Margin preset for square 2D panels (Panels 2 copula, 3 regime grid).
 * Slightly more generous to accommodate axis labels on both axes.
 */
export const SQUARE_MARGINS = { top: 8, right: 8, bottom: 22, left: 32 } as const;

/** A drawing area derived from a container size + margins. */
export interface PlotArea {
  width: number;
  height: number;
  innerWidth: number;
  innerHeight: number;
  margins: { top: number; right: number; bottom: number; left: number };
}

export function plotArea(
  size: Size,
  margins: { top: number; right: number; bottom: number; left: number },
): PlotArea {
  const innerWidth = Math.max(0, size.width - margins.left - margins.right);
  const innerHeight = Math.max(0, size.height - margins.top - margins.bottom);
  return { width: size.width, height: size.height, innerWidth, innerHeight, margins };
}

/** Even-spaced tick values across a [domainMin, domainMax] interval. */
export function ticks(min: number, max: number, count: number): number[] {
  if (count < 2) return [min, max];
  const out: number[] = [];
  for (let i = 0; i < count; i++) {
    out.push(min + ((max - min) * i) / (count - 1));
  }
  return out;
}

/** Format a number as a "0.25"-style label, no trailing zeros. */
export function fmt2(x: number): string {
  return Number.isFinite(x) ? x.toFixed(2).replace(/\.?0+$/, '') : '';
}
