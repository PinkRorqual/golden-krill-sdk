import { createHash } from 'crypto';
import { readFileSync } from 'fs';
import { join } from 'path';
import * as gk1 from '../src/gk1';

// Vendored byte copy of ../../conformance/gk1_vectors.json (ports cannot read the sibling
// conformance/ dir at test time). Its sha256 must equal the canonical hash in
// conformance/README.md, so a mis-transcribed copy fails loudly.
const CANONICAL_SHA256 = '8064704da42255c923cd0a041f2b9eff265a9339e059bbc997354e43ed81cbe6';
const raw = readFileSync(join(__dirname, 'gk1_vectors.json'));
const vectors = JSON.parse(raw.toString('utf8')) as {
  cases: Array<{ name: string; json: string; gk1: string; decoded: unknown }>;
};

describe('GK1 conformance vector', () => {
  it('vendored copy matches the canonical sha256', () => {
    expect(createHash('sha256').update(raw).digest('hex')).toBe(CANONICAL_SHA256);
  });

  for (const c of vectors.cases) {
    it(`${c.name}: decode(gk1) is byte-exact json`, () => {
      expect(gk1.decode(c.gk1)).toBe(c.json);
    });
    it(`${c.name}: encode(json) is byte-exact gk1`, () => {
      expect(gk1.encode(c.json)).toBe(c.gk1);
    });
    it(`${c.name}: decoded struct matches`, () => {
      expect(JSON.parse(gk1.decode(c.gk1))).toEqual(c.decoded);
    });
  }

  it('raw JSON object/array passes through (dev/test fallback)', () => {
    expect(gk1.decode('{"a":1}')).toBe('{"a":1}');
    expect(gk1.decode('[1,2,3]')).toBe('[1,2,3]');
  });

  it('round-trips an arbitrary unicode string', () => {
    const s = '{"hi":"wörld-日本"}';
    expect(gk1.decode(gk1.encode(s))).toBe(s);
  });

  it('round-trips via the manual utf8 fallback (Hermes without TextEncoder/TextDecoder)', () => {
    const TE = (global as any).TextEncoder;
    const TD = (global as any).TextDecoder;
    (global as any).TextEncoder = undefined;
    (global as any).TextDecoder = undefined;
    try {
      const s = '{"x":"é-日"}';
      expect(gk1.decode(gk1.encode(s))).toBe(s);
    } finally {
      (global as any).TextEncoder = TE;
      (global as any).TextDecoder = TD;
    }
  });
});
