/**
 * Panel.tsx — generic panel shell.  In Phase 2b every panel renders a
 * placeholder body; in Phase 2c the body becomes the live SVG visualization.
 *
 * Visual structure:
 *   ┌─────────────────────────────┐
 *   │ #1  PRIOR U          [hint] │   ← header (number, name, optional hint)
 *   ├─────────────────────────────┤
 *   │                             │
 *   │     <body content>          │   ← body (placeholder or visualization)
 *   │                             │
 *   └─────────────────────────────┘
 */

import type { JSX, ReactNode } from 'react';

import styles from './Panel.module.css';

export interface PanelProps {
  /** Position in the cross — used as `grid-area` and as the chip label. */
  number: 1 | 2 | 3 | 4 | 5;
  /** Short title shown next to the number, e.g. "PRIOR U". */
  name: string;
  /** Optional small text in the right of the header (e.g. sample sizes). */
  hint?: ReactNode;
  /** Body content — for Phase 2b, a placeholder; for Phase 2c+, an SVG. */
  children?: ReactNode;
  /** When true, panel uses the "interactive heart" emphasis (Panel #3). */
  emphasis?: boolean;
}

const GRID_AREA: Record<PanelProps['number'], string> = {
  1: 'p1',
  2: 'p2',
  3: 'p3',
  4: 'p4',
  5: 'p5',
};

export function Panel({ number, name, hint, children, emphasis = false }: PanelProps): JSX.Element {
  return (
    <section
      className={`${styles.panel} ${emphasis ? styles.emphasis : ''}`}
      style={{ gridArea: GRID_AREA[number] }}
      aria-label={`Panel ${number}: ${name}`}
    >
      <header className={styles.header}>
        <span className={styles.number} aria-hidden="true">{`#${number}`}</span>
        <span className={styles.name}>{name}</span>
        {hint !== undefined && <span className={`${styles.hint} tnum`}>{hint}</span>}
      </header>
      <div className={styles.body}>{children ?? <PanelPlaceholder number={number} name={name} />}</div>
    </section>
  );
}

function PanelPlaceholder({ number, name }: { number: number; name: string }): JSX.Element {
  return (
    <div className={styles.placeholder}>
      <div className={styles.placeholderNumber}>{`#${number}`}</div>
      <div className={styles.placeholderName}>{name}</div>
      <div className={styles.placeholderNote}>Phase 2c content</div>
    </div>
  );
}
