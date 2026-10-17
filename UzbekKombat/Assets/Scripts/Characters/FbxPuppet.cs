using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Animations;
using UnityEngine.Playables;

namespace UzbekKombat
{
    /// <summary>
    /// Tashqi FBX model (Mixamo / Meshy / Asset Store, Humanoid) ni o'yinga ulaydi.
    ///  • Model: Assets/Resources/Characters/{id}/model.fbx
    ///  • Animatsiyalar: Assets/Resources/Characters/{id}/Anims/*.fbx (fayl nomi = slot, masalan "LP.fbx", "idle.fbx")
    /// Slot uchun klip bo'lsa — mocap klipi o'ynaydi (zarba kadrlari jang ma'lumotlariga moslanadi).
    /// Klip bo'lmasa — protsedural animatsiya FBX skeletiga "retarget" qilinadi. FBX topilmasa — protsedural qahramon.
    /// </summary>
    [DefaultExecutionOrder(500)]
    public class FbxPuppet : MonoBehaviour
    {
        public Rig rig;
        public Animator animator;
        public Transform fbxRoot;
        public string id;

        readonly Dictionary<string, AnimationClip> clips = new Dictionary<string, AnimationClip>();
        readonly Dictionary<string, float> impacts = new Dictionary<string, float>();

        PlayableGraph graph;
        AnimationMixerPlayable mixer;
        readonly AnimationClipPlayable[] slotPlayables = new AnimationClipPlayable[2];
        readonly string[] slotNames = new string[2];
        int active;
        float fade = 1f;
        const float FadeTime = 0.1f;
        float procWeight = 1f;

        class Map
        {
            public Bone ours;
            public Transform fb;
            public Quaternion qO, qF;     // LookRotation(P,S) har ikki skelet uchun
        }
        readonly List<Map> maps = new List<Map>();
        Map mapHandR, mapHandL, mapChest;
        Transform fbHips;
        float hipRatio = 1f;
        float soleRestY;
        readonly List<Transform> soleBones = new List<Transform>();
        Transform proxyR, proxyL, proxyBack;

        // Fighter so'rovi (har kadr)
        string reqSlot;
        float reqTime;
        bool reqNormalized, reqLoop;
        public bool grounded = true;

        public bool HasModel => animator != null;

        // ============================ Yaratish ============================
        public static Rig Build(string id, System.Func<Transform, Rig> fallback, Transform parent)
        {
            var rig = fallback(parent);
            var prefab = FindModel(id);
            if (prefab == null) return rig;
            var p = rig.gameObject.AddComponent<FbxPuppet>();
            if (!p.Init(id, rig, prefab)) { Destroy(p); }
            return rig;
        }

        static GameObject FindModel(string id)
        {
            var go = Resources.Load<GameObject>($"Characters/{id}/model");
            if (go != null) return go;
            // "model" nomi bo'lmasa — eng ko'p uchli SkinnedMesh'li obyekt (Anims ichidagilar odatda teri­siz)
            GameObject best = null; int bestV = 0;
            foreach (var g in Resources.LoadAll<GameObject>($"Characters/{id}"))
            {
                int v = 0;
                foreach (var s in g.GetComponentsInChildren<SkinnedMeshRenderer>(true)) if (s.sharedMesh) v += s.sharedMesh.vertexCount;
                if (v > bestV && g.GetComponentInChildren<Animator>() != null) { bestV = v; best = g; }
            }
            return bestV > 500 ? best : null;
        }

