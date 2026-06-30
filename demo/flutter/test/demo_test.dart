import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:goldenkrilldemo/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demo widget tests. A MockClient is injected via the (mutable) global [gk], so no
/// network is hit: /config returns canned knobs, /ads returns one house ad for the
/// banner/mrec slots and an empty bundle for the interstitial slot (so the
/// interstitial/rewarded flows resolve cleanly without dialogs or timers).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String gk1(Object j) => CatalogCodec.encode(jsonEncode(j));

  MockClient buildMock() => MockClient((req) async {
        if (req.url.path.contains('/config/')) {
          return http.Response(
              gk1({'house_cooldown_sec': 0, 'reserve_share': true, 'reserve_one_in': 1}), 200);
        }
        final slot = req.url.queryParameters['slot'];
        if (slot == 'interstitial') {
          return http.Response(gk1({'a': <dynamic>[], 'o': <dynamic>[]}), 200);
        }
        return http.Response(
            gk1({'a': [[1, 'https://x/img.webp', 'play']], 'o': <dynamic>[]}), 200);
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    demoNoFill = false;
    // Online + instant connectivity probe (the default talks to the real platform channel,
    // which never resolves in a widget test). Serving now gates on connectivity.
    gk = GoldenKrillAds(
        client: GoldenKrillClient(package: kDemoPackage, client: buildMock()),
        connectivity: () async => true);
  });

  testWidgets('launches on the Banner tab with the paid toggle + 4 destinations', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    expect(find.text('Paid: fill'), findsOneWidget);
    expect(find.text('Banner'), findsWidgets);
    expect(find.text('MREC'), findsWidgets);
    expect(find.text('Interstitial'), findsWidgets);
    expect(find.text('Rewarded'), findsWidgets);
    expect(find.byType(GoldenKrillBanner), findsOneWidget);
    expect(find.text('Rotate'), findsOneWidget);
  });

  testWidgets('fill/no-fill toggle flips its label', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    expect(find.text('Paid: fill'), findsOneWidget);
    await tester.tap(find.text('Paid: fill'));
    await tester.pump();
    expect(find.text('Paid: NO-FILL (house fallback)'), findsOneWidget);
  });

  testWidgets('navigates across all four tabs', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    await tester.tap(find.text('MREC'));
    await tester.pump();
    expect(find.textContaining('MREC'), findsWidgets);
    await tester.tap(find.text('Interstitial'));
    await tester.pump();
    expect(find.text('Show interstitial'), findsOneWidget);
    await tester.tap(find.text('Rewarded'));
    await tester.pump();
    expect(find.text('Show rewarded'), findsOneWidget);
  });

  testWidgets('interstitial flow runs without a network hit (no-fill, empty house)', (tester) async {
    demoNoFill = true;
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    await tester.tap(find.text('Interstitial'));
    await tester.pump();
    await tester.tap(find.text('Show interstitial'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Show interstitial'), findsOneWidget); // returned cleanly, no crash
  });

  testWidgets('rewarded flow shows a result (no-fill, empty house -> No reward)', (tester) async {
    demoNoFill = true;
    await tester.pumpWidget(const DemoApp());
    await tester.pump();
    await tester.tap(find.text('Rewarded'));
    await tester.pump();
    await tester.tap(find.text('Show rewarded'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No reward.'), findsOneWidget);
  });
}
