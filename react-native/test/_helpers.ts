import * as gk1 from '../src/gk1';
import { GoldenKrillAds } from '../src/ads';
/** Encode an object as a GK1 blob (what the server returns). */
export const enc = (o: unknown) => gk1.encode(JSON.stringify(o));
/** A minimal fetch Response stub (the client reads .status + .text()). */
export const resp = (status: number, body = '') => ({ status, text: async () => body } as any);
/** In-memory StorageLike for tests. */
export function memStore() {
  const m = new Map<string, string>();
  return {
    getItem: async (k: string) => (m.has(k) ? (m.get(k) as string) : null),
    setItem: async (k: string, v: string) => { m.set(k, v); },
  };
}
/** Let fire-and-forget beacons (provider + deviceToken + fetch) settle. */
export const flush = () => new Promise((r) => setTimeout(r, 20));

/** A GoldenKrillAds backed by a mock server: /config returns `cfg`, /ads returns `adsResp`. */
export function makeAds(adsResp: unknown, cfg: object = {}) {
  return new GoldenKrillAds('com.x', {
    storage: memStore(),
    now: () => 0,
    fetchImpl: async (u: any) =>
      String(u).includes('/config/') ? resp(200, enc(cfg)) : resp(200, enc(adsResp)),
  });
}
