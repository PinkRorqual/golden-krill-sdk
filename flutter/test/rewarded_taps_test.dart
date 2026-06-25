import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldenkrill/goldenkrill.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records launchUrl calls so the tappable full-screen badge can be asserted without a
/// real platform. (The creative image itself is zero-size in tests - its network image
/// errors to SizedBox.shrink - so its tap target is not exercisable here.)
class _FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final List<String> launched = [];
  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
  // Other members (linkDelegate, legacy launch, ...) are unused by the tap path.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping the full-screen badge opens the info url', (tester) async {
    final fake = _FakeLauncher();
    UrlLauncherPlatform.instance = fake;
    await tester.pumpWidget(const MaterialApp(
        home: GoldenKrillInterstitialPage(AdItem(id: 1, image: 'https://i'),
            closeAfter: Duration(milliseconds: 20), showBadge: true, badgeUrl: 'https://golden-krill.com/about')));
    await tester.pump(const Duration(milliseconds: 40)); // also fires the close-after timer
    await tester.tap(find.text('Powered by Golden Krill'));
    await tester.pump();
    expect(fake.launched, contains('https://golden-krill.com/about'));
  });
}
