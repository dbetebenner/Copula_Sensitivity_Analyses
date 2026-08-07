/**
 * Chrome.tsx — title bar + scenario chip + math strip + "Show math" toggle.
 *
 * Hidden in embed mode (Reveal slide) — the slide carries its own title and
 * the cross is the entire visual payload.
 */

import { useState } from 'react';
import type { JSX } from 'react';

import { MathStrip } from './MathStrip';
import styles from './Chrome.module.css';
import type { Bundle, Cohort } from '../types';
import { useAppStore } from '../store';

export interface ChromeProps {
  bundle: Bundle;
}

export function Chrome({ bundle }: ChromeProps): JSX.Element {
  const [mathVisible, setMathVisible] = useState(true);
  const viewMode = useAppStore((s) => s.viewMode);
  const setViewMode = useAppStore((s) => s.setViewMode);
  const populationVisible = useAppStore((s) => s.populationVisible);
  const togglePopulation = useAppStore((s) => s.togglePopulation);
  const appMode = useAppStore((s) => s.appMode);
  const setAppMode = useAppStore((s) => s.setAppMode);

  const m = bundle.manifest;

  return (
    <header className={styles.chrome}>
      <div className={styles.row}>
        <h1 className={styles.title}>
          Longitudinal Inference <span className={styles.titleAccent}>Without</span>{' '}
          Longitudinal Data
        </h1>
        <ScenarioChip
          label={m.label}
          cohort={formatCohort(m.cohort)}
          classification={m.data_classification}
        />
      </div>
      <div className={styles.row}>
        <MathStrip visible={mathVisible} />
        <div className={styles.controls} role="toolbar" aria-label="View controls">
          <AppModeSegment value={appMode} onChange={setAppMode} />
          <ViewModeSegment value={viewMode} onChange={setViewMode} />
          <PopulationToggle visible={populationVisible} onToggle={togglePopulation} />
          <button
            className={styles.toggle}
            type="button"
            onClick={() => setMathVisible((v) => !v)}
            aria-pressed={mathVisible}
            title="Toggle math identities"
          >
            {mathVisible ? 'Hide math' : 'Show math'}
          </button>
        </div>
      </div>
    </header>
  );
}

interface AppModeSegmentProps {
  value: 'explore' | 'tour' | 'compare';
  onChange: (mode: 'explore' | 'tour' | 'compare') => void;
}

function AppModeSegment({ value, onChange }: AppModeSegmentProps): JSX.Element {
  return (
    <div
      className={styles.segment}
      role="radiogroup"
      aria-label="Interaction mode"
      title="Interaction mode (space toggles tour play/pause)"
    >
      <button
        type="button"
        role="radio"
        aria-checked={value === 'explore'}
        className={`${styles.segmentBtn} ${value === 'explore' ? styles.segmentActive : ''}`}
        onClick={() => onChange('explore')}
      >
        Explore
      </button>
      <button
        type="button"
        role="radio"
        aria-checked={value === 'tour'}
        className={`${styles.segmentBtn} ${value === 'tour' ? styles.segmentActive : ''}`}
        onClick={() => onChange('tour')}
      >
        Tour
      </button>
    </div>
  );
}

interface ViewModeSegmentProps {
  value: 'pdf' | 'cdf';
  onChange: (mode: 'pdf' | 'cdf') => void;
}

function ViewModeSegment({ value, onChange }: ViewModeSegmentProps): JSX.Element {
  return (
    <div
      className={styles.segment}
      role="radiogroup"
      aria-label="PDF or CDF view"
      title="View mode (D / C)"
    >
      <button
        type="button"
        role="radio"
        aria-checked={value === 'pdf'}
        className={`${styles.segmentBtn} ${value === 'pdf' ? styles.segmentActive : ''}`}
        onClick={() => onChange('pdf')}
      >
        PDF
      </button>
      <button
        type="button"
        role="radio"
        aria-checked={value === 'cdf'}
        className={`${styles.segmentBtn} ${value === 'cdf' ? styles.segmentActive : ''}`}
        onClick={() => onChange('cdf')}
      >
        CDF
      </button>
    </div>
  );
}

interface PopulationToggleProps {
  visible: boolean;
  onToggle: () => void;
}

function PopulationToggle({ visible, onToggle }: PopulationToggleProps): JSX.Element {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={visible}
      className={`${styles.toggle} ${visible ? styles.toggleOn : ''}`}
      onClick={onToggle}
      title="Toggle population reference (P)"
    >
      <span className={styles.toggleDot} aria-hidden="true" />
      Population
    </button>
  );
}

interface ScenarioChipProps {
  label: string;
  cohort: string;
  classification: string;
}

function ScenarioChip({ label, cohort, classification }: ScenarioChipProps): JSX.Element {
  return (
    <div className={styles.chip} title={`${label} · ${classification}`}>
      <span className={styles.chipLabel}>{label}</span>
      <span className={styles.chipDivider} aria-hidden="true">·</span>
      <span className={styles.chipCohort}>{cohort}</span>
      <span
        className={`${styles.chipBadge} ${classification === 'PUBLIC' ? styles.badgePublic : ''}`}
      >
        {classification}
      </span>
    </div>
  );
}

/**
 * Format the cohort row defensively.  If any field is missing or carries a
 * sentinel like the literal string "NA" (from an older R precompute that
 * wrote NAs through jsonlite), elide the segment instead of rendering
 * something nonsensical like "GNA→GNA".
 */
function formatCohort(c: Cohort): string {
  const isReal = (x: unknown): boolean =>
    x !== null && x !== undefined && x !== '' && x !== 'NA';
  const grade =
    isReal(c.grade_prior) && isReal(c.grade_current)
      ? `G${c.grade_prior}→G${c.grade_current}`
      : null;
  const years =
    isReal(c.year_prior) && isReal(c.year_current)
      ? `${c.year_prior}–${c.year_current}`
      : null;
  const area = isReal(c.content_area) ? c.content_area : null;
  const parts = [grade, years, area].filter((x): x is string => x !== null);
  return parts.length > 0 ? parts.join(' · ') : '—';
}
