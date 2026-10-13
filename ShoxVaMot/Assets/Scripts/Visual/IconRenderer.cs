using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    /// <summary>
    /// Рендерит 3D-фигуры в текстуры-иконки (для панели взятых фигур и выбора превращения).
    /// Отдельный слой и отдельный свет, поэтому иконки не зависят от времени суток.
    /// </summary>
    public static class IconRenderer
    {
        public const int Layer = 30;
        static readonly Vector3 StagePos = new Vector3(0, -300f, 0);
        static readonly Dictionary<int, RenderTexture> icons = new Dictionary<int, RenderTexture>();

        public static Texture Get(PieceType t, Side s)
        {
            RenderTexture rt;
            return icons.TryGetValue(Key(t, s), out rt) ? rt : null;
        }

        static int Key(PieceType t, Side s) { return (int)t * 2 + (int)s; }

        /// <summary>На Android текстуры-рендеры могут теряться при сворачивании — перерисуем.</summary>
        public static void RefreshIfLost()
        {
            bool lost = icons.Count == 0;
            foreach (var rt in icons.Values) if (rt == null || !rt.IsCreated()) { lost = true; break; }
            if (!lost) return;
            foreach (var rt in icons.Values) if (rt != null) rt.Release();
            icons.Clear();
            RenderAll();
        }

        public static void RenderAll()
        {
            var camGo = new GameObject("IconCamera");
            var cam = camGo.AddComponent<Camera>();
            cam.enabled = false;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0, 0, 0, 0);
            cam.cullingMask = 1 << Layer;
            cam.fieldOfView = 26f;
            cam.nearClipPlane = 0.1f;
            cam.farClipPlane = 20f;
            cam.allowHDR = false;
            cam.allowMSAA = true;
            camGo.transform.position = StagePos + new Vector3(0, 1.15f, -2.75f);
            camGo.transform.LookAt(StagePos + new Vector3(0, 0.52f, 0));

            var holder = new GameObject("IconStage").transform;
            holder.position = StagePos;

            foreach (Side s in new[] { Side.White, Side.Black })
            {
                for (int t = 1; t <= 6; t++)
                {
                    var type = (PieceType)t;
                    var rt = new RenderTexture(192, 192, 16, RenderTextureFormat.ARGB32) { name = "icon_" + s + "_" + type, antiAliasing = 4 };
                    rt.Create();
                    var v = PieceFactory.Create(type, s, holder, Layer);
                    v.transform.localPosition = Vector3.zero;
                    v.transform.localRotation = Quaternion.Euler(0, 205f, 0);
                    v.enabled = false;
                    cam.targetTexture = rt;
                    cam.Render();
                    Object.DestroyImmediate(v.gameObject);
                    icons[Key(type, s)] = rt;
                }
            }
            cam.targetTexture = null;
            Object.Destroy(camGo);
            Object.Destroy(holder.gameObject);
        }
    }

    /// <summary>
    /// Витрина «Музея Афросиаба»: живая 3D-фигура на постаменте, рендерится в текстуру для UI.
    /// Фигуру можно вращать пальцем и показать удар саблей по узбекской дыне.
    /// </summary>
    public class ShowcaseStage : MonoBehaviour
    {
        public RenderTexture Texture { get; private set; }
        Camera cam;
        Transform turntable;
        PieceView current;
        GameObject melon;
        float spin, spinVel;
        bool attacking;
        static readonly Vector3 Pos = new Vector3(0, -600f, 0);
        public System.Action OnWhoosh, OnImpact;

        public static ShowcaseStage Create(Transform parent)
        {
            var go = new GameObject("Showcase");
            go.transform.SetParent(parent, false);
            go.transform.position = Pos;
            var s = go.AddComponent<ShowcaseStage>();
            s.Build();
            return s;
        }

        void Build()
        {
            Texture = new RenderTexture(768, 768, 16, RenderTextureFormat.ARGB32) { name = "showcase", antiAliasing = 4 };
            Texture.Create();

            var camGo = new GameObject("ShowcaseCamera");
            camGo.transform.SetParent(transform, false);
            cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0, 0, 0, 0);
            cam.cullingMask = 1 << IconRenderer.Layer;
            cam.fieldOfView = 30f;
            cam.targetTexture = Texture;
            cam.allowHDR = false;
            camGo.transform.localPosition = new Vector3(0, 1.3f, -3.1f);
            camGo.transform.LookAt(transform.position + new Vector3(0, 0.55f, 0.3f));
            cam.enabled = false;

            // постамент-ступень из майолики
            var plinth = new GameObject("Plinth");
            plinth.transform.SetParent(transform, false);
            plinth.transform.localPosition = new Vector3(0, -0.12f, 0);
            plinth.AddComponent<MeshFilter>().sharedMesh = MeshBuilder.Cached("lathe.plinth", () => MeshBuilder.Lathe("plinth", new[]
            {
                new Vector2(0, 0), new Vector2(1.1f, 0), new Vector2(1.1f, 0.06f), new Vector2(1.0f, 0.12f), new Vector2(0, 0.12f)
            }, 8, 22.5f, 360f, true, 4f));
            plinth.AddComponent<MeshRenderer>().sharedMaterial = MaterialLib.TileBlue;
            var col = plinth.AddComponent<BoxCollider>();
            col.center = new Vector3(0, 0.06f, 0);
            col.size = new Vector3(6f, 0.12f, 6f);
            PieceFactory.SetLayer(plinth, IconRenderer.Layer);

            turntable = new GameObject("Turntable").transform;
            turntable.SetParent(transform, false);
        }

        public void SetActive(bool on)
        {
            cam.enabled = on;
            gameObject.SetActive(on);
        }

        public void Show(PieceType type, Side side)
        {
            StopAllCoroutines();
            attacking = false;
            if (current != null) Destroy(current.gameObject);
            if (melon != null) Destroy(melon);
            current = PieceFactory.Create(type, side, turntable, IconRenderer.Layer);
            current.transform.localPosition = Vector3.zero;
            current.transform.localRotation = Quaternion.identity;
            spin = 200f;
            spinVel = 0f;
        }

        public void Drag(float dx) { spinVel = 0f; spin -= dx * 0.4f; }
        public void Release(float vx) { spinVel = -vx * 0.4f; }

        void Update()
        {
            if (current == null) return;
            if (!attacking)
            {
                spin += (spinVel + 14f) * Time.deltaTime;
                spinVel = Mathf.Lerp(spinVel, 0f, Time.deltaTime * 2f);
                turntable.localRotation = Quaternion.Euler(0, spin, 0);
            }
        }

        public void Attack()
        {
            if (current == null || attacking) return;
            StartCoroutine(AttackRoutine());
        }

        IEnumerator AttackRoutine()
        {
            attacking = true;
            Quaternion from = turntable.localRotation;
            Quaternion to = Quaternion.Euler(0, 90f, 0);
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.35f)
            {
                turntable.localRotation = Quaternion.Slerp(from, to, Ease.InOut(t));
                yield return null;
            }
            spin = 90f;

            // спелая узбекская дыня (қовун) как мишень
            if (melon != null) Destroy(melon);
            melon = new GameObject("Qovun");
            melon.transform.SetParent(transform, false);
            melon.transform.localPosition = new Vector3(0.62f, 0.2f, 0);
            melon.transform.localRotation = Quaternion.Euler(0, 0, 10);
            var mf = melon.AddComponent<MeshFilter>();
            mf.sharedMesh = MeshBuilder.Sphere;
            melon.transform.localScale = new Vector3(0.17f, 0.15f, 0.27f);
            var mr = melon.AddComponent<MeshRenderer>();
            mr.sharedMaterial = MelonMaterial();
            var body = new GameObject("half");
            body.transform.SetParent(melon.transform, false);
            body.AddComponent<MeshFilter>().sharedMesh = MeshBuilder.Sphere;
            body.AddComponent<MeshRenderer>().sharedMaterial = MelonInside();
            body.transform.localScale = Vector3.one * 0.92f;
            PieceFactory.SetLayer(melon, IconRenderer.Layer);
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.3f)
            {
                melon.transform.localScale = new Vector3(0.17f, 0.15f, 0.27f) * Ease.OutBack(t);
                yield return null;
            }

            var target = melon;
            yield return current.Strike(
                () => { if (OnWhoosh != null) OnWhoosh(); },
                () =>
                {
                    if (target == null) return;
                    Vector3 hit = target.transform.position + Vector3.up * 0.05f;
                    Fx.SwordClash(hit);
                    Fx.ShatterObject(target, hit, Vector3.right, 0.6f);
                    if (OnImpact != null) OnImpact();
                });
            melon = null;
            yield return null;
            attacking = false;
        }

        static Material melonMat, melonInside;

        static Material MelonMaterial()
        {
            if (melonMat != null) return melonMat;
            var tex = TextureFactory.Generate("qovun", 128, 128, (u, v, x, y) =>
            {
                float stripe = Mathf.Abs(Mathf.Sin(u * Mathf.PI * 12f + Noise.Value(u * 8f, v * 8f, 8, 8, 4) * 1.5f));
                float net = Noise.Value(u * 40f, v * 40f, 40, 40, 9);
                Color a = TextureFactory.Hex("#E4C64A"), b = TextureFactory.Hex("#9BA53A");
                Color c = Color.Lerp(a, b, stripe > 0.85f ? 0.8f : 0.1f);
                return c * (0.85f + net * 0.2f);
            });
            melonMat = MaterialLib.Std("qovun", Color.white, tex, 0.45f, 0f);
            return melonMat;
        }

        static Material MelonInside()
        {
            if (melonInside == null) melonInside = MaterialLib.Std("qovun.in", TextureFactory.Hex("#F6E3A0"), null, 0.6f, 0f);
            return melonInside;
        }
    }
}
