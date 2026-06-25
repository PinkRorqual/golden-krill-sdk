#if UNITY_2021_3_OR_NEWER
using UnityEngine;

namespace GoldenKrill.Demo
{
    /// Drop this on a GameObject and wire the four buttons + the "paid fills" toggle. Mirrors the
    /// Flutter + React Native demos: a simulated paid network with a fill/no-fill switch driving
    /// GK reserve vs fallback. In a development build testMode defaults on, so you always see a
    /// TEST AD. Attach a RawImage-bearing prefab via the slot fields to render.
    public class GoldenKrillDemoBehaviour : MonoBehaviour
    {
        public string package = "com.pinkrorqual.demo";
        public bool paidFills = true;
        [Tooltip("RawImage host for banner/mrec; a fullscreen host is created for interstitial/rewarded.")]
        public GoldenKrillBanner bannerSlot;
        public GoldenKrillBanner mrecSlot;

        private GoldenKrillDemoController _demo;
        private bool _ready;

        private async void Start()
        {
            var ads = GoldenKrillUnity.Create(package); // testMode = Debug.isDebugBuild
            _demo = new GoldenKrillDemoController(ads);
            await _demo.Ready();
            _ready = true;
            Debug.Log("[GoldenKrillDemo] ready");
        }

        public async void OnBanner()
        {
            if (!_ready) return;
            var ad = await _demo.BannerMoment();
            if (ad != null && bannerSlot != null) bannerSlot.Show(ad, true);
        }

        public async void OnMrec()
        {
            if (!_ready) return;
            _demo.PaidFills = paidFills;
            var ad = await _demo.MrecMoment();
            if (ad != null && mrecSlot != null) mrecSlot.Show(ad, true);
        }

        public async void OnInterstitial()
        {
            if (!_ready) return;
            _demo.PaidFills = paidFills;
            var ad = await _demo.InterstitialMoment();
            ShowFullscreen<GoldenKrillInterstitial>(ad, c => c.Show(ad, true, () => Debug.Log("[GoldenKrillDemo] interstitial closed")));
        }

        public async void OnRewarded()
        {
            if (!_ready) return;
            _demo.PaidFills = paidFills;
            var ad = await _demo.RewardedMoment();
            ShowFullscreen<GoldenKrillRewarded>(ad, c => c.Show(ad, _demo == null ? 10000 : 10000, true,
                earned => Debug.Log($"[GoldenKrillDemo] rewarded closed, earned={earned}")));
        }

        private void ShowFullscreen<T>(AdItem ad, System.Action<T> show) where T : MonoBehaviour
        {
            if (ad == null) { Debug.Log("[GoldenKrillDemo] no fill"); return; }
            var go = new GameObject("GK_Fullscreen", typeof(RectTransform), typeof(UnityEngine.UI.RawImage));
#if UNITY_2023_1_OR_NEWER
            var canvas = FindAnyObjectByType<Canvas>();
#else
            var canvas = FindObjectOfType<Canvas>();
#endif
            if (canvas != null) go.transform.SetParent(canvas.transform, false);
            var rt = (RectTransform)go.transform;
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one; rt.sizeDelta = Vector2.zero;
            show(go.AddComponent<T>());
        }
    }
}
#endif
