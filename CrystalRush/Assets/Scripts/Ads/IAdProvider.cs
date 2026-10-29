using System;

/// <summary>How a rewarded ad ended.</summary>
public enum AdResult
{
    Rewarded,     // watched to the end - give the bonus
    Skipped,      // the player closed it early - no bonus
    NotAvailable  // no ad loaded / no internet / error / timeout
}

/// <summary>
/// One ad network. AdManager talks to ads only through this interface,
/// so we can swap Unity LevelPlay (Android), Monetag (WebGL) and the stub (Editor/PC)
/// without touching the game code.
/// A provider only loads and shows ads and REPORTS what happened to the host (AdManager).
/// All the rules (timeouts, retries, rewards) live in AdManager, in one place.
/// </summary>
public interface IAdProvider
{
    string Name { get; }
    bool IsRewardedReady { get; }
    bool IsInterstitialReady { get; }

    void Initialize(IAdHost host);

    /// <summary>Loads what is missing. Safe to call often: it does nothing while a load is already running.</summary>
    void LoadAds();

    void ShowRewarded();
    void ShowInterstitial();
}

/// <summary>
/// What a provider tells AdManager. These methods may be called from any thread:
/// AdManager moves them to the Unity main thread itself.
/// </summary>
public interface IAdHost
{
    void OnAdOpened();          // the ad is on the screen
    void OnRewardEarned();      // rewarded ad watched to the end
    void OnAdClosed();          // the player closed the ad
    void OnAdFailedToShow();    // the ad could not be shown at all
}
