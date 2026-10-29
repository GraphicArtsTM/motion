// Unity LevelPlay for Android (package com.unity.services.levelplay 9.x, already in Packages/manifest.json).
// This file compiles only with the LEVELPLAY_ENABLED define. The editor script LevelPlayDefineGuard
// adds it for Android automatically while the package is installed and removes it if the package is removed,
// so the project always compiles.
#if LEVELPLAY_ENABLED
using Unity.Services.LevelPlay;
using UnityEngine;

public class LevelPlayAdProvider : IAdProvider
{
    readonly string appKey;
    readonly string rewardedAdUnitId;
    readonly string interstitialAdUnitId;

    IAdHost host;
    LevelPlayRewardedAd rewardedAd;
    LevelPlayInterstitialAd interstitialAd;
    bool initialized;
    bool initializing;
    bool rewardedLoading;
    bool interstitialLoading;
    float rewardedLoadStart;
    float interstitialLoadStart;

    // If the SDK never answers a load request, we allow a new one after this time.
    const float LoadAnswerTimeout = 60f;

    public LevelPlayAdProvider(string appKey, string rewardedAdUnitId, string interstitialAdUnitId)
    {
        this.appKey = appKey;
        this.rewardedAdUnitId = rewardedAdUnitId;
        this.interstitialAdUnitId = interstitialAdUnitId;
    }

    public string Name => "Unity LevelPlay";
    public bool IsRewardedReady => rewardedAd != null && rewardedAd.IsAdReady();
    public bool IsInterstitialReady => interstitialAd != null && interstitialAd.IsAdReady();

    public void Initialize(IAdHost host)
    {
        this.host = host;
        // Never click your own real ads! Add your phone as a test device in the LevelPlay dashboard.
        LevelPlay.OnInitSuccess += OnInitSuccess;
        LevelPlay.OnInitFailed += OnInitFailed;
        StartInit();
    }

    void StartInit()
    {
        initializing = true;
        LevelPlay.Init(appKey);
    }

    void OnInitSuccess(LevelPlayConfiguration configuration)
    {
        initializing = false;
        if (initialized) return;
        initialized = true;

        rewardedAd = new LevelPlayRewardedAd(rewardedAdUnitId);
        rewardedAd.OnAdLoaded += info => rewardedLoading = false;
        rewardedAd.OnAdLoadFailed += error =>
        {
            rewardedLoading = false;
            Debug.Log("LevelPlay: rewarded not loaded: " + error);
        };
        rewardedAd.OnAdDisplayed += info => host.OnAdOpened();
        rewardedAd.OnAdRewarded += (info, reward) => host.OnRewardEarned();
        rewardedAd.OnAdClosed += info => host.OnAdClosed();
        rewardedAd.OnAdDisplayFailed += (info, error) => host.OnAdFailedToShow();

        interstitialAd = new LevelPlayInterstitialAd(interstitialAdUnitId);
        interstitialAd.OnAdLoaded += info => interstitialLoading = false;
        interstitialAd.OnAdLoadFailed += error =>
        {
            interstitialLoading = false;
            Debug.Log("LevelPlay: interstitial not loaded: " + error);
        };
        interstitialAd.OnAdDisplayed += info => host.OnAdOpened();
        interstitialAd.OnAdClosed += info => host.OnAdClosed();
        interstitialAd.OnAdDisplayFailed += (info, error) => host.OnAdFailedToShow();

        LoadAds();
    }

    void OnInitFailed(LevelPlayInitError error)
    {
        // AdManager will call LoadAds again later, and LoadAds tries to start the SDK again.
        initializing = false;
        Debug.LogWarning("LevelPlay: init failed: " + error);
    }

    public void LoadAds()
    {
        if (!initialized)
        {
            if (!initializing) StartInit();
            return;
        }

        float now = Time.realtimeSinceStartup;
        if (rewardedLoading && now - rewardedLoadStart > LoadAnswerTimeout) rewardedLoading = false;
        if (interstitialLoading && now - interstitialLoadStart > LoadAnswerTimeout) interstitialLoading = false;

        if (!rewardedLoading && !rewardedAd.IsAdReady())
        {
            rewardedLoading = true;
            rewardedLoadStart = now;
            rewardedAd.LoadAd();
        }
        if (!interstitialLoading && !interstitialAd.IsAdReady())
        {
            interstitialLoading = true;
            interstitialLoadStart = now;
            interstitialAd.LoadAd();
        }
    }

    public void ShowRewarded()
    {
        if (IsRewardedReady) rewardedAd.ShowAd();
        else host.OnAdFailedToShow();
    }

    public void ShowInterstitial()
    {
        if (IsInterstitialReady) interstitialAd.ShowAd();
        else host.OnAdFailedToShow();
    }
}
#endif
