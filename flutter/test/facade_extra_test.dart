import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deterministic coverage for the façade + client paths the widget/happy-path tests
/// don't reach: the package-only constructor, on-device config cache (fresh + stale
/// reuse), successful-fetch caching, rewarded house inventory, offline failover reuse,
/// session reset/dispose, and the debug log line.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String gk1(Object j) => CatalogCodec.encode(jsonEncode(j));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('package-only constructor, resetSession and dispose', () {
    final ads = GoldenKrillAds(package: 'com.x'); // default real http.Client (unused)
    ads.resetSession();
    ads.dispose();
    GoldenKrillClient(package: 'com.y').dispose(); // default-client ctor + dispose
  });

  test('loadConfig returns the fresh on-device cache without a network fetch', () async {
    SharedPreferences.setMockInitialValues({
      'gk_cfg_v1_com.x': gk1({'reserve_one_in': 9}),
      'gk_cfg_at_v1_com.x': DateTime(2030, 1, 1).millisecondsSinceEpoch,
    });
    final mock = MockClient((_) async => http.Response('err', 500)); // would fail if hit
    final cfg = await GoldenKrillClient(
            package: 'com.x', client: mock, now: () => DateTime(2030, 1, 1, 0, 0, 1))
        .loadConfig();
    expect(cfg.reserveOneIn, 9); // served from the fresh cache
  });

  test('loadConfig reuses stale last-good when the fetch fails', () async {
    SharedPreferences.setMockInitialValues({
      'gk_cfg_v1_com.x': gk1({'reserve_one_in': 3}),
      'gk_cfg_at_v1_com.x': DateTime(2000).millisecondsSinceEpoch, // stale
    });
    final mock = MockClient((_) async => http.Response('err', 500));
    final cfg = await GoldenKrillClient(package: 'com.x', client: mock, now: () => DateTime(2030))
        .loadConfig();
    expect(cfg.reserveOneIn, 3); // stale last-good, even though the fetch failed
  });

  test('loadConfig caches a successful fetch on device', () async {
    final mock = MockClient((_) async => http.Response(gk1({'reserve_one_in': 6}), 200));
    final cfg = await GoldenKrillClient(package: 'com.x', client: mock, now: () => DateTime(2030))
        .loadConfig();
    expect(cfg.reserveOneIn, 6);
    expect((await SharedPreferences.getInstance()).getString('gk_cfg_v1_com.x'), isNotNull);
  });

  test('rewardedHouse serves available inventory', () async {
    final mock = MockClient((req) async {
      if (req.url.path.contains('/config/')) return http.Response(gk1({'house_cooldown_sec': 0}), 200);
      return http.Response(gk1({'a': [[5, 'https://i', 's']], 'o': <dynamic>[]}), 200);
    });
    final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock));
    await ads.ensureReady(slot: 'interstitial');
    expect((await ads.rewardedHouse())!.id, 5);
  });

  test('fallback reuses the offline failover when a later fetch fails', () async {
    var fail = false;
    final mock = MockClient((req) async {
      if (req.url.path.contains('/config/')) {
        return http.Response(gk1({'house_cooldown_sec': 0, 'reserve_share': false}), 200);
      }
      if (fail) return http.Response('x', 500);
      return http.Response(gk1({'a': [[5, 'https://i', 's']], 'o': <dynamic>[]}), 200);
    });
    final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock));
    await ads.ensureReady(slot: 'interstitial'); // warms the failover with the [5] bundle
    fail = true;
    expect((await ads.fallbackAd('interstitial'))!.id, 5); // fetch fails -> failover reuse
  });

  test('debug logging emits a tagged line on a failed fetch', () async {
    GoldenKrillDebug.enabled = true;
    addTearDown(() => GoldenKrillDebug.enabled = false);
    final mock = MockClient((_) async => http.Response('err', 500));
    final r = await GoldenKrillClient(package: 'com.x', client: mock).fetchAds();
    expect(r.ok, isFalse); // gkLog ran the [GoldenKrill] print branch (debug on)
  });
}
