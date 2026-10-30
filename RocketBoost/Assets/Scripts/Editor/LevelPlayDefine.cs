using System;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;

// Adds the ROCKET_LEVELPLAY define for Android and iOS when the Unity LevelPlay package
// (com.unity.services.levelplay, "Ads Mediation") is installed, and removes it when the package is removed.
// Thanks to this, the project builds for Android both with and without the package:
// without it AdManager uses the stub, with it - the real LevelPlay SDK.
[InitializeOnLoad]
static class LevelPlayDefine
{
    const string Define = "ROCKET_LEVELPLAY";

    static LevelPlayDefine()
    {
        bool installed = AppDomain.CurrentDomain.GetAssemblies().Any(a => a.GetName().Name == "Unity.LevelPlay");
        Apply(NamedBuildTarget.Android, installed);
        Apply(NamedBuildTarget.iOS, installed);
    }

    static void Apply(NamedBuildTarget target, bool enabled)
    {
        string current = PlayerSettings.GetScriptingDefineSymbols(target);
        var symbols = current.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries).Select(s => s.Trim()).ToList();
        bool has = symbols.Contains(Define);
        if (enabled == has) return;
        if (enabled) symbols.Add(Define); else symbols.Remove(Define);
        PlayerSettings.SetScriptingDefineSymbols(target, string.Join(";", symbols));
        UnityEngine.Debug.Log("[Rocket Boost] " + (enabled ? "LevelPlay found: " : "LevelPlay not installed: ") +
                              Define + (enabled ? " added" : " removed") + " for " + target.TargetName);
    }
}
