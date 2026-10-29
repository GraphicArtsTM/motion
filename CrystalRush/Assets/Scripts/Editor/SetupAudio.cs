using System;
using System.IO;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Setup step: sounds. All effects and the music loop are synthesized by code
/// (sine/triangle waves, noise, a plucked string) and saved as WAV files in Assets/Audio.
/// The music is in D harmonic minor - a light Central Asian flavour.
/// </summary>
public static partial class CrystalRushSetup
{
    const int SampleRate = 44100;

    static AudioClip musicClip, collectClip, hitClip, dashClip, pickupClip, portalClip, winClip, loseClip, clickClip;

    static void CreateAudio()
    {
        collectClip = SaveWav("Collect", MakeCollect());
        hitClip = SaveWav("Hit", MakeHit());
        dashClip = SaveWav("Dash", MakeDash());
        pickupClip = SaveWav("Pickup", MakePickup());
        portalClip = SaveWav("PortalOpen", MakePortalOpen());
        winClip = SaveWav("Win", MakeWin());
        loseClip = SaveWav("Lose", MakeLose());
        clickClip = SaveWav("Click", MakeClick());
        musicClip = SaveWav("Music", MakeMusic(), true);
    }

    // ---------------------------------------------------------------- sound effects

    static float[] MakeCollect()
    {
        float[] s = new float[(int)(0.35f * SampleRate)];
        AddTone(s, 0f, 0.15f, Note(88), 0.5f, Wave.Triangle, 18f);   // E6
        AddTone(s, 0.06f, 0.25f, Note(95), 0.5f, Wave.Triangle, 12f); // B6
        AddTone(s, 0.06f, 0.25f, Note(107), 0.12f, Wave.Sine, 14f);  // sparkle
        return Normalize(s, 0.8f);
    }

    static float[] MakeHit()
    {
        float[] s = new float[(int)(0.4f * SampleRate)];
        AddSweep(s, 0f, 0.3f, 160f, 40f, 0.9f, 12f);
        AddNoise(s, 0f, 0.25f, 0.6f, 22f, 0.35f, 1);
        return Normalize(s, 0.85f);
    }

    static float[] MakeDash()
    {
        float[] s = new float[(int)(0.35f * SampleRate)];
        // Noise that goes from dull to bright = a "whoosh".
        System.Random random = new System.Random(7);
        float low = 0f;
        for (int i = 0; i < s.Length; i++)
        {
            float t = i / (float)SampleRate;
            float cutoff = Mathf.Lerp(0.05f, 0.5f, t / 0.35f);
            low += ((float)random.NextDouble() * 2f - 1f - low) * cutoff;
            float envelope = Mathf.Clamp01(t / 0.05f) * Mathf.Exp(-t * 9f);
            s[i] += low * envelope;
        }
        AddSweep(s, 0f, 0.2f, 300f, 700f, 0.15f, 10f);
        return Normalize(s, 0.6f);
    }

    static float[] MakePickup()
    {
        float[] s = new float[(int)(0.5f * SampleRate)];
        int[] notes = { 84, 88, 91, 96 }; // C6 E6 G6 C7
        for (int i = 0; i < notes.Length; i++) AddTone(s, i * 0.06f, 0.2f, Note(notes[i]), 0.4f, Wave.Triangle, 10f);
        return Normalize(s, 0.8f);
    }

    static float[] MakePortalOpen()
    {
        float[] s = new float[(int)(1.4f * SampleRate)];
        int[] chord = { 74, 78, 81, 86 }; // D5 F#5 A5 D6 - the minor key ends on a bright major chord
        for (int i = 0; i < chord.Length; i++)
            AddTone(s, i * 0.07f, 1.2f, Note(chord[i]), 0.3f, Wave.Sine, 2.5f, 0.12f, 6f);
        return Normalize(s, 0.75f);
    }

