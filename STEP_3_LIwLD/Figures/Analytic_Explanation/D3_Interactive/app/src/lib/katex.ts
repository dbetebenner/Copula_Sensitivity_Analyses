/**
 * lib/katex.ts — thin wrapper around KaTeX's renderToString with module-level
 * memoization.  Since we only render a small fixed set of identities (and the
 * same ones for every page render), caching by source string keeps re-renders
 * effectively free.
 */

import katex from 'katex';

const cache = new Map<string, string>();

export interface RenderOptions {
  displayMode?: boolean;
}

/**
 * Render a TeX string to KaTeX HTML.  Throws on malformed input — we want
 * compile-time-style failures during development, not silent corruption.
 */
export function tex(source: string, opts: RenderOptions = {}): string {
  const key = `${opts.displayMode ? 'D' : 'I'}::${source}`;
  const hit = cache.get(key);
  if (hit !== undefined) return hit;
  const html = katex.renderToString(source, {
    displayMode: opts.displayMode ?? false,
    throwOnError: true,
    output: 'html',
    strict: 'warn',
    trust: false,
  });
  cache.set(key, html);
  return html;
}

/**
 * The three load-bearing identities that anchor the LIwLD explainer.
 *
 * Notation convention:
 *   H_{(U,V)}            joint CDF of the (U, V) pair  (Sklar)
 *   G                    growth-regime CDF on [0, 1]
 *   \mathcal{G}_{\text{Beta}}  the parametric family we optimize over
 *
 * H is reserved for the joint CDF; G carries every appearance of the
 * growth regime — separating the two letters is a deliberate choice to
 * remove the H/H ambiguity that arose when both objects shared a glyph.
 */
export const IDENTITIES = {
  sklar:    String.raw`H_{(U,V)}(u,v) = C\bigl(F_U(u),\, F_V(v)\bigr)`,
  induced:  String.raw`F_G(v) = \mathbb{E}_U\bigl[\,G\!\left(F_0(v\mid U)\right)\,\bigr]`,
  estimator: String.raw`\hat G_S = \arg\min_{G \in \mathcal{G}_{\text{Beta}}} W_1\!\left(F_{\mathrm{obs}}^V,\, F_G\right)`,
} as const;
