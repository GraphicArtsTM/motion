using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// A procedurally built level. Subclasses lay out geometry and hazards in <see cref="BuildGeometry"/>
    /// and describe the space (spawns, kill height, throw targets, lighting) through the fields below.
    /// </summary>
    public abstract class Arena
    {
        public abstract string Title { get; }
        public abstract string Subtitle { get; }

        public Transform Root { get; private set; }
        public Vector3 Center = Vector3.zero;
        public float Radius = 7f;
        public float KillY = -6f;
        public bool HasWater;
        public float WaterY;
        public readonly List<Vector3> Spawns = new List<Vector3>();
        public readonly List<Vector3> HillSpots = new List<Vector3>();

        // camera framing
        public float CameraYaw = 0f, CameraPitch = 50f, CameraMinDist = 9f, CameraMaxDist = 30f;

        // lighting
        public Color SkyColor = new Color(0.55f, 0.75f, 0.95f);
        public Color FogColor = new Color(0.6f, 0.78f, 0.95f);
        public float FogDensity = 0.012f;
        public Color AmbientSky = new Color(0.6f, 0.68f, 0.8f);
        public Color AmbientEquator = new Color(0.5f, 0.5f, 0.55f);
        public Color AmbientGround = new Color(0.3f, 0.28f, 0.26f);
        public Color SunColor = new Color(1f, 0.95f, 0.85f);
        public float SunIntensity = 1.15f;
        public Vector3 SunEuler = new Vector3(50f, -35f, 0f);

        public void Build(Transform parent)
        {
            Root = Kit.Group(parent, GetType().Name).transform;
            BuildGeometry();
        }

        protected abstract void BuildGeometry();

        public virtual Vector3 SpawnPoint(int i) => Spawns.Count == 0 ? Center : Spawns[i % Spawns.Count];

        public Quaternion SpawnRotation(Vector3 p)
        {
            Vector3 to = Center - p;
            to.y = 0f;
            return to.sqrMagnitude < 0.01f ? Quaternion.identity : Quaternion.LookRotation(to.normalized, Vector3.up);
        }

        /// <summary>Where a bot should carry a victim to throw them out.</summary>
        public virtual Vector3 ThrowPoint(Vector3 from)
        {
            Vector3 d = from - Center;
            d.y = 0f;
            if (d.sqrMagnitude < 0.01f) d = Vector3.right;
            return Center + d.normalized * (Radius + 2f);
        }

        public virtual void OnBrawlerOut(Brawler b)
        {
            if (HasWater)
            {
                Vector3 p = b.Position;
                p.y = WaterY;
                Fx.Splash(p);
                Sfx.Play(Sfx.Splash, p, 1f, Random.Range(0.85f, 1.1f));
            }
        }

        public virtual void Tick(float dt) { }

        // ------------------------------------------------------------------ shared decoration helpers

        protected GameObject Water(float y, float size, Color color)
        {
            HasWater = true;
            WaterY = y;
            var w = Kit.Deco(PrimitiveType.Cube, Root, new Vector3(Center.x, y - 0.5f, Center.z), new Vector3(size, 1f, size), color, null, false, 0.85f);
            w.name = "Water";
            var bob = w.AddComponent<Bob>();
            bob.amp = 0.05f;
            bob.speed = 0.8f;
            return w;
        }

        protected void Clouds(int count, float minR, float maxR, float minY, float maxY, int seed)
        {
            var rng = new System.Random(seed);
            for (int i = 0; i < count; i++)
            {
                float a = (float)rng.NextDouble() * Mathf.PI * 2f;
                float r = Mathf.Lerp(minR, maxR, (float)rng.NextDouble());
                var c = Kit.Group(Root, "Cloud", new Vector3(Mathf.Cos(a) * r, Mathf.Lerp(minY, maxY, (float)rng.NextDouble()), Mathf.Sin(a) * r) + Center);
                int puffs = 3 + rng.Next(4);
                for (int p = 0; p < puffs; p++)
                {
                    float s = 2f + (float)rng.NextDouble() * 3f;
                    Kit.Deco(PrimitiveType.Sphere, c.transform, new Vector3(p * 1.8f - puffs, (float)rng.NextDouble(), (float)rng.NextDouble() * 1.5f),
                        new Vector3(s * 1.4f, s, s), new Color(1f, 1f, 1f), null, false, 0f);
                }
                var bob = c.AddComponent<Bob>();
                bob.amp = 0.4f;
                bob.speed = 0.2f + (float)rng.NextDouble() * 0.3f;
            }
        }

        protected void SpawnRing(Vector3 center, float radius, int count, float y)
        {
            for (int i = 0; i < count; i++)
            {
                float a = i * Mathf.PI * 2f / count + Mathf.PI * 0.25f;
                Spawns.Add(center + new Vector3(Mathf.Cos(a) * radius, y, Mathf.Sin(a) * radius));
            }
        }

        protected static Vector3 Closest(Vector3 from, params Vector3[] points)
        {
            Vector3 best = points[0];
            float bd = float.MaxValue;
            foreach (var p in points)
            {
                float d = (p - from).sqrMagnitude;
                if (d < bd) { bd = d; best = p; }
            }
            return best;
        }
    }

    public static class ArenaCatalog
    {
        public static readonly string[] BrawlTitles = { "Крыша", "Фабрика", "Колесо обозрения", "Льдины" };
        public static int BrawlCount => BrawlTitles.Length;

        public static Arena CreateBrawl(int index)
        {
            switch (((index % BrawlCount) + BrawlCount) % BrawlCount)
            {
                case 1: return new FactoryArena();
                case 2: return new FerrisArena();
                case 3: return new IceFloesArena();
                default: return new RooftopArena();
            }
        }

        public static Arena CreateClimb() => new TowerLevel();
    }
}
