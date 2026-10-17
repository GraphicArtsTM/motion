using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Avtomatik ishga tushirish: istalgan sahnada Play bosilganda o'yin o'zini yaratadi.
    /// Sahnadagi boshqa kamera/yorug'liklar o'chiriladi (konflikt bo'lmasligi uchun).
    /// </summary>
    public static class Bootstrap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Init()
        {
            if (GameManager.I != null) return;
            foreach (var c in Object.FindObjectsOfType<Camera>()) c.gameObject.SetActive(false);
            foreach (var l in Object.FindObjectsOfType<Light>()) l.gameObject.SetActive(false);
            GameManager.Boot();
        }
    }
}