    static float[] MakeWin()
    {
        float[] s = new float[(int)(1.6f * SampleRate)];
        int[] run = { 72, 76, 79 }; // C5 E5 G5
        for (int i = 0; i < run.Length; i++) AddTone(s, i * 0.12f, 0.2f, Note(run[i]), 0.4f, Wave.Square, 8f);
        foreach (int n in new[] { 84, 88, 91 }) AddTone(s, 0.36f, 1.1f, Note(n), 0.3f, Wave.Triangle, 2.5f);
        AddTone(s, 0.36f, 1.1f, Note(60), 0.3f, Wave.Triangle, 2.5f);
        return Normalize(s, 0.8f);
    }

    static float[] MakeLose()
    {
        float[] s = new float[(int)(1.3f * SampleRate)];
        int[] notes = { 67, 64, 60 }; // G4 E4 C4
        for (int i = 0; i < notes.Length; i++) AddTone(s, i * 0.25f, 0.3f, Note(notes[i]), 0.45f, Wave.Triangle, 5f, 0.01f, 5f);
        AddSweep(s, 0.75f, 0.5f, Note(59), Note(47), 0.45f, 3f);
        return Normalize(s, 0.8f);
    }

    static float[] MakeClick()
    {
        float[] s = new float[(int)(0.06f * SampleRate)];
        AddTone(s, 0f, 0.05f, 1500f, 0.5f, Wave.Sine, 70f);
        return Normalize(s, 0.6f);
    }

    // ---------------------------------------------------------------- music

    static float[] MakeMusic()
    {
        const float bpm = 112f;
        float beat = 60f / bpm;
        float bar = beat * 4f;
        const int bars = 8;
        float[] s = new float[(int)(bar * bars * SampleRate)];

        // Chords: Dm - Bb - Gm - A (A major = the "harmonic minor" sound), played twice.
        int[] bassRoots = { 50, 46, 43, 45 };
        int[][] arps =
        {
            new[] { 62, 65, 69, 74 },   // Dm
            new[] { 58, 62, 65, 70 },   // Bb
            new[] { 55, 58, 62, 67 },   // Gm
            new[] { 57, 61, 64, 69 },   // A
        };
        int[] arpOrder = { 0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 3, 2, 1 };

        // A melody for the second half (MIDI note, start beat, length in beats).
        int[,] melody =
        {
            { 69, 0, 1 }, { 70, 1, 1 }, { 69, 2, 1 }, { 65, 3, 1 },
            { 74, 4, 2 }, { 70, 6, 1 }, { 65, 7, 1 },
            { 67, 8, 1 }, { 70, 9, 1 }, { 74, 10, 1 }, { 72, 11, 1 },
            { 73, 12, 2 }, { 69, 14, 2 },
        };

        for (int b = 0; b < bars; b++)
        {
            int chord = b % 4;
            float barStart = b * bar;

            // Bass: eighth notes, root and octave.
            for (int e = 0; e < 8; e++)
            {
                int note = bassRoots[chord] - 12 + (e % 4 == 2 ? 12 : 0);
                AddTone(s, barStart + e * beat * 0.5f, beat * 0.45f, Note(note), 0.22f, Wave.Triangle, 6f, 0.005f, 0f, true);
            }

            // Plucked strings (like a dutar): sixteenth-note arpeggio.
            for (int k = 0; k < 16; k++)
            {
                int note = arps[chord][arpOrder[k]];
                float volume = k % 4 == 0 ? 0.2f : 0.13f;
                AddPluck(s, barStart + k * beat * 0.25f, Note(note), volume, 0.5f);
            }

            // Drums: kick on 1 and 3, a doira-like slap on 2 and 4, soft hats on every eighth.
            AddKick(s, barStart);
            AddKick(s, barStart + beat * 2f);
            AddKick(s, barStart + beat * 3.5f, 0.5f);
            AddNoise(s, barStart + beat, 0.15f, 0.22f, 25f, 0.45f, 100 + b, true);
            AddNoise(s, barStart + beat * 3f, 0.15f, 0.22f, 25f, 0.45f, 200 + b, true);
            for (int e = 0; e < 8; e++)
                AddHat(s, barStart + e * beat * 0.5f, e % 2 == 1 ? 0.06f : 0.035f, 300 + b * 8 + e);
        }

        // Melody in bars 5-8.
        float melodyStart = 4 * bar;
        for (int i = 0; i < melody.GetLength(0); i++)
        {
            float start = melodyStart + melody[i, 1] * beat;
            float length = melody[i, 2] * beat;
            AddTone(s, start, length * 0.95f, Note(melody[i, 0]), 0.14f, Wave.Sine, 1.5f, 0.02f, 5.5f, true);
            AddTone(s, start, length * 0.95f, Note(melody[i, 0] + 12), 0.04f, Wave.Triangle, 2f, 0.02f, 5.5f, true);
        }

        return Normalize(s, 0.7f);
    }

