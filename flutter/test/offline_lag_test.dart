import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for the three connected ad-serving bugs:
///   Bug A - offline gate: no ad available / served while the device is offline, and
///           never a stale cached creative whose beacons can't succeed.
///   Bug B - fire-and-forget beacon queue: impressions never block the UI (close stays
///           instant on a hung POST); duplicates collapse; unsent records persist + retry.
///   Bug C - single in-flight gate: a second show() while one is loading / on screen is
///           rejected with a typed AdAlreadyShowing, so two ads never stack.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String gk1(Object j) => CatalogCodec.encode(jsonEncode(j));

  // A façade wired to a fixed config + a single cross-promo creative (id 1), with an
  // injectable connectivity probe and (optionally) an injected event queue.
  GoldenKrillAds ads({
    required Future<bool> Function() online,
    GkEventQueue? events,
    Map<String, Object?> cfg = const {},
    bool empty = false,
  }) {
    final mock = MockClient((req) async {
      if (req.url.path.contains('/config/')) {
        return http.Response(
            gk1({'reserve_share': false, 'house_cooldown_sec': 0, 'ad_badge_chance': 0, ...cfg}), 200);
      }
      if (empty) return http.Response(gk1({'a': <dynamic>[], 'o': <dynamic>[]}), 200);
      return http.Response(gk1({'a': [[1, 'https://x/i.png', 'https://store/app']], 'o': <dynamic>[]}), 200);
    });
    return GoldenKrillAds(
      client: GoldenKrillClient(package: 'com.x', client: mock),
      connectivity: online,
      events: events,
    );
  }

  group('Bug A - connectivity gate', () {
    test('connectivity mapping: offline only when every result is none', () {
      expect(gkIsOnline([ConnectivityResult.none]), isFalse);
      expect(gkIsOnline(const <ConnectivityResult>[]), isFalse);
      expect(gkIsOnline([ConnectivityResult.wifi]), isTrue);
      expect(gkIsOnline([ConnectivityResult.none, ConnectivityResult.mobile]), isTrue);
    });

    test('default probe fails open when the platform channel is unavailable', () async {
      expect(await gkConnectivityPlus(), isTrue); // MissingPluginException -> assume online
    });

    test('isAdAvailable: true online, false offline', () async {
      expect(await ads(online: () async => true).isAdAvailable(), isTrue);
      expect(await ads(online: () async => false).isAdAvailable(), isFalse);
    });

    test('offline NEVER serves the stale failover creative', () async {
      var online = true;
      final gk = ads(online: () async => online);
      await gk.ensureReady(slot: 'banner'); // online: warms the failover with id 1
      expect((await gk.fallbackAd('banner'))!.id, 1); // online -> serves
      online = false;
      expect(await gk.fallbackAd('banner'), isNull); // offline -> no stale creative served
      online = true;
      expect((await gk.fallbackAd('banner'))!.id, 1); // back online -> serves again
    });

    test('show() returns a typed offline failure and presents nothing', () async {
      final gk = ads(online: () async => false);
      var paidCalled = false, presented = false;
      final r = await gk.show('interstitial',
          paid: () async {
            paidCalled = true;
            return false;
          },
          present: (_) => presented = true);
      expect(r.outcome, ShowOutcome.offline);
      expect(r.shown, isFalse);
      expect(paidCalled, isFalse); // gated before the paid attempt
      expect(presented, isFalse);
      expect(gk.isAdShowing, isFalse); // gate not left stuck
    });
  });

  group('Bug B - fire-and-forget beacon queue', () {
    test('failed POST is kept and persists, then a fresh instance retries + drains', () async {
      var ok = false;
      Future<bool> post(List<Map<String, dynamic>> e, {String attestation = '', String nonce = ''}) async => ok;
      final q1 = GkEventQueue(post: post);
      await q1.add('e1', [{'creative': 1, 'slot': 'banner', 'kind': 'view'}], nonce: 'n1');
      await Future<void>.delayed(const Duration(milliseconds: 20)); // let the background flush run (it fails)
      expect(await q1.pendingCount(), 1); // POST failed -> retained for retry

      ok = true;
      final q2 = GkEventQueue(post: post); // a new run reads the persisted record
      await q2.flush();
      expect(await q2.pendingCount(), 0); // retried successfully -> drained
    });

    test('duplicate event id collapses (no double-count)', () async {
      Future<bool> post(List<Map<String, dynamic>> e, {String attestation = '', String nonce = ''}) async =>
          false; // keep pending so we can count records
      final q = GkEventQueue(post: post);
      await q.add('same', [{'creative': 1, 'slot': 's', 'kind': 'view'}], nonce: 'n');
      await q.add('same', [{'creative': 1, 'slot': 's', 'kind': 'view'}], nonce: 'n'); // collapses
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await q.pendingCount(), 1); // one record despite two enqueues
    });

    test('a hung POST never blocks the enqueuing caller', () async {
      final stuck = Completer<bool>(); // never completes
      final q = GkEventQueue(post: (e, {String attestation = '', String nonce = ''}) => stuck.future);
      await q
          .add('e1', [{'creative': 1, 'slot': 's', 'kind': 'view'}], nonce: 'n')
          .timeout(const Duration(seconds: 1)); // returns despite the hung POST
      expect(await q.pendingCount(), 1); // still pending (POST in flight)
    });

    test('show() is not blocked by a hung impression POST', () async {
      final stuck = Completer<bool>();
      final q = GkEventQueue(post: (e, {String attestation = '', String nonce = ''}) => stuck.future);
      final gk = ads(online: () async => true, events: q);
      await gk.ensureReady(slot: 'banner');
      final r = await gk
          .show('banner', paid: () async => false, present: (_) {})
          .timeout(const Duration(seconds: 1));
      expect(r.shown, isTrue); // shown immediately even though the beacon POST hangs
      expect(r.ad!.id, 1);
    });

    testWidgets('interstitial close fires onClosed and pops synchronously', (tester) async {
      var closed = false;
      final pops = _PopRecorder();
      const ad = AdItem(id: 1, image: 'https://x/i.png', store: 'https://store/app');
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [pops],
        home: Scaffold(
          body: Builder(
            builder: (c) => ElevatedButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => GoldenKrillInterstitialPage(ad,
                      closeAfter: const Duration(milliseconds: 50), onClosed: () => closed = true))),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump(); // start the push
      await tester.pump(const Duration(milliseconds: 400)); // finish the route transition
      await tester.pump(const Duration(milliseconds: 60)); // closeAfter elapses -> close shows
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(); // onClosed runs; maybePop's willPop microtask resolves
      await tester.pump(); // pop() is processed
      expect(closed, isTrue); // host hook fired synchronously on tap
      expect(pops.count, 1); // the route popped without awaiting any network
      await tester.pump(const Duration(milliseconds: 400)); // let the reverse transition settle
      tester.takeException(); // swallow any network-image error from the fill
    });
  });

  group('Bug C - single in-flight gate', () {
    test('a second show() while one is on screen is rejected as AlreadyShowing', () async {
      final gk = ads(online: () async => true);
      await gk.ensureReady(slot: 'interstitial');
      final reached = Completer<void>(); // signals the first call has presented (gate held)
      final hold = Completer<void>(); // keeps the first ad "on screen"
      final first = gk.show('interstitial', paid: () async => false, present: (ad) {
        reached.complete();
        return hold.future;
      });
      await reached.future; // deterministic: first is parked in present, gate is held
      expect(gk.isAdShowing, isTrue);

      final second = await gk.show('interstitial', paid: () async => false, present: (_) {});
      expect(second.outcome, ShowOutcome.alreadyShowing);
      expect(second.shown, isFalse);

      hold.complete(); // dismiss the first ad
      expect((await first).shown, isTrue);
      expect(gk.isAdShowing, isFalse); // gate released

      // A fresh call after dismissal proceeds normally.
      final third = await gk.show('interstitial', paid: () async => false, present: (_) {});
      expect(third.shown, isTrue);
    });

    test('isAdAvailable is false while an ad is showing, even online', () async {
      final gk = ads(online: () async => true);
      await gk.ensureReady(slot: 'interstitial');
      final reached = Completer<void>();
      final hold = Completer<void>();
      final first = gk.show('interstitial', paid: () async => false, present: (ad) {
        reached.complete();
        return hold.future;
      });
      await reached.future;
      expect(await gk.isAdAvailable(), isFalse); // online but busy
      hold.complete();
      await first;
      expect(await gk.isAdAvailable(), isTrue);
    });
  });
}

/// Counts route pops so a test can assert a close button actually dismissed its route,
/// independent of the reverse-transition timing.
class _PopRecorder extends NavigatorObserver {
  int count = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}
