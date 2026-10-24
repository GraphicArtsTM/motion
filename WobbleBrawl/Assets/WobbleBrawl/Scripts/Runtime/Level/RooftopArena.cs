using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Sunset skyscraper roof with a wrecking ball swinging from a crane. Classic ring-out arena.</summary>
    public sealed class RooftopArena : Arena
    {
        public override string Title => "Крыша";
        public override string Subtitle => "Небоскрёб на закате. Берегись крана!";

        protected override void BuildGeometry()
        {
            Radius = 8f;
            KillY = -5f;
            CameraPitch = 52f;
            SkyColor = new Color(0.98f, 0.62f, 0.45f);
            FogColor = new Color(0.95f, 0.6f, 0.5f);
            FogDensity = 0.014f;
            AmbientSky = new Color(0.95f, 0.65f, 0.6f);
            AmbientEquator = new Color(0.65f, 0.45f, 0.5f);
            AmbientGround = new Color(0.25f, 0.2f, 0.3f);
            SunColor = new Color(1f, 0.78f, 0.55f);
            SunEuler = new Vector3(28f, -60f, 0f);
            SunIntensity = 1.25f;

            var concrete = new Color(0.58f, 0.57f, 0.6f);
            var trim = new Color(0.42f, 0.4f, 0.46f);

            // roof slab and the tower below it
            Kit.Box(Root, new Vector3(0, -0.5f, 0), new Vector3(16f, 1f, 16f), concrete);
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(0, -16f, 0), new Vector3(15.6f, 30f, 15.6f), new Color(0.32f, 0.3f, 0.4f));
            for (int floor = 0; floor < 9; floor++)
            {
                float y = -2.5f - floor * 3f;
                for (int side = 0; side < 4; side++)
                {
                    var rot = Quaternion.Euler(0, side * 90f, 0);
                    var pos = rot * new Vector3(0, y, 7.82f);
                    Kit.Deco(PrimitiveType.Cube, Root, pos, rot * new Vector3(14f, 1.2f, 0.05f), new Color(1f, 0.85f, 0.55f), rot, false, 0.9f, 0.6f);
                }
            }

            // parapet on the back edge, broken trim on the left
            Kit.Box(Root, new Vector3(0, 0.3f, 7.8f), new Vector3(16f, 0.6f, 0.4f), trim);
            Kit.Box(Root, new Vector3(-7.8f, 0.2f, 3.5f), new Vector3(0.4f, 0.4f, 9f), trim);

            // rooftop clutter: AC units, vents, a water tower to climb
            Kit.Box(Root, new Vector3(-4.5f, 0.55f, 4.2f), new Vector3(2.2f, 1.1f, 1.4f), new Color(0.75f, 0.76f, 0.78f));
            Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(-4.5f, 1.12f, 4.2f), new Vector3(0.9f, 0.03f, 0.9f), new Color(0.2f, 0.2f, 0.22f));
            var fan = Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-4.5f, 1.16f, 4.2f), new Vector3(0.85f, 0.02f, 0.12f), new Color(0.5f, 0.5f, 0.52f), null, false);
            fan.AddComponent<RollerSpin>().speed = 400f;
            Kit.Box(Root, new Vector3(5f, 0.6f, -3.8f), new Vector3(1.6f, 1.2f, 1.6f), new Color(0.7f, 0.72f, 0.75f));
            Kit.Box(Root, new Vector3(2f, 0.35f, 5.5f), new Vector3(0.8f, 0.7f, 0.8f), new Color(0.5f, 0.5f, 0.55f));

            var wood = new Color(0.55f, 0.36f, 0.22f);
            for (int i = 0; i < 4; i++)
            {
                float x = 5.2f + (i % 2) * 1.6f, z = 4.6f + (i / 2) * 1.6f;
                Kit.Box(Root, new Vector3(x, 1.6f, z), new Vector3(0.18f, 3.2f, 0.18f), new Color(0.3f, 0.3f, 0.32f));
            }
            Kit.Box(Root, new Vector3(6f, 3.25f, 5.4f), new Vector3(2.2f, 0.15f, 2.2f), wood);
            Kit.Cylinder(Root, new Vector3(6f, 4.3f, 5.4f), 1.05f, 2f, wood);
            Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(6f, 5.35f, 5.4f), new Vector3(2.15f, 0.5f, 2.15f), new Color(0.35f, 0.33f, 0.35f));

            // billboard frame — climbable posts
            Kit.Box(Root, new Vector3(-3f, 2.5f, 7.3f), new Vector3(0.25f, 5f, 0.25f), new Color(0.25f, 0.25f, 0.28f));
            Kit.Box(Root, new Vector3(3f, 2.5f, 7.3f), new Vector3(0.25f, 5f, 0.25f), new Color(0.25f, 0.25f, 0.28f));
            Kit.Box(Root, new Vector3(0, 4.2f, 7.45f), new Vector3(8f, 2.6f, 0.2f), new Color(0.15f, 0.55f, 0.95f));
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(0, 4.2f, 7.33f), new Vector3(7.4f, 0.5f, 0.05f), new Color(1f, 0.85f, 0.2f), null, false, 0.4f, 1.2f);
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-2.2f, 4.9f, 7.33f), new Vector3(2.4f, 0.35f, 0.05f), Color.white, null, false, 0.4f, 0.8f);
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(2.2f, 3.5f, 7.33f), new Vector3(2.4f, 0.35f, 0.05f), Color.white, null, false, 0.4f, 0.8f);

            // crane with a wrecking ball sweeping across the roof
            var steel = new Color(1f, 0.72f, 0.1f);
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-11f, -2f, -2f), new Vector3(0.9f, 28f, 0.9f), steel);
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-5.5f, 12.2f, -2f), new Vector3(12f, 0.6f, 0.6f), steel);
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-11f, 12.6f, -2f), new Vector3(2.5f, 1.4f, 1.4f), new Color(0.25f, 0.25f, 0.3f));
            Pendulum.Create(Root, new Vector3(0f, 11.8f, -2f), 10.3f, 0.7f, 260f, Vector3.right, new Color(0.15f, 0.15f, 0.17f));

            // physics props
            Kit.Crate(Root, new Vector3(-2.5f, 0.45f, -4f), Vector3.one * 0.9f, new Color(0.75f, 0.52f, 0.3f), 14f);
            Kit.Crate(Root, new Vector3(-2.4f, 1.35f, -4.1f), Vector3.one * 0.8f, new Color(0.75f, 0.52f, 0.3f), 12f, Quaternion.Euler(0, 20, 0));
            Kit.Crate(Root, new Vector3(3.5f, 0.45f, 2.5f), Vector3.one * 0.9f, new Color(0.75f, 0.52f, 0.3f), 14f);
            Kit.Barrel(Root, new Vector3(-6.2f, 0.5f, -5.5f), 0.4f, 1f, new Color(0.2f, 0.55f, 0.35f), 18f);
            Kit.Ball(Root, new Vector3(1f, 0.5f, -1f), 0.45f, new Color(1f, 0.3f, 0.35f), 4f);

            // the city far below
            var rng = new System.Random(7);
            for (int i = 0; i < 70; i++)
            {
                float a = (float)rng.NextDouble() * Mathf.PI * 2f;
                float r = 15f + (float)rng.NextDouble() * 45f;
                float h = 15f + (float)rng.NextDouble() * 35f;
                float top = -8f - (float)rng.NextDouble() * 22f + (r > 35f ? 12f : 0f);
                float w = 4f + (float)rng.NextDouble() * 5f;
                var col = Color.Lerp(new Color(0.38f, 0.32f, 0.5f), new Color(0.6f, 0.45f, 0.55f), (float)rng.NextDouble());
                var pos = new Vector3(Mathf.Cos(a) * r, top - h * 0.5f, Mathf.Sin(a) * r);
                Kit.Deco(PrimitiveType.Cube, Root, pos, new Vector3(w, h, w), col, null, false, 0.1f);
                if (rng.NextDouble() < 0.6)
                    Kit.Deco(PrimitiveType.Cube, Root, pos + Vector3.up * (h * 0.5f - 1.5f), new Vector3(w + 0.05f, 0.6f, w + 0.05f), new Color(1f, 0.82f, 0.5f), null, false, 0.5f, 0.8f);
            }
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(0, -40f, 0), new Vector3(200f, 1f, 200f), new Color(0.25f, 0.22f, 0.3f), null, false);
            Clouds(10, 35f, 70f, 6f, 20f, 3);

            SpawnRing(Vector3.zero, 4.2f, 8, 0.05f);
            HillSpots.Add(new Vector3(0, 0, 0));
            HillSpots.Add(new Vector3(-4f, 0, -4.5f));
            HillSpots.Add(new Vector3(4.5f, 0, 1f));
            HillSpots.Add(new Vector3(6f, 3.4f, 5.4f)); // on top of the water tower!
        }
    }
}
