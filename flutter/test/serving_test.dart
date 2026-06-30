import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String gk1(Object json) => CatalogCodec.encode(jsonEncode(json));

  group('wire models', () {
    test('AdBundle parses tuples and tolerates junk rows', () {
      final b = AdBundle.fromJson({
        'a': [
          [1, 'img', 'store'],
          [2, 'i2', null],
          'bad',
          [3],
        ],
        'o': [
          [9, 'o', 's'],
        ],
      });
      expect(b.ads.map((e) => e.id), [1, 2]); // 'bad' + too-short [3] dropped
      expect(b.ads.first.store, 'store');
      expect(b.own.single.id, 9);
    });

    test('ServeConfig fills defaults for missing fields', () {
      final c = ServeConfig.fromJson({'reserve_one_in': 7});
      expect(c.reserveOneIn, 7);
      expect(c.reserveShare, isTrue); // default
      expect(c.maxPerSession, ServeConfig.defaults.maxPerSession);
    });

    test('ServeConfig parses banner_sdk_refresh (default false)', () {
      expect(ServeConfig.fromJson({}).bannerSdkRefresh, isFalse);
      expect(ServeConfig.fromJson({'banner_sdk_refresh': true}).bannerSdkRefresh, isTrue);
    });

    test('bannerRotation: configured value, else jittered 55-65s', () {
      expect(ServeConfig.fromJson({'banner_rotation_sec': 30}).bannerRotation().inSeconds, 30);
      final s = ServeConfig.fromJson({}).bannerRotation(Random(1)).inSeconds;
      expect(s, inInclusiveRange(55, 65));
    });
  });

  group('client', () {
    test('loadConfig decodes GK1', () async {
      final mock = MockClient((_) async =>
          http.Response(gk1({'reserve_one_in': 5, 'max_per_session': 2}), 200));
      final cfg = await GoldenKrillClient(package: 'com.x', client: mock).loadConfig();
      expect(cfg.reserveOneIn, 5);
      expect(cfg.maxPerSession, 2);
    });

    test('fetchAds signals ok=false + empty bundle on failure', () async {
      final mock = MockClient((_) async => http.Response('err', 500));
      final r = await GoldenKrillClient(package: 'com.x', client: mock).fetchAds();
      expect(r.ok, isFalse);
      expect(r.bundle.ads, isEmpty);
    });

    test('fetchAds signals ok=true on a successful (even empty) response', () async {
      final mock = MockClient((_) async => http.Response(gk1({'a': [], 'o': []}), 200));
      final r = await GoldenKrillClient(package: 'com.x', client: mock).fetchAds();
      expect(r.ok, isTrue); // empty is empty, not a failure
      expect(r.bundle.ads, isEmpty);
    });
  });

  group('façade', () {
    test('fallback serves, gated only by the cooldown (server picks; no client rotation)', () async {
      var t = DateTime(2030);
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'house_cooldown_sec': 100, 'reserve_share': false}), 200);
        }
        return http.Response(gk1({'a': [[1, 'i1', 's1']], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), now: () => t);
      await ads.ensureReady(slot: 'banner');
      expect((await ads.fallbackAd('banner'))!.id, 1); // serves
      expect(await ads.fallbackAd('banner'), isNull); // within cooldown -> blocked
      t = t.add(const Duration(seconds: 101));
      expect((await ads.fallbackAd('banner'))!.id, 1); // cooldown passed -> serves again
    });

    test('fallback: own pool fills when GK is on cooldown (separate clocks)', () async {
      var t = DateTime(2030);
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'house_cooldown_sec': 100, 'own_ads_cooldown_min': 1,
              'reserve_share': false, 'fallback_fill': true}), 200);
        }
        return http.Response(gk1({'a': [[1, 'i', 's']], 'o': [[9, 'o', 's']]}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), now: () => t);
      await ads.ensureReady(slot: 'interstitial');
      expect((await ads.fallbackAd('interstitial'))!.id, 1);  // GK pool first
      t = t.add(const Duration(seconds: 1));
      expect((await ads.fallbackAd('interstitial'))!.id, 9);  // GK cooled -> own pool fills
      t = t.add(const Duration(seconds: 100));
      expect((await ads.fallbackAd('interstitial'))!.id, 1);  // GK cooldown elapsed -> GK again
    });

    test('failover: reuse last good on fetch failure; empty success stays empty', () async {
      var t = DateTime(2030);
      var fail = false, empty = false;
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': false, 'house_cooldown_sec': 0}), 200);
        }
        if (fail) return http.Response('err', 500);
        if (empty) return http.Response(gk1({'a': [], 'o': []}), 200);
        return http.Response(gk1({'a': [[1, 'i', 's']], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), now: () => t);
      await ads.ensureReady(slot: 'banner'); // warms failover with id 1
      fail = true;
      expect((await ads.fallbackAd('banner'))!.id, 1); // fetch failed -> fresh failover reused
      t = t.add(const Duration(hours: 2)); // failover now stale (> kFailoverTtl)
      expect(await ads.fallbackAd('banner'), isNull); // stale failover -> nothing
      fail = false;
      empty = true;
      expect(await ads.fallbackAd('banner'), isNull); // empty success -> empty, no stale reuse
    });

    test('show: paid shown -> no house presented', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': false, 'house_cooldown_sec': 0}), 200);
        }
        return http.Response(gk1({'a': [[1, 'i', 's']], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(
          client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await ads.ensureReady(slot: 'banner');
      AdItem? presented;
      final r = await ads.show('banner', paid: () async => true, present: (a) => presented = a);
      expect(r.shown, isTrue);
      expect(r.ad, isNull); // paid took it; SDK never sees the creative
      expect(presented, isNull); // paid took it; no house shown
    });

    test('show: paid no-fill -> house presented', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': false, 'house_cooldown_sec': 0}), 200);
        }
        return http.Response(gk1({'a': [[1, 'i', 's']], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(
          client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await ads.ensureReady(slot: 'banner');
      AdItem? presented;
      final r = await ads.show('banner', paid: () async => false, present: (a) => presented = a);
      expect(r.shown, isTrue);
      expect(r.ad!.id, 1); // fallback creative surfaced on the result
      expect(presented!.id, 1);
    });

    test('reserveAd fires on the 1st eligible moment then every Nth', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(
              gk1({'reserve_share': true, 'reserve_one_in': 4, 'house_cooldown_sec': 0, 'max_per_session': 10}),
              200);
        }
        return http.Response(gk1({'a': [[1, 'i', 's']], 'o': []}), 200);
      });
      final gk = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await gk.ensureReady(slot: 'banner');
      expect(await gk.reserveAd('banner'), isNotNull); // 1st
      expect(await gk.reserveAd('banner'), isNull); // 2nd
      expect(await gk.reserveAd('banner'), isNull); // 3rd
      expect(await gk.reserveAd('banner'), isNull); // 4th
      expect(await gk.reserveAd('banner'), isNotNull); // 5th
    });

    test('bannerReserveTurn fires 1 unit in N (time-based)', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': true, 'reserve_one_in': 4}), 200);
        }
        return http.Response(gk1({'a': [], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await ads.ensureReady(slot: 'banner');
      expect(ads.bannerReserveTurn(0), isTrue); // 1st unit = ours
      expect(ads.bannerReserveTurn(1), isFalse);
      expect(ads.bannerReserveTurn(3), isFalse);
      expect(ads.bannerReserveTurn(4), isTrue); // every Nth
    });

    test('show auto-loads the bundle if ensureReady was not called', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': false, 'house_cooldown_sec': 0}), 200);
        }
        return http.Response(gk1({'a': [[1, 'i', 's']], 'o': []}), 200);
      });
      final gk = GoldenKrillAds(
          client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      AdItem? presented;
      // no ensureReady() call - show() must self-heal
      final r = await gk.show('banner', paid: () async => false, present: (a) => presented = a);
      expect(r.shown, isTrue);
      expect(presented!.id, 1);
    });

    test('nextAd falls back to own-studio when cross-promo empty', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'house_cooldown_sec': 0}), 200);
        }
        return http.Response(
            gk1({
              'a': [],
              'o': [
                [7, 'own', 'store'],
              ],
            }),
            200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await ads.ensureReady(slot: 'interstitial');
      expect((await ads.nextAd('interstitial'))!.id, 7);
    });
  });

  group('widgets', () {
    test('rewardedDuration: configured value, else 10s default', () {
      const set = ServeConfig(
          reserveShare: true, reserveOneIn: 4, fallbackFill: true, fillOwnAds: false,
          houseCooldownSec: 240, maxPerSession: 3, ownAdsCooldownMin: 5, rewardedSeconds: 30);
      expect(set.rewardedDuration(), const Duration(seconds: 30));
      expect(ServeConfig.defaults.rewardedDuration(), const Duration(seconds: 10)); // 0 -> default
    });

    test('rewardedReserve: fires 1-in-N (count-based, cross-promo only)', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': true, 'reserve_one_in': 4, 'max_per_session': 99}), 200);
        }
        return http.Response(
            gk1({'a': [[1, 'https://x/a.png', 'https://play.google.com/store/apps/details?id=a']], 'o': []}),
            200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await ads.ensureReady(slot: 'interstitial');
      expect(await ads.rewardedReserve(), isNotNull); // moment 0 -> ours
      expect(await ads.rewardedReserve(), isNull);    // 1 -> paid
      expect(await ads.rewardedReserve(), isNull);    // 2 -> paid
      expect(await ads.rewardedReserve(), isNull);    // 3 -> paid
      expect(await ads.rewardedReserve(), isNotNull); // 4 -> ours again
    });

    test('rewardedHouse: user-initiated -> always serves (no cap/cooldown); availability tracks inventory', () async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) return http.Response(gk1({}), 200);
        return http.Response(
            gk1({'a': [
              [1, 'https://x/a.png', 'https://play.google.com/store/apps/details?id=a'],
              [2, 'https://x/b.png', 'https://play.google.com/store/apps/details?id=b'],
            ], 'o': []}),
            200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      expect(ads.rewardedAvailable.value, isFalse);
      await ads.ensureReady(slot: 'interstitial');
      expect(ads.rewardedReady, isTrue);
      expect(ads.rewardedAvailable.value, isTrue);
      expect(await ads.rewardedHouse(), isNotNull); // always serves
      expect(await ads.rewardedHouse(), isNotNull); // again - no cap
      expect(await ads.rewardedHouse(), isNotNull); // and again
      expect(ads.rewardedAvailable.value, isTrue); // inventory unchanged -> still available
    });

    testWidgets('rewarded page: mounts and blocks dismissal until the reward is earned', (tester) async {
      // Network images don't load in widget tests (precache throws), so we just verify
      // the page mounts and offers no early exit before completion; the countdown length
      // and reserve/house/cap logic are exercised by the façade tests above.
      const ad = AdItem(id: 1, image: 'https://x/a.png', store: 'https://play.google.com/store/apps/details?id=a');
      await tester.pumpWidget(const MaterialApp(
          home: GoldenKrillRewardedPage(ad, duration: Duration(milliseconds: 300))));
      await tester.pump();
      expect(find.byType(GoldenKrillRewardedPage), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing); // not earned yet -> no dismissal
      tester.takeException(); // swallow the expected network-image precache error in tests
      await tester.pumpWidget(const SizedBox()); // dispose -> cancels any timer
    });

    testWidgets('banner: a throwing paidBuilder is treated as no-fill (house, no crash)', (tester) async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': false}), 200); // never a reserve turn
        }
        return http.Response(
            gk1({'a': [[7, 'https://x/i.png', 'https://play.google.com/store/apps/details?id=z']], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await tester.pumpWidget(MaterialApp(
          home: GoldenKrillBanner(
        ads: ads,
        unit: const Duration(hours: 1),
        paidBuilder: () async => throw Exception('boom'),
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);       // throw was swallowed
      expect(find.byType(Image), findsOneWidget);   // fell back to a house creative
      await tester.pumpWidget(const SizedBox());     // dispose -> cancels the timer
    });

    testWidgets('banner collapses when no inventory', (tester) async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) return http.Response(gk1({}), 200);
        return http.Response(gk1({'a': [], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await tester.pumpWidget(MaterialApp(
          home: GoldenKrillBanner(ads: ads, unit: const Duration(hours: 1))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20)); // let load + first tick run
      expect(find.byType(Image), findsNothing); // collapsed to SizedBox.shrink
      await tester.pumpWidget(const SizedBox()); // dispose -> cancels the rotation timer
    });

    testWidgets('banner Model B (default): paid for (N-1) units, then house 1 unit, then paid', (tester) async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(gk1({'reserve_share': true, 'reserve_one_in': 3}), 200);
        }
        return http.Response(
            gk1({'a': [[7, 'https://x/i.png', 'https://play.google.com/store/apps/details?id=z']], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await tester.pumpWidget(MaterialApp(
          home: GoldenKrillBanner(
        ads: ads,
        unit: const Duration(milliseconds: 100),
        paidBuilder: () async => const SizedBox(key: Key('paid')),
      )));
      await tester.pump();                                    // start + ensureReady
      await tester.pump(const Duration(milliseconds: 10));    // _enterPaid completes
      expect(find.byKey(const Key('paid')), findsOneWidget);  // paid phase
      expect(find.byType(Image), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));   // (N-1)*unit -> house phase fires
      await tester.pump();                                    // flush async house load
      expect(find.byType(Image), findsOneWidget);             // house creative, uninterrupted
      expect(find.byKey(const Key('paid')), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));   // 1 unit -> back to paid
      await tester.pump();
      expect(find.byKey(const Key('paid')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());              // dispose
    });

    testWidgets('banner Model A (sdkControlsRefresh): renders paid via the tick loop', (tester) async {
      final mock = MockClient((req) async {
        if (req.url.path.contains('/config/')) return http.Response(gk1({'reserve_share': false}), 200);
        return http.Response(gk1({'a': [], 'o': []}), 200);
      });
      final ads = GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
      await tester.pumpWidget(MaterialApp(
          home: GoldenKrillBanner(
        ads: ads,
        sdkControlsRefresh: true,
        unit: const Duration(hours: 1),
        paidBuilder: () async => const SizedBox(key: Key('paid')),
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byKey(const Key('paid')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
