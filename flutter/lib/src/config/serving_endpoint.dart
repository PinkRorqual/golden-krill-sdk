/// Frozen serving endpoints + cache TTLs (API model). The SDK talks only to these.
library;

/// Production serving host. Binary (GK1) responses via `fmt=gk1`.
const String kServingBase = 'https://a.golden-krill.com';

/// Re-fetch cadence. Config changes rarely; the ads bundle is window-cached server
/// side, so an hour on-device matches it.
const Duration kConfigTtl = Duration(hours: 12);
const Duration kAdsTtl = Duration(hours: 1);

Uri gkConfigUrl(String package, {String base = kServingBase, bool test = false}) =>
    Uri.parse('$base/api/v1/config/$package?fmt=gk1${test ? '&test=1' : ''}');

Uri gkAdsUrl(String package,
        {String? slot, String lang = 'en', String? store, String base = kServingBase, bool test = false}) =>
    Uri.parse('$base/api/v1/ads').replace(queryParameters: {
      'app': package,
      'lang': lang,
      'fmt': 'gk1',
      if (slot != null) 'slot': slot,
      if (store != null) 'store': store, // platform store so the click resolves the right app store
      if (test) 'test': '1', // test mode: server returns a TEST AD and counts nothing
    });

Uri gkEventsUrl({String base = kServingBase}) => Uri.parse('$base/api/v1/events');
