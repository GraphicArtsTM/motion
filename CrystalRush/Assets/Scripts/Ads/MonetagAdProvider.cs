using System.Runtime.InteropServices;

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
    IAdHost host;

    public MonetagAdProvider(string callbackObjectName, string rewardedZoneId, string interstitialZoneId)
    {
        this.callbackObjectName = callbackObjectName;
        this.rewardedZoneId = rewardedZoneId;
        this.interstitialZoneId = interstitialZoneId;
    }

    public string Name => "Monetag (WebGL)";
    public bool IsRewardedReady => Monetag_IsReady(rewardedZoneId) == 1;
    public bool IsInterstitialReady => Monetag_IsReady(interstitialZoneId) == 1;

    public void Initialize(IAdHost host)
    {
        this.host = host;
        LoadAds();
    }

    /// <summary>Adds the Monetag SDK script. If it failed to load (no internet, ad blocker), the next call tries again.</summary>
    public void LoadAds()
    {
        Monetag_Init(rewardedZoneId);
        if (interstitialZoneId != rewardedZoneId) Monetag_Init(interstitialZoneId);
    }

    public void ShowRewarded() => Show(rewardedZoneId, true);

    public void ShowInterstitial() => Show(interstitialZoneId, false);

    void Show(string zoneId, bool rewarded)
    {
        if (Monetag_IsReady(zoneId) != 1)
        {
            host.OnAdFailedToShow();
            return;
        }
        // Monetag has no "opened" event, so we count the ad as opened when we ask for it.
        // The answer comes later from JavaScript into AdManager.OnWebAdResult.
        host.OnAdOpened();
        Monetag_Show(zoneId, callbackObjectName, rewarded ? 1 : 0);
    }
}
