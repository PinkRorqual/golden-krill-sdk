#if UNITY_2021_3_OR_NEWER
using System;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;

namespace GoldenKrill
{
    /// UnityWebRequest-backed HTTP. Runs on the main thread (call the SDK from there). Never
    /// throws to the SDK: a transport error surfaces as a null body, which the client treats
    /// as a fetch failure (degrades to cache/defaults).
    public sealed class UnityWebRequestHttp : IGoldenKrillHttp
    {
        public Task<HttpResult> GetAsync(string url)
        {
            var tcs = new TaskCompletionSource<HttpResult>();
            var req = UnityWebRequest.Get(url);
            var op = req.SendWebRequest();
            op.completed += _ =>
            {
                try
                {
                    bool ok = req.result == UnityWebRequest.Result.Success;
                    tcs.SetResult(new HttpResult((int)req.responseCode, ok ? req.downloadHandler.text : null));
                }
                catch { tcs.SetResult(new HttpResult(0, null)); }
                finally { req.Dispose(); }
            };
            return tcs.Task;
        }

        public Task PostAsync(string url, string jsonBody)
        {
            var tcs = new TaskCompletionSource<bool>();
            var req = new UnityWebRequest(url, "POST")
            {
                uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(jsonBody)),
                downloadHandler = new DownloadHandlerBuffer(),
            };
            req.SetRequestHeader("Content-Type", "application/json");
            var op = req.SendWebRequest();
            op.completed += _ => { try { req.Dispose(); } catch { } tcs.TrySetResult(true); }; // beacons: result ignored
            return tcs.Task;
        }
    }

    /// PlayerPrefs-backed storage (the config last-good cache + the anonymous weekly device token).
    public sealed class PlayerPrefsStorage : IGoldenKrillStorage
    {
        public string Get(string key) => PlayerPrefs.HasKey(key) ? PlayerPrefs.GetString(key) : null;
        public void Set(string key, string value) { PlayerPrefs.SetString(key, value); PlayerPrefs.Save(); }
    }

    /// Unity entry point. Wires UnityWebRequest + PlayerPrefs + the device store, and defaults
    /// testMode to Debug.isDebugBuild (the C# equivalent of Flutter kDebugMode / RN __DEV__):
    /// you see an always-fill TEST AD in a development build and ship the real path automatically.
    /// NEVER ship a release build with testMode forced on. base + package stay injectable.
    public static class GoldenKrillUnity
    {
        public static GoldenKrillAds Create(
            string package,
            string baseUrl = null,
            bool? testMode = null,
            Func<string, Task<string>> attestationProvider = null)
        {
            var opts = new GoldenKrillOptions
            {
                Http = new UnityWebRequestHttp(),
                Storage = new PlayerPrefsStorage(),
                Store = Application.platform == RuntimePlatform.IPhonePlayer ? "appstore" : "play",
                Base = baseUrl, // null -> Endpoints.ServingBase
                TestMode = testMode ?? Debug.isDebugBuild,
                AttestationProvider = attestationProvider,
            };
            return new GoldenKrillAds(package, opts);
        }
    }
}
#endif
