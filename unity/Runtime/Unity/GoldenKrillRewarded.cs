#if UNITY_2021_3_OR_NEWER
using System;
using System.Collections;
using UnityEngine;
using UnityEngine.UI;

namespace GoldenKrill
{
    /// Rewarded: fullscreen creative with a countdown bar; the close button is BLOCKED until the
    /// countdown completes, then it dismisses and grants the reward. onClose(earned). Bigger slot,
    /// so the disclosure is the full "Powered by Golden Krill" pill (parity with Flutter/RN).
    public class GoldenKrillRewarded : MonoBehaviour
    {
        private bool _earned;

        public void Show(AdItem ad, int durationMs, bool showBadge, Action<bool> onClose)
        {
            GoldenKrillAdView.EnsureEventSystem();
            var rt = (RectTransform)transform;
            var raw = GetComponent<RawImage>() ?? gameObject.AddComponent<RawImage>();
            StartCoroutine(GoldenKrillAdView.LoadInto(raw, ad.Image));
            GoldenKrillAdView.OnTap(gameObject, () => GoldenKrillAdView.OpenStore(ad));
            if (showBadge) GoldenKrillAdView.AddBadge(rt, Endpoints.BadgeInfoUrl, "Powered by Golden Krill");

            var barGo = new GameObject("GK_Countdown", typeof(RectTransform), typeof(Image));
            var brt = (RectTransform)barGo.transform; brt.SetParent(rt, false);
            brt.anchorMin = new Vector2(0, 1); brt.anchorMax = new Vector2(1, 1); brt.pivot = new Vector2(0, 1);
            brt.sizeDelta = new Vector2(0, 6); brt.anchoredPosition = Vector2.zero;
            var bar = barGo.GetComponent<Image>();
            bar.color = new Color(0.96f, 0.74f, 0.29f, 1f);
            bar.type = Image.Type.Filled; bar.fillMethod = Image.FillMethod.Horizontal; bar.fillAmount = 0;

            StartCoroutine(Countdown(bar, Mathf.Max(1, durationMs) / 1000f, rt, onClose));
        }

        private IEnumerator Countdown(Image bar, float seconds, RectTransform parent, Action<bool> onClose)
        {
            float elapsed = 0;
            while (elapsed < seconds)
            {
                elapsed += Time.deltaTime;
                if (bar != null) bar.fillAmount = Mathf.Clamp01(elapsed / seconds);
                yield return null; // dismissal blocked while counting
            }
            _earned = true; // watched to completion -> reward earned
            GoldenKrillAdView.AddCloseButton(parent, () => { onClose?.Invoke(_earned); Destroy(gameObject); });
        }
    }
}
#endif
