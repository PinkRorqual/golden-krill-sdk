// Golden Krill Flutter demo: four screens (banner / mrec / interstitial / rewarded),
// the Flutter twin of the React Native demo. House-ads-only - the "paid network" is
// simulated, so a paid no-fill (or a ~1-in-N reserve unit) falls back to a Golden Krill
// house ad. Serves as the test app id below.
import 'package:flutter/material.dart';
import 'package:goldenkrill/goldenkrill.dart';

void main() {
  GoldenKrillDebug.enabled = true; // [GoldenKrill] logs in the console
  runApp(const DemoApp());
}

// The serving id (what the SDK sends to /ads + /config). A separate test app in the portal.
const String kDemoPackage = 'com.goldenkrilltest.fluttershowcase';

// Serving host override. Defaults to production; point the demo at staging or a local
// mock so reviewers reliably see inventory instead of a silent empty collapse:
//   tool/flutter run --dart-define=GK_BASE=https://staging.golden-krill.com
const String kDemoBase = String.fromEnvironment('GK_BASE', defaultValue: kServingBase);

// The SDK facade the screens use. Mutable so a widget test can swap in a
// MockClient-backed instance before pumping, so tests hit no network.
GoldenKrillAds gk = GoldenKrillAds(
  client: GoldenKrillClient(package: kDemoPackage, base: kDemoBase),
);

// When true, the simulated paid network returns no fill, so the SDK fills with a house ad.
bool demoNoFill = false;

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Golden Krill demo',
        theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFFBFAF6), useMaterial3: true),
        debugShowCheckedModeBanner: false,
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;
  bool _noFill = false;

  @override
  void initState() {
    super.initState();
    gk.ensureReady(slot: 'banner');
    gk.ensureReady(slot: 'mrec');
    gk.ensureReady(slot: 'interstitial'); // also serves rewarded
  }

  @override
  Widget build(BuildContext context) {
    final screens = [const BannerScreen(), const MrecScreen(), const InterstitialScreen(), const RewardedScreen()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Golden Krill demo', style: TextStyle(color: Color(0xFF12363A), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFBFAF6),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _noFill ? const Color(0xFFB85C00) : const Color(0xFF1E88E5)),
              onPressed: () => setState(() {
                demoNoFill = !demoNoFill;
                _noFill = demoNoFill;
              }),
              child: Text(_noFill ? 'Paid: NO-FILL (house fallback)' : 'Paid: fill'),
            ),
          ),
          Expanded(child: screens[_tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.crop_16_9), label: 'Banner'),
          NavigationDestination(icon: Icon(Icons.crop_square), label: 'MREC'),
          NavigationDestination(icon: Icon(Icons.fullscreen), label: 'Interstitial'),
          NavigationDestination(icon: Icon(Icons.card_giftcard), label: 'Rewarded'),
        ],
      ),
    );
  }
}

// Simulated paid banner: a real app returns its AdMob banner (or null on no-fill).
Future<Widget?> _fakePaidBanner() async {
  if (demoNoFill) return null; // paid no-fill -> SDK house fallback
  return Container(
    color: const Color(0xFF1B2B2B),
    alignment: Alignment.center,
    child: const Text('Paid network ad (simulated)', style: TextStyle(color: Color(0xFF9FB3B3), fontWeight: FontWeight.bold)),
  );
}

class BannerScreen extends StatefulWidget {
  const BannerScreen({super.key});
  @override
  State<BannerScreen> createState() => _BannerScreenState();
}

class _BannerScreenState extends State<BannerScreen> {
  int _rot = 0;
  @override
  Widget build(BuildContext context) => _Rotatable(
        text: 'Banner rotates paid (simulated) and house ads. ~1 in N units is a house ad '
            '(reserve, from config); the gold "GK" mark shows only on those.',
        onRotate: () => setState(() => _rot++),
        child: GoldenKrillBanner(key: ValueKey(_rot), ads: gk, slot: 'banner', height: 100, showBadge: true, paidBuilder: _fakePaidBanner),
      );
}

class MrecScreen extends StatefulWidget {
  const MrecScreen({super.key});
  @override
  State<MrecScreen> createState() => _MrecScreenState();
}

class _MrecScreenState extends State<MrecScreen> {
  int _rot = 0;
  @override
  Widget build(BuildContext context) => _Rotatable(
        text: 'MREC (600x500). Same paid/house rotation; being bigger, its house unit shows a '
            'tappable "Powered by Golden Krill" pill (-> /about).',
        onRotate: () => setState(() => _rot++),
        child: SizedBox(width: 300, child: GoldenKrillBanner(key: ValueKey(_rot), ads: gk, slot: 'mrec', showBadge: true, paidBuilder: _fakePaidBanner)),
      );
}

class _Rotatable extends StatelessWidget {
  const _Rotatable({required this.text, required this.onRotate, required this.child});
  final String text;
  final VoidCallback onRotate;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF444444))),
            const SizedBox(height: 16),
            child,
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRotate, child: const Text('Rotate')),
          ],
        ),
      );
}

// Stand-in for the host app's paid full-screen ad (the SDK never shows paid; the app does).
// Auto-dismisses after 1s so you can fast-forward and watch the 1-in-N reserve cadence.
Future<bool> _simulatedPaidFullScreen(BuildContext context) async {
  if (demoNoFill) return false; // no-fill -> SDK house fallback
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      Future.delayed(const Duration(seconds: 1), () => Navigator.of(ctx).maybePop());
      return const Dialog.fullscreen(
        backgroundColor: Color(0xFF1B2B2B),
        child: Center(child: Text('Paid network ad (simulated, 1s)', style: TextStyle(color: Color(0xFF9FB3B3), fontWeight: FontWeight.bold, fontSize: 16))),
      );
    },
  );
  return true; // paid "showed"
}

class InterstitialScreen extends StatelessWidget {
  const InterstitialScreen({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('~1 in N taps shows a house interstitial (reserve, from config); the rest are '
                  'your paid network (simulated). Cooldown may gate the fallback.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => gk.showInterstitial(context, paid: () => _simulatedPaidFullScreen(context)),
                child: const Text('Show interstitial'),
              ),
            ],
          ),
        ),
      );
}

class RewardedScreen extends StatefulWidget {
  const RewardedScreen({super.key});
  @override
  State<RewardedScreen> createState() => _RewardedScreenState();
}

class _RewardedScreenState extends State<RewardedScreen> {
  String _msg = '';
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('~1 in N is a house rewarded (reserve, from config - countdown, then reward); '
                  'the rest are your paid network (simulated, 1s).', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  setState(() => _msg = '');
                  final earned = await gk.showRewarded(context, paid: () => _simulatedPaidFullScreen(context));
                  if (mounted) setState(() => _msg = earned ? 'Reward earned!' : 'No reward.');
                },
                child: const Text('Show rewarded'),
              ),
              if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_msg, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF12363A)))),
            ],
          ),
        ),
      );
}
