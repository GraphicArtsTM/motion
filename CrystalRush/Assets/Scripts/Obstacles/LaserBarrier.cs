using UnityEngine;

/// <summary>
/// Danger type 1 - LASER GATE.
/// Works in a cycle: OFF (safe) -> WARNING (thin blinking beam, still safe) -> ON (deadly) -> OFF...
/// Only in the ON state the trigger collider of the beam is enabled.
/// Different start offsets let several lasers work out of step.
/// </summary>
public class LaserBarrier : MonoBehaviour
{
    enum Phase { Off, Warning, On }

    [Header("Timing (seconds)")]
    [SerializeField] float offTime = 2f;
    [SerializeField] float warningTime = 0.7f;
    [SerializeField] float onTime = 1.6f;
    [SerializeField] float startOffset = 0f;

    [Header("Shape")]
    [SerializeField, Min(1f)] float length = 6f;
    [SerializeField] float beamThickness = 0.22f;

    [Header("Parts")]
    [SerializeField] Transform beam;
    [SerializeField] Collider beamCollider;
    [SerializeField] Renderer beamRenderer;
    [SerializeField] Transform postA;
    [SerializeField] Transform postB;

    float cycleTimer;
    Phase phase = Phase.Off;

    float CycleLength => offTime + warningTime + onTime;

    void Awake()
    {
        ApplyLength();
        cycleTimer = Mathf.Repeat(startOffset, CycleLength);
        SetPhase(GetPhase(cycleTimer));
    }

    void Update()
    {
        cycleTimer = Mathf.Repeat(cycleTimer + Time.deltaTime, CycleLength);
        Phase newPhase = GetPhase(cycleTimer);
        if (newPhase != phase) SetPhase(newPhase);

        if (phase == Phase.Warning)
        {
            // Blink faster and faster before the beam turns on.
            float timeInWarning = cycleTimer - offTime;
            float blinkSpeed = Mathf.Lerp(8f, 24f, timeInWarning / warningTime);
            beamRenderer.enabled = Mathf.Sin(Time.time * blinkSpeed) > 0f;
        }
        else if (phase == Phase.On)
        {
            // A small "hum" so the active beam looks alive.
            float pulse = 1f + Mathf.Sin(Time.time * 30f) * 0.12f;
            beam.localScale = new Vector3(length, beamThickness * pulse, beamThickness * pulse);
        }
    }

    Phase GetPhase(float time)
    {
        if (time < offTime) return Phase.Off;
        if (time < offTime + warningTime) return Phase.Warning;
        return Phase.On;
    }

    void SetPhase(Phase newPhase)
    {
        phase = newPhase;
        bool on = phase == Phase.On;

        beamCollider.enabled = on;
        beamRenderer.enabled = phase != Phase.Off;
        float thickness = on ? beamThickness : beamThickness * 0.3f;
        beam.localScale = new Vector3(length, thickness, thickness);
    }

    /// <summary>Places the two posts and stretches the beam between them. The setup tool calls it too.</summary>
    public void ApplyLength()
    {
        if (beam != null) beam.localScale = new Vector3(length, beamThickness, beamThickness);
        if (postA != null) postA.localPosition = new Vector3(-length * 0.5f, postA.localPosition.y, 0f);
        if (postB != null) postB.localPosition = new Vector3(length * 0.5f, postB.localPosition.y, 0f);
    }
}
