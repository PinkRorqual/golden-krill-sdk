import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gk_debug.dart';
import 'goldenkrill_ads.dart';
import 'serve_models.dart';

/// Parse a `#RGB` / `#RRGGBB` / `#AARRGGBB` hex string to a [Color], or null if it is
/// missing/unparseable. Used for the server-supplied creative edge-fill colours.
Color? gkParseColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// The gap thicknesses (logical px) left by `BoxFit.contain` of a [creative] inside a
/// [slot]. For a given creative+slot only one axis has gaps (letterbox = top/bottom,
/// pillarbox = left/right); the other pair is 0. Pure + side-effect free, so the fill
/// maths is unit-testable without decoding any image.
@immutable
class GkEdgeGaps {
  const GkEdgeGaps(this.top, this.bottom, this.left, this.right);
  final double top, bottom, left, right;

  @override
  bool operator ==(Object other) =>
      other is GkEdgeGaps && other.top == top && other.bottom == bottom && other.left == left && other.right == right;
  @override
  int get hashCode => Object.hash(top, bottom, left, right);
}

GkEdgeGaps gkContainGaps(Size slot, Size creative) {
  if (creative.width <= 0 || creative.height <= 0 || slot.width <= 0 || slot.height <= 0) {
    return const GkEdgeGaps(0, 0, 0, 0);
  }
  final scale = math.min(slot.width / creative.width, slot.height / creative.height);
  final gv = math.max(0.0, (slot.height - creative.height * scale) / 2);
  final gh = math.max(0.0, (slot.width - creative.width * scale) / 2);
  return GkEdgeGaps(gv, gv, gh, gh);
}

/// The contain-fit background for [slot]: a neutral base with the four gap bands painted
/// in the sampled edge colours `[top,bottom,left,right]` (the off-axis pair is zero-size,
/// so only the relevant two show). Until the [creative] dimensions are known it is a
/// single neutral/edge solid. Extracted so the band layout is unit-testable with explicit
/// sizes, with no image decode.
Widget gkEdgeFill(Size slot, Size? creative, List<Color>? edges, Color neutral) {
  if (creative == null) return ColoredBox(color: edges != null ? edges[0] : neutral);
  final g = gkContainGaps(slot, creative);
  final t = edges?[0] ?? neutral, b = edges?[1] ?? neutral, l = edges?[2] ?? neutral, r = edges?[3] ?? neutral;
  return Stack(children: [
    Positioned.fill(child: ColoredBox(color: neutral)),
    if (g.top > 0) Positioned(top: 0, left: 0, right: 0, height: g.top, child: ColoredBox(color: t)),
    if (g.bottom > 0) Positioned(bottom: 0, left: 0, right: 0, height: g.bottom, child: ColoredBox(color: b)),
    if (g.left > 0) Positioned(top: 0, bottom: 0, left: 0, width: g.left, child: ColoredBox(color: l)),
    if (g.right > 0) Positioned(top: 0, bottom: 0, right: 0, width: g.right, child: ColoredBox(color: r)),
  ]);
}

/// Full-bleed background + creative for the interstitial/rewarded pages.
///
/// Default (contain): the creative is letter/pillar-boxed (never stretched) and the
/// gaps are filled with the server's sampled edge colours `[top,bottom,left,right]`
/// (a neutral solid until the colours/dimensions are known). Photographic/full-bleed
/// creatives ([AdItem.isPhotographic]) instead cover the screen over a blurred copy.
/// The creative's *dimensions* come cheaply from the decoded image's ImageInfo (no
/// on-device pixel sampling).
class GoldenKrillCreativeFill extends StatefulWidget {
  const GoldenKrillCreativeFill(this.ad, {super.key, this.neutral = Colors.black});
  final AdItem ad;
  final Color neutral;

  @override
  State<GoldenKrillCreativeFill> createState() => _GoldenKrillCreativeFillState();
}

class _GoldenKrillCreativeFillState extends State<GoldenKrillCreativeFill> {
  Size? _creative;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.ad.isPhotographic) return; // cover+blur path needs no dimensions
    final stream = CachedNetworkImageProvider(widget.ad.image).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => _creative = Size(info.image.width.toDouble(), info.image.height.toDouble()));
    }, onError: (_, __) {/* keep the neutral fill */});
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  List<Color>? get _edges {
    final c = [for (final h in widget.ad.edgeColors) gkParseColor(h)];
    return c.length == 4 && !c.contains(null) ? c.cast<Color>() : null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ad.isPhotographic) {
      return Stack(fit: StackFit.expand, children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Image(image: CachedNetworkImageProvider(widget.ad.image), fit: BoxFit.cover, gaplessPlayback: true),
        ),
        GoldenKrillCreative(widget.ad, fit: BoxFit.cover),
      ]);
    }
    final edges = _edges;
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(fit: StackFit.expand, children: [
        gkEdgeFill(Size(constraints.maxWidth, constraints.maxHeight), _creative, edges, widget.neutral),
        GoldenKrillCreative(widget.ad),
      ]);
    });
  }
}

