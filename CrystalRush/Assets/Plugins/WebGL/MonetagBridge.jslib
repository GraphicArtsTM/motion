// JavaScript bridge between Unity (C#) and the Monetag SDK. Used only in the WebGL build.
// C# side: Assets/Scripts/Ads/MonetagAdProvider.cs, answers go to AdManager.OnWebAdResult.
//
// Monetag gives every zone a function window["show_" + zoneId], created by its SDK script:
//   <script src="//libtl.com/sdk.js" data-zone="ZONE_ID" data-sdk="show_ZONE_ID"></script>
// We add that script from code, so the WebGL template does not need to be changed.
// show_ZONE_ID() returns a Promise: resolved = the ad was watched, rejected = no ad / error.

mergeInto(LibraryManager.library, {

  Monetag_Init: function (zonePtr) {
    var zone = UTF8ToString(zonePtr);
    if (!/^[0-9]+$/.test(zone) || zone === "0000000") {
      if (!window.__monetagWarned) console.warn("[Monetag] Zone ID is not set in AdManager");
      window.__monetagWarned = true;
      return;
    }
    if (typeof window["show_" + zone] === "function") return;             // already loaded
    if (document.querySelector('script[data-zone="' + zone + '"]')) return; // still loading

    var script = document.createElement("script");
    script.src = "https://libtl.com/sdk.js";
    script.async = true;
    script.setAttribute("data-zone", zone);
    script.setAttribute("data-sdk", "show_" + zone);
    script.onerror = function () {
      // Remove the broken tag, so the next Monetag_Init (AdManager retries) can try again.
      console.warn("[Monetag] SDK could not be loaded (no internet or ad blocker)");
      if (script.parentNode) script.parentNode.removeChild(script);
    };
    document.head.appendChild(script);
  },

  Monetag_IsReady: function (zonePtr) {
    var zone = UTF8ToString(zonePtr);
    return (typeof window["show_" + zone] === "function") ? 1 : 0;
  },

  Monetag_Show: function (zonePtr, objectPtr, rewarded) {
    var zone = UTF8ToString(zonePtr);
    var objectName = UTF8ToString(objectPtr);
    var answered = false;

    // Exactly one answer per ad.
    function reply(result) {
      if (answered) return;
      answered = true;
      if (typeof SendMessage === "function") SendMessage(objectName, "OnWebAdResult", result);
      else if (typeof Module !== "undefined" && Module.SendMessage) Module.SendMessage(objectName, "OnWebAdResult", result);
    }

    var show = window["show_" + zone];
    if (typeof show !== "function") { reply("failed"); return; }

    try {
      var promise = show();
      if (!promise || typeof promise.then !== "function") { reply("closed"); return; }
      promise
        .then(function () { reply(rewarded ? "rewarded" : "closed"); })
        .catch(function (error) { console.warn("[Monetag] ad failed", error); reply("failed"); });
    } catch (error) {
      console.warn("[Monetag] ad error", error);
      reply("failed");
    }
  }
});