    // ---------------------------------------------------------------- synth building blocks

    enum Wave { Sine, Triangle, Square }

    /// <summary>Frequency of a MIDI note (69 = A4 = 440 Hz).</summary>
    static float Note(int midi) => 440f * Mathf.Pow(2f, (midi - 69) / 12f);

    /// <summary>
    /// Adds one note. decay = how fast it fades, vibrato in Hz (0 = none).
    /// wrap = samples after the end go to the beginning (for a seamless music loop).
    /// </summary>
    static void AddTone(float[] s, float start, float duration, float frequency, float volume, Wave wave,
        float decay, float attack = 0.005f, float vibrato = 0f, bool wrap = false)
    {
        int first = (int)(start * SampleRate);
        int count = (int)(duration * SampleRate);
        float phase = 0f;
        for (int i = 0; i < count; i++)
        {
            float t = i / (float)SampleRate;
            float f = frequency * (1f + (vibrato > 0f ? 0.006f * Mathf.Sin(2f * Mathf.PI * vibrato * t) : 0f));
            phase += f / SampleRate;
            float x = phase - Mathf.Floor(phase);
            float value;
            switch (wave)
            {
                case Wave.Triangle: value = 4f * Mathf.Abs(x - 0.5f) - 1f; break;
                case Wave.Square: value = (x < 0.5f ? 1f : -1f) * 0.5f; break;
                default: value = Mathf.Sin(2f * Mathf.PI * x); break;
            }
            float envelope = Mathf.Min(1f, t / attack) * Mathf.Exp(-t * decay);
            float release = Mathf.Clamp01((count - i) / (0.01f * SampleRate)); // no click at the end
            Write(s, first + i, value * volume * envelope * release, wrap);
        }
    }

    static void AddSweep(float[] s, float start, float duration, float fromHz, float toHz, float volume, float decay)
    {
        int first = (int)(start * SampleRate);
        int count = (int)(duration * SampleRate);
        float phase = 0f;
        for (int i = 0; i < count; i++)
        {
            float t = i / (float)SampleRate;
            float f = Mathf.Lerp(fromHz, toHz, t / duration);
            phase += f / SampleRate;
            float release = Mathf.Clamp01((count - i) / (0.01f * SampleRate));
            Write(s, first + i, Mathf.Sin(2f * Mathf.PI * phase) * volume * Mathf.Exp(-t * decay) * release, false);
        }
    }

    /// <summary>Noise burst. smoothing 0..1: smaller = darker sound.</summary>
    static void AddNoise(float[] s, float start, float duration, float volume, float decay, float smoothing, int seed, bool wrap = false)
    {
        System.Random random = new System.Random(seed);
        int first = (int)(start * SampleRate);
        int count = (int)(duration * SampleRate);
        float low = 0f;
        for (int i = 0; i < count; i++)
        {
            float t = i / (float)SampleRate;
            low += ((float)random.NextDouble() * 2f - 1f - low) * smoothing;
            Write(s, first + i, low * volume * Mathf.Exp(-t * decay), wrap);
        }
    }

    static void AddHat(float[] s, float start, float volume, int seed)
    {
        // Bright noise = white noise minus its smoothed (dark) part.
        System.Random random = new System.Random(seed);
        int first = (int)(start * SampleRate);
        int count = (int)(0.05f * SampleRate);
        float low = 0f;
        for (int i = 0; i < count; i++)
        {
            float t = i / (float)SampleRate;
            float white = (float)random.NextDouble() * 2f - 1f;
            low += (white - low) * 0.2f;
            Write(s, first + i, (white - low) * volume * Mathf.Exp(-t * 60f), true);
        }
    }

