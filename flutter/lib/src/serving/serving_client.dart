import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog_codec.dart';
import '../config/serving_endpoint.dart';
import '../gk_debug.dart';
import 'serve_models.dart';

/// The SDK's single I/O boundary against the serving API. Fetches GK1 blobs,
/// decodes + parses them, and keeps a **last-good** on-device cache so a failed
/// fetch or bad blob never leaves the app empty:
///
///   fresh fetch  ->  else last-good cache  ->  else compiled defaults / empty
///
/// Never throws to the caller; never blocks the app's paid path. Beacons are
/// fire-and-forget. All collaborators injectable for tests.
class GoldenKrillClient {
  GoldenKrillClient({
    required this.package,
    http.Client? client,
    String base = kServingBase,
    Duration configTtl = kConfigTtl,
    DateTime Function()? now,
    String? store,
    this.testMode = false,
  })  : _client = client ?? http.Client(),
        _base = base,
        _configTtl = configTtl,
        _now = now ?? DateTime.now,
        _store = store ?? _deviceStore();

  final String package;
  final http.Client _client;
  final String _base;
  final String _store; // platform store id sent with /ads so clicks resolve the right app store
  // Test mode: ask the server for a TEST AD (always-fill) and tell it to count nothing. NOT
  // a security boundary (a client can lie); it only keeps honest dev traffic out of metrics.
  final bool testMode;

  // The device's app store. iOS -> App Store; everything else -> Play (Android default).
  // defaultTargetPlatform is web-safe (unlike dart:io Platform).
  static String _deviceStore() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'appstore' : 'play';
  final Duration _configTtl;
  final DateTime Function() _now;

  String get _configKey => 'gk_cfg_v1_$package';
  String get _configAtKey => 'gk_cfg_at_v1_$package';

  /// Per-app serving config. Fresh -> last-good -> compiled defaults. Never throws.
  Future<ServeConfig> loadConfig() async {
    final map = await _loadJson(
      url: gkConfigUrl(package, base: _base, test: testMode),
      blobKey: _configKey,
      atKey: _configAtKey,
      ttl: _configTtl,
    );
    return map == null ? ServeConfig.defaults : ServeConfig.fromJson(map);
  }

  /// Per-display ad fetch for a slot. The server returns one random cross-promo +
  /// one random own-studio ad and randomizes per call, so we fetch fresh every time
  /// (no on-device TTL cache here). Returns the bundle plus `ok`:
  ///
  ///   ok == true   -> fetch succeeded (the bundle may still be empty = no inventory)
  ///   ok == false  -> fetch FAILED (network / HTTP / bad blob); caller may failover
  ///
  /// Never throws. "Empty is empty": a successful empty bundle is a real no-fill, not
  /// a failure, so the caller shows nothing and proceeds to its paid ad.
  Future<({AdBundle bundle, bool ok})> fetchAds({String slot = 'banner', String lang = 'en'}) async {
    final body = await _fetch(gkAdsUrl(package, slot: slot, lang: lang, store: _store, base: _base, test: testMode));
    if (body == null) return (bundle: AdBundle.empty, ok: false);
    final m = _decode(body);
    if (m == null) return (bundle: AdBundle.empty, ok: false);
    return (bundle: AdBundle.fromJson(m), ok: true);
  }

  /// Report display beacons (impressions). Fire-and-forget; failure ignored. Sends an
  /// anonymous, weekly-rotating device token so the server can approximate distinct-device
  /// reach per app WITHOUT any advertising id or stable identity (see trust-and-metrics).
  Future<void> postEvents(List<Map<String, dynamic>> events, {String attestation = '', String nonce = ''}) async {
    if (events.isEmpty) return;
    try {
      await _client.post(
        gkEventsUrl(base: _base),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'host': package, 'attestation': attestation, 'nonce': nonce,
          'device': await _deviceToken(), 'events': events,
          if (testMode) 'test': true, // test beacons are accepted but counted nowhere
        }),
      );
    } catch (_) {/* beacons never affect the app */}
  }

  /// Anonymous reach token: a random value kept in this app's own sandbox and **rotated
  /// weekly**, so it can never track a person or cross-link apps. Not an advertising id.
  Future<String> _deviceToken() async {
    const ttl = Duration(days: 7);
    final prefs = await SharedPreferences.getInstance();
    final tok = prefs.getString('gk_did_v1');
    final at = prefs.getInt('gk_did_at_v1');
    if (tok != null && at != null) {
      final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(at));
      if (!age.isNegative && age < ttl) return tok;
    }
    final r = Random.secure();
    final fresh = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await prefs.setString('gk_did_v1', fresh);
    await prefs.setInt('gk_did_at_v1', _now().millisecondsSinceEpoch);
    return fresh;
  }

  /// Shared fetch+decode+cache with the fresh/last-good/null fallback tiers.
  Future<Map<String, dynamic>?> _loadJson({
    required Uri url,
    required String blobKey,
    required String atKey,
    required Duration ttl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(blobKey);
    final at = prefs.getInt(atKey);

    if (cached != null && at != null) {
      final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(at));
      if (!age.isNegative && age < ttl) {
        final m = _decode(cached);
        if (m != null) return m;
      }
    }
    final body = await _fetch(url);
    if (body != null) {
      final m = _decode(body);
      if (m != null) {
        await prefs.setString(blobKey, body);
        await prefs.setInt(atKey, _now().millisecondsSinceEpoch);
        return m;
      }
    }
    if (cached != null) {
      final m = _decode(cached); // last-good, even if stale
      if (m != null) return m;
    }
    return null;
  }

  Map<String, dynamic>? _decode(String blob) {
    try {
      final json = jsonDecode(CatalogCodec.decode(blob)); // GK1 or raw JSON
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetch(Uri url) async {
    try {
      final resp = await _client.get(url);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) return resp.body;
      gkLog(() => 'fetch ${url.path}: HTTP ${resp.statusCode} (using cache/defaults)');
      return null;
    } catch (e) {
      gkLog(() => 'fetch ${url.path}: $e (using cache/defaults)');
      return null;
    }
  }

  void dispose() => _client.close();
}
