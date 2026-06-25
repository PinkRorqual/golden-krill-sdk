import 'dart:async';

import 'package:flutter/foundation.dart';

import '../gk_debug.dart';
import 'serve_models.dart';
import 'serving_client.dart';

/// How long a last-good response stays usable as an offline failover.
const Duration kFailoverTtl = Duration(hours: 1);

/// Optional host-supplied attestation hook. Given the per-serve [nonce], the HOST app
/// returns an opaque attestation token (Play Integrity on Android, App Attest later on
/// iOS) that the SDK FORWARDS on the impression beacon. The SDK never mints or gathers
/// it (minting needs native code = the host's job), so the SDK stays native-free and
/// open-source. The token is opaque to the SDK; only the server verifies it
/// (see golden-krill/docs/trust-and-metrics.md). This is inert until that server verification
/// (rollout step 3) lands. The host should cache/refresh its token - the SDK calls this
/// once per beacon, not per impression in a loop.
typedef AttestationProvider = Future<String> Function(String nonce);

/// How long the SDK waits for the host's attestation provider before giving up and
/// beaconing without attestation (a slow provider must never block or drop a beacon).
const Duration kAttestationTimeout = Duration(seconds: 4);

/// The integration façade, covering all three serving moments behind one object.
/// A consuming app holds one instance next to its own `AdsService`.
///
/// - **Reserve** ([reserveAd]) - on a configured ~1-in-N share of eligible moments,
///   show a cross-promo *before* the paid ad (only if enabled in config).
/// - **Fallback** ([fallbackAd]) - on a paid no-fill, fill the slot rather than blank.
/// - **Own-studio** - the last resort *inside* [fallbackAd]: when there's no cross-promo
///   it serves another of your studio's apps.
///
/// **Serving model:** every display hits the server fresh. The server returns ONE random
/// cross-promo ad + ONE random own-studio ad and randomizes per call, so rotation lives
/// server-side - the SDK does not cache for rotation or rotate locally. The only cache is
/// an offline **failover**: the last *successful* response is reused (up to [kFailoverTtl])
/// **only when a fetch fails**. A successful but empty response is a real no-fill ("empty
/// is empty") - the slot collapses and the app proceeds to its paid ad.
///
/// Cooldown ([ServeConfig.houseCooldownSec]) still gates the fallback; reserve is the
/// 1-in-N share; rewarded is user-initiated (no cooldown). Any method returns `null` ->
/// show nothing. Impressions are recorded for you; clicks are automatic (open `ad.store`,
/// a tracker URL that 302s to the store). Never throws.
class GoldenKrillAds {
  /// [testMode] defaults to [kDebugMode] (true in a debug build, false in release), so a
  /// developer sees an always-fill "TEST AD" while integrating and ships the real path
  /// automatically. Override it to force either path (e.g. QA exercising real serving on a
  /// release build). NEVER ship a release build with testMode forced on. Ignored when you
  /// inject your own [client] (set testMode on the client instead).
  GoldenKrillAds({
    String? package,
    GoldenKrillClient? client,
    DateTime Function()? now,
    this.attestationProvider,
    bool? testMode,
  })  : assert(package != null || client != null, 'provide package or client'),
        _client = client ?? GoldenKrillClient(package: package!, testMode: testMode ?? kDebugMode),
        _now = now ?? DateTime.now;

  final GoldenKrillClient _client;
  final DateTime Function() _now;

  /// Optional host hook to forward an attestation token on beacons. Null (default) =
  /// no attestation, today's behavior. See [AttestationProvider].
  final AttestationProvider? attestationProvider;

  ServeConfig _config = ServeConfig.defaults;
  bool _configLoaded = false;
  final Map<String, _Failover> _failover = {}; // last good response per slot (offline reuse)
  int _eligible = 0; // eligible moments seen (drives the interstitial reserve cadence)
  int _rewardedEligible = 0; // rewarded moments seen (drives the rewarded reserve cadence)
  // Two independent cooldowns so the GK pool + studio pool don't spam each other:
  DateTime? _lastGkAt;  // a GK (pool 1) ad was shown - gated by config.houseCooldownSec
  DateTime? _lastOwnAt; // a studio own (pool 2) ad was shown - gated by config.ownAdsCooldownMin

  /// Reactive availability for rewarded: the last fetch for the rewarded (interstitial)
  /// slot had inventory. Bind a "watch ad for reward" button's enabled state to this.
  final ValueNotifier<bool> rewardedAvailable = ValueNotifier<bool>(false);

  ServeConfig get config => _config;

  /// Whether a rewarded house ad looked available at the last fetch (approximate: the
  /// actual show re-fetches fresh). Reads the failover copy of the rewarded slot.
  bool get rewardedReady {
    final f = _failover['interstitial'];
    return f != null && (f.bundle.ads.isNotEmpty || f.bundle.own.isNotEmpty);
  }

  /// Whether a slot has a warmed/last-good response (used by the UI helpers to self-heal).
  bool hasSlot(String slot) => _failover.containsKey(slot);

