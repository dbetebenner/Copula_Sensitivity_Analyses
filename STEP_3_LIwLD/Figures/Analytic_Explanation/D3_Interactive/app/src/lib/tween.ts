/**
 * lib/tween.ts — small animation hook for value interpolation.
 *
 * useTweenedValue(target, durationMs):
 *   - returns a number that animates smoothly to `target`
 *   - cubic-out easing (matches the --p-ease-out token's curve)
 *   - snaps instantly when prefers-reduced-motion is on
 *   - cancels in-flight tween when target changes mid-flight
 *   - cancels and resets on unmount
 *
 * The shape of the API mirrors React's pattern: the hook owns the timer,
 * the component just receives the current value.  No imperative refs in
 * caller code.
 */

import { useEffect, useRef, useState } from 'react';

const DEFAULT_DURATION_MS = 480;

export function useTweenedValue(target: number, durationMs: number = DEFAULT_DURATION_MS): number {
  const [value, setValue] = useState<number>(target);
  // Mirror state into a ref so the effect's snapshot can read the *current*
  // animated value as the new tween's starting point.
  const valueRef = useRef<number>(target);
  valueRef.current = value;

  useEffect(() => {
    if (target === valueRef.current) return;

    // Honor reduced motion: jump straight to the target.
    const reduced =
      typeof window !== 'undefined' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) {
      setValue(target);
      return;
    }

    let cancelled = false;
    const startValue = valueRef.current;
    const delta = target - startValue;
    const startTime = performance.now();

    const tick = () => {
      if (cancelled) return;
      const elapsed = performance.now() - startTime;
      const t = Math.min(1, elapsed / durationMs);
      // cubic-out
      const eased = 1 - Math.pow(1 - t, 3);
      setValue(startValue + delta * eased);
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);

    return () => {
      cancelled = true;
    };
  }, [target, durationMs]);

  return value;
}
