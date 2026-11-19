using UnityEngine;

// One player's hero. Combines the former PlayerController and PlayerCollisionHandler:
// moves on commands from the phone joystick (or the keyboard), jumps,
// and tells its world about a hit on an obstacle.
[RequireComponent(typeof(Rigidbody))]
public class PlayerAvatar : MonoBehaviour
{
    const float BaseMoveSpeed = 5f;
    const float XClamp = 3f;
    const float ZClamp = 2f;
    const float CollisionCooldown = 1.2f;   // after a hit the hero blinks and cannot be hit again
    const float StunTime = 0.45f;           // controls do not respond right after a hit
    const float KnockbackSpeed = 7f;        // the hero is thrown back
    const float BounceVelocity = 4.5f;      // ...and bounces up a little
    const float HeroRadius = 0.3f;          // the size used to check touching obstacles
    const float HitSlowAmount = -2f;
    const float JumpVelocity = 8.2f;      // apex ~1.4 m: enough to clear a fence, not a wall
    const float JumpGravity = -24f;
    const float JumpBuffer = 0.15f;       // a press slightly before landing still counts

    PlayerWorld world;
    PhonePlayer input;
    Rigidbody body;
    Animator animator;
    CharacterRig rig;
    float moveSpeed;
    float originX;
    float cooldownTimer;

    float height;              // current jump height
    float verticalVelocity;
    bool grounded = true;
    float jumpBufferTimer;
    float lateral;             // smoothed sideways input, for leaning

    Transform shieldFx, magnetFx, blobShadow;
    Renderer[] modelRenderers;
    float stunTimer;
    float knockback;
    bool blinkVisible = true;

    static readonly int HitTrigger = Animator.StringToHash("Hit");

    public float Height { get { return height; } }

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

