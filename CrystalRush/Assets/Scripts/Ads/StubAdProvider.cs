using System;
using System.Collections;
using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// A FAKE ad for the Editor and the PC build. It shows a full-screen panel with a countdown,
/// so we can test the whole ad logic (reward, closing early, "no ad loaded") without a real network.
/// The panel is built from code, so no prefab is needed.
/// </summary>
public class StubAdProvider : MonoBehaviour, IAdProvider
{
    float rewardedSeconds = 5f;
    float interstitialSeconds = 3f;
    bool simulateNoFill;

    GameObject overlay;
    Text titleText;
    Text infoText;
    Text timerText;
    Button closeButton;
    Text closeLabel;
    Button skipButton;
    Text skipLabel;
    Font font;
    IAdHost host;
    bool isShowing;

    public string Name => simulateNoFill ? "Stub (no fill)" : "Stub (test ads)";
    public bool IsRewardedReady => !simulateNoFill;
    public bool IsInterstitialReady => !simulateNoFill;

    public void Setup(float rewardedSeconds, float interstitialSeconds, bool simulateNoFill, Font font)
    {
        this.rewardedSeconds = rewardedSeconds;
        this.interstitialSeconds = interstitialSeconds;
        this.simulateNoFill = simulateNoFill;
        this.font = font;
    }

    public void Initialize(IAdHost host)
    {
        this.host = host;
        if (font == null) font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
    }

    public void LoadAds()
    {
        // A fake ad is always "loaded" (unless we simulate "no fill").
    }

    public void ShowRewarded()
    {
        if (!TryStart()) return;
        StartCoroutine(ShowAd(true, rewardedSeconds));
    }

    public void ShowInterstitial()
    {
        if (!TryStart()) return;
        StartCoroutine(ShowAd(false, interstitialSeconds));
    }

    bool TryStart()
    {
        if (simulateNoFill || isShowing)
        {
            host.OnAdFailedToShow();
            return false;
        }
        isShowing = true;
        return true;
    }

    IEnumerator ShowAd(bool isRewarded, float seconds)
    {
        if (overlay == null) BuildOverlay();
        host.OnAdOpened();
        overlay.SetActive(true);

        titleText.text = Localization.Get("ad_test_title");
        infoText.text = Localization.Get(isRewarded ? "ad_test_rewarded" : "ad_test_inter");
        closeLabel.text = Localization.Get("ad_close");
        skipLabel.text = Localization.Get("ad_skip");
        closeButton.gameObject.SetActive(false);
        // A rewarded ad can be skipped, but then there is no reward.
        skipButton.gameObject.SetActive(isRewarded);

        bool closed = false;
        bool skipped = false;
        closeButton.onClick.RemoveAllListeners();
        closeButton.onClick.AddListener(() => closed = true);
        skipButton.onClick.RemoveAllListeners();
        skipButton.onClick.AddListener(() => skipped = true);

        // Unscaled time: the game is paused (Time.timeScale = 0) while the ad is shown.
        float timeLeft = seconds;
        while (timeLeft > 0f && !skipped)
        {
            timerText.text = Localization.Format("ad_wait", Mathf.CeilToInt(timeLeft));
            timeLeft -= Time.unscaledDeltaTime;
            yield return null;
        }

        if (!skipped)
        {
            timerText.text = string.Empty;
            skipButton.gameObject.SetActive(false);
            closeButton.gameObject.SetActive(true);
            while (!closed) yield return null;
        }

        overlay.SetActive(false);
        isShowing = false;
        if (isRewarded && !skipped) host.OnRewardEarned();
        host.OnAdClosed();
    }

    void BuildOverlay()
    {
        overlay = new GameObject("StubAdOverlay", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        overlay.transform.SetParent(transform, false);
        Canvas canvas = overlay.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 1000; // above all game UI
        CanvasScaler scaler = overlay.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920f, 1080f);
        scaler.matchWidthOrHeight = 0.5f;

        Image background = CreateRect("Background", overlay.transform, Vector2.zero, Vector2.one).gameObject.AddComponent<Image>();
        background.color = new Color(0.05f, 0.04f, 0.12f, 0.97f);

        titleText = CreateText("Title", overlay.transform, new Vector2(0.5f, 0.72f), 72, new Color(1f, 0.85f, 0.3f));
        infoText = CreateText("Info", overlay.transform, new Vector2(0.5f, 0.58f), 40, Color.white);
        timerText = CreateText("Timer", overlay.transform, new Vector2(0.5f, 0.45f), 44, new Color(0.6f, 0.9f, 1f));

        closeButton = CreateButton("CloseButton", overlay.transform, new Vector2(0.5f, 0.3f), new Color(0.2f, 0.75f, 0.45f), out closeLabel);
        skipButton = CreateButton("SkipButton", overlay.transform, new Vector2(0.5f, 0.16f), new Color(0.45f, 0.45f, 0.55f), out skipLabel);
    }

    RectTransform CreateRect(string name, Transform parent, Vector2 anchorMin, Vector2 anchorMax)
    {
        RectTransform rect = new GameObject(name, typeof(RectTransform)).GetComponent<RectTransform>();
        rect.SetParent(parent, false);
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        return rect;
    }

    Text CreateText(string name, Transform parent, Vector2 anchor, int size, Color color)
    {
        RectTransform rect = CreateRect(name, parent, anchor, anchor);
        rect.sizeDelta = new Vector2(1600f, 120f);
        Text text = rect.gameObject.AddComponent<Text>();
        text.font = font;
        text.fontSize = size;
        text.color = color;
        text.alignment = TextAnchor.MiddleCenter;
        text.raycastTarget = false;
        return text;
    }

    Button CreateButton(string name, Transform parent, Vector2 anchor, Color color, out Text label)
    {
        RectTransform rect = CreateRect(name, parent, anchor, anchor);
        rect.sizeDelta = new Vector2(520f, 110f);
        Image image = rect.gameObject.AddComponent<Image>();
        image.color = color;
        Button button = rect.gameObject.AddComponent<Button>();
        label = CreateText("Label", rect, new Vector2(0.5f, 0.5f), 40, Color.white);
        label.rectTransform.sizeDelta = new Vector2(500f, 100f);
        return button;
    }
}
