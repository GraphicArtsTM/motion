/// <summary>
/// ALL AD KEYS IN ONE PLACE. Paste your own keys here (README, section "Реклама").
/// This file is never touched by "Crystal Rush > Build Game", so the keys survive a rebuild.
/// </summary>
public static class AdKeys
{
    // ---------- Unity LevelPlay (Android) ----------
    // LevelPlay dashboard -> Apps: the App Key is next to the app name (copy icon).
    // Ad units -> the "Ad unit ID" column. Package Name of the app must be the same as in Player Settings.
    // Now: Unity's DEMO keys from the official LevelPlay sample - they show test ads only, no money.
    public const string LevelPlayAppKey = "25b63cf85";
    public const string LevelPlayRewardedAdUnitId = "syz3d8ekts22q0or";
    public const string LevelPlayInterstitialAdUnitId = "h3xw38h9214adgxo";

    // ---------- Monetag (WebGL) ----------
    // Monetag -> Sites -> your zone of type "Rewarded Interstitial": the Zone ID (numbers only).
    public const string MonetagRewardedZoneId = "0000000";
    public const string MonetagInterstitialZoneId = "0000000";
}
