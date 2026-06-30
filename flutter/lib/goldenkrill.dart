/// Golden Krill cross-promotion SDK (Flutter).
///
/// Fills a paid ad no-fill (or a small reserved share of moments) with a house ad -
/// a cross-promo for another participating app - instead of a blank. See
/// INTEGRATION.md for wiring it behind your own ads code.
library;

export 'src/gk_debug.dart' show GoldenKrillDebug; // opt-in debug logging
export 'src/catalog/catalog_codec.dart'; // GK1 wire codec (used by the serving client)
export 'src/config/serving_endpoint.dart'
    show kServingBase, kConfigTtl, kAdsTtl, gkConfigUrl, gkAdsUrl, gkEventsUrl;
export 'src/serving/serve_models.dart';
export 'src/serving/serving_client.dart';
export 'src/serving/connectivity.dart' show GkConnectivity, gkConnectivityPlus, gkIsOnline; // pluggable offline gate
export 'package:connectivity_plus/connectivity_plus.dart' show ConnectivityResult;
export 'src/serving/event_queue.dart' show GkEventQueue, GkEventPost; // persistent beacon retry queue
export 'src/serving/goldenkrill_ads.dart';
export 'src/serving/goldenkrill_widgets.dart';
