using UnityEngine;
using UnityEngine.InputSystem;

// Rocket control: thrust and rotation (keyboard, gamepad and the on-screen buttons from TouchControls).
// Based on the book "Rocket Boost From Scratch", Part 4, plus the phone changes from the ads guide, Part 4.3.
public class Movement : MonoBehaviour
{
    // If the bindings are empty, default ones are added (Space / W / ↑ / gamepad A and ← → / A D / left stick),
    // so the rocket flies right away. You can change them in the Inspector.
    [SerializeField] InputAction thrust;
    [SerializeField] InputAction rotation;
    [SerializeField] float thrustStrength = 1000f;
    [SerializeField] float rotationStrength = 120f;
    [SerializeField] AudioClip mainEngineSFX;
    [SerializeField] ParticleSystem mainEngineParticles;
    [SerializeField] ParticleSystem rightThrustParticles;
    [SerializeField] ParticleSystem leftThrustParticles;

    Rigidbody rb;
    AudioSource audioSource;

    private void Awake()
    {
        if (thrust == null || thrust.bindings.Count == 0) thrust = CreateThrustAction();
        if (rotation == null || rotation.bindings.Count == 0) rotation = CreateRotationAction();
    }

    // Called by Unity in the editor when the component is added (or Reset is chosen in its menu)
    private void Reset()
    {
        ResetBindingsToDefault();
    }

    public void ResetBindingsToDefault()
    {
        thrust = CreateThrustAction();
        rotation = CreateRotationAction();
    }

    private void Start()
    {
        rb = GetComponent<Rigidbody>();
        audioSource = GetComponent<AudioSource>();
    }

    private void OnEnable()
    {
        thrust.Enable();
        rotation.Enable();
    }

    private void OnDisable()
    {
        thrust.Disable();
        rotation.Disable();
        // The sound is not stopped here: CollisionHandler plays the crash/success sound on the same AudioSource
        StopParticles(mainEngineParticles);
        StopRotating();
    }

    private void FixedUpdate()
    {
        ProcessThrust();
        ProcessRotation();
    }

    private void ProcessThrust()
    {
        if (thrust.IsPressed() || TouchControls.Thrust)
        {
            StartThrusting();
        }
        else
        {
            StopThrusting();
        }
    }

    private void StartThrusting()
    {
        rb.AddRelativeForce(Vector3.up * thrustStrength * Time.fixedDeltaTime);
        if (audioSource != null && mainEngineSFX != null && !audioSource.isPlaying)
        {
            // A looping engine sound: it plays while the button is held, without gaps
            audioSource.clip = mainEngineSFX;
            audioSource.loop = true;
            audioSource.Play();
        }
        if (mainEngineParticles != null && !mainEngineParticles.isPlaying)
        {
            mainEngineParticles.Play();
        }
    }

    private void StopThrusting()
    {
        if (audioSource != null && audioSource.isPlaying && audioSource.clip == mainEngineSFX)
        {
            audioSource.Stop();
        }
        StopParticles(mainEngineParticles);
    }

    private void ProcessRotation()
    {
        float rotationInput = Mathf.Clamp(rotation.ReadValue<float>() + TouchControls.Rotation, -1f, 1f);
        if (rotationInput < 0)
        {
            RotateRight();
        }
        else if (rotationInput > 0)
        {
            RotateLeft();
        }
        else
        {
            StopRotating();
        }
    }

    private void RotateRight()
    {
        ApplyRotation(rotationStrength);
        if (rightThrustParticles != null && !rightThrustParticles.isPlaying)
        {
            StopParticles(leftThrustParticles);
            rightThrustParticles.Play();
        }
    }

    private void RotateLeft()
    {
        ApplyRotation(-rotationStrength);
        if (leftThrustParticles != null && !leftThrustParticles.isPlaying)
        {
            StopParticles(rightThrustParticles);
            leftThrustParticles.Play();
        }
    }

    private void StopRotating()
    {
        StopParticles(rightThrustParticles);
        StopParticles(leftThrustParticles);
    }

    private void ApplyRotation(float rotationThisFrame)
    {
        // We remember the Rigidbody constraints (Freeze Position Z, Freeze Rotation X/Y),
        // because "freezeRotation = false" would also clear the X and Y locks.
        RigidbodyConstraints savedConstraints = rb.constraints;
        rb.freezeRotation = true;
        transform.Rotate(Vector3.forward * rotationThisFrame * Time.fixedDeltaTime);
        rb.constraints = savedConstraints;
    }

    static void StopParticles(ParticleSystem ps)
    {
        if (ps != null && ps.isPlaying) ps.Stop();
    }

    static InputAction CreateThrustAction()
    {
        InputAction action = new InputAction("Thrust", InputActionType.Button);
        action.AddBinding("<Keyboard>/space");
        action.AddBinding("<Keyboard>/w");
        action.AddBinding("<Keyboard>/upArrow");
        action.AddBinding("<Gamepad>/buttonSouth");
        action.AddBinding("<Gamepad>/rightTrigger");
        return action;
    }

    static InputAction CreateRotationAction()
    {
        InputAction action = new InputAction("Rotation", InputActionType.Value, expectedControlType: "Axis");
        action.AddCompositeBinding("1DAxis")
            .With("Negative", "<Keyboard>/leftArrow")
            .With("Positive", "<Keyboard>/rightArrow");
        action.AddCompositeBinding("1DAxis")
            .With("Negative", "<Keyboard>/a")
            .With("Positive", "<Keyboard>/d");
        action.AddBinding("<Gamepad>/leftStick/x");
        return action;
    }
}
