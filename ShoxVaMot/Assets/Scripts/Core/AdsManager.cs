using System;
using System.Collections;
using UnityEngine;
#if SHOX_UNITY_ADS
using UnityEngine.Advertisements;
#endif

namespace Shatranj.Core
{
    /// <summary>
    /// Настройки рекламы. Game ID и ID рекламного блока — из Unity Dashboard → Monetization → Placements.
    /// Перед публикацией в Google Play поставьте TestMode = false.
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
        /// <summary>Сколько ждать инициализации и загрузки ролика, прежде чем начать партию без рекламы.</summary>
        public const float LoadWaitSeconds = 7f;
    }

    /// <summary>
    /// Межстраничная реклама Unity Ads перед началом партии.
    ///
    /// Важно для Android: SDK вызывает обработчики (OnInitializationComplete, OnUnityAdsAdLoaded…)
    /// из Java-потока, а не из главного потока Unity. Поэтому обработчики здесь только ставят флажки,
    /// а все вызовы Unity и SDK делаются в Update() главного потока.
    /// </summary>
    public class AdsManager : MonoBehaviour
#if SHOX_UNITY_ADS
        , IUnityAdsInitializationListener, IUnityAdsLoadListener, IUnityAdsShowListener
#endif
    {
        public static AdsManager I { get; private set; }

#pragma warning disable 0649, 0414, 0169 // без пакета Unity Ads часть полей не используется
        // флажки, которые выставляют обработчики SDK из любого потока
        volatile bool initialized, initFailed, loaded, loadFailed, showDone;
        volatile string lastError = "";
        bool initRequested, loading, showing, busy;
        float lastShown = -9999f, retryAt = -1f;
#pragma warning restore 0649, 0414, 0169

        public static AdsManager Create(Transform parent)
        {
            var go = new GameObject("Ads");
            go.transform.SetParent(parent, false);
            I = go.AddComponent<AdsManager>();
            return I;
        }

        static string GameId
        {
            get
            {
#if UNITY_IOS
                return AdsConfig.IosGameId;
#else
                return AdsConfig.AndroidGameId;
#endif
            }
        }

        static string AdUnit
        {
            get
            {
#if UNITY_IOS
                return AdsConfig.IosInterstitial;
#else
                return AdsConfig.AndroidInterstitial;
#endif
            }
        }

        static bool Configured { get { return !GameId.StartsWith("YOUR_"); } }

        /// <summary>Короткий отчёт о состоянии рекламы (скрытая диагностика в «Об игре»).</summary>
        public static string Status
        {
            get
            {
#if SHOX_UNITY_ADS
                if (I == null) return "Ads: нет менеджера";
                if (!Configured) return "Ads: не задан Game ID";
                return "Ads " + GameId + " / " + AdUnit + (AdsConfig.TestMode ? " (test)" : "") +
                       "\ninit: " + (I.initialized ? "OK" : I.initFailed ? "ОШИБКА" : I.initRequested ? "идёт…" : "нет") +
                       ", ролик: " + (I.loaded ? "загружен" : I.loading ? "грузится…" : "нет") +
                       (string.IsNullOrEmpty(I.lastError) ? "" : "\n" + I.lastError);
#else
                return "Ads: пакет com.unity.ads не подключён (нет SHOX_UNITY_ADS)";
#endif
            }
        }

        void Start()
        {
#if SHOX_UNITY_ADS
            if (!Configured)
            {
                Debug.Log("[Ads] Game ID не задан (AdsConfig). Реклама отключена.");
                return;
            }
            if (!Advertisement.isSupported)
            {
                lastError = "Платформа не поддерживается";
                return;
            }
            initRequested = true;
            if (Advertisement.isInitialized) initialized = true;
            else Advertisement.Initialize(GameId, AdsConfig.TestMode, this);
#endif
        }

        void Update()
        {
#if SHOX_UNITY_ADS
            if (!initialized) return;
            // загрузка ролика — только из главного потока
            if (loadFailed)
            {
                loadFailed = false;
                loading = false;
                retryAt = Time.realtimeSinceStartup + 15f;
            }
            if (!loaded && !loading && !showing && Time.realtimeSinceStartup >= retryAt)
            {
                loading = true;
                retryAt = -1f;
                Advertisement.Load(AdUnit, this);
            }
            if (loaded) loading = false;
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
            if (!initRequested || initFailed || cooldown)
            {
                if (then != null) then();
                return;
            }
            StartCoroutine(ShowRoutine(then));
        }

        IEnumerator ShowRoutine(Action then)
        {
            busy = true;
#if SHOX_UNITY_ADS
            // ждём и инициализацию, и загрузку — на телефоне первая загрузка занимает несколько секунд
            for (float t = 0; t < AdsConfig.LoadWaitSeconds && !loaded && !initFailed; t += Time.unscaledDeltaTime) yield return null;
            if (loaded)
            {
                loaded = false;
                showDone = false;
                showing = true;
                AudioListener.pause = true;
                Advertisement.Show(AdUnit, this);
                for (float t = 0; t < 120f && !showDone; t += Time.unscaledDeltaTime) yield return null;
                showing = false;
                AudioListener.pause = false;
                lastShown = Time.realtimeSinceStartup;
            }
            else Debug.Log("[Ads] Ролик не успел загрузиться — партия начинается без рекламы. " + Status);
#endif
            busy = false;
            yield return null;
            if (then != null) then();
        }

#if SHOX_UNITY_ADS
        // ---- обработчики SDK: могут прийти из Java-потока, поэтому только флажки и Debug.Log

        public void OnInitializationComplete()
        {
            initialized = true;
            Debug.Log("[Ads] Инициализация OK, Game ID " + AdsConfig.AndroidGameId);
        }

        public void OnInitializationFailed(UnityAdsInitializationError error, string message)
        {
            initFailed = true;
            lastError = "init: " + error + " " + message;
            Debug.LogWarning("[Ads] Ошибка инициализации: " + error + " " + message);
        }

        public void OnUnityAdsAdLoaded(string placementId)
        {
            loaded = true;
            Debug.Log("[Ads] Ролик загружен: " + placementId);
        }

        public void OnUnityAdsFailedToLoad(string placementId, UnityAdsLoadError error, string message)
        {
            loaded = false;
            loadFailed = true;
            lastError = "load «" + placementId + "»: " + error + " " + message;
            Debug.LogWarning("[Ads] Не удалось загрузить «" + placementId + "»: " + error + " " + message);
        }

        public void OnUnityAdsShowFailure(string placementId, UnityAdsShowError error, string message)
        {
            lastError = "show: " + error + " " + message;
            showDone = true;
            Debug.LogWarning("[Ads] Ошибка показа: " + error + " " + message);
        }

        public void OnUnityAdsShowStart(string placementId) { }

        public void OnUnityAdsShowClick(string placementId) { }

        public void OnUnityAdsShowComplete(string placementId, UnityAdsShowCompletionState showCompletionState)
        {
            showDone = true;
        }
#endif

        void OnApplicationPause(bool paused)
        {
            if (!paused && !showing) AudioListener.pause = false;
        }
    }
}
