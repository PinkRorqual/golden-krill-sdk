import {
  adBundleFromJson,
  adItemFromList,
  serveConfigFromJson,
  DEFAULT_CONFIG,
  bannerRotationMs,
  rewardedMs,
  rollAdBadge,
} from '../src/models';

describe('wire models', () => {
  it('adBundle parses tuples and drops junk rows', () => {
    const b = adBundleFromJson({
      a: [[1, 'img', 'store'], [2, 'i2'], 'bad', [3]],
      o: [[9, 'o', 's']],
      n: 'NONCE',
    });
    expect(b.ads.map((x) => x.id)).toEqual([1, 2]); // 'bad' + too-short [3] dropped
    expect(b.ads[0].store).toBe('store');
    expect(b.own[0].id).toBe(9);
    expect(b.nonce).toBe('NONCE');
  });

  it('adItemFromList rejects non-arrays + bad types', () => {
    expect(adItemFromList('nope')).toBeNull();
    expect(adItemFromList([null, 'img'])).toBeNull();
    expect(adItemFromList([1, 2])).toBeNull();
  });

  it('serveConfig fills defaults for missing fields', () => {
    const c = serveConfigFromJson({ reserve_one_in: 7 });
    expect(c.reserveOneIn).toBe(7);
    expect(c.reserveShare).toBe(true);
    expect(c.maxPerSession).toBe(DEFAULT_CONFIG.maxPerSession);
  });

  it('parses banner_sdk_refresh, badge chance + url', () => {
    expect(serveConfigFromJson({}).bannerSdkRefresh).toBe(false);
    expect(serveConfigFromJson({ banner_sdk_refresh: true }).bannerSdkRefresh).toBe(true);
    const c = serveConfigFromJson({ ad_badge_chance: 0.5, badge_url: 'https://x' });
    expect(c.adBadgeChance).toBe(0.5);
    expect(c.badgeUrl).toBe('https://x');
  });

  it('bannerRotationMs: configured value, else jittered 55-65s', () => {
    expect(bannerRotationMs(serveConfigFromJson({ banner_rotation_sec: 30 }))).toBe(30000);
    const ms = bannerRotationMs(serveConfigFromJson({}));
    expect(ms).toBeGreaterThanOrEqual(55000);
    expect(ms).toBeLessThanOrEqual(65000);
  });

  it('rewardedMs: configured value, else 10s default', () => {
    expect(rewardedMs(serveConfigFromJson({ rewarded_seconds: 7 }))).toBe(7000);
    expect(rewardedMs(serveConfigFromJson({}))).toBe(10000);
  });

  it('rollAdBadge: never at chance 0, always at chance 1', () => {
    expect(rollAdBadge(serveConfigFromJson({ ad_badge_chance: 0 }))).toBe(false);
    expect(rollAdBadge(serveConfigFromJson({ ad_badge_chance: 1 }))).toBe(true);
  });
});
