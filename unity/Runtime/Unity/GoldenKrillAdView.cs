#if UNITY_2021_3_OR_NEWER
using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Networking;
using UnityEngine.UI;

namespace GoldenKrill
{
    /// Shared helpers for the creative components: load the ad image, open the store on tap,
    /// and (house ads only) draw the disclosure badge that opens the "what is this" page.
    internal static class GoldenKrillAdView
    {
        /// The legacy built-in font, robust across Unity versions: 2022.2+ renamed it to
        /// "LegacyRuntime.ttf"; earlier versions ship "Arial.ttf". Try both so badge/close
        /// text is never invisible (a missing font silently renders nothing).
        internal static Font BuiltinFont()
        {
            return Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf")
                   ?? Resources.GetBuiltinResource<Font>("Arial.ttf");
        }

        /// uGUI Buttons only receive taps if the scene has an EventSystem and the Canvas has a
        /// GraphicRaycaster. We guarantee the EventSystem; create one if the host scene lacks it
        /// (otherwise the ad/badge/close buttons are dead). The Canvas raycaster is the
        /// integrator's (a standard Canvas has one); documented in the README.
        internal static void EnsureEventSystem()
        {
#if UNITY_2023_1_OR_NEWER
            var existing = UnityEngine.Object.FindAnyObjectByType<UnityEngine.EventSystems.EventSystem>();
#else
            var existing = UnityEngine.Object.FindObjectOfType<UnityEngine.EventSystems.EventSystem>();
#endif
            if (existing != null) return;
            new GameObject("EventSystem",
                typeof(UnityEngine.EventSystems.EventSystem),
                typeof(UnityEngine.EventSystems.StandaloneInputModule));
        }

        public static IEnumerator LoadInto(RawImage target, string imageUrl, Action done = null)
        {
            using (var req = UnityWebRequestTexture.GetTexture(imageUrl))
            {
                yield return req.SendWebRequest();
                if (req.result == UnityWebRequest.Result.Success && target != null)
                    target.texture = DownloadHandlerTexture.GetContent(req);
                done?.Invoke();
            }
        }

        public static void OnTap(GameObject go, Action action)
        {
            var btn = go.GetComponent<Button>() ?? go.AddComponent<Button>();
            btn.onClick.RemoveAllListeners();
            btn.onClick.AddListener(() => action());
        }

        public static void OpenStore(AdItem ad)
        {
            // The store slot is a /c tracker URL (server-observed; counts the click), or a direct
            // URL in test mode. Open it verbatim - the SDK never builds its own click URL.
            if (ad != null && !string.IsNullOrEmpty(ad.Store)) Application.OpenURL(ad.Store);
        }

        // Brand badge colours, IDENTICAL to the Flutter + RN SDKs so the mark is visually
        // consistent on every platform: gold #E7AD34 chip, dark-teal #12363A bold text.
        private static readonly Color BadgeGold = new Color(0xE7 / 255f, 0xAD / 255f, 0x34 / 255f, 1f);
        private static readonly Color BadgeText = new Color(0x12 / 255f, 0x36 / 255f, 0x3A / 255f, 1f);

        /// Add the on-brand disclosure badge in the bottom-right corner (matching Flutter/RN):
        /// "GK" on the tiny banner, the full "Powered by Golden Krill" pill on bigger slots. Always
        /// "GK"-branded, never "Ad". Pass "GK-Test" in test mode to tag test ads. Tappable -> badge
        /// page. The chip auto-sizes to the label so longer text is not clipped.
        public static void AddBadge(RectTransform parent, string badgeUrl, string label = "GK")
        {
            bool compact = label.Length <= 2;            // "GK" vs the full pill
            int fontSize = compact ? 9 : 11;
            float padH = compact ? 4f : 7f;
            var go = new GameObject("GK_Badge", typeof(RectTransform), typeof(Image), typeof(Button));
            var rt = (RectTransform)go.transform;
            rt.SetParent(parent, false);
            rt.anchorMin = new Vector2(1, 0); rt.anchorMax = new Vector2(1, 0); rt.pivot = new Vector2(1, 0);
            float w = padH * 2f + label.Length * (fontSize * 0.62f);
            rt.sizeDelta = new Vector2(w, fontSize + 6f); rt.anchoredPosition = new Vector2(-2, 2);
            go.GetComponent<Image>().color = BadgeGold;
            var txtGo = new GameObject("Text", typeof(RectTransform), typeof(Text));
            var lrt = (RectTransform)txtGo.transform; lrt.SetParent(rt, false);
            lrt.anchorMin = Vector2.zero; lrt.anchorMax = Vector2.one; lrt.sizeDelta = Vector2.zero;
            var txt = txtGo.GetComponent<Text>();
            txt.text = label; txt.alignment = TextAnchor.MiddleCenter; txt.color = BadgeText;
            txt.fontSize = fontSize; txt.fontStyle = FontStyle.Bold;
            txt.font = BuiltinFont();
            string url = string.IsNullOrEmpty(badgeUrl) ? Endpoints.BadgeInfoUrl : badgeUrl;
            go.GetComponent<Button>().onClick.AddListener(() => Application.OpenURL(url));
        }

        /// Shared close button (used by interstitial + rewarded). A dark square with an "X".
        internal static void AddCloseButton(RectTransform parent, Action onClick)
        {
            var go = new GameObject("GK_Close", typeof(RectTransform), typeof(Image), typeof(Button));
            var rt = (RectTransform)go.transform; rt.SetParent(parent, false);
            rt.anchorMin = new Vector2(1, 1); rt.anchorMax = new Vector2(1, 1); rt.pivot = new Vector2(1, 1);
            rt.sizeDelta = new Vector2(44, 44); rt.anchoredPosition = new Vector2(-8, -8);
            go.GetComponent<Image>().color = new Color(0, 0, 0, 0.55f);
            go.GetComponent<Button>().onClick.AddListener(() => onClick());
            var label = new GameObject("X", typeof(RectTransform), typeof(Text));
            var lrt = (RectTransform)label.transform; lrt.SetParent(rt, false);
            lrt.anchorMin = Vector2.zero; lrt.anchorMax = Vector2.one; lrt.sizeDelta = Vector2.zero;
            var txt = label.GetComponent<Text>();
            txt.text = "X"; txt.alignment = TextAnchor.MiddleCenter; txt.color = Color.white;
            txt.fontSize = 24; txt.font = BuiltinFont();
        }
    }
}
#endif
