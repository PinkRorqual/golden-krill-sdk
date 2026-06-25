import { GoldenKrillAds } from '../src/ads';
import { enc, resp, memStore, flush } from './_helpers';

// RN parity with the Flutter step-2 hook: the SDK forwards a host-provided opaque token,
// bound to the per-serve nonce, and a missing/failing provider never blocks/drops a beacon.
function adsAtt(provider?: (n: string) => Promise<string>, onEvents?: (b: any) => void) {
  return new GoldenKrillAds('com.x', {
    storage: memStore(), now: () => 1e12,
    attestationProvider: provider,
    fetchImpl: async (u: any, init: any) => {
      if (init && init.body) { onEvents?.(JSON.parse(init.body)); return resp(200, ''); } // /events beacon
      if (String(u).includes('/config/')) return resp(200, enc({ house_cooldown_sec: 0, reserve_share: false }));
      return resp(200, enc({ a: [[1, 'i', 's']], o: [], n: 'NONCE1' }));
    },
  });
}

async function beaconOnce(ads: GoldenKrillAds) {
  await ads.ensureReady('banner');
  await ads.fallbackAd('banner'); // records an impression -> beacon (fire-and-forget)
  await flush();
}

describe('attestation passthrough (RN)', () => {
  it('forwards the host token + per-serve nonce', async () => {
    let seenNonce = '';
    let body: any = null;
    const ads = adsAtt(async (n) => { seenNonce = n; return `TOKEN-${n}`; }, (b) => (body = b));
    await beaconOnce(ads);
    expect(seenNonce).toBe('NONCE1');
    expect(body.attestation).toBe('TOKEN-NONCE1');
    expect(body.nonce).toBe('NONCE1');
  });

  it('no provider -> beacon carries an empty attestation', async () => {
    let body: any = null;
    const ads = adsAtt(undefined, (b) => (body = b));
    await beaconOnce(ads);
    expect(body.attestation).toBe('');
  });

  it('throwing provider still fires the beacon, without attestation', async () => {
    let body: any = null;
    const ads = adsAtt(async () => { throw new Error('no integrity'); }, (b) => (body = b));
    await beaconOnce(ads);
    expect(body).not.toBeNull(); // never dropped
    expect(body.attestation).toBe('');
  });
});
