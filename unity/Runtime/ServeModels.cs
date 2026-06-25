using System;
using System.Collections.Generic;

namespace GoldenKrill
{
    /// One ad row: a bare positional tuple [id, image, store]. `store` is a /c tracker URL
    /// (open verbatim; it 302s to the store and counts the click), or a direct URL in test mode.
    public sealed class AdItem
    {
        public int Id;
        public string Image;
        public string Store; // may be null

        /// Parse a [id, image, store] row (tolerates extra trailing slots). Null if malformed.
        public static AdItem FromList(object row)
        {
            if (!(row is List<object> list) || list.Count < 2) return null;
            if (!(list[0] is double idD) || !(list[1] is string image)) return null;
            string store = list.Count > 2 && list[2] is string s ? s : null;
            return new AdItem { Id = (int)idD, Image = image, Store = store };
        }
    }

    /// The two-tier /ads response: Ads = cross-promo, Own = own-studio last resort. IsTest is
    /// the additive GK1 `t` tag (true only for a test-mode bundle); render the TEST AD normally.
    public sealed class AdBundle
    {
        public List<AdItem> Ads = new List<AdItem>();
        public List<AdItem> Own = new List<AdItem>();
        public string Nonce = "";
        public bool IsTest;

        public static readonly AdBundle Empty = new AdBundle();

        public static AdBundle FromJson(object json)
        {
            var map = json as Dictionary<string, object>;
            var b = new AdBundle();
            if (map == null) return b;
            b.Ads = Items(Get(map, "a"));
            b.Own = Items(Get(map, "o"));
            b.Nonce = Get(map, "n") is string n ? n : "";
            b.IsTest = Get(map, "t") is double t && t != 0;
            return b;
        }

        private static List<AdItem> Items(object x)
        {
            var outList = new List<AdItem>();
            if (x is List<object> list)
                foreach (var row in list)
                {
                    var it = AdItem.FromList(row);
                    if (it != null) outList.Add(it);
                }
            return outList;
        }

        internal static object Get(Dictionary<string, object> map, string key) =>
            map != null && map.TryGetValue(key, out var v) ? v : null;
    }

    /// Per-app serving config from /config. Missing fields fall back to house-friendly defaults.
    public sealed class ServeConfig
    {
        public bool ReserveShare;
        public int ReserveOneIn;
        public bool FallbackFill;
        public bool FillOwnAds;
        public int HouseCooldownSec;
        public int MaxPerSession;
        public int OwnAdsCooldownMin;
        public int BannerRotationSec; // 0 = SDK jitters ~55-65s
        public int RewardedSeconds;   // 0 = SDK default 10s
        public double AdBadgeChance;  // 0..1 probability of drawing the disclosure badge
        public string BadgeUrl;       // '' -> SDK default (Endpoints.BadgeInfoUrl)
        public bool BannerSdkRefresh; // false = Regular (passive), true = Advanced (SDK-driven)

        /// EXACT defaults, matching Flutter/RN/server (reserveOneIn=4, fallbackFill=true,
        /// houseCooldownSec=240, maxPerSession=3, fillOwnAds=false).
        public static ServeConfig Defaults => new ServeConfig
        {
            ReserveShare = true,
            ReserveOneIn = 4,
            FallbackFill = true,
            FillOwnAds = false,
            HouseCooldownSec = 240,
            MaxPerSession = 3,
            OwnAdsCooldownMin = 5,
            BannerRotationSec = 0,
            RewardedSeconds = 0,
            AdBadgeChance = 0,
            BadgeUrl = "",
            BannerSdkRefresh = false,
        };

        public static ServeConfig FromJson(object json)
        {
            var map = json as Dictionary<string, object>;
            var d = Defaults;
            if (map == null) return d;
            return new ServeConfig
            {
                ReserveShare = B(map, "reserve_share", d.ReserveShare),
                ReserveOneIn = I(map, "reserve_one_in", d.ReserveOneIn),
                FallbackFill = B(map, "fallback_fill", d.FallbackFill),
                FillOwnAds = B(map, "fill_own_ads", d.FillOwnAds),
                HouseCooldownSec = I(map, "house_cooldown_sec", d.HouseCooldownSec),
                MaxPerSession = I(map, "max_per_session", d.MaxPerSession),
                OwnAdsCooldownMin = I(map, "own_ads_cooldown_min", d.OwnAdsCooldownMin),
                BannerRotationSec = I(map, "banner_rotation_sec", 0),
                RewardedSeconds = I(map, "rewarded_seconds", 0),
                AdBadgeChance = AdBundle.Get(map, "ad_badge_chance") is double a ? a : 0,
                BadgeUrl = AdBundle.Get(map, "badge_url") is string s ? s : "",
                BannerSdkRefresh = B(map, "banner_sdk_refresh", d.BannerSdkRefresh),
            };
        }

        private static bool B(Dictionary<string, object> m, string k, bool d) =>
            AdBundle.Get(m, k) is bool v ? v : d;

        private static int I(Dictionary<string, object> m, string k, int d) =>
            AdBundle.Get(m, k) is double v ? (int)Math.Truncate(v) : d;

        // --- Pure helpers (parity with models.ts) ---

        /// Roll whether to draw the disclosure badge on this display (probability AdBadgeChance).
        public bool RollAdBadge(Func<double> rnd) =>
            AdBadgeChance > 0 && rnd() < AdBadgeChance;

        /// Effective banner rotation interval (ms): configured value if set, else jittered ~55-65s.
        public int BannerRotationMs(Func<double> rnd)
        {
            int sec = BannerRotationSec > 0 ? BannerRotationSec : 55 + (int)(rnd() * 11);
            return sec * 1000;
        }

        /// Effective rewarded countdown (ms): configured value if set, else the 10s default.
        public int RewardedMs() => (RewardedSeconds > 0 ? RewardedSeconds : 10) * 1000;
    }
}
