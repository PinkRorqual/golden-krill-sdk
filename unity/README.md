# Golden Krill SDK for Unity (C#)

Source-shipped, native-free cross-promotion SDK: no DLL, no Rust, no advertising id. Unity
compiles the `.cs` itself. Full feature parity with the Flutter and React Native SDKs.

## Install (UPM via git URL)

Unity → Window → Package Manager → Add package from git URL:

```
https://github.com/PinkRorqual/golden-krill-sdk.git?path=/unity
```

## Quick start

```csharp
using GoldenKrill;

var ads = GoldenKrillUnity.Create("com.you.game");   // testMode defaults to Debug.isDebugBuild
await ads.EnsureReady("interstitial");

// Before your paid ad: reserve ~1-in-N moments for a house ad.
var reserved = await ads.ReserveAd("interstitial");
// On a paid no-fill: fall back to a house ad.
var fallback = await ads.FallbackAd("interstitial");

// Render (uGUI components): banner/mrec on a RawImage, interstitial/rewarded fullscreen.
bannerRawImage.GetComponent<GoldenKrillBanner>().Show(fallback, showBadge: true);
```

`GoldenKrillUnity.Create(package, baseUrl, testMode, attestationProvider)` keeps the serving
base + package injectable (staging/tests). `baseUrl = null` uses `https://a.golden-krill.com`.

## Test mode

`testMode` defaults to `Debug.isDebugBuild` (the C# equivalent of Flutter `kDebugMode` / RN
`__DEV__`): an always-fill **TEST AD** in a development build, the real path in release. Override
it via `GoldenKrillUnity.Create(pkg, testMode: false)` to QA the real path on a release build.
**Never ship a release build with testMode forced on.** It is metric hygiene, not a security
boundary (a client can lie); the real anti-fraud is the attestation/trust layer.

## Attestation passthrough (optional, native-free)

Pass `attestationProvider: async nonce => yourHostToken` to `Create`. The SDK forwards the
opaque token (which YOUR app mints via Play Integrity / App Attest) on the beacon, bound to the
per-serve nonce. A null/throwing/slow provider still beacons, without attestation, and never
blocks serving. The SDK never mints a token.

## Privacy

App-keyed aggregate counters only: no advertising id, no per-user profiling. The only on-device
identifier is an anonymous, weekly-rotating reach token kept in PlayerPrefs. All calls are HTTPS.

## Tests

Two runners:

- **Unity Test Framework (NUnit)** for the full suite incl. the conformance vector. In the
  Editor: Window → General → Test Runner → EditMode → Run. Batch mode:
  ```
  Unity -batchmode -runTests -projectPath <your-project> -testPlatform EditMode \
        -testResults results.xml -quit
  ```
- **Host `dotnet test`** for the pure core (no Unity needed; host stays clean). The core has no
  UnityEngine dependency (HTTP/storage/clock are injected), so it runs in a .NET SDK container:
  ```
  docker run --rm -v "$PWD":/work -w /work/<throwaway-test-proj> \
    mcr.microsoft.com/dotnet/sdk:8.0 dotnet test
  ```
  (A csproj that `Compile`-includes `unity/Runtime/*.cs` + `unity/Tests/*.cs` + NUnit. This is how
  the SDK was validated: 24 tests green, including byte-exact GK1 conformance vs the canonical
  vector.) The Unity-only UI components (`Runtime/Unity/`) compile + run only in Unity.

## UI status (read this)

The **core logic is validated headless** (24 tests). The **uGUI creative components are NOT
yet verified in an actual Unity render** - they have not been compiled or drawn by Unity, so
treat them as provisional and expect a visual polish pass, the same way the Flutter and React
Native UIs needed one. Known traps are already handled in code: the legacy font is loaded with
a version fallback (`LegacyRuntime.ttf` then `Arial.ttf`, else the badge/close text is
invisible), and an `EventSystem` is created if the scene lacks one (else buttons are dead).
What a Unity pass still must confirm:

- Your **Canvas needs a GraphicRaycaster** (a standard `Canvas` has one) or no taps register.
- Badge / close / countdown **anchors + sizes** look right at each slot size.
- The RawImage shows a brief white box while the texture loads (add a placeholder if it bothers you).
- Legacy `Text` is used (works everywhere); swap to TextMeshPro if you prefer.

Run it in **Editor Play mode** to do this pass quickly (no APK/emulator needed).

## Parity matrix (Flutter / RN public symbol → Unity C#)

| Flutter / RN | Unity C# | Notes |
|---|---|---|
| `CatalogCodec.encode/decode` (Dart) / `gk1.encode/decode` (TS) | `Gk1.Encode/Decode` | byte-identical (conformance vector) |
| `AdItem`, `AdItem.fromList` | `AdItem`, `AdItem.FromList` | tuple `[id,image,store]`, junk-tolerant |
| `AdBundle`, `AdBundle.fromJson`, `.empty` | `AdBundle`, `AdBundle.FromJson`, `.Empty` | adds `IsTest` (reads the additive GK1 `t` tag, per step 16) |
| `ServeConfig`, `.defaults`, `fromJson` | `ServeConfig`, `.Defaults`, `FromJson` | exact defaults (reserveOneIn=4, fallbackFill=true, houseCooldownSec=240, maxPerSession=3) |
| `rollAdBadge`, `bannerRotationMs`, `rewardedMs` | `ServeConfig.RollAdBadge/BannerRotationMs/RewardedMs` | pure helpers |
| `GoldenKrillClient` (loadConfig/fetchAds/postEvents) | `GoldenKrillClient` (`LoadConfig`/`FetchAds`/`PostEvents`) | TTL cache, weekly device token, no ad id |
| `ClientOptions` (fetchImpl/storage/now/base/testMode) | `GoldenKrillOptions` (Http/Storage/NowMs/Rng/Base/Store/TestMode) | all injectable |
| `GoldenKrillAds` façade | `GoldenKrillAds` | reserve/fallback/banner/rewarded + cooldowns + `ResetSession` |
| `attestationProvider` | `AttestationProvider` (`Func<string,Task<string>>`) | null/throw/timeout safe |
| `onRewardedAvailable`, `rewardedReady` | `OnRewardedAvailable`, `RewardedReady` | |
| `FAILOVER_TTL_MS`, `ATTESTATION_TIMEOUT_MS` | `FailoverTtlMs`, `AttestationTimeoutMs` | same values |
| testMode default `kDebugMode`/`__DEV__` | `GoldenKrillUnity.Create` → `Debug.isDebugBuild` | the Unity entry sets the default |
| banner/mrec/interstitial/rewarded widgets | `GoldenKrillBanner`/`GoldenKrillMrec`/`GoldenKrillInterstitial`/`GoldenKrillRewarded` | uGUI MonoBehaviours + disclosure badge |

**Deliberately different / omitted:**
- **`MiniJson`** (Unity-only): the Dart/TS SDKs use the platform JSON parser; C# ships a tiny
  dependency-free parser to stay native-free (no Newtonsoft).
- **HTTP/storage adapters are explicit interfaces** (`IGoldenKrillHttp`, `IGoldenKrillStorage`),
  mirroring RN's injectable `fetchImpl`/`storage`; the Unity defaults are `UnityWebRequest` +
  `PlayerPrefs`.
- **`AdBundle.IsTest`** is new vs Flutter/RN (which don't expose the `t` tag); added because step
  16 asks Unity to read it. Additive, harmless.
- No Rust core, no precompiled binary, no native plugin (by design).
