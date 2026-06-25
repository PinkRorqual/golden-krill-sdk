// GK1 wire codec: "GK1." + base64url(XOR(utf8(json), key)). Obfuscation + a stable
// envelope, not encryption (HTTPS does transit security; host-pinned URLs stop redirects).
// Byte-identical to the Dart/Python implementations - do not change the tag or key.
const KEY = 'pink-rorqual//golden-krill//v1';
const TAG = 'GK1.';

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

function b64urlEncode(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += B64[b0 >> 2];
    out += B64[((b0 & 3) << 4) | (b1 >> 4)];
    if (i + 1 < bytes.length) out += B64[((b1 & 15) << 2) | (b2 >> 6)];
    if (i + 2 < bytes.length) out += B64[b2 & 63];
  }
  while (out.length % 4 !== 0) out += '='; // url-safe WITH padding, matching Dart/Python
  return out;
}

function b64urlDecode(s: string): Uint8Array {
  const lookup: Record<string, number> = {};
  for (let i = 0; i < B64.length; i++) lookup[B64[i]] = i;
  const clean = s.replace(/=+$/, '');
  const out: number[] = [];
  for (let i = 0; i < clean.length; i += 4) {
    const c0 = lookup[clean[i]];
    const c1 = lookup[clean[i + 1]];
    const c2 = lookup[clean[i + 2]];
    const c3 = lookup[clean[i + 3]];
    out.push((c0 << 2) | (c1 >> 4));
    if (clean[i + 2] !== undefined) out.push(((c1 & 15) << 4) | (c2 >> 2));
    if (clean[i + 3] !== undefined) out.push(((c2 & 3) << 6) | c3);
  }
  return new Uint8Array(out);
}

function utf8Encode(s: string): Uint8Array {
  // TextEncoder is available in Hermes/modern RN; fall back to a manual encoder.
  if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(s);
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let c = s.charCodeAt(i);
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    else out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
  }
  return new Uint8Array(out);
}

function utf8Decode(bytes: Uint8Array): string {
  if (typeof TextDecoder !== 'undefined') return new TextDecoder().decode(bytes);
  let out = '';
  for (let i = 0; i < bytes.length; ) {
    const b = bytes[i++];
    if (b < 0x80) out += String.fromCharCode(b);
    else if (b < 0xe0) out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i++] & 0x3f));
    else out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f));
  }
  return out;
}

function xor(bytes: Uint8Array): Uint8Array {
  const k = utf8Encode(KEY);
  const out = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) out[i] = bytes[i] ^ k[i % k.length];
  return out;
}

/** Encode a JSON string into a GK1 blob. */
export function encode(json: string): string {
  return TAG + b64urlEncode(xor(utf8Encode(json)));
}

/** Decode a GK1 blob to its JSON string. Tolerates a raw (non-GK1) JSON body. */
export function decode(blob: string): string {
  if (!blob.startsWith(TAG)) return blob;
  return utf8Decode(xor(b64urlDecode(blob.slice(TAG.length))));
}