        bool Init(string charId, Rig r, GameObject prefab)
        {
            id = charId;
            rig = r;
            var go = Instantiate(prefab, rig.model, false);
            go.name = "FBX_" + prefab.name;
            fbxRoot = go.transform;
            fbxRoot.localPosition = Vector3.zero;
            fbxRoot.localRotation = Quaternion.identity;
            animator = go.GetComponentInChildren<Animator>();
            if (animator == null || animator.avatar == null || !animator.avatar.isHuman)
            {
                Debug.LogWarning($"[O'zbek Jangi] {charId}: FBX Humanoid emas (Rig → Animation Type = Humanoid). Protsedural model ishlatiladi.");
                Destroy(go);
                animator = null;
                return false;
            }
            animator.runtimeAnimatorController = null;
            animator.applyRootMotion = false;
            animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;

            // --- Masshtab: bosh balandligi protsedural skeletga teng ---
            var head = animator.GetBoneTransform(HumanBodyBones.Head);
            float fbHead = ModelPos(head).y;
            float ourHead = ModelPos(rig[Bone.Head]).y;
            if (fbHead > 0.01f) fbxRoot.localScale *= ourHead / fbHead;

            Calibrate();
            SetupProxies();
            HideProcedural(go);
            PrepareMaterials(go);
            LoadClips();

            graph = PlayableGraph.Create("UK_" + charId);
            graph.SetTimeUpdateMode(DirectorUpdateMode.Manual);
            var output = AnimationPlayableOutput.Create(graph, "anim", animator);
            mixer = AnimationMixerPlayable.Create(graph, 2);
            output.SetSourcePlayable(mixer);
            graph.Play();
            Debug.Log($"[O'zbek Jangi] {charId}: FBX ulandi ({prefab.name}), animatsiya slotlari: {clips.Count} — {string.Join(", ", clips.Keys)}");
            return true;
        }

        Vector3 ModelPos(Transform t) => rig.model.InverseTransformPoint(t.position);

        Quaternion RelRot(Transform t)
        {
            Quaternion q = Quaternion.identity;
            while (t != null && t != rig.model) { q = t.localRotation * q; t = t.parent; }
            return q;
        }

        // ============================ Kalibrlash ============================
        enum Kind { Trunk, Limb, Hand, Foot }

