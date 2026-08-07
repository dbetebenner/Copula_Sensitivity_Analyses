/**
 * MathStrip.tsx — the three load-bearing identities, rendered with KaTeX.
 *
 * These three identities together carry the entire mathematical story of
 * LIwLD — Sklar's theorem (the link), the induced-CDF formula (what the
 * regime does), and the estimator (what we infer).  They live in a slim
 * strip just under the title; a "Show math" toggle hides them when the
 * audience isn't math-literate.
 */

import { useMemo } from 'react';
import type { JSX } from 'react';

import { tex, IDENTITIES } from '../lib/katex';
import styles from './MathStrip.module.css';

export interface MathStripProps {
  visible?: boolean;
}

export function MathStrip({ visible = true }: MathStripProps): JSX.Element | null {
  // Memoize per-component-mount; the underlying tex() also caches at module level.
  const sklar = useMemo(() => tex(IDENTITIES.sklar), []);
  const induced = useMemo(() => tex(IDENTITIES.induced), []);
  const estimator = useMemo(() => tex(IDENTITIES.estimator), []);

  if (!visible) return null;

  return (
    <div className={styles.strip} role="group" aria-label="Three identities anchoring LIwLD">
      <Identity
        label="Sklar"
        html={sklar}
        title="Sklar's theorem links the joint CDF to the marginals via a copula."
      />
      <span className={styles.divider} aria-hidden="true">·</span>
      <Identity
        label="Induced"
        html={induced}
        title="The induced V-CDF is the U-expectation of the growth regime G applied to the conditional CDF."
      />
      <span className={styles.divider} aria-hidden="true">·</span>
      <Identity
        label="Estimator"
        html={estimator}
        title="The inferred regime Ĝ_S is the Beta(m, κ) that minimizes the Wasserstein-1 distance to the observed V CDF."
      />
    </div>
  );
}

interface IdentityProps {
  label: string;
  html: string;
  title: string;
}

function Identity({ label, html, title }: IdentityProps): JSX.Element {
  return (
    <span className={styles.identity} title={title}>
      <span className={styles.identityLabel}>{label}</span>
      <span
        className={styles.identityMath}
        // Trusted: produced by katex with strict='warn' from a hard-coded source.
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </span>
  );
}
