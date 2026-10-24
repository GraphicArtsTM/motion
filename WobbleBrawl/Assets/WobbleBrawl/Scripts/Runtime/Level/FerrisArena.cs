using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Seaside boardwalk with a working Ferris wheel. Ride the gondolas, fight at the top, splash into the sea.</summary>
    public sealed class FerrisArena : Arena
    {
        public override string Title => "Колесо обозрения";
        public override string Subtitle => "Набережная. Кабинки едут, вода холодная.";

        const float HubY = 11.05f, WheelR = 7.6f, WheelZ = 0.25f, DeckTop = 0.6f, Speed = 9f;
        Transform wheelDeco;

        protected override void BuildGeometry()
        {
            Center = new Vector3(0, 0, -3f);
            Radius = 7.5f;
            KillY = -0.7f;
            CameraPitch = 30f;
            CameraMinDist = 13f;
            CameraMaxDist = 34f;
            SkyColor = new Color(0.55f, 0.8f, 1f);
            FogColor = new Color(0.7f, 0.86f, 1f);
            FogDensity = 0.01f;
            AmbientSky = new Color(0.65f, 0.75f, 0.9f);
            AmbientEquator = new Color(0.55f, 0.6f, 0.65f);
            AmbientGround = new Color(0.3f, 0.35f, 0.4f);
            SunEuler = new Vector3(45f, 30f, 0f);

            var plank = new Color(0.72f, 0.52f, 0.33f);
            var plankDark = new Color(0.55f, 0.38f, 0.24f);

            Water(-0.25f, 220f, new Color(0.15f, 0.5f, 0.75f));

            // decks either side of the channel the wheel dips into
            BuildDeck(new Vector3(0, DeckTop - 0.5f, -5.1f), new Vector3(17f, 1f, 6f), plank, plankDark);
            BuildDeck(new Vector3(0, DeckTop - 0.5f, 4.6f), new Vector3(17f, 1f, 4.2f), plank, plankDark);
            // pier legs
            for (int x = -8; x <= 8; x += 4)
            {
                Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(x, -1.5f, -7.9f), new Vector3(0.35f, 1.5f, 0.35f), plankDark);
                Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(x, -1.5f, 6.5f), new Vector3(0.35f, 1.5f, 0.35f), plankDark);
            }

            // wheel structure (decorative, rotates in sync with the gondolas)
            var white = new Color(0.95f, 0.95f, 0.97f);
            var hub = new Vector3(0, HubY, WheelZ);
            wheelDeco = Kit.Group(Root, "WheelRim", hub).transform;
            for (int i = 0; i < 32; i++)
            {
                float a0 = i * Mathf.PI * 2f / 32f, a1 = (i + 1) * Mathf.PI * 2f / 32f;
                var p0 = new Vector3(Mathf.Cos(a0), Mathf.Sin(a0), 0) * WheelR;
                var p1 = new Vector3(Mathf.Cos(a1), Mathf.Sin(a1), 0) * WheelR;
                Strut(wheelDeco, p0 + Vector3.forward * -0.9f, p1 + Vector3.forward * -0.9f, 0.12f, white);
                Strut(wheelDeco, p0 + Vector3.forward * 0.9f, p1 + Vector3.forward * 0.9f, 0.12f, white);
                if (i % 2 == 0)
                    Kit.Deco(PrimitiveType.Sphere, wheelDeco, p0 * 1.01f, Vector3.one * 0.22f,
                        i % 4 == 0 ? new Color(1f, 0.4f, 0.4f) : new Color(1f, 0.9f, 0.3f), null, false, 0.5f, 2f);
            }
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI / 4f;
                var p = new Vector3(Mathf.Cos(a), Mathf.Sin(a), 0) * WheelR;
                Strut(wheelDeco, Vector3.forward * -0.9f, p + Vector3.forward * -0.9f, 0.1f, white);
                Strut(wheelDeco, Vector3.forward * 0.9f, p + Vector3.forward * 0.9f, 0.1f, white);
            }
            Kit.Deco(PrimitiveType.Cylinder, wheelDeco, Vector3.zero, new Vector3(1.2f, 1.1f, 1.2f), new Color(0.9f, 0.3f, 0.35f), Quaternion.Euler(90, 0, 0));
            // A-frame legs standing in the channel
            foreach (float z in new[] { WheelZ - 1.4f, WheelZ + 1.4f })
            {
                Strut(Root, new Vector3(-4.2f, -0.5f, z), new Vector3(0, HubY, z), 0.25f, new Color(0.4f, 0.42f, 0.48f));
                Strut(Root, new Vector3(4.2f, -0.5f, z), new Vector3(0, HubY, z), 0.25f, new Color(0.4f, 0.42f, 0.48f));
            }

            // gondolas
            Color[] colors =
            {
                new Color(0.95f, 0.35f, 0.35f), new Color(0.35f, 0.65f, 0.95f), new Color(0.98f, 0.82f, 0.25f), new Color(0.45f, 0.85f, 0.45f),
                new Color(0.75f, 0.45f, 0.95f), new Color(1f, 0.55f, 0.2f), new Color(0.3f, 0.85f, 0.85f), new Color(1f, 0.5f, 0.75f),
            };
            for (int i = 0; i < 8; i++)
                BuildGondola(hub, i * 45f, colors[i]);

            // boardwalk dressing
            for (int x = -8; x <= 8; x += 4)
                Kit.Lamp(Root, new Vector3(x, DeckTop, -7.6f), new Color(1f, 0.85f, 0.5f), 2.6f);
            Kit.Box(Root, new Vector3(-6.5f, DeckTop + 1.1f, 5.6f), new Vector3(2f, 2.2f, 1.6f), new Color(0.95f, 0.4f, 0.45f));
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-6.5f, DeckTop + 2.35f, 5.6f), new Vector3(2.4f, 0.3f, 2f), Color.white);
            for (int b = 0; b < 5; b++)
            {
                var balloon = Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(-6.5f + (b - 2) * 0.4f, DeckTop + 3.6f + (b % 2) * 0.3f, 5.6f), new Vector3(0.45f, 0.55f, 0.45f),
                    colors[b], null, false, 0.6f);
                var bob = balloon.AddComponent<Bob>();
                bob.amp = 0.1f; bob.speed = 1.5f + b * 0.2f;
            }
            Kit.Crate(Root, new Vector3(5f, DeckTop + 0.45f, -6.2f), Vector3.one * 0.9f, new Color(0.75f, 0.52f, 0.3f), 14f);
            Kit.Barrel(Root, new Vector3(6.3f, DeckTop + 0.5f, 4.2f), 0.4f, 1f, new Color(0.2f, 0.5f, 0.85f), 16f);
            Kit.Ball(Root, new Vector3(-2f, DeckTop + 0.5f, -4.5f), 0.5f, new Color(1f, 0.85f, 0.2f), 3f);

            // horizon: lighthouse and distant islands
            Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(28f, 5f, 40f), new Vector3(2.5f, 7f, 2.5f), Color.white);
            Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(28f, 5f, 40f), new Vector3(2.55f, 1f, 2.55f), new Color(0.9f, 0.2f, 0.2f));
            Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(28f, 12.5f, 40f), Vector3.one * 2f, new Color(1f, 0.95f, 0.6f), null, false, 0.5f, 2f);
            Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(-40f, -3f, 55f), new Vector3(40f, 12f, 20f), new Color(0.4f, 0.65f, 0.4f), null, false);
            Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(45f, -4f, 70f), new Vector3(50f, 14f, 25f), new Color(0.45f, 0.62f, 0.45f), null, false);
            Clouds(12, 40f, 80f, 12f, 25f, 21);

            for (int i = 0; i < 6; i++) Spawns.Add(new Vector3(-6f + i * 2.4f, DeckTop + 0.05f, i % 2 == 0 ? -4.2f : -6.2f));
            Spawns.Add(new Vector3(-3f, DeckTop + 0.05f, 4.6f));
            Spawns.Add(new Vector3(3f, DeckTop + 0.05f, 4.6f));
            HillSpots.Add(new Vector3(0, DeckTop, -5f));
            HillSpots.Add(new Vector3(-5f, DeckTop, 4.5f));
            HillSpots.Add(new Vector3(5f, DeckTop, -5.5f));
            HillSpots.Add(new Vector3(5f, DeckTop, 4.5f));
        }

        void BuildDeck(Vector3 center, Vector3 size, Color a, Color b)
        {
            Kit.Box(Root, center, size, a);
            int planks = Mathf.RoundToInt(size.x / 0.8f);
            for (int i = 0; i < planks; i += 2)
                Kit.Deco(PrimitiveType.Cube, Root, center + new Vector3(-size.x * 0.5f + (i + 0.5f) * 0.8f, size.y * 0.5f + 0.003f, 0),
                    new Vector3(0.78f, 0.01f, size.z), b, null, false);
        }

        void BuildGondola(Vector3 hub, float startDeg, Color color)
        {
            var g = new GameObject("Gondola");
            g.transform.SetParent(Root, false);
            var floor = Kit.Box(g.transform, Vector3.zero, new Vector3(2.4f, 0.25f, 2.2f), color);
            floor.name = "Floor";
            Kit.Box(g.transform, new Vector3(-1.15f, 0.35f, 0), new Vector3(0.1f, 0.5f, 2.2f), Palette.Darken(color, 0.8f));
            Kit.Box(g.transform, new Vector3(1.15f, 0.35f, 0), new Vector3(0.1f, 0.5f, 2.2f), Palette.Darken(color, 0.8f));
            Kit.Box(g.transform, new Vector3(0, 2.3f, 0), new Vector3(2.6f, 0.15f, 2.4f), Palette.Darken(color, 0.7f));
            Kit.Deco(PrimitiveType.Cube, g.transform, new Vector3(-1.15f, 1.3f, 0.9f), new Vector3(0.08f, 2f, 0.08f), Color.white);
            Kit.Deco(PrimitiveType.Cube, g.transform, new Vector3(1.15f, 1.3f, 0.9f), new Vector3(0.08f, 2f, 0.08f), Color.white);
            Kit.Deco(PrimitiveType.Cube, g.transform, new Vector3(0, 2.75f, 0), new Vector3(0.12f, 0.9f, 0.12f), Color.white);
            OrbitMover.Attach(g, hub, WheelR, Speed, startDeg, new Vector3(0, -2.9f, 0));
        }

        static void Strut(Transform parent, Vector3 a, Vector3 b, float thickness, Color c)
        {
            Vector3 mid = (a + b) * 0.5f;
            Vector3 d = b - a;
            Kit.Deco(PrimitiveType.Cube, parent, mid, new Vector3(thickness, thickness, d.magnitude), c,
                Quaternion.LookRotation(d.normalized, Mathf.Abs(d.normalized.y) > 0.99f ? Vector3.forward : Vector3.up), true);
        }

        public override void Tick(float dt)
        {
            if (wheelDeco != null) wheelDeco.Rotate(0f, 0f, Speed * dt, Space.Self);
        }

        public override Vector3 ThrowPoint(Vector3 from)
        {
            float x = from.x;
            return from.z < WheelZ
                ? Closest(from, new Vector3(x, 0, -8.8f), new Vector3(x, 0, WheelZ), new Vector3(-9f, 0, from.z), new Vector3(9f, 0, from.z))
                : Closest(from, new Vector3(x, 0, 7.4f), new Vector3(x, 0, WheelZ), new Vector3(-9f, 0, from.z), new Vector3(9f, 0, from.z));
        }
    }
}
