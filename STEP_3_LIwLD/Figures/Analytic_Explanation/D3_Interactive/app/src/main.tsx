import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';

import './styles/tokens.css';
import './styles/global.css';
import 'katex/dist/katex.min.css';

import { App } from './App';

// ─────────────────────────────────────────────────────────────────────────────
// Embedded-page detection.  Whenever the app is loaded inside another page
// (e.g. a RevealJS slide iframe), we tag <html data-embedded="1"> which the
// token CSS keys off to switch panel surfaces to translucent — so the host
// page's background reads through and the cross blends into the slide rather
// than reading as a separate window.
//
// `?embed=1` (which hides the chrome — see App.tsx route handling) also
// activates this skin.  Plain page loads (no iframe, no query) keep the
// solid panel surfaces.
//
// Parent pages can still override individual token values from JS:
//   iframe.contentDocument.documentElement.style.setProperty('--e-bg', '...')
//   iframe.contentDocument.documentElement.style.setProperty('--e-bg-panel', '...')
// Inline-style cascade beats the [data-embedded] rules, so the parent has
// the final say.
// ─────────────────────────────────────────────────────────────────────────────
{
  const params = new URLSearchParams(window.location.search);
  const inIframe = window.self !== window.top;
  if (inIframe || params.get('embed') === '1' || params.get('embedded') === '1') {
    document.documentElement.dataset.embedded = '1';
  }
}

const rootEl = document.getElementById('root');
if (!rootEl) {
  throw new Error('Root element #root missing from index.html');
}

createRoot(rootEl).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
