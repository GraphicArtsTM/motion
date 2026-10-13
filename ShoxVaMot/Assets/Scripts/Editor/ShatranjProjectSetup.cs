using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

namespace Shatranj.EditorTools
{
    /// <summary>
    /// Автонастройка проекта при первом открытии в Unity:
    ///  • материал-основа Standard в Resources (чтобы шейдер попал в сборку);
    ///  • сцена Assets/Scenes/Main.unity в Build Settings (игра строится кодом сама);
    ///  • параметры Android: портрет, IL2CPP, ARM64+ARMv7, minSdk 24, идентификатор пакета;
    ///  • шейдеры текста и спрайтов в Always Included, линейный туман не вырезается.
    /// Меню: Shox va Mot → Setup Project / Build Android APK / Build Android App Bundle.
    /// </summary>
    [InitializeOnLoad]
    public static class ShatranjProjectSetup
    {
        public const string ScenePath = "Assets/Scenes/Main.unity";
        const string MaterialPath = "Assets/Resources/ShatranjStandard.mat";
        const string DoneKey = "Shatranj.SetupDone.v1";
        const string MarkerPath = "ProjectSettings/ShoxVaMotConfigured.txt";
        const string BumpPath = "Assets/Resources/ShatranjStandardBump.mat";
        const string FlatNormalPath = "Assets/Resources/ShatranjFlatNormal.asset";

        static ShatranjProjectSetup()
        {
            EditorApplication.delayCall += () =>
            {
                if (EditorApplication.isPlayingOrWillChangePlaymode) return;
                EnsureAdsDefine();
                if (Application.isBatchMode) return;
                if (SessionState.GetBool(DoneKey, false)) return;
                SessionState.SetBool(DoneKey, true);
                Setup(false);
            };
        }

        [MenuItem("Shox va Mot/Setup Project", priority = 1)]
        public static void SetupMenu() { Setup(true, true); }

        /// <summary>
        /// Параметры плеера применяются один раз (или принудительно из меню),
        /// чтобы не затирать ваши собственные изменения в Player Settings.
        /// </summary>
        public static void Setup(bool verbose, bool forcePlayer = false)
        {
            EnsureMaterial();
            EnsureScene();
            EnsureAdsDefine();
            if (forcePlayer || !File.Exists(MarkerPath))
            {
                ConfigurePlayer();
                ConfigureGraphics();
                File.WriteAllText(MarkerPath, "Shox va Mot — player settings applied. Delete this file to re-apply automatically.\n");
            }
            AssetDatabase.SaveAssets();
            if (verbose) Debug.Log("[Shox va Mot] Проект настроен. Откройте Assets/Scenes/Main.unity и нажмите Play.");
        }

        const string AdsDefine = "SHOX_UNITY_ADS";

        /// <summary>
        /// Если установлен пакет Unity Ads (com.unity.ads), включаем символ SHOX_UNITY_ADS,
        /// чтобы скомпилировался код рекламы; если пакет удалён — выключаем.
        /// </summary>
        public static void EnsureAdsDefine()
        {
            bool hasAds = false;
            foreach (var asm in System.AppDomain.CurrentDomain.GetAssemblies())
                if (asm.GetType("UnityEngine.Advertisements.Advertisement", false) != null) { hasAds = true; break; }
            foreach (var group in new[] { BuildTargetGroup.Android, BuildTargetGroup.iOS, BuildTargetGroup.Standalone })
            {
                string defs = PlayerSettings.GetScriptingDefineSymbolsForGroup(group);
                var list = new System.Collections.Generic.List<string>(defs.Split(new[] { ';' }, System.StringSplitOptions.RemoveEmptyEntries));
                bool has = list.Contains(AdsDefine);
                if (hasAds == has) continue;
                if (hasAds) list.Add(AdsDefine); else list.Remove(AdsDefine);
                PlayerSettings.SetScriptingDefineSymbolsForGroup(group, string.Join(";", list.ToArray()));
            }
        }

        static void EnsureMaterial()
        {
            Directory.CreateDirectory("Assets/Resources");
            var shader = Shader.Find("Standard");
            if (shader == null) return;
            if (AssetDatabase.LoadAssetAtPath<Material>(MaterialPath) == null)
            {
                var m = new Material(shader) { name = "ShatranjStandard", enableInstancing = true };
                AssetDatabase.CreateAsset(m, MaterialPath);
            }
            if (AssetDatabase.LoadAssetAtPath<Material>(BumpPath) == null)
            {
                // плоская карта нормалей: материал с _NORMALMAP попадёт в сборку вместе со своим вариантом шейдера
                var flat = AssetDatabase.LoadAssetAtPath<Texture2D>(FlatNormalPath);
                if (flat == null)
                {
                    flat = new Texture2D(4, 4, TextureFormat.RGBA32, false, true) { name = "ShatranjFlatNormal" };
                    var px = new Color32[16];
                    for (int i = 0; i < 16; i++) px[i] = new Color32(128, 128, 255, 255);
                    flat.SetPixels32(px);
                    flat.Apply();
                    AssetDatabase.CreateAsset(flat, FlatNormalPath);
                }
                var b = new Material(shader) { name = "ShatranjStandardBump", enableInstancing = true };
                b.SetTexture("_BumpMap", flat);
                b.EnableKeyword("_NORMALMAP");
                AssetDatabase.CreateAsset(b, BumpPath);
            }
        }

        static void EnsureScene()
        {
            if (!File.Exists(ScenePath))
            {
                Directory.CreateDirectory("Assets/Scenes");
                var active = SceneManager.GetActiveScene();
                bool replaceActive = string.IsNullOrEmpty(active.path) && !active.isDirty;
                var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, replaceActive ? NewSceneMode.Single : NewSceneMode.Additive);
                var marker = new GameObject("Shox va Mot (сцена строится кодом — GameRoot)");
                SceneManager.MoveGameObjectToScene(marker, scene);
                EditorSceneManager.SaveScene(scene, ScenePath);
                if (!replaceActive) EditorSceneManager.CloseScene(scene, true);
            }

