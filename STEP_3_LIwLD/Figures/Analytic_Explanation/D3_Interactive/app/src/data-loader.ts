/**
 * data-loader.ts — Fetches a scenario bundle, verifies SHA-256 of every file,
 * and returns a fully-typed Bundle.
 *
 * Wire conventions: see schema/manifest.schema.json and lib/binary.ts.
 *
 * Failure modes (all thrown as `LiwldLoadError`):
 *   - Manifest fetch fails or is not valid JSON.
 *   - Manifest schema_version is unrecognized.
 *   - data_classification is RESTRICTED (refuse client-side).
 *   - Any of the five panel files fails to fetch.
 *   - Any SHA-256 mismatch.
 *   - Any binary panel file size mismatches the spec.
 */

import type {
  Bundle,
  Manifest,
  ManifestFileKey,
  Panel1Data,
  Panel2Data,
  Panel5ObservedData,
} from './types';
import { sha256Hex } from './lib/sha256';
import {
  buildRegimeAxes,
  buildVAxis,
  decodePanel3,
  decodePanel5Induced,
} from './lib/binary';

const SUPPORTED_SCHEMA_VERSIONS = new Set<string>(['1.0.0']);

/** Default scenario folder, served by Vite from app/public/data/scenarios/. */
const DEFAULT_BASE = 'data/scenarios';

export class LiwldLoadError extends Error {
  override readonly name = 'LiwldLoadError';
  // `cause` is declared on the base Error type in modern lib.dom — we forward
  // through super({cause}) instead of redeclaring as a parameter property,
  // which keeps TypeScript's `noImplicitOverride` happy.
  constructor(message: string, cause?: unknown) {
    super(message, cause === undefined ? undefined : { cause });
  }
}

/**
 * Fetch + verify + assemble one scenario bundle.
 * @param scenarioId   e.g. "liwld_phase_a_v1"
 * @param baseUrl      Override for testing or alternative deployments.
 */
export async function loadScenario(
  scenarioId: string,
  baseUrl: string = DEFAULT_BASE,
): Promise<Bundle> {
  const dir = `${baseUrl}/${scenarioId}`;

  // ---- 1. manifest.json ----------------------------------------------------
  //
  // Always revalidate the manifest.  The panel binaries below can be cached
  // aggressively because their SHA-256s are embedded in this file — any
  // drift surfaces as a checksum mismatch and a hard error.  But the
  // manifest itself is the entry point: if we let the browser cache it
  // wholesale, a fresh `pnpm copy-data` run won't reach the running app.
  const manifestUrl = `${dir}/manifest.json`;
  const manifestRes = await fetchOrThrow(manifestUrl, 'manifest.json', 'no-cache');
  let manifest: Manifest;
  try {
    manifest = (await manifestRes.json()) as Manifest;
  } catch (err) {
    throw new LiwldLoadError(`Manifest is not valid JSON: ${manifestUrl}`, err);
  }

  if (!SUPPORTED_SCHEMA_VERSIONS.has(manifest.schema_version)) {
    throw new LiwldLoadError(
      `Unsupported manifest schema_version: ${manifest.schema_version}.`,
    );
  }
  if (manifest.data_classification === 'RESTRICTED') {
    throw new LiwldLoadError(
      `Scenario ${manifest.scenario_id} is RESTRICTED; loader refuses without auth.`,
    );
  }

  // ---- 2. Fetch all five panel files in parallel ---------------------------
  const fileKeys: ManifestFileKey[] = [
    'panel_1_u',
    'panel_2_copula',
    'panel_3_grid',
    'panel_5_observed_v',
    'panel_5_induced_v',
  ];

  const fetched = await Promise.all(
    fileKeys.map(async (key) => {
      const filename = manifest.files[key];
      const url = `${dir}/${filename}`;
      const res = await fetchOrThrow(url, key);
      const buf = await res.arrayBuffer();
      return { key, filename, buf };
    }),
  );

  // ---- 3. Verify SHA-256 of each ------------------------------------------
  await Promise.all(
    fetched.map(async ({ key, filename, buf }) => {
      const expected = manifest.checksums[key];
      if (expected === undefined) {
        throw new LiwldLoadError(
          `Manifest missing checksum for "${key}" (${filename}).`,
        );
      }
      const actual = await sha256Hex(buf);
      if (actual !== expected) {
        throw new LiwldLoadError(
          `SHA-256 mismatch for ${filename}: expected ${expected.slice(0, 12)}…, got ${actual.slice(0, 12)}….`,
        );
      }
    }),
  );

  // ---- 4. Decode each into typed panel data --------------------------------
  const get = (key: ManifestFileKey): ArrayBuffer => {
    const found = fetched.find((f) => f.key === key);
    if (!found) throw new LiwldLoadError(`Internal: missing fetched file ${key}`);
    return found.buf;
  };

  const decoder = new TextDecoder('utf-8');
  const parseJson = <T>(key: ManifestFileKey): T => {
    try {
      return JSON.parse(decoder.decode(get(key))) as T;
    } catch (err) {
      throw new LiwldLoadError(`Failed to parse JSON for ${key}.`, err);
    }
  };

  const panel_1 = parseJson<Panel1Data>('panel_1_u');
  const panel_2 = parseJson<Panel2Data>('panel_2_copula');
  const panel_5_observed = parseJson<Panel5ObservedData>('panel_5_observed_v');

  const panel_3 = decodePanel3(
    get('panel_3_grid'),
    manifest.regime_grid.m_n,
    manifest.regime_grid.k_n,
  );

  const panel_5_induced = decodePanel5Induced(
    get('panel_5_induced_v'),
    manifest.regime_grid.m_n,
    manifest.regime_grid.k_n,
    manifest.v_grid.v_n,
  );

  // ---- 5. Reconstruct grid axes (cheap, but useful to do once) ------------
  const { m_grid, k_grid } = buildRegimeAxes(manifest.regime_grid);
  const v_grid = buildVAxis(manifest.v_grid);

  return {
    manifest,
    m_grid,
    k_grid,
    v_grid,
    panel_1,
    panel_2,
    panel_3,
    panel_5_observed,
    panel_5_induced,
  };
}

async function fetchOrThrow(
  url: string,
  label: string,
  cacheMode: RequestCache = 'force-cache',
): Promise<Response> {
  let res: Response;
  try {
    res = await fetch(url, { cache: cacheMode });
  } catch (err) {
    throw new LiwldLoadError(`Failed to fetch ${label} from ${url}.`, err);
  }
  if (!res.ok) {
    throw new LiwldLoadError(
      `Fetch ${label} returned ${res.status} ${res.statusText} (${url}).`,
    );
  }
  return res;
}
