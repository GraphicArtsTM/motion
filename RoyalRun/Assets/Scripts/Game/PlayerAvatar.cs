using UnityEngine;

// One player's hero in an endless lane runner.
//   Left / right (swipe, A/D, arrows, phone): change lane - or turn at a corner;
//   Up (swipe up, W, Space): jump over low fences;
//   Down (swipe down, S): slide under beams (in the air - drop down quickly).
// Running into things: see RegisterHit (what happens depends on the game mode).
[RequireComponent(typeof(Rigidbody))]
public class PlayerAvatar : MonoBehaviour
{
    public static readonly float[] Lanes = { -2.5f, 0f, 2.5f };

    const float LaneSpeed = 13f;            // metres per second sideways
    const float CollisionCooldown = 1.2f;   // after a hit the hero blinks and cannot be hit again
    const float StunTime = 0.35f;           // controls do not respond right after a hit
    const float JumpVelocity = 8.6f;        // apex ~1.5 m: enough to clear a fence, not a wall
    const float JumpGravity = -26f;
    const float FastFallVelocity = -14f;
    const float SlideTime = 0.75f;
    const float InputBuffer = 0.18f;        // a press slightly too early still counts
    const float HeroRadius = 0.3f;          // the size used to check touching obstacles
    const float HitSlowAmount = -2f;

    PlayerWorld world;
    PhonePlayer input;
    Rigidbody body;
    Animator animator;
    CharacterRig rig;
    float laneSpeed;
    float originX;
    int lane = 1;
    float cooldownTimer;
    float stunTimer;
    float knockback;
    float lateral;

    float height;                // current jump height
    float verticalVelocity;
    bool grounded = true;
    float jumpBuffer;
    float slideTimer;
    float slideBuffer;

    Transform shieldFx, magnetFx, blobShadow;
    Renderer[] modelRenderers;
    bool blinkVisible = true;

    static readonly int HitTrigger = Animator.StringToHash("Hit");

    public float Height { get { return height; } }
    public bool Sliding { get { return slideTimer > 0f; } }
    public int Lane { get { return lane; } }

    public static PlayerAvatar Create(PlayerWorld world, PhonePlayer input, GameObject modelPrefab,
                                      CharacterDef character, Vector3 position)
    {
        GameObject go = new GameObject("Player " + (input.slot + 1));
        go.tag = "Player";                      // the tag is needed by coins, apples and checkpoints
        go.transform.SetParent(world.transform, false);
        go.transform.position = position;
        go.transform.localScale = Vector3.one * 1.2f;

        CapsuleCollider capsule = go.AddComponent<CapsuleCollider>();
        capsule.radius = 0.35f;
        capsule.height = 2f;
        capsule.direction = 1;
        capsule.center = new Vector3(0f, 0.83f, 0f);

        Rigidbody rb = go.AddComponent<Rigidbody>();
        rb.isKinematic = true;
        rb.useGravity = false;
        rb.interpolation = RigidbodyInterpolation.Interpolate;

        // a trigger "sensor" (a second way of noticing obstacles, see HitSensor)
        GameObject sensorGo = new GameObject("Hit Sensor");
        sensorGo.transform.SetParent(go.transform, false);
        CapsuleCollider sensorCol = sensorGo.AddComponent<CapsuleCollider>();
        sensorCol.isTrigger = true;
        sensorCol.radius = 0.3f;
        sensorCol.height = 1.5f;
        sensorCol.direction = 1;
        sensorCol.center = new Vector3(0f, 0.95f, 0f);
        HitSensor sensor = sensorGo.AddComponent<HitSensor>();

        GameObject model = Instantiate(modelPrefab, go.transform);
        model.transform.localPosition = Vector3.zero;
        model.transform.localRotation = Quaternion.identity;
        ModelTint.Apply(model, character.tint);

        PlayerAvatar avatar = go.AddComponent<PlayerAvatar>();
        avatar.world = world;
        avatar.input = input;
        avatar.body = rb;
        avatar.animator = model.GetComponentInChildren<Animator>();
        avatar.rig = model.GetComponentInChildren<CharacterRig>();
        avatar.modelRenderers = model.GetComponentsInChildren<Renderer>();
        avatar.cooldownTimer = CollisionCooldown;
        avatar.originX = world.OriginX;
        avatar.laneSpeed = LaneSpeed * character.moveMult;
        avatar.BuildEffects();
        if (avatar.rig != null) avatar.rig.Footstep += avatar.OnFootstep;
        sensor.owner = avatar;
        input.jumpQueued = false;
        input.actions.Clear();
        return avatar;
    }

