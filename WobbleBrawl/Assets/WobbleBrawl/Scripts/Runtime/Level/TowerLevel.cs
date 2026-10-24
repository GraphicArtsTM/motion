using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Human-Fall-Flat style co-op climb above the clouds. Each section teaches one physical skill and
    /// can be solved more than one way:
    ///   0 start yard  → climb a 2 m ledge (raise arms, grab, pull up)
    ///   1 crate yard  → wall too tall to reach: drag the crate over and stand on it (or boost a friend)
    ///   2 gatehouse   → weigh down the pressure plate to open the gate (crate, friend... or climb the wall)
    ///   3 the gap     → ride the moving platform
    ///   4 log bridge  → balance on a spinning log, or go hand-over-hand along the monkey bars
    ///   5 launch pad  → bounce up to the summit and grab the edge
    /// </summary>
    public sealed class TowerLevel : Arena
    {
        public override string Title => "Башня";
        public override string Subtitle => "Кооперативное восхождение над облаками";

        public readonly List<Vector3> Checkpoints = new List<Vector3>();
        public readonly List<string> Hints = new List<string>();
        public Vector3 Goal;
        public System.Action<Brawler, int> onCheckpoint;
        public System.Action<Brawler> onGoal;

        SlidingDoor gate;
        PressurePlate plate;
        float gateTimer;

        static readonly Color Stone = new Color(0.78f, 0.74f, 0.68f);
        static readonly Color StoneDark = new Color(0.6f, 0.56f, 0.52f);
        static readonly Color Grass = new Color(0.45f, 0.75f, 0.4f);
        static readonly Color Wood = new Color(0.65f, 0.45f, 0.28f);

        protected override void BuildGeometry()
        {
            Radius = 4f;
            KillY = -10f;
            CameraPitch = 38f;
            CameraMinDist = 10f;
            CameraMaxDist = 22f;
            SkyColor = new Color(0.5f, 0.75f, 1f);
            FogColor = new Color(0.72f, 0.85f, 1f);
            FogDensity = 0.008f;
            AmbientSky = new Color(0.7f, 0.8f, 0.95f);
            AmbientEquator = new Color(0.6f, 0.65f, 0.7f);
            AmbientGround = new Color(0.4f, 0.4f, 0.38f);
            SunEuler = new Vector3(50f, -40f, 0f);

            // ---- section 0: start yard + 2 m ledge
            Island(new Vector3(0, 0, 0), new Vector3(9f, 1f, 8f));
            Block(new Vector3(0, 1f, 6.5f), new Vector3(9f, 2f, 5f));
            Checkpoint(new Vector3(0, 0.05f, -1f), "Подойди к уступу, подними руки вверх и держи ОБЕ руки (захват). Затем жми ПРЫЖОК, чтобы подтянуться.");
            Kit.Crate(Root, new Vector3(3f, 0.45f, -2f), Vector3.one * 0.8f, new Color(0.8f, 0.55f, 0.3f), 10f);

            // ---- section 1: crate yard, 4.6 m wall
            Checkpoint(new Vector3(0, 2.05f, 6f), "Стена слишком высокая. Притащи ящик к стене (схвати обеими руками) и залезь с него.");
            Block(new Vector3(0, 4.3f, 11.5f), new Vector3(9f, 4.6f, 5f), 2f);
            Kit.Crate(Root, new Vector3(-2.5f, 2.65f, 5.5f), Vector3.one * 1.2f, new Color(0.8f, 0.55f, 0.3f), 22f);
            Kit.Crate(Root, new Vector3(2.8f, 2.5f, 7f), Vector3.one * 0.9f, new Color(0.8f, 0.55f, 0.3f), 12f);

            // ---- section 2: gatehouse (top of the big block is y = 6.6)
            const float Top = 6.6f;
            Block(new Vector3(0, Top - 0.5f, 18.5f), new Vector3(10f, 1f, 9f), Top - 1f);
            Checkpoint(new Vector3(0, Top + 0.05f, 15f), "Ворота откроет только тяжёлая кнопка. Положи на неё ящик... или попроси друга постоять.");
            Kit.Box(Root, new Vector3(-3.25f, Top + 2f, 21f), new Vector3(3.5f, 4f, 0.6f), StoneDark);
            Kit.Box(Root, new Vector3(3.25f, Top + 2f, 21f), new Vector3(3.5f, 4f, 0.6f), StoneDark);
            Kit.Box(Root, new Vector3(0, Top + 3.5f, 21f), new Vector3(3f, 1f, 0.6f), StoneDark);
            gate = SlidingDoor.Create(Root, new Vector3(0, Top + 1.5f, 21f), new Vector3(0, 2.9f, 0), new Vector3(3f, 3f, 0.4f), Wood);
            plate = PressurePlate.Create(Root, new Vector3(-3f, Top, 16.5f), new Vector2(1.6f, 1.6f), 20f);
            plate.onChanged = pressed => { if (pressed) gateTimer = 4f; };
            Kit.Crate(Root, new Vector3(3f, Top + 0.55f, 16f), Vector3.one * 1f, new Color(0.55f, 0.55f, 0.6f), 28f);

            // ---- section 3: the gap, crossed by a moving platform
            Block(new Vector3(0, Top - 0.5f, 25f), new Vector3(8f, 1f, 4f), Top - 1f);
            Checkpoint(new Vector3(0, Top + 0.05f, 24.5f), "Запрыгивай на движущуюся платформу и не свались!");
            var mover = Piston.Create(Root, new Vector3(0, Top - 0.2f, 28.4f), new Vector3(0, Top - 0.2f, 34.6f), new Vector3(3f, 0.4f, 3f), new Color(0.3f, 0.6f, 0.95f), 0f);
            mover.waitTime = 1.5f; mover.extendTime = 3.6f; mover.holdTime = 1.5f; mover.retractTime = 3.6f;

            // ---- section 4: spinning log bridge or monkey bars
            Block(new Vector3(0, Top - 0.5f, 39f), new Vector3(8f, 1f, 6f), Top - 1f);
            Checkpoint(new Vector3(0, Top + 0.05f, 38.5f), "Пройди по крутящемуся бревну... или перебирайся по турнику руками (захват и прыжок).");
            var log = Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(-1.8f, Top - 0.35f, 46.5f), new Vector3(1.1f, 4.6f, 1.1f), Wood, Quaternion.Euler(90, 0, 0));
            log.name = "Log";
            var logCol = log.AddComponent<MeshCollider>();
            logCol.sharedMesh = MatFactory.Mesh(PrimitiveType.Cylinder);
            logCol.convex = true;
            Spinner.Attach(log, Vector3.up, 40f);
            for (int i = 0; i < 9; i++)
            {
                float z = 42.6f + i * 0.95f;
                Kit.Box(Root, new Vector3(2f, Top + 2.6f, z), new Vector3(1.6f, 0.12f, 0.12f), new Color(0.6f, 0.6f, 0.66f));
            }
            Kit.Box(Root, new Vector3(1.15f, Top + 1.3f, 42.4f), new Vector3(0.15f, 2.6f, 0.15f), new Color(0.6f, 0.6f, 0.66f));
            Kit.Box(Root, new Vector3(2.85f, Top + 1.3f, 42.4f), new Vector3(0.15f, 2.6f, 0.15f), new Color(0.6f, 0.6f, 0.66f));
            Kit.Box(Root, new Vector3(1.15f, Top + 1.3f, 50.6f), new Vector3(0.15f, 2.6f, 0.15f), new Color(0.6f, 0.6f, 0.66f));
            Kit.Box(Root, new Vector3(2.85f, Top + 1.3f, 50.6f), new Vector3(0.15f, 2.6f, 0.15f), new Color(0.6f, 0.6f, 0.66f));

            // ---- section 5: launch pad to the summit
            Block(new Vector3(0, Top - 0.5f, 54.5f), new Vector3(8f, 1f, 6f), Top - 1f);
            Checkpoint(new Vector3(0, Top + 0.05f, 52.5f), "Прыгай на батут и в полёте тянись к вершине — хватайся за край!");
            // tilted slightly forward so the launch carries you over the summit edge
            var pad = Kit.Box(Root, new Vector3(0, Top + 0.1f, 56f), new Vector3(2f, 0.2f, 2f), new Color(1f, 0.35f, 0.5f), Quaternion.Euler(12f, 0, 0));
            pad.AddComponent<BouncePad>().power = 14f;
            Kit.Deco(PrimitiveType.Cylinder, Root, new Vector3(0, Top + 0.05f, 56f), new Vector3(2.4f, 0.06f, 2.4f), new Color(0.2f, 0.2f, 0.25f));

            const float Summit = 12.5f;
            Block(new Vector3(0, Summit - 1.5f, 61.5f), new Vector3(7f, 3f, 6f), Summit - 3f);
            Goal = new Vector3(0, Summit, 62f);
            // flag
            Kit.Deco(PrimitiveType.Cylinder, Root, Goal + new Vector3(0, 1.5f, 1.5f), new Vector3(0.12f, 1.5f, 0.12f), Color.white);
            var flag = Kit.Deco(PrimitiveType.Cube, Root, Goal + new Vector3(0.6f, 2.6f, 1.5f), new Vector3(1.2f, 0.7f, 0.05f), new Color(1f, 0.3f, 0.3f), null, true, 0.3f, 0.5f);
            var fb = flag.AddComponent<Bob>();
            fb.amp = 0.05f; fb.speed = 4f;
            Kit.Deco(PrimitiveType.Cylinder, Root, Goal + Vector3.up * 0.02f, new Vector3(3f, 0.02f, 3f), new Color(1f, 0.85f, 0.2f), null, false, 0.5f, 1.5f);
            Zone.Create(Root, Goal + Vector3.up * 1f, new Vector3(5f, 3f, 5f), b => onGoal?.Invoke(b));

            Clouds(24, 20f, 70f, -12f, 6f, 13);
            Clouds(10, 30f, 70f, 16f, 26f, 17);
            // hint of a far-away world below
            Kit.Deco(PrimitiveType.Sphere, Root, new Vector3(0, -60f, 30f), new Vector3(160f, 40f, 160f), new Color(0.4f, 0.65f, 0.45f), null, false);

            Center = new Vector3(0, 0, 0);
            for (int i = 0; i < 4; i++) Spawns.Add(new Vector3(-1.5f + i, 0.05f, -2f));
        }

        void Island(Vector3 top, Vector3 size)
        {
            Kit.Box(Root, top + Vector3.down * size.y * 0.5f, size, Grass);
            Kit.Deco(PrimitiveType.Cube, Root, top + Vector3.down * (size.y + 1.5f), new Vector3(size.x * 0.92f, 3f, size.z * 0.92f), new Color(0.55f, 0.4f, 0.3f));
            Kit.Deco(PrimitiveType.Sphere, Root, top + Vector3.down * (size.y + 4f), new Vector3(size.x * 0.8f, 5f, size.z * 0.8f), new Color(0.5f, 0.36f, 0.27f));
        }

        /// <summary>Stone block with a grass cap. <paramref name="depthBelow"/> extends the block down visually.</summary>
        void Block(Vector3 center, Vector3 size, float depthBelow = 0f)
        {
            Kit.Box(Root, center, size, Stone);
            Kit.Deco(PrimitiveType.Cube, Root, center + Vector3.up * (size.y * 0.5f + 0.01f), new Vector3(size.x + 0.04f, 0.04f, size.z + 0.04f), Grass, null, false);
            if (depthBelow > 0f)
                Kit.Deco(PrimitiveType.Cube, Root, center + Vector3.down * (size.y * 0.5f + depthBelow * 0.5f), new Vector3(size.x * 0.9f, depthBelow, size.z * 0.9f), StoneDark);
        }

        void Checkpoint(Vector3 pos, string hint)
        {
            int index = Checkpoints.Count;
            Checkpoints.Add(pos);
            Hints.Add(hint);
            Kit.Deco(PrimitiveType.Cylinder, Root, pos + Vector3.down * 0.03f, new Vector3(1.4f, 0.02f, 1.4f), new Color(0.4f, 0.8f, 1f), null, false, 0.5f, 0.8f);
            Zone.Create(Root, pos + Vector3.up * 1f, new Vector3(11f, 3f, 3f), b => onCheckpoint?.Invoke(b, index));
        }

        public override void Tick(float dt)
        {
            if (gate == null) return;
            if (gateTimer > 0f) gateTimer -= dt;
            gate.open = (plate != null && plate.Pressed) || gateTimer > 0f;
        }

        public override Vector3 ThrowPoint(Vector3 from) => from + Vector3.right * 6f;
    }
}
