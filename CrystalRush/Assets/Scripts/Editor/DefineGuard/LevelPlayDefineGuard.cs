using System.Collections.Generic;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;

/// <summary>
/// Keeps the LEVELPLAY_ENABLED define for Android in sync with the LevelPlay package:
/// package installed -> define on (real ads), package removed -> define off (stub, project still compiles).
/// It lives in its own small assembly, so it works even when the game scripts have compile errors.
/// </summary>
[InitializeOnLoad]
static class LevelPlayDefineGuard
{
    const string Define = "LEVELPLAY_ENABLED";
    const string PackagePath = "Packages/com.unity.services.levelplay/package.json";

    static LevelPlayDefineGuard()
    {
        EditorApplication.delayCall += Check;
        UnityEditor.PackageManager.Events.registeredPackages += _ => Check();
    }

    static void Check()
    {
        bool installed = UnityEditor.PackageManager.PackageInfo.FindForAssetPath(PackagePath) != null;

        NamedBuildTarget android = NamedBuildTarget.Android;
        List<string> defines = PlayerSettings.GetScriptingDefineSymbols(android)
            .Split(';')
            .Select(d => d.Trim())
            .Where(d => d.Length > 0)
            .ToList();

        bool hasDefine = defines.Contains(Define);
        if (installed == hasDefine) return;

        if (installed) defines.Add(Define);
        else defines.Remove(Define);
        PlayerSettings.SetScriptingDefineSymbols(android, string.Join(";", defines));
        UnityEngine.Debug.Log($"Crystal Rush: {Define} {(installed ? "added" : "removed")} for Android.");
    }
}
