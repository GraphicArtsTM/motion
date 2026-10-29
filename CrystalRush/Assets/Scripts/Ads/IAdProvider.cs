using System;

/// <summary>How a rewarded ad ended.</summary>
public enum AdResult
{
    Rewarded,     // watched to the end - give the bonus
    Skipped,      // the player closed it early - no bonus
    NotAvailable  // no ad loaded / no internet / error
}

/// <summary>
/// One ad network. AdManager talks to ads only through this interface,
/// so we can swap Unity LevelPlay (Android), Monetag (WebGL) and the stub (Editor/PC)
/// without touching the game code.
/// </summary>
public interface IAdProvider
{
    string Name { get; }
    bool IsRewardedReady { get; }
    bool IsInterstitialReady { get; }

    void Initialize();

    /// <summary>onFinished(AdResult.Rewarded) only if the ad was watched to the end.</summary>
    void ShowRewarded(Action<AdResult> onFinished);

    /// <summary>onClosed is called when the ad is closed OR failed to show.</summary>
    void ShowInterstitial(Action onClosed);
}
