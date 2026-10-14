using UnityEngine;
#if SHOX_POSTFX
using UnityEngine.Rendering.PostProcessing;
#endif

namespace Shatranj.Visual
{
    /// <summary>
    /// Пост-обработка (пакет com.unity.postprocessing): мягкое свечение золота, фонарей и окон,
    /// тёплая цветокоррекция, затенение в углах на высоком качестве.
    /// Код компилируется только при наличии пакета (символ SHOX_POSTFX ставит редакторский скрипт).
    /// </summary>
    public static class PostFx
    {
        const int VolumeLayer = 29;

#if SHOX_POSTFX
        static PostProcessLayer layer;
        static PostProcessVolume volume;
        static Bloom bloom;
        static AmbientOcclusion ao;
        static ColorGrading grading;
#endif

        public static bool Available
        {
            get
            {
#if SHOX_POSTFX
                return layer != null;
#else
                return false;
#endif
            }
        }

        public static void Setup(Camera cam)
        {
#if SHOX_POSTFX
            if (layer != null || cam == null) return;
            var refs = Resources.Load<ShoxPostFxRefs>("ShoxPostFxRefs");
            var res = refs != null ? refs.resources as PostProcessResources : null;
            if (res == null)
            {
                Debug.LogWarning("[PostFx] Нет Resources/ShoxPostFxRefs — выполните меню Shox va Mot → Setup Project.");
                return;
            }
            layer = cam.gameObject.AddComponent<PostProcessLayer>();
            layer.Init(res);
            layer.volumeTrigger = cam.transform;
            layer.volumeLayer = 1 << VolumeLayer;
            layer.antialiasingMode = PostProcessLayer.Antialiasing.None;
            layer.stopNaNPropagation = true;

            var profile = ScriptableObject.CreateInstance<PostProcessProfile>();
            bloom = profile.AddSettings<Bloom>();
            bloom.enabled.Override(true);
            bloom.fastMode.Override(true);
            bloom.softKnee.Override(0.6f);
            bloom.diffusion.Override(6f);

            grading = profile.AddSettings<ColorGrading>();
            grading.enabled.Override(true);
            grading.gradingMode.Override(GradingMode.LowDefinitionRange);

            ao = profile.AddSettings<AmbientOcclusion>();
            ao.enabled.Override(false);
            ao.mode.Override(AmbientOcclusionMode.ScalableAmbientObscurance);
            ao.quality.Override(AmbientOcclusionQuality.Low);
            ao.radius.Override(0.3f);
            ao.intensity.Override(0.55f);

            var go = new GameObject("PostFxVolume") { layer = VolumeLayer };
            Object.DontDestroyOnLoad(go);
            volume = go.AddComponent<PostProcessVolume>();
            volume.isGlobal = true;
            volume.priority = 10f;
            volume.sharedProfile = profile;
#endif
        }

        /// <summary>Включить/выключить и подстроить под время суток и уровень графики.</summary>
        public static void Apply(bool on, int quality, Ambience a)
        {
#if SHOX_POSTFX
            if (layer == null) return;
            bool active = on && quality > 0;
            layer.enabled = active;
            volume.enabled = active;
            if (!active) return;

            switch (a)
            {
                case Ambience.Day:
                    bloom.intensity.Override(1.2f); bloom.threshold.Override(0.9f); bloom.color.Override(new Color(1f, 0.95f, 0.85f));
                    grading.temperature.Override(4f); grading.saturation.Override(8f); grading.contrast.Override(10f); grading.brightness.Override(2f);
                    break;
                case Ambience.Sunset:
                    bloom.intensity.Override(1.6f); bloom.threshold.Override(0.82f); bloom.color.Override(new Color(1f, 0.8f, 0.55f));
                    grading.temperature.Override(10f); grading.saturation.Override(12f); grading.contrast.Override(14f); grading.brightness.Override(0f);
                    break;
                default:
                    bloom.intensity.Override(2.2f); bloom.threshold.Override(0.7f); bloom.color.Override(new Color(1f, 0.75f, 0.45f));
                    grading.temperature.Override(6f); grading.saturation.Override(6f); grading.contrast.Override(16f); grading.brightness.Override(-4f);
                    break;
            }
            ao.enabled.Override(quality >= 2);
#endif
        }
    }
}
