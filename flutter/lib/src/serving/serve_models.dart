/// Wire models for the API serving responses (`/ads`, `/config`), wire v1.
///
/// Parsing is defensive + forward-compatible: unknown fields are ignored, missing
/// fields fall back to safe defaults, and extra positional ad slots (future
/// `weight`, `package`, ...) are tolerated. Never throws on a well-formed-but-newer
/// payload, so an old SDK keeps working when the server adds fields.
library;

import 'dart:math';

/// One ad in the rotation. Wire form is a bare positional tuple
/// `[id, image, store, fill, "T,B,L,R"]` (see WIRE.md); only `[id, image]` are
/// required and every slot after `store` is optional + additive (older SDKs ignore
/// them, so the wire stays non-breaking). `id` is required for beacon attribution.
class AdItem {
  const AdItem({
    required this.id,
    required this.image,
    this.store,
    this.fill = 'contain',
    this.edgeColors = const [],
  });

  final int id;
  final String image;
  final String? store;

  /// How to present a full-screen creative whose aspect does not match the device.
  /// `contain` (default) = letterbox/pillarbox with a solid edge-colour fill (no
  /// stretch). `cover`/`blur` = photographic/full-bleed, so the creative covers and
  /// the gap behind is a blurred enlargement. Unknown -> treated as contain.
  final String fill;

  /// Server-sampled edge colours `[top, bottom, left, right]` (hex), used to fill the
  /// contain-fit gaps. Empty when the server has not sampled the creative yet; the SDK
  /// then falls back to a neutral solid. Pixel sampling happens once at creative
  /// generation (server side), never on device.
  final List<String> edgeColors;

  /// True when the creative wants full-bleed cover + blur fill instead of contain.
  bool get isPhotographic => fill == 'cover' || fill == 'blur';

  /// Parse `[id, image, store, fill, "T,B,L,R"]`. Tolerates extra trailing slots so
  /// the wire can grow without breaking already-shipped SDKs.
  static AdItem? fromList(dynamic row) {
    if (row is! List || row.length < 2) return null;
    final id = row[0];
    final image = row[1];
    if (id is! int || image is! String) return null;
    final store = row.length > 2 && row[2] is String ? row[2] as String : null;
    final fill =
        row.length > 3 && row[3] is String && (row[3] as String).isNotEmpty ? row[3] as String : 'contain';
    final colors = row.length > 4 && row[4] is String ? _parseColors(row[4] as String) : const <String>[];
    return AdItem(id: id, image: image, store: store, fill: fill, edgeColors: colors);
  }

  // "T,B,L,R" -> 4 hex strings, or [] unless exactly four are present (all-or-none).
  static List<String> _parseColors(String s) {
    final parts = [for (final p in s.split(',')) p.trim()]..removeWhere((p) => p.isEmpty);
    return parts.length == 4 ? parts : const [];
  }
}

/// The two-tier `/ads` response: `a` = cross-promo (reserve + fallback), `o` =
/// own-studio last resort.
class AdBundle {
  const AdBundle({required this.ads, required this.own, this.nonce = ''});

  final List<AdItem> ads;
  final List<AdItem> own;

  /// Per-serve, single-use nonce from the server, echoed on the beacon so the server can
  /// reject replays. Opaque to the SDK. Empty when the server didn't send one.
  final String nonce;

  static const AdBundle empty = AdBundle(ads: [], own: []);

  factory AdBundle.fromJson(Map<String, dynamic> json) => AdBundle(
        ads: _items(json['a']),
        own: _items(json['o']),
        nonce: json['n'] is String ? json['n'] as String : '',
      );

  static List<AdItem> _items(dynamic x) {
    if (x is! List) return const [];
    return [
      for (final row in x)
        if (AdItem.fromList(row) case final item?) item,
    ];
  }
}

