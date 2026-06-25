import { GoldenKrillClient, ClientOptions } from './client';
import { AdBundle, AdItem, DEFAULT_CONFIG, EMPTY_BUNDLE, ServeConfig } from './models';
import { gkLog } from './debug';

/** How long a last-good response stays usable as an offline failover. */
export const FAILOVER_TTL_MS = 60 * 60 * 1000; // 1h

/** How long to wait for the host attestation provider before beaconing without it. */
export const ATTESTATION_TIMEOUT_MS = 4000;

/** Resolve `p`, or reject after `ms` - so a slow attestation provider never stalls a beacon.
 *  The timer is cleared when `p` settles, so it never leaks/keeps the process alive. */
function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let handle: ReturnType<typeof setTimeout>;
  const timer = new Promise<T>((_resolve, reject) => {
    handle = setTimeout(() => reject(new Error('timeout')), ms);
  });
  return Promise.race([p.finally(() => clearTimeout(handle)), timer]);
}

/** The integration facade. One instance per app, held next to your own ads code.
 *  Mirrors the Flutter SDK.
 *
 *  Serving model: every display hits the server fresh. The server returns ONE random
 *  cross-promo + ONE random own-studio ad and randomizes per call, so rotation lives
 *  server-side; the SDK does not cache for rotation or rotate locally. The only cache is
 *  an offline failover: the last *successful* response is reused (up to FAILOVER_TTL_MS)
 *  ONLY when a fetch fails. A successful but empty response is a real no-fill ("empty is
 *  empty") - the slot collapses and the app proceeds to its paid ad.
 *
 *  Picks return null -> show nothing (collapse the slot). Never throws. */
export class GoldenKrillAds {
  private client: GoldenKrillClient;
  private now: () => number;
  private cfg: ServeConfig = DEFAULT_CONFIG;
  private cfgLoaded = false;
  private failover: Record<string, { bundle: AdBundle; at: number }> = {}; // last good per slot

  private eligible = 0; // interstitial reserve cadence
  private rewardedEligible = 0; // rewarded reserve cadence
  private lastGkAt: number | null = null;  // GK pool cooldown clock (houseCooldownSec)
  private lastOwnAt: number | null = null; // studio own pool cooldown clock (ownAdsCooldownMin)

  /** Set whenever rewarded availability changes; bind a "watch ad" button to it. */
  onRewardedAvailable?: (available: boolean) => void;

  /** Optional host hook to forward an attestation token on beacons (mirrors Flutter).
   *  Null = no attestation. The host mints + caches the token; the SDK only forwards it. */
  attestationProvider?: (nonce: string) => Promise<string>;

  constructor(pkg: string, opts: ClientOptions = {}) {
    // testMode defaults to __DEV__ (true in a dev build, false in a release/production
    // bundle), so an integrator sees an always-fill "TEST AD" while building and ships the
    // real path automatically. Override via opts.testMode (e.g. QA exercising real serving in
    // a release build). NEVER ship a release build with testMode forced on.
    const devDefault = typeof __DEV__ !== 'undefined' ? !!__DEV__ : false;
    this.client = new GoldenKrillClient(pkg, { ...opts, testMode: opts.testMode ?? devDefault });
    this.now = opts.now ?? (() => Date.now());
    this.attestationProvider = opts.attestationProvider;
  }

  get config(): ServeConfig {
    return this.cfg;
  }

  hasSlot(slot: string): boolean {
    return slot in this.failover;
  }

  async ensureReady(slot = 'banner', lang = 'en'): Promise<void> {
    if (!this.cfgLoaded) {
      this.cfg = await this.client.loadConfig();
      this.cfgLoaded = true;
    }
    await this.fetchBundle(slot, lang); // warm: seeds failover + rewarded availability (no impression)
    gkLog(
      () =>
        `ready[${slot}]: reserve=${this.cfg.reserveShare ? `1/${this.cfg.reserveOneIn}` : 'off'} ` +
        `fallback=${this.cfg.fallbackFill}`,
    );
  }

  /** Per-display fetch with offline failover. On success refresh the failover copy (even if
   *  empty) and return it; on failure reuse the last good copy if still fresh, else empty. */
  private async fetchBundle(slot: string, lang: string): Promise<AdBundle> {
    const r = await this.client.fetchAds(slot, lang);
    if (r.ok) {
      this.failover[slot] = { bundle: r.bundle, at: this.now() };
      this.refreshRewarded();
      return r.bundle;
    }
    const f = this.failover[slot];
    if (f && this.now() - f.at < FAILOVER_TTL_MS) {
      gkLog(() => `fetch[${slot}] failed -> failover (age ${Math.round((this.now() - f.at) / 1000)}s)`);
      return f.bundle;
    }
    return EMPTY_BUNDLE;
  }

  // Record an impression (no cooldown stamp - callers stamp the right clock). The serve's
  // nonce is echoed so the server can verify the beacon (replay defense).
  private record(slot: string, ad: AdItem, nonce: string): AdItem {
    this.beacon([{ creative: ad.id, slot, kind: 'view' }], nonce);
    return ad;
  }

