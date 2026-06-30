/// Device connectivity probe. The SDK gates ad availability + serving on this so it
/// never shows an offline CTA whose click/impression beacons cannot succeed (Bug A).
///
/// A probe is just `Future<bool> Function()` (true = a network path looks present), so
/// tests inject a fake and the default talks to `connectivity_plus`. Kept tiny + behind a
/// typedef so the core serving logic stays plugin-free and unit-testable.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../gk_debug.dart';

/// Upper bound on how long the default probe waits for the platform channel before it
/// gives up and assumes online. A connectivity check is normally <50ms; the timeout only
/// guards against a wedged channel so the probe can never block the ad path.
const Duration kConnectivityTimeout = Duration(seconds: 2);

/// Probes whether the device currently has any network transport. Returns true when
/// online, false when fully offline. Pluggable: inject your own in tests.
typedef GkConnectivity = Future<bool> Function();

/// Pure online/offline decision over a connectivity_plus result list: online when any
/// transport is present (wifi / mobile / ethernet / vpn / bluetooth), offline only when
/// every result is `none` (or the list is empty). Extracted so the mapping is unit-tested
/// without the platform channel.
bool gkIsOnline(List<ConnectivityResult> results) =>
    results.any((c) => c != ConnectivityResult.none);

/// Default probe backed by `connectivity_plus`. A probe error fails OPEN (assume online)
/// so a flaky platform channel never permanently blocks serving: an actually-dead network
/// then just fails the fetch, which already collapses to no-fill.
Future<bool> gkConnectivityPlus() async {
  try {
    return gkIsOnline(await Connectivity().checkConnectivity().timeout(kConnectivityTimeout));
  } catch (e) {
    gkLog(() => 'connectivity probe failed/timed out ($e) -> assume online');
    return true;
  }
}
