# AI integration prompt - Golden Krill (Flutter)

Paste the block below to an AI coding assistant working **inside your Flutter app's
repo**. It wires Golden Krill behind your existing ads code. (Human? Just follow
[`INTEGRATION.md`](INTEGRATION.md) instead.)

---

You are working in a Flutter app. Integrate the **Golden Krill SDK** so that, around the
app's paid ad network (AdMob/AppLovin), unused ad moments are filled with house ads
(cross-promos for other apps) instead of blanks. It is **fallback + reserve only**: do
not change when or where paid ads are requested.

**1. Dependency** - in `pubspec.yaml`:
```yaml
dependencies:
  goldenkrill:
    git: { url: https://github.com/PinkRorqual/golden-krill-sdk.git, path: flutter, ref: v0.9.2 }
```
Run `flutter pub get`. This pulls `connectivity_plus` (the SDK gates ads on connectivity).

**2. One singleton, initialised once at startup:**
```dart
import 'package:goldenkrill/goldenkrill.dart';
final gk = GoldenKrillAds(package: '<THIS APP ANDROID PACKAGE, e.g. com.pinkrorqual.cardnook>');
await gk.ensureReady(slot: 'interstitial'); // and any other slot the app uses
```
Place it next to the app's existing `AdsService`.

**3. Wire it.** Easiest is a **turnkey full-screen call** (the SDK presents + closes the
creative itself). These return `Future<bool>` ("was something shown / reward earned?"),
unchanged across versions, so existing call sites need **no edit**:
```dart
final shown  = await gk.showInterstitial(context, paid: () async => admob.tryShowInterstitial());
final earned = await gk.showRewarded(context,    paid: () async => admob.showRewarded());
// Optional: pass onClosed: () { ... } - it fires synchronously when the user taps close.
```

Or orchestrate with **your own renderer** via `show()`:
```dart
final r = await gk.show('interstitial',
  paid: () async => await admob.tryShowInterstitial(), // true if it showed, false on no-fill
  present: (ad) => present(ad),                         // render the creative (below); may be sync or async
);
// gk runs reserve (1-in-N) -> your paid ad -> fallback + own-studio, from config.
// r.shown == false -> nothing was shown; collapse the slot.
```
`show()` returns a typed **`ShowResult`**, not a bare bool: `r.shown` is the old boolean,
and `r.outcome` is the reason (`ShowOutcome.shown` / `noFill` / `offline` /
`alreadyShowing`). `present` is `FutureOr<void> Function(AdItem)` - return the route's pop
`Future` to hold the in-flight gate until dismissal, so a second `show()` while one ad is
loading or on screen is rejected with `alreadyShowing` and two ads never stack. Advanced
manual control: `await gk.reserveAd(slot)` before paid + `await gk.fallbackAd(slot)` on
no-fill instead of `show` (both are async - they fetch per display).

**4. Availability + offline.** Serving is gated on connectivity (`connectivity_plus`):
offline, nothing is served (the SDK never shows a stale cached creative whose click /
impression beacons could not succeed) and `show()` returns `ShowOutcome.offline`. Gate any
"show ad" button on **`await gk.isAdAvailable()`** (`Future<bool>`: online AND no ad already
loading / on screen), re-checked at tap time. In tests, inject a fake probe so serving is
deterministic and offline: `GoldenKrillAds(connectivity: () async => true)` (the default
talks to the real platform channel, which never resolves in a widget test).

**`present(AdItem ad)`**: render `ad.image` (network image) at the slot's pixel size; on
tap `launchUrl(Uri.parse(ad.store))`. `ad.store` is a tracker URL - open it **as-is**
(never strip/rewrite). The impression is recorded for you, via a fire-and-forget,
de-duplicated retry queue, so telemetry never blocks the UI and the close button pops
synchronously even with no network.

**Slots:** `banner` 640x100, `mrec` 600x500, `interstitial` 1080x1920 (also rewarded).

**Rules:**
- `null` / nothing / `!r.shown` from any call is normal and frequent - collapse the slot,
  never a blank placeholder.
- Call Golden Krill only at a real ad moment, never on a timer or at startup.
- Do not add any analytics/tracking around it (it records app-keyed aggregates itself; no
  advertising ID, no user data).
- Add or update tests for the new reserve/fallback branches: `GoldenKrillAds` takes an
  injectable client + clock + connectivity probe - use a `MockClient` and
  `connectivity: () async => true`.

**Migration (already-integrated app moving to v0.9.2):** re-pin `ref:` to `v0.9.2`, run
`flutter pub get` (pulls `connectivity_plus`), rebuild. **No call-site change** if you use
the turnkey `showInterstitial` / `showRewarded` (still `Future<bool>`). If you call `show()`
directly, read `result.shown` where you previously used the returned `bool`.

**Acceptance:** paid path unchanged; a forced no-fill shows a Golden Krill creative (or
nothing) not a blank; offline shows nothing, not a stale creative; tapping opens the store
via `ad.store`; `flutter analyze` clean; tests pass.
