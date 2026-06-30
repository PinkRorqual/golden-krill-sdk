# Golden Krill SDK - changelog

Consumers pin a git tag (Flutter `ref:`, RN `#tag`). Per-display serving + the trust
beacons are server-driven, so most behavior changes need no consumer code change.

## v0.9.3 - docs + test: connectivity_plus test-harness note (Flutter)

Docs and a regression test only. No API change, no behavior change. Consumers may stay
pinned to `v0.9.2`; this tag just makes the note discoverable.

- **Test-harness footgun from v0.9.2.** The default connectivity probe runs
  `Connectivity().checkConnectivity().timeout(2s)`. Under `flutter_test` the connectivity
  platform channel is unstubbed, so that 2s guard timer is left pending and the framework
  reports `A Timer is still pending` at teardown. It is a one-shot probe, not a leak (no
  stream subscription), and the seam to avoid it already exists.
- **Fix (consumer-side, in your tests).** In any widget test that touches serving, either
  inject a fake probe, `GoldenKrillAds(connectivity: () async => true)` (preferred:
  deterministic, arms no timer), or stub the platform channels:
  `dev.fluttercommunity.plus/connectivity` (method `check` -> `['wifi']`) plus a null
  handler on the `dev.fluttercommunity.plus/connectivity_status` event channel. See the
  Testing section of `flutter/INTEGRATION.md`.
- **Regression test.** `flutter/test/widgets_test.dart` drives the rewarded no-fill path
  (HTTP stubbed to 400, fake `GkConnectivity` injected) and asserts a clean teardown with
  no pending timer, documenting the injection contract.

**Consumer migration:** none required. Optionally re-pin to `v0.9.3`; no code change.

## v0.9.2 - offline gate, fire-and-forget beacons, no double-show (Flutter)

Three connected ad-serving fixes, all from production Corrupted Circuits sessions:

- **Offline gate (Bug A).** Ad availability + serving now gate on connectivity
  (`connectivity_plus`). Offline, `show()` returns the typed `ShowOutcome.offline`,
  `reserveAd`/`fallbackAd`/`bannerHouse` return `null`, and the SDK no longer serves a
  stale cached creative whose click/impression beacons could not succeed. The last-good
  failover stays a *transient-blip* safety net (online but a fetch failed), not an
  offline-device path. New `gk.isAdAvailable()` (online AND not already showing).
- **Telemetry never blocks the UI (Bug B).** Impression beacons go through a persistent,
  fire-and-forget retry queue keyed on an event id, so duplicates collapse and unsent
  beacons survive a restart and retry later. The close (X) button calls an optional
  `onClosed` and pops **synchronously**, never awaiting a network POST, even on a dead
  connection.
- **No stacked ads under lag (Bug C).** `show()` (and `showInterstitial`/`showRewarded`)
  serialise through a single in-flight gate: a second call while one ad is loading or on
  screen is rejected with `ShowOutcome.alreadyShowing` instead of popping a second ad
  under the first.

API: `show()` now returns a typed `ShowResult` (`r.shown` is the old boolean; `r.outcome`
distinguishes `shown`/`noFill`/`offline`/`alreadyShowing`) and its `present` may return a
`Future` held until dismissal. The turnkey `showInterstitial`/`showRewarded` keep their
`Future<bool>` shape and gain an optional `onClosed`. React Native + Unity unchanged.

**Consumer migration:** bump the pin to `v0.9.2`, `flutter pub get` (pulls
`connectivity_plus`), rebuild. No call-site change if you use `showInterstitial` /
`showRewarded`; direct `show()` callers read `result.shown`.

## v0.9.0 - Unity SDK, test mode, iOS privacy manifest

- **New platform: Unity (C#).** Source-shipped and native-free. The core serving logic is
  validated headless; the uGUI creative components ship as provisional and are finishing an
  editor polish pass.
- **SDK test mode.** With `test=1` the server returns an always-fill TEST AD so a new
  integrator sees a creative on day one. It is recorded nowhere and defaults to debug builds.
- **iOS privacy manifest.** Flutter and React Native ship `PrivacyInfo.xcprivacy` (no
  tracking, no advertising id; app-keyed aggregate product-interaction only).

Consumer migration: bump the pin to `v0.9.0`. No code change.

## v0.8.2 - banner strategy follows the portal toggle

The banner refresh strategy now **defaults from the host's portal setting** (served
`banner_sdk_refresh` in `/config`), so flipping "Advanced: let Golden Krill control banner
refresh" in the portal actually drives the widget - no code change needed.