/// Per-app serving config from `/config/<package>`. Missing fields fall back to
/// the house-friendly defaults (reserve 1-of-4, fallback on, no own-ads).
class ServeConfig {
  const ServeConfig({
    required this.reserveShare,
    required this.reserveOneIn,
    required this.fallbackFill,
    required this.fillOwnAds,
    required this.houseCooldownSec,
    required this.maxPerSession,
    required this.ownAdsCooldownMin,
    this.bannerRotationSec = 0,
    this.rewardedSeconds = 0,
    this.adBadgeChance = 0,
    this.badgeUrl = '',
    this.bannerSdkRefresh = false,
  });

  final bool reserveShare;
  final int reserveOneIn;
  final bool fallbackFill;
  final bool fillOwnAds;
  final int houseCooldownSec;
  final int maxPerSession;
  final int ownAdsCooldownMin;

  /// Banner rotation/window unit, in seconds. 0 = unset -> the SDK jitters (~55-65s,
  /// avoids every device rotating in lockstep). Use [bannerRotation] to resolve it.
  final int bannerRotationSec;

  /// How long the rewarded countdown runs, in seconds. 0 = unset -> the SDK default
  /// (10s). Operator-set; the countdown starts after the creative loads. Use
  /// [rewardedDuration] to resolve it.
  final int rewardedSeconds;

  /// Probability (0..1) of drawing a small disclosure badge over a house ad ("Ad" on
  /// full-screen, a "GK" mark on banners). 0 = never, 1 = always; rolled per display.
  final double adBadgeChance;

  /// Where a tap on the full-screen badge goes. '' -> the SDK default (kBadgeInfoUrl).
  final String badgeUrl;

  /// Host's banner refresh strategy (portal Config). false = Regular (default): SDK shows
  /// one house unit then hands back to paid for N-1 units. true = Advanced: SDK drives the
  /// refresh (host must disable paid auto-refresh). The widget's explicit `sdkControlsRefresh`
  /// param overrides this; otherwise the banner defaults from here.
  final bool bannerSdkRefresh;

  /// Compiled fallback when no config has ever been fetched (offline first run).
  static const ServeConfig defaults = ServeConfig(
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
  );

  /// Effective banner rotation interval: the configured value if set (>0), else a
  /// jittered ~55-65s default (55 + 0..10). Call once per banner so the jitter is stable.
  Duration bannerRotation([Random? rng]) => bannerRotationSec > 0
      ? Duration(seconds: bannerRotationSec)
      : Duration(seconds: 55 + (rng ?? Random()).nextInt(11));

  /// Effective rewarded countdown: the configured value if set (>0), else the 10s default.
  Duration rewardedDuration() => Duration(seconds: rewardedSeconds > 0 ? rewardedSeconds : 10);

  /// Roll whether to draw the disclosure badge on this display (probability adBadgeChance).
  bool rollAdBadge([Random? rng]) =>
      adBadgeChance > 0 && (rng ?? Random()).nextDouble() < adBadgeChance;

  factory ServeConfig.fromJson(Map<String, dynamic> json) => ServeConfig(
        reserveShare: _b(json['reserve_share'], defaults.reserveShare),
        reserveOneIn: _i(json['reserve_one_in'], defaults.reserveOneIn),
        fallbackFill: _b(json['fallback_fill'], defaults.fallbackFill),
        fillOwnAds: _b(json['fill_own_ads'], defaults.fillOwnAds),
        houseCooldownSec: _i(json['house_cooldown_sec'], defaults.houseCooldownSec),
        maxPerSession: _i(json['max_per_session'], defaults.maxPerSession),
        ownAdsCooldownMin: _i(json['own_ads_cooldown_min'], defaults.ownAdsCooldownMin),
        bannerRotationSec: _i(json['banner_rotation_sec'], 0),
        rewardedSeconds: _i(json['rewarded_seconds'], 0),
        adBadgeChance: _d(json['ad_badge_chance'], 0),
        badgeUrl: json['badge_url'] is String ? json['badge_url'] as String : '',
        bannerSdkRefresh: _b(json['banner_sdk_refresh'], false),
      );

  static bool _b(dynamic v, bool d) => v is bool ? v : d;
  static int _i(dynamic v, int d) => v is int ? v : (v is num ? v.toInt() : d);
  static double _d(dynamic v, double d) => v is num ? v.toDouble() : d;
}