        // a trigger "sensor" for fences (see HitSensor for why it is needed)
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
        avatar.originX = position.x;
        avatar.moveSpeed = BaseMoveSpeed * character.moveMult;
        avatar.BuildEffects();
        sensor.owner = avatar;
        input.jumpQueued = false;
        return avatar;
    }

    // Glowing orbs around the hero (shield) and a gold ring at the feet (magnet).
    void BuildEffects()
    {
        shieldFx = new GameObject("Shield FX").transform;
        shieldFx.SetParent(transform, false);
        shieldFx.localPosition = new Vector3(0f, 0.95f, 0f);
        for (int i = 0; i < 6; i++)
        {
            float a = i * Mathf.PI / 3f;
            MatLib.Prim(PrimitiveType.Sphere, "Orb", shieldFx, new Vector3(Mathf.Sin(a) * 0.75f, (i % 2) * 0.5f - 0.25f, Mathf.Cos(a) * 0.75f),
                        Vector3.one * 0.16f, new Color(0.35f, 0.9f, 1f), false, default(Vector3), 0.9f, 1.6f);
        }
        shieldFx.gameObject.SetActive(false);

        magnetFx = new GameObject("Magnet FX").transform;
        magnetFx.SetParent(transform, false);
        magnetFx.localPosition = new Vector3(0f, 0.05f, 0f);
        for (int i = 0; i < 10; i++)
        {
            float a = i * Mathf.PI / 5f;
            MatLib.Prim(PrimitiveType.Cube, "Spark", magnetFx, new Vector3(Mathf.Sin(a) * 0.9f, 0f, Mathf.Cos(a) * 0.9f),
                        new Vector3(0.12f, 0.04f, 0.2f), new Color(1f, 0.82f, 0.3f), false, new Vector3(0f, a * Mathf.Rad2Deg, 0f), 0.8f, 1.2f);
        }
        magnetFx.gameObject.SetActive(false);

        // a soft dark spot under the feet: it stays on the ground and shrinks during a jump,
        // so it is easy to see where the hero will land
        GameObject blob = MatLib.Prim(PrimitiveType.Cylinder, "Blob Shadow", transform, new Vector3(0f, 0.012f, 0f),
                                      new Vector3(0.85f, 0.004f, 0.75f), new Color(0.06f, 0.04f, 0.1f), false, default(Vector3), 0f);
        Renderer br = blob.GetComponent<Renderer>();
        br.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        br.receiveShadows = false;
        blobShadow = blob.transform;
    }

    void Update()
    {
        float dt = Time.deltaTime;
        cooldownTimer += dt;
        if (jumpBufferTimer > 0f) jumpBufferTimer -= dt;
        if (stunTimer > 0f) stunTimer -= dt;

        // did we run into something? (checked every frame against all obstacles of this world)
        if (world.Running && cooldownTimer >= CollisionCooldown) CheckHazards();

        // blinking while the hero cannot be hit again
        bool visible = cooldownTimer >= CollisionCooldown || world.Finished || Mathf.Repeat(cooldownTimer * 10f, 1f) < 0.55f;
        if (visible != blinkVisible)
        {
            blinkVisible = visible;
            foreach (Renderer r in modelRenderers) if (r != null) r.enabled = visible;
        }

        if (world.Running && dt > 0f)
        {
            if (input.isKeyboard && GameInput.JumpPressed(input.keyboardScheme)) jumpBufferTimer = JumpBuffer;
            if (input.jumpQueued) { input.jumpQueued = false; jumpBufferTimer = JumpBuffer; }
        }
        else
        {
            input.jumpQueued = false;
        }

        Vector2 move = world.Running ? ReadInput() : Vector2.zero;
        lateral = Mathf.Lerp(lateral, move.x, 1f - Mathf.Exp(-10f * dt));

        if (rig != null)
        {
            rig.running = world.Running;
            rig.defeated = world.Finished;
            rig.runSpeed = world.MoveSpeed / 6f;
            rig.lateral = lateral;
            rig.airborne = !grounded;
            rig.verticalSpeed = verticalVelocity;
        }

        // power-up effects spin around the hero
        bool shield = world.ShieldActive;
        if (shieldFx.gameObject.activeSelf != shield) shieldFx.gameObject.SetActive(shield);
        if (shield)
        {
            shieldFx.Rotate(0f, 180f * dt, 0f, Space.Self);
            // blink during the last 2 seconds
            float left = world.ShieldTimeLeft;
            shieldFx.localScale = Vector3.one * (left < 2f && Mathf.Repeat(Time.time * 8f, 1f) < 0.4f ? 0.6f : 1f);
        }
        bool magnet = world.MagnetActive;
        if (magnetFx.gameObject.activeSelf != magnet) magnetFx.gameObject.SetActive(magnet);
        if (magnet) magnetFx.Rotate(0f, -240f * dt, 0f, Space.Self);

        // the shadow stays on the road (the hero's root moves up during a jump)
        float s = transform.localScale.y;
        float k = Mathf.Clamp01(1f - height / 2.2f);
        blobShadow.localPosition = new Vector3(0f, (0.012f - height) / s, 0f);
        blobShadow.localScale = new Vector3(0.85f * (0.55f + 0.45f * k), 0.004f, 0.75f * (0.55f + 0.45f * k));
    }

    void FixedUpdate()
    {
        float dt = Time.fixedDeltaTime;

        // when the road is not moving (intro, time is up) the hero does not run,
        // but a jump in progress still lands - nobody stays hanging in the air
        Vector2 move = world.Running && stunTimer <= 0f ? ReadInput() : Vector2.zero;
        Vector3 current = body.position;
        Vector3 next = current + new Vector3(move.x, 0f, move.y) * (moveSpeed * dt);
        if (!world.Running) jumpBufferTimer = 0f;

        // thrown back after a hit
        if (knockback > 0f)
        {
            next.z -= knockback * dt;
            knockback = Mathf.MoveTowards(knockback, 0f, 18f * dt);
        }

        next.x = Mathf.Clamp(next.x, originX - XClamp, originX + XClamp);
        next.z = Mathf.Clamp(next.z, -ZClamp, ZClamp);

        // jump: our own simple vertical physics (the body is kinematic)
        if (jumpBufferTimer > 0f && grounded)
        {
            jumpBufferTimer = 0f;
            grounded = false;
            verticalVelocity = JumpVelocity;
            Sfx.Play(SynthAudio.Jump, 0.45f);
        }
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
                Sfx.Play(SynthAudio.Land, 0.35f);
            }
        }
        next.y = height;

        body.MovePosition(next);
    }

    Vector2 ReadInput()
    {
        Vector2 move = input.move;

        // the keyboard player: their own keys (several players can share one keyboard)
        if (input.isKeyboard) move = GameInput.MoveVector(input.keyboardScheme);

        // the phone disconnected - stand still
        if (!input.isKeyboard && !input.connected) move = Vector2.zero;
        return move;
    }

    // The hero is a vertical capsule; every obstacle of the world is checked against it.
    void CheckHazards()
    {
        float s = transform.localScale.y;
        Vector3 feet = transform.position;
        Vector3 bottom = feet + Vector3.up * (0.45f * s);     // the feet may brush the top of a fence in a jump
        Vector3 top = feet + Vector3.up * (1.6f * s);
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
        if (h != null) RegisterHit(h);
    }

    // The trigger sensor (a second way to notice fences).
    public void OnSensorTouch(Collider other)
    {
        if (other.isTrigger) return;
        Hazard h = other.GetComponentInParent<Hazard>();
        if (h != null) RegisterHit(h);
    }

    void RegisterHit(Hazard hazard)
    {
        if (cooldownTimer < CollisionCooldown) return;
        if (!world.Running || hazard.Smashed) return;
        cooldownTimer = 0f;

        // whatever we ran into breaks into pieces
        hazard.Smash(transform.position + Vector3.up);

        // the shield takes the blow
        if (world.TryAbsorbHit())
        {
            Sfx.Play(SynthAudio.Shield, 0.6f);
            return;
        }

        // the hero is thrown back and bounces, the controls stop for a moment,
        // the road almost stops, time is taken away, the screen flashes red and shakes
        knockback = KnockbackSpeed;
        stunTimer = StunTime;
        if (grounded)
        {
            grounded = false;
            verticalVelocity = BounceVelocity;
        }
        world.ChangeSpeed(HitSlowAmount, true);
        world.OnHit(hazard.TimePenalty);
        Sfx.Play(SynthAudio.Hit, 0.9f);
        Sfx.Play(SynthAudio.Thud, 0.8f);
        if (animator != null) animator.SetTrigger(HitTrigger);
        if (rig != null) rig.PlayHit();
    }
}
