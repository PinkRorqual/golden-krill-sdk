# goldenkrill (Flutter)

Flutter client for the [Golden Krill](https://golden-krill.com) cross-promotion network.
When your paid ad network returns **no fill** (or on a small reserved share of moments),
it fills the slot with a **house ad** for another participating app instead of a blank.
It sits beside your existing ads code, is frequency-capped, never throws, and never blocks
your paid path. App-keyed aggregate beacons only: no advertising ID, no profiling.

## Install
```yaml
dependencies:
  goldenkrill:
    git: { url: https://github.com/PinkRorqual/golden-krill-sdk.git, path: flutter, ref: v0.9.0 }
```

## Use

Two styles, your choice - both are first-class.

**One call (simple):** GoldenKrill orchestrates reserve -> paid -> fallback/own from config.
```dart
import 'package:goldenkrill/goldenkrill.dart';

final gk = GoldenKrillAds(package: 'com.pinkrorqual.yourapp');
await gk.ensureReady(slot: 'interstitial');

await gk.show('interstitial',
  paid: () async => admob.tryShow(),   // true if your paid ad showed, false on no-fill
  present: present);                    // present(ad): show ad.image; on tap open ad.store
```

**À-la-carte (full control):** weave the building blocks into your own flow.
```dart
final reserved = await gk.reserveAd('interstitial'); // ~1-in-N pre-empt (async, if enabled)
if (reserved != null) { present(reserved); return; }
if (await admob.tryShow()) return;
final filler = await gk.fallbackAd('interstitial');  // no-fill: cross-promo, then own studio
if (filler != null) present(filler);                 // else show nothing
```

The `paid` closure wraps your *whole* paid stack (one network, a waterfall, or a mediation
SDK) - GoldenKrill is network-agnostic and only decides paid-vs-house.

Full guide: [INTEGRATION.md](INTEGRATION.md). Slots: `banner` 640x100, `mrec` 600x500,
`interstitial` 1080x1920 (also rewarded).

## License
Apache-2.0 (the SDK code). Using the Golden Krill **network** is governed separately by
its Terms of Service + Privacy Policy.
