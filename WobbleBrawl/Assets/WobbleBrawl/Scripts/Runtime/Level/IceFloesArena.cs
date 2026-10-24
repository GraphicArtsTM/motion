using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Slippery ice floes bobbing on a stormy sea. Crowd one edge and it tips everyone into the water.</summary>
    public sealed class IceFloesArena : Arena
    {
        public override string Title => "Льдины";
        public override string Subtitle => "Шторм, лёд и скользкие ботинки.";

        protected override void BuildGeometry()
        {
            Radius = 7.5f;
            KillY = -0.9f;
            CameraPitch = 48f;
            CameraMinDist = 11f;
            SkyColor = new Color(0.42f, 0.48f, 0.58f);
            FogColor = new Color(0.5f, 0.56f, 0.65f);
            FogDensity = 0.022f;
            AmbientSky = new Color(0.6f, 0.68f, 0.8f);
            AmbientEquator = new Color(0.45f, 0.5f, 0.58f);
            AmbientGround = new Color(0.25f, 0.3f, 0.35f);
            SunColor = new Color(0.85f, 0.9f, 1f);
            SunIntensity = 0.95f;
            SunEuler = new Vector3(55f, 140f, 0f);

            Water(0f, 220f, new Color(0.1f, 0.3f, 0.42f));

            var ice = new Color(0.86f, 0.94f, 1f);
            var snow = Color.white;

            // the big central floe and a ring of smaller ones
            Floe(new Vector3(0, 0.05f, 0), new Vector3(5.2f, 0.8f, 5.2f), 0f, 1100f, ice, snow, 0f);
            for (int i = 0; i < 6; i++)
            {
                float a = i * Mathf.PI / 3f + 0.3f;
                float r = 5.6f;
                var p = new Vector3(Mathf.Cos(a) * r, 0.05f, Mathf.Sin(a) * r);
                Floe(p, new Vector3(3.2f, 0.7f, 3f), i * 23f, 520f, ice, snow, i * 1.1f);
            }

            // icebergs and a stranded ship on the horizon
            var rng = new System.Random(5);
            for (int i = 0; i < 9; i++)
            {
                float a = (float)rng.NextDouble() * Mathf.PI * 2f;
                float r = 25f + (float)rng.NextDouble() * 35f;
                float h = 4f + (float)rng.NextDouble() * 10f;
                Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(Mathf.Cos(a) * r, 0f, Mathf.Sin(a) * r),
                    new Vector3(h * 1.4f, h * 2f, h * 1.2f), new Color(0.88f, 0.94f, 1f), Quaternion.Euler(0, (float)rng.NextDouble() * 360f, 0), false, 0.6f);
            }
            var hull = new Color(0.6f, 0.15f, 0.15f);
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-22f, 0.5f, 30f), new Vector3(14f, 4f, 4f), hull, Quaternion.Euler(0, 20, 8));
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-22f, 3.5f, 30f), new Vector3(5f, 3f, 3f), Color.white, Quaternion.Euler(0, 20, 8));
            Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(-21f, 6f, 30f), new Vector3(1f, 2f, 1f), new Color(0.15f, 0.15f, 0.15f), Quaternion.Euler(0, 20, 8));

            Snowfall();
            Clouds(10, 30f, 60f, 14f, 22f, 8);

            SpawnRing(Vector3.zero, 1.6f, 4, 0.85f);
            for (int i = 0; i < 4; i++)
            {
                float a = i * Mathf.PI / 2f + 0.3f;
                Spawns.Add(new Vector3(Mathf.Cos(a) * 5.6f, 0.75f, Mathf.Sin(a) * 5.6f));
            }
            HillSpots.Add(new Vector3(0, 0.8f, 0));
            for (int i = 0; i < 3; i++)
            {
                float a = i * Mathf.PI * 2f / 3f + 0.3f;
                HillSpots.Add(new Vector3(Mathf.Cos(a) * 5.6f, 0.7f, Mathf.Sin(a) * 5.6f));
            }
        }

        void Floe(Vector3 pos, Vector3 size, float yaw, float mass, Color ice, Color snow, float phase)
        {
            pos.y = size.y * 0.5f; // floats with its bottom at the waterline
            var go = Kit.Box(Root, pos, size, ice, Quaternion.Euler(0, yaw, 0), Kit.IceMat, 0.9f);
            go.name = "Floe";
            // chunky snow caps (decorative) and a slightly bigger, darker underside
            Kit.Deco(PrimitiveType.Cube, go.transform, new Vector3(0, -0.35f, 0), new Vector3(1.05f, 0.4f, 1.05f), new Color(0.5f, 0.7f, 0.85f), null, false, 0.4f);
            Kit.Deco(PrimitiveType.Sphere, go.transform, new Vector3(0.25f, 0.5f, -0.2f), new Vector3(0.35f, 0.25f, 0.3f), snow, null, true, 0f);
            Kit.Deco(PrimitiveType.Sphere, go.transform, new Vector3(-0.3f, 0.5f, 0.3f), new Vector3(0.25f, 0.2f, 0.25f), snow, null, true, 0f);
            Buoyant.Attach(go, 0f, mass, phase);
        }

        void Snowfall()
        {
            var go = new GameObject("Snow");
            go.transform.SetParent(Root, false);
            go.transform.localPosition = new Vector3(0, 14f, 0);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = true;
            main.startLifetime = 9f;
            main.startSpeed = 0.5f;
            main.startSize = new ParticleSystem.MinMaxCurve(0.05f, 0.12f);
            main.startColor = new Color(1f, 1f, 1f, 0.9f);
            main.gravityModifier = 0.06f;
            main.maxParticles = 1500;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var emission = ps.emission;
            emission.rateOverTime = 150f;
            var shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Box;
            shape.scale = new Vector3(40f, 1f, 40f);
            var noise = ps.noise;
            noise.enabled = true;
            noise.strength = 0.6f;
            noise.frequency = 0.3f;
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.renderMode = ParticleSystemRenderMode.Mesh;
            r.mesh = MatFactory.Mesh(PrimitiveType.Sphere);
            r.sharedMaterial = MatFactory.Unlit();
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            ps.Play();
        }
    }
}
