using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace GoldenKrill
{
    /// HTTP result: status + body. Body is null on a transport error.
    public struct HttpResult
    {
        public int Status;
        public string Body;
        public HttpResult(int status, string body) { Status = status; Body = body; }
    }

    /// Injectable HTTP so the core is testable + the serving base is not hardcoded. The Unity
    /// adapter (UnityWebRequest) lives in the Unity-only layer; tests inject a fake.
    public interface IGoldenKrillHttp
    {
        Task<HttpResult> GetAsync(string url);
        Task PostAsync(string url, string jsonBody); // fire-and-forget on the caller side
    }

    /// Injectable key/value storage (PlayerPrefs in Unity; in-memory in tests). Sync is fine.
    public interface IGoldenKrillStorage
    {
        string Get(string key);
        void Set(string key, string value);
    }

    /// In-memory storage fallback (no persistence) - used when no storage is provided.
    public sealed class MemoryStorage : IGoldenKrillStorage
    {
        private readonly Dictionary<string, string> _m = new Dictionary<string, string>();
        public string Get(string key) => _m.TryGetValue(key, out var v) ? v : null;
        public void Set(string key, string value) => _m[key] = value;
    }

    /// Construction options for the client + facade. Everything injectable for tests/staging;
    /// nothing hardcoded. TestMode null = use the layer default (Unity: Debug.isDebugBuild).
    public sealed class GoldenKrillOptions
    {
        public IGoldenKrillHttp Http;
        public IGoldenKrillStorage Storage;
        public Func<long> NowMs;         // clock in epoch milliseconds
        public Func<double> Rng;         // 0..1 random
        public string Base;              // serving base (override for staging)
        public string Store;             // device store id (appstore/play); injectable
        public long ConfigTtlMs;         // 0 -> default
        public bool? TestMode;           // null -> layer default
        public Func<string, Task<string>> AttestationProvider; // nonce -> opaque token, optional
    }
}
