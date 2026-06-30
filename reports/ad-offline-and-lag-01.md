# ad-offline-and-lag-01: offline CTAs, unresponsive close, and stacked ads under lag

Date: 2026-06-30
Repo: PinkRorqual/golden-krill-sdk (Flutter package under `flutter/`)
Trigger: three connected ad-serving bugs reproduced in production Corrupted Circuits
(eapp) sessions. Flutter SDK only; React Native + Unity not touched.

## The three bugs (root causes)

**Bug A - offline CTAs.** `_fetchBundle` (`flutter/lib/src/serving/goldenkrill_ads.dart`)
served the **last-good failover** creative whenever a fetch *failed*. A fully offline
device fails every fetch, so it kept showing a house creative whose click tracker
(`ad.store`) and impression beacon could never succeed. Nothing gated serving on
connectivity. The failover was designed for a transient blip while online, not a
known-offline device.

**Bug B - close (X) feels unresponsive offline.** The close handlers were already
synchronous, but telemetry robustness was the real gap: a single fire-and-forget
`postEvents` with no retry and no de-dup. The fix hardens this into a contract: beacons
go through a persistent, de-duplicated, fire-and-forget queue, and close fires an
`onClosed` hook + pops **synchronously**, so no future change can accidentally make close
await a network POST.

**Bug C - two ads stack under lag.** `show()` had no debounce. Two calls in quick
succession (rapid taps / overlapping triggers) both ran the full async load; under
network lag the first was still loading when the second started, and both eventually
presented, stacking a second full-screen ad below the first.

## The fixes

All in `flutter/lib/src/serving/`.

### Bug A - gate availability + serving on connectivity

- New `connectivity.dart`: a `GkConnectivity = Future<bool> Function()` probe (injectable),
  default `gkConnectivityPlus` backed by `connectivity_plus`. A pure `gkIsOnline(results)`
  does the online/offline mapping (unit-tested without the platform channel). The default
  probe **fails open** on a platform-channel error (assume online) so a flaky probe can
  never permanently block ads; an actually-dead network then just fails the fetch.
- `_fetchBundle` returns `AdBundle.empty` when offline **before** fetching and **without**
  touching the failover. This gates every path that funnels through it: `reserveAd`,
  `fallbackAd`, `bannerHouse`, `rewardedHouse`, and the `ensureReady` warm.
- New `gk.isAdAvailable()` (`Future<bool>`): online **and** not already showing.
- `show()` returns `ShowResult.offline` when offline (typed failure, nothing served).

### Bug B - persistent fire-and-forget beacon queue + synchronous close

- New `event_queue.dart` (`GkEventQueue`): persists pending beacons in
  `shared_preferences`, keyed by an opaque event id so a duplicate enqueue (a retry of the
  same impression) **collapses** instead of double-counting. `flush()` posts each record,
  drops the ones that succeed, keeps the rest for a later retry; re-entrancy-guarded;
  never throws. Capped at 200 records (oldest dropped). Unsent beacons survive an app
  restart.
- `GoldenKrillClient.postEvents` now returns `bool` (true on 2xx) so the queue knows
  whether to retry.
- `GoldenKrillAds._beacon` routes impressions through the queue. The attestation token is
  fetched best-effort (timeout) off the caller's path. Enqueue + flush are unawaited from
  the caller, so a hung POST never blocks the UI.
