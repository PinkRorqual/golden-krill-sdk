#if UNITY_2021_3_OR_NEWER
using System;
using UnityEngine;
using UnityEngine.UI;

namespace GoldenKrill
{
    /// Interstitial: fullscreen creative + a close button; resolves when dismissed. Bigger slot,
    /// so the disclosure is the full "Powered by Golden Krill" pill (parity with Flutter/RN).
    public class GoldenKrillInterstitial : MonoBehaviour
    {
        public void Show(AdItem ad, bool showBadge, Action onClose)
        {
            GoldenKrillAdView.EnsureEventSystem();
            var rt = (RectTransform)transform;
            var raw = GetComponent<RawImage>() ?? gameObject.AddComponent<RawImage>();
            StartCoroutine(GoldenKrillAdView.LoadInto(raw, ad.Image));
            GoldenKrillAdView.OnTap(gameObject, () => GoldenKrillAdView.OpenStore(ad));
            GoldenKrillAdView.AddCloseButton(rt, () => { onClose?.Invoke(); Destroy(gameObject); });
            if (showBadge) GoldenKrillAdView.AddBadge(rt, Endpoints.BadgeInfoUrl, "Powered by Golden Krill");
        }
    }
}
#endif
