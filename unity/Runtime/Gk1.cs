using System.Collections.Generic;
using System.Text;

namespace GoldenKrill
{
    /// GK1 wire codec: "GK1." + base64url(XOR(utf8(json), key)). Obfuscation + a stable
    /// envelope, not encryption (HTTPS does transit security; host-pinned URLs stop redirects).
    /// Byte-identical to the Dart / Python / TS implementations: do not change the tag or key.
    /// The conformance vector (Tests/gk1_vectors.json) pins this against every other port.
    public static class Gk1
    {
        private const string Key = "pink-rorqual//golden-krill//v1";
        private const string Tag = "GK1.";

        // URL-safe alphabet (-, _) and WITH '=' padding, matching Dart/Python/TS exactly.
        private const string B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

        private static string B64UrlEncode(byte[] bytes)
        {
            var sb = new StringBuilder();
            for (int i = 0; i < bytes.Length; i += 3)
            {
                int b0 = bytes[i];
                int b1 = i + 1 < bytes.Length ? bytes[i + 1] : 0;
                int b2 = i + 2 < bytes.Length ? bytes[i + 2] : 0;
                sb.Append(B64[b0 >> 2]);
                sb.Append(B64[((b0 & 3) << 4) | (b1 >> 4)]);
                if (i + 1 < bytes.Length) sb.Append(B64[((b1 & 15) << 2) | (b2 >> 6)]);
                if (i + 2 < bytes.Length) sb.Append(B64[b2 & 63]);
            }
            while (sb.Length % 4 != 0) sb.Append('='); // url-safe WITH padding
            return sb.ToString();
        }

        private static byte[] B64UrlDecode(string s)
        {
            var lookup = new Dictionary<char, int>();
            for (int i = 0; i < B64.Length; i++) lookup[B64[i]] = i;
            string clean = s.TrimEnd('=');
            var outBytes = new List<byte>();
            for (int i = 0; i < clean.Length; i += 4)
            {
                int c0 = lookup[clean[i]];
                int c1 = lookup[clean[i + 1]];
                bool has2 = i + 2 < clean.Length;
                bool has3 = i + 3 < clean.Length;
                int c2 = has2 ? lookup[clean[i + 2]] : 0;
                int c3 = has3 ? lookup[clean[i + 3]] : 0;
                outBytes.Add((byte)((c0 << 2) | (c1 >> 4)));
                if (has2) outBytes.Add((byte)(((c1 & 15) << 4) | (c2 >> 2)));
                if (has3) outBytes.Add((byte)(((c2 & 3) << 6) | c3));
            }
            return outBytes.ToArray();
        }

        private static byte[] Xor(byte[] bytes)
        {
            byte[] k = Encoding.UTF8.GetBytes(Key);
            var outBytes = new byte[bytes.Length];
            for (int i = 0; i < bytes.Length; i++) outBytes[i] = (byte)(bytes[i] ^ k[i % k.Length]);
            return outBytes;
        }

        /// Encode a JSON string into a GK1 blob.
        public static string Encode(string json)
        {
            return Tag + B64UrlEncode(Xor(Encoding.UTF8.GetBytes(json)));
        }

        /// Decode a GK1 blob to its JSON string. Tolerates a raw (non-GK1) JSON body.
        public static string Decode(string blob)
        {
            if (blob == null || !blob.StartsWith(Tag)) return blob;
            return Encoding.UTF8.GetString(Xor(B64UrlDecode(blob.Substring(Tag.Length))));
        }
    }
}
