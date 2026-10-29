using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// The first time the project is opened (no scenes yet), runs "Crystal Rush > Build Game" by itself,
/// so after "Add project" in Unity Hub the game is ready to play. Later it does nothing:
/// the menu item can still be used to rebuild everything.
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
        if (File.Exists(MainMenuScene))
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
        Debug.Log("Crystal Rush: first start - building scenes, prefabs and sounds...");
        CrystalRushSetup.BuildGame();
    }
}
