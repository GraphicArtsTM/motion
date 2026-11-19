using UnityEditor;
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

    [MenuItem("Royal Run/Reset Language and Record", false, 20)]
    static void ResetPrefs()
    {
        PlayerPrefs.DeleteKey("royalrun_lang");
        PlayerPrefs.DeleteKey("royalrun_best");
        PlayerPrefs.Save();
        Debug.Log("[Royal Run] The saved language and the record were reset.");
    }
}
