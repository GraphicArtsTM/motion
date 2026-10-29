using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

/// <summary>
/// Rolls the player ball with physics forces. This ONE script reads both kinds of input:
/// the keyboard (PC) and the on-screen joystick + DASH button (phone).
/// Dash: a short burst of speed with a cooldown.
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class PlayerController : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] float acceleration = 32f;
    [SerializeField] float maxSpeed = 7.5f;
    [SerializeField] float brakeStrength = 6f;

    [Header("Dash")]
    [SerializeField] float dashSpeed = 15f;
    [SerializeField] float dashCooldown = 1.2f;
    [SerializeField] float dashDuration = 0.3f;
    [SerializeField] TrailRenderer dashTrail;

    [Header("Touch controls (found automatically if empty)")]
    [SerializeField] VirtualJoystick joystick;

    Rigidbody body;
    Vector3 moveInput;
    Vector3 lastMoveDirection = Vector3.forward;
    bool dashRequested;
    float nextDashTime;
    float dashEndTime;

    /// <summary>0..1, how ready the dash is. The DASH button uses it to fill up.</summary>
    public float DashReady => dashCooldown <= 0f ? 1f : Mathf.Clamp01(1f - (nextDashTime - Time.time) / dashCooldown);

    void Awake()
    {
        body = GetComponent<Rigidbody>();
        // A sleeping Rigidbody gets no trigger events, so a trap could miss a player who stands still.
        body.sleepThreshold = 0f;
        if (joystick == null) joystick = FindFirstObjectByType<VirtualJoystick>();
        if (dashTrail != null) dashTrail.emitting = false;
    }

    void Update()
    {
        moveInput = ReadKeyboard() + ReadJoystick();
        moveInput = Vector3.ClampMagnitude(moveInput, 1f);
        if (moveInput.sqrMagnitude > 0.01f) lastMoveDirection = moveInput.normalized;

        if (ReadDashKey()) RequestDash();

        if (dashTrail != null && dashTrail.emitting && Time.time > dashEndTime) dashTrail.emitting = false;
    }

    void FixedUpdate()
    {
        if (moveInput.sqrMagnitude > 0.0001f)
        {
            body.AddForce(moveInput * acceleration, ForceMode.Acceleration);
        }
        else
        {
            // No input: slow down on the floor so the ball is easy to control.
            Vector3 flat = new Vector3(body.linearVelocity.x, 0f, body.linearVelocity.z);
            body.AddForce(-flat * brakeStrength, ForceMode.Acceleration);
        }

        LimitSpeed();

        if (dashRequested)
        {
            dashRequested = false;
            Dash();
        }
    }

    /// <summary>Called by the keyboard and by the DASH button on the screen.</summary>
    public void RequestDash()
    {
        if (Time.time >= nextDashTime) dashRequested = true;
    }

    void Dash()
    {
        nextDashTime = Time.time + dashCooldown;
        dashEndTime = Time.time + dashDuration;
        Vector3 direction = moveInput.sqrMagnitude > 0.01f ? moveInput.normalized : lastMoveDirection;
        Vector3 velocity = body.linearVelocity;
        body.linearVelocity = new Vector3(direction.x * dashSpeed, velocity.y, direction.z * dashSpeed);

        if (dashTrail != null) dashTrail.emitting = true;
        AudioManager.Play(Sfx.Dash);
    }

    void LimitSpeed()
    {
        // While dashing the ball may go faster for a moment.
        float limit = Time.time < dashEndTime ? dashSpeed : maxSpeed;
        Vector3 velocity = body.linearVelocity;
        Vector3 flat = new Vector3(velocity.x, 0f, velocity.z);
        if (flat.magnitude > limit)
        {
            flat = flat.normalized * limit;
            body.linearVelocity = new Vector3(flat.x, velocity.y, flat.z);
        }
    }

    Vector3 ReadJoystick()
    {
        if (joystick == null) return Vector3.zero;
        Vector2 direction = joystick.Direction;
        return new Vector3(direction.x, 0f, direction.y);
    }

#if ENABLE_INPUT_SYSTEM
    // New Input System (default in Unity 6 projects).
    Vector3 ReadKeyboard()
    {
        Keyboard keyboard = Keyboard.current;
        if (keyboard == null) return Vector3.zero;

        float x = 0f, z = 0f;
        if (keyboard.aKey.isPressed || keyboard.leftArrowKey.isPressed) x -= 1f;
        if (keyboard.dKey.isPressed || keyboard.rightArrowKey.isPressed) x += 1f;
        if (keyboard.sKey.isPressed || keyboard.downArrowKey.isPressed) z -= 1f;
        if (keyboard.wKey.isPressed || keyboard.upArrowKey.isPressed) z += 1f;
        return new Vector3(x, 0f, z);
    }

    bool ReadDashKey()
    {
        Keyboard keyboard = Keyboard.current;
        return keyboard != null && (keyboard.spaceKey.wasPressedThisFrame || keyboard.leftShiftKey.wasPressedThisFrame);
    }
#else
    // Old Input Manager (if the project uses it).
    Vector3 ReadKeyboard()
    {
        return new Vector3(Input.GetAxisRaw("Horizontal"), 0f, Input.GetAxisRaw("Vertical"));
    }

    bool ReadDashKey()
    {
        return Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.LeftShift);
    }
#endif
}
