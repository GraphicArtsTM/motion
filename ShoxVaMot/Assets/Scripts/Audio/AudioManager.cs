using System.Collections;
using System.Collections.Generic;
using System.Threading;
using UnityEngine;

namespace Shatranj.Audio
{
    public enum Sfx { Tap, Place, Step, Whoosh, Impact, Crack, Check, Victory, Draw, Click, Open, Promote, Hero, Illegal, Tick, Pop }

    /// <summary>Воспроизведение синтезированных звуков и фоновой музыки.</summary>
    public class AudioManager : MonoBehaviour
    {
        public static AudioManager I { get; private set; }

        readonly Dictionary<Sfx, AudioClip> clips = new Dictionary<Sfx, AudioClip>();
        AudioSource music;
        AudioSource[] voices;
        int nextVoice;
        float sfxVolume = 1f, musicVolume = 0.5f;
        float musicDuck = 1f;
        float[] musicData;
        Coroutine duckCo;

        public static AudioManager Create(Transform parent)
        {
            var go = new GameObject("Audio");
            go.transform.SetParent(parent, false);
            var a = go.AddComponent<AudioManager>();
            I = a;
            a.Build();
            return a;
        }

        void Build()
        {
            music = gameObject.AddComponent<AudioSource>();
            music.loop = true;
            music.playOnAwake = false;
            music.spatialBlend = 0f;
            voices = new AudioSource[10];
            for (int i = 0; i < voices.Length; i++)
            {
                voices[i] = gameObject.AddComponent<AudioSource>();
                voices[i].playOnAwake = false;
                voices[i].spatialBlend = 0f;
            }

            var rnd = new System.Random(42);
            Make(Sfx.Tap, SoundSynth.WoodTap(1f, rnd));
            Make(Sfx.Place, SoundSynth.WoodTap(0.7f, rnd));
            Make(Sfx.Step, SoundSynth.Step(rnd));
            Make(Sfx.Whoosh, SoundSynth.Whoosh(rnd));
            Make(Sfx.Impact, SoundSynth.Impact(rnd));
            Make(Sfx.Crack, SoundSynth.Crack(rnd));
            Make(Sfx.Check, SoundSynth.Check(rnd));
            Make(Sfx.Victory, SoundSynth.Victory(rnd));
            Make(Sfx.Draw, SoundSynth.DrawChord(rnd));
            Make(Sfx.Click, SoundSynth.Click());
            Make(Sfx.Open, SoundSynth.Open(rnd));
            Make(Sfx.Promote, SoundSynth.Promote(rnd));
            Make(Sfx.Hero, SoundSynth.Hero(rnd));
            Make(Sfx.Illegal, SoundSynth.Illegal());
            Make(Sfx.Tick, SoundSynth.Tick());
            Make(Sfx.Pop, SoundSynth.Pop(rnd));

            // музыка считается в фоновом потоке, чтобы не было рывка при запуске
            var th = new Thread(() => { musicData = SoundSynth.Music(7); }) { IsBackground = true };
            th.Start();
            StartCoroutine(WaitMusic());
        }

        IEnumerator WaitMusic()
        {
            while (musicData == null) yield return null;
            var clip = AudioClip.Create("music", musicData.Length, 1, SoundSynth.SR, false);
            clip.SetData(musicData, 0);
            musicData = null;
            music.clip = clip;
            ApplyVolumes();
            music.Play();
        }

        void Make(Sfx id, float[] data)
        {
            var c = AudioClip.Create(id.ToString(), data.Length, 1, SoundSynth.SR, false);
            c.SetData(data, 0);
            clips[id] = c;
        }

        public void SetVolumes(float musicVol, float sfxVol)
        {
            musicVolume = musicVol;
            sfxVolume = sfxVol;
            ApplyVolumes();
        }

        void ApplyVolumes()
        {
            if (music != null) music.volume = musicVolume * 0.6f * musicDuck;
        }

        /// <summary>Приглушить музыку (например, на время фанфар).</summary>
        public void Duck(float level, float seconds)
        {
            if (duckCo != null) StopCoroutine(duckCo);
            duckCo = StartCoroutine(DuckRoutine(level, seconds));
        }

        IEnumerator DuckRoutine(float level, float seconds)
        {
            musicDuck = level;
            ApplyVolumes();
            for (float t = 0; t < seconds; t += Time.unscaledDeltaTime) yield return null;
            for (float t = 0; t < 1f; t += Time.unscaledDeltaTime / 1.5f)
            {
                musicDuck = Mathf.Lerp(level, 1f, t);
                ApplyVolumes();
                yield return null;
            }
            musicDuck = 1f;
            ApplyVolumes();
        }

        public static void Play(Sfx id, float volume = 1f, float pitchJitter = 0.06f)
        {
            if (I == null) return;
            I.PlayInternal(id, volume, pitchJitter);
        }

        void PlayInternal(Sfx id, float volume, float pitchJitter)
        {
            AudioClip c;
            if (!clips.TryGetValue(id, out c) || sfxVolume <= 0.001f) return;
            var v = voices[nextVoice];
            nextVoice = (nextVoice + 1) % voices.Length;
            v.pitch = 1f + Random.Range(-pitchJitter, pitchJitter);
            v.PlayOneShot(c, volume * sfxVolume);
        }
    }
}
