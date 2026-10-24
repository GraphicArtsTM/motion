using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Factory floor: conveyors drag you towards the grinders, wall pistons punch you off the front edge.</summary>
    public sealed class FactoryArena : Arena
    {
        public override string Title => "Фабрика";
        public override string Subtitle => "Конвейеры несут к дробилкам. Поршни не дремлют.";

        protected override void BuildGeometry()
        {
            Radius = 7f;
            KillY = -3f;
            CameraPitch = 50f;
            CameraMinDist = 10f;
            SkyColor = new Color(0.12f, 0.12f, 0.16f);
            FogColor = new Color(0.14f, 0.13f, 0.17f);
            FogDensity = 0.03f;
            AmbientSky = new Color(0.55f, 0.5f, 0.45f);
            AmbientEquator = new Color(0.35f, 0.32f, 0.3f);
            AmbientGround = new Color(0.15f, 0.14f, 0.14f);
            SunColor = new Color(1f, 0.9f, 0.75f);
            SunIntensity = 0.9f;
            SunEuler = new Vector3(65f, -20f, 0f);

            var metal = new Color(0.45f, 0.47f, 0.5f);
            var dark = new Color(0.2f, 0.2f, 0.23f);
            var hazard = new Color(1f, 0.78f, 0.1f);

            // main floor with hazard stripes along the open front edge
            Kit.Box(Root, new Vector3(0, -0.5f, 0), new Vector3(9f, 1f, 10f), metal);
            for (int i = 0; i < 9; i++)
                Kit.Deco(PrimitiveType.Cube, Root, new Vector3(-4f + i, 0.005f, -4.8f), new Vector3(0.5f, 0.02f, 0.35f), i % 2 == 0 ? hazard : dark, Quaternion.Euler(0, 30, 0), false);

            // conveyors to the grinders
            Conveyor.Create(Root, new Vector3(-7.5f, -0.25f, 0), new Vector3(6f, 0.5f, 4f), Vector3.left, 2.2f);
            Conveyor.Create(Root, new Vector3(7.5f, -0.25f, 0), new Vector3(6f, 0.5f, 4f), Vector3.right, 2.2f);
            for (int s = -1; s <= 1; s += 2)
            {
                // grinder rollers (decorative, spinning) and the pit
                for (int k = 0; k < 2; k++)
                {
                    var roller = Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(s * (11f + k * 0.7f), -0.9f + k * 0.15f, 0), new Vector3(0.7f, 2f, 0.7f), new Color(0.6f, 0.6f, 0.62f), Quaternion.Euler(90, 0, 0));
                    for (int t = 0; t < 6; t++)
                        Kit.Deco(PrimitiveType.Cube, roller.transform, Quaternion.Euler(0, t * 60f, 0) * new Vector3(0.5f, 0, 0), new Vector3(0.25f, 1f, 0.12f), dark, Quaternion.Euler(0, t * 60f, 0), false);
                    roller.AddComponent<RollerSpin>().speed = (k == 0 ? 1f : -1f) * 360f * s;
                }
                Kit.Deco(PrimitiveType.Cube, Root, new Vector3(s * 11.3f, -3f, 0), new Vector3(2.4f, 4f, 5f), new Color(0.08f, 0.08f, 0.1f), null, false);
                // catwalks beside the belts
                Kit.Box(Root, new Vector3(s * 7.3f, -0.1f, 4.2f), new Vector3(5.6f, 0.2f, 1.1f), dark);
                Kit.Box(Root, new Vector3(s * 7.3f, -0.1f, -4.2f), new Vector3(5.6f, 0.2f, 1.1f), dark);
                Kit.Box(Root, new Vector3(s * 10f, 0.5f, 4.7f), new Vector3(0.1f, 1f, 0.1f), hazard);
                Kit.Box(Root, new Vector3(s * 10f, 0.5f, -4.7f), new Vector3(0.1f, 1f, 0.1f), hazard);
            }

            // back wall with two pistons
            Kit.Box(Root, new Vector3(0, 3f, 6f), new Vector3(26f, 8f, 1f), new Color(0.3f, 0.3f, 0.34f));
            for (int i = 0; i < 2; i++)
            {
                float x = i == 0 ? -2.4f : 2.4f;
                var piston = Piston.Create(Root, new Vector3(x, 0.8f, 5.2f), new Vector3(x, 0.8f, 1.2f), new Vector3(2.2f, 1.5f, 1.5f), new Color(0.75f, 0.2f, 0.15f), i * 2.6f);
                piston.waitTime = 3.4f;
                var lamp = Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(x, 2.2f, 5.45f), Vector3.one * 0.4f, new Color(0.3f, 0.08f, 0.05f));
                piston.warningLight = lamp.GetComponent<Renderer>();
                Kit.Deco(PrimitiveType.Cube, Root, new Vector3(x, 0.8f, 5.6f), new Vector3(2.6f, 1.9f, 0.3f), dark);
            }

            // overhead pipes and lamps
            for (int i = 0; i < 3; i++)
                Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(0, 6.5f + i * 0.6f, 4.5f - i * 1.4f), new Vector3(0.35f, 14f, 0.35f), i == 1 ? new Color(0.7f, 0.25f, 0.2f) : new Color(0.5f, 0.55f, 0.6f), Quaternion.Euler(0, 0, 90));
            Kit.Lamp(Root, new Vector3(-4f, 0f, 5.2f), new Color(1f, 0.8f, 0.5f), 4.5f, true);
            Kit.Lamp(Root, new Vector3(4f, 0f, 5.2f), new Color(1f, 0.8f, 0.5f), 4.5f, true);

            // stuff riding the belts
            Kit.Crate(Root, new Vector3(-6f, 0.45f, 0.8f), Vector3.one * 0.8f, new Color(0.7f, 0.5f, 0.3f), 12f);
            Kit.Crate(Root, new Vector3(6.5f, 0.45f, -0.8f), Vector3.one * 0.8f, new Color(0.7f, 0.5f, 0.3f), 12f);
            Kit.Barrel(Root, new Vector3(-2.5f, 0.5f, -2.5f), 0.4f, 1f, new Color(0.15f, 0.4f, 0.75f), 16f);
            Kit.Barrel(Root, new Vector3(3f, 0.5f, 2.8f), 0.4f, 1f, new Color(0.8f, 0.3f, 0.15f), 16f);

            // distant machinery silhouettes
            var rng = new System.Random(11);
            for (int i = 0; i < 18; i++)
            {
                float x = -24f + i * 2.8f;
                float h = 4f + (float)rng.NextDouble() * 10f;
                Kit.Deco(PrimitiveType.Cube, Root, new Vector3(x, h * 0.5f - 6f, 14f + (float)rng.NextDouble() * 6f), new Vector3(2.4f, h, 2.4f), new Color(0.18f, 0.18f, 0.22f), null, false);
            }
            Kit.Deco(PrimitiveType.Cube, Root, new Vector3(0, -8f, 0), new Vector3(80f, 1f, 80f), new Color(0.08f, 0.08f, 0.1f), null, false);

            Spawns.Add(new Vector3(-2.5f, 0.05f, -2f));
            Spawns.Add(new Vector3(2.5f, 0.05f, 2f));
            Spawns.Add(new Vector3(-2.5f, 0.05f, 2f));
            Spawns.Add(new Vector3(2.5f, 0.05f, -2f));
            Spawns.Add(new Vector3(0f, 0.05f, -3.5f));
            Spawns.Add(new Vector3(0f, 0.05f, 3f));
            Spawns.Add(new Vector3(-3.6f, 0.05f, 0f));
            Spawns.Add(new Vector3(3.6f, 0.05f, 0f));
            HillSpots.Add(new Vector3(0, 0, 0));
            HillSpots.Add(new Vector3(-7f, 0, 0));
            HillSpots.Add(new Vector3(0, 0, 3f));
            HillSpots.Add(new Vector3(7f, 0, 0));
        }

        public override Vector3 ThrowPoint(Vector3 from)
        {
            return Closest(from, new Vector3(-11.5f, 0, 0), new Vector3(11.5f, 0, 0), new Vector3(from.x, 0, -6.5f));
        }
    }

    /// <summary>Spins a decorative transform around its local up axis.</summary>
    public sealed class RollerSpin : MonoBehaviour
    {
        public float speed = 180f;
        void Update() => transform.Rotate(0f, speed * Time.deltaTime, 0f, Space.Self);
    }
}