    // Glowing orbs around the hero (shield), a gold ring at the feet (magnet), a soft shadow.
    void BuildEffects()
    {
        shieldFx = new GameObject("Shield FX").transform;
        shieldFx.SetParent(transform, false);
        shieldFx.localPosition = new Vector3(0f, 0.95f, 0f);
        for (int i = 0; i < 6; i++)
        {
            float a = i * Mathf.PI / 3f;
            MatLib.Prim(PrimitiveType.Sphere, "Orb", shieldFx, new Vector3(Mathf.Sin(a) * 0.75f, (i % 2) * 0.5f - 0.25f, Mathf.Cos(a) * 0.75f),
                        Vector3.one * 0.16f, new Color(0.35f, 0.9f, 1f), false, default(Vector3), 0.9f, 1.6f, Surface.Plain);
        }
        shieldFx.gameObject.SetActive(false);

        magnetFx = new GameObject("Magnet FX").transform;
        magnetFx.SetParent(transform, false);
        magnetFx.localPosition = new Vector3(0f, 0.05f, 0f);
        for (int i = 0; i < 10; i++)
        {
            float a = i * Mathf.PI / 5f;
            MatLib.Prim(PrimitiveType.Cube, "Spark", magnetFx, new Vector3(Mathf.Sin(a) * 0.9f, 0f, Mathf.Cos(a) * 0.9f),
                        new Vector3(0.12f, 0.04f, 0.2f), new Color(1f, 0.82f, 0.3f), false, new Vector3(0f, a * Mathf.Rad2Deg, 0f), 0.8f, 1.2f, Surface.Plain);
        }
        magnetFx.gameObject.SetActive(false);

        GameObject blob = MatLib.Prim(PrimitiveType.Cylinder, "Blob Shadow", transform, new Vector3(0f, 0.012f, 0f),
                                      new Vector3(0.85f, 0.004f, 0.75f), new Color(0.06f, 0.05f, 0.08f), false, default(Vector3), 0f, 0f, Surface.Plain);
        Renderer br = blob.GetComponent<Renderer>();
        br.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        br.receiveShadows = false;
        blobShadow = blob.transform;
    }

    // A puff of dust where the foot touched the road (it stays behind as the road runs on).
    void OnFootstep()
    {
        if (!world.Running) return;
        Sfx.PlayStep(0.22f);
        if (PlayerWorld.Lite) return;
        DebrisBurst.Dust(transform.position + new Vector3(Random.Range(-0.15f, 0.15f), 0.05f, -0.1f),
                         new Color(0.62f, 0.57f, 0.5f), world.transform);
    }

    // ================= input =================

    void Update()
    {
        float dt = Time.deltaTime;
        cooldownTimer += dt;
        if (stunTimer > 0f) stunTimer -= dt;
        if (jumpBuffer > 0f) jumpBuffer -= dt;
        if (slideBuffer > 0f) slideBuffer -= dt;

        if (world.Running && dt > 0f)
        {
            ReadActions();
            if (cooldownTimer >= CollisionCooldown && !world.Turning) CheckHazards();
        }
        else
        {
            input.jumpQueued = false;
            input.actions.Clear();
        }

        // blinking while the hero cannot be hit again
        bool visible = cooldownTimer >= CollisionCooldown || world.Finished || Mathf.Repeat(cooldownTimer * 10f, 1f) < 0.55f;
        if (visible != blinkVisible)
        {
            blinkVisible = visible;
            foreach (Renderer r in modelRenderers) if (r != null) r.enabled = visible;
        }

        if (rig != null)
        {
            rig.running = world.Running;
            rig.defeated = world.Finished;
            rig.runSpeed = world.MoveSpeed / 7f;
            rig.lateral = lateral;
            rig.airborne = !grounded;
            rig.verticalSpeed = verticalVelocity;
            rig.sliding = Sliding && grounded;
        }

        // power-up effects spin around the hero
        bool shield = world.ShieldActive;
        if (shieldFx.gameObject.activeSelf != shield) shieldFx.gameObject.SetActive(shield);
        if (shield)
        {
            shieldFx.Rotate(0f, 180f * dt, 0f, Space.Self);
            float left = world.ShieldTimeLeft;
            shieldFx.localScale = Vector3.one * (left < 2f && Mathf.Repeat(Time.time * 8f, 1f) < 0.4f ? 0.6f : 1f);
        }
        bool magnet = world.MagnetActive;
        if (magnetFx.gameObject.activeSelf != magnet) magnetFx.gameObject.SetActive(magnet);
        if (magnet) magnetFx.Rotate(0f, -240f * dt, 0f, Space.Self);

        // the shadow stays on the road (the hero's root moves up during a jump)
        float sc = transform.localScale.y;
        float k = Mathf.Clamp01(1f - height / 2.2f);
        blobShadow.localPosition = new Vector3(0f, (0.012f - height) / sc, 0f);
        blobShadow.localScale = new Vector3(0.85f * (0.55f + 0.45f * k), 0.004f, 0.75f * (0.55f + 0.45f * k));
    }

