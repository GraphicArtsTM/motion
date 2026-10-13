using UnityEngine;
using UnityEngine.EventSystems;
using Shatranj.Visual;

namespace Shatranj.Core
{
    /// <summary>
    /// Сенсорное управление: тап — выбрать фигуру/клетку, свайп одним пальцем — вращать камеру,
    /// щипок двумя — приблизить. В редакторе: мышь и колесо.
    /// </summary>
    public class BoardInput : MonoBehaviour
    {
        GameRoot root;
        bool down, dragging, pinching;
        Vector2 downPos, lastPos;
        float lastPinch;

        public void Init(GameRoot r) { root = r; }

        bool CanInteract
        {
            get
            {
                return root != null && root.Ready && root.Match != null && root.Match.Game != null &&
                       root.UI.Current == root.UI.Hud && !root.UI.HasOverlay;
            }
        }

        float DragThreshold
        {
            get
            {
                float dpi = Screen.dpi > 1f ? Screen.dpi : 320f;
                return Mathf.Max(10f, dpi * 0.07f);
            }
        }

        void Update()
        {
            if (!CanInteract)
            {
                down = dragging = pinching = false;
                return;
            }

            // двумя пальцами — масштаб
            if (Input.touchCount >= 2)
            {
                var t0 = Input.GetTouch(0);
                var t1 = Input.GetTouch(1);
                float d = Vector2.Distance(t0.position, t1.position);
                if (!pinching) { pinching = true; lastPinch = d; }
                else if (d > 1f)
                {
                    root.Rig.Zoom(lastPinch / d);
                    lastPinch = d;
                }
                down = false;
                return;
            }
            if (pinching)
            {
                if (Input.touchCount == 0) pinching = false;
                return;
            }

            if (Mathf.Abs(Input.mouseScrollDelta.y) > 0.01f) root.Rig.Zoom(1f - Input.mouseScrollDelta.y * 0.08f);

            Vector2 pos = Input.mousePosition;
            if (Input.GetMouseButtonDown(0))
            {
                if (OverUI()) return;
                down = true;
                dragging = false;
                downPos = lastPos = pos;
            }
            if (down && Input.GetMouseButton(0))
            {
                if (!dragging && (pos - downPos).magnitude > DragThreshold) dragging = true;
                if (dragging)
                {
                    Vector2 delta = pos - lastPos;
                    float k = 220f / Mathf.Max(Screen.width, 1);
                    root.Rig.Orbit(delta.x * k, -delta.y * k * 0.6f);
                }
                lastPos = pos;
            }
            if (down && Input.GetMouseButtonUp(0))
            {
                if (!dragging) Tap(pos);
                down = false;
                dragging = false;
            }
        }

        bool OverUI()
        {
            var es = EventSystem.current;
            if (es == null) return false;
            if (Input.touchCount > 0) return es.IsPointerOverGameObject(Input.GetTouch(0).fingerId);
            return es.IsPointerOverGameObject();
        }

        void Tap(Vector2 screenPos)
        {
            var cam = root.Rig.Cam;
            Ray ray = cam.ScreenPointToRay(screenPos);
            int pieceSq = -1, planeSq = -1;

            float enter;
            if (new Plane(Vector3.up, Vector3.zero).Raycast(ray, out enter))
                planeSq = BoardView.SquareAt(ray.GetPoint(enter));

            int mask = ~((1 << 2) | (1 << IconRenderer.Layer));
            RaycastHit hit;
            if (Physics.Raycast(ray, out hit, 400f, mask))
            {
                var pv = hit.collider.GetComponentInParent<PieceView>();
                if (pv != null) pieceSq = BoardView.SquareAt(pv.transform.position);
            }
            root.Match.OnTap(pieceSq, planeSq);
        }
    }
}
