using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace UzbekKombat.EditorTools
{
    /// <summary>
    /// Assets/Resources/Characters/{id}/ ichidagi FBX'larni avtomatik sozlaydi:
    /// model.fbx — Humanoid, materiallar bilan; Anims/*.fbx — Humanoid klip, nomi = fayl nomi,
    /// loop (idle/walk...) yoqiladi, ildiz harakati pozaga "pishiriladi" (joyida o'ynaydi).
    /// </summary>
    public class CharacterImporter : AssetPostprocessor
    {
        static bool IsChar(string p)
        {
            p = p.Replace('\\', '/');
            return p.Contains("/Resources/Characters/") && p.EndsWith(".fbx", System.StringComparison.OrdinalIgnoreCase);
        }

        static bool IsAnim(string p) => p.Replace('\\', '/').Contains("/Anims/");

        void OnPreprocessModel()
        {
            if (!IsChar(assetPath)) return;
            var mi = (ModelImporter)assetImporter;
            bool anim = IsAnim(assetPath);
            mi.animationType = ModelImporterAnimationType.Human;
            mi.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            mi.importAnimation = anim;
            mi.importCameras = false;
            mi.importLights = false;
            mi.importBlendShapes = !anim;
            mi.materialImportMode = anim ? ModelImporterMaterialImportMode.None : ModelImporterMaterialImportMode.ImportStandard;
            mi.animationCompression = ModelImporterAnimationCompression.Optimal;
        }

        void OnPreprocessAnimation()
        {
            if (!IsChar(assetPath) || !IsAnim(assetPath)) return;
            var mi = (ModelImporter)assetImporter;
            var clips = mi.defaultClipAnimations;
            if (clips == null || clips.Length == 0) return;
            string file = Path.GetFileNameWithoutExtension(assetPath);
            string slot = AnimSlots.Resolve(file, out _);
            for (int i = 0; i < clips.Length; i++)
            {
                var c = clips[i];
                c.name = clips.Length == 1 ? file : file + "_" + i;
                c.loopTime = slot != null && AnimSlots.IsLoop(slot);
                c.lockRootRotation = true;
                c.lockRootHeightY = true;
                c.lockRootPositionXZ = true;
                c.keepOriginalOrientation = true;
                c.keepOriginalPositionY = true;
                c.keepOriginalPositionXZ = true;
            }
            mi.clipAnimations = clips;
        }

        // ====================== Tekshiruv hisoboti ======================
        static readonly string[] Heroes = { "temur", "jaloliddin", "ulugbek", "chingiz" };
        static readonly string[] Recommended =
        {
            "idle", "walkF", "walkB", "crouch", "block", "jump", "jumpF", "run",
            "LP", "HP", "LK", "HK", "cHP", "cHK", "jK",
            "hitHigh", "hitMid", "hitHeavy", "knockdown", "getUp", "dizzy", "victory", "intro", "throw"
        };

        [MenuItem("O'zbek Jangi/FBX personajlarni tekshirish")]
        static void Report()
        {
            EnsureFolders();
            var sb = new StringBuilder("O'ZBEK JANGI — FBX personajlar holati\n\n");
            foreach (var id in Heroes)
            {
                string folder = $"Assets/Resources/Characters/{id}";
                sb.Append($"■ {id.ToUpper()}\n");
                var modelPath = Directory.Exists(folder) ? FindModel(folder) : null;
                if (modelPath == null) { sb.Append("   Model: YO'Q (protsedural qahramon ishlatiladi)\n\n"); continue; }
                var go = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
                var an = go != null ? go.GetComponentInChildren<Animator>() : null;
                bool human = an != null && an.avatar != null && an.avatar.isHuman;
                sb.Append($"   Model: {Path.GetFileName(modelPath)} — {(human ? "Humanoid ✔" : "Humanoid EMAS ✖ (Mixamo'da rig qiling)")}\n");
                var found = new HashSet<string>();
                var unknown = new List<string>();
                foreach (var f in Directory.GetFiles(folder + "/Anims", "*.fbx"))
                {
                    string n = Path.GetFileNameWithoutExtension(f);
                    string slot = AnimSlots.Resolve(n, out _);
                    if (slot != null) found.Add(slot); else unknown.Add(n);
                }
                sb.Append($"   Animatsiyalar ({found.Count}): {string.Join(", ", found)}\n");
                var missing = new List<string>();
                foreach (var r in Recommended) if (!found.Contains(r)) missing.Add(r);
                if (missing.Count > 0) sb.Append($"   Yetishmaydi (protsedural bo'ladi): {string.Join(", ", missing)}\n");
                if (unknown.Count > 0) sb.Append($"   Tanilmagan fayllar (slot nomiga o'zgartiring): {string.Join(", ", unknown)}\n");
                sb.Append('\n');
            }
            Debug.Log(sb.ToString());
            EditorUtility.DisplayDialog("O'zbek Jangi — FBX", sb.ToString(), "OK");
        }

        static string FindModel(string folder)
        {
            string p = folder + "/model.fbx";
            if (File.Exists(p)) return p;
            foreach (var f in Directory.GetFiles(folder, "*.fbx")) return f.Replace('\\', '/');
            return null;
        }

        [MenuItem("O'zbek Jangi/FBX papkalarini yaratish")]
        static void EnsureFolders()
        {
            foreach (var id in Heroes)
            {
                string folder = $"Assets/Resources/Characters/{id}/Anims";
                if (!Directory.Exists(folder)) Directory.CreateDirectory(folder);
            }
            AssetDatabase.Refresh();
        }

        [MenuItem("O'zbek Jangi/FBX'larni qayta import qilish")]
        static void Reimport()
        {
            foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { "Assets/Resources/Characters" }))
                AssetDatabase.ImportAsset(AssetDatabase.GUIDToAssetPath(guid), ImportAssetOptions.ForceUpdate);
            Debug.Log("[O'zbek Jangi] FBX qayta import qilindi.");
        }
    }
}