  void _refreshRewardedSignal() => rewardedAvailable.value = rewardedReady;

  /// Load config (cached for the run) and warm the slot's failover copy. Call once at
  /// startup and/or before first use. Config is fetched once; the warm fetch seeds the
  /// offline failover + rewarded availability. Cheap and safe to call per slot.
  Future<void> ensureReady({String slot = 'banner', String lang = 'en'}) async {
    if (!_configLoaded) {
      _config = await _client.loadConfig();
      _configLoaded = true;
    }
    await _fetchBundle(slot, lang); // warm: seeds failover + availability (no impression)
    gkLog(() => 'ready[$slot]: reserve=${_config.reserveShare ? "1/${_config.reserveOneIn}" : "off"} '
        'fallback=${_config.fallbackFill}');
  }

  /// Per-display fetch with offline failover. On success, refresh the failover copy (even
  /// if empty) and return it. On failure, reuse the last good copy if it is still fresh,
  /// else empty. Never throws.
  Future<AdBundle> _fetchBundle(String slot, String lang) async {
    final r = await _client.fetchAds(slot: slot, lang: lang);
    if (r.ok) {
      _failover[slot] = _Failover(r.bundle, _now());
      _refreshRewardedSignal();
      return r.bundle;
    }
    final f = _failover[slot];
    if (f != null && _now().difference(f.at) < kFailoverTtl) {
      gkLog(() => 'fetch[$slot] failed -> failover (age ${_now().difference(f.at).inSeconds}s)');
      return f.bundle;
    }
    return AdBundle.empty;
  }

  // Record an impression (no cooldown stamp - callers stamp the right clock). The serve's
  // nonce is echoed so the server can verify the beacon (replay defense).
  AdItem _record(String slot, AdItem ad, String nonce) {
    _beacon([
      {'creative': ad.id, 'slot': slot, 'kind': 'view'},
    ], nonce);
    return ad;
  }

  /// Fire an impression beacon, forwarding a host attestation token when an
  /// [attestationProvider] is set. Fire-and-forget + best-effort: a null/throwing/slow
  /// provider just beacons WITHOUT attestation - it is never blocked or dropped. Called
  /// once per beacon (not per impression in a loop); the host caches/refreshes its token.
  void _beacon(List<Map<String, dynamic>> events, String nonce) {
    // ignore: discarded_futures - intentional fire-and-forget; never blocks the caller
    _postBeacon(events, nonce);
  }

  Future<void> _postBeacon(List<Map<String, dynamic>> events, String nonce) async {
    var token = '';
    final provider = attestationProvider;
    if (provider != null) {
      try {
        token = await provider(nonce).timeout(kAttestationTimeout);
      } catch (_) {
        token = ''; // null / throw / timeout -> forward nothing, still beacon
      }
    }
    await _client.postEvents(events, attestation: token, nonce: nonce);
  }

  bool _gkCooldownOk() {
    final t = _lastGkAt;
    return t == null || _now().difference(t).inSeconds >= _config.houseCooldownSec;
  }

  bool _ownCooldownOk() {
    final t = _lastOwnAt;
    return t == null || _now().difference(t).inSeconds >= _config.ownAdsCooldownMin * 60;
  }

  /// REWARDED: fetch a house rewarded creative (reuses the `interstitial` slot).
  /// User-initiated, so it always serves what's available (no cooldown). Records the
  /// impression. Returns null when there's no inventory.
  Future<AdItem?> rewardedHouse({String lang = 'en'}) async {
    final b = await _fetchBundle('interstitial', lang);
    final ad = b.ads.isNotEmpty ? b.ads.first : (b.own.isNotEmpty ? b.own.first : null);
    return ad == null ? null : _record('interstitial', ad, b.nonce);
  }

  /// REWARDED RESERVE: on ~1-in-N user-initiated reward moments, return a cross-promo to
  /// show *instead of* the paid reward (the user still earns the reward, from us). Returns
  /// null on non-reserve moments, when reserve is off, or there's no cross-promo inventory
  /// -> fall through to the paid reward. Skips the cooldown (user-initiated).
  Future<AdItem?> rewardedReserve({String lang = 'en'}) async {
    if (!_config.reserveShare || _config.reserveOneIn < 1) {
      _rewardedEligible++;
      return null;
    }
    final shouldReserve = _rewardedEligible % _config.reserveOneIn == 0; // fires on the 1st, then every Nth
    _rewardedEligible++;
    if (!shouldReserve) return null;
    final b = await _fetchBundle('interstitial', lang);
    return b.ads.isEmpty ? null : _record('interstitial', b.ads.first, b.nonce); // cross-promo only
  }

