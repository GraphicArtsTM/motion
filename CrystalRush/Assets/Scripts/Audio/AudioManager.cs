using UnityEngine;

public enum Sfx
{
    Collect,
    Hit,
    Dash,
    Pickup,
    PortalOpen,
    Win,
    Lose,
    Click
}

/// <summary>
/// Plays music and sound effects. Lives through scene loads (DontDestroyOnLoad),
/// so the music does not restart on every level.
/// Every scene has a copy of the AudioManager prefab; extra copies remove themselves.
/// </summary>
public class AudioManager : MonoBehaviour
{
    public static AudioManager Instance { get; private set; }

    [Header("Music")]
    [SerializeField] AudioClip music;
    [SerializeField, Range(0f, 1f)] float musicVolume = 0.45f;

    [Header("Sound effects")]
    [SerializeField] AudioClip collect;
    [SerializeField] AudioClip hit;
    [SerializeField] AudioClip dash;
    [SerializeField] AudioClip pickup;
    [SerializeField] AudioClip portalOpen;
    [SerializeField] AudioClip win;
    [SerializeField] AudioClip lose;
    [SerializeField] AudioClip click;

    AudioSource musicSource;
    AudioSource sfxSource;

    void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
        DontDestroyOnLoad(gameObject);

        musicSource = gameObject.AddComponent<AudioSource>();
        musicSource.clip = music;
        musicSource.loop = true;
        musicSource.playOnAwake = false;
        musicSource.volume = musicVolume;
        musicSource.ignoreListenerPause = false;

        sfxSource = gameObject.AddComponent<AudioSource>();
        sfxSource.playOnAwake = false;
        // UI clicks and the Game Over sound must play even when the game is paused.
        sfxSource.ignoreListenerPause = true;

        AudioListener.volume = SaveData.Volume;
        if (music != null) musicSource.Play();
    }

    /// <summary>Short way to play a sound from any script: AudioManager.Play(Sfx.Hit).</summary>
    public static void Play(Sfx sound)
    {
        if (Instance != null) Instance.PlaySound(sound);
    }

    void PlaySound(Sfx sound)
    {
        AudioClip clip = GetClip(sound);
        if (clip == null) return;
        // A little random pitch so repeated sounds do not get boring.
        sfxSource.pitch = sound == Sfx.Collect || sound == Sfx.Hit ? Random.Range(0.94f, 1.08f) : 1f;
        sfxSource.PlayOneShot(clip);
    }

    AudioClip GetClip(Sfx sound)
    {
        switch (sound)
        {
            case Sfx.Collect: return collect;
            case Sfx.Hit: return hit;
            case Sfx.Dash: return dash;
            case Sfx.Pickup: return pickup;
            case Sfx.PortalOpen: return portalOpen;
            case Sfx.Win: return win;
            case Sfx.Lose: return lose;
            case Sfx.Click: return click;
            default: return null;
        }
    }

    /// <summary>Master volume for the whole game (slider in the menu and in the pause panel).</summary>
    public static void SetVolume(float volume)
    {
        SaveData.Volume = volume;
        AudioListener.volume = volume;
    }

    /// <summary>Ads must not play over our music.</summary>
    public static void SetPausedForAd(bool paused)
    {
        AudioListener.pause = paused;
    }
}
