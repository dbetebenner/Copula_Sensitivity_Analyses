#!/usr/bin/env node
// scripts/copy-data.mjs
//
// Mirror ../data/scenarios/  →  app/public/data/scenarios/
//
// Runs as `predev` and `prebuild` so the served app always has fresh bundles.
// Pure Node (no deps).  Uses cp -R semantics: preserves file mtimes, replaces
// destination contents.

import { cp, mkdir, rm, stat } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const APP_DIR = resolve(__dirname, '..');
const SRC_DIR = resolve(APP_DIR, '..', 'data', 'scenarios');
const DST_DIR = resolve(APP_DIR, 'public', 'data', 'scenarios');

async function exists(p) {
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  if (!(await exists(SRC_DIR))) {
    console.error(`[copy-data] source missing: ${SRC_DIR}`);
    console.error('[copy-data] run R/liwld_precompute.R first.');
    process.exit(1);
  }

  // Replace destination wholesale to avoid stale files from prior bundles.
  if (await exists(DST_DIR)) {
    await rm(DST_DIR, { recursive: true, force: true });
  }
  await mkdir(DST_DIR, { recursive: true });
  await cp(SRC_DIR, DST_DIR, { recursive: true, preserveTimestamps: true });

  console.log(`[copy-data] mirrored:`);
  console.log(`  src: ${SRC_DIR}`);
  console.log(`  dst: ${DST_DIR}`);
}

main().catch((err) => {
  console.error('[copy-data] failed:', err);
  process.exit(1);
});
