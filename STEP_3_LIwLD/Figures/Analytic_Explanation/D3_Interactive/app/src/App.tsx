/**
 * App.tsx — orchestrator for the LIwLD interactive.
 *
 *   loading                       loading                spinner
 *   ────────  ──►  ready  ──►  ─────────────────────────────────
 *               (Bundle)         standalone:  Chrome + Cross
 *                                embed:       just Cross (1280×720)
 *                                diagnostic:  BundleDiagnostic
 *
 * Routes (URL query string):
 *   ?embed=1        → no chrome, fixed 1280 × 720, RevealJS-friendly
 *   ?diagnostic=1   → show the BundleDiagnostic card (Phase 2a verifier)
 *   ?scenario=ID    → override the default scenario id
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties, JSX } from 'react';

import { loadScenario, LiwldLoadError } from './data-loader';
import type { Bundle } from './types';
import { parseAppRoute, type AppRouteParams } from './lib/url';
import { useAppStore } from './store';
import { clamp } from './lib/handle';
import { buildTour, useTourController } from './lib/tour';

import { Chrome } from './components/Chrome';
import { Cross } from './components/Cross';
import { BundleDiagnostic } from './components/BundleDiagnostic';
import { TourCaption } from './components/TourCaption';

import styles from './App.module.css';

const DEFAULT_SCENARIO_ID = 'liwld_phase_a_v1';

type LoadState =
  | { kind: 'loading' }
  | { kind: 'ready'; bundle: Bundle; loadMs: number }
  | { kind: 'error'; message: string };

export function App(): JSX.Element {
  const [route] = useState<AppRouteParams>(() => parseAppRoute());
  const [state, setState] = useState<LoadState>({ kind: 'loading' });

  // The keyboard handler reads the current bundle out of a ref so it doesn't
  // have to re-bind the listener on every render.  Set inside the load effect.
  const bundleRef = useRef<Bundle | null>(null);

  useEffect(() => {
    let cancelled = false;
    const scenarioId = route.scenario ?? DEFAULT_SCENARIO_ID;

    const t0 = performance.now();
    loadScenario(scenarioId)
      .then((bundle) => {
        if (cancelled) return;
        bundleRef.current = bundle;
        // Open the page AT the inferred regime — the optimum the user will
        // first see, not some arbitrary default.
        useAppStore.getState().setHandle(bundle.manifest.argmin.m, bundle.manifest.argmin.k);
        setState({ kind: 'ready', bundle, loadMs: performance.now() - t0 });
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        const message =
          err instanceof LiwldLoadError
            ? err.message
            : err instanceof Error
              ? err.message
              : String(err);
        setState({ kind: 'error', message });
      });

    return () => {
      cancelled = true;
    };
  }, [route.scenario]);

  // Document-level keyboard shortcuts (work in both standalone and embed
  // modes — the visible chrome controls disappear in embed, but the keys
  // still fire so a presenter can drive the demo from the keyboard).
  //
  //   D / C        : switch PDF / CDF
  //   P            : toggle population reference
  //   ← → ↑ ↓      : nudge handle by one grid cell (Shift = ×5)
  //   R            : snap handle to argmin
  //   0            : snap handle to U(0,1) baseline
  useEffect(() => {
    function onKey(e: KeyboardEvent): void {
      const target = e.target as HTMLElement | null;
      if (target && /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName)) return;
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      const store = useAppStore.getState();
      const key = e.key;
      const lower = key.toLowerCase();

      // Mode + population toggles
      if (lower === 'd') {
        store.setViewMode('pdf');
        e.preventDefault();
        return;
      }
      if (lower === 'c') {
        store.setViewMode('cdf');
        e.preventDefault();
        return;
      }
      if (lower === 'p') {
        store.togglePopulation();
        e.preventDefault();
        return;
      }

      // Space: enter tour mode if not in it; otherwise toggle play/pause.
      if (key === ' ' || key === 'Spacebar') {
        if (store.appMode !== 'tour') {
          store.setAppMode('tour');
        } else {
          store.toggleTourPlaying();
        }
        e.preventDefault();
        return;
      }

      // Handle-driven shortcuts need a loaded bundle.
      const bundle = bundleRef.current;
      if (!bundle) return;
      const m = bundle.manifest;

      // Snap shortcuts
      if (lower === 'r') {
        store.setHandle(m.argmin.m, m.argmin.k);
        e.preventDefault();
        return;
      }
      if (key === '0') {
        store.setHandle(m.uniform_ref.m, m.uniform_ref.k);
        e.preventDefault();
        return;
      }

      // Arrow-key nudging
      if (
        key === 'ArrowLeft' ||
        key === 'ArrowRight' ||
        key === 'ArrowUp' ||
        key === 'ArrowDown'
      ) {
        const dm = (m.regime_grid.m_max - m.regime_grid.m_min) / (m.regime_grid.m_n - 1);
        const dlk =
          (Math.log10(m.regime_grid.k_max) - Math.log10(m.regime_grid.k_min)) /
          (m.regime_grid.k_n - 1);
        const stepMul = e.shiftKey ? 5 : 1;

        const cur = store.handle;
        let nextM = cur.m;
        let nextK = cur.k;

        if (key === 'ArrowLeft') nextM -= dm * stepMul;
        if (key === 'ArrowRight') nextM += dm * stepMul;
        if (key === 'ArrowUp') {
          // Larger κ — concentration up.  Step in log space.
          nextK = Math.pow(10, Math.log10(cur.k) + dlk * stepMul);
        }
        if (key === 'ArrowDown') {
          nextK = Math.pow(10, Math.log10(cur.k) - dlk * stepMul);
        }

        nextM = clamp(nextM, m.regime_grid.m_min, m.regime_grid.m_max);
        nextK = clamp(nextK, m.regime_grid.k_min, m.regime_grid.k_max);

        store.setHandle(nextM, nextK);
        e.preventDefault();
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  if (state.kind === 'loading') return <LoadingShell embed={route.embed} />;
  if (state.kind === 'error') return <ErrorShell message={state.message} embed={route.embed} />;

  // Diagnostic route: regardless of embed, show the bundle card.
  if (route.diagnostic) {
    return (
      <main className={styles.diagnostic}>
        <BundleDiagnostic bundle={state.bundle} loadMs={state.loadMs} />
      </main>
    );
  }

  return <ReadyApp bundle={state.bundle} embed={route.embed} />;
}

/**
 * ReadyApp — the rendered cross with chrome (or just the cross in embed mode),
 * plus the tour controller (mounted only when bundle is ready) and the
 * Tour caption overlay.  Split out from `App` so the controller hook only
 * runs in the `ready` branch — keeps the hook contract clean.
 */
