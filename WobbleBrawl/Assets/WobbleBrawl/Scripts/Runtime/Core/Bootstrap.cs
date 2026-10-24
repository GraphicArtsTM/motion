using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Zero-setup entry point: the whole game is generated in code, so pressing Play in ANY scene
    /// (even an empty one) starts it. Put a <see cref="NoAutoBoot"/> component in a scene to opt out.
    /// </summary>
    public static class Bootstrap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (Object.FindFirstObjectByType<NoAutoBoot>() != null) return;
            if (Object.FindFirstObjectByType<GameManager>() != null) return;
            new GameObject("WobbleBrawl").AddComponent<GameManager>();
        }
    }

    /// <summary>Marker: scenes containing this component do not auto-start the game.</summary>
    public sealed class NoAutoBoot : MonoBehaviour { }
}
