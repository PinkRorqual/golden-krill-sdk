# Integrating Golden Krill - Flutter

Flutter-specific guide. For the language-agnostic model + pseudocode, see the
[repo README](../README.md). Golden Krill is a **fallback + reserve house-ad
provider**: it fills a slot with a cross-promo when your paid network has **no fill**,
or on a small reserved share of moments. It sits beside your existing ads code; paid
call sites don't change. It never throws and never blocks your paid path.

## 1. Depend on it

```yaml
dependencies:
  goldenkrill:
    git: { url: https://github.com/PinkRorqual/golden-krill-sdk.git, path: flutter, ref: v0.9.0 }
```

## 2. One instance, loaded once

```dart
import 'package:goldenkrill/goldenkrill.dart';

final gk = GoldenKrillAds(package: 'com.pinkrorqual.yourapp'); // your Android package
await gk.ensureReady(slot: 'interstitial');
await gk.ensureReady(slot: 'banner');
```

`ensureReady` fetches per-app config + the slot's ad bundle once (cached ~1h,
offline-safe via last-good cache, never throws). Keep `gk` as a singleton.

## Readiness & timing (avoid the first-launch race)

On a fresh install, two independent races can make the first ad moment "always paid,
never house". Treat them as one rule:

> Don't act on an ad moment until **(a)** your paid SDK's **consent gate** (UMP / ATT /
> CCPA) has resolved, **and (b)** the Golden Krill bundle is loaded.

- **(a) Consent gate (yours to handle).** If your paid SDK is gated on UMP/ATT, your
  `paid` callback returns `false` instantly until consent resolves. That's fine - Golden
  Krill then tries to fill - but only if (b) is met.
- **(b) Per-display fetch.** Each display hits the server fresh, so `reserveAd`/`fallbackAd`
  are **async** (they `await` an HTTP fetch). The server randomizes and returns one cross-promo
  + one own-studio ad; the SDK shows what it gets (no client-side rotation). A successful but
  empty response is a real no-fill ("empty is empty") -> null -> go to paid. The only cache is
  a 1h **failover** copy, reused **only** when a fetch fails. `ensureReady` loads config
  (reserve ratio, cooldown) once and warms the failover copy.

`gk.show()` loads config first if you call it early. The **à-la-carte** `reserveAd`/`fallbackAd`
are **async** - `await` them, and call `ensureReady` once up front so config is loaded.

> **Own-studio backfill is a last resort you can't easily observe in testing.** The server
> returns one cross-promo ad (`a`) and one own-studio ad (`o`); the SDK shows `o` only when
> `a` is empty. Cross-promo is almost always available, so during your own integration
> testing you will usually *not* see your own apps, and there is no flag to force it. That is
> expected - the server applies the tiers (cross-promo first, then your own apps) on every
> request, so it works even though it is hard to see directly.

Recommended bootstrap for an ad-bearing screen - wait for both, with a single timeout cap
so a stalled consent flow or unreachable server costs only this one mount (it recovers
next mount):
```dart
Future<void> _bootstrapAds() async {
  await Future.wait([
    if (!consentGate.ready) consentGate.waitUntil(const Duration(seconds: 8)),
    gk.ensureReady(slot: 'banner')
      .timeout(const Duration(seconds: 8), onTimeout: () {})
      .catchError((_) {}),
  ]);
  if (!mounted) return;
  await gk.show('banner', paid: tryPaidAd, present: renderAd);
}
```

`ensureReady` is **cheap to call again** (last-good cache after the first fetch), so
calling it at app boot **and** in each ad-bearing screen's bootstrap is the recommended
pattern, not a duplicate.

If you `unawaited(gk.ensureReady(...))` at boot for a fast start, the **screen** must then
`await` readiness before an à-la-carte call. Fire-and-forget on *both* sides is the one
broken shape - the bundle loses the race every first launch.

## 3. Wire the three moments

### Interstitial / rewarded - one orchestrated call (recommended)

```dart
Future<void> showInterstitial() async {
  final r = await gk.show(
    'interstitial',
    paid: () async => admob.tryShowInterstitial(), // true if shown, false on no-fill
    present: present,                              // render the creative (below)
  );
  // gk runs reserve (1-in-N) -> paid -> fallback + own-studio, from config.
  // r.shown is the old boolean; r.outcome distinguishes noFill / offline / alreadyShowing.
}
```