  /// RESERVE: call on every eligible moment *before* the paid ad. Returns a cross-promo
  /// to show instead of paid on ~1-in-N moments (when `reserveShare` is on), else `null`
  /// -> proceed to your paid ad as normal.
  Future<AdItem?> reserveAd(String slot, {String lang = 'en'}) async {
    if (!_config.reserveShare || _config.reserveOneIn < 1) {
      _eligible++;
      return null;
    }
    // Decide BEFORE incrementing so position 0 reserves: fires on the 1st eligible moment
    // of a session, then every Nth (1, 1+N, 1+2N, ...). Short sessions still get one.
    final shouldReserve = _eligible % _config.reserveOneIn == 0;
    _eligible++;
    if (!shouldReserve) return null;
    final b = await _fetchBundle(slot, lang);
    if (b.ads.isEmpty) return null; // reserve serves the GK pool only
    _lastGkAt = _now(); // a GK ad shown -> start the GK cooldown
    return _record(slot, b.ads.first, b.nonce);
  }

  /// FALLBACK: call when the paid network returned no fill. Cross-promo first, then your
  /// own studio's other apps as a last resort. `null` -> show nothing. Gated by cooldown;
  /// an empty (but successful) response is a real no-fill and returns null.
  Future<AdItem?> fallbackAd(String slot, {String lang = 'en'}) async {
    final b = await _fetchBundle(slot, lang);
    // Pool 1 (GK): served if fallbackFill is on + GK cooldown elapsed.
    if (_config.fallbackFill && b.ads.isNotEmpty && _gkCooldownOk()) {
      _lastGkAt = _now();
      return _record(slot, b.ads.first, b.nonce);
    }
    // Pool 2 (studio own): last resort when GK is empty/cooled. The server only returns
    // `own` when this app opted in (fill_own_ads); gated by its separate own-ads cooldown.
    if (b.own.isNotEmpty && _ownCooldownOk()) {
      _lastOwnAt = _now();
      return _record(slot, b.own.first, b.nonce);
    }
    return null;
  }

  /// Deprecated alias for [fallbackAd].
  Future<AdItem?> nextAd(String slot, {String lang = 'en'}) => fallbackAd(slot, lang: lang);

  // --- Banner engine (used by GoldenKrillBanner). Banners are time-based and
  // fill/cadence-gated: no interstitial cooldown. ---

  /// Whether a given banner rotation unit is a reserve turn (ours instead of paid).
  /// Time-based: ours on units 0, N, 2N, ... = 1 unit in every N.
  bool bannerReserveTurn(int unit) =>
      _config.reserveShare && _config.reserveOneIn >= 1 && unit % _config.reserveOneIn == 0;

  /// Fetch a house creative for a banner (cross-promo, then own-studio). Records the
  /// impression (no cooldown stamp - banners are fill-gated). Returns null if no inventory.
  Future<AdItem?> bannerHouse(String slot, {String lang = 'en'}) async {
    final b = await _fetchBundle(slot, lang);
    final ad = b.ads.isNotEmpty ? b.ads.first : (b.own.isNotEmpty ? b.own.first : null);
    if (ad == null) return null;
    _beacon([
      {'creative': ad.id, 'slot': slot, 'kind': 'view'},
    ], b.nonce);
    gkLog(() => 'banner[$slot]: house id=${ad.id}');
    return ad;
  }

  /// One-call orchestration covering all three moments using config. You provide:
  /// - [paid]: attempt your paid ad; return `true` if it showed, `false` on no-fill.
  /// - [present]: display a Golden Krill creative (render `ad.image`, open `ad.store`
  ///   on tap). The impression is already recorded.
  ///
  /// Flow: reserve (1-in-N, if enabled) -> your paid ad -> fallback + own-studio.
  /// Returns `true` if anything was shown, else `false`. Never throws.
  Future<bool> show(
    String slot, {
    required Future<bool> Function() paid,
    required void Function(AdItem ad) present,
    String lang = 'en',
  }) async {
    if (!_configLoaded) {
      _config = await _client.loadConfig();
      _configLoaded = true;
    }
    final reserved = await reserveAd(slot, lang: lang);
    if (reserved != null) {
      gkLog(() => 'show[$slot]: reserve id=${reserved.id}');
      present(reserved);
      return true;
    }
    bool paidShown = false;
    try {
      paidShown = await paid();
    } catch (_) {/* a paid failure just means we try to fill */}
    if (paidShown) {
      gkLog(() => 'show[$slot]: paid');
      return true;
    }
    final filler = await fallbackAd(slot, lang: lang);
    if (filler != null) {
      gkLog(() => 'show[$slot]: fallback id=${filler.id}');
      present(filler);
      return true;
    }
    gkLog(() => 'show[$slot]: nothing');
    return false;
  }

  /// New session (e.g. app resumed after long background): reset the reserve cadence +
  /// cooldown. The offline failover copy is kept (it's a cross-session safety net).
  void resetSession() {
    _eligible = 0;
    _rewardedEligible = 0;
    _lastGkAt = null;
    _lastOwnAt = null;
  }

  void dispose() {
    rewardedAvailable.dispose();
    _client.dispose();
  }
}

class _Failover {
  _Failover(this.bundle, this.at);
  final AdBundle bundle;
  final DateTime at;
}