/// Renders a creative image and opens its store link on tap. The official renderer:
/// using it (vs your own `present`) is what lets the network credit a *measured*
/// display later. Shows nothing if the image fails to load.
class GoldenKrillCreative extends StatelessWidget {
  const GoldenKrillCreative(this.ad, {super.key, this.fit = BoxFit.contain});

  final AdItem ad;
  final BoxFit fit;

  void _open() {
    final s = ad.store;
    if (s != null && s.isNotEmpty) {
      // ignore: discarded_futures
      launchUrl(Uri.parse(s), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _open,
        child: CachedNetworkImage(
          imageUrl: ad.image,
          fit: fit,
          fadeInDuration: Duration.zero, // no flash; creatives rotate, not animate in
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
}

/// Drop-in banner that owns the rotation loop and honors the contract:
///
/// - **Reserve** (time-based): on ~1 unit in every N, show ours instead of paid.
/// - **Paid**: on the other units, mount your paid banner via [paidBuilder].
/// - **Fallback**: if a paid unit returns no fill, show ours instead of a blank.
/// - **Refresh**: it rotates every unit (`config.banner_rotation_sec`, else jittered
///   ~55-65s), like a paid banner - never freezes one creative.
///
/// [paidBuilder] loads your paid banner and returns its widget if it filled, or `null`
/// on no-fill. Pass `null` for "no paid network" (ours every unit). Banners are
/// fill/cadence-gated - no interstitial cooldown or session cap applies.
class GoldenKrillBanner extends StatefulWidget {
  const GoldenKrillBanner({
    super.key,
    required this.ads,
    this.slot = 'banner',
    this.paidBuilder,
    this.height,
    this.unit,
    this.showBadge,
    this.reserveSpace = true,
    this.sdkControlsRefresh,
  });

  final GoldenKrillAds ads;
  final String slot;

  /// Banner refresh strategy. **Null (default) reads the host's portal setting** from the
  /// served config (`bannerSdkRefresh`); pass a bool to override per call site.
  ///
  /// - **false - Regular (default):** leave your paid network's banner auto-refresh ON. GK shows
  ///   one house ad for 1 unit, then hands the slot back to paid for the next (N-1) units, then
  ///   repeats. [unit] (or the config rotation) is the refresh interval T.
  /// - **true - Advanced:** GK drives rotation every unit (exact 1-in-N). You MUST turn your paid
  ///   network's banner auto-refresh OFF, or the two fight.
  ///
  /// See the portal Help "Banner & MREC refresh".
  final bool? sdkControlsRefresh;

  /// Hold the slot's box even before/without an ad so the host layout never shifts when
  /// one arrives (AdMob-style, default true). False collapses to nothing on no-fill.
  final bool reserveSpace;

  /// Draw a tiny GK corner mark. Null -> the portal's show_ad_badge config.
  final bool? showBadge;

  /// Loads a paid banner; returns its widget if filled, `null` on no-fill. `null`
  /// builder = no paid network (ours every unit).
  final Future<Widget?> Function()? paidBuilder;
  final double? height;

  /// Override the rotation unit (else taken from config / jittered).
  final Duration? unit;

  @override
  State<GoldenKrillBanner> createState() => _GoldenKrillBannerState();
}

class _GoldenKrillBannerState extends State<GoldenKrillBanner> {
  Widget? _child;
  Timer? _timer;
  int _unit = 0;
  bool _ticking = false;
  bool _badge = false; // rolled per rotation so it doesn't flicker on rebuild

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await widget.ads.ensureReady(slot: widget.slot);
    // Explicit param wins; otherwise default from the host's portal setting (served config).
    final sdkControls = widget.sdkControlsRefresh ?? widget.ads.config.bannerSdkRefresh;
    if (sdkControls) {
      // Advanced: GK drives rotation, re-mounting paid every unit.
      final dur = widget.unit ?? widget.ads.config.bannerRotation();
      await _tick();
      _timer = Timer.periodic(dur, (_) => _tick());
    } else {
      await _enterPaid(); // Model B (default): host auto-refreshes paid; GK inserts 1-in-N.
    }
  }

  Duration get _unitDur => widget.unit ?? widget.ads.config.bannerRotation();

  // Reserve ratio N from config; <= 1 means no reserve (paid only, host auto-refreshes).
  int get _reserveN {
    final c = widget.ads.config;
    return (c.reserveShare && c.reserveOneIn >= 1) ? c.reserveOneIn : 0;
  }

  void _show(Widget? next, bool isHouse) {
    if (!mounted) return;
    setState(() {
      _child = next;
      _badge = isHouse && (widget.showBadge ?? widget.ads.config.rollAdBadge());
    });
  }

  // Model B paid phase: mount the paid banner once (it auto-refreshes itself) for (N-1) units,
  // then switch to the house phase. No paid network / no-fill -> our house fill instead.
  Future<void> _enterPaid() async {
    Widget? paid;
    if (widget.paidBuilder != null) {
      try {
        paid = await widget.paidBuilder!.call();
      } catch (e) {
        gkLog(() => 'banner[${widget.slot}]: paidBuilder threw ($e) -> no-fill');
        paid = null;
      }
    }
    _show(paid ?? await _house(), paid == null);
    if (!mounted) return;
    final n = _reserveN;
    // No reserve -> stay paid; re-check after one unit (lets fill/inventory recover).
    _timer = n <= 1 ? Timer(_unitDur, _enterPaid) : Timer(_unitDur * (n - 1), _enterHouse);
  }

  // Model B house phase: one house ad, uninterrupted for a single unit, then back to paid.
  Future<void> _enterHouse() async {
    final house = await _house();
    if (house == null) {
      await _enterPaid(); // no house inventory -> keep paid running
      return;
    }
    _show(house, true);
    if (!mounted) return;
    _timer = Timer(_unitDur, _enterPaid);
  }

  Future<void> _tick() async {
    if (_ticking) return; // skip if a paid load is still in flight
    _ticking = true;
    final reserveTurn = widget.ads.bannerReserveTurn(_unit);
    _unit++;
    Widget? next;
    bool isHouse; // the badge is OURS-only: never drawn on (or beside) a paid ad
    if (reserveTurn || widget.paidBuilder == null) {
      next = await _house();
      isHouse = true;
    } else {
      Widget? paid;
      try {
        paid = await widget.paidBuilder!.call();
      } catch (e) {
        gkLog(() => 'banner[${widget.slot}]: paidBuilder threw ($e) -> no-fill');
        paid = null; // a throwing paidBuilder is treated as no-fill, never propagated
      }
      if (paid != null) {
        next = paid;
        isHouse = false; // paid filled -> no GK mark
      } else {
        next = await _house(); // no-fill or error -> fallback to ours
        isHouse = true;
      }
    }
    final badge = isHouse && (widget.showBadge ?? widget.ads.config.rollAdBadge());
    if (mounted) {
      setState(() {
        _child = next;
        _badge = badge;
      });
    }
    _ticking = false;
  }

  Future<Widget?> _house() async {
    final ad = await widget.ads.bannerHouse(widget.slot);
    return ad == null ? null : GoldenKrillCreative(ad);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Slot aspect ratios (match the server's creative dimensions) so the box fits the
  // creative exactly - no crop, no letterbox. Falls back to an explicit height if unknown.
  static const _slotAspect = {'banner': 640 / 100, 'mrec': 600 / 500};

  @override
  Widget build(BuildContext context) {
    final aspect = _slotAspect[widget.slot];
    // Align(center, heightFactor:1) hugs the creative even if the host forces a tight,
    // full-width box (e.g. SizedBox(width: infinity, height: 50)) - otherwise the box
    // stretches past the creative and the corner badge lands in the empty side margin.
    Widget box(Widget? inner) => aspect != null
        ? Align(alignment: Alignment.center, heightFactor: 1, child: AspectRatio(aspectRatio: aspect, child: inner))
        : SizedBox(height: widget.height, child: inner);
    final child = _child;
    // Reserve the slot's box even before/without an ad so the host layout never shifts when
    // one arrives (AdMob-style). reserveSpace=false collapses to nothing on no-fill.
    if (child == null) return widget.reserveSpace ? box(null) : const SizedBox.shrink();
    // Tiny banner: display-only "GK". Bigger slots (mrec): tappable "Powered by Golden Krill".
    final isBanner = widget.slot == 'banner';
    final mark = isBanner
        ? const _GkBadge('GK', compact: true)
        : _GkBadge(
            'Powered by Golden Krill',
            url: widget.ads.config.badgeUrl.isNotEmpty ? widget.ads.config.badgeUrl : kBadgeInfoUrl,
          );
    final inner = _badge
        ? Stack(children: [Positioned.fill(child: child), Positioned(bottom: 2, right: 2, child: mark)])
        : child;
    return box(inner);
  }
}

/// Full-screen interstitial page. Tap the creative to open the store; a close button
/// appears after [closeAfter] so the user can't dismiss it instantly.
class GoldenKrillInterstitialPage extends StatefulWidget {
  const GoldenKrillInterstitialPage(
    this.ad, {
    super.key,
    this.closeAfter = const Duration(seconds: 3),
    this.showBadge = false,
    this.badgeUrl = '',
  });

  final AdItem ad;
  final Duration closeAfter;
  final bool showBadge;
  final String badgeUrl;

  @override
  State<GoldenKrillInterstitialPage> createState() => _GoldenKrillInterstitialPageState();
}

class _GoldenKrillInterstitialPageState extends State<GoldenKrillInterstitialPage> {
  bool _canClose = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.closeAfter, () {
      if (mounted) setState(() => _canClose = true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Contain-fit creative over a sampled edge-colour fill (or cover+blur for
            // photographic creatives); fills the whole screen, edge to edge.
            Positioned.fill(child: GoldenKrillCreativeFill(widget.ad)),
            // Chrome lives in the safe-area over the fill, never under the status bar.
            SafeArea(
              child: Stack(
                children: [
                  if (widget.showBadge)
                    Positioned(top: 4, left: 4, child: _GkBadge('Powered by Golden Krill', url: widget.badgeUrl)),
                  if (_canClose)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        style: IconButton.styleFrom(backgroundColor: Colors.black45), // visible on any bg
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Full-screen rewarded page: shows the creative with a countdown bar, blocks dismissal
/// until it completes, then the reward is earned (a close button appears). Tapping the
/// creative opens the store (a bonus). Pops `true` once the reward is earned.
class GoldenKrillRewardedPage extends StatefulWidget {
  const GoldenKrillRewardedPage(this.ad, {super.key, this.duration = const Duration(seconds: 5), this.showBadge = false, this.badgeUrl = ''});

  final AdItem ad;
  final Duration duration;
  final bool showBadge;
  final String badgeUrl;

  @override
  State<GoldenKrillRewardedPage> createState() => _GoldenKrillRewardedPageState();
}

class _GoldenKrillRewardedPageState extends State<GoldenKrillRewardedPage> {
  Timer? _timer;
  double _progress = 0;
  bool _done = false;
  bool _loaded = false; // countdown starts only once the creative image is ready

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    // Don't burn the timer while the image downloads. Precache it (the Creative widget
    // reuses the cache, so no double fetch), then start the countdown. whenComplete fires
    // on success or error, so a broken image still grants rather than hangs.
    // coverage:ignore-start
    // precacheImage needs a real network fetch + a temp-dir cache (path_provider), neither
    // of which exists in unit tests, so this load-gated branch and the countdown it starts
    // cannot run here. Verified manually + via the demo app.
    precacheImage(CachedNetworkImageProvider(widget.ad.image), context).whenComplete(() {
      if (!mounted || _loaded) return;
      setState(() => _loaded = true);
      _startCountdown();
    });
    // coverage:ignore-end
  }

  // Only reachable once the precache above completes - untestable in unit tests (see note).
  // coverage:ignore-start
  void _startCountdown() {
    const tick = Duration(milliseconds: 100);
    final total = widget.duration.inMilliseconds;
    var elapsed = 0;
    _timer = Timer.periodic(tick, (t) {
      elapsed += tick.inMilliseconds;
      if (!mounted) return;
      setState(() {
        _progress = (elapsed / total).clamp(0.0, 1.0);
        if (_progress >= 1.0) _done = true;
      });
      if (_progress >= 1.0) t.cancel();
    });
  }
  // coverage:ignore-end

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _done, // no early bail: the reward is earned only on completion
        child: Scaffold(
          backgroundColor: Colors.black,
          body: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    // Contain-fit creative over a sampled edge-colour fill (cover+blur for
                    // photographic); full-bleed, edge to edge.
                    Positioned.fill(child: GoldenKrillCreativeFill(widget.ad)),
                    // Countdown + chrome in the safe-area over the fill, not over the art.
                    SafeArea(
                      child: Stack(
                        children: [
                          Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(value: _progress)),
                          if (widget.showBadge)
                            Positioned(top: 8, left: 4, child: _GkBadge('Powered by Golden Krill', url: widget.badgeUrl)),
                          if (_done)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                style: IconButton.styleFrom(backgroundColor: Colors.black45), // visible on any bg
                                onPressed: () => Navigator.of(context).pop(true), // reward earned
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      );
}

/// UI conveniences on [GoldenKrillAds] (kept out of the core class so the logic stays
/// Flutter-widget-free).
extension GoldenKrillUI on GoldenKrillAds {
  /// One-call interstitial: runs the orchestration and presents any house ad with the
  /// official full-screen renderer. Returns true if something was shown.
  Future<bool> showInterstitial(
    BuildContext context, {
    required Future<bool> Function() paid,
    bool? showBadge, // null -> portal's show_ad_badge config
  }) {
    final badge = showBadge ?? config.rollAdBadge();
    final badgeUrl = config.badgeUrl.isNotEmpty ? config.badgeUrl : kBadgeInfoUrl;
    return show(
      'interstitial',
      paid: paid,
      present: (ad) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, __, ___) => GoldenKrillInterstitialPage(ad, showBadge: badge, badgeUrl: badgeUrl),
        ),
      ),
    );
  }

  /// One-call rewarded. User-initiated, so it tries your **paid rewarded first** (real
  /// reward + revenue); on no-fill it shows a house rewarded ad (timed, reward earned on
  /// completion). [paid] returns true if the paid network granted the reward.
  /// Returns true if the reward was earned (paid or house), false otherwise.
  Future<bool> showRewarded(
    BuildContext context, {
    required Future<bool> Function() paid,
    Duration? duration, // null -> portal-configured length (config.rewardedSeconds)
    bool? showBadge, // null -> portal's show_ad_badge config
  }) async {
    if (!hasSlot('interstitial')) await ensureReady(slot: 'interstitial');
    final dur = duration ?? config.rewardedDuration();
    final badge = showBadge ?? config.rollAdBadge();
    final badgeUrl = config.badgeUrl.isNotEmpty ? config.badgeUrl : kBadgeInfoUrl;
    // Reserve: on ~1-in-N reward moments, show a house cross-promo even if paid could
    // fill (the user still earns the reward). Honors the portal's reserve setting.
    final reserved = await rewardedReserve();
    if (reserved != null) {
      if (!context.mounted) return false;
      return _presentRewarded(context, reserved, dur, badge, badgeUrl);
    }
    try {
      if (await paid()) return true; // paid network granted the reward
    } catch (_) {/* paid failure -> try house */}
    final ad = await rewardedHouse(); // user-initiated; null = no inventory
    if (ad == null || !context.mounted) return false;
    return _presentRewarded(context, ad, dur, badge, badgeUrl);
  }

  Future<bool> _presentRewarded(BuildContext context, AdItem ad, Duration duration, bool showBadge, String badgeUrl) async {
    final earned = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: true,
        pageBuilder: (_, __, ___) => GoldenKrillRewardedPage(ad, duration: duration, showBadge: showBadge, badgeUrl: badgeUrl),
      ),
    );
    return earned ?? false;
  }
}

/// Where the disclosure badge sends a user who taps it (who we are / how to join).
const String kBadgeInfoUrl = 'https://golden-krill.com/about';

/// Small disclosure badge drawn over house ads ("Ad" full-screen, "GK" compact on banners).
/// On full-screen it's tappable (opens [kBadgeInfoUrl]); on banners it's display-only so it
/// can't steal the advertiser's tap on a tiny surface.
class _GkBadge extends StatelessWidget {
  const _GkBadge(this.label, {this.compact = false, this.url});

  final String label;
  final bool compact;
  final String? url; // null/empty -> display-only (banner); set -> tappable (full-screen)

  @override
  Widget build(BuildContext context) {
    // Always on-brand gold (banner "GK" + full-screen "Powered by Golden Krill"), with a
    // hairline dark border so it pops on any creative.
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 6, vertical: compact ? 0 : 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE7AD34),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x66000000), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: const Color(0xFF12363A),
          fontSize: compact ? 8 : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    final u = url;
    if (u == null || u.isEmpty) return chip;
    // Topmost in the Stack, so tapping it doesn't reach the creative behind (no store tap).
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
      child: chip,
    );
  }
}
