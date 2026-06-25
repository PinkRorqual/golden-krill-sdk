import { GoldenKrillAds } from '../src/ads';
import { GoldenKrillDebug } from '../src/debug';
import { enc, resp, memStore } from './_helpers';

function adsWith(handler: (url: string) => any, now: () => number = () => 0) {
  return new GoldenKrillAds('com.x', {
    storage: memStore(), now,
    fetchImpl: async (u: any) => handler(String(u)),
  });
}

const cfgThen = (cfg: object, ads: object) => (url: string) =>
  url.includes('/config/') ? resp(200, enc(cfg)) : resp(200, enc(ads));

describe('GoldenKrillAds facade', () => {
  it('fallback serves once, then is gated by the GK cooldown', async () => {
    let t = 1e12;
    const a = adsWith(cfgThen({ house_cooldown_sec: 100, reserve_share: false }, { a: [[1, 'i', 's']], o: [] }), () => t);
    await a.ensureReady('banner');
    expect((await a.fallbackAd('banner'))!.id).toBe(1); // serves
    expect(await a.fallbackAd('banner')).toBeNull();    // within cooldown -> blocked
    t += 200000;
    expect((await a.fallbackAd('banner'))!.id).toBe(1); // cooldown elapsed -> serves again
  });

  it('bannerReserveTurn is 1-in-N', async () => {
    const a = adsWith(cfgThen({ reserve_share: true, reserve_one_in: 3 }, { a: [], o: [] }));
    await a.ensureReady('banner');
    expect(a.bannerReserveTurn(0)).toBe(true);
    expect(a.bannerReserveTurn(1)).toBe(false);
    expect(a.bannerReserveTurn(3)).toBe(true);
  });

  it('reserveAd follows the 1-in-N cadence', async () => {
    const a = adsWith(cfgThen({ reserve_share: true, reserve_one_in: 2, house_cooldown_sec: 0 }, { a: [[1, 'i', 's']], o: [] }));
    await a.ensureReady('interstitial');
    expect((await a.reserveAd('interstitial'))!.id).toBe(1); // eligible 0 -> hit
    expect(await a.reserveAd('interstitial')).toBeNull();    // eligible 1 -> miss
    expect((await a.reserveAd('interstitial'))!.id).toBe(1); // eligible 2 -> hit
  });

  it('reserveAd is off when reserveShare is false', async () => {
    const a = adsWith(cfgThen({ reserve_share: false }, { a: [[1, 'i', 's']], o: [] }));
    await a.ensureReady('interstitial');
    expect(await a.reserveAd('interstitial')).toBeNull();
  });

  it('rewardedReady reflects the last fetch; rewardedHouse serves; resetSession is safe', async () => {
    const a = adsWith(cfgThen({}, { a: [[5, 'i', 's']], o: [] }));
    await a.ensureReady('interstitial');
    expect(a.rewardedReady).toBe(true);
    expect((await a.rewardedHouse())!.id).toBe(5);
    a.resetSession();
    expect(a.rewardedReady).toBe(true); // failover kept across a session reset
  });

  it('fetchBundle reuses the offline failover when a later fetch fails', async () => {
    let fail = false;
    const a = adsWith((url) =>
      url.includes('/config/') ? resp(200, enc({ house_cooldown_sec: 0, reserve_share: false }))
        : fail ? resp(500, 'x') : resp(200, enc({ a: [[7, 'i', 's']], o: [] })));
    await a.ensureReady('banner'); // warms failover with [7]
    fail = true;
    expect((await a.fallbackAd('banner'))!.id).toBe(7); // fetch fails -> failover reuse
  });

  it('bannerHouse + rewardedReserve serve, with debug logging on', async () => {
    GoldenKrillDebug.enabled = true; // exercises the gkLog message closures
    try {
      const a = adsWith(cfgThen({ reserve_share: true, reserve_one_in: 1, house_cooldown_sec: 0 },
        { a: [[2, 'i', 's']], o: [[9, 'o', 's']] }));
      await a.ensureReady('banner');
      expect((await a.bannerHouse('banner'))!.id).toBe(2);
      expect((await a.rewardedReserve())!.id).toBe(2); // reserve_one_in 1 -> always a reserve turn
    } finally {
      GoldenKrillDebug.enabled = false;
    }
  });

  it('fallback drops to the own-studio pool when GK fill is off', async () => {
    const a = adsWith(cfgThen({ fallback_fill: false, reserve_share: false, own_ads_cooldown_min: 0 },
      { a: [[1, 'i', 's']], o: [[9, 'o', 's']] }));
    await a.ensureReady('interstitial');
    expect((await a.fallbackAd('interstitial'))!.id).toBe(9); // GK off -> own pool
  });

  it('bannerHouse returns null on no inventory', async () => {
    const a = adsWith(cfgThen({}, { a: [], o: [] }));
    await a.ensureReady('banner');
    expect(await a.bannerHouse('banner')).toBeNull();
  });
});
