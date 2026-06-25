import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Step 2: host-forwarded attestation PASSTHROUGH. The SDK forwards an opaque token the
/// HOST minted (it never mints one itself), bound to the per-serve nonce, and never lets
/// a missing/failing provider block or drop a beacon. Inert until the server verifies it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String gk1(Object json) => CatalogCodec.encode(jsonEncode(json));

  // A serving mock that captures the /events beacon body. `onEvents` fires per beacon.
  MockClient mock(void Function(Map<String, dynamic>) onEvents) => MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'house_cooldown_sec': 0, 'reserve_share': false}), 200);
        }
        if (req.url.path.contains('/events')) {
          onEvents(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('', 200);
        }
        return http.Response(gk1({'a': [[1, 'i', 's']], 'o': <dynamic>[], 'n': 'NONCE1'}), 200);
      });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('forwards the host token + per-serve nonce on the beacon', () async {
    Map<String, dynamic>? body;
    String? seenNonce;
    final ads = GoldenKrillAds(
      client: GoldenKrillClient(package: 'com.x', client: mock((b) => body = b)),
      attestationProvider: (nonce) async {
        seenNonce = nonce;
        return 'TOKEN-$nonce';
      },
    );
    await ads.ensureReady(slot: 'banner');
    await ads.fallbackAd('banner'); // records an impression -> beacon (fire-and-forget)
    await settle();
    expect(seenNonce, 'NONCE1'); // the serve nonce was handed to the provider
    expect(body?['attestation'], 'TOKEN-NONCE1'); // the returned token reached the beacon
    expect(body?['nonce'], 'NONCE1');
  });

  test('no provider -> beacon carries an empty attestation (today behavior)', () async {
    Map<String, dynamic>? body;
    final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock((b) => body = b)));
    await ads.ensureReady(slot: 'banner');
    await ads.fallbackAd('banner');
    await settle();
    expect(body?['attestation'], '');
  });

  test('throwing provider still fires the beacon, without attestation', () async {
    Map<String, dynamic>? body;
    var fired = false;
    final ads = GoldenKrillAds(
      client: GoldenKrillClient(package: 'com.x', client: mock((b) {
        fired = true;
        body = b;
      })),
      attestationProvider: (nonce) async => throw Exception('no integrity available'),
    );
    await ads.ensureReady(slot: 'banner');
    await ads.fallbackAd('banner');
    await settle();
    expect(fired, isTrue); // never dropped
    expect(body?['attestation'], ''); // failure -> forwarded nothing
  });
}
