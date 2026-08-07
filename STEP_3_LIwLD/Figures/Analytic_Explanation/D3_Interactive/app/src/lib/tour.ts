/**
 * lib/tour.ts — the scripted walkthrough that powers Tour mode.
 *
 * Each step is a waypoint: a target handle position, an optional view-mode
 * change, an optional population visibility toggle, a caption, and timings.
 * The controller (`useTourController`) animates the handle in (m, log₁₀κ)
 * space toward the next step's target with cubic-out easing, then waits for
 * the step's `durationMs` before auto-advancing.
 *
 * Total tour length: ~25 seconds.  Auto-loops at the end.  Honors
 * prefers-reduced-motion: transitions snap instantly.
 */

import { useEffect, useRef } from 'react';

import type { Bundle } from '../types';
import { useAppStore } from '../store';

export interface TourStep {
  id: string;
  caption: string;
  handle?: { m: number; k: number };
  viewMode?: 'pdf' | 'cdf';
  populationVisible?: boolean;
  /** How long to dwell on this step before auto-advancing. */
  durationMs: number;
  /** Duration of the morph TO this step's targets. Defaults to 700 ms. */
  transitionMs?: number;
}

export function buildTour(bundle: Bundle): TourStep[] {
  const { argmin, uniform_ref } = bundle.manifest;

  return [
    {
      id: 'inputs',
      caption:
        'Start with the inputs: prior U on the left, current V on the right — both as densities. Grey is the population baseline; teal is the subgroup.',
      handle: { m: argmin.m, k: argmin.k },
      viewMode: 'pdf',
      populationVisible: true,
      durationMs: 4500,
      transitionMs: 600,
    },
    {
      id: 'cdf-reveal',
      caption:
        'Switch to the CDF view. The shaded teal band on the right is W₁ — the area between the observed and inferred CDFs. It is what the estimator minimizes.',
      viewMode: 'cdf',
      durationMs: 4500,
    },
    {
      id: 'uniform',
      caption:
        'If we used Uniform(0,1) — a no-information regime — the induced V drifts wildly off target. Watch the band swell.',
      handle: { m: uniform_ref.m, k: uniform_ref.k },
      durationMs: 4500,
      transitionMs: 1200,
    },
    {
      id: 'mid',
      caption:
        'Sliding toward the dark valley shrinks the band. Each (m, κ) cell encodes a different growth story for the subgroup.',
      handle: { m: 0.42, k: 10 },
      durationMs: 4500,
      transitionMs: 1400,
    },
    {
      id: 'argmin-final',
      caption:
        `The minimum-distance regime — Ĝ_S — fits the observed V to within ${pctOfBaseline(argmin.w1, uniform_ref.w1)}% of the baseline distance. That is the inferred regime.`,
      handle: { m: argmin.m, k: argmin.k },
      durationMs: 5500,
      transitionMs: 1300,
    },
    {
      id: 'wrap',
      caption:
        'From unlinked cross-sections, we recovered a growth regime — no student-level pairing required. Longitudinal inference without longitudinal data.',
      durationMs: 5500,
    },
  ];
}

function pctOfBaseline(w1: number, baseline: number): number {
  if (!baseline || baseline <= 0) return 0;
  return Math.round((w1 / baseline) * 100);
}

/**
 * useTourController — drives the tour state machine.  Mount this once
 * (App.tsx).  When tourPlaying is true and tourStep is in range, applies
 * the step's view-mode/population flags, animates the handle to the step's
 * target, then auto-advances after `durationMs`.
 *
 * Looping: when the last step's timer fires, advance to step 0.
 */
export function useTourController(steps: TourStep[]): void {
  const tourPlaying = useAppStore((s) => s.tourPlaying);
  const tourStep = useAppStore((s) => s.tourStep);

  // Keep the latest step list in a ref so we don't restart timers when the
  // bundle (and so the steps array) recomputes.
  const stepsRef = useRef(steps);
  stepsRef.current = steps;

  useEffect(() => {
    if (!tourPlaying) return;
    if (tourStep < 0) return;
    const step = stepsRef.current[tourStep];
    if (!step) return;

    const store = useAppStore.getState();

    if (step.viewMode) store.setViewMode(step.viewMode);
    if (step.populationVisible !== undefined) {
      store.setPopulationVisible(step.populationVisible);
    }

    let cancelled = false;

    // Handle motion: cubic-ease in (m, log₁₀κ) space.
    const reduced =
      typeof window !== 'undefined' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (step.handle) {
      const targetM = step.handle.m;
      const targetK = step.handle.k;
      if (reduced) {
        store.setHandle(targetM, targetK);
      } else {
        const start = { m: store.handle.m, k: store.handle.k };
        const startTime = performance.now();
        const transitionMs = step.transitionMs ?? 700;
        const tick = (): void => {
          if (cancelled) return;
          const elapsed = performance.now() - startTime;
          const t = Math.min(1, elapsed / transitionMs);
          const eased = 1 - Math.pow(1 - t, 3);
          const m = start.m + (targetM - start.m) * eased;
          const log10k =
            Math.log10(start.k) + (Math.log10(targetK) - Math.log10(start.k)) * eased;
          useAppStore.getState().setHandle(m, Math.pow(10, log10k));
          if (t < 1) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      }
    }

    // Auto-advance after this step's dwell time.
    const timer = setTimeout(() => {
      if (cancelled) return;
      const next = (tourStep + 1) % stepsRef.current.length;
      useAppStore.getState().setTourStep(next);
    }, step.durationMs);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [tourPlaying, tourStep]);
}