        void Calibrate()
        {
            void Add(Bone ours, HumanBodyBones hb, Kind kind, HumanBodyBones child, ref Map store)
            {
                var fb = animator.GetBoneTransform(hb);
                if (fb == null) return;
                Vector3 up = Vector3.up, fwd = Vector3.forward;
                Vector3 pModel, sModel;
                switch (kind)
                {
                    case Kind.Trunk: pModel = up; sModel = fwd; break;
                    case Kind.Foot:
                        {
                            var toes = animator.GetBoneTransform(child);
                            pModel = toes != null ? (ModelPos(toes) - ModelPos(fb)).normalized : new Vector3(0, -0.3f, 1f).normalized;
                            sModel = up;
                            break;
                        }
                    case Kind.Hand:
                        {
                            var c = animator.GetBoneTransform(child);
                            var lower = fb.parent;
                            pModel = c != null ? (ModelPos(c) - ModelPos(fb)).normalized : (ModelPos(fb) - ModelPos(lower)).normalized;
                            sModel = fwd;
                            break;
                        }
                    default:
                        {
                            var c = animator.GetBoneTransform(child);
                            if (c == null) return;
                            pModel = (ModelPos(c) - ModelPos(fb)).normalized;
                            sModel = fwd;
                            break;
                        }
                }
                Quaternion rel = RelRot(fb);
                Vector3 pl = Quaternion.Inverse(rel) * pModel, sl = Quaternion.Inverse(rel) * sModel;
                var m = new Map { ours = ours, fb = fb, qF = Look(pl, sl), qO = OurQ(ours, kind) };
                maps.Add(m);
                store = m;
            }
            Map dummy = null;
            Add(Bone.Hips, HumanBodyBones.Hips, Kind.Trunk, HumanBodyBones.Spine, ref dummy);
            Add(Bone.Spine, HumanBodyBones.Spine, Kind.Trunk, HumanBodyBones.Chest, ref dummy);
            Add(Bone.Chest, HumanBodyBones.Chest, Kind.Trunk, HumanBodyBones.Neck, ref mapChest);
            Add(Bone.Chest, HumanBodyBones.UpperChest, Kind.Trunk, HumanBodyBones.Neck, ref dummy);
            Add(Bone.Neck, HumanBodyBones.Neck, Kind.Trunk, HumanBodyBones.Head, ref dummy);
            Add(Bone.Head, HumanBodyBones.Head, Kind.Trunk, HumanBodyBones.Head, ref dummy);
            Add(Bone.UpperArmL, HumanBodyBones.LeftUpperArm, Kind.Limb, HumanBodyBones.LeftLowerArm, ref dummy);
            Add(Bone.ForeArmL, HumanBodyBones.LeftLowerArm, Kind.Limb, HumanBodyBones.LeftHand, ref dummy);
            Add(Bone.HandL, HumanBodyBones.LeftHand, Kind.Hand, HumanBodyBones.LeftMiddleProximal, ref mapHandL);
            Add(Bone.UpperArmR, HumanBodyBones.RightUpperArm, Kind.Limb, HumanBodyBones.RightLowerArm, ref dummy);
            Add(Bone.ForeArmR, HumanBodyBones.RightLowerArm, Kind.Limb, HumanBodyBones.RightHand, ref dummy);
            Add(Bone.HandR, HumanBodyBones.RightHand, Kind.Hand, HumanBodyBones.RightMiddleProximal, ref mapHandR);
            Add(Bone.ThighL, HumanBodyBones.LeftUpperLeg, Kind.Limb, HumanBodyBones.LeftLowerLeg, ref dummy);
            Add(Bone.ShinL, HumanBodyBones.LeftLowerLeg, Kind.Limb, HumanBodyBones.LeftFoot, ref dummy);
            Add(Bone.FootL, HumanBodyBones.LeftFoot, Kind.Foot, HumanBodyBones.LeftToes, ref dummy);
            Add(Bone.ThighR, HumanBodyBones.RightUpperLeg, Kind.Limb, HumanBodyBones.RightLowerLeg, ref dummy);
            Add(Bone.ShinR, HumanBodyBones.RightLowerLeg, Kind.Limb, HumanBodyBones.RightFoot, ref dummy);
            Add(Bone.FootR, HumanBodyBones.RightFoot, Kind.Foot, HumanBodyBones.RightToes, ref dummy);

            fbHips = animator.GetBoneTransform(HumanBodyBones.Hips);
            float ourHipY = ModelPos(rig[Bone.Hips]).y;
            hipRatio = ourHipY > 0.01f ? ModelPos(fbHips).y / ourHipY : 1f;
            soleRestY = float.MaxValue;
            foreach (var hb in new[] { HumanBodyBones.LeftFoot, HumanBodyBones.RightFoot, HumanBodyBones.LeftToes, HumanBodyBones.RightToes })
            {
                var t = animator.GetBoneTransform(hb);
                if (t == null) continue;
                soleBones.Add(t);
                soleRestY = Mathf.Min(soleRestY, ModelPos(t).y);
            }
            if (soleRestY == float.MaxValue) soleRestY = 0.08f;
        }

        static Quaternion Look(Vector3 p, Vector3 s)
        {
            Vector3 so = s - Vector3.Dot(s, p) * p;
            if (so.sqrMagnitude < 1e-6f) so = Vector3.Cross(p, Vector3.right);
            return Quaternion.LookRotation(p, so.normalized);
        }

        /// <summary>Protsedural skeletda suyakning asosiy (P) va ikkilamchi (S) o'qlari — lokal fazoda.</summary>
        static Quaternion OurQ(Bone b, Kind k)
        {
            switch (k)
            {
                case Kind.Trunk: return Look(Vector3.up, Vector3.forward);
                case Kind.Foot: return Look(new Vector3(0, -0.05f, 0.15f).normalized, Vector3.up);
                default: return Look(Vector3.down, Vector3.forward);
            }
        }

        void SetupProxies()
        {
            Transform MakeProxy(string n, Transform mount)
            {
                if (mount == null) return null;
                var p = new GameObject(n).transform;
                p.SetParent(rig.model, false);
                mount.SetParent(p, false);
                return p;
            }
            if (mapHandR != null) proxyR = MakeProxy("ProxyHandR", rig.mountR);
            if (mapHandL != null) proxyL = MakeProxy("ProxyHandL", rig.mountL);
            if (mapChest != null) proxyBack = MakeProxy("ProxyChest", rig.mountBack);
        }

