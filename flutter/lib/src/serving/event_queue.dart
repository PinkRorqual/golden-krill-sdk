/// A persistent, fire-and-forget telemetry queue for impression / click beacons (Bug B).
///
/// Telemetry must NEVER block a UI action - in particular the close (X) button must pop
/// immediately, even if a beacon POST is hung on a dead network. So every beacon is
/// enqueued (persisted) and flushed off the caller's path; the caller never awaits the
/// network. Records are keyed by an opaque event id, so a duplicate enqueue (a retry of
/// the same impression) COLLAPSES instead of double-counting. Unsent records survive an
/// app restart in `shared_preferences` and are retried on the next enqueue/flush.
///
/// Never throws to the caller.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../gk_debug.dart';

/// Posts a batch of events to the network. Returns true when the POST succeeded (the
/// record is then dropped), false when it failed (the record is kept for a later retry).
typedef GkEventPost = Future<bool> Function(
  List<Map<String, dynamic>> events, {
  String attestation,
  String nonce,
});

class GkEventQueue {
  GkEventQueue({required this.post, this.maxPending = 200});

  /// The network sink (e.g. `GoldenKrillClient.postEvents`). Injected so tests can stub
  /// success / failure / a never-completing (hung) POST.
  final GkEventPost post;

  /// Hard cap on persisted records so a long offline stretch can't grow the blob without
  /// bound; the oldest are dropped first.
  final int maxPending;

  static const String _key = 'gk_evtq_v1';
  bool _flushing = false;

  /// Enqueue a beacon (persist) then kick a background flush. Duplicate [id]s collapse:
  /// a record already pending under the same id is not added again. Returns once the
  /// record is persisted; the actual POST is fired in the background, never awaited by
  /// the caller's UI path.
  Future<void> add(
    String id,
    List<Map<String, dynamic>> events, {
    String attestation = '',
    String nonce = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _load(prefs);
    if (list.any((r) => r['id'] == id)) {
      gkLog(() => 'evtq: duplicate $id collapsed');
      // ignore: discarded_futures - background retry of whatever is pending
      flush();
      return;
    }
    list.add({'id': id, 'events': events, 'att': attestation, 'nonce': nonce});
    while (list.length > maxPending) {
      list.removeAt(0); // drop oldest
    }
    await prefs.setString(_key, jsonEncode(list));
    // ignore: discarded_futures - fire-and-forget; the caller never awaits the network
    flush();
  }

  /// Try to send every pending record; drop the ones that succeed, keep the rest for a
  /// later retry. Re-entrancy-guarded so overlapping flushes don't double-send. Never
  /// throws.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _load(prefs);
      if (list.isEmpty) return;
      final remaining = <Map<String, dynamic>>[];
      for (final r in list) {
        final events = ((r['events'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        bool ok;
        try {
          ok = await post(events,
              attestation: r['att'] as String? ?? '', nonce: r['nonce'] as String? ?? '');
        } catch (_) {
          ok = false;
        }
        if (!ok) remaining.add(r);
      }
      await prefs.setString(_key, jsonEncode(remaining));
      gkLog(() => 'evtq: flushed ${list.length - remaining.length}/${list.length}');
    } finally {
      _flushing = false;
    }
  }

  /// Number of records still waiting to be sent (test/diagnostic helper).
  Future<int> pendingCount() async => _load(await SharedPreferences.getInstance()).length;

  List<Map<String, dynamic>> _load(SharedPreferences prefs) {
    final s = prefs.getString(_key);
    if (s == null) return [];
    try {
      final d = jsonDecode(s);
      return d is List ? d.map((e) => (e as Map).cast<String, dynamic>()).toList() : [];
    } catch (_) {
      return [];
    }
  }
}
