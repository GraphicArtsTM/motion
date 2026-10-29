using UnityEngine;

/// <summary>
/// The exit of the level. It is closed (grey) until all crystals are collected,
/// then it lights up, starts its particles and lets the player finish the level.
/// </summary>
public class ExitPortal : MonoBehaviour
{
    [SerializeField] Renderer ringRenderer;
    [SerializeField] Material closedMaterial;
    [SerializeField] Material openMaterial;
    [SerializeField] ParticleSystem openEffect;
    [SerializeField] Light portalLight;
    [SerializeField] Transform ring;
    [SerializeField] float openSpinSpeed = 120f;
    [SerializeField] float messageCooldown = 2f;

    bool isOpen;
    float nextMessageTime;

    void Start()
    {
        SetOpen(false);
        if (GameManager.Instance != null)
        {
            GameManager.Instance.PortalOpened += OnPortalOpened;
            if (GameManager.Instance.PortalOpen) SetOpen(true);
        }
    }

    void OnDestroy()
    {
        if (GameManager.Instance != null) GameManager.Instance.PortalOpened -= OnPortalOpened;
    }

    void Update()
    {
        // The ring model lies in its local XZ plane, so it spins around its own Y axis.
        if (isOpen && ring != null) ring.Rotate(0f, openSpinSpeed * Time.deltaTime, 0f, Space.Self);
    }

    void OnPortalOpened()
    {
        SetOpen(true);
    }

    void SetOpen(bool open)
    {
        isOpen = open;
        if (ringRenderer != null) ringRenderer.sharedMaterial = open ? openMaterial : closedMaterial;
        if (portalLight != null) portalLight.enabled = open;
        if (openEffect != null)
        {
            if (open) openEffect.Play();
            else openEffect.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        }
    }

    /// <summary>Called by PlayerCollision when the player touches the portal.</summary>
    public void TryEnter()
    {
        GameManager game = GameManager.Instance;
        if (game == null) return;

        if (isOpen)
        {
            game.CompleteLevel();
        }
        else if (Time.time >= nextMessageTime)
        {
            nextMessageTime = Time.time + messageCooldown;
            game.ShowMessage(Localization.Get("msg_portal_locked"));
        }
    }
}
