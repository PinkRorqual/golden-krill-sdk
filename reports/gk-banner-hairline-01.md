# gk-banner-hairline-01: white hairline on top of the GK banner (iOS)

Date: 2026-06-26
Repo: PinkRorqual/golden-krill-sdk (Flutter package under `flutter/`, consumed by capp)
Trigger: capp iOS work (`reports/mac-capp-archiveprep-01.md` in PinkRorqual/capp) plus a
direct maintainer report: "on the iOS app I see a white pixel line on top of the GK banner."

## First: the cited capp report is NOT an SDK bug

`reports/mac-capp-archiveprep-01.md` (capp) describes a capp-side iOS archive-prep round only:
committing `ios/Podfile` + `ios/Podfile.lock` and wiring `CODE_SIGN_ENTITLEMENTS` into capp's
own `project.pbxproj`. It never references the SDK; the installed pods are `Flutter`,
`isar_community_flutter_libs`, `sign_in_with_apple` (no goldenkrill pod, since the SDK is
pure-Dart). The SDK's `flutter/ios/PrivacyInfo.xcprivacy` is intentionally a canonical
declaration the host app mirrors (its own header says so), not an auto-bundled resource. So
nothing in that report is an SDK defect.

The real bug is the separately reported visual one below.

## Confirmed cause (real SDK bug)

A 1px white line along the top edge of the banner on iOS.

- The banner builds its creative as `GoldenKrillCreative(ad)`, which renders
  `CachedNetworkImage(fit: BoxFit.contain)` with NO opaque colour behind it
  (`flutter/lib/src/serving/goldenkrill_widgets.dart`, banner `build` -> `Stack[Positioned.fill(creative), badge]`).
- The full-screen interstitial/rewarded path does NOT have this problem because it paints a
  backing first via `gkEdgeFill` (a neutral base plus the sampled edge-colour bands) and only
  then the creative.
- On iOS, a contain-fit image in a fractional-height box (the banner is `AspectRatio(640/100)`,
  e.g. 61.4 pt tall) rounds to a sub-pixel gap at an edge. With nothing painted behind the
  image, the host background shows through that gap, which on a light screen reads as a white
  hairline. Any creative that is not exactly 6.4:1 would also letterbox to the host background
  for the same reason.

Verdict: real SDK defect, Flutter side. The banner was missing the opaque backing that the
full-screen path already has.

## The fix (minimal)

`flutter/lib/src/serving/goldenkrill_widgets.dart`:
1. New pure helper `gkBannerBackground(AdItem ad, {Color neutral})` -> the creative's top
   sampled edge colour when known, else a neutral (default black).
2. `GoldenKrillCreative` gains an optional `Color? background`; when set, the image is wrapped
   in a `ColoredBox(color: background)`. Null (the full-screen path) is unchanged.
3. The banner's house creative is now built as
   `GoldenKrillCreative(ad, background: gkBannerBackground(ad))`, so a sub-pixel gap shows the
   creative's own edge colour instead of the host background. No crop, no stretch, no layout
   change; only the previously-transparent backing is now opaque.

## Tests + coverage

Added 5 regression tests (red before the change: `background` / `gkBannerBackground` did not
exist; green after):
- `test/fill_test.dart` - `gkBannerBackground`: top edge colour used; neutral fallback when
  absent; neutral fallback on garbage edge colour (all three branches).
- `test/widgets_test.dart` - banner creative paints an opaque backing of the requested colour;
  null background adds no backing (full-screen path unaffected).

Results (via `tool/flutter`, the shared Docker toolchain):
- `flutter test`: all 103 pass (was 98; +5).
- `flutter analyze` on the changed files: No issues found.
- Long-dash check on the changed files: clean.
- Coverage: the new code paths are fully exercised; `goldenkrill_widgets.dart` sits at 84.7%
  overall (199/235), unchanged-in-character by this fix (the uncovered lines are pre-existing
  interstitial/rewarded chrome, not the banner backing).

## Cross-platform scope

- Flutter: fixed (`GoldenKrillCreative` background + `gkBannerBackground`).
- React Native: SAME defect, also fixed. `Creative` (`react-native/src/components/Creative.tsx`)
  gains an optional `background` that sets the wrapper's `backgroundColor`; the banner
  (`GoldenKrillBanner.tsx`) passes a neutral `BANNER_BACKDROP` (`#000000`) to its house
  creative. Note: the RN `AdItem` carries no sampled edge colours (the Flutter one does), so RN
  uses a neutral rather than the creative's edge colour. A 1px sub-pixel gap is essentially
  invisible either way; carrying edge colours into the RN wire model for an exact match is a
  separate, optional follow-up.
- Unity: NOT affected. `unity/Runtime/Unity/GoldenKrillBanner.cs` uses `RawImage`, which
  stretches the texture to fill the rect (no contain letterbox, so no gap). No change, no bump.

## Tests + coverage (React Native)

Added 2 regression tests in `react-native/test/Creative.test.tsx` (red before: the `background`
prop did not exist; green after): a set `background` paints the wrapper `backgroundColor`; an
unset one leaves it undefined (default unchanged). Results via local jest:
- Creative + banner suites: pass; full RN suite: 80 pass / 12 suites.
- `tsc --noEmit` is not usable here (the `react-native` peer types are not resolvable in this
  package's local node_modules, so it errors across every file, untouched ones included); the
  effective typecheck is ts-jest, which compiled and ran all 80 tests.
- Long-dash check on the changed RN files: clean.

## Version + re-pin

- Post-v0.9.0 bug fix -> PATCH, both changed SDKs:
  - `flutter/pubspec.yaml` `version: 0.9.0 -> 0.9.1`
  - `react-native/package.json` `version: 0.9.0 -> 0.9.1`
  - Unity unchanged (not affected).
- capp pins the Flutter package by git tag: `pubspec.yaml` `goldenkrill: git: ref: v0.9.0`. It
  will NOT pick this up automatically. After the maintainer commits and tags `v0.9.1`, capp
  re-pins `ref: v0.9.0 -> v0.9.1` and runs `flutter pub get`. Any RN consumer re-installs
  `@goldenkrill/react-native` at the new ref/tag. (Both are consumer-side, not in the git block.)

## Maintainer git block (SDK repo, exactly the changed files + this report)

Run from `golden-krill-sdk/`:

```
git add flutter/lib/src/serving/goldenkrill_widgets.dart \
        flutter/test/fill_test.dart \
        flutter/test/widgets_test.dart \
        flutter/pubspec.yaml \
        react-native/src/components/Creative.tsx \
        react-native/src/components/GoldenKrillBanner.tsx \
        react-native/test/Creative.test.tsx \
        react-native/package.json \
        reports/gk-banner-hairline-01.md
git commit -m "banner: paint an opaque backing behind the contain-fit creative so a sub-pixel gap no longer bleeds the host background as a white hairline on iOS (Flutter + React Native); bump 0.9.1"
git push origin main
git tag -a v0.9.1 -m "v0.9.1: fix iOS banner white-hairline (opaque backing behind contain-fit creative), Flutter + React Native"
git push origin v0.9.1
```

Then: capp sets `ref: v0.9.1` + `flutter pub get`; any RN app re-installs the SDK at v0.9.1.
