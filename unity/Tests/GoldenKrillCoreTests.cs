using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Threading.Tasks;
using NUnit.Framework;

namespace GoldenKrill.Tests
{
    // A fake HTTP that records GETs/POSTs and returns programmed responses. Keeps the core
    // testable without UnityWebRequest or a real server (serving base + package injectable).
    internal sealed class FakeHttp : IGoldenKrillHttp
    {
        public readonly List<string> Gets = new List<string>();
        public readonly List<string> Posts = new List<string>();
        public Func<string, HttpResult> OnGet;

        public Task<HttpResult> GetAsync(string url)
        {
            Gets.Add(url);
            return Task.FromResult(OnGet != null ? OnGet(url) : new HttpResult(0, null));
        }

        public Task PostAsync(string url, string jsonBody) { Posts.Add(jsonBody); return Task.CompletedTask; }
    }

    internal static class Util
    {
        // Build a serving FakeHttp: config -> the given config map; ads -> the given bundle map.
        public static FakeHttp Serving(Dictionary<string, object> config, Dictionary<string, object> bundle)
        {
            return new FakeHttp
            {
                OnGet = url => url.Contains("/config/")
                    ? new HttpResult(200, Gk1.Encode(MiniJson.Serialize(config)))
                    : new HttpResult(200, Gk1.Encode(MiniJson.Serialize(bundle)))
            };
        }

        public static List<object> Row(int id, string img, string store) =>
            new List<object> { (double)id, img, store };
    }

    [TestFixture]
    public class Gk1Tests
    {
        [Test]
        public void RoundTrip()
        {
            string s = "{\"a\":[[1,\"img\",\"store\"]],\"o\":[]}";
            Assert.AreEqual(s, Gk1.Decode(Gk1.Encode(s)));
        }

        [Test]
        public void RawJsonPassesThrough()
        {
            Assert.AreEqual("{\"raw\":1}", Gk1.Decode("{\"raw\":1}")); // no GK1. prefix -> verbatim
            Assert.IsTrue(Gk1.Encode("{}").StartsWith("GK1."));
        }

        [Test]
        public void FrozenSingleValue() // identical bytes to the Python/Dart/TS pins
        {
            Assert.AreEqual("GK1.C0sYSRdDEg==", Gk1.Encode("{\"v\":1}"));
        }
    }

    [TestFixture]
    public class ConformanceTests
    {
        // The canonical hash recorded in conformance/README.md. The vendored copy must match it,
        // and C# must decode/encode every case byte-exactly (proving parity with Dart/TS/Python).
        private const string Canonical = "8064704da42255c923cd0a041f2b9eff265a9339e059bbc997354e43ed81cbe6";

        private static string VectorPath()
        {
            string env = Environment.GetEnvironmentVariable("GK1_VECTORS");
            if (!string.IsNullOrEmpty(env) && File.Exists(env)) return env;
#if UNITY_2021_3_OR_NEWER
            // As a UPM package the files are under Packages/; as copied source they are under
            // Assets/. Try the package path, then search Assets so either setup works.
            string pkg = Path.Combine(UnityEngine.Application.dataPath, "..", "Packages",
                "com.pinkrorqual.goldenkrill", "Tests", "gk1_vectors.json");
            if (File.Exists(pkg)) return pkg;
            var hits = Directory.GetFiles(UnityEngine.Application.dataPath, "gk1_vectors.json", SearchOption.AllDirectories);
            if (hits.Length > 0) return hits[0];
#endif
            foreach (var p in new[]
            {
                Path.Combine(AppContext.BaseDirectory, "gk1_vectors.json"),
                Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "gk1_vectors.json"),
            })
                if (File.Exists(p)) return p;
            throw new FileNotFoundException("gk1_vectors.json not found (set GK1_VECTORS)");
        }

        [Test]
        public void VendoredCopyMatchesCanonicalHash()
        {
            byte[] bytes = File.ReadAllBytes(VectorPath());
            using (var sha = SHA256.Create())
            {
                string hex = BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
                Assert.AreEqual(Canonical, hex, "vendored gk1_vectors.json drifted from the canonical hash");
            }
        }