- `GoldenKrillInterstitialPage` / `GoldenKrillRewardedPage` gain an optional `onClosed`;
  the close button calls it then `Navigator.pop` **synchronously** (it never awaited
  network, and now can't).

### Bug C - single in-flight gate

- `GoldenKrillAds` gains `_showing` + `tryBeginShow()` / `endShow()` / `isAdShowing`.
  `show()` claims the gate up front; a second call while one ad is loading or on screen is
  rejected with `ShowResult.alreadyShowing`. `present` may return a `Future` (the official
  renderers return the route's pop future), so the gate is held for the full on-screen
  lifetime, not just the load. `showInterstitial` / `showRewarded` share the same gate.

### API surface

- `show()` now returns a typed `ShowResult` (`r.shown` = the old boolean; `r.outcome` is
  `shown` / `noFill` / `offline` / `alreadyShowing`) and its `present` is
  `FutureOr<void> Function(AdItem)`. The turnkey `showInterstitial` / `showRewarded` keep
  their `Future<bool>` shape (and gain optional `onClosed`), so consuming apps that use
  the turnkey calls have **no call-site change**. Direct `show()` callers read
  `result.shown`. Per the task this ships as a **patch** (0.9.1 -> 0.9.2); the only public
  signature that changed (`show()`) has no consumer call sites today (capp/eapp/fapp use
  the turnkey helpers).

## Tests

New `flutter/test/offline_lag_test.dart` (one group per bug), plus three updated `show()`
assertions in `serving_test.dart` (now read `ShowResult`):

- **Bug A:** `gkIsOnline` mapping (4 cases); default probe fails open; `isAdAvailable`
  true online / false offline; offline never serves the stale failover (warm online ->
  offline returns null -> back online serves); `show()` returns `offline`, calls neither
  `paid` nor `present`, leaves the gate unstuck.
- **Bug B:** failed POST retained + persisted, a fresh queue instance retries and drains
  (restart survival); duplicate id collapses to one record; a hung POST never blocks the
  enqueuing caller; `show()` is not blocked by a hung impression POST; interstitial close
  fires `onClosed` and pops synchronously.
- **Bug C:** a second `show()` while one is on screen is rejected `alreadyShowing`, the
  gate releases on dismissal, a later call proceeds; `isAdAvailable` is false while showing
  even when online.

### Results (via `tool/flutter`, the shared Docker toolchain - nothing on the host)

- `flutter pub get`: resolved `connectivity_plus 6.1.5`.
- `flutter analyze lib test`: No issues found.
- `flutter test -j 8`: 115 / 115 pass, no failures (whole suite).
- Coverage: deferred. `--coverage` hangs (~1h) on this WSL box, so coverage is measured on
  the coverage gate (CI / a clean machine), not here. The new code paths are each covered by
  dedicated tests in `test/offline_lag_test.dart` (12 tests: the connectivity gate, the
  fire-and-forget de-duped beacon queue incl. a hung-POST case, synchronous close, and the
  single in-flight show() gate) plus the updated `serving_test.dart` / `widgets_test.dart`.
- Long-dash guard on changed files: clean.

## Cross-platform scope

Flutter only. React Native and Unity were not in scope for this report and are unchanged
(no version bump for them). The same three behaviours are worth a follow-up port to RN/
Unity, tracked separately.

## iOS privacy note

`connectivity_plus` reads the network transport type; it does not track the user or use an
advertising id, so it does not change the SDK's "no tracking" posture. It ships its own
`PrivacyInfo.xcprivacy`; the host app's privacy manifest mirroring is unaffected.

## Version + re-pin

- Post-0.9.1 bug fix -> PATCH: `flutter/pubspec.yaml` `0.9.1 -> 0.9.2` (+ adds the
  `connectivity_plus` dependency). RN `package.json` and Unity unchanged.

### Consuming apps (maintainer bumps each in a separate per-app session)

The SDK is pinned by git tag per app; none pick this up automatically. After the
maintainer commits + tags `v0.9.2`:

- **capp** (Cardnook) - `lib/services/ads_service.dart` holds `GoldenKrillAds`; uses the
  turnkey calls. Re-pin `goldenkrill` `ref: v0.9.1 -> v0.9.2`, `flutter pub get`.
- **eapp** (Corrupted Circuits, where these bugs were seen) -
  `lib/ads/ads_service.dart` wraps `GoldenKrillAds.showRewarded`. Re-pin + `pub get`.
- **fapp** - `lib/ads/ads_service.dart`, same shape as eapp. Re-pin + `pub get`.

All three use `showInterstitial` / `showRewarded` (still `Future<bool>`), so re-pin +
`pub get` + rebuild is the whole change; **no app code edit** is required. Each app's
`flutter pub get` will pull `connectivity_plus` transitively. (Consumer-side, not in the
SDK git block below.)

## Maintainer git block (SDK repo, exactly the changed files + this report)

This is the v0.9.2 bug-fix commit only. The `tool/flutter` wrapper alignment is a separate
concern with its own git block (see below). Run from `golden-krill-sdk/`:

```
git add flutter/lib/src/serving/connectivity.dart \
        flutter/lib/src/serving/event_queue.dart \
        flutter/lib/src/serving/goldenkrill_ads.dart \
        flutter/lib/src/serving/goldenkrill_widgets.dart \
        flutter/lib/src/serving/serving_client.dart \
        flutter/lib/goldenkrill.dart \
        flutter/pubspec.yaml \
        flutter/pubspec.lock \
        flutter/INTEGRATION.md \
        flutter/test/offline_lag_test.dart \
        flutter/test/serving_test.dart \
        flutter/test/widgets_test.dart \
        demo/flutter/test/demo_test.dart \
        CHANGELOG.md \
        reports/ad-offline-and-lag-01.md
git commit -m "serving: gate ads on connectivity (no offline CTAs), move impression beacons to a persistent fire-and-forget retry queue with synchronous close, and serialise show() through a single in-flight gate so two ads never stack under lag; bump 0.9.2"
git push origin main
git tag -a v0.9.2 -m "v0.9.2: offline gate + fire-and-forget beacon queue + no double-show (Flutter)"
git push origin v0.9.2
```

`widgets_test.dart` and `demo/flutter/test/demo_test.dart` are in this commit because the
connectivity gate made them inject a fake online probe (the default probe talks to the real
platform channel, which never resolves in a widget test).

Then: capp / eapp / fapp each set `ref: v0.9.2` + `flutter pub get` (separate per-app
sessions). eapp is currently temp-pinned at `v0.9.1` and is blocked on this tag for its next
release.

## Maintainer git block (separate: `tool/flutter` wrapper alignment)

Independent of the 0.9.2 fix: aligns the Docker wrapper to the studio toolchain standard (4 GB
per-container cgroup cap + an explicit `pinkrorqual-goldenkrill-sdk-<pid>` container label, so
the SDK container no longer collides with the GK family by deriving its name from the pubspec
`name: goldenkrill`). No SDK behaviour change, no version bump. `demo/flutter/tool/flutter`
mirrors the same fix; drop it from the `git add` if you prefer to align only the package
wrapper. Run from `golden-krill-sdk/`:

```
git add flutter/tool/flutter demo/flutter/tool/flutter
git commit -m "tool: align flutter wrapper with studio toolchain (4g cap + explicit goldenkrill-sdk container name)"
git push origin main
```