        void HideProcedural(GameObject fbx)
        {
            foreach (var r in rig.GetComponentsInChildren<Renderer>(true))
            {
                if (r.transform.IsChildOf(fbx.transform)) continue;
                if ((proxyR && r.transform.IsChildOf(proxyR)) || (proxyL && r.transform.IsChildOf(proxyL)) || (proxyBack && r.transform.IsChildOf(proxyBack))) continue;
                r.enabled = false;
            }
            foreach (var sb in rig.GetComponentsInChildren<SpringBone>(true)) sb.enabled = false;
        }

        static void PrepareMaterials(GameObject go)
        {
            foreach (var r in go.GetComponentsInChildren<Renderer>(true))
            {
                var mats = r.materials; // nusxa
                foreach (var m in mats)
                {
                    if (m == null) continue;
                    if (m.HasProperty("_EmissionColor"))
                    {
                        m.EnableKeyword("_EMISSION");
                        if (m.GetColor("_EmissionColor").maxColorComponent < 0.001f) m.SetColor("_EmissionColor", Color.black);
                    }
                }
                r.materials = mats;
                r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
                if (r is SkinnedMeshRenderer smr) smr.updateWhenOffscreen = true;
            }
        }

        // ============================ Klip slotlari ============================
        void LoadClips()
        {
            foreach (var c in Resources.LoadAll<AnimationClip>($"Characters/{id}"))
            {
                if (c == null || c.name.StartsWith("__preview__")) continue;
                string slot = AnimSlots.Resolve(c.name, out float impact);
                if (slot == null || clips.ContainsKey(slot)) continue;
                clips[slot] = c;
                impacts[slot] = impact;
            }
        }

        public bool Has(string slot) => slot != null && clips.ContainsKey(slot);

        public string First(params string[] candidates)
        {
            foreach (var s in candidates) if (Has(s)) return s;
            return null;
        }

        /// <summary>Takrorlanuvchi (loop) yoki bir martalik slotni so'rash. normalized=true bo'lsa time — 0..1.</summary>
        public void Request(string slot, float time, bool normalized, bool loop)
        {
            reqSlot = slot; reqTime = time; reqNormalized = normalized; reqLoop = loop;
        }

        /// <summary>Zarba: klipning "zarba nuqtasi" o'yin kadrlaridagi startup bilan bir vaqtga to'g'ri keladi.</summary>
        public void RequestAttack(string slot, float frame, int startup, int total)
        {
            if (!Has(slot)) { reqSlot = null; return; }
            float imp = impacts.TryGetValue(slot, out var i) ? i : 0.4f;
            float n = frame <= startup ? frame / Mathf.Max(1, startup) * imp
                                       : imp + (frame - startup) / Mathf.Max(1f, total - startup) * (1 - imp);
            Request(slot, Mathf.Clamp01(n), true, false);
        }

        public void ClearRequest() { reqSlot = null; }

        // ============================ Har kadr ============================
        void LateUpdate() => Apply(Time.deltaTime);

        public void ApplyNow() => Apply(0.016f, true);

        void Apply(float dt, bool snap = false)
        {
            if (animator == null || !graph.IsValid()) return;
            AnimationClip clip = Has(reqSlot) ? clips[reqSlot] : null;
            if (clip != null && slotNames[active] != reqSlot)
            {
                int next = 1 - active;
                if (slotPlayables[next].IsValid()) { graph.Disconnect(mixer, next); slotPlayables[next].Destroy(); }
                var p = AnimationClipPlayable.Create(graph, clip);
                p.SetApplyFootIK(true);
                graph.Connect(p, 0, mixer, next);
                slotPlayables[next] = p;
                slotNames[next] = reqSlot;
                active = next;
                fade = snap || slotNames[1 - active] == null ? 1f : 0f;
            }
            if (clip != null)
            {
                fade = Mathf.Min(1f, fade + dt / FadeTime);
                mixer.SetInputWeight(active, fade);
                mixer.SetInputWeight(1 - active, slotPlayables[1 - active].IsValid() ? 1 - fade : 0);
                float len = Mathf.Max(0.01f, clip.length);
                float t = reqNormalized ? reqTime * len : reqTime;
                t = reqLoop ? Mathf.Repeat(t, len) : Mathf.Clamp(t, 0, len - 0.001f);
                slotPlayables[active].SetTime(t);
                graph.Evaluate(0f);
            }
            float procTarget = clip != null ? 0f : 1f;
            procWeight = snap ? procTarget : Mathf.MoveTowards(procWeight, procTarget, dt / FadeTime);
            if (clip == null && procWeight >= 0.999f && slotNames[active] != null)
            {
                // Protsedural rejim: mikser bo'sh (dam olish pozasi) — retarget to'liq ishlaydi
            }

            Retarget(procWeight);
            if (grounded) Ground();
            UpdateProxies();
        }

