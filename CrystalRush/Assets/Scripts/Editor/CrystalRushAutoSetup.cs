using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// The first time the project is opened (no scenes yet), runs "Crystal Rush > Build Game" by itself,
/// so after "Add project" in Unity Hub the game is ready to play. If the scenes were built by an older
/// version of the tool, it offers to rebuild them. Otherwise it does nothing.
/// </summary>
[InitializeOnLoad]
static class CrystalRushAutoSetup
{
    const string MainMenuScene = "Assets/Scenes/MainMenu.unity";
    const string SessionKey = "CrystalRush.AutoSetupDone";
    const int MaxWaitTicks = 600;

    static int waitedTicks;

    static CrystalRushAutoSetup()
    {
        if (Application.isBatchMode || SessionState.GetBool(SessionKey, false)) return;
        EditorApplication.delayCall += TryRun;
    }

    static void TryRun()
    {
        bool built = File.Exists(MainMenuScene);
        if (built && BuiltVersion() >= CrystalRushSetup.SetupVersion)
        {
            SessionState.SetBool(SessionKey, true);
            return;
        }

        // Wait until Unity has finished importing and compiling, and the URP shaders are available.
        bool urpActive = GraphicsSettings.currentRenderPipeline != null;
        bool busy = EditorApplication.isCompiling || EditorApplication.isUpdating || EditorApplication.isPlayingOrWillChangePlaymode;
        bool shadersMissing = urpActive && Shader.Find("Universal Render Pipeline/Lit") == null;
        if ((busy || shadersMissing) && waitedTicks++ < MaxWaitTicks)
        {
            EditorApplication.delayCall += TryRun;
            return;
        }

        SessionState.SetBool(SessionKey, true);

        // The game was built by an older version of the tool: ask before rebuilding the scenes.
        if (built && !EditorUtility.DisplayDialog("Crystal Rush",
                "The game scripts were updated. Rebuild the scenes and prefabs now?\n" +
                "Скрипты игры обновлены. Пересобрать сцены и префабы?\n" +
                "O‘yin skriptlari yangilandi. Sahnalar va prefablarni qayta yig‘aylikmi?",
                "Rebuild / Пересобрать", "Later / Позже"))
            return;

        Debug.Log("Crystal Rush: building scenes, prefabs and sounds...");
        CrystalRushSetup.BuildGame();
    }

    static int BuiltVersion()
    {
        if (!File.Exists(CrystalRushSetup.SetupVersionFile)) return 1; // built before version stamps existed
        return int.TryParse(File.ReadAllText(CrystalRushSetup.SetupVersionFile).Trim(), out int version) ? version : 1;
    }
}
