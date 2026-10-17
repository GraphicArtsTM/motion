using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace UzbekKombat.EditorTools
{
    /// <summary>
    /// Loyiha birinchi marta ochilganda Assets/Scenes/Main.unity sahnasini yaratadi va Build Settings'ga qo'shadi.
    /// O'yin to'liq protsedural — sahna bo'sh, hammasini Bootstrap yaratadi.
    /// </summary>
    [InitializeOnLoad]
    public static class ProjectSetup
    {
        const string ScenePath = "Assets/Scenes/Main.unity";

        static ProjectSetup()
        {
            EditorApplication.delayCall += () => Ensure(false);
        }

        [MenuItem("O'zbek Jangi/Sahnani tayyorlash")]
        static void EnsureMenu() => Ensure(true);

        [MenuItem("O'zbek Jangi/O'yinni boshlash ▶")]
        static void PlayMenu()
        {
            Ensure(true);
            if (EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
            {
                EditorSceneManager.OpenScene(ScenePath);
                EditorApplication.isPlaying = true;
            }
        }

        static void Ensure(bool openScene)
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) return;
            bool created = false;
            if (!File.Exists(ScenePath))
            {
                if (!AssetDatabase.IsValidFolder("Assets/Scenes")) AssetDatabase.CreateFolder("Assets", "Scenes");
                var active = EditorSceneManager.GetActiveScene();
                bool canReplace = string.IsNullOrEmpty(active.path) && !active.isDirty;
                if (!canReplace) return; // foydalanuvchining saqlanmagan ishiga tegmaymiz
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(scene, ScenePath);
                created = true;
            }
            var scenes = EditorBuildSettings.scenes;
            if (scenes.Length == 0 || scenes[0].path != ScenePath)
                EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            PlayerSettings.productName = "O'zbek Jangi: Qadimiy Qahramonlar";
            PlayerSettings.companyName = "UzbekKombat";
            PlayerSettings.defaultScreenWidth = 1920;
            PlayerSettings.defaultScreenHeight = 1080;
            PlayerSettings.runInBackground = true;
            if (PlayerSettings.colorSpace != ColorSpace.Linear) PlayerSettings.colorSpace = ColorSpace.Linear; // realistik yoritish
            if ((created || openScene) && EditorSceneManager.GetActiveScene().path != ScenePath)
                EditorSceneManager.OpenScene(ScenePath);
            if (created) Debug.Log("[O'zbek Jangi] Main.unity yaratildi. Play tugmasini bosing!");
        }
    }
}