            var scenes = EditorBuildSettings.scenes;
            bool present = false;
            foreach (var s in scenes) if (s.path == ScenePath) present = true;
            if (!present)
            {
                var list = new System.Collections.Generic.List<EditorBuildSettingsScene>(scenes);
                list.Insert(0, new EditorBuildSettingsScene(ScenePath, true));
                EditorBuildSettings.scenes = list.ToArray();
            }

            var cur = SceneManager.GetActiveScene();
            if (string.IsNullOrEmpty(cur.path) && !cur.isDirty) EditorSceneManager.OpenScene(ScenePath);
        }

        static void ConfigurePlayer()
        {
            PlayerSettings.companyName = "Shatranj Studio";
            PlayerSettings.productName = "Shox va Mot";
            if (string.IsNullOrEmpty(PlayerSettings.bundleVersion) || PlayerSettings.bundleVersion == "0.1" || PlayerSettings.bundleVersion == "1.0")
                PlayerSettings.bundleVersion = "1.0.0";
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, "uz.shoxvamot.game");
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.Portrait;
            PlayerSettings.allowedAutorotateToPortrait = true;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = false;
            PlayerSettings.allowedAutorotateToLandscapeRight = false;
            PlayerSettings.colorSpace = ColorSpace.Gamma;
            PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64 | AndroidArchitecture.ARMv7;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel24;
            PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevelAuto;
            PlayerSettings.Android.preferredInstallLocation = AndroidPreferredInstallLocation.Auto;
            PlayerSettings.Android.renderOutsideSafeArea = false;
            PlayerSettings.SplashScreen.backgroundColor = new Color(0.04f, 0.1f, 0.22f);
            PlayerSettings.MTRendering = true;
            PlayerSettings.gpuSkinning = true;
            PlayerSettings.SetManagedStrippingLevel(BuildTargetGroup.Android, ManagedStrippingLevel.Low);
            var icon = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Art/AppIcon.png");
            if (icon != null) PlayerSettings.SetIconsForTargetGroup(BuildTargetGroup.Unknown, new[] { icon });
        }

        static void ConfigureGraphics()
        {
            var gs = AssetDatabase.LoadAssetAtPath<GraphicsSettings>("ProjectSettings/GraphicsSettings.asset");
            if (gs == null) return;
            var so = new SerializedObject(gs);

            var arr = so.FindProperty("m_AlwaysIncludedShaders");
            foreach (var name in new[] { "GUI/Text Shader", "Sprites/Default", "UI/Default" })
            {
                var sh = Shader.Find(name);
                if (sh == null || arr == null) continue;
                bool found = false;
                for (int i = 0; i < arr.arraySize; i++)
                    if (arr.GetArrayElementAtIndex(i).objectReferenceValue == sh) { found = true; break; }
                if (found) continue;
                arr.InsertArrayElementAtIndex(arr.arraySize);
                arr.GetArrayElementAtIndex(arr.arraySize - 1).objectReferenceValue = sh;
            }

            // туман включается кодом во время игры — не даём сборке вырезать его варианты шейдеров
            var fogStrip = so.FindProperty("m_FogStripping");
            if (fogStrip != null) fogStrip.intValue = 1;
            var keepLinear = so.FindProperty("m_FogKeepLinear");
            if (keepLinear != null) keepLinear.boolValue = true;
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        // ------------------------------------------------------------------ Сборка

        [MenuItem("Shox va Mot/Build Android APK", priority = 20)]
        public static void BuildApk() { Build(false); }

        [MenuItem("Shox va Mot/Build Android App Bundle (Google Play)", priority = 21)]
        public static void BuildAab() { Build(true); }

        [MenuItem("Shox va Mot/Open Main Scene", priority = 40)]
        public static void OpenScene()
        {
            if (EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) EditorSceneManager.OpenScene(ScenePath);
        }

        static void Build(bool aab)
        {
            Setup(false);
            if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android)
                EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
            EditorUserBuildSettings.buildAppBundle = aab;
            Directory.CreateDirectory("Builds/Android");
            var options = new BuildPlayerOptions
            {
                scenes = new[] { ScenePath },
                locationPathName = "Builds/Android/ShoxVaMot" + (aab ? ".aab" : ".apk"),
                target = BuildTarget.Android,
                options = BuildOptions.None
            };
            var report = BuildPipeline.BuildPlayer(options);
            if (report.summary.result == BuildResult.Succeeded)
            {
                Debug.Log("[Shox va Mot] Сборка готова: " + options.locationPathName + " (" + (report.summary.totalSize / (1024 * 1024)) + " МБ)");
                EditorUtility.RevealInFinder(options.locationPathName);
            }
            else Debug.LogError("[Shox va Mot] Сборка не удалась: " + report.summary.result);
        }

        /// <summary>Командная строка: Unity -batchmode -quit -projectPath . -executeMethod Shatranj.EditorTools.ShatranjProjectSetup.CIBuildApk</summary>
        public static void CIBuildApk() { Build(false); }
    }

    /// <summary>Перед любой сборкой убеждаемся, что проект настроен.</summary>
    public class ShatranjPreBuild : IPreprocessBuildWithReport
    {
        public int callbackOrder { get { return 0; } }
        public void OnPreprocessBuild(BuildReport report)
        {
            if (AssetDatabase.LoadAssetAtPath<Material>("Assets/Resources/ShatranjStandardBump.mat") == null)
                ShatranjProjectSetup.Setup(false);
        }
    }
}
