# Golden Krill SDK - React Native

Cross-promotion ("house ads") for React Native. When your paid network (AdMob / AppLovin)
returns **no fill**, Golden Krill fills the slot with a promo for another participating app
instead of a blank. Same published API + `GK1` wire as the Flutter SDK; **no advertising id,
app-keyed aggregates only**.

- API contract (source of truth): https://golden-krill.com/api/docs

## Install

Peer deps: `react`, `react-native`. Optional `@react-native-async-storage/async-storage`
for a persistent on-device cache (without it the cache is in-memory for the session).

```jsonc
// package.json (git/source dependency)
"@goldenkrill/react-native": "github:PinkRorqual/golden-krill-sdk#path:react-native"
```

## Use

One instance, loaded once:
```ts
import { GoldenKrillAds } from '@goldenkrill/react-native';
const gk = new GoldenKrillAds('com.you.app');
await gk.ensureReady('banner');
await gk.ensureReady('interstitial'); // also serves rewarded
```

**Banner** - owns its rotation loop (time-based reserve + fallback + refresh). Give it a
`paidBuilder` that resolves your paid banner element, or `null` on no-fill (omit it for "no
paid network"). Reserve units never request paid (policy-safe):
```tsx
<GoldenKrillBanner ads={gk} slot="banner" height={50}
  paidBuilder={async () => (await admob.load()) ? <AdMobBanner/> : null} />
```

**Interstitial** - try your paid network first, then set `visible`:
```tsx
<GoldenKrillInterstitial ads={gk} visible={v} onClose={() => setV(false)} />
```

**Rewarded** - reserve -> paid -> house; countdown starts after the image loads, blocks
early exit, grants on completion:
```tsx
<GoldenKrillRewarded ads={gk} visible={v} onClose={(earned) => earned && grant()} />
```

The **1-in-N reserve** is honored on all three slots; rotation/length come from the portal
config. Turn on terse logs with `GoldenKrillDebug.enabled = true` (grep `[GoldenKrill]`).

## Demo

A runnable Expo demo lives at [`../demo/react-native`](../demo/react-native): the three ad
types on three screens, house-ads-only, with a **Rotate** button so you don't wait for the
banner timer. `cd demo/react-native && npm install && npm start`.

## Test mode

`testMode` makes the server return an always-fill **TEST AD** (even with no real inventory
or an unregistered app) and count nothing (no metric, reach, trust, or weight moves).

```ts
new GoldenKrillAds('com.you.app');                    // testMode defaults to __DEV__
new GoldenKrillAds('com.you.app', { testMode: false }); // force the real path (QA on a release build)
```

Default is `__DEV__` (true in a dev build, false in a release bundle), so you see TEST ADs
while developing and ship the real path automatically. **Never ship a release build with
`testMode` forced on.** It is metric hygiene, not a security boundary (a client can lie);
the real anti-fraud is the attestation/trust layer.

## Privacy + Apple App Review (iOS)

The SDK passes App Review cleanly as an embedded SDK: no IDFA, no device/advertising
identifier, no tracking, so it imposes **no ATT requirement** on your app (ATT is only for
your own paid ad SDK). It collects only anonymous, aggregate ad-interaction counts. A
canonical `PrivacyInfo.xcprivacy` ships at [`ios/PrivacyInfo.xcprivacy`](ios/PrivacyInfo.xcprivacy)
(`NSPrivacyTracking = false`, no tracking domains, ad-interaction not-linked + not-tracking,
no directly-used required-reason APIs). The SDK is a **pure-TypeScript package** (no native
iOS framework), so reflect these declarations in your app's own `PrivacyInfo.xcprivacy`; in
practice it adds nothing trackable. The App Attest passthrough (`attestationProvider`)
degrades gracefully: a missing/throwing/slow provider still beacons, without attestation, and
never blocks serving. All calls are HTTPS (ATS-clean). CocoaPods/Xcode integration is
Mac-only to verify (test-archive a host app and check the privacy report).

## License

[Apache-2.0](../LICENSE). Copyright Crypto Ventures SRL.
