using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Shatranj.Visual
{
    public enum Ambience { Day, Sunset, Night }

    /// <summary>
    /// Собирает мехмонхону (InteriorBuilder) и отвечает за атмосферу: солнце через окна,
    /// заполняющий свет, фонари, лучи света с пылинками, пробу отражений и время суток.
    /// </summary>
    public class EnvironmentBuilder : MonoBehaviour
    {
        Light sun, fill, iconLight;
        readonly List<Light> lanterns = new List<Light>();
        readonly List<GameObject> lanternGlows = new List<GameObject>();
        readonly List<GameObject> shafts = new List<GameObject>();
        ReflectionProbe probe;
        ParticleSystem motes;
        Material shaftMat, glowMat;

        public static float FloorY { get { return InteriorBuilder.FloorY; } }

        public void Build()
        {
            var table = new GameObject("Xontaxta").transform;
            table.SetParent(transform, false);
            InteriorBuilder.BuildTable(table);

            var room = new GameObject("Mehmonxona").transform;
            room.SetParent(transform, false);
            InteriorBuilder.BuildRoom(room);

            // стены и потолок не отбрасывают тени, чтобы солнце из окон доставало до доски
            foreach (var r in room.GetComponentsInChildren<MeshRenderer>())
                r.shadowCastingMode = ShadowCastingMode.Off;
            // утварь на столе тоже без теней: тени отбрасывают только доска и фигуры
            foreach (var r in table.GetComponentsInChildren<MeshRenderer>())
                r.shadowCastingMode = ShadowCastingMode.Off;
            foreach (var r in room.GetComponentsInChildren<MeshRenderer>())
                if (r.sharedMaterial == InteriorBuilder.WindowGlow) r.receiveShadows = false;

            var floorCol = new GameObject("FloorCollider").AddComponent<BoxCollider>();
            floorCol.transform.SetParent(transform, false);
            floorCol.center = new Vector3(0, FloorY - 0.5f, 0);
            floorCol.size = new Vector3(InteriorBuilder.Half * 2f, 1f, InteriorBuilder.Half * 2f);
            var tableCol = table.gameObject.AddComponent<BoxCollider>();
            tableCol.center = new Vector3(0, InteriorBuilder.TableTop - InteriorBuilder.TableThick * 0.5f, 0);
            tableCol.size = new Vector3(12.6f, InteriorBuilder.TableThick, 12.6f);

            BuildLights();
            BuildShafts();
            BuildMotes();
            BuildProbe();

            // неподвижную геометрию объединяем — меньше вызовов отрисовки на телефоне
            StaticBatchingUtility.Combine(room.gameObject);
            StaticBatchingUtility.Combine(table.gameObject);
        }

        static Transform Part(Transform p, Mesh mesh, Material m, Vector3 pos, Vector3 euler, Vector3 scale, bool shadows = true)
        {
            var go = new GameObject(mesh != null ? mesh.name : "part");
            go.transform.SetParent(p, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = m;
            if (!shadows) r.shadowCastingMode = ShadowCastingMode.Off;
            return go.transform;
        }

        // ================================================================== Свет

        void BuildLights()
        {
            var sgo = new GameObject("Sun");
            sgo.transform.SetParent(transform, false);
            sun = sgo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.8f;
            sun.shadowBias = 0.03f;
            sun.shadowNormalBias = 0.25f;
            sun.cullingMask = ~(1 << IconRenderer.Layer);

            var fgo = new GameObject("Fill");
            fgo.transform.SetParent(transform, false);
            fill = fgo.AddComponent<Light>();
            fill.type = LightType.Directional;
            fill.shadows = LightShadows.None;
            fill.cullingMask = ~(1 << IconRenderer.Layer);

            var igo = new GameObject("IconLight");
            igo.transform.SetParent(transform, false);
            iconLight = igo.AddComponent<Light>();
            iconLight.type = LightType.Directional;
            iconLight.intensity = 1.15f;
            iconLight.color = new Color(1f, 0.95f, 0.88f);
            iconLight.transform.rotation = Quaternion.Euler(35f, 150f, 0);
            iconLight.cullingMask = 1 << IconRenderer.Layer;
            iconLight.shadows = LightShadows.None;

            glowMat = MaterialLib.Unlit(new Color(1f, 0.72f, 0.35f, 0.85f), TextureFactory.Glow());

            // фонари-чироқ на хонтахте — настоящие источники света
            foreach (var p in InteriorBuilder.TableLanterns)
            {
                var body = new GameObject("Chiroq").transform;
                body.SetParent(transform, false);
                body.localPosition = p;
                var mesh = MeshBuilder.Cached("env.chiroq", () => MeshBuilder.Lathe("chiroq", new[]
                {
                    new Vector2(0, 0), new Vector2(0.25f, 0), new Vector2(0.2f, 0.1f), new Vector2(0.12f, 0.15f), new Vector2(0.16f, 0.5f),
                    new Vector2(0.22f, 0.55f), new Vector2(0.1f, 0.75f), new Vector2(0.03f, 0.9f), new Vector2(0, 0.95f)
                }, 12, 0, 360, true));
                Part(body, mesh, MaterialLib.Brass, Vector3.zero, Vector3.zero, Vector3.one);
                var glow = Part(body, MeshBuilder.QuadXZ, glowMat, new Vector3(0, 0.38f, 0), Vector3.zero, new Vector3(1.4f, 1f, 1.4f), false);
                glow.gameObject.AddComponent<Billboard>();
                lanternGlows.Add(glow.gameObject);

                var lgo = new GameObject("LanternLight");
                lgo.transform.SetParent(transform, false);
                lgo.transform.localPosition = p + new Vector3(0, 0.45f, 0);
                var l = lgo.AddComponent<Light>();
                l.type = LightType.Point;
                l.range = 13f;
                l.color = new Color(1f, 0.68f, 0.36f);
                l.shadows = LightShadows.None;
                l.cullingMask = ~(1 << IconRenderer.Layer);
                lanterns.Add(l);
            }

            // подвесные латунные фонари — свечение
            foreach (var p in InteriorBuilder.HangingLanterns)
            {
                var glow = Part(transform, MeshBuilder.QuadXZ, glowMat, p, Vector3.zero, new Vector3(2.6f, 1f, 2.6f), false);
                glow.gameObject.AddComponent<Billboard>();
                lanternGlows.Add(glow.gameObject);
            }
        }

        // ================================================================== Лучи света и пылинки

        void BuildShafts()
        {
            shaftMat = MaterialLib.Unlit(new Color(1f, 0.9f, 0.7f, 0.07f), TextureFactory.LightShaft());
            var mesh = new Mesh { name = "shaft" };
            mesh.vertices = new[] { new Vector3(-0.5f, 0, 0), new Vector3(0.5f, 0, 0), new Vector3(0.5f, -1f, 0), new Vector3(-0.5f, -1f, 0) };
            mesh.uv = new[] { new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0), new Vector2(0, 0) };
            mesh.triangles = new[] { 0, 1, 2, 0, 2, 3 };
            mesh.RecalculateNormals();
            mesh.RecalculateBounds();

            foreach (var win in InteriorBuilder.Windows)
            {
                Vector3 dir = (win.Inward + Vector3.down * 0.75f).normalized;
                var root = new GameObject("Shaft").transform;
                root.SetParent(transform, false);
                root.position = win.Center;
                root.rotation = Quaternion.FromToRotation(Vector3.down, dir);
                for (int k = 0; k < 2; k++)
                {
                    var q = Part(root, mesh, shaftMat, Vector3.zero, new Vector3(0, k * 90f, 0), new Vector3(win.Width * 0.9f, 19f, 1f), false);
                    q.GetComponent<MeshRenderer>().receiveShadows = false;
                }
                shafts.Add(root.gameObject);
            }
        }

        void BuildMotes()
        {
            var go = new GameObject("Motes");
            go.transform.SetParent(transform, false);
            go.transform.localPosition = new Vector3(0, 2.5f, 0);
            motes = go.AddComponent<ParticleSystem>();
            motes.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var m = motes.main;
            m.loop = true;
            m.startLifetime = new ParticleSystem.MinMaxCurve(7f, 12f);
            m.startSpeed = new ParticleSystem.MinMaxCurve(0.02f, 0.12f);
            m.startSize = new ParticleSystem.MinMaxCurve(0.04f, 0.09f);
            m.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0.92f, 0.75f, 0.7f), new Color(1f, 0.85f, 0.6f, 0.4f));
            m.maxParticles = 220;
            m.simulationSpace = ParticleSystemSimulationSpace.World;
            m.gravityModifier = -0.002f;
            var em = motes.emission;
            em.rateOverTime = 14f;
            var sh = motes.shape;
            sh.shapeType = ParticleSystemShapeType.Box;
            sh.scale = new Vector3(22f, 9f, 22f);
            var noise = motes.noise;
            noise.enabled = true;
            noise.strength = 0.12f;
            noise.frequency = 0.25f;
            var col = motes.colorOverLifetime;
            col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(Color.white, 1) },
                      new[] { new GradientAlphaKey(0f, 0), new GradientAlphaKey(1f, 0.3f), new GradientAlphaKey(1f, 0.7f), new GradientAlphaKey(0f, 1) });
            col.color = new ParticleSystem.MinMaxGradient(g);
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = MaterialLib.Unlit(Color.white, TextureFactory.Glow());
            r.shadowCastingMode = ShadowCastingMode.Off;
            r.receiveShadows = false;
            motes.Play();
        }

        // ================================================================== Отражения

        void BuildProbe()
        {
            var go = new GameObject("ReflectionProbe");
            go.transform.SetParent(transform, false);
            go.transform.localPosition = new Vector3(0, 3f, 0);
            probe = go.AddComponent<ReflectionProbe>();
            probe.mode = ReflectionProbeMode.Realtime;
            probe.refreshMode = ReflectionProbeRefreshMode.ViaScripting;
            probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.NoTimeSlicing;
            probe.size = new Vector3(InteriorBuilder.Half * 2f, InteriorBuilder.Height, InteriorBuilder.Half * 2f);
            probe.center = new Vector3(0, FloorY + InteriorBuilder.Height * 0.5f - 3f, 0);
            probe.boxProjection = true;
            probe.resolution = 128;
            probe.hdr = false;
            probe.cullingMask = ~((1 << IconRenderer.Layer) | (1 << 2));
            probe.clearFlags = ReflectionProbeClearFlags.SolidColor;
            probe.backgroundColor = new Color(0.25f, 0.18f, 0.12f);
        }

        /// <summary>Перерисовать отражения (после смены освещения или расстановки).</summary>
        public void RefreshReflections()
        {
            if (probe == null) return;
            QualitySettings.realtimeReflectionProbes = true;
            probe.RenderProbe();
        }

        // ================================================================== Время суток

        public void Apply(Ambience a, int quality)
        {
            Color sunColor, fillColor, ambSky, ambEq, ambGround, window, shaft;
            float sunI, fillI, lanternI;
            Vector3 sunRot;
            bool lampsOn;
            switch (a)
            {
                case Ambience.Day:
                    sunColor = new Color(1f, 0.95f, 0.86f); sunI = 1.05f; sunRot = new Vector3(52f, -62f, 0);
                    fillColor = new Color(0.65f, 0.75f, 0.95f); fillI = 0.28f;
                    ambSky = new Color(0.62f, 0.58f, 0.52f); ambEq = new Color(0.55f, 0.45f, 0.35f); ambGround = new Color(0.3f, 0.22f, 0.16f);
                    window = new Color(1f, 0.97f, 0.9f); shaft = new Color(1f, 0.95f, 0.82f, 0.07f);
                    lanternI = 0.6f; lampsOn = false;
                    break;
                case Ambience.Sunset:
                    sunColor = new Color(1f, 0.64f, 0.36f); sunI = 1.1f; sunRot = new Vector3(24f, -70f, 0);
                    fillColor = new Color(0.55f, 0.48f, 0.75f); fillI = 0.22f;
                    ambSky = new Color(0.55f, 0.42f, 0.38f); ambEq = new Color(0.56f, 0.37f, 0.25f); ambGround = new Color(0.22f, 0.14f, 0.1f);
                    window = new Color(1f, 0.72f, 0.42f); shaft = new Color(1f, 0.7f, 0.4f, 0.09f);
                    lanternI = 0.9f; lampsOn = true;
                    break;
                default:
                    sunColor = new Color(0.5f, 0.6f, 1f); sunI = 0.25f; sunRot = new Vector3(55f, 30f, 0);
                    fillColor = new Color(0.4f, 0.45f, 0.7f); fillI = 0.1f;
                    ambSky = new Color(0.17f, 0.15f, 0.2f); ambEq = new Color(0.2f, 0.14f, 0.1f); ambGround = new Color(0.08f, 0.06f, 0.05f);
                    window = new Color(0.12f, 0.18f, 0.36f); shaft = new Color(0.5f, 0.6f, 1f, 0.03f);
                    lanternI = 1.9f; lampsOn = true;
                    break;
            }
            sun.color = sunColor;
            sun.intensity = sunI;
            sun.transform.rotation = Quaternion.Euler(sunRot);
            fill.color = fillColor;
            fill.intensity = fillI;
            fill.transform.rotation = Quaternion.Euler(35f, 120f, 0);
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = ambSky;
            RenderSettings.ambientEquatorColor = ambEq;
            RenderSettings.ambientGroundColor = ambGround;
            RenderSettings.fog = false;
            RenderSettings.skybox = null;

            if (InteriorBuilder.WindowGlow != null) InteriorBuilder.WindowGlow.color = window;
            if (shaftMat != null) shaftMat.color = shaft;
            foreach (var s in shafts) s.SetActive(a != Ambience.Night);
            foreach (var l in lanterns) { l.enabled = true; l.intensity = lanternI; }
            foreach (var g in lanternGlows) g.SetActive(lampsOn || g.transform.parent != transform);
            if (motes != null)
            {
                var r = motes.GetComponent<ParticleSystemRenderer>();
                r.enabled = a != Ambience.Night && quality > 0;
            }
            var cam = Camera.main;
            if (cam != null) cam.backgroundColor = new Color(0.12f, 0.08f, 0.05f);

            ApplyQuality(quality);
            RefreshReflections();
        }

        /// <summary>
        /// Уровни графики под телефоны: Низкая — без теней и попиксельных фонарей, 30 FPS, рендер 540p;
        /// Средняя — жёсткие тени, один попиксельный фонарь, 720p; Высокая — мягкие тени, 900p.
        /// Интерфейс при этом остаётся чётким (Canvas масштабируется отдельно).
        /// </summary>
        public void ApplyQuality(int q)
        {
            int shortSide;
            switch (q)
            {
                case 0:
                    sun.shadows = LightShadows.None;
                    QualitySettings.antiAliasing = 0;
                    QualitySettings.pixelLightCount = 0;
                    shortSide = 540;
                    break;
                case 1:
                    sun.shadows = LightShadows.Hard;
                    QualitySettings.shadowResolution = ShadowResolution.Low;
                    QualitySettings.antiAliasing = 2;
                    QualitySettings.pixelLightCount = 1;
                    shortSide = 720;
                    break;
                default:
                    sun.shadows = LightShadows.Soft;
                    QualitySettings.shadowResolution = ShadowResolution.Medium;
                    QualitySettings.antiAliasing = 2;
                    QualitySettings.pixelLightCount = 2;
                    shortSide = 900;
                    break;
            }
            QualitySettings.shadows = q == 0 ? ShadowQuality.Disable : ShadowQuality.All;
            QualitySettings.shadowDistance = q == 1 ? 26f : 32f;
            QualitySettings.shadowCascades = 1;
            QualitySettings.softParticles = false;
            Application.targetFrameRate = q == 0 ? 30 : 60;
            if (probe != null) probe.resolution = q == 0 ? 64 : 128;
            SetRenderResolution(shortSide);
        }

        /// <summary>Рендер в пониженном разрешении на телефонах — главный выигрыш по FPS.</summary>
        static void SetRenderResolution(int shortSide)
        {
#if (UNITY_ANDROID || UNITY_IOS) && !UNITY_EDITOR
            int nw = Display.main.systemWidth, nh = Display.main.systemHeight;
            int nShort = Mathf.Min(nw, nh), nLong = Mathf.Max(nw, nh);
            if (nShort <= 0) return;
            float k = Mathf.Min(1f, shortSide / (float)nShort);
            int w = Mathf.RoundToInt(nShort * k), h = Mathf.RoundToInt(nLong * k);
            if (Screen.width != w || Screen.height != h) Screen.SetResolution(w, h, true);
#endif
        }
    }

    /// <summary>Поворачивает объект лицом к камере (свечение фонарей).</summary>
    public class Billboard : MonoBehaviour
    {
        void LateUpdate()
        {
            var cam = Camera.main;
            if (cam == null) return;
            transform.rotation = Quaternion.LookRotation(transform.position - cam.transform.position) * Quaternion.Euler(-90, 0, 0);
        }
    }
}
