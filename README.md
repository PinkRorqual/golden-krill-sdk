<p align="center">
  <img src="assets/goldenkrill-logo.png" alt="Golden Krill" width="120">
</p>

# Golden Krill SDK

Open-source client SDKs for the [Golden Krill](https://golden-krill.com) cross-promotion
network. When an app's paid ad network (AdMob / AppLovin) returns **no fill**, Golden
Krill fills the slot with a **house ad** - a cross-promo for another participating app -
instead of a blank. No money changes hands for the ads: you show others, others show you.

**Open source on purpose.** You embed this in your app, so you can read and audit
exactly what it does. The SDKs call only the documented endpoints, send **app-keyed
aggregate** beacons, and use **no advertising ID and no per-user profiling**. Build from
source; releases publish a SHA-256 to verify the artifact.

- **API contract (the source of truth):** https://golden-krill.com/api/docs (OpenAPI 3.1)

## SDKs

Each platform is a thin client of the **same published API**. The contract - not a shared
binary - is what keeps them consistent.

| Path | Platform | Status |
|---|---|---|
| [`flutter/`](flutter/) | Flutter / Dart | available |
| [`react-native/`](react-native/) | React Native | available |
| [`unity/`](unity/) | Unity (C#) | core available |
| `rust/` | Rust core / native | planned |

> Flutter and React Native are production grade, sharing the same serving model, config,
> and GK1 wire, tested on Android devices and verified on the iOS simulator. The surface
> differs per platform (Flutter offers a one-call `show()` orchestration; React Native and
> Unity use the a-la-carte calls plus components, see each folder's guide). Unity ships the
> same validated core logic (its headless tests pass); its uGUI creative components are
> provisional and
> undergoing an editor polish pass. Rust is a roadmap idea, not started.

Each SDK folder has its own platform-specific integration guide. The serving model below is
the same everywhere; the way you call it differs per platform (see the note after the example).

## The model

Hold one client next to your own ads code and use it at three moments. Each is enabled
independently by the per-app config you set in the portal; any call returns *nothing* if
there's no eligible ad or the frequency cap is hit (then you show nothing - never a blank).

> The one-call `show()` below is the **Flutter** convenience form. React Native and Unity
> wire the same reserve, paid, fallback model with the a-la-carte `reserveAd` / `fallbackAd`
> calls plus the banner, interstitial, and rewarded components. See those folders' guides.

```text
startup:
    gk = GoldenKrill(package = "com.you.app")
    gk.ensureReady(slot = "interstitial")        # fetch config + ads (cached, offline-safe)

at an eligible interstitial moment - ONE call orchestrates everything:
    gk.show("interstitial",
            paid    = () => yourNetwork.tryShow(),  # return true if it showed, false on no-fill
            present = (ad) => render(ad))            # how to display a house creative
    # gk runs, using config: reserve (1-in-N) -> your paid ad -> fallback + own-studio.
    # returns true if anything was shown; false -> you showed nothing (collapse the slot).

render(ad):
    show ad.image at the slot size
    on tap: open ad.store          # a /c tracker URL: 302s to the store, counts the click
    # the impression was already recorded; never modify ad.store
```

You hand it your **paid attempt** and how to **present** a creative; it owns the
reserve/fallback/own decision from config. For banners, drop in `GoldenKrillBanner`,
which owns its own rotation loop: time-based reserve (ours ~1 unit in N) + fallback +
auto-refresh. You give it a `paidBuilder` (loads your paid banner, returns it if filled,
null on no-fill); on reserve units it simply doesn't request paid (policy-safe).

**Advanced (à-la-carte):** if you want manual control, the same decisions are exposed as the
async `await reserveAd(slot)` (call before paid) and `await fallbackAd(slot)` (call on no-fill).
Each fetches fresh from the server per display (the server randomizes + picks; no client-side
rotation), with a 1h failover copy used only when a fetch fails.

## Slots

`banner` (640x100), `mrec` (600x500), `interstitial` (1080x1920, also used for rewarded).

## Rules of the road

- Use the SDK only at a **real ad moment** - never on a timer or at startup.
- It self-limits (per-session cap + cooldown from config); *nothing* is a normal, frequent
  result - collapse the slot.
- It is **fallback/reserve only** - it never changes when or where you request paid ads.
- It records impressions/clicks itself (app-keyed aggregate, no user data); don't add any
  tracking around it.

## Adding a new SDK

Implement the published OpenAPI contract for the platform, mirror the model above, and
match the shared conformance behaviour (GK1 decode + the serving decisions). The contract
+ shared test vectors keep every SDK consistent without a shared binary.

## License

[Apache-2.0](LICENSE). Free to use, modify, and redistribute (including commercially);
just keep the notices. Copyright Crypto Ventures SRL.
