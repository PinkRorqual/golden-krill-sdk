// Frozen serving endpoints + cache TTLs (the API model). The SDK talks only to these.
export const SERVING_BASE = 'https://a.golden-krill.com';

/// Where the disclosure badge sends a user who taps it (who we are / how to join).
export const BADGE_INFO_URL = 'https://golden-krill.com/about';

export const CONFIG_TTL_MS = 12 * 60 * 60 * 1000; // 12h
export const ADS_TTL_MS = 1 * 60 * 60 * 1000; // 1h

export function configUrl(pkg: string, base = SERVING_BASE, test = false): string {
  return `${base}/api/v1/config/${encodeURIComponent(pkg)}?fmt=gk1${test ? '&test=1' : ''}`;
}

export function adsUrl(pkg: string, slot: string, lang = 'en', store?: string, base = SERVING_BASE, test = false): string {
  const q = new URLSearchParams({ app: pkg, slot, lang, fmt: 'gk1' });
  if (store) q.set('store', store); // platform store so the click resolves the right app store
  if (test) q.set('test', '1'); // test mode: server returns a TEST AD and counts nothing
  return `${base}/api/v1/ads?${q.toString()}`;
}

export function eventsUrl(base = SERVING_BASE): string {
  return `${base}/api/v1/events`;
}
