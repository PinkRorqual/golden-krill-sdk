import 'dart:convert';
import 'dart:typed_data';

/// Thrown when an encoded catalog blob cannot be decoded - corrupt payload, or
/// a format version this (older) build does not understand.
class CatalogCodecException implements Exception {
  const CatalogCodecException(this.message);
  final String message;
  @override
  String toString() => 'CatalogCodecException: $message';
}

/// Wire codec for the runtime-fetched catalog.
///
/// The catalog is **not** served as plain-text JSON. It is compiled to a static,
/// versioned, obfuscated blob ([encode]) that is deployed to an obscure path on
/// `cryptoven.eu`, and GoldenKrill decodes it at runtime ([decode]). Encode and
/// decode live together, in the same code, so the two ends can never drift.
///
/// **This is obfuscation + a stable envelope, not cryptographic confidentiality.**
/// HTTPS provides transit security; host-pinning (see `catalog_url`) stops tap
/// redirects. The codec's jobs are narrow: (1) the payload is not readable
/// clear-text sitting at a URL, and (2) the envelope is **versioned** so the
/// format can evolve without breaking already-shipped apps.
///
/// ## Backward-compatibility contract - read before changing anything
///
/// App binaries embed a *frozen snapshot* of this code and can live on users'
/// devices for years. A binary can only decode formats that existed when it
/// shipped. Therefore:
///
/// - **v1 (`GK1`) is eternal.** Its byte layout below must never change, and
///   the server must keep serving GK1 for as long as any GK1-only binary is in
///   the field. Every GoldenKrill version ever shipped understands GK1, so
///   emitting GK1 guarantees "old versions can still decode it".
/// - New formats (a future `GK2`, e.g. real compression) may be **added** to
///   [decode], but [encode] keeps emitting GK1 until no GK1-only app remains.
///   Never repurpose the `GK1` tag for a different layout.
/// - Payload-level additions (new catalog/app fields, new slot names) need no
///   new envelope version - the JSON parser already ignores what it doesn't
///   know.
class CatalogCodec {
  const CatalogCodec._(); // coverage:ignore-line - static-only, never instantiated

  /// Current envelope version tag. The blob is `"$_v1Tag.<base64url payload>"`.
  static const String _v1Tag = 'GK1';
  static const String _v1Prefix = '$_v1Tag.';

  /// Fixed obfuscation key. NOT a secret and NOT security - it only keeps the
  /// payload from being one-step readable as JSON. Frozen as part of the v1
  /// layout; changing it would break every shipped binary, so never edit it.
  static const String _obfuscationKey = 'pink-rorqual//golden-krill//v1';

  /// Encode a JSON string into the v1 blob. Used by the build-time tool that
  /// compiles the deployed catalog file. Output: `GK1.` + base64url of the
  /// XOR-obfuscated UTF-8 bytes.
  static String encode(String json) {
    final bytes = utf8.encode(json);
    final obfuscated = _xor(bytes);
    return _v1Prefix + base64Url.encode(obfuscated);
  }

  /// Decode a fetched blob back to its JSON string.
  ///
  /// Accepts, in order:
  /// - a `GK1.` envelope (the production format), and
  /// - raw JSON (a leading `{` or `[`) - a graceful fallback for local dev and
  ///   tests, so a hand-written catalog still loads.
  ///
  /// Throws [CatalogCodecException] for an unknown/garbled format or a corrupt
  /// v1 payload, so the caller can serve nothing rather than trust junk.
  static String decode(String blob) {
    final trimmed = blob.trimLeft();
    if (trimmed.startsWith(_v1Prefix)) {
      return _decodeV1(trimmed.substring(_v1Prefix.length));
    }
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return blob; // raw JSON passthrough (dev/test fallback)
    }
    throw const CatalogCodecException('unrecognised catalog format');
  }

  static String _decodeV1(String payload) {
    final Uint8List obfuscated;
    try {
      obfuscated = base64Url.decode(payload);
    } on FormatException catch (e) {
      throw CatalogCodecException('corrupt GK1 payload: ${e.message}');
    }
    final bytes = _xor(obfuscated);
    try {
      return utf8.decode(bytes);
    } on FormatException catch (e) {
      throw CatalogCodecException('GK1 payload is not UTF-8: ${e.message}');
    }
  }

  /// Symmetric XOR against the cycled key bytes. Its own inverse, so the same
  /// routine both obfuscates (encode) and de-obfuscates (decode).
  static Uint8List _xor(List<int> input) {
    final key = utf8.encode(_obfuscationKey);
    final out = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      out[i] = input[i] ^ key[i % key.length];
    }
    return out;
  }
}
