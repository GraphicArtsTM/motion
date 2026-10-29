using UnityEngine;
using UnityEngine.EventSystems;

/// <summary>
/// On-screen joystick for phones (works with the mouse in the Editor too).
/// PlayerController reads Direction, a vector from (-1,-1) to (1,1).
/// </summary>
public class VirtualJoystick : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
{
    [SerializeField] RectTransform background;
    [SerializeField] RectTransform handle;
    [SerializeField] float deadZone = 0.12f;

    public Vector2 Direction { get; private set; }

    Canvas canvas;

    void Awake()
    {
        canvas = GetComponentInParent<Canvas>();
        if (background == null) background = (RectTransform)transform;
    }

    void OnDisable()
    {
        Release();
    }

    public void OnPointerDown(PointerEventData eventData)
    {
        OnDrag(eventData);
    }

    public void OnDrag(PointerEventData eventData)
    {
        Camera uiCamera = canvas != null && canvas.renderMode != RenderMode.ScreenSpaceOverlay ? canvas.worldCamera : null;
        if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(background, eventData.position, uiCamera, out Vector2 local))
            return;

        float radius = background.rect.width * 0.5f;
        Vector2 offset = local - background.rect.center;
        Vector2 direction = Vector2.ClampMagnitude(offset / radius, 1f);

        Direction = direction.magnitude < deadZone ? Vector2.zero : direction;
        if (handle != null) handle.anchoredPosition = direction * radius;
    }

    public void OnPointerUp(PointerEventData eventData)
    {
        Release();
    }

    void Release()
    {
        Direction = Vector2.zero;
        if (handle != null) handle.anchoredPosition = Vector2.zero;
    }
}
