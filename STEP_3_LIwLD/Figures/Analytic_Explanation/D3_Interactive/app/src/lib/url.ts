/** url.ts — tiny query-string helpers. */

export interface AppRouteParams {
  /** Render the chrome-less embed layout when ?embed=1. */
  embed: boolean;
  /** Show the bundle-diagnostic card instead of the cross when ?diagnostic=1. */
  diagnostic: boolean;
  /** Override the default scenario id (?scenario=...). */
  scenario: string | null;
}

export function parseAppRoute(search: string = window.location.search): AppRouteParams {
  const params = new URLSearchParams(search);
  return {
    embed: params.get('embed') === '1',
    diagnostic: params.get('diagnostic') === '1',
    scenario: params.get('scenario'),
  };
}