    void ReadActions()
    {
        if (stunTimer > 0f) { input.actions.Clear(); return; }

        // the phone: swipes and taps
        while (input.actions.Count > 0) Act(input.actions.Dequeue());
        if (input.jumpQueued) { input.jumpQueued = false; Act('U'); }

        if (!input.isKeyboard) return;

        // the keyboard (each player has their own keys)
        int s = input.keyboardScheme;
        bool wasd = s == GameInput.SchemeSolo || s == 0;
        bool arrows = s == GameInput.SchemeSolo || s == 1;
        bool numpad = s == 2;
        if ((wasd && GameInput.Down(GKey.A)) || (arrows && GameInput.Down(GKey.Left)) || (numpad && GameInput.Down(GKey.Numpad4))) Act('L');
        if ((wasd && GameInput.Down(GKey.D)) || (arrows && GameInput.Down(GKey.Right)) || (numpad && GameInput.Down(GKey.Numpad6))) Act('R');
        if ((wasd && (GameInput.Down(GKey.W) || GameInput.Down(GKey.Space))) || (arrows && (GameInput.Down(GKey.Up) || GameInput.Down(GKey.RightShift)))
            || (numpad && (GameInput.Down(GKey.Numpad8) || GameInput.Down(GKey.Numpad0)))) Act('U');
        if ((wasd && GameInput.Down(GKey.S)) || (arrows && GameInput.Down(GKey.Down)) || (numpad && GameInput.Down(GKey.Numpad5))) Act('D');

        // the touch screen / mouse swipes belong to the first keyboard player (single player on a phone)
        if (s == GameInput.SchemeSolo || s == 0)
        {
            switch (GameInput.Swipe)
            {
                case SwipeDir.Left: Act('L'); break;
                case SwipeDir.Right: Act('R'); break;
                case SwipeDir.Up: Act('U'); break;
                case SwipeDir.Down: Act('D'); break;
            }
        }
    }

    void Act(char a)
    {
        switch (a)
        {
            case 'L': if (!world.TryTurn(-1)) ChangeLane(-1); break;
            case 'R': if (!world.TryTurn(1)) ChangeLane(1); break;
            case 'U': jumpBuffer = InputBuffer; slideBuffer = 0f; break;
            case 'D':
                slideBuffer = InputBuffer;
                jumpBuffer = 0f;
                if (!grounded) verticalVelocity = Mathf.Min(verticalVelocity, FastFallVelocity);   // drop down quickly
                break;
        }
    }

    void ChangeLane(int dir)
    {
        int next = Mathf.Clamp(lane + dir, 0, Lanes.Length - 1);
        if (next == lane)
        {
            // pressed against the edge: a little wobble, nothing else
            if (rig != null) rig.lateral = dir * 1.5f;
            return;
        }
        lane = next;
        Sfx.Play(SynthAudio.Whoosh, 0.4f, 1f + Random.Range(-0.08f, 0.08f), dir * 0.35f);
    }

    // ================= movement =================