function ReadyApp({ bundle, embed }: { bundle: Bundle; embed: boolean }): JSX.Element {
  const tourSteps = useMemo(() => buildTour(bundle), [bundle]);
  useTourController(tourSteps);

  // TourCaption is rendered as the Cross's `overlay` so it positions absolute
  // against the cross itself (not against any wrapper div).  This keeps the
  // dimension chain to the panels a single hop — every panel still sees a
  // properly definite parent height.
  const overlay = <TourCaption steps={tourSteps} />;

  if (embed) {
    return (
      <main className={styles.embedFrame}>
        <Cross bundle={bundle} embed overlay={overlay} />
      </main>
    );
  }

  return (
    <div className={styles.shell}>
      <Chrome bundle={bundle} />
      <main className={styles.crossFrame}>
        <Cross bundle={bundle} overlay={overlay} />
      </main>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Loading / error shells (kept inline; not worth their own CSS Modules)
// ────────────────────────────────────────────────────────────────────────────

function LoadingShell({ embed }: { embed: boolean }): JSX.Element {
  return (
    <div style={shellMessage(embed)}>
      <div style={spinnerStyle} aria-hidden="true" />
      <p style={{ color: 'var(--e-text-soft)' }}>Loading scenario bundle…</p>
    </div>
  );
}

function ErrorShell({ message, embed }: { message: string; embed: boolean }): JSX.Element {
  return (
    <div style={shellMessage(embed)}>
      <h2 style={{ margin: 0, color: 'crimson' }}>Failed to load bundle</h2>
      <pre
        style={{
          marginTop: 'var(--p-space-3)',
          padding: 'var(--p-space-3)',
          background: 'var(--p-slate-50)',
          border: '1px solid var(--e-divider)',
          borderRadius: 'var(--p-radius-sm)',
          fontSize: 'var(--p-text-sm)',
          whiteSpace: 'pre-wrap',
          maxWidth: 720,
        }}
      >
        {message}
      </pre>
      <p style={{ color: 'var(--e-text-soft)', marginTop: 'var(--p-space-3)' }}>
        Did you run <code>node scripts/copy-data.mjs</code>? Did you run{' '}
        <code>Rscript R/liwld_precompute.R</code> first?
      </p>
    </div>
  );
}

function shellMessage(embed: boolean): CSSProperties {
  return {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: embed ? '720px' : '100vh',
    width: embed ? '1280px' : '100%',
    margin: '0 auto',
    padding: 'var(--p-space-6)',
    gap: 'var(--p-space-3)',
  };
}

const spinnerStyle: CSSProperties = {
  width: 28,
  height: 28,
  border: '2px solid var(--e-border-panel)',
  borderTopColor: 'var(--e-subgroup-observed)',
  borderRadius: '50%',
  animation: 'liwld-spin 800ms linear infinite',
};
