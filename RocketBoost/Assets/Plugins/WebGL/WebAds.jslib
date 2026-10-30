// A bridge from Unity (C#) to JavaScript on the game page (WebGL only).
// C# calls these functions through [DllImport("__Internal")] in AdManager.cs.
// The page (Assets/WebGLTemplates/RocketBoost/index.html) must define
// window.monetagShowRewarded and window.monetagShowInterstitial (functions that return a Promise).
mergeInto(LibraryManager.library, {

  WebAd_IsAvailable: function () {
    return (typeof window.monetagShowRewarded === 'function') ? 1 : 0;
  },

  WebAd_ShowRewarded: function () {
    var send = function (method) {
      if (typeof SendMessage === 'function') {
        SendMessage('AdManager', method);
      } else if (window.unityInstance) {
        window.unityInstance.SendMessage('AdManager', method);
      }
    };
    try {
      if (typeof window.monetagShowRewarded !== 'function') {
        send('OnWebRewardedFailed');
        return;
      }
      Promise.resolve(window.monetagShowRewarded())
        .then(function () { send('OnWebRewardedDone'); })
        .catch(function () { send('OnWebRewardedFailed'); });
    } catch (e) {
      send('OnWebRewardedFailed');
    }
  },

  WebAd_ShowInterstitial: function () {
    var send = function (method) {
      if (typeof SendMessage === 'function') {
        SendMessage('AdManager', method);
      } else if (window.unityInstance) {
        window.unityInstance.SendMessage('AdManager', method);
      }
    };
    try {
      if (typeof window.monetagShowInterstitial !== 'function') {
        send('OnWebInterstitialDone');
        return;
      }
      Promise.resolve(window.monetagShowInterstitial())
        .then(function () { send('OnWebInterstitialDone'); })
        .catch(function () { send('OnWebInterstitialDone'); });
    } catch (e) {
      send('OnWebInterstitialDone');
    }
  }
});