    void FixedUpdate()
    {
        float dt = Time.fixedDeltaTime;
        Vector3 current = body.position;
        Vector3 next = current;

        if (world.Running)
        {
            float targetX = originX + Lanes[lane];
            float before = next.x;
            next.x = Mathf.MoveTowards(current.x, targetX, laneSpeed * dt);
            lateral = Mathf.Lerp(lateral, Mathf.Clamp((next.x - before) / (laneSpeed * dt + 0.0001f), -1f, 1f), 0.4f);
        }
        else lateral = Mathf.Lerp(lateral, 0f, 0.2f);

        // thrown back after a hit (classic mode), then back to the running line
        if (knockback > 0f)
        {
            next.z -= knockback * dt;
            knockback = Mathf.MoveTowards(knockback, 0f, 18f * dt);
        }
        else next.z = Mathf.MoveTowards(next.z, 0f, 3f * dt);
        next.z = Mathf.Clamp(next.z, -2f, 0f);

        // jump and slide: our own simple vertical physics (the body is kinematic)
        if (world.Running)
        {
            if (jumpBuffer > 0f && grounded)
            {
                jumpBuffer = 0f;
                grounded = false;
                slideTimer = 0f;
                verticalVelocity = JumpVelocity;
                Sfx.PlayVar(SynthAudio.Jump, 0.5f, 0.06f);
            }
            if (slideBuffer > 0f && grounded)
            {
                slideBuffer = 0f;
                if (slideTimer <= 0f) Sfx.PlayVar(SynthAudio.Slide, 0.55f, 0.06f);
                slideTimer = SlideTime;
            }
        }
        if (slideTimer > 0f) slideTimer -= dt;

        if (!grounded)
        {
            verticalVelocity += JumpGravity * dt;
            height += verticalVelocity * dt;
            if (height <= 0f)
            {
                height = 0f;
                verticalVelocity = 0f;
                grounded = true;
                if (rig != null) rig.Land();
                world.OnLanded();
                Sfx.PlayVar(SynthAudio.Land, 0.45f, 0.08f);
            }
        }
        next.y = height;

        body.MovePosition(next);
    }

    // After a corner the road is re-centred on the world's origin: the lane stays the same.
    public void SnapToLane()
    {
        Vector3 p = body.position;
        p.x = originX + Lanes[lane];
        body.position = p;
        transform.position = p;
    }

    // ================= hits =================

    // The hero is a vertical capsule (shorter while sliding); every obstacle of the world is checked against it.
    void CheckHazards()
    {
        float s = transform.localScale.y;
        Vector3 feet = transform.position;
        Vector3 bottom = feet + Vector3.up * (0.45f * s);   // the feet may brush the top of a fence in a jump
        Vector3 top = feet + Vector3.up * ((Sliding && grounded ? 0.7f : 1.6f) * s);
        foreach (Hazard h in world.Hazards)
        {
            if (h != null && h.Touches(bottom, top, HeroRadius * s))
            {
                RegisterHit(h);
                return;
            }
        }
    }

    // Falling obstacles have a dynamic Rigidbody, so a physics collision may also arrive here.
    void OnCollisionEnter(Collision other)
    {
        Hazard h = other.collider.GetComponentInParent<Hazard>();
        if (h != null && world.Running && cooldownTimer >= CollisionCooldown && !(Sliding && h.Kind == HazardKind.Fatal)) RegisterHit(h);
    }

    // The trigger sensor (a second way of noticing obstacles).
    public void OnSensorTouch(Collider other)
    {
        if (other.isTrigger || Sliding) return;
        Hazard h = other.GetComponentInParent<Hazard>();
        if (h != null && world.Running && cooldownTimer >= CollisionCooldown) RegisterHit(h);
    }

    void RegisterHit(Hazard hazard)
    {
        if (cooldownTimer < CollisionCooldown || !world.Running || hazard.Smashed) return;
        cooldownTimer = 0f;
        bool barrier = hazard.Kind == HazardKind.TurnBarrier;

        // whatever we ran into breaks into pieces
        hazard.Smash(transform.position + Vector3.up);

        // the shield takes the blow (even a deadly one)
        if (world.TryAbsorbHit())
        {
            Sfx.Play(SynthAudio.ShieldBreak, 0.75f);
            if (barrier) world.ForceTurn();
            return;
        }

        bool fatal = world.Rules == GameRules.Endless && hazard.Kind != HazardKind.Stumble;
        if (fatal) Sfx.Play(SynthAudio.Crash, 1f);
        else
        {
            Sfx.PlayVar(SynthAudio.Hit, 0.85f, 0.06f);
            Sfx.Play(SynthAudio.Stumble, 0.6f);
        }
        if (animator != null) animator.SetTrigger(HitTrigger);
        if (rig != null) rig.PlayHit();
        stunTimer = StunTime;

        if (world.Rules == GameRules.Endless)
        {
            if (hazard.Kind == HazardKind.Stumble) world.OnStumble();
            else world.Crash(barrier ? CrashCause.MissedTurn : CrashCause.Obstacle);
            return;
        }

        // classic mode: thrown back, the road stumbles, time is taken away; a missed corner turns by itself
        knockback = 7f;
        if (grounded)
        {
            grounded = false;
            verticalVelocity = 4.5f;
        }
        world.ChangeSpeed(HitSlowAmount, true);
        world.OnHit(hazard.TimePenalty);
        if (barrier) world.ForceTurn();
    }
}
