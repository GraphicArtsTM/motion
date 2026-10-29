using System;
using System.Collections.Concurrent;
using UnityEngine;

/// <summary>
/// THE ONLY PLACE FOR ADS. Game code calls AdManager.Instance and never an ad SDK directly.
///  - Rewarded: only when the player presses a "Watch ad" button (main menu or Game Over).
///  - Interstitial: only BETWEEN rounds (restart / next level), every N-th time and not too often, never during play.
///  - Editor and PC build: a stub (fake ad) so the game logic can be tested without real ads.
///  - Android: Unity LevelPlay. WebGL: Monetag through a small JavaScript bridge.
///
/// Stability rules - the game can never get stuck because of an ad:
///  1. Every callback from an SDK is moved to the Unity main thread.
///  2. Every shown ad has a watchdog timer: if the SDK never answers, the ad is finished for it.
///  3. Every request gets exactly ONE answer (late or double SDK callbacks are ignored).
///  4. Ads that failed to load are loaded again later (5 s, 10 s, 20 s ... up to 60 s).
/// </summary>
public class AdManager : MonoBehaviour, IAdHost
{
    static AdManager instance;

    /// <summary>Always returns an AdManager. If a scene has none (started from the Editor), one is created.</summary>
    public static AdManager Instance
    {
        get
        {
            if (instance == null)
            {
                instance = FindFirstObjectByType<AdManager>();
                if (instance == null) instance = new GameObject("AdManager").AddComponent<AdManager>();
            }
            return instance;
        }
    }

    enum AdKind { None, Rewarded, Interstitial }

    [Header("Rules")]
    [Tooltip("Show an interstitial on every N-th finished round (restart or next level).")]
    [SerializeField, Min(1)] int interstitialEveryNRounds = 3;
    [Tooltip("At least this many seconds between two interstitials (also counted from the game start).")]
    [SerializeField, Min(0f)] float minSecondsBetweenInterstitials = 30f;

    [Header("Stability")]
    [Tooltip("If the ad has not opened after this many seconds, give up (no reward, game goes on).")]
    [SerializeField, Min(3f)] float openTimeout = 15f;
    [Tooltip("Longest time an opened ad may take (only time when our app is in front is counted).")]
    [SerializeField, Min(10f)] float maxAdDuration = 120f;
    [Tooltip("Some networks send 'rewarded' a moment AFTER 'closed'. Wait this long for it.")]
    [SerializeField, Min(0f)] float rewardGraceTime = 1f;
    [SerializeField, Min(1f)] float firstRetryDelay = 5f;
    [SerializeField, Min(1f)] float maxRetryDelay = 60f;

    [Header("Testing")]
    [Tooltip("Use the fake ad even in Android/WebGL builds (for tests without an approved account).")]
    [SerializeField] bool forceStub = false;
    [Tooltip("The stub pretends that no ad was loaded - to test the 'ad not available' case.")]
    [SerializeField] bool stubSimulateNoFill = false;
    [SerializeField] float stubRewardedSeconds = 5f;
    [SerializeField] float stubInterstitialSeconds = 3f;
    [Tooltip("Font of the fake ad (must have Cyrillic and Uzbek letters).")]
    [SerializeField] Font stubFont;

    [Serializable]
    public class LevelPlayKeys
    {
        // Demo keys from Unity's official LevelPlay sample: they show TEST ads.
        // Replace them with the keys of YOUR app from the LevelPlay dashboard to earn money.
        public string appKey = "25b63cf85";
        public string rewardedAdUnitId = "syz3d8ekts22q0or";
        public string interstitialAdUnitId = "h3xw38h9214adgxo";
    }

    [Serializable]
    public class MonetagZones
    {
        [Tooltip("Zone ID of the Monetag 'Rewarded Interstitial' zone (numbers only).")]
        public string rewardedZoneId = "0000000";
        public string interstitialZoneId = "0000000";
    }

    [Header("Unity LevelPlay (Android)")]
    [SerializeField] LevelPlayKeys levelPlay = new LevelPlayKeys();

    [Header("Monetag (WebGL)")]
    [SerializeField] MonetagZones monetag = new MonetagZones();

    // SDK callbacks can come from other threads; they wait here until Update runs them.
    readonly ConcurrentQueue<Action> mainThreadQueue = new ConcurrentQueue<Action>();

    IAdProvider provider;
    int finishedRounds;
    float lastInterstitialTime;
    float nextLoadTime;
    float retryDelay;
    bool appInFront = true;

