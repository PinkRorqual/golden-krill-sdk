import { GoldenKrillAds } from '../src/ads';
import { GoldenKrillClient } from '../src/client';
import { adsUrl, configUrl } from '../src/endpoints';
import { enc, resp, memStore, flush } from './_helpers';

// Prompt 16 test mode (RN parity): testMode defaults to __DEV__, sends test=1 on /ads +
// /config and test:true on beacons, and renders the server's TEST AD normally.
function recordingAds(testMode?: boolean) {
  const urls: string[] = [];
  let body: any = null;
  const ads = new GoldenKrillAds('com.x', {
    storage: memStore(),
    now: () => 1e12,
    testMode,
    fetchImpl: async (u: any, init: any) => {
      urls.push(String(u));
      if (init && init.body) { body = JSON.parse(init.body); return resp(200, ''); }
      if (String(u).includes('/config/')) return resp(200, enc({ house_cooldown_sec: 0, reserve_share: false }));
      return resp(200, enc({ a: [[0, 'i', 's']], o: [], n: 'N', t: 1 }));
    },
  });
  return { ads, urls: () => urls, body: () => body };
}

async function run(r: ReturnType<typeof recordingAds>) {
  await r.ads.ensureReady('banner');
  await r.ads.fallbackAd('banner'); // records an impression -> beacon
  await flush();
}

describe('test mode (RN)', () => {
  it('endpoints add test=1 only when requested', () => {
    expect(adsUrl('p', 'banner', 'en', undefined, undefined, true)).toContain('test=1');
    expect(adsUrl('p', 'banner')).not.toContain('test=1');
    expect(configUrl('p', undefined, true)).toContain('test=1');
    expect(configUrl('p')).not.toContain('test=1');
  });

  it('testMode sends test=1 on ads + config and test:true on the beacon', async () => {
    const r = recordingAds(true);
    await run(r);
    expect(r.urls().some((u) => u.includes('/config/') && u.includes('test=1'))).toBe(true);
    expect(r.urls().some((u) => u.includes('/ads?') && u.includes('test=1'))).toBe(true);
    expect(r.body().test).toBe(true);
  });

  it('explicit testMode=false never sends test', async () => {
    const r = recordingAds(false);
    await run(r);
    expect(r.urls().every((u) => !u.includes('test=1'))).toBe(true);
    expect(r.body() && r.body().test).toBeFalsy();
  });

  it('client default is false; ads layer defaults to __DEV__', () => {
    expect(new GoldenKrillClient('p', {}).testMode).toBe(false);
    (global as any).__DEV__ = true;
    expect((recordingAds(undefined).ads as any).client.testMode).toBe(true);
    (global as any).__DEV__ = false;
    expect((recordingAds(undefined).ads as any).client.testMode).toBe(false);
  });
});