  /** Fire an impression beacon, forwarding a host attestation token when an
   *  attestationProvider is set. Fire-and-forget + best-effort: a null/throwing/slow
   *  provider just beacons WITHOUT attestation - never blocked or dropped. Called once per
   *  beacon (not per impression in a loop); the host caches/refreshes its token. */
  private beacon(events: Array<Record<string, unknown>>, nonce: string): void {
    void this.postBeacon(events, nonce);
  }

  private async postBeacon(events: Array<Record<string, unknown>>, nonce: string): Promise<void> {
    let token = '';
    const provider = this.attestationProvider;
    if (provider) {
      try {
        token = await withTimeout(provider(nonce), ATTESTATION_TIMEOUT_MS);
      } catch {
        token = ''; // null / throw / timeout -> forward nothing, still beacon
      }
    }
    this.client.postEvents(events, nonce, token);
  }

  private gkCooldownOk(): boolean {
    return this.lastGkAt == null || (this.now() - this.lastGkAt) / 1000 >= this.cfg.houseCooldownSec;
  }

  private ownCooldownOk(): boolean {
    return this.lastOwnAt == null || (this.now() - this.lastOwnAt) / 1000 >= this.cfg.ownAdsCooldownMin * 60;
  }

  // --- Interstitial (count-based reserve + cooldown) ---

  /** RESERVE: call before the paid ad; returns a cross-promo on ~1-in-N moments, else null. */
  async reserveAd(slot: string, lang = 'en'): Promise<AdItem | null> {
    if (!this.cfg.reserveShare || this.cfg.reserveOneIn < 1) {
      this.eligible++;
      return null;
    }
    const should = this.eligible % this.cfg.reserveOneIn === 0; // 1st, then every Nth
    this.eligible++;
    if (!should) return null;
    const b = await this.fetchBundle(slot, lang);
    if (!b.ads.length) return null; // reserve serves the GK pool only
    this.lastGkAt = this.now();    // a GK ad shown -> start the GK cooldown
    return this.record(slot, b.ads[0], b.nonce);
  }

  /** FALLBACK: call on a paid no-fill. Pool 1 (GK) if fallbackFill + GK cooldown elapsed;
   *  else pool 2 (studio own) if its own cooldown elapsed (server returns own only when the
   *  app opted into fill_own_ads). Two separate cooldowns so they don't spam each other. */
  async fallbackAd(slot: string, lang = 'en'): Promise<AdItem | null> {
    const b = await this.fetchBundle(slot, lang);
    if (this.cfg.fallbackFill && b.ads.length && this.gkCooldownOk()) {
      this.lastGkAt = this.now();
      return this.record(slot, b.ads[0], b.nonce);
    }
    if (b.own.length && this.ownCooldownOk()) {
      this.lastOwnAt = this.now();
      return this.record(slot, b.own[0], b.nonce);
    }
    return null;
  }

  // --- Banner (time-based reserve; fill/cadence-gated, no cooldown) ---

  bannerReserveTurn(unit: number): boolean {
    return this.cfg.reserveShare && this.cfg.reserveOneIn >= 1 && unit % this.cfg.reserveOneIn === 0;
  }

  async bannerHouse(slot: string, lang = 'en'): Promise<AdItem | null> {
    const b = await this.fetchBundle(slot, lang);
    const ad = b.ads.length ? b.ads[0] : b.own.length ? b.own[0] : null;
    if (!ad) return null;
    this.beacon([{ creative: ad.id, slot, kind: 'view' }], b.nonce); // no cooldown stamp
    gkLog(() => `banner[${slot}]: house id=${ad.id}`);
    return ad;
  }

  // --- Rewarded (reuses the interstitial slot). Reserve = always 1-in-N; the user-initiated
  //     fallback always serves (they asked for it) - no cooldown. ---

  /** Whether rewarded looked available at the last fetch (approximate; the show re-fetches). */
  get rewardedReady(): boolean {
    const f = this.failover['interstitial'];
    return !!f && (f.bundle.ads.length > 0 || f.bundle.own.length > 0);
  }

  private refreshRewarded(): void {
    this.onRewardedAvailable?.(this.rewardedReady);
  }

  /** REWARDED RESERVE: ~1-in-N reward moments show ours instead of paid (cross-promo only). */
  async rewardedReserve(lang = 'en'): Promise<AdItem | null> {
    if (!this.cfg.reserveShare || this.cfg.reserveOneIn < 1) {
      this.rewardedEligible++;
      return null;
    }
    const should = this.rewardedEligible % this.cfg.reserveOneIn === 0;
    this.rewardedEligible++;
    if (!should) return null;
    const b = await this.fetchBundle('interstitial', lang);
    return b.ads.length ? this.record('interstitial', b.ads[0], b.nonce) : null;
  }

  async rewardedHouse(lang = 'en'): Promise<AdItem | null> {
    // User-initiated: always serve what we have (no cooldown).
    const b = await this.fetchBundle('interstitial', lang);
    const ad = b.ads.length ? b.ads[0] : b.own.length ? b.own[0] : null;
    return ad ? this.record('interstitial', ad, b.nonce) : null;
  }

  /** New session (e.g. resume after long background): reset the reserve cadence + cooldown.
   *  The offline failover copy is kept (it's a cross-session safety net). */
  resetSession(): void {
    this.eligible = 0;
    this.rewardedEligible = 0;
    this.lastGkAt = null;
    this.lastOwnAt = null;
  }
}
