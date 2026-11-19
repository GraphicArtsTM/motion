using UnityEngine;

// One player's hero. Combines the former PlayerController and PlayerCollisionHandler:
// moves on commands from the phone joystick (or the keyboard for a test player)
// and tells its world about a hit on an obstacle.
[RequireComponent(typeof(Rigidbody))]
public class PlayerAvatar : MonoBehaviour
{
    const float BaseMoveSpeed = 5f;
    const float XClamp = 3f;
    const float ZClamp = 2f;
    const float CollisionCooldown = 1f;
    const float HitSlowAmount = -2f;

    PlayerWorld world;
    PhonePlayer input;
    Rigidbody body;
    Animator animator;
    CharacterRig rig;
    float moveSpeed;
    float originX;
    float cooldownTimer;

    static readonly int HitTrigger = Animator.StringToHash("Hit");

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
        avatar.originX = position.x;
        avatar.moveSpeed = BaseMoveSpeed * character.moveMult;
        avatar.cooldownTimer = 0f;
        sensor.owner = avatar;
        return avatar;
    }

    void Update()
    {
        cooldownTimer += Time.deltaTime;

        if (rig != null)
        {
            rig.running = !world.Finished;
            rig.runSpeed = world.MoveSpeed / 6f;
        }
    }

    void FixedUpdate()
    {
        if (world.Finished) return;

        Vector2 move = ReadInput();
        Vector3 current = body.position;
        Vector3 next = current + new Vector3(move.x, 0f, move.y) * (moveSpeed * Time.fixedDeltaTime);

        next.x = Mathf.Clamp(next.x, originX - XClamp, originX + XClamp);
        next.z = Mathf.Clamp(next.z, -ZClamp, ZClamp);

        body.MovePosition(next);
    }

    Vector2 ReadInput()
    {
        Vector2 move = input.move;

        // the keyboard player: WASD / arrows (works with both the new and the old input system)
        if (input.isKeyboard) move = GameInput.MoveVector();

        // the phone disconnected - stand still
        if (!input.isKeyboard && !input.connected) move = Vector2.zero;
        return move;
    }

    // Falling obstacles have a dynamic Rigidbody, so a real collision arrives here.
    void OnCollisionEnter(Collision other)
    {
        if (other.collider.GetComponentInParent<Hazard>() == null) return;
        RegisterHit();
    }

    // Fences are static - they are reported by the trigger sensor.
    public void OnSensorTouch(Collider other)
    {
        if (other.isTrigger) return;
        if (other.GetComponentInParent<Hazard>() == null) return;
        RegisterHit();
    }

    void RegisterHit()
    {
        if (cooldownTimer < CollisionCooldown) return;
        if (world.Finished) return;

        cooldownTimer = 0f;
        world.ChangeSpeed(HitSlowAmount);
        world.NotifyHit();
        Sfx.Play(SynthAudio.Hit, 0.7f);
        if (animator != null) animator.SetTrigger(HitTrigger);
        if (rig != null) rig.PlayHit();
    }
}
