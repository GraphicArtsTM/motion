using System;
using UnityEngine;

/// <summary>
/// THE ONLY PLACE FOR ADS. Game code calls AdManager.Instance and never an ad SDK directly.
///  - Rewarded: only when the player presses "Watch ad: +3 lives" on the Game Over screen.
///  - Interstitial: only BETWEEN rounds (restart / next level), every N-th time, never during play.
///  - Editor and PC build: a stub (fake ad) so the game logic can be tested without real ads.
///  - Android: Unity LevelPlay (needs the SDK and the LEVELPLAY_ENABLED define, see README).
///  - WebGL: Monetag through a small JavaScript bridge.
/// </summary>
public class AdManager : MonoBehaviour
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

    [Header("Rules")]
    [Tooltip("Show an interstitial on every N-th finished round (restart or next level).")]
    [SerializeField, Min(1)] int interstitialEveryNRounds = 3;

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
        public string appKey = "YOUR_APP_KEY";
        public string rewardedAdUnitId = "YOUR_REWARDED_AD_UNIT_ID";
        public string interstitialAdUnitId = "YOUR_INTERSTITIAL_AD_UNIT_ID";
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

    IAdProvider provider;
    int finishedRounds;
    bool adIsShowing;

    public string ProviderName => provider != null ? provider.Name : "none";
    public bool IsShowingAd => adIsShowing;

    void Awake()
    {
        if (instance != null && instance != this)
        {
            Destroy(gameObject);
            return;
        }
        instance = this;
        DontDestroyOnLoad(gameObject);

        provider = CreateProvider();
        provider.Initialize();
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
        StubAdProvider stub = gameObject.AddComponent<StubAdProvider>();
        stub.Setup(stubRewardedSeconds, stubInterstitialSeconds, stubSimulateNoFill, stubFont);
        return stub;
    }

    /// <summary>
    /// Rewarded ad. AdResult.Rewarded = the player watched it, give the bonus.
    /// If the ad is not loaded, NotAvailable comes back at once and the game goes on without a bonus.
    /// </summary>
    public void ShowRewarded(Action<AdResult> onResult)
    {
        if (adIsShowing || !provider.IsRewardedReady)
        {
            onResult?.Invoke(AdResult.NotAvailable);
            return;
        }

        BeginAd();
        provider.ShowRewarded(result =>
        {
            EndAd();
            onResult?.Invoke(result);
        });
    }

    /// <summary>
    /// Call this when a round is over and the next one is about to start (restart, next level).
    /// Every N-th time an interstitial is shown first. 'continueGame' is always called in the end,
    /// even if there is no ad, so the game can never get stuck because of ads.
    /// </summary>
    public void OnRoundFinished(Action continueGame)
    {
        finishedRounds++;
        bool timeForAd = finishedRounds % interstitialEveryNRounds == 0;

        if (!timeForAd || adIsShowing || !provider.IsInterstitialReady)
        {
            continueGame?.Invoke();
            return;
        }

        BeginAd();
        provider.ShowInterstitial(() =>
        {
            EndAd();
            continueGame?.Invoke();
        });
    }

    void BeginAd()
    {
        adIsShowing = true;
        AudioManager.SetPausedForAd(true);
    }

    void EndAd()
    {
        adIsShowing = false;
        AudioManager.SetPausedForAd(false);
    }

    // Called from JavaScript (WebGL, MonetagBridge.jslib) with SendMessage.
    public void OnWebAdResult(string result)
    {
        if (provider is MonetagAdProvider web) web.HandleResult(result);
    }
}
