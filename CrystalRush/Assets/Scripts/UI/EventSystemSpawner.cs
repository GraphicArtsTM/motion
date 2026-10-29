using UnityEngine;
using UnityEngine.EventSystems;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem.UI;
#endif

/// <summary>
/// UI buttons need one EventSystem in the scene. This creates it with the correct input module
/// for the project's input settings (new Input System or old Input Manager).
/// </summary>
public class EventSystemSpawner : MonoBehaviour
{
    void Awake()
    {
        if (EventSystem.current != null || FindFirstObjectByType<EventSystem>() != null) return;

        GameObject eventSystem = new GameObject("EventSystem", typeof(EventSystem));
#if ENABLE_INPUT_SYSTEM
        InputSystemUIInputModule module = eventSystem.AddComponent<InputSystemUIInputModule>();
        module.AssignDefaultActions();
#else
        eventSystem.AddComponent<StandaloneInputModule>();
#endif
    }
}
