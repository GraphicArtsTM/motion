using UnityEngine;

/// <summary>
/// Danger type 3 - SPIKE TRAP in the floor.
/// HIDDEN (safe) -> WARNING (the plate glows orange, still safe) -> UP (spikes out, deadly) -> HIDDEN...
/// The player can see the warning and must leave the plate in time.
/// </summary>
public class SpikeTrap : MonoBehaviour
{
    enum Phase { Hidden, Warning, Up }

    [Header("Timing (seconds)")]
    [SerializeField] float hiddenTime = 2.2f;
    [SerializeField] float warningTime = 0.9f;
    [SerializeField] float upTime = 1.3f;
    [SerializeField] float startOffset = 0f;

    [Header("Parts")]
    [SerializeField] Transform spikes;
    [SerializeField] Collider damageTrigger;
    [SerializeField] Renderer plateRenderer;
    [SerializeField] Color safeColor = new Color(0.25f, 0.27f, 0.35f);
    [SerializeField] Color warningColor = new Color(1f, 0.55f, 0.1f);
    [SerializeField] Color dangerColor = new Color(1f, 0.15f, 0.15f);

    [Header("Spike movement")]
    [SerializeField] float hiddenHeight = -0.6f;
    [SerializeField] float upHeight = 0.05f;
    [SerializeField] float moveSpeed = 12f;

    float timer;
    Phase phase;
    MaterialPropertyBlock block;

    float CycleLength => hiddenTime + warningTime + upTime;

    void Awake()
    {
        block = new MaterialPropertyBlock();
        timer = Mathf.Repeat(startOffset, CycleLength);
        phase = GetPhase(timer);
        damageTrigger.enabled = phase == Phase.Up;
        spikes.localPosition = new Vector3(0f, phase == Phase.Up ? upHeight : hiddenHeight, 0f);
    }

    void Update()
    {
        timer = Mathf.Repeat(timer + Time.deltaTime, CycleLength);
        phase = GetPhase(timer);

        // The trap hurts only while the spikes are up.
        damageTrigger.enabled = phase == Phase.Up;

        float targetHeight = phase == Phase.Up ? upHeight : hiddenHeight;
        Vector3 position = spikes.localPosition;
        position.y = Mathf.MoveTowards(position.y, targetHeight, moveSpeed * Time.deltaTime);
        spikes.localPosition = position;

        UpdatePlateColor();
    }

    Phase GetPhase(float time)
    {
        if (time < hiddenTime) return Phase.Hidden;
        if (time < hiddenTime + warningTime) return Phase.Warning;
        return Phase.Up;
    }

    void UpdatePlateColor()
    {
        if (plateRenderer == null) return;

        Color color = safeColor;
        if (phase == Phase.Warning)
        {
            float blink = Mathf.PingPong(Time.time * 6f, 1f);
            color = Color.Lerp(safeColor, warningColor, blink);
        }
        else if (phase == Phase.Up)
        {
            color = dangerColor;
        }

        // A MaterialPropertyBlock changes the color without creating a new material for every trap.
        plateRenderer.GetPropertyBlock(block);
        block.SetColor("_BaseColor", color);           // URP Lit
        block.SetColor("_Color", color);               // Built-in Standard
        block.SetColor("_EmissionColor", color * (phase == Phase.Hidden ? 0f : 1.5f));
        plateRenderer.SetPropertyBlock(block);
    }
}