        void Retarget(float w)
        {
            if (w <= 0.001f) return;
            foreach (var m in maps)
            {
                Quaternion ours = RelRot(rig[m.ours]);
                Quaternion desired = ours * m.qO * Quaternion.Inverse(m.qF);
                Quaternion current = RelRot(m.fb);
                Quaternion blended = w >= 0.999f ? desired : Quaternion.Slerp(current, desired, w);
                m.fb.localRotation = Quaternion.Inverse(RelRot(m.fb.parent)) * blended;
            }
            // Chanoq pozitsiyasi
            Vector3 ourHip = ModelPos(rig[Bone.Hips]);
            Vector3 desiredHip = new Vector3(ourHip.x, ourHip.y * hipRatio, ourHip.z);
            Vector3 cur = ModelPos(fbHips);
            fbHips.position = rig.model.TransformPoint(Vector3.Lerp(cur, desiredHip, w));
        }

        void Ground()
        {
            if (soleBones.Count == 0) return;
            float minY = float.MaxValue;
            foreach (var t in soleBones) minY = Mathf.Min(minY, ModelPos(t).y);
            float delta = Mathf.Clamp(soleRestY - minY, -0.4f, 0.4f);
            if (Mathf.Abs(delta) < 0.0005f) return;
            Vector3 hp = ModelPos(fbHips);
            fbHips.position = rig.model.TransformPoint(hp + new Vector3(0, delta, 0));
        }

        void UpdateProxies()
        {
            void Set(Transform proxy, Map m)
            {
                if (proxy == null || m == null) return;
                Quaternion f = RelRot(m.fb);
                proxy.localPosition = ModelPos(m.fb);
                proxy.localRotation = f * m.qF * Quaternion.Inverse(m.qO);
                proxy.localScale = Vector3.one;
            }
            Set(proxyR, mapHandR);
            Set(proxyL, mapHandL);
            Set(proxyBack, mapChest);
        }

        void OnDestroy()
        {
            if (graph.IsValid()) graph.Destroy();
        }
    }

    /// <summary>
    /// Animatsiya fayl nomlarini o'yin slotlariga moslash. Eng ishonchli yo'l — faylni slot nomi bilan nomlash
    /// (masalan "LP.fbx"). Mixamo standart nomlari ham taniladi. "@0.35" qo'shimchasi — zarba nuqtasi (klipning 35%).
    /// </summary>
    public static class AnimSlots
    {
        public static readonly string[] All =
        {
            "idle", "walkF", "walkB", "crouch", "block", "crouchBlock", "blockHit", "jump", "jumpF", "land", "run", "dashF", "dashB",
            "LP", "LP2", "HP", "LK", "HK", "cLP", "cHP", "cLK", "cHK", "jP", "jK", "throw", "thrown",
            "hitHigh", "hitMid", "hitLow", "hitHeavy", "juggle", "knockdown", "lying", "getUp", "dizzy",
            "victory", "intro", "defeat", "taunt",
            "special1", "special2", "special3", "special4", "super"
        };

