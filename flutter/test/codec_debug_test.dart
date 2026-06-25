import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the codec error/passthrough paths and the opt-in debug logger - the
/// branches the happy-path serving + conformance tests do not reach.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'pink-rorqual//golden-krill//v1';
  List<int> obf(List<int> bytes) {
    final k = utf8.encode(key);
    return [for (var i = 0; i < bytes.length; i++) bytes[i] ^ k[i % k.length]];
  }

  group('CatalogCodec error + passthrough paths', () {
    test('round-trips an arbitrary string', () {
      const s = '{"hello":"wörld"}';
      expect(CatalogCodec.decode(CatalogCodec.encode(s)), s);
    });

    test('raw JSON object/array passes through unchanged (dev/test fallback)', () {
      expect(CatalogCodec.decode('{"a":1}'), '{"a":1}');
      expect(CatalogCodec.decode('  [1,2,3]'), '  [1,2,3]');
    });

    test('unrecognised format throws CatalogCodecException', () {
      expect(() => CatalogCodec.decode('not a blob'),
          throwsA(isA<CatalogCodecException>()));
    });

    test('corrupt GK1 base64 throws', () {
      expect(() => CatalogCodec.decode('GK1.!!!not-base64!!!'),
          throwsA(isA<CatalogCodecException>()));
    });

    test('GK1 payload that is not valid UTF-8 throws', () {
      final blob = 'GK1.${base64Url.encode(obf([0xC3, 0x28]))}'; // 0xC3 0x28 = invalid UTF-8
      expect(() => CatalogCodec.decode(blob), throwsA(isA<CatalogCodecException>()));
    });

    test('exception toString carries the message', () {
      const e = CatalogCodecException('boom');
      expect(e.toString(), contains('boom'));
    });
  });

  group('GoldenKrillDebug / gkLog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults off', () => expect(GoldenKrillDebug.enabled, isFalse));

    test('enabling it exercises the log path on a failed fetch (no throw)', () async {
      GoldenKrillDebug.enabled = true;
      final printed = <String>[];
      await runZonedGuarded(() async {
        final mock = MockClient((_) async => http.Response('nope', 500));
        // A 500 makes the client log "[GoldenKrill] fetch ...". We only assert it
        // runs cleanly and produces a tagged line.
        final r = await GoldenKrillClient(package: 'com.x', client: mock).fetchAds();
        expect(r.ok, isFalse);
      }, (e, s) {}, zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ));
      GoldenKrillDebug.enabled = false;
      expect(printed.any((l) => l.contains('[GoldenKrill]')), isTrue);
    });
  });
}
