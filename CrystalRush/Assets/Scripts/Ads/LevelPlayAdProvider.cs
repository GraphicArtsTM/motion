// Unity LevelPlay (ironSource) for Android.
// This file compiles only when the scripting define LEVELPLAY_ENABLED is set
// (Project Settings > Player > Android > Scripting Define Symbols), after the
// "Ads Mediation" (com.unity.services.levelplay) package is installed. Without the SDK the
// project still compiles and AdManager uses the stub. Written for the LevelPlay 8.x API.
#if LEVELPLAY_ENABLED
using System;
using Unity.Services.LevelPlay;
using UnityEngine;

public class LevelPlayAdProvider : IAdProvider
{
    readonly string appKey;
    readonly string rewardedAdUnitId;
    readonly string interstitialAdUnitId;

    LevelPlayRewardedAd rewardedAd;
    LevelPlayInterstitialAd interstitialAd;
    Action<AdResult> rewardedCallback;
    Action interstitialCallback;
    bool rewardEarned;

    public LevelPlayAdProvider(string appKey, string rewardedAdUnitId, string interstitialAdUnitId)
    {
        this.appKey = appKey;
        this.rewardedAdUnitId = rewardedAdUnitId;
        this.interstitialAdUnitId = interstitialAdUnitId;
    }

    public string Name => "Unity LevelPlay";
    public bool IsRewardedReady => rewardedAd != null && rewardedAd.IsAdReady();
    public bool IsInterstitialReady => interstitialAd != null && interstitialAd.IsAdReady();

    public void Initialize()
    {
        // Test mode: never click your own real ads! Add your phone as a test device in the LevelPlay dashboard.
        LevelPlay.OnInitSuccess += OnInitSuccess;
        LevelPlay.OnInitFailed += error => Debug.LogWarning("LevelPlay init failed: " + error);
        LevelPlay.Init(appKey);
    }

    void OnInitSuccess(LevelPlayConfiguration configuration)
    {
        rewardedAd = new LevelPlayRewardedAd(rewardedAdUnitId);
        rewardedAd.OnAdRewarded += (adInfo, reward) => rewardEarned = true;
        rewardedAd.OnAdClosed += adInfo => FinishRewarded(rewardEarned ? AdResult.Rewarded : AdResult.Skipped);
        rewardedAd.OnAdDisplayFailed += error => FinishRewarded(AdResult.NotAvailable);
        rewardedAd.OnAdLoadFailed += error => Debug.Log("LevelPlay rewarded not loaded: " + error);
        rewardedAd.LoadAd();

        interstitialAd = new LevelPlayInterstitialAd(interstitialAdUnitId);
        interstitialAd.OnAdClosed += adInfo => FinishInterstitial();
        interstitialAd.OnAdDisplayFailed += error => FinishInterstitial();
        interstitialAd.OnAdLoadFailed += error => Debug.Log("LevelPlay interstitial not loaded: " + error);
        interstitialAd.LoadAd();
    }

    public void ShowRewarded(Action<AdResult> onFinished)
    {
        rewardedCallback = onFinished;
        rewardEarned = false;
        rewardedAd.ShowAd();
    }

    public void ShowInterstitial(Action onClosed)
    {
        interstitialCallback = onClosed;
        interstitialAd.ShowAd();
    }

    void FinishRewarded(AdResult result)
    {
        Action<AdResult> callback = rewardedCallback;
        rewardedCallback = null;
        rewardedAd.LoadAd(); // load the next one right away
        callback?.Invoke(result);
    }

    void FinishInterstitial()
    {
        Action callback = interstitialCallback;
        interstitialCallback = null;
        interstitialAd.LoadAd();
        callback?.Invoke();
    }
}
#endif
