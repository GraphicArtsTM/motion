using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace WobbleBrawl.EditorTools
{
    /// <summary>
    /// One-time project setup: creates the boot scene, registers it in Build Settings, sets the
    /// product name and opens the scene — so a freshly cloned project is one click away from Play.
    /// </summary>
    [InitializeOnLoad]
    public static class WobbleProjectSetup
    {
        const string ScenePath = "Assets/WobbleBrawl/Scenes/Main.unity";
        const string DoneKey = "WobbleBrawl.SetupDone.v1";

        static WobbleProjectSetup()
        {
            EditorApplication.delayCall += () =>
            {
                if (SessionState.GetBool(DoneKey, false)) return;
                SessionState.SetBool(DoneKey, true);
                if (!File.Exists(ScenePath)) Setup(openScene: true);
                else EnsureBuildSettings();
            };
        }

        [MenuItem("Wobble Brawl/Setup Project (create Main scene)", priority = 0)]
        public static void SetupMenu() => Setup(openScene: true);

        [MenuItem("Wobble Brawl/Play", priority = 1)]
        public static void PlayMenu()
        {
            if (!File.Exists(ScenePath)) Setup(openScene: true);
            else if (SceneManager.GetActiveScene().path != ScenePath) EditorSceneManager.OpenScene(ScenePath);
            EditorApplication.isPlaying = true;
        }

        static void Setup(bool openScene)
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) return;
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;

            Directory.CreateDirectory(Path.GetDirectoryName(ScenePath));
            if (!File.Exists(ScenePath))
            {
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                // a placeholder camera so the Scene/Game views are not empty; the game builds its own at runtime
                var cam = new GameObject("Editor Preview Camera").AddComponent<Camera>();
                cam.transform.SetPositionAndRotation(new Vector3(0, 9, -11), Quaternion.Euler(45, 0, 0));
                cam.clearFlags = CameraClearFlags.SolidColor;
                cam.backgroundColor = new Color(0.98f, 0.62f, 0.45f);
                var note = new GameObject("README — the game is generated at runtime, just press Play");
                note.transform.position = Vector3.zero;
                EditorSceneManager.SaveScene(scene, ScenePath);
                AssetDatabase.Refresh();
            }
            EnsureBuildSettings();

            PlayerSettings.productName = "Wobble Brawl";
            PlayerSettings.companyName = "Wobble Studio";
            PlayerSettings.defaultScreenWidth = 1920;
            PlayerSettings.defaultScreenHeight = 1080;
            PlayerSettings.runInBackground = true;

            if (openScene && SceneManager.GetActiveScene().path != ScenePath)
                EditorSceneManager.OpenScene(ScenePath);
            Debug.Log("[Wobble Brawl] Project ready. Press Play (or menu Wobble Brawl ▸ Play).");
        }

        static void EnsureBuildSettings()
        {
            var scenes = EditorBuildSettings.scenes.ToList();
            if (scenes.Any(s => s.path == ScenePath)) return;
            scenes.Insert(0, new EditorBuildSettingsScene(ScenePath, true));
            EditorBuildSettings.scenes = scenes.ToArray();
        }
    }
}
