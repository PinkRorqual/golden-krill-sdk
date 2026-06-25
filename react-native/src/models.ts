// Wire models, mirroring the Flutter SDK. Parsing is defensive: malformed rows are
// dropped, never thrown.

export interface AdItem {
  id: number;
  image: string;
  store?: string; // a /c tracker URL: open verbatim, it 302s to the store and counts the click
}

/** Parse a `[id, image, store]` tuple (tolerates extra trailing slots). */
export function adItemFromList(row: unknown): AdItem | null {
  if (!Array.isArray(row) || row.length < 2) return null;
  const id = row[0];
  const image = row[1];
  if (typeof id !== 'number' || typeof image !== 'string') return null;
  const store = row.length > 2 && typeof row[2] === 'string' ? row[2] : undefined;
  return { id, image, store };
}

/** The two-tier /ads response: `a` = cross-promo, `o` = own-studio last resort. */
export interface AdBundle {
  ads: AdItem[];
  own: AdItem[];
  /** Per-serve single-use nonce, echoed on the beacon for replay defense. Opaque. */
  nonce: string;
}

export const EMPTY_BUNDLE: AdBundle = { ads: [], own: [], nonce: '' };

export function adBundleFromJson(json: any): AdBundle {
  const items = (x: unknown): AdItem[] =>
    Array.isArray(x) ? (x.map(adItemFromList).filter(Boolean) as AdItem[]) : [];
  return { ads: items(json?.a), own: items(json?.o), nonce: typeof json?.n === 'string' ? json.n : '' };
}

/** Per-app serving config from /config. Missing fields fall back to house-friendly defaults. */
export interface ServeConfig {
  reserveShare: boolean;
  reserveOneIn: number;
  fallbackFill: boolean;
  fillOwnAds: boolean;
  houseCooldownSec: number;
  maxPerSession: number;
  ownAdsCooldownMin: number;
  bannerRotationSec: number; // 0 = SDK jitters ~55-65s
  rewardedSeconds: number; // 0 = SDK default 10s
  adBadgeChance: number; // 0..1 probability of drawing the disclosure badge, rolled per display
  badgeUrl: string; // where the badge tap goes; '' -> SDK default (BADGE_INFO_URL)
  bannerSdkRefresh: boolean; // host banner strategy: false = Regular, true = Advanced (SDK-driven)
}

export const DEFAULT_CONFIG: ServeConfig = {
  reserveShare: true,
  reserveOneIn: 4,
  fallbackFill: true,
  fillOwnAds: false,
  houseCooldownSec: 240,
  maxPerSession: 3,
  ownAdsCooldownMin: 5,
  bannerRotationSec: 0,
  rewardedSeconds: 0,
  adBadgeChance: 0,
  badgeUrl: '',
  bannerSdkRefresh: false,
};

const b = (v: unknown, d: boolean) => (typeof v === 'boolean' ? v : d);
const i = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : d);

export function serveConfigFromJson(json: any): ServeConfig {
  return {
    reserveShare: b(json?.reserve_share, DEFAULT_CONFIG.reserveShare),
    reserveOneIn: i(json?.reserve_one_in, DEFAULT_CONFIG.reserveOneIn),
    fallbackFill: b(json?.fallback_fill, DEFAULT_CONFIG.fallbackFill),
    fillOwnAds: b(json?.fill_own_ads, DEFAULT_CONFIG.fillOwnAds),
    houseCooldownSec: i(json?.house_cooldown_sec, DEFAULT_CONFIG.houseCooldownSec),
    maxPerSession: i(json?.max_per_session, DEFAULT_CONFIG.maxPerSession),
    ownAdsCooldownMin: i(json?.own_ads_cooldown_min, DEFAULT_CONFIG.ownAdsCooldownMin),
    bannerRotationSec: i(json?.banner_rotation_sec, 0),
    rewardedSeconds: i(json?.rewarded_seconds, 0),
    adBadgeChance: typeof json?.ad_badge_chance === 'number' && Number.isFinite(json.ad_badge_chance) ? json.ad_badge_chance : 0,
    badgeUrl: typeof json?.badge_url === 'string' ? json.badge_url : '',
    bannerSdkRefresh: b(json?.banner_sdk_refresh, DEFAULT_CONFIG.bannerSdkRefresh),
  };
}

/** Roll whether to draw the disclosure badge on this display (probability adBadgeChance). */
export function rollAdBadge(cfg: ServeConfig, rnd = Math.random): boolean {
  return cfg.adBadgeChance > 0 && rnd() < cfg.adBadgeChance;
}

/** Effective banner rotation interval (ms): configured value if set, else jittered ~55-65s. */
export function bannerRotationMs(cfg: ServeConfig, rnd = Math.random): number {
  const sec = cfg.bannerRotationSec > 0 ? cfg.bannerRotationSec : 55 + Math.floor(rnd() * 11);
  return sec * 1000;
}

/** Effective rewarded countdown (ms): configured value if set, else the 10s default. */
export function rewardedMs(cfg: ServeConfig): number {
  return (cfg.rewardedSeconds > 0 ? cfg.rewardedSeconds : 10) * 1000;
}