    static void AddKick(float[] s, float start, float volume = 0.75f)
    {
        int first = (int)(start * SampleRate);
        int count = (int)(0.25f * SampleRate);
        float phase = 0f;
        for (int i = 0; i < count; i++)
        {
            float t = i / (float)SampleRate;
            float f = 45f + 110f * Mathf.Exp(-t * 30f);
            phase += f / SampleRate;
            Write(s, first + i, Mathf.Sin(2f * Mathf.PI * phase) * volume * Mathf.Exp(-t * 14f), true);
        }
    }

    /// <summary>Karplus-Strong plucked string: a short noise burst in a delay line that slowly smooths out.</summary>
    static void AddPluck(float[] s, float start, float frequency, float volume, float duration)
    {
        int period = Mathf.Max(2, Mathf.RoundToInt(SampleRate / frequency));
        float[] line = new float[period];
        System.Random random = new System.Random(Mathf.RoundToInt(frequency * 1000f + start * 100f));
        for (int i = 0; i < period; i++) line[i] = (float)random.NextDouble() * 2f - 1f;

        int first = (int)(start * SampleRate);
        int count = (int)(duration * SampleRate);
        int index = 0;
        for (int i = 0; i < count; i++)
        {
            int next = (index + 1) % period;
            float value = line[index];
            line[index] = 0.5f * (line[index] + line[next]) * 0.994f;
            index = next;
            float release = Mathf.Clamp01((count - i) / (0.02f * SampleRate));
            Write(s, first + i, value * volume * release, true);
        }
    }

    static void Write(float[] s, int index, float value, bool wrap)
    {
        if (wrap) index %= s.Length;
        if (index >= 0 && index < s.Length) s[index] += value;
    }

    static float[] Normalize(float[] s, float peak)
    {
        float max = 0.0001f;
        foreach (float v in s) max = Mathf.Max(max, Mathf.Abs(v));
        float gain = peak / max;
        for (int i = 0; i < s.Length; i++) s[i] *= gain;
        return s;
    }

    // ---------------------------------------------------------------- WAV file

    static AudioClip SaveWav(string name, float[] samples, bool isMusic = false)
    {
        string path = AudioFolder + "/" + name + ".wav";
        using (FileStream stream = new FileStream(path, FileMode.Create))
        using (BinaryWriter writer = new BinaryWriter(stream))
        {
            int dataSize = samples.Length * 2;
            writer.Write(new[] { 'R', 'I', 'F', 'F' });
            writer.Write(36 + dataSize);
            writer.Write(new[] { 'W', 'A', 'V', 'E' });
            writer.Write(new[] { 'f', 'm', 't', ' ' });
            writer.Write(16);                 // size of the format block
            writer.Write((short)1);           // PCM
            writer.Write((short)1);           // mono
            writer.Write(SampleRate);
            writer.Write(SampleRate * 2);     // bytes per second
            writer.Write((short)2);           // bytes per sample
            writer.Write((short)16);          // bits per sample
            writer.Write(new[] { 'd', 'a', 't', 'a' });
            writer.Write(dataSize);
            foreach (float sample in samples)
            {
                writer.Write((short)(Mathf.Clamp(sample, -1f, 1f) * short.MaxValue));
            }
        }

        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        if (isMusic)
        {
            AudioImporter importer = (AudioImporter)AssetImporter.GetAtPath(path);
            AudioImporterSampleSettings settings = importer.defaultSampleSettings;
            settings.loadType = AudioClipLoadType.CompressedInMemory;
            settings.compressionFormat = AudioCompressionFormat.Vorbis;
            settings.quality = 0.6f;
            importer.defaultSampleSettings = settings;
            importer.loadInBackground = true;
            importer.SaveAndReimport();
        }
        return AssetDatabase.LoadAssetAtPath<AudioClip>(path);
    }
}
