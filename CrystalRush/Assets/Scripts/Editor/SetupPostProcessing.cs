using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using Object = UnityEngine.Object;

/// <summary>
/// Setup step: URP post-processing (Bloom makes the glowing crystals, lasers and portal shine; Vignette darkens the corners).
/// URP classes are reached through reflection, so this file also compiles in a project without URP;
/// in that case this step is simply skipped.
/// </summary>
public static partial class CrystalRushSetup
{
    const string UrpAssembly = "Unity.RenderPipelines.Universal.Runtime";
    const string CoreAssembly = "Unity.RenderPipelines.Core.Runtime";
    const string ProfilePath = MaterialsFolder + "/PostProcessing.asset";

    static ScriptableObject postProcessingProfile;

    static void CreatePostProcessingProfile()
    {
        postProcessingProfile = null;
        try
        {
            Type profileType = Type.GetType("UnityEngine.Rendering.VolumeProfile, " + CoreAssembly);
            Type bloomType = Type.GetType("UnityEngine.Rendering.Universal.Bloom, " + UrpAssembly);
            Type vignetteType = Type.GetType("UnityEngine.Rendering.Universal.Vignette, " + UrpAssembly);
            if (profileType == null || bloomType == null || vignetteType == null) return; // not a URP project

            AssetDatabase.DeleteAsset(ProfilePath);
            ScriptableObject profile = ScriptableObject.CreateInstance(profileType);
            AssetDatabase.CreateAsset(profile, ProfilePath);

            MethodInfo add = profileType.GetMethod("Add", new[] { typeof(Type), typeof(bool) });
            ScriptableObject bloom = (ScriptableObject)add.Invoke(profile, new object[] { bloomType, true });
            SetParameter(bloom, "intensity", 0.9f);
            SetParameter(bloom, "threshold", 0.95f);
            SetParameter(bloom, "scatter", 0.65f);
            ScriptableObject vignette = (ScriptableObject)add.Invoke(profile, new object[] { vignetteType, true });
            SetParameter(vignette, "intensity", 0.3f);

            // The effects must be saved inside the profile asset.
            foreach (ScriptableObject component in new[] { bloom, vignette })
            {
                component.hideFlags = HideFlags.HideInInspector | HideFlags.HideInHierarchy;
                AssetDatabase.AddObjectToAsset(component, profile);
            }
            EditorUtility.SetDirty(profile);
            AssetDatabase.SaveAssets();
            postProcessingProfile = profile;
        }
        catch (Exception exception)
        {
            Debug.LogWarning("Crystal Rush setup: post-processing skipped (" + exception.Message + ")");
        }
    }

    static void AddGlobalVolume()
    {
        if (postProcessingProfile == null) return;
        Type volumeType = Type.GetType("UnityEngine.Rendering.Volume, " + CoreAssembly);
        if (volumeType == null) return;

        GameObject go = new GameObject("Global Volume");
        Component volume = go.AddComponent(volumeType);
        SetMember(volume, "isGlobal", true);
        SetMember(volume, "sharedProfile", postProcessingProfile);
    }

    static void EnablePostProcessing(GameObject cameraObject)
    {
        Type cameraDataType = Type.GetType("UnityEngine.Rendering.Universal.UniversalAdditionalCameraData, " + UrpAssembly);
        if (cameraDataType == null) return;
        Component data = cameraObject.GetComponent(cameraDataType);
        if (data == null) data = cameraObject.AddComponent(cameraDataType);
        SetMember(data, "renderPostProcessing", true);
    }

    /// <summary>Sets e.g. bloom.intensity.value = 0.9 (a VolumeParameter field).</summary>
    static void SetParameter(object effect, string field, float value)
    {
        object parameter = effect.GetType().GetField(field, BindingFlags.Public | BindingFlags.Instance)?.GetValue(effect);
        if (parameter == null) return;
        parameter.GetType().GetProperty("value")?.SetValue(parameter, value);
        parameter.GetType().GetProperty("overrideState")?.SetValue(parameter, true);
    }

    static void SetMember(object target, string name, object value)
    {
        const BindingFlags flags = BindingFlags.Public | BindingFlags.Instance;
        PropertyInfo property = target.GetType().GetProperty(name, flags);
        if (property != null && property.CanWrite)
        {
            property.SetValue(target, value);
            return;
        }
        FieldInfo field = target.GetType().GetField(name, flags);
        if (field != null) field.SetValue(target, value);
    }
}
