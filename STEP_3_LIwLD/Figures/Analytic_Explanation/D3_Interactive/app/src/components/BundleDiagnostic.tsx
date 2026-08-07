/**
 * BundleDiagnostic.tsx — the card we used as the Phase 2a boot diagnostic.
 *
 * Still reachable via `?diagnostic=1`.  Useful any time we want to verify
 * SHA-256 round-trip or read the manifest in the browser without diff'ing
 * data/scenarios/<id>/manifest.json.
 */

import type { CSSProperties, JSX, ReactNode } from 'react';

import type { Bundle } from '../types';

export interface BundleDiagnosticProps {
  bundle: Bundle;
  loadMs: number;
}

export function BundleDiagnostic({ bundle, loadMs }: BundleDiagnosticProps): JSX.Element {
  const m = bundle.manifest;
  return (
    <section style={cardStyle}>
      <h2 style={cardTitleStyle}>
        Bundle loaded <span style={{ color: 'var(--e-subgroup-observed)' }}>✓</span>
      </h2>
      <p style={{ color: 'var(--e-text-soft)' }}>
        All five files fetched and SHA-256 verified in{' '}
        <span className="tnum">{loadMs.toFixed(0)} ms</span>.
      </p>

      <Row label="Scenario" value={`${m.label} (${m.scenario_id})`} />
      <Row label="Source" value={`${m.data_source} · ${m.data_classification}`} />
      <Row
        label="Cohort"
        value={
          `Grade ${m.cohort.grade_prior} → ${m.cohort.grade_current}, ` +
          `${m.cohort.year_prior} → ${m.cohort.year_current}, ${m.cohort.content_area}`
        }
      />
      <Row
        label="Counts"
        value={
          <span className="tnum">
            n<sub>sub</sub> = {m.n_subgroup.toLocaleString()} · n<sub>pop</sub> ={' '}
            {m.n_population.toLocaleString()}
          </span>
        }
      />
      <Row
        label="Copula"
        value={
          <span className="tnum">
            {m.copula.family} · ρ = {fmt(m.copula.rho, 3)} · df = {fmt(m.copula.df, 2)}
            {m.copula.df_display !== undefined && (
              <span style={{ color: 'var(--e-text-muted)' }}>
                {' '}
                (display df = {m.copula.df_display})
              </span>
            )}
          </span>
        }
      />
      <Row
        label="Regime grid"
        value={
          <span className="tnum">
            m ∈ [{fmt(m.regime_grid.m_min, 2)}, {fmt(m.regime_grid.m_max, 2)}], n = {m.regime_grid.m_n}
            {' · '}
            κ ∈ [{fmt(m.regime_grid.k_min, 2)}, {fmt(m.regime_grid.k_max, 2)}], n = {m.regime_grid.k_n}{' '}
            ({m.regime_grid.k_scale})
          </span>
        }
      />
      <Row
        label="V grid"
        value={
          <span className="tnum">
            v ∈ [{fmt(m.v_grid.v_min, 3)}, {fmt(m.v_grid.v_max, 3)}], n = {m.v_grid.v_n}
          </span>
        }
      />
      <Row
        label="argmin"
        value={
          <span className="tnum">
            (m = {fmt(m.argmin.m, 4)}, κ = {fmt(m.argmin.k, 3)}) · W₁ = {fmt(m.argmin.w1, 5)}
            {' · cell idx ('}
            {m.argmin.m_idx},{m.argmin.k_idx})
          </span>
        }
      />
      <Row
        label="uniform_ref"
        value={
          <span className="tnum">
            (m = {fmt(m.uniform_ref.m, 2)}, κ = {fmt(m.uniform_ref.k, 2)}) · W₁ ={' '}
            {fmt(m.uniform_ref.w1, 5)} · argmin is{' '}
            <strong>{((m.argmin.w1 / m.uniform_ref.w1) * 100).toFixed(0)}%</strong> of baseline
          </span>
        }
      />
      <Row
        label="Bundle"
        value={
          <span className="tnum">
            panel_3 = {bundle.panel_3.data.length.toLocaleString()} f32 · panel_5 induced ={' '}
            {bundle.panel_5_induced.data.length.toLocaleString()} u8 · contour layers ={' '}
            {bundle.panel_2.length}
          </span>
        }
      />
      <Row
        label="Build"
        value={
          <span className="tnum" style={{ color: 'var(--e-text-soft)' }}>
            {m.build.tool} v{m.build.tool_version} · {m.build.timestamp_utc}
            {m.build.r_version && ` · R ${m.build.r_version}`}
          </span>
        }
      />

      <details style={{ marginTop: 'var(--p-space-4)' }}>
        <summary style={{ cursor: 'pointer', color: 'var(--e-text-soft)' }}>
          SHA-256 (verified)
        </summary>
        <table style={tableStyle}>
          <tbody>
            {Object.entries(m.checksums).map(([k, v]) => (
              <tr key={k}>
                <td style={tdLabel}>{k}</td>
                <td style={tdValue} className="tnum">
                  {v}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </section>
  );
}

function Row({ label, value }: { label: string; value: ReactNode }): JSX.Element {
  return (
    <div style={rowStyle}>
      <div style={rowLabelStyle}>{label}</div>
      <div style={rowValueStyle}>{value}</div>
    </div>
  );
}

function fmt(x: number | undefined, digits: number): string {
  return x === undefined || Number.isNaN(x) ? '—' : x.toFixed(digits);
}

const cardStyle: CSSProperties = {
  background: 'var(--e-bg-panel)',
  border: '1px solid var(--e-border-panel)',
  borderRadius: 'var(--e-radius)',
  padding: 'var(--p-space-5)',
};
const cardTitleStyle: CSSProperties = {
  margin: '0 0 var(--p-space-2) 0',
  fontSize: 'var(--e-text-title)',
  fontWeight: 600,
};
const rowStyle: CSSProperties = {
  display: 'grid',
  gridTemplateColumns: '120px 1fr',
  gap: 'var(--p-space-3)',
  padding: 'var(--p-space-2) 0',
  borderTop: '1px solid var(--e-divider)',
};
const rowLabelStyle: CSSProperties = {
  color: 'var(--e-text-muted)',
  fontSize: 'var(--e-text-label)',
  textTransform: 'uppercase',
  letterSpacing: '0.04em',
  paddingTop: 2,
};
const rowValueStyle: CSSProperties = {
  color: 'var(--e-text)',
};
const tableStyle: CSSProperties = {
  marginTop: 'var(--p-space-2)',
  borderCollapse: 'collapse',
  width: '100%',
};
const tdLabel: CSSProperties = {
  padding: '4px 12px 4px 0',
  color: 'var(--e-text-soft)',
  whiteSpace: 'nowrap',
  verticalAlign: 'top',
};
const tdValue: CSSProperties = {
  padding: '4px 0',
  fontFamily: 'var(--e-font-mono)',
  fontSize: 'var(--p-text-xs)',
  wordBreak: 'break-all',
  color: 'var(--e-text)',
};
