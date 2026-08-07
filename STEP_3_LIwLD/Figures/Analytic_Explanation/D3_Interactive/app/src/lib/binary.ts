/**
 * binary.ts — Decoders for the two binary panel artifacts.
 *
 * The wire format conventions (matching R/export_bundle.R):
 *
 *  - panel3_w1_surface.bin
 *      Float32, little-endian, row-major [m_n × k_n].
 *      Byte offset of (m_idx, k_idx) = 4 * (m_idx * k_n + k_idx).
 *
 *  - panel5_v_induced.bin
 *      Uint8 quantized, row-major [m_n × k_n × v_n].
 *      Byte offset of (m_idx, k_idx, v_idx) = m_idx*k_n*v_n + k_idx*v_n + v_idx.
 *      Decode: F_G = byte / 255  (clamped to [0, 1]).
 */

import type { Panel3Surface, Panel5InducedTensor } from '../types';

/** Decode panel3 binary into a Panel3Surface view. */
export function decodePanel3(buffer: ArrayBuffer, m_n: number, k_n: number): Panel3Surface {
  const expected = m_n * k_n * 4;
  if (buffer.byteLength !== expected) {
    throw new Error(
      `panel3 size mismatch: got ${buffer.byteLength}, expected ${expected} ` +
        `(m_n=${m_n}, k_n=${k_n})`,
    );
  }
  // Little-endian Float32 — Vite/browser native endianness is little-endian
  // on the platforms we ship to (x86-64, arm64).  Use DataView for safety.
  const dv = new DataView(buffer);
  const data = new Float32Array(m_n * k_n);
  for (let i = 0; i < data.length; i++) {
    data[i] = dv.getFloat32(i * 4, /* littleEndian */ true);
  }
  return {
    data,
    m_n,
    k_n,
    at: (m_idx: number, k_idx: number) => {
      if (m_idx < 0 || m_idx >= m_n || k_idx < 0 || k_idx >= k_n) {
        return Number.NaN;
      }
      return data[m_idx * k_n + k_idx] ?? Number.NaN;
    },
  };
}

/** Decode panel5 induced binary into a Panel5InducedTensor view. */
export function decodePanel5Induced(
  buffer: ArrayBuffer,
  m_n: number,
  k_n: number,
  v_n: number,
): Panel5InducedTensor {
  const expected = m_n * k_n * v_n;
  if (buffer.byteLength !== expected) {
    throw new Error(
      `panel5 induced size mismatch: got ${buffer.byteLength}, expected ${expected} ` +
        `(m_n=${m_n}, k_n=${k_n}, v_n=${v_n})`,
    );
  }
  const data = new Uint8Array(buffer);

  const atCell = (m_idx: number, k_idx: number): Float32Array => {
    const out = new Float32Array(v_n);
    if (m_idx < 0 || m_idx >= m_n || k_idx < 0 || k_idx >= k_n) {
      return out; // returns zeros for out-of-grid; caller decides what to do
    }
    const base = (m_idx * k_n + k_idx) * v_n;
    for (let v = 0; v < v_n; v++) {
      out[v] = (data[base + v] ?? 0) / 255;
    }
    return out;
  };

  const bilinear = (m_idx_f: number, k_idx_f: number): Float32Array => {
    const out = new Float32Array(v_n);

    // Clamp into valid interpolation range.
    const m_clamped = Math.max(0, Math.min(m_n - 1, m_idx_f));
    const k_clamped = Math.max(0, Math.min(k_n - 1, k_idx_f));

    const m0 = Math.floor(m_clamped);
    const k0 = Math.floor(k_clamped);
    const m1 = Math.min(m_n - 1, m0 + 1);
    const k1 = Math.min(k_n - 1, k0 + 1);
    const dm = m_clamped - m0;
    const dk = k_clamped - k0;

    const w00 = (1 - dm) * (1 - dk);
    const w01 = (1 - dm) * dk;
    const w10 = dm * (1 - dk);
    const w11 = dm * dk;

    const b00 = (m0 * k_n + k0) * v_n;
    const b01 = (m0 * k_n + k1) * v_n;
    const b10 = (m1 * k_n + k0) * v_n;
    const b11 = (m1 * k_n + k1) * v_n;

    for (let v = 0; v < v_n; v++) {
      const f =
        w00 * (data[b00 + v] ?? 0) +
        w01 * (data[b01 + v] ?? 0) +
        w10 * (data[b10 + v] ?? 0) +
        w11 * (data[b11 + v] ?? 0);
      out[v] = f / 255;
    }
    return out;
  };

  return { data, m_n, k_n, v_n, atCell, bilinear };
}

/**
 * Reconstruct the regime grid axes from the manifest spec.
 * Linear in m, log in κ (the only k_scale we currently support).
 */
export function buildRegimeAxes(spec: {
  m_min: number;
  m_max: number;
  m_n: number;
  k_min: number;
  k_max: number;
  k_n: number;
  k_scale: 'linear' | 'log';
}): { m_grid: Float64Array; k_grid: Float64Array } {
  const m_grid = new Float64Array(spec.m_n);
  for (let i = 0; i < spec.m_n; i++) {
    m_grid[i] = spec.m_min + ((spec.m_max - spec.m_min) * i) / (spec.m_n - 1);
  }
  const k_grid = new Float64Array(spec.k_n);
  if (spec.k_scale === 'log') {
    const lo = Math.log(spec.k_min);
    const hi = Math.log(spec.k_max);
    for (let j = 0; j < spec.k_n; j++) {
      k_grid[j] = Math.exp(lo + ((hi - lo) * j) / (spec.k_n - 1));
    }
  } else {
    for (let j = 0; j < spec.k_n; j++) {
      k_grid[j] = spec.k_min + ((spec.k_max - spec.k_min) * j) / (spec.k_n - 1);
    }
  }
  return { m_grid, k_grid };
}

/** Reconstruct the v-axis from the manifest spec. */
export function buildVAxis(spec: { v_min: number; v_max: number; v_n: number }): Float64Array {
  const v_grid = new Float64Array(spec.v_n);
  for (let i = 0; i < spec.v_n; i++) {
    v_grid[i] = spec.v_min + ((spec.v_max - spec.v_min) * i) / (spec.v_n - 1);
  }
  return v_grid;
}
