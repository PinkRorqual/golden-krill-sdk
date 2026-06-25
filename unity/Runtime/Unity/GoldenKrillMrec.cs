#if UNITY_2021_3_OR_NEWER
namespace GoldenKrill
{
    /// MREC creative (the banner behaviour at the 600x500 slot size). A bigger slot, so the
    /// disclosure is the full "Powered by Golden Krill" pill, matching Flutter/RN. Its own file
    /// so Unity can attach it (a MonoBehaviour must live in a file named after the class).
    public class GoldenKrillMrec : GoldenKrillBanner
    {
        protected override string BadgeLabel => "Powered by Golden Krill";
    }
}
#endif
