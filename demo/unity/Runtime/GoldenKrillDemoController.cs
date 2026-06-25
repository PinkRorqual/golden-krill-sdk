using System.Threading.Tasks;

namespace GoldenKrill.Demo
{
    /// Pure demo logic (no UnityEngine, so it is host-testable), shared by the Unity demo
    /// behaviour. Simulates a paid network with a fill/no-fill toggle, mirroring the Flutter +
    /// React Native demos: when paid FILLS, an interstitial/rewarded moment goes through GK
    /// RESERVE (~1-in-N); when paid has NO FILL, it goes through GK FALLBACK.
    public sealed class GoldenKrillDemoController
    {
        private readonly GoldenKrillAds _ads;

        /// Simulated paid network: true = paid fills (GK only reserves a share), false = no-fill.
        public bool PaidFills = true;

        public GoldenKrillDemoController(GoldenKrillAds ads) { _ads = ads; }

        public Task Ready() => _ads.EnsureReady("interstitial");

        public Task<AdItem> InterstitialMoment() =>
            PaidFills ? _ads.ReserveAd("interstitial") : _ads.FallbackAd("interstitial");

        public Task<AdItem> RewardedMoment() =>
            PaidFills ? _ads.RewardedReserve() : _ads.RewardedHouse();

        public Task<AdItem> BannerMoment() => _ads.BannerHouse("banner");

        public Task<AdItem> MrecMoment() => _ads.FallbackAd("mrec");
    }
}
