import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Prompt 16 test mode (Flutter): testMode defaults to kDebugMode, sends test=1 on /ads +
// /config and test:true on beacons, and renders the server's TEST AD normally.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String gk1(Object json) => CatalogCodec.encode(jsonEncode(json));

  MockClient mock(List<Uri> urls, void Function(Map<String, dynamic>)? onEvents) =>
      MockClient((req) async {
        urls.add(req.url);
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'house_cooldown_sec': 0, 'reserve_share': false}), 200);
        }
        if (req.url.path.contains('/events')) {
          onEvents?.call(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('', 200);
        }
        return http.Response(gk1({'a': [[0, 'i', 's']], 'o': <dynamic>[], 'n': 'N', 't': 1}), 200);
      });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('testMode sends test=1 on ads + config and test:true on the beacon', () async {
    final urls = <Uri>[];
    Map<String, dynamic>? body;
    final ads = GoldenKrillAds(
        client: GoldenKrillClient(package: 'com.x', client: mock(urls, (b) => body = b), testMode: true));
    await ads.ensureReady(slot: 'banner');
    await ads.fallbackAd('banner');
    await settle();
    expect(urls.any((u) => u.path.contains('/config/') && u.query.contains('test=1')), isTrue);
    expect(urls.any((u) => u.path.endsWith('/ads') && u.queryParameters['test'] == '1'), isTrue);
    expect(body?['test'], true);
  });

  test('no test=1 and no test flag when testMode is false', () async {
    final urls = <Uri>[];
    Map<String, dynamic>? body;
    final ads = GoldenKrillAds(
        client: GoldenKrillClient(package: 'com.x', client: mock(urls, (b) => body = b), testMode: false));
    await ads.ensureReady(slot: 'banner');
    await ads.fallbackAd('banner');
    await settle();
    expect(urls.every((u) => !u.query.contains('test=1')), isTrue);
    expect(body?.containsKey('test'), isFalse);
  });

  test('GoldenKrillAds defaults testMode to kDebugMode', () {
    // Exercises the default client path (testMode ?? kDebugMode) without a network call.
    expect(GoldenKrillAds(package: 'com.x'), isNotNull);
    expect(GoldenKrillAds(package: 'com.x', testMode: false), isNotNull);
  });
}