        static readonly Dictionary<string, string> alias = new Dictionary<string, string>
        {
            // turish / harakat
            { "fightingidle", "idle" }, { "fightidle", "idle" }, { "boxingidle", "idle" }, { "swordandshieldidle", "idle" }, { "greatswordidle", "idle" }, { "idle", "idle" },
            { "walkingforward", "walkF" }, { "walkforward", "walkF" }, { "stepforward", "walkF" }, { "walking", "walkF" }, { "swordandshieldwalk", "walkF" },
            { "walkingbackwards", "walkB" }, { "walkbackward", "walkB" }, { "walkbackwards", "walkB" }, { "stepbackward", "walkB" },
            { "crouchidle", "crouch" }, { "crouching", "crouch" }, { "crouchingidle", "crouch" },
            { "blocking", "block" }, { "block", "block" }, { "standingblockidle", "block" }, { "swordandshieldblockidle", "block" },
            { "crouchblock", "crouchBlock" }, { "crouchingblock", "crouchBlock" },
            { "jump", "jump" }, { "jumping", "jump" }, { "frontflip", "jumpF" }, { "jumpforward", "jumpF" }, { "landing", "land" },
            { "running", "run" }, { "run", "run" }, { "fastrun", "run" },
            // zarbalar
            { "punching", "LP" }, { "punch", "LP" }, { "leadjab", "LP" }, { "jab", "LP" }, { "swordandshieldslash", "LP" },
            { "crosspunch", "HP" }, { "hook", "HP" }, { "hookpunch", "HP" }, { "swordslash", "HP" }, { "greatswordslash", "HP" }, { "stableswordoutwardslash", "HP" },
            { "kick", "LK" }, { "frontkick", "LK" }, { "mmakick", "HK" }, { "roundhousekick", "HK" }, { "hurricanekick", "HK" },
            { "uppercut", "cHP" }, { "legsweep", "cHK" }, { "sweep", "cHK" },
            { "flyingkick", "jK" },
            // reaksiyalar
            { "headhit", "hitHigh" }, { "hitreaction", "hitHigh" }, { "bigheadhit", "hitHigh" }, { "stomachhit", "hitMid" }, { "bodyhit", "hitMid" },
            { "bigstomachhit", "hitHeavy" }, { "fallingbackdeath", "knockdown" }, { "knockeddown", "knockdown" }, { "fallflat", "knockdown" }, { "dying", "defeat" },
            { "gettingup", "getUp" }, { "standup", "getUp" }, { "standingup", "getUp" }, { "dizzy", "dizzy" }, { "drunkidle", "dizzy" },
            { "victory", "victory" }, { "victoryidle", "victory" }, { "cheering", "victory" }, { "taunt", "taunt" }, { "rallying", "intro" },
            { "defeated", "defeat" }, { "throw", "throw" }, { "thrown", "thrown" },
        };

        static string Norm(string s)
        {
            var sb = new System.Text.StringBuilder();
            foreach (char ch in s.ToLowerInvariant()) if (char.IsLetterOrDigit(ch)) sb.Append(ch);
            return sb.ToString();
        }

        public static string Resolve(string clipName, out float impact)
        {
            impact = 0.4f;
            string n = clipName;
            int at = n.IndexOf('@');
            if (at >= 0)
            {
                float.TryParse(n.Substring(at + 1).Replace(',', '.'), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float imp);
                if (imp > 0 && imp < 1) impact = imp;
                n = n.Substring(0, at);
            }
            n = n.Trim();
            // 1) aynan slot nomi (katta-kichik harf farqi yo'q)
            foreach (var s in All) if (string.Equals(s, n, System.StringComparison.OrdinalIgnoreCase)) return s;
            // 2) Mixamo taxallusi
            string k = Norm(n);
            if (alias.TryGetValue(k, out var slot)) return slot;
            foreach (var kv in alias) if (k.StartsWith(kv.Key)) return kv.Value;
            return null;
        }

        public static bool IsLoop(string slot) =>
            slot == "idle" || slot == "walkF" || slot == "walkB" || slot == "crouch" || slot == "block" || slot == "crouchBlock" ||
            slot == "run" || slot == "dizzy" || slot == "lying";
    }
}
