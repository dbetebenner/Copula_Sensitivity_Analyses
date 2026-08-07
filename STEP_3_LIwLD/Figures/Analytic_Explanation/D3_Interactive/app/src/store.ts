/**
 * store.ts — global view state for the LIwLD interactive.
 *
 * Single source of truth for the chrome controls AND every panel's render.
 * Keeping this small is deliberate: the more state lives here, the more
 * coupling you create between unrelated panels.
 *
 * Selector tip for consumers: subscribe to PRIMITIVE fields (e.g. handleM,
 * handleK) not the handle object — Zustand uses Object.is, so primitives
 * stop spurious re-renders when only the unrelated half of state changes.
 */

import { create } from 'zustand';

export type ViewMode = 'pdf' | 'cdf';

export type AppMode = 'explore' | 'tour' | 'compare';

export interface HandlePos {
  m: number;
  k: number;
}

export interface AppState {
  viewMode: ViewMode;
  populationVisible: boolean;
  /** Live (m, κ) handle position in Panel #3 — drives Panels #4 and #5. */
  handle: HandlePos;

  /** Top-level interaction mode.  'tour' auto-runs the scripted walkthrough. */
  appMode: AppMode;
  /** Current step index inside the tour script.  -1 when not in tour mode. */
  tourStep: number;
  /** Whether the tour is currently auto-advancing (vs paused). */
  tourPlaying: boolean;

  setViewMode: (mode: ViewMode) => void;
  toggleViewMode: () => void;

  setPopulationVisible: (visible: boolean) => void;
  togglePopulation: () => void;

  setHandle: (m: number, k: number) => void;

  setAppMode: (mode: AppMode) => void;
  setTourStep: (step: number) => void;
  setTourPlaying: (playing: boolean) => void;
  toggleTourPlaying: () => void;
}

// Sentinel pre-load value.  App.tsx replaces this with manifest.argmin
// once the bundle resolves — the page opens *at the inferred regime*.
const DEFAULT_HANDLE: HandlePos = { m: 0.5, k: 2 };

export const useAppStore = create<AppState>((set) => ({
  viewMode: 'pdf',
  populationVisible: true,
  handle: DEFAULT_HANDLE,

  appMode: 'explore',
  tourStep: -1,
  tourPlaying: false,

  setViewMode: (mode) => set({ viewMode: mode }),
  toggleViewMode: () => set((s) => ({ viewMode: s.viewMode === 'pdf' ? 'cdf' : 'pdf' })),

  setPopulationVisible: (v) => set({ populationVisible: v }),
  togglePopulation: () => set((s) => ({ populationVisible: !s.populationVisible })),

  setHandle: (m, k) => set({ handle: { m, k } }),

  setAppMode: (mode) =>
    set((s) => {
      // Entering tour: auto-start at step 0, playing.
      if (mode === 'tour' && s.appMode !== 'tour') {
        return { appMode: mode, tourStep: 0, tourPlaying: true };
      }
      // Leaving tour: pause and reset step.
      if (s.appMode === 'tour' && mode !== 'tour') {
        return { appMode: mode, tourStep: -1, tourPlaying: false };
      }
      return { appMode: mode };
    }),
  setTourStep: (step) => set({ tourStep: step }),
  setTourPlaying: (playing) => set({ tourPlaying: playing }),
  toggleTourPlaying: () => set((s) => ({ tourPlaying: !s.tourPlaying })),
}));

/** Selector helpers — keep callers honest about subscribing to primitives. */
export const selectHandleM = (s: AppState): number => s.handle.m;
export const selectHandleK = (s: AppState): number => s.handle.k;
