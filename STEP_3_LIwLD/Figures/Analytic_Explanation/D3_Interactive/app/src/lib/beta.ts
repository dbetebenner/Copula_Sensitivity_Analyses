/**
 * lib/beta.ts — Beta distribution PDF/CDF, parameterized by (m, κ).
 *
 * Convention (matches R's regime_beta):
 *   α = m · κ
 *   β = (1 - m) · κ
 *
 * The Beta PDF is
 *   f(p; α, β) = p^(α-1) · (1 - p)^(β-1) / B(α, β)
 *
 * where B is the Beta function.  We compute it in log-space for numerical
 * stability, then exponentiate at the end.  The lgamma implementation here
 * is a Lanczos approximation accurate to ~14 digits, which is more than
 * enough for visualization.
 *
 * For the CDF we use the regularized incomplete beta function via a
 * continued-fraction expansion (the standard Numerical Recipes approach).
 */

const SQRT_2PI = Math.sqrt(2 * Math.PI);

const LANCZOS_G = 7;
const LANCZOS_COEF = [
  0.999_999_999_999_999_8,
  676.520_368_121_885_1,
  -1259.139_216_722_402_8,
  771.323_428_777_653_1,
  -176.615_029_162_140_6,
  12.507_343_278_686_905,
  -0.138_571_095_265_720_12,
  9.984_369_578_019_572e-6,
  1.505_632_735_149_311_6e-7,
];

/** log Γ(x) for x > 0.  Lanczos approximation. */
export function lgamma(x: number): number {
  if (x <= 0) return Number.NaN;
  let sum = LANCZOS_COEF[0]!;
  for (let i = 1; i < LANCZOS_COEF.length; i++) {
    sum += LANCZOS_COEF[i]! / (x + i - 1);
  }
  const t = x + LANCZOS_G - 0.5;
  return Math.log(SQRT_2PI * sum) + (x - 0.5) * Math.log(t) - t;
}

/** log B(α, β) — log of the Beta function. */
export function logBeta(alpha: number, beta: number): number {
  return lgamma(alpha) + lgamma(beta) - lgamma(alpha + beta);
}

/** Convert (m, κ) to (α, β). */
export function shapeFromMK(m: number, k: number): { alpha: number; beta: number } {
  return { alpha: m * k, beta: (1 - m) * k };
}

/**
 * Beta(α, β) PDF on [0, 1].
 * Returns 0 outside the open interval; clamps gracefully at the endpoints.
 */
export function betaPdf(p: number, alpha: number, beta: number): number {
  if (p <= 0 || p >= 1) {
    // Endpoint behavior depends on shape parameters; for visualization we
    // return 0 so the curve closes cleanly at the frame.
    return 0;
  }
  const logp = (alpha - 1) * Math.log(p) + (beta - 1) * Math.log(1 - p) - logBeta(alpha, beta);
  return Math.exp(logp);
}

/**
 * Beta(α, β) CDF — regularized incomplete beta I_x(α, β).
 *
 *   bt   = exp(a·log(x) + b·log(1−x) − logB(a, b))
 *   I_x  = bt · betacf(a, b, x) / a
 *
 * Symmetry: I_x(α, β) = 1 − I_{1−x}(β, α).  We pick the side where the
 * continued fraction converges faster (NR §6.4).
 *
 * Note on factor of 1/a: our `betaCf` already returns h/a (encapsulating
 * that division), so `lbt` here is plain log(bt) without a -log(a) term —
 * dividing twice would put the CDF off by ~1/a and produce a step-like
 * artifact at the useFlip threshold.
 */
export function betaCdf(x: number, alpha: number, beta: number): number {
  if (x <= 0) return 0;
  if (x >= 1) return 1;

  const useFlip = x > (alpha + 1) / (alpha + beta + 2);
  const xa = useFlip ? 1 - x : x;
  const a = useFlip ? beta : alpha;
  const b = useFlip ? alpha : beta;

  const lbt = a * Math.log(xa) + b * Math.log(1 - xa) - logBeta(a, b);
  const tail = Math.exp(lbt) * betaCf(xa, a, b);

  return useFlip ? 1 - tail : tail;
}

/**
 * Continued-fraction expansion for I_x(a, b) (Numerical Recipes §6.4).
 * Modified Lentz's method.  Converges in ~10–20 iterations for typical
 * regime parameters.
 */
function betaCf(x: number, a: number, b: number): number {
  const MAX_ITER = 200;
  const EPS = 3e-7;
  const FPMIN = 1e-30;

  const qab = a + b;
  const qap = a + 1;
  const qam = a - 1;
  let c = 1;
  let d = 1 - (qab * x) / qap;
  if (Math.abs(d) < FPMIN) d = FPMIN;
  d = 1 / d;
  let h = d;

  for (let m = 1; m <= MAX_ITER; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c;
    if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d;
    h *= d * c;

    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c;
    if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1) < EPS) return h / a;
  }
  return h / a;
}

/**
 * Convenience: evaluate Beta PDF on a uniform grid of n points across (0, 1).
 * Returns parallel arrays {p, density}.
 */
export function betaPdfGrid(
  alpha: number,
  beta: number,
  n: number = 200,
): { p: Float32Array; density: Float32Array } {
  const p = new Float32Array(n);
  const density = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const pi = (i + 0.5) / n; // midpoint sampling; avoids endpoints
    p[i] = pi;
    density[i] = betaPdf(pi, alpha, beta);
  }
  return { p, density };
}
