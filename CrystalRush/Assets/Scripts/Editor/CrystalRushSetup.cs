using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using Object = UnityEngine.Object;

/// <summary>
/// EDITOR TOOL. Menu: Crystal Rush > Build Game.
/// Creates the whole game inside an empty Unity 6 (URP) project: folders, tags, textures, sounds,
/// materials, models, particles, prefabs, UI, the 4 scenes, Build Settings and Player Settings.
/// It can be run again at any time: everything is re-created in place.
/// This file holds the main steps and small helpers; the other Setup*.cs files hold each step.
/// </summary>
public static partial class CrystalRushSetup
{
    const string TexturesFolder = "Assets/Textures";
    const string AudioFolder = "Assets/Audio";
    const string MaterialsFolder = "Assets/Materials";
    const string ModelsFolder = "Assets/Models";
    const string ParticlesFolder = "Assets/Particles";
    const string PrefabsFolder = "Assets/Prefabs";
    const string ScenesFolder = "Assets/Scenes";
    const string FontPath = "Assets/Fonts/Rubik-SemiBold.ttf";

    // Raise this number when the generated content changes; projects built with an older
    // version are offered a rebuild on the next start (see CrystalRushAutoSetup).
    public const int SetupVersion = 2;
    public const string SetupVersionFile = ScenesFolder + "/.setup-version"; // hidden file, Unity does not import it

    const string PackageName = "com.yourname.crystalrush";
    const string CompanyName = "YourName";
    const string ProductName = "Crystal Rush";

    static Font uiFont;

    [MenuItem("Crystal Rush/Build Game (create scenes, prefabs, sounds)", false, 0)]
    public static void BuildGame()
    {
        if (EditorApplication.isPlayingOrWillChangePlaymode)
        {
            EditorUtility.DisplayDialog(ProductName, "Stop Play mode first.", "OK");
            return;
        }
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;

        try
        {
            Progress("Folders and tags", 0.02f);
            CreateFolders();
            AddTag("Hazard");
            AddTag("Crystal");
            AddTag("Pickup");

            // A clean temporary scene, so the objects we build do not end up in the user's scene.
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            uiFont = AssetDatabase.LoadAssetAtPath<Font>(FontPath);
            if (uiFont == null) uiFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

            Progress("Textures", 0.08f);
            CreateTextures();
            Progress("Sounds and music", 0.15f);
            CreateAudio();
            Progress("Materials", 0.35f);
            CreateMaterials();
            Progress("Models", 0.4f);
            CreateMeshes();
            Progress("Particles", 0.45f);
            CreateParticles();
            CreatePostProcessingProfile();
            Progress("Prefabs", 0.55f);
            CreatePrefabs();
            Progress("Interface", 0.65f);
            CreateGameUIPrefab();
            Progress("Main menu", 0.7f);
            CreateMainMenuScene();
            for (int i = 0; i < Levels.Length; i++)
            {
                Progress("Level " + Levels[i].number, 0.75f + i * 0.06f);
                CreateLevelScene(Levels[i]);
            }
            Progress("Project settings", 0.95f);
            ConfigureProject();
            File.WriteAllText(SetupVersionFile, SetupVersion.ToString());

            AssetDatabase.SaveAssets();
        }
        finally
        {
            EditorUtility.ClearProgressBar();
        }

        EditorSceneManager.OpenScene(ScenesFolder + "/" + GameScenes.MainMenu + ".unity");
        EditorUtility.DisplayDialog(ProductName,
            "Done!\n\nScenes: Assets/Scenes (MainMenu, Level1-3), added to Build Settings.\n" +
            "Press Play in the MainMenu scene.\n\n" +
            "Готово! Нажмите Play в сцене MainMenu.\nTayyor! MainMenu sahnasida Play tugmasini bosing.", "OK");
    }

    [MenuItem("Crystal Rush/Reset saved progress (PlayerPrefs)", false, 20)]
    public static void ResetProgress()
    {
        PlayerPrefs.DeleteAll();
        Debug.Log("Crystal Rush: PlayerPrefs cleared (high score, levels, language, volume).");
    }

    static void Progress(string step, float value)
    {
        EditorUtility.DisplayProgressBar(ProductName, step, value);
    }

    // ---------------------------------------------------------------- folders, tags

    static void CreateFolders()
    {
        foreach (string folder in new[] { TexturesFolder, AudioFolder, MaterialsFolder, ModelsFolder, ParticlesFolder, PrefabsFolder, ScenesFolder })
        {
            EnsureFolder(folder);
        }
    }

    static void EnsureFolder(string path)
    {
        if (AssetDatabase.IsValidFolder(path)) return;
        string parent = Path.GetDirectoryName(path).Replace('\\', '/');
        EnsureFolder(parent);
        AssetDatabase.CreateFolder(parent, Path.GetFileName(path));
    }

    static void AddTag(string tag)
    {
        Object tagManagerAsset = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TagManager.asset")[0];
        SerializedObject tagManager = new SerializedObject(tagManagerAsset);
        SerializedProperty tags = tagManager.FindProperty("tags");
        for (int i = 0; i < tags.arraySize; i++)
        {
            if (tags.GetArrayElementAtIndex(i).stringValue == tag) return;
        }
        tags.arraySize++;
        tags.GetArrayElementAtIndex(tags.arraySize - 1).stringValue = tag;
        tagManager.ApplyModifiedPropertiesWithoutUndo();
    }

    // ---------------------------------------------------------------- project settings

