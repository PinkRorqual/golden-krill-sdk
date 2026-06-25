using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading.Tasks;

namespace GoldenKrill
{
    /// No-op HTTP: every GET fails (transport error) and POST does nothing. The default when
    /// no HTTP adapter is wired, so the SDK degrades to cache/defaults instead of throwing.
    internal sealed class NoopHttp : IGoldenKrillHttp
    {
        public Task<HttpResult> GetAsync(string url) => Task.FromResult(new HttpResult(0, null));
        public Task PostAsync(string url, string jsonBody) => Task.CompletedTask;
    }

    /// Talks to the serving API: GK1 fetch + last-good cache + fire-and-forget beacons. Never
    /// throws; degrades to cache then defaults/empty. App-keyed aggregate only: NO advertising
    /// id, only an anonymous weekly-rotating device token for approximate distinct-device reach.
    public sealed class GoldenKrillClient
    {
        public readonly string Pkg;
        public readonly bool TestMode;

        private readonly IGoldenKrillHttp _http;
        private readonly IGoldenKrillStorage _storage;
        private readonly Func<long> _now;
        private readonly Func<double> _rng;
        private readonly string _base;
        private readonly string _store;
        private readonly long _configTtlMs;

        private const string Abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        private const long DeviceTtlMs = 7L * 24 * 60 * 60 * 1000; // weekly rotation

        public GoldenKrillClient(string pkg, GoldenKrillOptions opts = null)
        {
            opts = opts ?? new GoldenKrillOptions();
            Pkg = pkg;
            _http = opts.Http ?? new NoopHttp();
            _storage = opts.Storage ?? new MemoryStorage();
            _now = opts.NowMs ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            var rndGen = new Random();
            _rng = opts.Rng ?? (() => rndGen.NextDouble());
            _base = string.IsNullOrEmpty(opts.Base) ? Endpoints.ServingBase : opts.Base;
            _store = string.IsNullOrEmpty(opts.Store) ? "play" : opts.Store;
            _configTtlMs = opts.ConfigTtlMs > 0 ? opts.ConfigTtlMs : Endpoints.ConfigTtlMs;
            TestMode = opts.TestMode ?? false;
        }

        private string CfgKey => "gk_cfg_v1_" + Pkg;

        /// Per-app serving config. Fresh -> last-good -> compiled defaults. Never throws.
        public async Task<ServeConfig> LoadConfig()
        {
            object map = await CachedJson(CfgKey, Endpoints.ConfigUrl(Pkg, _base, TestMode), _configTtlMs);
            return map == null ? ServeConfig.Defaults : ServeConfig.FromJson(map);
        }

        /// Per-display ad fetch. ok == false means the fetch FAILED (caller may failover);
        /// ok == true with an empty bundle is a real no-fill ("empty is empty"). Never throws.
        public async Task<(AdBundle bundle, bool ok)> FetchAds(string slot = "banner", string lang = "en")
        {
            string body = await FetchText(Endpoints.AdsUrl(Pkg, slot, lang, _store, _base, TestMode));
            if (body == null) return (AdBundle.Empty, false);
            object json = Parse(body);
            if (json == null) return (AdBundle.Empty, false);
            return (AdBundle.FromJson(json), true);
        }

        /// Fire-and-forget impression/tap beacons (app-keyed; no advertising id). Forwards the
        /// optional host attestation token + the per-serve nonce. test:true is added in test mode.
        public void PostEvents(List<object> events, string nonce = "", string attestation = "")
        {
            _ = PostEventsAsync(events, nonce, attestation);
        }

        private async Task PostEventsAsync(List<object> events, string nonce, string attestation)
        {
            try
            {
                var body = new Dictionary<string, object>
                {
                    { "host", Pkg },
                    { "attestation", attestation ?? "" },
                    { "device", DeviceToken() },
                    { "nonce", nonce ?? "" },
                    { "events", events },
                };
                if (TestMode) body["test"] = true; // test beacons are accepted but counted nowhere
                await _http.PostAsync(Endpoints.EventsUrl(_base), MiniJson.Serialize(body));
            }
            catch { /* beacons never affect the app */ }
        }

        private async Task<object> CachedJson(string blobKey, string url, long ttlMs)
        {
            string atKey = blobKey + "_at";
            string at = _storage.Get(atKey);
            string cached = _storage.Get(blobKey);
            bool fresh = at != null && _now() - long.Parse(at, CultureInfo.InvariantCulture) < ttlMs;
            if (fresh && cached != null) return Parse(cached);
            string body = await FetchText(url);
            if (body != null)
            {
                _storage.Set(blobKey, body);
                _storage.Set(atKey, _now().ToString(CultureInfo.InvariantCulture));
                return Parse(body);
            }
            if (cached != null) return Parse(cached); // fetch failed -> last-good cache
            return null;
        }

        private static object Parse(string blob)
        {
            try { return MiniJson.Parse(Gk1.Decode(blob)); }
            catch { return null; }
        }

        private async Task<string> FetchText(string url)
        {
            try
            {
                HttpResult r = await _http.GetAsync(url);
                if (r.Status == 200 && !string.IsNullOrEmpty(r.Body)) return r.Body;
                return null;
            }
            catch { return null; }
        }

        /// Anonymous reach token: a random value kept in this app's own storage and rotated
        /// weekly, so it can never track a person or cross-link apps. Not an advertising id.
        private string DeviceToken()
        {
            string tok = _storage.Get("gk_did_v1");
            string at = _storage.Get("gk_did_at_v1");
            if (tok != null && at != null &&
                _now() - long.Parse(at, CultureInfo.InvariantCulture) < DeviceTtlMs)
                return tok;
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < 22; i++) sb.Append(Abc[(int)(_rng() * Abc.Length)]);
            string fresh = sb.ToString();
            _storage.Set("gk_did_v1", fresh);
            _storage.Set("gk_did_at_v1", _now().ToString(CultureInfo.InvariantCulture));
            return fresh;
        }
    }
}
