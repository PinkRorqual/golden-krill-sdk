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
    git: { url: https://github.com/PinkRorqual/golden-krill-sdk.git, path: flutter, ref: v0.9.0 }
```
Run `flutter pub get`.

**2. One singleton, initialised once at startup:**
```dart
import 'package:goldenkrill/goldenkrill.dart';
final gk = GoldenKrillAds(package: '<THIS APP ANDROID PACKAGE, e.g. com.pinkrorqual.cardnook>');
await gk.ensureReady(slot: 'interstitial'); // and any other slot the app uses
```
Place it next to the app's existing `AdsService`.

**3. Wire it with one orchestrated call** inside the app's `AdsService` (don't change paid
call sites):
```dart
final shown = await gk.show('interstitial',
  paid: () async => await admob.tryShowInterstitial(), // true if it showed, false on no-fill
  present: (ad) => present(ad),                         // render the creative (below)
);
// gk runs reserve (1-in-N) -> your paid ad -> fallback + own-studio, from config.
// shown == false -> nothing was shown; collapse the slot.
```
Advanced (manual control): use `await gk.reserveAd(slot)` before paid + `await
gk.fallbackAd(slot)` on no-fill instead of `show` (both are async - they fetch per display).

**`present(AdItem ad)`**: render `ad.image` (network image) at the slot's pixel size; on
tap `launchUrl(Uri.parse(ad.store))`. `ad.store` is a tracker URL - open it **as-is**
(never strip/rewrite). The impression is recorded for you by the SDK.

**Slots:** `banner` 640x100, `mrec` 600x500, `interstitial` 1080x1920 (also rewarded).

**Rules:**
- `null`/nothing from any call is normal and frequent - collapse the slot, never a blank
  placeholder.
- Call Golden Krill only at a real ad moment, never on a timer or at startup.
- Do not add any analytics/tracking around it (it records app-keyed aggregates itself; no
  advertising ID, no user data).
- Add or update tests for the new reserve/fallback branches (`GoldenKrillAds` takes an
  injectable client + clock - use a `MockClient`).

**Acceptance:** paid path unchanged; a forced no-fill shows a Golden Krill creative (or
nothing) not a blank; tapping opens the store via `ad.store`; `flutter analyze` clean;
tests pass.
