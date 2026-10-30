using UnityEngine;
using UnityEngine.InputSystem;

// Closes the game when Escape is pressed (on Android the "Back" button arrives as Escape).
// It is used in the main menu; inside a level Escape opens the pause window instead (GameUI).
// In WebGL Application.Quit() does nothing: a game cannot close a browser tab.
public class QuitApplication : MonoBehaviour
{
    void Update()
    {
        // A phone has no keyboard: Keyboard.current is null
        if (Keyboard.current != null && Keyboard.current.escapeKey.wasPressedThisFrame)
        {
            Debug.Log("We pushed escape, aren't we clever");
            Application.Quit();
        }
    }
}
