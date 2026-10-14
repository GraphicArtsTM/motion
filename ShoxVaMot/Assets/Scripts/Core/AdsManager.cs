using System;
using System.Collections;
using UnityEngine;
#if SHOX_UNITY_ADS
using UnityEngine.Advertisements;
#endif

namespace Shatranj.Core
{
    /// <summary>
    /// Настройки рекламы. Game ID и Ad Unit ID берутся в Unity Dashboard → Monetization (Unity Ads).
    /// Пока стоят заглушки, реклама не запрашивается и игра запускается сразу.
    /// Перед публикацией поставьте TestMode = false.
    /// </summary>
    public static class AdsConfig
    {
        public const string AndroidGameId = "800397695";
        public const string IosGameId = "YOUR_IOS_GAME_ID";
        public const string AndroidInterstitial = "BP_Interstitial_Android";
        public const string IosInterstitial = "Interstitial_iOS";
        public const bool TestMode = true;

        /// <summary>Минимальная пауза между показами (сек). 0 — реклама перед каждой партией.</summary>
        public const float MinSecondsBetweenAds = 0f;
        /// <summary>Сколько ждать загрузки ролика, прежде чем начать партию без рекламы.</summary>
        public const float LoadWaitSeconds = 5f;
    }

    /// <summary>
    /// Межстраничная реклама Unity Ads перед началом партии.
    /// Код рекламы компилируется только при наличии пакета com.unity.ads
    /// (символ SHOX_UNITY_ADS выставляет редакторский скрипт автоматически),
    /// поэтому проект собирается и без него.
    /// </summary>
    public class AdsManager : MonoBehaviour
#if SHOX_UNITY_ADS
        , IUnityAdsInitializationListener, IUnityAdsLoadListener, IUnityAdsShowListener
#endif
    {
        public static AdsManager I { get; private set; }

#pragma warning disable 0649, 0414 // без пакета Unity Ads часть полей не используется
        bool initialized, loaded, loading, showing, busy;
#pragma warning restore 0649, 0414
        float lastShown = -9999f;

        public static AdsManager Create(Transform parent)
        {
            var go = new GameObject("Ads");
            go.transform.SetParent(parent, false);
            I = go.AddComponent<AdsManager>();
            return I;
        }

        static string GameId
        {
            get { return Application.platform == RuntimePlatform.IPhonePlayer ? AdsConfig.IosGameId : AdsConfig.AndroidGameId; }
        }

        static string AdUnit
        {
            get { return Application.platform == RuntimePlatform.IPhonePlayer ? AdsConfig.IosInterstitial : AdsConfig.AndroidInterstitial; }
        }

        static bool Configured { get { return !GameId.StartsWith("YOUR_"); } }

        void Start()
        {
#if SHOX_UNITY_ADS
            if (!Configured)
            {
                Debug.Log("[Ads] Unity Ads подключён, но Game ID не задан (AdsConfig). Реклама отключена.");
                return;
            }
            if (!Advertisement.isSupported) return;
            if (Advertisement.isInitialized) { initialized = true; Load(); }
            else Advertisement.Initialize(GameId, AdsConfig.TestMode, this);
#endif
        }

        /// <summary>Показать рекламу (если она готова), затем выполнить действие.</summary>
        public static void ShowThen(Action then)
        {
            if (I == null) { if (then != null) then(); return; }
            I.Show(then);
        }

        void Show(Action then)
        {
            if (busy) return;
            bool cooldown = Time.realtimeSinceStartup - lastShown < AdsConfig.MinSecondsBetweenAds;
            if (!initialized || cooldown)
            {
                if (then != null) then();
                return;
            }
            StartCoroutine(ShowRoutine(then));
        }

        IEnumerator ShowRoutine(Action then)
        {
            busy = true;
            if (!loaded && !loading) Load();
            for (float t = 0; t < AdsConfig.LoadWaitSeconds && !loaded; t += Time.unscaledDeltaTime) yield return null;
#if SHOX_UNITY_ADS
            if (loaded)
            {
                loaded = false;
                showing = true;
                AudioListener.pause = true;
                Advertisement.Show(AdUnit, this);
                for (float t = 0; t < 120f && showing; t += Time.unscaledDeltaTime) yield return null;
                showing = false;
                AudioListener.pause = false;
                lastShown = Time.realtimeSinceStartup;
                Load();
            }
#endif
            busy = false;
            if (then != null) then();
        }

        void Load()
        {
#if SHOX_UNITY_ADS
            if (!initialized || loading) return;
            loading = true;
            Advertisement.Load(AdUnit, this);
#endif
        }

#if SHOX_UNITY_ADS
        public void OnInitializationComplete()
        {
            Debug.Log("[Ads] Unity Ads инициализирован, Game ID " + GameId + (AdsConfig.TestMode ? " (тестовый режим)" : ""));
            initialized = true;
            Load();
        }

        public void OnInitializationFailed(UnityAdsInitializationError error, string message)
        {
            Debug.LogWarning("[Ads] Ошибка инициализации: " + error + " " + message);
        }

        public void OnUnityAdsAdLoaded(string placementId)
        {
            Debug.Log("[Ads] Реклама загружена: " + placementId);
            loading = false;
            loaded = true;
        }

        public void OnUnityAdsFailedToLoad(string placementId, UnityAdsLoadError error, string message)
        {
            loading = false;
            loaded = false;
            Debug.LogWarning("[Ads] Не удалось загрузить «" + placementId + "»: " + error + " " + message);
            // повторим попытку чуть позже (нет сети, нет показа и т.п.)
            Invoke("Load", 20f);
        }

        public void OnUnityAdsShowFailure(string placementId, UnityAdsShowError error, string message)
        {
            showing = false;
            Debug.LogWarning("[Ads] Ошибка показа: " + error + " " + message);
        }

        public void OnUnityAdsShowStart(string placementId) { }

        public void OnUnityAdsShowClick(string placementId) { }

        public void OnUnityAdsShowComplete(string placementId, UnityAdsShowCompletionState showCompletionState)
        {
            showing = false;
        }
#endif

        void OnApplicationPause(bool paused)
        {
            if (!paused && !showing) AudioListener.pause = false;
        }
    }
}
