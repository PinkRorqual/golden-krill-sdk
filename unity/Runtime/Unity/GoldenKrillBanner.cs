#if UNITY_2021_3_OR_NEWER
using UnityEngine;
using UnityEngine.UI;

namespace GoldenKrill
{
    /// Banner / MREC creative: a RawImage that shows the ad and opens the store on tap. The
    /// slot size is set by your layout (640x100 vs 600x500). Disclosure mark matches Flutter/RN:
    /// "GK" on the tiny banner, the full "Powered by Golden Krill" pill on bigger slots (Mrec).
    [RequireComponent(typeof(RawImage))]
    public class GoldenKrillBanner : MonoBehaviour
    {
        /// The disclosure label for this slot. Banner = "GK"; Mrec overrides to the full pill.
        protected virtual string BadgeLabel => "GK";

        public void Show(AdItem ad, bool showBadge)
        {
            GoldenKrillAdView.EnsureEventSystem();
            var img = GetComponent<RawImage>();
            StartCoroutine(GoldenKrillAdView.LoadInto(img, ad.Image));
            GoldenKrillAdView.OnTap(gameObject, () => GoldenKrillAdView.OpenStore(ad));
            if (showBadge) GoldenKrillAdView.AddBadge((RectTransform)transform, Endpoints.BadgeInfoUrl, BadgeLabel);
        }
    }
}
#endif
