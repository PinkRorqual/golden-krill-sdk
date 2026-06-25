# Golden Krill Flutter demo

A tiny showcase app for the Golden Krill Flutter SDK (the Flutter twin of the
React Native demo). It exercises all four serving moments behind the SDK facade.
House-ads-only: the "paid network" is **simulated**, so a paid no-fill (or a
~1-in-N reserved unit) falls back to a Golden Krill house ad.

## What it shows

Four tabs:

- **Banner** - rotates a simulated paid banner and house ads. ~1-in-N units is a
  house ad (the reserve share, from config); the gold "GK" mark shows only on those.
- **MREC** (600x500 creative, shown about 300px wide on a phone) - same paid/house rotation; the larger house unit shows a
  tappable "Powered by Golden Krill" pill (to `/about`).
- **Interstitial** - ~1-in-N taps shows a house interstitial; the rest are the
  simulated paid network. The house cooldown can gate the fallback.
- **Rewarded** - ~1-in-N is a house rewarded (countdown, then reward); the rest are
  simulated paid. Shows "Reward earned!" / "No reward."

The **Paid: fill / NO-FILL** button at the top toggles the simulated paid network.
Flip it to NO-FILL to force the SDK's house fallback on every moment.

## Run it (host-clean, via the studio Docker wrapper)

Everything runs through `tool/flutter` (the verbatim studio wrapper - the Flutter
SDK, Android SDK and JDK live only in the `pinkrorqual-flutter:latest` image, never
on the host):

```bash
tool/flutter pub get
tool/flutter run                 # on a connected device/emulator
```

### Point it at a server that has inventory

By default the SDK talks to production (`https://a.golden-krill.com`). New inventory
may be thin, so a reviewer can hit a silent empty collapse. Override the serving
host with `--dart-define` to target staging or a local mock and reliably see fill:

```bash
tool/flutter run --dart-define=GK_BASE=https://staging.golden-krill.com
```

- **Target package (serving id):** `com.goldenkrilltest.fluttershowcase` - a separate
  test app registered in the portal. The SDK sends this to `/ads` and `/config`.
- **Target server:** `kDemoBase` (the `GK_BASE` define), default
  `https://a.golden-krill.com`.

## Platforms

**Android-only** for now (the `android/` runner is present; there is no `ios/`).
iOS can be added with `tool/flutter create --platforms=ios .` when an Apple build
machine is available; the SDK itself is already cross-OS (pure Dart, no native).

## Tests

```bash
tool/flutter test --coverage
```

The widget tests inject a `MockClient`, so they hit no network: they drive all four
tabs, the fill/no-fill toggle, and the interstitial/rewarded flows against canned
GK1 responses.