    // The ad that is on the screen right now.
    AdKind showing = AdKind.None;
    Action<AdResult> rewardedCallback;
    Action interstitialCallback;
    bool opened;
    bool rewardEarned;
    float watchdog;
    float graceLeft = -1f;

    public string ProviderName => provider != null ? provider.Name : "none";
    public bool IsShowingAd => showing != AdKind.None;
    public bool IsRewardedReady => provider != null && SafeCheck(() => provider.IsRewardedReady);

    void Awake()
    {
        if (instance != null && instance != this)
        {
            Destroy(gameObject);
            return;
        }
        instance = this;
        DontDestroyOnLoad(gameObject);

        retryDelay = firstRetryDelay;
        lastInterstitialTime = Time.realtimeSinceStartup;

        provider = CreateProvider();
        try
        {
            provider.Initialize(this);
        }
        catch (Exception exception)
        {
            Debug.LogWarning($"AdManager: {provider.Name} failed to start ({exception.Message}), using the stub.");
            provider = CreateStub();
            provider.Initialize(this);
        }
        Debug.Log($"AdManager: using {provider.Name}");
    }

    IAdProvider CreateProvider()
    {
        if (forceStub) return CreateStub();

#if UNITY_EDITOR
        return CreateStub();
#elif UNITY_ANDROID && LEVELPLAY_ENABLED
        return new LevelPlayAdProvider(levelPlay.appKey, levelPlay.rewardedAdUnitId, levelPlay.interstitialAdUnitId);
#elif UNITY_WEBGL
        return new MonetagAdProvider(gameObject.name, monetag.rewardedZoneId, monetag.interstitialZoneId);
#else
        return CreateStub();
#endif
    }

    IAdProvider CreateStub()
    {
        StubAdProvider stub = gameObject.GetComponent<StubAdProvider>();
        if (stub == null) stub = gameObject.AddComponent<StubAdProvider>();
        stub.Setup(stubRewardedSeconds, stubInterstitialSeconds, stubSimulateNoFill, stubFont);
        return stub;
    }

    void Update()
    {
        while (mainThreadQueue.TryDequeue(out Action action))
        {
            try { action(); }
            catch (Exception exception) { Debug.LogException(exception); }
        }

        UpdateWatchdog();
        UpdateLoading();
    }

    // ---------------------------------------------------------------- public API for the game

    /// <summary>
    /// Rewarded ad. AdResult.Rewarded = the player watched it, give the bonus.
    /// The callback is ALWAYS called exactly once (also when there is no ad).
    /// </summary>
    public void ShowRewarded(Action<AdResult> onResult)
    {
        if (IsShowingAd || !IsRewardedReady)
        {
            RequestLoadSoon();
            onResult?.Invoke(AdResult.NotAvailable);
            return;
        }

        rewardedCallback = onResult;
        BeginAd(AdKind.Rewarded);
        if (!SafeCall(provider.ShowRewarded)) FinishAd();
    }

    /// <summary>
    /// Call this when a round is over and the next one is about to start (restart, next level).
    /// Every N-th time an interstitial is shown first. 'continueGame' is always called in the end,
    /// even if there is no ad, so the game can never get stuck because of ads.
    /// </summary>
    public void OnRoundFinished(Action continueGame)
    {
        finishedRounds++;
        bool nthRound = finishedRounds % interstitialEveryNRounds == 0;
        bool notTooOften = Time.realtimeSinceStartup - lastInterstitialTime >= minSecondsBetweenInterstitials;
        bool ready = provider != null && SafeCheck(() => provider.IsInterstitialReady);

        if (!nthRound || !notTooOften || IsShowingAd || !ready)
        {
            if (nthRound && !ready) RequestLoadSoon();
            continueGame?.Invoke();
            return;
        }

        interstitialCallback = continueGame;
        BeginAd(AdKind.Interstitial);
        if (!SafeCall(provider.ShowInterstitial)) FinishAd();
    }

    // ---------------------------------------------------------------- IAdHost (called by providers, any thread)

    public void OnAdOpened() => RunOnMainThread(() =>
    {
        if (showing == AdKind.None || opened) return;
        opened = true;
        watchdog = maxAdDuration;
    });

    public void OnRewardEarned() => RunOnMainThread(() =>
    {
        if (showing != AdKind.Rewarded) return;
        rewardEarned = true;
        if (graceLeft >= 0f) FinishAd(); // the ad was already closed, we were only waiting for this
    });

