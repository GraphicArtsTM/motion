using System;
using System.Runtime.InteropServices;
using UnityEngine;
#if (UNITY_ANDROID || UNITY_IOS) && !UNITY_EDITOR && ROCKET_LEVELPLAY
using Unity.Services.LevelPlay;
#endif

// One entry point for all ads. The game only asks three things:
// "is a rewarded ad ready?", "show a rewarded ad" and "show an interstitial".
//   Android / iOS build + the LevelPlay package installed  -> Unity LevelPlay (rewarded, interstitial, banner)
//   WebGL build                                             -> Monetag through WebAds.jslib (+ Adsterra banners in index.html)
//   Editor, PC, or Android without the LevelPlay package    -> a stub: no ads, the reward is given at once
// The ROCKET_LEVELPLAY define is added automatically by Editor/LevelPlayDefine.cs when the package
// com.unity.services.levelplay is installed, so the project builds for Android with or without it.
// From the ads guide, Part 3.2 (updated for LevelPlay SDK 9.x).
#pragma warning disable 0414 // some key fields are used only on one platform
public class AdManager : MonoBehaviour
{
    public static AdManager Instance { get; private set; }

    [Header("LevelPlay — Android")]
    [SerializeField] string appKey = "YOUR_APP_KEY";
    [SerializeField] string rewardedAdUnitId = "YOUR_REWARDED_ID";
    [SerializeField] string interstitialAdUnitId = "YOUR_INTERSTITIAL_ID";
    [SerializeField] string bannerAdUnitId = "YOUR_BANNER_ID";

    [Header("LevelPlay — iOS (a separate app on the LevelPlay website)")]
    [SerializeField] string iosAppKey = "YOUR_IOS_APP_KEY";
    [SerializeField] string iosRewardedAdUnitId = "YOUR_IOS_REWARDED_ID";
    [SerializeField] string iosInterstitialAdUnitId = "YOUR_IOS_INTERSTITIAL_ID";
    [SerializeField] string iosBannerAdUnitId = "YOUR_IOS_BANNER_ID";

    [Header("Banner")]
    [SerializeField] bool showBanner = true;
    [SerializeField] bool bannerAtTop = false;

    Action onRewarded;
    Action onRewardFailed;
    Action onInterstitialDone;
    bool isDuplicate = false;

