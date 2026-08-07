/**
 * Cross.tsx — the cross-pattern layout that holds the five panels.
 *
 * Geometry:
 *   ┌───────┬───────┬───────┐
 *   │       │  #2   │       │   ← top    (copula)
 *   ├───────┼───────┼───────┤
 *   │  #1   │  #3   │  #5   │   ← middle (U │ regime grid │ V)
 *   ├───────┼───────┼───────┤
 *   │       │  #4   │       │   ← bottom (Beta density)
 *   └───────┴───────┴───────┘
 *
 * On narrow viewports (<768px) we flatten to a single column in numeric
 * order — that order matches the natural reading sequence:
 *   1. Prior U distribution (input)
 *   2. Copula (the link)
 *   3. Regime grid (the choice)
 *   4. Beta density (the chosen regime, visualized)
 *   5. Current V distribution (the consequence)
 */

import { useMemo } from 'react';
import type { JSX, ReactNode } from 'react';

import { Panel } from './Panel';
import { PanelU } from './panels/PanelU';
import { PanelCopula } from './panels/PanelCopula';
import { PanelRegimeGrid } from './panels/PanelRegimeGrid';
import { PanelBeta } from './panels/PanelBeta';
import { PanelV } from './panels/PanelV';
import styles from './Cross.module.css';
import type { Bundle } from '../types';
import { selectHandleM, selectHandleK, useAppStore } from '../store';
import { w1AtHandle } from '../lib/handle';

export interface CrossProps {
  bundle: Bundle;
  /** Embed mode (no chrome, fixed canvas).  Affects gap and padding. */
  embed?: boolean;
  /**
   * Optional overlay element rendered inside the Cross's positioning context.
   * Use for absolutely-positioned UI like the Tour caption that should track
   * the cross boundaries, not the page.
   */
  overlay?: ReactNode;
}

export function Cross({ bundle, embed = false, overlay }: CrossProps): JSX.Element {
  const m = bundle.manifest;
  const handleM = useAppStore(selectHandleM);
  const handleK = useAppStore(selectHandleK);

  // Live W₁ at the handle, computed from the bilinear-interpolated induced
  // CDF against the subgroup-observed CDF.  Cheap (~200 fp ops); recomputed
  // every drag tick via Zustand's primitive subscriptions.
  const liveW1 = useMemo(
    () => w1AtHandle(bundle, handleM, handleK),
    [bundle, handleM, handleK],
  );
  const baseline = m.uniform_ref.w1;
  const pctOfBaseline = baseline > 0 ? (liveW1 / baseline) * 100 : 0;

  return (
    <div className={`${styles.cross} ${embed ? styles.embed : ''}`}>
      <Panel
        number={1}
        name="Prior U"
        hint={
          <span>
            n<sub>sub</sub>={m.n_subgroup.toLocaleString()} · n<sub>pop</sub>=
            {m.n_population.toLocaleString()}
          </span>
        }
      >
        <PanelU bundle={bundle} />
      </Panel>
      <Panel
        number={2}
        name="Copula"
        hint={
          <span>
            {m.copula.family} · ρ={m.copula.rho?.toFixed(3) ?? '—'} · df=
            {m.copula.df?.toFixed(1) ?? '—'}
          </span>
        }
      >
        <PanelCopula bundle={bundle} />
      </Panel>
      <Panel
        number={3}
        name="Regime grid (m, κ)"
        emphasis
        hint={
          <span>
            {m.regime_grid.m_n}×{m.regime_grid.k_n} cells · drag the handle
          </span>
        }
      >
        <PanelRegimeGrid bundle={bundle} />
      </Panel>
      <Panel
        number={4}
        name="Beta(m, κ)"
        hint={
          <span>
            handle: m={handleM.toFixed(3)} · κ={handleK.toFixed(2)}
          </span>
        }
      >
        <PanelBeta bundle={bundle} />
      </Panel>
      <Panel
        number={5}
        name="Current V"
        hint={
          <span>
            W₁ = {liveW1.toFixed(4)} · {pctOfBaseline.toFixed(0)}% of baseline
          </span>
        }
      >
        <PanelV bundle={bundle} />
      </Panel>
      {overlay}
    </div>
  );
}
