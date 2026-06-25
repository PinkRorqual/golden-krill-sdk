import { Platform } from 'react-native';
import * as gk1 from './gk1';
import { adsUrl, configUrl, eventsUrl, CONFIG_TTL_MS, SERVING_BASE } from './endpoints';

// The device's app store: iOS -> App Store; everything else -> Play (Android default).
const DEVICE_STORE = Platform.OS === 'ios' ? 'appstore' : 'play';
import {
  AdBundle,
  adBundleFromJson,
  DEFAULT_CONFIG,
  EMPTY_BUNDLE,
  ServeConfig,
  serveConfigFromJson,
} from './models';
import { gkLog } from './debug';

export interface StorageLike {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
}

function defaultStorage(): StorageLike {
  try {
    // Use AsyncStorage if the app has it; otherwise fall back to in-memory (no persistence).
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    return require('@react-native-async-storage/async-storage').default as StorageLike;
  } catch {
    const mem = new Map<string, string>();
    return {
      getItem: async (k) => (mem.has(k) ? (mem.get(k) as string) : null),
      setItem: async (k, v) => {
        mem.set(k, v);
      },
    };
  }
}

export interface ClientOptions {
  fetchImpl?: typeof fetch;
  storage?: StorageLike;
  now?: () => number;
  base?: string;
  configTtlMs?: number;
  adsTtlMs?: number;
  /** Optional host hook to forward an opaque attestation token (Play Integrity / App
   *  Attest) on beacons, bound to the per-serve nonce. The SDK never mints it; null =
   *  no attestation. Mirrors the Flutter AttestationProvider. */
  attestationProvider?: (nonce: string) => Promise<string>;
  /** Test mode: ask the server for an always-fill TEST AD and tell it to count nothing. NOT
   *  a security boundary (a client can lie); only metric hygiene. Defaults from __DEV__ at
   *  the GoldenKrillAds layer. */
  testMode?: boolean;
}

/** Talks to the serving API: GK1 fetch + last-good cache + fire-and-forget beacons.
 *  Never throws; degrades to cache then defaults/empty. */
export class GoldenKrillClient {
  readonly pkg: string;
  private fetchImpl: typeof fetch;
  private storage: StorageLike;
  private now: () => number;
  private base: string;
  private configTtlMs: number;
  readonly testMode: boolean;

  constructor(pkg: string, opts: ClientOptions = {}) {
    this.pkg = pkg;
    this.fetchImpl = opts.fetchImpl ?? fetch;
    this.storage = opts.storage ?? defaultStorage();
    this.now = opts.now ?? (() => Date.now());
    this.base = opts.base ?? SERVING_BASE;
    this.configTtlMs = opts.configTtlMs ?? CONFIG_TTL_MS;
    this.testMode = opts.testMode ?? false;
  }

  private cfgKey = () => `gk_cfg_v1_${this.pkg}`;

  async loadConfig(): Promise<ServeConfig> {
    const json = await this.cachedJson(this.cfgKey(), configUrl(this.pkg, this.base, this.testMode), this.configTtlMs);
    return json ? serveConfigFromJson(json) : DEFAULT_CONFIG;
  }

  /**
   * Per-display ad fetch. The server returns one random cross-promo + one random own-studio
   * ad and randomizes per call, so we fetch fresh every time (no on-device TTL cache here).
   * `ok === false` means the fetch FAILED (network/HTTP/bad blob) and the caller may failover;
   * `ok === true` with an empty bundle is a real no-fill ("empty is empty"). Never throws.
   */
  async fetchAds(slot: string, lang = 'en'): Promise<{ bundle: AdBundle; ok: boolean }> {
    const body = await this.fetchText(adsUrl(this.pkg, slot, lang, DEVICE_STORE, this.base, this.testMode));
    if (body == null) return { bundle: EMPTY_BUNDLE, ok: false };
    const json = this.parse(body);
    if (json == null) return { bundle: EMPTY_BUNDLE, ok: false };
    return { bundle: adBundleFromJson(json), ok: true };
  }

  /** Force a re-fetch on the next load by clearing the freshness timestamps. */
  async refresh(): Promise<void> {
    await this.storage.setItem(`${this.cfgKey()}_at`, '0');
  }

  private async cachedJson(blobKey: string, url: string, ttlMs: number): Promise<any | null> {
    const atKey = `${blobKey}_at`;
    const at = await this.storage.getItem(atKey);
    const cached = await this.storage.getItem(blobKey);
    const fresh = at != null && this.now() - parseInt(at, 10) < ttlMs;
    if (fresh && cached) return this.parse(cached); // within TTL -> reuse cache, no fetch
    const body = await this.fetchText(url);
    if (body != null) {
      await this.storage.setItem(blobKey, body);
      await this.storage.setItem(atKey, String(this.now()));
      return this.parse(body);
    }
    if (cached) return this.parse(cached); // fetch failed -> last-good cache
    return null; // nothing -> caller uses defaults/empty
  }

  private parse(blob: string): any | null {
    try {
      const obj = JSON.parse(gk1.decode(blob));
      return obj && typeof obj === 'object' ? obj : null;
    } catch {
      return null;
    }
  }

  private async fetchText(url: string): Promise<string | null> {
    try {
      const r = await this.fetchImpl(url);
      if (r.status === 200) {
        const t = await r.text();
        if (t) return t;
      }
      gkLog(() => `fetch ${url}: HTTP ${r.status} (using cache/defaults)`);
      return null;
    } catch (e) {
      gkLog(() => `fetch ${url}: ${e} (using cache/defaults)`);
      return null;
    }
  }

  /** Fire-and-forget impression/tap beacons (app-keyed; no advertising id). Sends an
   *  anonymous, weekly-rotating device token so the server can approximate distinct-device
   *  reach per app WITHOUT any stable identity or cross-app key (see trust-and-metrics). */
  postEvents(events: Array<Record<string, unknown>>, nonce = '', attestation = ''): void {
    this.deviceToken()
      .then((device) =>
        this.fetchImpl(eventsUrl(this.base), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ host: this.pkg, attestation, device, nonce, events, ...(this.testMode ? { test: true } : {}) }),
        }),
      )
      .catch(() => {});
  }

  /** Anonymous reach token: a random value kept in this app's own storage and rotated
   *  weekly, so it can never track a person or cross-link apps. Not an advertising id. */
  private async deviceToken(): Promise<string> {
    const TTL = 7 * 24 * 60 * 60 * 1000; // 1 week
    const tok = await this.storage.getItem('gk_did_v1');
    const at = await this.storage.getItem('gk_did_at_v1');
    if (tok && at && this.now() - parseInt(at, 10) < TTL) return tok;
    const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    let fresh = '';
    for (let i = 0; i < 22; i++) fresh += abc[Math.floor(Math.random() * abc.length)];
    await this.storage.setItem('gk_did_v1', fresh);
    await this.storage.setItem('gk_did_at_v1', String(this.now()));
    return fresh;
  }
}
