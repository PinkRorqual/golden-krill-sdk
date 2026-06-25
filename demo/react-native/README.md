# Golden Krill - React Native demo (Expo)

A runnable showcase of the three ad types (banner, interstitial, rewarded) on three
screens, **house-ads only** (no paid network is wired, so the SDK always fills with a
house ad). A **Rotate** button advances the banner immediately so you don't wait for the
rotation timer.

It consumes the SDK straight from source at [`../../react-native`](../../react-native)
(no publish/build step) via `metro.config.js`.

## Run

```bash
cd demo/react-native
npm install          # or: npx expo install   (to align native module versions)
npm start            # then press a (Android), i (iOS), or w (web)
```

Scan the QR with **Expo Go** on a phone, or run an emulator. You'll see house ads served
from `a.golden-krill.com` (this demo sends an unknown caller id, so it gets house-studio
ads - exactly the "no advertising id -> house ads" path).

## What to look at

- **Banner** - rotates on a timer; **Rotate** forces the next creative now.
- **Interstitial** - full screen; close appears after a few seconds.
- **Rewarded** - countdown starts after the image loads; reward granted on completion.

Console shows `[GoldenKrill] ...` decision logs (`GoldenKrillDebug.enabled = true`).

## Notes

- Needs the house studio to have approved creatives, or the slots collapse (correct behavior).
- This is a demo, not production wiring - a real app puts its paid network behind the
  `paidBuilder` / `paid:` callbacks (see the SDK [README](../../react-native/README.md)).