    void Awake()
    {
        if (Instance != null) { isDuplicate = true; Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    void Start()
    {
        if (isDuplicate) return;
        PlatformInit();
    }

    // ===== Public API (the game calls it) =====

    public bool IsRewardedReady()
    {
        return PlatformIsRewardedReady();
    }

    public void ShowRewarded(Action onReward, Action onFail = null)
    {
        if (!PlatformIsRewardedReady()) { onFail?.Invoke(); return; }
        onRewarded = onReward;
        onRewardFailed = onFail;
        AudioListener.pause = true; // the rocket engine and the ad must not sound at the same time
        PlatformShowRewarded();
    }

    public void ShowInterstitial(Action onDone)
    {
        onInterstitialDone = onDone;
        AudioListener.pause = true;
        PlatformShowInterstitial();
    }

    // ===== Common "finishes" =====

    void GrantReward()
    {
        AudioListener.pause = false;
        Action a = onRewarded;
        onRewarded = null;
        onRewardFailed = null;
        a?.Invoke();
    }

    void FailReward()
    {
        AudioListener.pause = false;
        Action a = onRewardFailed;
        onRewarded = null;
        onRewardFailed = null;
        a?.Invoke();
    }

    void FinishInterstitial()
    {
        AudioListener.pause = false;
        Action a = onInterstitialDone;
        onInterstitialDone = null;
        a?.Invoke();
    }

#if (UNITY_ANDROID || UNITY_IOS) && !UNITY_EDITOR && ROCKET_LEVELPLAY
    // ===== Android / iOS: Unity LevelPlay (SDK 9.x) =====
    LevelPlayRewardedAd rewardedAd;
    LevelPlayInterstitialAd interstitialAd;
    LevelPlayBannerAd bannerAd;
    bool rewardEarned;

#if UNITY_IOS
    string AppKey => iosAppKey.Trim();
    string RewardedId => iosRewardedAdUnitId.Trim();
    string InterstitialId => iosInterstitialAdUnitId.Trim();
    string BannerId => iosBannerAdUnitId.Trim();
#else
    string AppKey => appKey.Trim();
    string RewardedId => rewardedAdUnitId.Trim();
    string InterstitialId => interstitialAdUnitId.Trim();
    string BannerId => bannerAdUnitId.Trim();
#endif

    void PlatformInit()
    {
        // GDPR / CCPA consent (LevelPlay.SetConsent, LevelPlay.SetMetaData) must be set here, before Init
        LevelPlay.OnInitSuccess += OnLevelPlayReady;
        LevelPlay.OnInitFailed += err => Debug.Log("[Ads] Init failed: " + err);
        LevelPlay.Init(AppKey);
    }

    void OnLevelPlayReady(LevelPlayConfiguration config)
    {
        Debug.Log("[Ads] LevelPlay is ready");
        if (showBanner) CreateBanner(); // the banner appears as soon as the SDK is ready

        rewardedAd = new LevelPlayRewardedAd(RewardedId);
        rewardedAd.OnAdRewarded += (info, reward) => rewardEarned = true;
        rewardedAd.OnAdClosed += info => OnRewardedClosed();
        rewardedAd.OnAdDisplayFailed += (info, err) => OnRewardedClosed();
        rewardedAd.OnAdLoadFailed += err => Debug.Log("[Ads] Rewarded load failed: " + err);
        rewardedAd.LoadAd();

        interstitialAd = new LevelPlayInterstitialAd(InterstitialId);
        interstitialAd.OnAdClosed += info => OnInterstitialClosed();
        interstitialAd.OnAdDisplayFailed += (info, err) => OnInterstitialClosed();
        interstitialAd.OnAdLoadFailed += err => Debug.Log("[Ads] Interstitial load failed: " + err);
        interstitialAd.LoadAd();
    }

    void CreateBanner()
    {
        // 320x50 at the bottom (or the top) in the center. In SDK 9.x size and position go into a Config.
        LevelPlayBannerAd.Config bannerConfig = new LevelPlayBannerAd.Config.Builder()
            .SetSize(LevelPlayAdSize.BANNER)
            .SetPosition(bannerAtTop ? LevelPlayBannerPosition.TopCenter : LevelPlayBannerPosition.BottomCenter)
            .SetDisplayOnLoad(true)
            .Build();
        bannerAd = new LevelPlayBannerAd(BannerId, bannerConfig);
        bannerAd.OnAdLoaded += info => Debug.Log("[Ads] Banner loaded");
        bannerAd.OnAdLoadFailed += err => Debug.Log("[Ads] Banner load failed: " + err);
        bannerAd.LoadAd();
    }

    void OnRewardedClosed()
    {
        if (rewardEarned) GrantReward(); else FailReward();
        rewardEarned = false;
        rewardedAd.LoadAd();
    }

    void OnInterstitialClosed()
    {
        interstitialAd.LoadAd();
        FinishInterstitial();
    }

    bool PlatformIsRewardedReady()
    {
        return rewardedAd != null && rewardedAd.IsAdReady();
    }

    void PlatformShowRewarded()
    {
        rewardEarned = false;
        rewardedAd.ShowAd();
    }

    void PlatformShowInterstitial()
    {
        if (interstitialAd != null && interstitialAd.IsAdReady())
            interstitialAd.ShowAd();
        else
            FinishInterstitial();
    }

#elif UNITY_WEBGL && !UNITY_EDITOR
    // ===== WebGL: Monetag through JavaScript (Assets/Plugins/WebGL/WebAds.jslib) =====
    [DllImport("__Internal")] static extern int WebAd_IsAvailable();
    [DllImport("__Internal")] static extern void WebAd_ShowRewarded();
    [DllImport("__Internal")] static extern void WebAd_ShowInterstitial();

    void PlatformInit() { }
    bool PlatformIsRewardedReady() { return WebAd_IsAvailable() == 1; }
    void PlatformShowRewarded() { WebAd_ShowRewarded(); }
    void PlatformShowInterstitial() { WebAd_ShowInterstitial(); }

#else
    // ===== Editor, PC (and Android/iOS without the LevelPlay package): a stub =====
    void PlatformInit()
    {
        Debug.Log("[Ads] Editor stub: ads are not shown");
    }

    bool PlatformIsRewardedReady() { return true; }

    void PlatformShowRewarded()
    {
        Debug.Log("[Ads] Editor stub: reward given at once");
        GrantReward();
    }

    void PlatformShowInterstitial()
    {
        Debug.Log("[Ads] Editor stub: interstitial skipped");
        FinishInterstitial();
    }
#endif

    // JavaScript (WebGL) calls these methods through SendMessage('AdManager', ...).
    // That is why the object must be named exactly "AdManager".
    public void OnWebRewardedDone() { GrantReward(); }
    public void OnWebRewardedFailed() { FailReward(); }
    public void OnWebInterstitialDone() { FinishInterstitial(); }
}