`show()` returns a typed [`ShowResult`]: `r.shown` is the old "did anything display?"
boolean, and `r.outcome` is one of `shown` / `noFill` / `offline` / `alreadyShowing`.
`present` may return a `Future` (e.g. the route's pop future) - the SDK holds a single
in-flight gate until it completes, so a second `show()` while one ad is loading or on
screen is rejected (`outcome == alreadyShowing`) and two ads never stack.

Equivalent à-la-carte form, if you need manual control:

```dart
final reserved = await gk.reserveAd('interstitial');     // ~1-in-N, before paid (async fetch)
if (reserved != null) return present(reserved);
if (await admob.tryShowInterstitial()) return;           // your paid ad
final filler = await gk.fallbackAd('interstitial');      // no-fill: cross-promo, then own
if (filler != null) present(filler);                     // else show nothing
```

### Turnkey renderers (least code)

The SDK ships official renderers, so you don't have to write `present` at all:

```dart
// Interstitial: one call, GoldenKrill presents the creative full-screen itself.
await gk.showInterstitial(context, paid: () async => admob.tryShowInterstitial());

// Banner: owns the rotation loop (time-based reserve + fallback + refresh).
GoldenKrillBanner(
  ads: gk,
  slot: 'banner',
  height: 50,
  paidBuilder: () async => loadAdmobBanner(),  // Future<Widget?>: widget if filled, null on no-fill
)
```

Using the official renderers (vs your own `present`) is also what lets the network
credit a *measured* display later.

### Banner - how it works

`GoldenKrillBanner` runs its own rotation loop (unit from `banner_rotation_sec`, else a
jittered ~55-65s) and on each unit:
- **Reserve** (time-based): ~1 unit in every N shows **ours** instead of paid (when
  enabled). It simply doesn't request paid on those units - **never load-and-discard**,
  so it's policy-safe.
- **Paid**: on the other units it calls your `paidBuilder` and shows the paid banner.
- **Fallback**: if `paidBuilder` returns `null` (no fill), it shows ours instead of a blank.
- **Refresh**: it rotates every unit, like a paid banner - never freezes one creative.

`paidBuilder` is `Future<Widget?> Function()?`: load your paid banner, return its widget
if it **filled**, or `null` on no-fill. Pass `null` for "no paid network" (ours every unit).
Banners are fill/cadence-gated - the interstitial cooldown/cap don't apply.

### Presenting a creative

```dart
void present(AdItem ad) {
  // Render ad.image at the slot's pixel size. On tap, open ad.store with url_launcher.
  // ad.store is a /c tracker URL that 302s to the real store and counts the click.
  // The impression was recorded when the AdItem was returned. Never modify ad.store.
}
```

## Rewarded

Rewarded reuses the **`interstitial`** slot's creatives (no separate upload). It honors
the **1-in-N reserve** (a house reward on ~1-in-N moments even if paid could fill), then
your **paid rewarded**, then a house rewarded on no-fill - in that order:
```dart
final earned = await gk.showRewarded(context, paid: () async => admob.showRewarded());
if (earned) grantReward();
```
- `paid` returns `true` if the paid network granted the reward.
- The house rewarded ad shows the creative with a **countdown bar**, blocks dismissal until
  it completes, then the reward is earned (tapping the creative opens the store too).
- Gate a "watch ad" button on **`gk.rewardedReady`** (bool) or the reactive
  **`gk.rewardedAvailable`** (`ValueNotifier<bool>`).
- Frequency: counts the session cap, **skips the cooldown** (user-initiated).
- Countdown length is the portal's `rewarded_seconds` (0 = SDK default 10s); pass
  `duration:` to override per call. The countdown **starts after the creative loads**, so
  a slow image doesn't eat the reward time.

## Multiple networks / mediation

The `paid` closure abstracts your *entire* paid stack - Golden Krill never sees which
network you use and has no ad-SDK dependency. One network, a hand-rolled AdMob+AppLovin
waterfall, or a mediation SDK (AppLovin MAX / AdMob mediation) all look identical:

```dart
gk.show(slot, paid: () async {
  if (await admob.tryShow(slot)) return true;   // waterfall: your order/logic
  return await applovin.tryShow(slot);
}, present: present);
// or simply: paid: () => max.tryShow(slot)   // a mediation SDK is already one call
```

Golden Krill decides only paid-vs-house and fires a house ad only when your whole paid
stack returns `false`. It never mediates paid-vs-paid - that stays your job.

## `AdItem`

| Field | Meaning |
|---|---|
| `id` | creative id (internal, for beacons) |
| `image` | creative image URL - show at the slot size |
| `store` | click-tracker URL - open as-is on tap (counts the click, 302s to the store) |

## Offline + availability

- **Offline = no ad.** Every fetch/serve is gated on connectivity (`connectivity_plus`).
  Offline, `show()` returns `outcome == offline`, `fallbackAd`/`reserveAd`/`bannerHouse`
  return `null`, and the SDK does **not** serve a stale cached creative (its click /
  impression beacons could not succeed). The last-good failover is only for a *transient*
  blip while online, not a known-offline device.
- **`gk.isAdAvailable()`** (`Future<bool>`): true only when online **and** no ad is
  already loading / on screen. Gate a "show ad" button on it, and re-check at tap time.
- Inject a custom probe in tests via `GoldenKrillAds(connectivity: () async => false)`.
- **Telemetry never blocks the UI.** Impression beacons go to a persistent, deduplicated,
  fire-and-forget retry queue; the close (X) button calls your optional `onClosed` and
  pops **synchronously**, never awaiting the network, even offline.

## Behaviour you can rely on

- **`null` is normal** (cap hit, cooldown, no eligible inventory, offline, offline first run).
  Always collapse; never a placeholder.
- **Frequency-capped** by config (`maxPerSession` + `houseCooldownSec`). Call
  `gk.resetSession()` on return from a long background for a fresh cap.
- **Degrades gracefully**: failed fetch -> last-good cache -> safe defaults. Never throws.

## Slots

`banner` 640x100, `mrec` 600x500, `interstitial` 1080x1920 (also rewarded).

## Testing

`GoldenKrillAds` / `GoldenKrillClient` take an injectable `http.Client` + clock, so you
can unit-test the fallback branch with a `MockClient` and no network. See
[`test/serving_test.dart`](test/serving_test.dart).

## Debug logging

Off by default, zero cost when off. Turn it on in dev and grep your console / logcat for
`[GoldenKrill]`:
```dart
GoldenKrillDebug.enabled = true;
```
Tag is always `[GoldenKrill]`, printed via `print` (no level/severity). It logs the
decisions, not a firehose: config/ads loaded (`ready[...]`), which path was chosen
(`show[...]: reserve|paid|fallback|nothing`), banner house picks (`banner[...]: house id=`),
a throwing `paidBuilder` (`paidBuilder threw ... -> no-fill`), and fetch failures
(`fetch ...: HTTP 5xx (using cache/defaults)`).

## Default config values

If `/api/v1/config` can't be reached, the SDK uses these (also the field meanings). The
operator can change the served values; treat these as the floor, not a contract.

| Field | Default | Meaning |
|---|---|---|
| `reserveShare` | `true` | reserve is on |
| `reserveOneIn` | `4` | ours 1 unit in every N |
| `fallbackFill` | `true` | fill paid no-fill with ours |
| `fillOwnAds` | `false` | promote own-studio apps as last resort |
| `houseCooldownSec` | `240` | min gap between house ads (interstitial) |
| `maxPerSession` | `3` | per-session house cap (interstitial) |
| `ownAdsCooldownMin` | `5` | extra spacing before own-studio ads |
| `bannerRotation()` | jittered **55-65s** | banner rotation unit when `banner_rotation_sec` is 0 |

## Reserve cadence (which tick is ours)

Reserve fires on the **first** eligible moment, then every Nth. With `reserveOneIn: 4`:

| tick / unit | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| served | **ours** | paid | paid | paid | **ours** | paid | paid | paid |

Banner cadence is **time-based** (each unit is one rotation period); interstitial cadence
is **count-based** (each eligible call). Short sessions still get the cross-promo.

## Cross-promo vs own-studio (`ads` vs `own`)

The bundle has two pools: `ads` (cross-promo, other studios) and `own` (your own studio's
other apps). **Reserve uses `ads` only.** **Fallback uses `ads`, then falls through to
`own`** when there's no cross-promo. So your own apps only surface as a last resort.

## Banner `paidBuilder` contract

- **Signature:** `Future<Widget?> Function()?`. Load your paid banner; return its widget if
  it **filled**, `null` on no-fill. `null` builder = no paid network (ours every unit).
- **Reserve units never call it** - on ours-turns the SDK doesn't request paid at all
  (policy-safe; no load-and-discard).
- **Throwing is treated as no-fill** - the SDK swallows it and shows a house ad; it never
  propagates. (Returning `null` is still the clean way.)
- **Consent gates:** if your paid SDK is gated on async readiness (UMP / ATT / CCPA),
  return `null` until it's ready - the SDK fills with a house ad and retries paid next unit.
- **Lifecycle:** on the next tick the SDK drops its reference to the previous widget; it
  does **not** call `dispose()` on native resources that widget held. If your paid banner
  needs explicit teardown, manage it yourself.
- **AdMob refresh:** by default (Regular mode, v0.7.0+) the SDK does NOT own rotation, so
  keep your AdMob auto-refresh ON. Only if you pass `sdkControlsRefresh: true` (Advanced
  mode) does the SDK drive rotation; then **disable the ad unit's auto-refresh in the AdMob
  console** so the two schedules don't race. See CHANGELOG v0.7.0 and v0.8.2.

## On-device cache

| What | TTL | SharedPreferences key |
|---|---|---|
| config | `kConfigTtl` = **12h** | `gk_cfg_v1_<package>` |
| ads bundle | `kAdsTtl` = **1h** | `gk_ads_v1_<package>_<slot>` (+ `gk_ads_at_v1_...` timestamp) |

Fetched at most once per TTL; serves last-good cache offline. To force a refresh in dev,
clear those keys (or the app's SharedPreferences). "Stale ads" almost always means a warm
1h cache - wait it out or clear the key.

## Debugging with curl

The SDK requests the obfuscated GK1 wire (`fmt=gk1`), but the same endpoints return readable
**JSON without it** - use that to confirm what your app is provisioned with:
```bash
# readable JSON (for you):
curl -s 'https://a.golden-krill.com/api/v1/config/<your.package>'
curl -s 'https://a.golden-krill.com/api/v1/ads?app=<your.package>&slot=banner&lang=en'
# exactly what the device decodes (GK1 blob):
curl -s 'https://a.golden-krill.com/api/v1/ads?app=<your.package>&slot=banner&fmt=gk1'
```
Config shows your served knobs (incl. `banner_rotation_sec`); `/ads` shows `{"a":[...],"o":[...]}`
as `[id, image, store]` tuples. Empty `a` + `o` = no eligible inventory (collapse is correct).

## Test mode

`testMode` makes the server return an always-fill **"TEST AD"** (even with zero real
inventory, and for an app that is not yet registered) so you can see an ad on your very
first run, and tells the server to **count nothing**: a test serve and its beacons never
touch any real metric, reach, trust, or reciprocity weight.

```dart
final ads = GoldenKrillAds(package: 'com.you.app');           // testMode defaults to kDebugMode
final ads = GoldenKrillAds(package: 'com.you.app', testMode: false); // force the real path (QA on release)
```

- **Default = debug build.** `testMode` defaults to `kDebugMode` (true in debug, false in
  release), so you get TEST ADs while developing and ship the real path automatically.
- **NEVER ship a release build with `testMode` forced on.** QA may override it to exercise
  the real serving path on a release build.
- It is a convenience + metric-hygiene feature, **not a security boundary** (a client can
  lie about the flag). The real anti-fraud is the attestation/trust layer; test mode only
  keeps honest dev traffic out of the numbers.

## Privacy

App-keyed aggregate counters only - no advertising ID, no per-user profiling.

## Privacy + Apple App Review (iOS)

The Golden Krill SDK is built to pass App Review cleanly as an embedded SDK.

**No tracking, no IDFA, no ATT obligation.** The SDK does not use the IDFA, does not read
any device or advertising identifier, and never links data to a user or across apps. It
collects only anonymous, aggregate ad-interaction counts (which house ad was shown or
tapped) for serving and frequency-capping. Because it does not track, it imposes **no App
Tracking Transparency (ATT) requirement** on your app. ATT prompts are only for your own
paid ad SDK (e.g. AdMob), not for Golden Krill: keep gating your paid SDK on UMP/ATT as you
already do, and add nothing extra for Golden Krill.

**Privacy manifest.** A canonical `PrivacyInfo.xcprivacy` ships at `ios/PrivacyInfo.xcprivacy`
in this SDK, declaring `NSPrivacyTracking = false`, no tracking domains, ad-interaction data
as not-linked + not-tracking (for app functionality), and no directly-used required-reason
APIs (local persistence goes through `shared_preferences`, which ships its own manifest).
Golden Krill is distributed as a **pure-Dart package** (no native iOS framework), so it is
not on Apple's list of binary SDKs that must bundle their own manifest. Reflect these
declarations in **your app's** `PrivacyInfo.xcprivacy` (which App Review reads): in practice
Golden Krill adds nothing trackable, so your manifest needs no Golden Krill specific tracking
or identifier entries.

**App Attest passthrough degrades gracefully.** The iOS attestation path is identical to
Android: your app optionally mints a token and forwards it via `attestationProvider`; the SDK
only forwards the opaque string. Server-side verification is parked, so a missing, null,
throwing, or slow provider is fine: the beacon still fires, just without attestation, and
serving is never blocked. You can ship with no `attestationProvider` at all.

**ATS-clean.** All network calls are HTTPS to `a.golden-krill.com` and `golden-krill.com`,
so no App Transport Security exceptions are needed.

**Verify on a Mac (the maintainer):** the Dart/JS logic above is covered by automated tests,
but CocoaPods/Xcode integration (the manifest being picked up in an actual `pod install` +
archive, and an on-device build) can only be confirmed on macOS with Xcode. Do a test
archive of a host app that embeds the SDK and confirm App Review's privacy report is clean.
