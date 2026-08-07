/**
 * Hex-encoded SHA-256 of an ArrayBuffer using the browser's WebCrypto.
 * Matches what `digest::digest(file = ..., algo = "sha256")` produces in R.
 */
export async function sha256Hex(buffer: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', buffer);
  const bytes = new Uint8Array(digest);
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    const v = bytes[i] ?? 0;
    hex += v.toString(16).padStart(2, '0');
  }
  return hex;
}
