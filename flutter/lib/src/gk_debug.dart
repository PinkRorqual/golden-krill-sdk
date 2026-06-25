/// Opt-in debug logging. Off by default and zero-cost when off (the message is only
/// built when enabled). Turn on with `GoldenKrillDebug.enabled = true;` and grep your
/// console / logcat for `[GoldenKrill]`.
library;

class GoldenKrillDebug {
  GoldenKrillDebug._();

  /// Flip to true (e.g. in dev) to emit concise `[GoldenKrill] ...` lines.
  static bool enabled = false;
}

/// Log a concise line iff debug is enabled. Takes a closure so nothing is computed
/// when disabled.
void gkLog(String Function() message) {
  if (GoldenKrillDebug.enabled) {
    // ignore: avoid_print
    print('[GoldenKrill] ${message()}');
  }
}