    public void OnAdClosed() => RunOnMainThread(() =>
    {
        if (showing == AdKind.None) return;
        opened = true;
        if (showing == AdKind.Rewarded && !rewardEarned && rewardGraceTime > 0f)
            graceLeft = rewardGraceTime; // the reward may still come
        else
            FinishAd();
    });

    public void OnAdFailedToShow() => RunOnMainThread(() =>
    {
        if (showing == AdKind.None) return;
        opened = false;
        rewardEarned = false;
        FinishAd();
    });

    // Called from JavaScript (WebGL, MonetagBridge.jslib) with SendMessage.
    public void OnWebAdResult(string result)
    {
        switch (result)
        {
            case "rewarded": OnRewardEarned(); OnAdClosed(); break;
            case "closed": OnAdClosed(); break;
            default: OnAdFailedToShow(); break;
        }
    }

    // ---------------------------------------------------------------- inside

    void RunOnMainThread(Action action) => mainThreadQueue.Enqueue(action);

    void BeginAd(AdKind kind)
    {
        showing = kind;
        opened = false;
        rewardEarned = false;
        graceLeft = -1f;
        watchdog = openTimeout;
        AudioManager.SetPausedForAd(true);
    }

    /// <summary>The ONLY place where an ad ends and the game gets its answer.</summary>
    void FinishAd()
    {
        if (showing == AdKind.None) return;

        AdKind finished = showing;
        AdResult result = rewardEarned ? AdResult.Rewarded : (opened ? AdResult.Skipped : AdResult.NotAvailable);
        showing = AdKind.None;
        graceLeft = -1f;
        AudioManager.SetPausedForAd(false);
        RequestLoadSoon(); // prepare the next ad

        if (finished == AdKind.Interstitial)
        {
            lastInterstitialTime = Time.realtimeSinceStartup;
            Action callback = interstitialCallback;
            interstitialCallback = null;
            SafeInvoke(() => callback?.Invoke());
        }
        else
        {
            Action<AdResult> callback = rewardedCallback;
            rewardedCallback = null;
            SafeInvoke(() => callback?.Invoke(result));
        }
    }

    void UpdateWatchdog()
    {
        if (showing == AdKind.None || !appInFront) return;

        // While a real ad is open, Android pauses our app; that time is not counted.
        float delta = Mathf.Min(Time.unscaledDeltaTime, 0.25f);
        if (graceLeft >= 0f)
        {
            graceLeft -= delta;
            if (graceLeft < 0f) FinishAd();
            return;
        }

        watchdog -= delta;
        if (watchdog <= 0f)
        {
            Debug.LogWarning($"AdManager: {provider.Name} did not answer in time, the ad is finished by the watchdog.");
            if (!opened) rewardEarned = false;
            FinishAd();
        }
    }

    void UpdateLoading()
    {
        if (provider == null || IsShowingAd || Time.realtimeSinceStartup < nextLoadTime) return;

        bool allReady = SafeCheck(() => provider.IsRewardedReady) && SafeCheck(() => provider.IsInterstitialReady);
        if (allReady)
        {
            retryDelay = firstRetryDelay;
            nextLoadTime = Time.realtimeSinceStartup + firstRetryDelay;
            return;
        }

        SafeCall(provider.LoadAds);
        nextLoadTime = Time.realtimeSinceStartup + retryDelay;
        retryDelay = Mathf.Min(retryDelay * 2f, maxRetryDelay); // 5, 10, 20, 40, 60, 60...
    }

    void RequestLoadSoon()
    {
        retryDelay = firstRetryDelay;
        nextLoadTime = Mathf.Min(nextLoadTime, Time.realtimeSinceStartup + 0.5f);
    }

    void OnApplicationPause(bool paused) => appInFront = !paused;
    void OnApplicationFocus(bool focused) => appInFront = focused;

    static void SafeInvoke(Action action)
    {
        try { action(); }
        catch (Exception exception) { Debug.LogException(exception); }
    }

    bool SafeCall(Action action)
    {
        try
        {
            action();
            return true;
        }
        catch (Exception exception)
        {
            Debug.LogWarning($"AdManager: {ProviderName} error: {exception.Message}");
            return false;
        }
    }

    bool SafeCheck(Func<bool> check)
    {
        try { return check(); }
        catch { return false; }
    }
}
