using UnityEditor;
using UnityEditor.Build;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

// Editor helper: when the project is opened for the first time, the Game scene opens by itself,
// so you can press Play right away. Also adds the "Royal Run" menu to the top bar.
[InitializeOnLoad]
static class RoyalRunEditorStartup
{
    const string ScenePath = "Assets/Scenes/Game.unity";
    const string SessionKey = "RoyalRun.StartupDone";

    static RoyalRunEditorStartup()
    {
        EditorApplication.delayCall += OpenGameSceneIfEmpty;
    }

    static void OpenGameSceneIfEmpty()
    {
        if (SessionState.GetBool(SessionKey, false)) return;
        SessionState.SetBool(SessionKey, true);

        if (EditorApplication.isPlayingOrWillChangePlaymode) return;

        // Only replace an untitled, unsaved, empty scene - never the scene you are working on.
        Scene active = SceneManager.GetActiveScene();
        if (!string.IsNullOrEmpty(active.path) || active.isDirty) return;
        if (AssetDatabase.LoadAssetAtPath<SceneAsset>(ScenePath) == null) return;

        EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        Debug.Log("[Royal Run] The Game scene is open. Press Play. (Tip: turn on \"Maximize On Play\" in the Game view.)");
    }

    [MenuItem("Royal Run/Open Game Scene", false, 1)]
    static void OpenGameScene()
    {
        if (EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
            EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
    }

    [MenuItem("Royal Run/Play", false, 2)]
    static void Play()
    {
        if (SceneManager.GetActiveScene().path != ScenePath)
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        }
        EditorApplication.isPlaying = true;
    }

    // Android: upright screen, a package name, 64-bit IL2CPP (required by Google Play), then switch the platform.
    [MenuItem("Royal Run/Setup Android Build", false, 10)]
    static void SetupAndroid()
    {
        PlayerSettings.companyName = "RoyalRun";
        PlayerSettings.productName = "Royal Run";
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.royalrun.game");
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.Portrait;
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
        PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
        PlayerSettings.Android.forceInternetPermission = true;   // the Wi-Fi race needs the network

        if (!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.Android, BuildTarget.Android))
        {
            EditorUtility.DisplayDialog("Royal Run",
                "Android settings are saved.\n\nThe Android Build Support module is not installed: Unity Hub -> Installs -> (your Unity) -> Add modules -> Android Build Support (with SDK & NDK, OpenJDK).",
                "OK");
            return;
        }
        EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
        Debug.Log("[Royal Run] Android is set up: portrait, IL2CPP, ARM64, package com.royalrun.game. Use Royal Run -> Build Android APK.");
    }

    [MenuItem("Royal Run/Build Android APK", false, 11)]
    static void BuildAndroid()
    {
        SetupAndroid();
        if (!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.Android, BuildTarget.Android)) return;
        BuildPlayerOptions o = new BuildPlayerOptions
        {
            scenes = new[] { ScenePath },
            locationPathName = "Builds/RoyalRun.apk",
            target = BuildTarget.Android,
            options = BuildOptions.None,
        };
        BuildPipeline.BuildPlayer(o);
        EditorUtility.RevealInFinder("Builds/RoyalRun.apk");
    }

    [MenuItem("Royal Run/Reset Language and Record", false, 20)]
    static void ResetPrefs()
    {
        PlayerPrefs.DeleteKey("royalrun_lang");
        PlayerPrefs.DeleteKey("royalrun_best");
        PlayerPrefs.DeleteKey("royalrun_best_endless");
        PlayerPrefs.DeleteKey("royalrun_mode");
        PlayerPrefs.Save();
        Debug.Log("[Royal Run] The saved language and the record were reset.");
    }
}
