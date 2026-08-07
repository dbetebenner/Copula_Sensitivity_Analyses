/**
 * TourCaption.tsx — caption + step controls for Tour mode.
 *
 * Visual: a slim strip at the BOTTOM of the cross frame containing the
 * narration, a segmented step indicator, and a play / pause button.
 * Cross-fades when the step changes.  Hidden in Explore and Compare modes.
 */

import { useEffect, useState } from 'react';
import type { JSX } from 'react';

import { useAppStore } from '../store';
import type { TourStep } from '../lib/tour';
import styles from './TourCaption.module.css';

export interface TourCaptionProps {
  steps: TourStep[];
}

export function TourCaption({ steps }: TourCaptionProps): JSX.Element | null {
  const appMode = useAppStore((s) => s.appMode);
  const tourStep = useAppStore((s) => s.tourStep);
  const tourPlaying = useAppStore((s) => s.tourPlaying);
  const setTourStep = useAppStore((s) => s.setTourStep);
  const toggleTourPlaying = useAppStore((s) => s.toggleTourPlaying);

  // Cross-fade: store the step we're displaying separately, so we can fade
  // the *previous* caption out before swapping in the new one.
  const [displayStep, setDisplayStep] = useState<number>(tourStep);
  const [fading, setFading] = useState<boolean>(false);

  useEffect(() => {
    if (tourStep === displayStep) return;
    setFading(true);
    const t = window.setTimeout(() => {
      setDisplayStep(tourStep);
      setFading(false);
    }, 180);
    return () => window.clearTimeout(t);
  }, [tourStep, displayStep]);

  if (appMode !== 'tour') return null;
  const step = steps[displayStep];
  if (!step) return null;

  return (
    <div className={styles.caption} role="status" aria-live="polite">
      <div className={styles.controls}>
        <button
          type="button"
          className={styles.playBtn}
          onClick={toggleTourPlaying}
          aria-label={tourPlaying ? 'Pause tour' : 'Play tour'}
          title={tourPlaying ? 'Pause (space)' : 'Play (space)'}
        >
          {tourPlaying ? '❚❚' : '▶'}
        </button>
        <Stepper
          total={steps.length}
          current={displayStep}
          onStep={(i) => setTourStep(i)}
        />
      </div>
      <p className={`${styles.body} ${fading ? styles.bodyFading : ''}`}>{step.caption}</p>
    </div>
  );
}

function Stepper({
  total,
  current,
  onStep,
}: {
  total: number;
  current: number;
  onStep: (i: number) => void;
}): JSX.Element {
  return (
    <div className={styles.stepper} role="group" aria-label="Tour steps">
      {Array.from({ length: total }, (_, i) => (
        <button
          key={i}
          type="button"
          className={`${styles.dot} ${i === current ? styles.dotActive : ''}`}
          onClick={() => onStep(i)}
          aria-label={`Step ${i + 1} of ${total}`}
          aria-current={i === current ? 'step' : undefined}
        />
      ))}
    </div>
  );
}
