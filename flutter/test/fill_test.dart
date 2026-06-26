import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';

/// Covers the creative-fill fix: hex parsing, the pure contain-gap maths (letterbox vs
/// pillarbox), the additive wire parsing of fill/edge-colours, the contain-vs-blur
/// selection by flag, and safe-area placement of the chrome.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gkParseColor', () {
    test('parses #RRGGBB, #RGB, #AARRGGBB', () {
      expect(gkParseColor('#FFFFFF'), const Color(0xFFFFFFFF));
      expect(gkParseColor('fff'), const Color(0xFFFFFFFF));
      expect(gkParseColor('#80FF0000'), const Color(0x80FF0000));
      expect(gkParseColor('#123456'), const Color(0xFF123456));
    });
    test('returns null for missing/garbage', () {
      expect(gkParseColor(null), isNull);
      expect(gkParseColor('nope'), isNull);
      expect(gkParseColor('#12'), isNull);
    });
  });

  group('gkContainGaps', () {
    test('letterboxes a wide creative in a tall slot (top/bottom gaps)', () {
      final g = gkContainGaps(const Size(100, 200), const Size(100, 100));
      expect(g.top, 50);
      expect(g.bottom, 50);
      expect(g.left, 0);
      expect(g.right, 0);
    });
    test('pillarboxes a square creative in a wide slot (left/right gaps)', () {
      final g = gkContainGaps(const Size(200, 100), const Size(100, 100));
      expect(g.left, 50);
      expect(g.right, 50);
      expect(g.top, 0);
      expect(g.bottom, 0);
    });
    test('no gaps when aspect matches', () {
      final g = gkContainGaps(const Size(200, 100), const Size(20, 10));
      expect(g, const GkEdgeGaps(0, 0, 0, 0));
    });
    test('degenerate sizes give zero gaps (no divide-by-zero)', () {
      expect(gkContainGaps(const Size(100, 100), const Size(0, 0)), const GkEdgeGaps(0, 0, 0, 0));
      expect(gkContainGaps(Size.zero, const Size(10, 10)), const GkEdgeGaps(0, 0, 0, 0));
    });
    test('GkEdgeGaps value equality + hashCode', () {
      expect(const GkEdgeGaps(1, 2, 3, 4), const GkEdgeGaps(1, 2, 3, 4));
      expect(const GkEdgeGaps(1, 2, 3, 4).hashCode, const GkEdgeGaps(1, 2, 3, 4).hashCode);
      expect(const GkEdgeGaps(1, 2, 3, 4) == const GkEdgeGaps(9, 2, 3, 4), isFalse);
    });
  });

  group('gkBannerBackground (banner white-hairline fix)', () {
    test('uses the top sampled edge colour when present', () {
      const ad = AdItem(id: 1, image: 'i', store: 's',
          edgeColors: ['#123456', '#000000', '#000000', '#000000']);
      expect(gkBannerBackground(ad), const Color(0xFF123456));
    });
    test('falls back to the neutral when no edge colour is known', () {
      const ad = AdItem(id: 1, image: 'i', store: 's');
      expect(gkBannerBackground(ad), const Color(0xFF000000));
      expect(gkBannerBackground(ad, neutral: const Color(0xFF222222)), const Color(0xFF222222));
    });
    test('falls back to the neutral when the edge colour is garbage', () {
      const ad = AdItem(id: 1, image: 'i', store: 's', edgeColors: ['nope', 'x', 'y', 'z']);
      expect(gkBannerBackground(ad), const Color(0xFF000000));
    });
  });

  group('AdItem additive wire parsing', () {
    test('defaults: contain, no edge colours, not photographic', () {
      final a = AdItem.fromList([1, 'img', 'store'])!;
      expect(a.fill, 'contain');
      expect(a.edgeColors, isEmpty);
      expect(a.isPhotographic, isFalse);
    });
    test('reads the fill hint + 4 edge colours from trailing slots', () {
      final a = AdItem.fromList([1, 'img', 'store', 'blur', '#fff,#eee,#ddd,#ccc'])!;
      expect(a.fill, 'blur');
      expect(a.isPhotographic, isTrue);
      expect(a.edgeColors, ['#fff', '#eee', '#ddd', '#ccc']);
    });
    test('edge colours are all-or-none (needs exactly four)', () {
      expect(AdItem.fromList([1, 'img', 'store', 'contain', '#fff,#eee'])!.edgeColors, isEmpty);
    });
    test('tolerates extra trailing slots beyond the colours (forward-compatible)', () {
      final a = AdItem.fromList([1, 'img', 'store', 'contain', '#a0a0a0,#b,#c,#d', 'future'])!;
      expect(a.id, 1);
      expect(a.edgeColors.length, 4);
    });
  });

  group('gkEdgeFill band layout', () {
    const edges = [Color(0xFFFFFFFF), Color(0xFFEEEEEE), Color(0xFFDDDDDD), Color(0xFFCCCCCC)];
    const black = Color(0xFF000000);

    testWidgets('neutral solid until creative dimensions are known', (tester) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(width: 100, height: 200, child: gkEdgeFill(const Size(100, 200), null, null, black))));
      expect(find.byType(ColoredBox), findsOneWidget);
    });

    testWidgets('letterbox paints base + top + bottom bands', (tester) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
              width: 100,
              height: 200,
              child: gkEdgeFill(const Size(100, 200), const Size(100, 100), edges, black))));
      expect(find.byType(ColoredBox), findsNWidgets(3)); // base + top + bottom (left/right zero)
    });

    testWidgets('pillarbox paints base + left + right bands', (tester) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
              width: 200,
              height: 100,
              child: gkEdgeFill(const Size(200, 100), const Size(100, 100), edges, black))));
      expect(find.byType(ColoredBox), findsNWidgets(3)); // base + left + right (top/bottom zero)
    });
  });

  group('GoldenKrillCreativeFill selection', () {
    testWidgets('photographic creative uses the blur fill', (tester) async {
      const ad = AdItem(id: 1, image: 'https://i', fill: 'blur');
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GoldenKrillCreativeFill(ad))));
      await tester.pump();
      expect(find.byType(ImageFiltered), findsOneWidget); // blur path
    });
    testWidgets('contain creative uses a solid colour fill (no blur)', (tester) async {
      const ad = AdItem(id: 1, image: 'https://i');
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GoldenKrillCreativeFill(ad))));
      await tester.pump();
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(ColoredBox), findsWidgets); // neutral/edge fill
    });
  });

  testWidgets('interstitial chrome sits in a SafeArea over the fill', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: GoldenKrillInterstitialPage(AdItem(id: 1, image: 'https://i'),
            closeAfter: Duration(milliseconds: 50), showBadge: true, badgeUrl: 'https://golden-krill.com/about')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80)); // let the close-after timer fire
    expect(find.byType(GoldenKrillCreativeFill), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets); // chrome wrapped in a SafeArea
  });
}