- `GoldenKrillBanner.sdkControlsRefresh` is now **nullable / optional**: omit it (default) to
  follow the portal toggle; pass `true`/`false` to override per call site.
- Naming: **Regular** (default - one house unit, then paid for N-1 units, repeat) vs
  **Advanced** (SDK drives rotation; host must disable paid auto-refresh). Behaviour unchanged
  from v0.7.0; only the default source (config) + names changed.

**Consumer migration:** bump the pin; no code change. If you previously passed
`sdkControlsRefresh: false` to force Regular, you can drop it (it's the default).

## v0.8.1 - store-aware click routing

The SDK now sends its **store** with each `/api/v1/ads` request (`store=appstore` on iOS,
`store=play` on Android), so a tapped ad opens the **right app store** for the device. The
server bakes the resolved store URL into the signed click token, so the `/c/` redirect is
trustworthy without any User-Agent guessing.

- **No call-site change** - `GoldenKrillClient` detects the platform automatically (Flutter
  `defaultTargetPlatform`, RN `Platform.OS`).
- **Back-compatible:** older apps (no `store` param) default to Google Play, exactly as before.
- Advertisers with an App Store listing now get correct iOS deep-links; Android sub-stores
  (Galaxy/AppGallery/etc.) currently resolve to Play until per-store listings ship server-side.

**Consumer migration:** bump the pin to `v0.8.1`, `pub get` / `npm install`, rebuild. No code change.

## v0.7.0 - banner refresh models + UI fixes

**Banner/MREC refresh now defaults to Model B (passive).** `GoldenKrillBanner` no longer
re-mounts the paid banner every unit by default. Instead it keeps your paid network's
auto-refresh ON: it mounts the paid banner once and lets it auto-refresh for (N-1) units,
then shows ONE house ad uninterrupted for 1 unit, then hands back - a two-phase loop that
gives Golden Krill ~1/N of the time. Set the rotation unit (`unit` prop / config
`banner_rotation_sec`) to match your paid network's refresh interval T.

- **Advanced (Model A):** pass `sdkControlsRefresh: true` (Flutter) / `sdkControlsRefresh`
  (RN) to have the SDK drive rotation every unit (exact 1-in-N). You MUST turn your paid
  network's banner auto-refresh OFF in that mode. See the portal Help "Banner & MREC refresh".

**Consumer migration:** bump the pin. If your app left AdMob/AppLovin auto-refresh ON
(the default), you're already in the right mode - no change. If you had disabled it expecting
the SDK to refresh, either re-enable it (Model B) or pass `sdkControlsRefresh: true` (Model A).

Also in this release (were unreleased fixes):
- Full-screen interstitial/rewarded close (X) now sits on a dark scrim - visible on any background.
- Banner center-hugs its creative even under a tight full-width host box, so the corner badge
  stays on the ad instead of drifting into the side margin.

## v0.6.0 - two-pool serving + two cooldowns

**Behavior change (no API change).** Serving now uses two pools with two independent
cooldowns, matching the portal model:

- **GK pool** = all ads eligible for the consuming app (an advertiser targets the
  consumer's category) minus the app itself - **includes the app's own studio**. Serves
  the reserve (1-in-N) and the no-paid-fill GK ad. Cooldown: `house_cooldown_sec`.
- **Studio pool** = that eligibility restricted to the consuming app's own studio - the
  last-resort own ad when the GK pool is empty or on cooldown. The host opts in via
  `fill_own_ads`. Separate cooldown: `own_ads_cooldown_min`.

The two cooldowns are independent so GK and studio fills don't spam each other.

**Consumer migration (eapp / capp / fapp):** just bump the pin to `v0.6.0`. No call-site
change - `show()`, the widgets, and the à-la-carte `await reserveAd`/`await fallbackAd`
are unchanged. Then `flutter pub get` / `npm install` and rebuild.

## v0.5.x - per-display async serving

- `/ads` returns one random cross-promo + one random own ad, `no-store`; the SDK fetches
  **per display** (no client-side rotation), keeps a 1h failure-only failover.
- **Breaking from 0.4.x:** à-la-carte `reserveAd`/`fallbackAd`/`bannerHouse`/`rewarded*`
  are **async** - add `await`. `show()` + widgets unchanged.
- Anonymous weekly-rotating reach token + per-serve nonce echoed on beacons (replay
  defense + approximate device reach). No native code, no advertising id.
- Full-screen blurred-fill interstitial/rewarded (no crop), banner `reserveSpace`
  (no layout shift), Flutter `cached_network_image` for disk-cached creatives.