        [Test]
        public void EveryCaseDecodesAndEncodesByteExact()
        {
            var doc = (Dictionary<string, object>)MiniJson.Parse(File.ReadAllText(VectorPath()));
            var cases = (List<object>)doc["cases"];
            Assert.IsNotEmpty(cases);
            foreach (Dictionary<string, object> c in cases)
            {
                string name = (string)c["name"];
                string json = (string)c["json"];
                string blob = (string)c["gk1"];
                Assert.AreEqual(json, Gk1.Decode(blob), $"decode mismatch: {name}");
                Assert.AreEqual(blob, Gk1.Encode(json), $"encode mismatch: {name}");
            }
        }
    }

    [TestFixture]
    public class ModelTests
    {
        [Test]
        public void AdItemTolerance()
        {
            Assert.IsNull(AdItem.FromList(new List<object> { (double)1 }));        // too short
            Assert.IsNull(AdItem.FromList(new List<object> { "x", "y" }));          // id not number
            var ok = AdItem.FromList(Util.Row(7, "img", "store"));
            Assert.AreEqual(7, ok.Id);
            Assert.AreEqual("store", ok.Store);
            var noStore = AdItem.FromList(new List<object> { (double)7, "img" });
            Assert.IsNull(noStore.Store);
        }

        [Test]
        public void BundleParseDropsJunkRows()
        {
            var json = MiniJson.Parse("{\"a\":[[1,\"i\",\"s\"],[\"bad\"]],\"o\":[[2,\"i2\"]],\"n\":\"NONCE\",\"t\":1}");
            var b = AdBundle.FromJson(json);
            Assert.AreEqual(1, b.Ads.Count);  // the junk ["bad"] row dropped
            Assert.AreEqual(2, b.Own[0].Id);
            Assert.AreEqual("NONCE", b.Nonce);
            Assert.IsTrue(b.IsTest);          // additive t tag
        }

        [Test]
        public void ConfigDefaultsExactlyMatch()
        {
            var d = ServeConfig.Defaults;
            Assert.AreEqual(4, d.ReserveOneIn);
            Assert.IsTrue(d.FallbackFill);
            Assert.AreEqual(240, d.HouseCooldownSec);
            Assert.AreEqual(3, d.MaxPerSession);
            Assert.IsFalse(d.FillOwnAds);
            // Missing fields fall back to defaults.
            var c = ServeConfig.FromJson(MiniJson.Parse("{\"reserve_one_in\":2}"));
            Assert.AreEqual(2, c.ReserveOneIn);
            Assert.AreEqual(240, c.HouseCooldownSec);
        }

        [Test]
        public void Helpers()
        {
            var c = ServeConfig.Defaults;
            c.AdBadgeChance = 0.5;
            Assert.IsTrue(c.RollAdBadge(() => 0.1));   // 0.1 < 0.5 -> draw
            Assert.IsFalse(c.RollAdBadge(() => 0.9));
            c.BannerRotationSec = 30;
            Assert.AreEqual(30000, c.BannerRotationMs(() => 0));
            c.BannerRotationSec = 0;
            Assert.AreEqual(55000, c.BannerRotationMs(() => 0)); // jitter floor at rnd=0
            c.RewardedSeconds = 0;
            Assert.AreEqual(10000, c.RewardedMs());
            c.RewardedSeconds = 7;
            Assert.AreEqual(7000, c.RewardedMs());
        }
    }

    [TestFixture]
    public class ClientTests
    {
        private static GoldenKrillOptions Opts(FakeHttp http, IGoldenKrillStorage store, Func<long> now, Func<double> rng = null) =>
            new GoldenKrillOptions { Http = http, Storage = store, NowMs = now, Rng = rng ?? (() => 0.0) };

        [Test]
        public async Task ConfigTtlCacheHitAndMiss()
        {
            long t = 1000;
            var http = new FakeHttp { OnGet = _ => new HttpResult(200, Gk1.Encode("{\"reserve_one_in\":9}")) };
            var c = new GoldenKrillClient("com.x", Opts(http, new MemoryStorage(), () => t));
            var cfg1 = await c.LoadConfig();
            Assert.AreEqual(9, cfg1.ReserveOneIn);
            Assert.AreEqual(1, http.Gets.Count);
            await c.LoadConfig();                       // within TTL -> cache hit, no new GET
            Assert.AreEqual(1, http.Gets.Count);
            t += Endpoints.ConfigTtlMs + 1;             // expire
            await c.LoadConfig();
            Assert.AreEqual(2, http.Gets.Count);        // refetched
        }

        [Test]
        public async Task FetchAdsEmptyVsError()
        {
            var ok = new GoldenKrillClient("com.x", Opts(
                new FakeHttp { OnGet = _ => new HttpResult(200, Gk1.Encode("{\"a\":[],\"o\":[]}")) },
                new MemoryStorage(), () => 0));
            var rOk = await ok.FetchAds("banner");
            Assert.IsTrue(rOk.ok);                       // success...
            Assert.AreEqual(0, rOk.bundle.Ads.Count);    // ...but empty (real no-fill)

            var err = new GoldenKrillClient("com.x", Opts(
                new FakeHttp { OnGet = _ => new HttpResult(500, null) }, new MemoryStorage(), () => 0));
            var rErr = await err.FetchAds("banner");
            Assert.IsFalse(rErr.ok);                      // HTTP error -> ok=false (caller may failover)
        }

        [Test]
        public async Task DeviceTokenRotatesWeekly()
        {
            long t = 1000;
            var store = new MemoryStorage();
            double cur = 0.0; // constant within one token (22 rng calls); changed between generations
            Func<double> rng = () => cur;
            var http = new FakeHttp { OnGet = _ => new HttpResult(200, Gk1.Encode("{\"a\":[[1,\"i\",\"s\"]],\"o\":[],\"n\":\"N\"}")) };
            var c = new GoldenKrillClient("com.x", Opts(http, store, () => t, rng));
            await c.FetchAds("banner");
            c.PostEvents(new List<object> { new Dictionary<string, object> { { "creative", 1 } } }, "N");
            await Task.Delay(20);
            string first = store.Get("gk_did_v1");
            Assert.IsNotNull(first);
            // same week -> token stable
            c.PostEvents(new List<object> { new Dictionary<string, object> { { "creative", 1 } } }, "N");
            await Task.Delay(20);
            Assert.AreEqual(first, store.Get("gk_did_v1"));
            // a week later -> rotates (a different rng value yields a different token)
            cur = 0.5;
            t += 8L * 24 * 60 * 60 * 1000;
            c.PostEvents(new List<object> { new Dictionary<string, object> { { "creative", 1 } } }, "N");
            await Task.Delay(20);
            Assert.AreNotEqual(first, store.Get("gk_did_v1"));
        }
    }

    [TestFixture]
    public class AdsTests
    {
        private static Dictionary<string, object> Cfg(int oneIn = 4, int houseCd = 240, bool fallback = true, bool ownAds = false) =>
            new Dictionary<string, object>
            {
                { "reserve_share", true }, { "reserve_one_in", (double)oneIn }, { "fallback_fill", fallback },
                { "fill_own_ads", ownAds }, { "house_cooldown_sec", (double)houseCd },
            };

        // Default bundle has only the GK (a) pool; the server omits `o` unless fill_own_ads.
        private static Dictionary<string, object> Bundle() => new Dictionary<string, object>
        {
            { "a", new List<object> { Util.Row(1, "i", "s") } },
            { "o", new List<object>() },
            { "n", "NONCE" },
        };

        private static Dictionary<string, object> OwnOnlyBundle() => new Dictionary<string, object>
        {
            { "a", new List<object>() },
            { "o", new List<object> { Util.Row(2, "i2", "s2") } },
            { "n", "NONCE" },
        };

        private static GoldenKrillAds Ads(FakeHttp http, Func<long> now)
        {
            var client = new GoldenKrillClient("com.x", new GoldenKrillOptions { Http = http, Storage = new MemoryStorage(), NowMs = now });
            return new GoldenKrillAds(client, now);
        }

        [Test]
        public async Task ReserveCadenceOneInN()
        {
            long t = 0;
            var ads = Ads(Util.Serving(Cfg(3), Bundle()), () => t);
            await ads.EnsureReady("interstitial");
            // 1st eligible (index 0) serves, next two null, then the 4th (index 3 -> 3%3==0) serves.
            Assert.IsNotNull(await ads.ReserveAd("interstitial")); // index 0
            t += 999999;
            Assert.IsNull(await ads.ReserveAd("interstitial"));     // 1
            Assert.IsNull(await ads.ReserveAd("interstitial"));     // 2
            Assert.IsNotNull(await ads.ReserveAd("interstitial"));  // 3 -> serves
        }

        [Test]
        public async Task FallbackCooldownClock()
        {
            long t = 0;
            var ads = Ads(Util.Serving(Cfg(4, 240), Bundle()), () => t);
            await ads.EnsureReady("banner");
            Assert.IsNotNull(await ads.FallbackAd("banner")); // first serves, stamps GK cooldown
            Assert.IsNull(await ads.FallbackAd("banner"));    // within 240s -> GK on cooldown, own off
            t += 241 * 1000;
            Assert.IsNotNull(await ads.FallbackAd("banner")); // cooldown elapsed -> serves again
        }

        [Test]
        public async Task ResetSessionClearsCadenceAndCooldown()
        {
            long t = 0;
            var ads = Ads(Util.Serving(Cfg(4, 240), Bundle()), () => t);
            await ads.EnsureReady("banner");
            await ads.FallbackAd("banner");          // stamps cooldown
            Assert.IsNull(await ads.FallbackAd("banner"));
            ads.ResetSession();                       // clears cooldown clocks
            Assert.IsNotNull(await ads.FallbackAd("banner"));
        }

        [Test]
        public async Task FallbackServesOwnPoolWhenGkEmpty()
        {
            long t = 0;
            var ads = Ads(Util.Serving(Cfg(4, 240, fallback: true), OwnOnlyBundle()), () => t);
            await ads.EnsureReady("banner");
            var got = await ads.FallbackAd("banner"); // GK pool empty -> own pool serves
            Assert.IsNotNull(got);
            Assert.AreEqual(2, got.Id);
        }

        [Test]
        public async Task BannerAndRewarded()
        {
            long t = 0;
            var ads = Ads(Util.Serving(Cfg(2), Bundle()), () => t);
            await ads.EnsureReady("interstitial");
            Assert.IsTrue(ads.BannerReserveTurn(0));
            Assert.IsFalse(ads.BannerReserveTurn(1));
            Assert.IsNotNull(await ads.BannerHouse("banner"));
            Assert.IsTrue(ads.RewardedReady);
            Assert.IsNotNull(await ads.RewardedHouse());
        }
    }

    [TestFixture]
    public class AttestationTests
    {
        private static (GoldenKrillAds ads, FakeHttp http) Make(Func<string, Task<string>> provider, long now = 0)
        {
            var http = Util.Serving(
                new Dictionary<string, object> { { "house_cooldown_sec", (double)0 }, { "reserve_share", false } },
                new Dictionary<string, object> { { "a", new List<object> { Util.Row(1, "i", "s") } }, { "o", new List<object>() }, { "n", "NONCE1" } });
            var client = new GoldenKrillClient("com.x", new GoldenKrillOptions { Http = http, Storage = new MemoryStorage(), NowMs = () => now });
            return (new GoldenKrillAds(client, () => now) { AttestationProvider = provider }, http);
        }

        private static async Task Beacon(GoldenKrillAds ads)
        {
            await ads.EnsureReady("banner");
            await ads.FallbackAd("banner"); // records an impression -> beacon
            await Task.Delay(50);           // let the fire-and-forget beacon land
        }

        [Test]
        public async Task ForwardsHostTokenAndNonce()
        {
            string seen = null;
            var (ads, http) = Make(n => { seen = n; return Task.FromResult("TOKEN-" + n); });
            await Beacon(ads);
            Assert.AreEqual("NONCE1", seen);
            var body = (Dictionary<string, object>)MiniJson.Parse(http.Posts[http.Posts.Count - 1]);
            Assert.AreEqual("TOKEN-NONCE1", body["attestation"]);
            Assert.AreEqual("NONCE1", body["nonce"]);
        }

        [Test]
        public async Task NoProviderEmptyAttestation()
        {
            var (ads, http) = Make(null);
            await Beacon(ads);
            var body = (Dictionary<string, object>)MiniJson.Parse(http.Posts[http.Posts.Count - 1]);
            Assert.AreEqual("", body["attestation"]);
        }

        [Test]
        public async Task ThrowingProviderStillBeacons()
        {
            var (ads, http) = Make(n => throw new Exception("no integrity"));
            await Beacon(ads);
            Assert.IsNotEmpty(http.Posts); // never dropped
            var body = (Dictionary<string, object>)MiniJson.Parse(http.Posts[http.Posts.Count - 1]);
            Assert.AreEqual("", body["attestation"]);
        }
    }

    [TestFixture]
    public class TestModeTests
    {
        [Test]
        public void EndpointsAddTestOnlyWhenRequested()
        {
            Assert.IsTrue(Endpoints.AdsUrl("p", "banner", test: true).Contains("test=1"));
            Assert.IsFalse(Endpoints.AdsUrl("p", "banner").Contains("test=1"));
            Assert.IsTrue(Endpoints.ConfigUrl("p", test: true).Contains("test=1"));
            Assert.IsFalse(Endpoints.ConfigUrl("p").Contains("test=1"));
        }

        [Test]
        public async Task TestModeSendsTestOnWireAndBeacon()
        {
            long t = 0;
            var http = Util.Serving(
                new Dictionary<string, object> { { "house_cooldown_sec", (double)0 }, { "reserve_share", false } },
                new Dictionary<string, object> { { "a", new List<object> { Util.Row(0, "i", "s") } }, { "o", new List<object>() }, { "n", "N" }, { "t", (double)1 } });
            var client = new GoldenKrillClient("com.x", new GoldenKrillOptions { Http = http, Storage = new MemoryStorage(), NowMs = () => t, TestMode = true });
            var ads = new GoldenKrillAds(client, () => t);
            await ads.EnsureReady("banner");
            await ads.FallbackAd("banner");
            await Task.Delay(50);
            Assert.IsTrue(http.Gets.Exists(u => u.Contains("/config/") && u.Contains("test=1")));
            Assert.IsTrue(http.Gets.Exists(u => u.Contains("/ads?") && u.Contains("test=1")));
            var body = (Dictionary<string, object>)MiniJson.Parse(http.Posts[http.Posts.Count - 1]);
            Assert.AreEqual(true, body["test"]);
        }

        [Test]
        public void ClientDefaultTestModeFalse()
        {
            Assert.IsFalse(new GoldenKrillClient("p").TestMode);
        }
    }
}
