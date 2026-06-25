namespace GoldenKrill
{
    /// Frozen serving endpoints + cache TTLs (the API model). The SDK talks only to these.
    /// `test=1` (additive) puts a request in test mode: an always-fill TEST AD, counted nowhere.
    public static class Endpoints
    {
        public const string ServingBase = "https://a.golden-krill.com";

        /// Where the disclosure badge sends a user who taps it (who we are / how to join).
        public const string BadgeInfoUrl = "https://golden-krill.com/about";

        public const long ConfigTtlMs = 12L * 60 * 60 * 1000; // 12h
        public const long AdsTtlMs = 1L * 60 * 60 * 1000;     // 1h

        public static string ConfigUrl(string pkg, string baseUrl = ServingBase, bool test = false) =>
            $"{baseUrl}/api/v1/config/{System.Uri.EscapeDataString(pkg)}?fmt=gk1{(test ? "&test=1" : "")}";

        public static string AdsUrl(string pkg, string slot, string lang = "en", string store = null,
                                    string baseUrl = ServingBase, bool test = false)
        {
            string url = $"{baseUrl}/api/v1/ads?app={System.Uri.EscapeDataString(pkg)}&slot={slot}&lang={lang}&fmt=gk1";
            if (!string.IsNullOrEmpty(store)) url += $"&store={store}"; // platform store -> right app store
            if (test) url += "&test=1"; // test mode: server returns a TEST AD and counts nothing
            return url;
        }

        public static string EventsUrl(string baseUrl = ServingBase) => $"{baseUrl}/api/v1/events";
    }
}
