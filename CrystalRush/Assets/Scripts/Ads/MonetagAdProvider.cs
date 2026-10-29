using System;
using System.Runtime.InteropServices;
using UnityEngine;

/// <summary>
/// Monetag ads for the WebGL build. The real work is done in JavaScript:
/// Assets/Plugins/WebGL/MonetagBridge.jslib loads the Monetag SDK for our zone and calls show_ZONEID().
/// When the ad ends, JavaScript calls AdManager.OnWebAdResult("rewarded" / "closed" / "failed").
/// In the Editor this class is never used (AdManager uses the stub there).
/// </summary>
public class MonetagAdProvider : IAdProvider
{
#if UNITY_WEBGL && !UNITY_EDITOR
    [DllImport("__Internal")] static extern void Monetag_Init(string zoneId);
    [DllImport("__Internal")] static extern int Monetag_IsReady(string zoneId);
    [DllImport("__Internal")] static extern void Monetag_Show(string zoneId, string gameObjectName, int rewarded);
#else
    static void Monetag_Init(string zoneId) { }
    static int Monetag_IsReady(string zoneId) => 0;
    static void Monetag_Show(string zoneId, string gameObjectName, int rewarded) { }
#endif

    readonly string callbackObjectName;
    readonly string rewardedZoneId;
    readonly string interstitialZoneId;

    Action<AdResult> rewardedCallback;
    Action interstitialCallback;

    public MonetagAdProvider(string callbackObjectName, string rewardedZoneId, string interstitialZoneId)
    {
        this.callbackObjectName = callbackObjectName;
        this.rewardedZoneId = rewardedZoneId;
        this.interstitialZoneId = interstitialZoneId;
    }

    public string Name => "Monetag (WebGL)";
    public bool IsRewardedReady => Monetag_IsReady(rewardedZoneId) == 1;
    public bool IsInterstitialReady => Monetag_IsReady(interstitialZoneId) == 1;

    public void Initialize()
    {
        Monetag_Init(rewardedZoneId);
        if (interstitialZoneId != rewardedZoneId) Monetag_Init(interstitialZoneId);
    }

    public void ShowRewarded(Action<AdResult> onFinished)
    {
        rewardedCallback = onFinished;
        Monetag_Show(rewardedZoneId, callbackObjectName, 1);
    }

    public void ShowInterstitial(Action onClosed)
    {
        interstitialCallback = onClosed;
        Monetag_Show(interstitialZoneId, callbackObjectName, 0);
    }

    /// <summary>Result from JavaScript: "rewarded", "closed" or "failed".</summary>
    public void HandleResult(string result)
    {
        if (rewardedCallback != null)
        {
            Action<AdResult> callback = rewardedCallback;
            rewardedCallback = null;
            if (result == "rewarded") callback(AdResult.Rewarded);
            else if (result == "closed") callback(AdResult.Skipped);
            else callback(AdResult.NotAvailable);
        }
        else if (interstitialCallback != null)
        {
            Action callback = interstitialCallback;
            interstitialCallback = null;
            callback();
        }
    }
}
