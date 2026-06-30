import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget-layer coverage for the renderers + the show* extensions: the GK badge/pill,
/// the full-screen interstitial + rewarded pages, and the facade convenience calls.
/// All network is mocked; creative images fail to load in tests and degrade gracefully.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String gk1(Object j) => CatalogCodec.encode(jsonEncode(j));
  const ad = AdItem(id: 1, image: 'https://cdn.example/i.webp', store: 'https://store.example/app');

  GoldenKrillAds adsServing({Map<String, Object?> cfg = const {}, bool empty = false}) {
    final mock = MockClient((req) async {
      if (req.url.path.contains('/config/')) {
        return http.Response(gk1({'house_cooldown_sec': 0, 'ad_badge_chance': 0, ...cfg}), 200);
      }
      if (empty) return http.Response(gk1({'a': <dynamic>[], 'o': <dynamic>[]}), 200);
      return http.Response(gk1({'a': [[1, 'https://cdn.example/i.webp', 'https://store.example/app']], 'o': <dynamic>[]}), 200);
    });
    // Deterministic online probe: these widget tests exercise serving, which now gates on
    // connectivity. Inject a fake (the default talks to the real platform channel, which
    // never resolves in a widget test) so the gate is online + instant.
    return GoldenKrillAds(client: GoldenKrillClient(package: 'com.x', client: mock), connectivity: () async => true);
  }

  testWidgets('GoldenKrillCreative builds its image renderer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GoldenKrillCreative(ad))));
    expect(find.byType(GoldenKrillCreative), findsOneWidget);
  });

  testWidgets('banner creative paints an opaque backing (no white-hairline bleed)', (tester) async {
    const bg = Color(0xFF123456);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GoldenKrillCreative(ad, background: bg))));
    final backed = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where((c) => c.color == bg);
    expect(backed, isNotEmpty); // the contain-fit image now has an opaque backing
  });

  testWidgets('no backing when background is null (full-screen path unaffected)', (tester) async {
    const bg = Color(0xFF123456);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GoldenKrillCreative(ad))));
    final backed = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where((c) => c.color == bg);
    expect(backed, isEmpty);
  });

  testWidgets('banner draws the compact GK mark on a house unit', (tester) async {
    final ads = adsServing(cfg: {'reserve_share': true, 'reserve_one_in': 1});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GoldenKrillBanner(ads: ads, slot: 'banner', showBadge: true))));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('GK'), findsOneWidget);
  });

  testWidgets('mrec draws the tappable "Powered by Golden Krill" pill', (tester) async {
    final ads = adsServing(cfg: {'reserve_share': true, 'reserve_one_in': 1});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GoldenKrillBanner(ads: ads, slot: 'mrec', showBadge: true))));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Powered by Golden Krill'), findsOneWidget);
  });

  testWidgets('banner with reserveSpace=false collapses on no inventory', (tester) async {
    final ads = adsServing(empty: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GoldenKrillBanner(ads: ads, slot: 'banner', reserveSpace: false, paidBuilder: null))));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(GoldenKrillCreative), findsNothing);
  });

  testWidgets('interstitial page reveals the close button after the delay + shows the badge', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: GoldenKrillInterstitialPage(ad,
            closeAfter: Duration(milliseconds: 100), showBadge: true, badgeUrl: 'https://golden-krill.com/about')));
    await tester.pump();
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Powered by Golden Krill'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('rewarded page mounts and blocks dismissal before completion', (tester) async {
    // Network images do not precache in widget tests, so we verify the page mounts and
    // offers no early exit; the countdown completion path is exercised by the façade tests.
    await tester.pumpWidget(const MaterialApp(
        home: GoldenKrillRewardedPage(ad, duration: Duration(milliseconds: 300))));
    await tester.pump();
    expect(find.byType(GoldenKrillRewardedPage), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing); // not earned -> no dismissal
    tester.takeException(); // swallow the expected network-image precache error
    await tester.pumpWidget(const SizedBox()); // dispose -> cancels the timer
  });

  testWidgets('showRewarded returns true when the paid network grants the reward', (tester) async {
    final ads = adsServing(cfg: {'reserve_share': false}); // no reserve -> paid-first
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    final earned = await ads.showRewarded(ctx, paid: () async => true);
    expect(earned, isTrue); // paid granted -> no house page shown
    expect(find.byType(GoldenKrillRewardedPage), findsNothing);
  });

  testWidgets('showRewarded returns false on paid no-fill with no house inventory', (tester) async {
    final ads = adsServing(cfg: {'reserve_share': false}, empty: true);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    final earned = await ads.showRewarded(ctx, paid: () async => false);
    expect(earned, isFalse);
  });

  testWidgets('showInterstitial presents a house page on paid no-fill', (tester) async {
    final ads = adsServing();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    final future = ads.showInterstitial(ctx, paid: () async => false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(GoldenKrillInterstitialPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // close becomes available
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(await future, isTrue); // something was shown
  });
}