    static void ConfigureProject()
    {
        EditorBuildSettings.scenes = new[]
        {
            new EditorBuildSettingsScene(ScenesFolder + "/" + GameScenes.MainMenu + ".unity", true),
            new EditorBuildSettingsScene(ScenesFolder + "/Level1.unity", true),
            new EditorBuildSettingsScene(ScenesFolder + "/Level2.unity", true),
            new EditorBuildSettingsScene(ScenesFolder + "/Level3.unity", true),
        };

        PlayerSettings.companyName = CompanyName;
        PlayerSettings.productName = ProductName;
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, PackageName);
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Standalone, PackageName);

        Texture2D icon = AssetDatabase.LoadAssetAtPath<Texture2D>(TexturesFolder + "/AppIcon.png");
        if (icon != null) PlayerSettings.SetIcons(NamedBuildTarget.Unknown, new[] { icon }, IconKind.Any);

        // Landscape only on phones.
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
        PlayerSettings.allowedAutorotateToPortrait = false;
        PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
        PlayerSettings.allowedAutorotateToLandscapeLeft = true;
        PlayerSettings.allowedAutorotateToLandscapeRight = true;

        // WebGL: the build also works on hosts that do not send the right compression headers.
        PlayerSettings.WebGL.decompressionFallback = true;
    }

    // ---------------------------------------------------------------- helpers

    /// <summary>Creates the asset, or overwrites the existing one in place (so links to it are kept).</summary>
    static T SaveAsset<T>(T asset, string path) where T : Object
    {
        asset.name = Path.GetFileNameWithoutExtension(path);
        T existing = AssetDatabase.LoadAssetAtPath<T>(path);
        if (existing == null)
        {
            AssetDatabase.CreateAsset(asset, path);
            return asset;
        }
        EditorUtility.CopySerialized(asset, existing);
        EditorUtility.SetDirty(existing);
        Object.DestroyImmediate(asset);
        return existing;
    }

    static GameObject SavePrefab(GameObject root, string name)
    {
        string path = PrefabsFolder + "/" + name + ".prefab";
        GameObject prefab = PrefabUtility.SaveAsPrefabAsset(root, path);
        Object.DestroyImmediate(root);
        return prefab;
    }

    static GameObject Place(GameObject prefab, Transform parent, Vector3 position, string name = null)
    {
        GameObject instance = (GameObject)PrefabUtility.InstantiatePrefab(prefab, parent);
        instance.transform.position = position;
        if (name != null) instance.name = name;
        return instance;
    }

    /// <summary>Sets a private [SerializeField] through SerializedObject, exactly like the Inspector does.</summary>
    static void Set(Object target, string property, object value)
    {
        SerializedObject serialized = new SerializedObject(target);
        SerializedProperty prop = serialized.FindProperty(property);
        if (prop == null)
        {
            Debug.LogError($"Crystal Rush setup: field '{property}' not found on {target.GetType().Name}");
            return;
        }

        switch (value)
        {
            case null: prop.objectReferenceValue = null; break;
            case Object reference: prop.objectReferenceValue = reference; break;
            case float number: prop.floatValue = number; break;
            case int number: prop.intValue = number; break;
            case bool flag: prop.boolValue = flag; break;
            case string text: prop.stringValue = text; break;
            case Vector3 vector: prop.vector3Value = vector; break;
            case Color color: prop.colorValue = color; break;
            case Enum enumValue: prop.enumValueIndex = Convert.ToInt32(enumValue); break;
            case Object[] references:
                prop.arraySize = references.Length;
                for (int i = 0; i < references.Length; i++) prop.GetArrayElementAtIndex(i).objectReferenceValue = references[i];
                break;
            default:
                Debug.LogError($"Crystal Rush setup: unsupported value type {value.GetType()} for '{property}'");
                return;
        }
        serialized.ApplyModifiedPropertiesWithoutUndo();
    }

    static GameObject Primitive(PrimitiveType type, string name, Transform parent, Material material, bool keepCollider)
    {
        GameObject go = GameObject.CreatePrimitive(type);
        go.name = name;
        go.transform.SetParent(parent, false);
        go.GetComponent<Renderer>().sharedMaterial = material;
        if (!keepCollider) Object.DestroyImmediate(go.GetComponent<Collider>());
        return go;
    }

    static GameObject MeshObject(string name, Transform parent, Mesh mesh, Material material)
    {
        GameObject go = new GameObject(name, typeof(MeshFilter), typeof(MeshRenderer));
        go.transform.SetParent(parent, false);
        go.GetComponent<MeshFilter>().sharedMesh = mesh;
        go.GetComponent<MeshRenderer>().sharedMaterial = material;
        return go;
    }

    static Light AddPointLight(Transform parent, string name, Color color, float intensity, float range, Vector3 localPosition)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.transform.localPosition = localPosition;
        Light light = go.AddComponent<Light>();
        light.type = LightType.Point;
        light.color = color;
        light.intensity = intensity;
        light.range = range;
        light.shadows = LightShadows.None;
        return light;
    }

    /// <summary>
    /// Changes made from code to prefab instances must be recorded, otherwise Unity can lose them.
    /// </summary>
    static void RecordPrefabInstanceChanges(Scene scene)
    {
        foreach (GameObject root in scene.GetRootGameObjects())
        {
            foreach (Transform child in root.GetComponentsInChildren<Transform>(true))
            {
                if (!PrefabUtility.IsPartOfPrefabInstance(child.gameObject)) continue;
                PrefabUtility.RecordPrefabInstancePropertyModifications(child.gameObject);
                foreach (Component component in child.GetComponents<Component>())
                {
                    if (component != null) PrefabUtility.RecordPrefabInstancePropertyModifications(component);
                }
            }
        }
    }
}
