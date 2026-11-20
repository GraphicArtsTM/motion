using System.Collections.Generic;
using UnityEngine;

// Runs the music cross-fades, the wind, birdsong and delayed sounds for Sfx (see SynthAudio.cs).
public class SfxDriver : MonoBehaviour
{
    AudioSource current, other, wind;
    AudioClip wanted;
    public float duck = 1f;
    float windLevel, reported = -1f;
    bool birdsReported;
    float birdTimer = 3f;

    struct Pending { public AudioClip clip; public float volume, at; }
    readonly List<Pending> pending = new List<Pending>();

    public void Setup(AudioSource a, AudioSource b, AudioSource w)
    {
        current = a;
        other = b;
        wind = w;
    }

    public void WantMusic(AudioClip clip)
    {
        if (clip == wanted) return;
        wanted = clip;
        // the old track fades out on "other", the new one fades in on "current"
        AudioSource t = current; current = other; other = t;
        current.clip = clip;
        current.volume = 0f;
        if (clip != null) current.Play(); else current.Stop();
    }

    public void Report(float speed01, bool birds)
    {
        reported = Mathf.Max(reported, speed01);
        birdsReported |= birds;
    }

    public void Schedule(AudioClip clip, float volume, float delay)
    {
        pending.Add(new Pending { clip = clip, volume = volume, at = Time.unscaledTime + delay });
    }

    bool musicReady;

    void Update()
    {
        float dt = Time.unscaledDeltaTime;
        if (!musicReady) musicReady = SynthAudio.PollMusic();

        // music cross-fade
        float target = Sfx.MusicVolume * duck;
        if (current != null && current.clip != null) current.volume = Mathf.MoveTowards(current.volume, target, dt * 0.6f);
        if (other != null && other.isPlaying)
        {
            other.volume = Mathf.MoveTowards(other.volume, 0f, dt * 0.8f);
            if (other.volume <= 0.001f) other.Stop();
        }

        // wind: louder and higher the faster the road runs; silent in the menus
        float w = reported >= 0f ? 0.06f + 0.22f * reported : 0f;
        windLevel = Mathf.MoveTowards(windLevel, w, dt * 0.5f);
        if (wind != null)
        {
            wind.volume = windLevel * Sfx.Volume;
            wind.pitch = 0.85f + 0.45f * Mathf.Clamp01(reported);
        }

        // birdsong now and then (not in winter, not while paused)
        if (birdsReported && Time.timeScale > 0f)
        {
            birdTimer -= dt;
            if (birdTimer <= 0f && SynthAudio.Birds != null)
            {
                birdTimer = Random.Range(3f, 8f);
                Sfx.Play(SynthAudio.Birds[Random.Range(0, SynthAudio.Birds.Length)], Random.Range(0.12f, 0.22f),
                         Random.Range(0.9f, 1.15f), Random.Range(-0.8f, 0.8f));
            }
        }
        reported = -1f;
        birdsReported = false;

        for (int i = pending.Count - 1; i >= 0; i--)
        {
            if (Time.unscaledTime < pending[i].at) continue;
            Sfx.Play(pending[i].clip, pending[i].volume);
            pending.RemoveAt(i);
        }
    }
}
