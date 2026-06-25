using System;
using System.Threading.Tasks;
using NUnit.Framework;

namespace GoldenKrill.Demo.Tests
{
    // Self-contained fake (the demo test assembly is separate from the SDK test assembly).
    internal sealed class DemoFakeHttp : IGoldenKrillHttp
    {
        public Func<string, HttpResult> OnGet;
        public Task<HttpResult> GetAsync(string url) => Task.FromResult(OnGet(url));
        public Task PostAsync(string url, string body) => Task.CompletedTask;
    }

    [TestFixture]
    public class GoldenKrillDemoSmokeTest
    {
        private static GoldenKrillAds AlwaysFills()
        {
            var http = new DemoFakeHttp
            {
                OnGet = url => url.Contains("/config/")
                    ? new HttpResult(200, Gk1.Encode("{\"house_cooldown_sec\":0,\"reserve_share\":true,\"reserve_one_in\":1,\"fill_own_ads\":true}"))
                    : new HttpResult(200, Gk1.Encode("{\"a\":[[1,\"i\",\"s\"]],\"o\":[[2,\"i2\",\"s2\"]],\"n\":\"N\"}"))
            };
            long t = 0;
            var client = new GoldenKrillClient("com.demo", new GoldenKrillOptions { Http = http, Storage = new MemoryStorage(), NowMs = () => t });
            return new GoldenKrillAds(client, () => t);
        }

        [Test]
        public async Task AllFourAdTypesProduceAnAd()
        {
            var demo = new GoldenKrillDemoController(AlwaysFills());
            await demo.Ready();
            demo.PaidFills = true;
            Assert.IsNotNull(await demo.InterstitialMoment()); // reserve 1-in-1 -> serves
            Assert.IsNotNull(await demo.RewardedMoment());     // rewarded reserve 1-in-1
            demo.PaidFills = false;
            Assert.IsNotNull(await demo.BannerMoment());       // banner house
            Assert.IsNotNull(await demo.MrecMoment());         // mrec fallback
        }
    }
}
