using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace GoldenKrill
{
    /// The integration facade. One instance per app, held next to your own ads code. Mirrors the
    /// Flutter + React Native SDKs.
    ///
    /// Serving model: every display hits the server fresh. The server returns ONE random
    /// cross-promo + ONE random own-studio ad and randomizes per call, so rotation lives
    /// server-side; the SDK does not cache for rotation. The only cache is an offline failover:
    /// the last successful response is reused (up to FailoverTtlMs) ONLY when a fetch fails. A
    /// successful but empty response is a real no-fill ("empty is empty"). Picks return null ->
    /// show nothing (collapse the slot). Never throws.
    public sealed class GoldenKrillAds
    {
        public const long FailoverTtlMs = 60L * 60 * 1000; // 1h
        public const int AttestationTimeoutMs = 4000;

        private readonly GoldenKrillClient _client;
        private readonly Func<long> _now;
        private ServeConfig _cfg = ServeConfig.Defaults;
        private bool _cfgLoaded;
        private readonly Dictionary<string, (AdBundle bundle, long at)> _failover =
            new Dictionary<string, (AdBundle, long)>();

        private int _eligible;          // interstitial reserve cadence
        private int _rewardedEligible;  // rewarded reserve cadence
        private long? _lastGkAt;        // GK pool cooldown clock (HouseCooldownSec)
        private long? _lastOwnAt;       // studio own pool cooldown clock (OwnAdsCooldownMin)

        /// Set whenever rewarded availability changes; bind a "watch ad" button to it.
        public Action<bool> OnRewardedAvailable;

        /// Optional host hook to forward an attestation token on beacons (parity with Flutter/RN).
        /// Null = no attestation. The host mints + caches the token; the SDK only forwards it. A
        /// null/throwing/slow provider never blocks or drops a beacon. The SDK never mints a token.
        public Func<string, Task<string>> AttestationProvider;

        public GoldenKrillAds(string pkg, GoldenKrillOptions opts = null)
        {
            opts = opts ?? new GoldenKrillOptions();
            _client = new GoldenKrillClient(pkg, opts);
            _now = opts.NowMs ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            AttestationProvider = opts.AttestationProvider;
        }

        /// Test convenience ctor for injecting a prebuilt client (staging/tests).
        public GoldenKrillAds(GoldenKrillClient client, Func<long> nowMs = null)
        {
            _client = client;
            _now = nowMs ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        }

        public ServeConfig Config => _cfg;
        public bool HasSlot(string slot) => _failover.ContainsKey(slot);

        public async Task EnsureReady(string slot = "banner", string lang = "en")
        {
            if (!_cfgLoaded)
            {
                _cfg = await _client.LoadConfig();
                _cfgLoaded = true;
            }
            await FetchBundle(slot, lang); // warm: seeds failover + rewarded availability (no impression)
        }

        private async Task<AdBundle> FetchBundle(string slot, string lang)
        {
            var r = await _client.FetchAds(slot, lang);
            if (r.ok)
            {
                _failover[slot] = (r.bundle, _now());
                RefreshRewarded();
                return r.bundle;
            }
            if (_failover.TryGetValue(slot, out var f) && _now() - f.at < FailoverTtlMs)
                return f.bundle;
            return AdBundle.Empty;
        }

        private AdItem Record(string slot, AdItem ad, string nonce)
        {
            Beacon(new List<object> {
                new Dictionary<string, object> { { "creative", ad.Id }, { "slot", slot }, { "kind", "view" } }
            }, nonce);
            return ad;
        }

        private void Beacon(List<object> events, string nonce)
        {
            _ = PostBeacon(events, nonce); // fire-and-forget
        }

        private async Task PostBeacon(List<object> events, string nonce)
        {
            string token = await ResolveToken(nonce);
            _client.PostEvents(events, nonce, token);
        }

        /// Resolve the host attestation token, or "" on null/throw/timeout, so a slow or failing
        /// provider never stalls or drops the beacon.
        private async Task<string> ResolveToken(string nonce)
        {
            var provider = AttestationProvider;
            if (provider == null) return "";
            try
            {
                Task<string> task = provider(nonce);
                Task done = await Task.WhenAny(task, Task.Delay(AttestationTimeoutMs));
                if (done != task) return ""; // timeout
                return (await task) ?? "";
            }
            catch { return ""; }
        }

        private bool GkCooldownOk() =>
            _lastGkAt == null || (_now() - _lastGkAt.Value) / 1000 >= _cfg.HouseCooldownSec;

        private bool OwnCooldownOk() =>
            _lastOwnAt == null || (_now() - _lastOwnAt.Value) / 1000 >= _cfg.OwnAdsCooldownMin * 60;

        // --- Interstitial (count-based reserve + cooldown) ---

        /// RESERVE: call before the paid ad; returns a cross-promo on ~1-in-N moments, else null.
        public async Task<AdItem> ReserveAd(string slot, string lang = "en")
        {
            if (!_cfg.ReserveShare || _cfg.ReserveOneIn < 1) { _eligible++; return null; }
            bool should = _eligible % _cfg.ReserveOneIn == 0; // 1st, then every Nth
            _eligible++;
            if (!should) return null;
            var b = await FetchBundle(slot, lang);
            if (b.Ads.Count == 0) return null; // reserve serves the GK pool only
            _lastGkAt = _now();
            return Record(slot, b.Ads[0], b.Nonce);
        }

        /// FALLBACK: call on a paid no-fill. Pool 1 (GK) if FallbackFill + GK cooldown elapsed;
        /// else pool 2 (studio own) if its own cooldown elapsed. Two cooldowns so they don't spam.
        public async Task<AdItem> FallbackAd(string slot, string lang = "en")
        {
            var b = await FetchBundle(slot, lang);
            if (_cfg.FallbackFill && b.Ads.Count > 0 && GkCooldownOk())
            {
                _lastGkAt = _now();
                return Record(slot, b.Ads[0], b.Nonce);
            }
            if (b.Own.Count > 0 && OwnCooldownOk())
            {
                _lastOwnAt = _now();
                return Record(slot, b.Own[0], b.Nonce);
            }
            return null;
        }

        // --- Banner (time-based reserve; fill/cadence-gated, no cooldown) ---

        public bool BannerReserveTurn(int unit) =>
            _cfg.ReserveShare && _cfg.ReserveOneIn >= 1 && unit % _cfg.ReserveOneIn == 0;

        public async Task<AdItem> BannerHouse(string slot, string lang = "en")
        {
            var b = await FetchBundle(slot, lang);
            AdItem ad = b.Ads.Count > 0 ? b.Ads[0] : (b.Own.Count > 0 ? b.Own[0] : null);
            if (ad == null) return null;
            Beacon(new List<object> {
                new Dictionary<string, object> { { "creative", ad.Id }, { "slot", slot }, { "kind", "view" } }
            }, b.Nonce); // no cooldown stamp
            return ad;
        }

        // --- Rewarded (reuses the interstitial slot). Reserve = 1-in-N; the user-initiated
        //     fallback always serves (they asked for it) - no cooldown. ---

        public bool RewardedReady =>
            _failover.TryGetValue("interstitial", out var f) && (f.bundle.Ads.Count > 0 || f.bundle.Own.Count > 0);

        private void RefreshRewarded() => OnRewardedAvailable?.Invoke(RewardedReady);

        public async Task<AdItem> RewardedReserve(string lang = "en")
        {
            if (!_cfg.ReserveShare || _cfg.ReserveOneIn < 1) { _rewardedEligible++; return null; }
            bool should = _rewardedEligible % _cfg.ReserveOneIn == 0;
            _rewardedEligible++;
            if (!should) return null;
            var b = await FetchBundle("interstitial", lang);
            return b.Ads.Count > 0 ? Record("interstitial", b.Ads[0], b.Nonce) : null;
        }

        public async Task<AdItem> RewardedHouse(string lang = "en")
        {
            var b = await FetchBundle("interstitial", lang); // user-initiated: always serve what we have
            AdItem ad = b.Ads.Count > 0 ? b.Ads[0] : (b.Own.Count > 0 ? b.Own[0] : null);
            return ad != null ? Record("interstitial", ad, b.Nonce) : null;
        }

        /// New session (e.g. resume after long background): reset the reserve cadence + cooldown.
        /// The offline failover copy is kept (a cross-session safety net).
        public void ResetSession()
        {
            _eligible = 0;
            _rewardedEligible = 0;
            _lastGkAt = null;
            _lastOwnAt = null;
        }
    }
}
