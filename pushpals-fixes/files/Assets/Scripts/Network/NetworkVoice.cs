using System.IO;
using PushPals.Players;
using PushPals.Ragdoll;
using PushPals.Ragdoll.Visual;
using Steamworks;
using Unity.Netcode;
using UnityEngine;

namespace PushPals.Network
{
    /// <summary>
    /// Голос по близости (Этап 13) через голосовой чат Steam: владелец спички записывает микрофон (Steam сжимает и сам
    /// отрезает тишину), шлёт хосту, хост — остальным. Каждый ПК проигрывает голос со спички говорящего:
    /// громкость падает с расстоянием до своей спички (рядом — полностью, дальше farDistance — тишина), звук слева/справа.
    /// Пока спичка говорит — у головы «звуковые волны». Без Steam (локальная сеть без Steam) голоса нет.
    /// Автотест: -pp-voicetest — вместо микрофона пищит тон (несжатый звук, Steam не нужен).
    /// </summary>
    [RequireComponent(typeof(RagdollController))]
    public class NetworkVoice : NetworkBehaviour
    {
        [Tooltip("До этого расстояния голос слышно полностью, м")]
        [SerializeField] private float nearDistance = 5f;
        [Tooltip("Дальше этого — не слышно, м")]
        [SerializeField] private float farDistance = 16f;
        [Tooltip("Насколько звук уходит влево/вправо (0 — по центру)")]
        [SerializeField, Range(0f, 1f)] private float maxPan = 0.7f;
        [Tooltip("Частота проигрывания, Гц (Steam распаковывает голос в любую от 11025 до 48000)")]
        [SerializeField] private int sampleRate = 24000;
        [Tooltip("Сколько звука накопить перед началом проигрывания (против заиканий), с")]
        [SerializeField] private float startBuffer = 0.1f;
        [Tooltip("Кусочки голоса копятся и уходят пачкой раз в столько секунд (пакет на каждый кадр переполнял очередь сети)")]
        [SerializeField] private float sendInterval = 0.06f;
        [Tooltip("Призрак звучит тише и с эхом")]
        [SerializeField, Range(0f, 1f)] private float ghostVolume = 0.6f;

        /// <summary>Автотест: вместо микрофона — тон (пищит полсекунды через полсекунды).</summary>
        public static bool TestTone { get; set; }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() { TestTone = false; }

        private const byte CodecSteam = 0, CodecPcm16 = 1;
        // Больше этого — ненадёжной отправкой нельзя (Netcode ругается) — шлём надёжной
        private const int UnreliableLimit = 1000;
        private const int TestRate = 8000;
        private const int MinPcmRate = 8000, MaxPcmRate = 48000;

        private RagdollController controller;
        private AudioSource source;
        private AudioEchoFilter echo;
        private readonly MemoryStream readStream = new MemoryStream();
        private readonly MemoryStream pcmStream = new MemoryStream();
        private bool recording;
        private readonly System.Collections.Generic.List<byte[]> pending = new System.Collections.Generic.List<byte[]>();
        private int pendingBytes;
        private float flushTimer;
        private float testPhase, testClock;

        // Кольцевой буфер звука (пишет главный поток, читает звуковой)
        private float[] ring;
        private int ringRead, ringWrite, ringCount;
        private bool playing;
        private readonly object ringLock = new object();

        /// <summary>Когда последний раз слышали (или сами говорили) — для значка.</summary>
        public float LastVoiceTime { get; private set; } = -10f;
        /// <summary>Громкость последнего кусочка (0..1).</summary>
        public float Level { get; private set; }
        /// <summary>Сколько кусочков голоса получили (для автотеста).</summary>
        public int PacketsHeard { get; private set; }
        public bool Speaking => Time.time - LastVoiceTime < 0.3f;
        public float BufferedSeconds { get { lock (ringLock) return ringCount / (float)sampleRate; } }
        public float Volume => source != null ? source.volume : 0f;

        private Transform waves;
        private SpriteRenderer[] waveArt;

        private void Awake()
        {
            controller = GetComponent<RagdollController>();
            ring = new float[sampleRate * 2];
        }

        public override void OnNetworkSpawn()
        {
            if (!IsOwner) CreatePlayer();
            else if (!TestTone && !SteamClient.IsValid && NetSession.Instance != null) NetSession.Instance.TryInitSteam();
        }

        public override void OnNetworkDespawn()
        {
            if (recording && SteamClient.IsValid) SteamUser.VoiceRecord = false;
            recording = false;
        }

        // Источник звука на спичке: потоковый клип читает кольцевой буфер
        private void CreatePlayer()
        {
            source = gameObject.AddComponent<AudioSource>();
            source.spatialBlend = 0f; // громкость и сторону считаем сами (2D-игра)
            source.loop = true;
            source.playOnAwake = false;
            source.clip = AudioClip.Create("Voice", sampleRate, 1, sampleRate, true, OnAudioRead);
            source.volume = 0f;
            echo = gameObject.AddComponent<AudioEchoFilter>();
            echo.delay = 180f;
            echo.decayRatio = 0.45f;
            echo.enabled = false;
            source.Play();
        }

        // ---------- Говорим (владелец) ----------

        private void Update()
        {
            if (!IsSpawned) return;
            if (IsOwner) { Record(); Flush(); }
            UpdateVolume();
            UpdateWaves();
        }

        private void Record()
        {
            if (TestTone) { SendTestTone(); return; }
            bool want = VoiceSettings.Transmitting && SteamClient.IsValid;
            if (want != recording)
            {
                recording = want;
                if (SteamClient.IsValid) SteamUser.VoiceRecord = want;
            }
            if (!recording || !SteamUser.HasVoiceData) return;
            readStream.SetLength(0);
            readStream.WriteByte(CodecSteam);
            int n = SteamUser.ReadVoiceData(readStream);
            if (n <= 0) return;
            LastVoiceTime = Time.time;
            Send(readStream.ToArray());
        }

        // Тон 440 Гц: полсекунды пищим, полсекунды молчим (кусочки по кадру)
        private void SendTestTone()
        {
            testClock += Time.deltaTime;
            if (testClock % 1f > 0.5f) return;
            int count = Mathf.Clamp(Mathf.RoundToInt(TestRate * Time.deltaTime), 1, 1200);
            var data = new byte[3 + count * 2];
            data[0] = CodecPcm16;
            data[1] = (byte)(TestRate & 255);
            data[2] = (byte)(TestRate >> 8);
            for (int i = 0; i < count; i++)
            {
                testPhase += 440f * 2f * Mathf.PI / TestRate;
                short s = (short)(Mathf.Sin(testPhase) * 8000f);
                data[3 + i * 2] = (byte)(s & 255);
                data[4 + i * 2] = (byte)((s >> 8) & 255);
            }
            LastVoiceTime = Time.time;
            Send(data);
        }

        // Кусочек в пачку
        private void Send(byte[] chunk)
        {
            pending.Add(chunk);
            pendingBytes += chunk.Length + 2;
        }

        // Пачка: [число кусочков] и у каждого [длина 2 байта][кусочек]
        private void Flush()
        {
            flushTimer += Time.deltaTime;
            if (pending.Count == 0 || (flushTimer < sendInterval && pendingBytes < UnreliableLimit - 100)) return;
            flushTimer = 0f;
            var data = new byte[1 + pendingBytes];
            data[0] = (byte)Mathf.Min(pending.Count, 255);
            int at = 1;
            for (int i = 0; i < pending.Count && i < 255; i++)
            {
                var c = pending[i];
                data[at] = (byte)(c.Length & 255);
                data[at + 1] = (byte)(c.Length >> 8);
                System.Buffer.BlockCopy(c, 0, data, at + 2, c.Length);
                at += 2 + c.Length;
            }
            pending.Clear();
            pendingBytes = 0;
            if (IsServer) Forward(data); // хост говорит — сразу всем
            else if (data.Length <= UnreliableLimit) SubmitVoiceRpc(data);
            else SubmitBigVoiceRpc(data);
        }

        // Хост: дальше всем, кроме говорящего
        private void Forward(byte[] data)
        {
            if (data.Length <= UnreliableLimit) PlayVoiceRpc(data);
            else PlayBigVoiceRpc(data);
        }

        [Rpc(SendTo.Server, Delivery = RpcDelivery.Unreliable)]
        private void SubmitVoiceRpc(byte[] data, RpcParams rpcParams = default)
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return; // говорить можно только своей спичкой
            Forward(data);
        }

        [Rpc(SendTo.Server, Delivery = RpcDelivery.Reliable)]
        private void SubmitBigVoiceRpc(byte[] data, RpcParams rpcParams = default)
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            Forward(data);
        }

        // Всем, кроме говорящего (и хосту, если говорит не он)
        [Rpc(SendTo.NotOwner, Delivery = RpcDelivery.Unreliable)]
        private void PlayVoiceRpc(byte[] data) => Hear(data);

        [Rpc(SendTo.NotOwner, Delivery = RpcDelivery.Reliable)]
        private void PlayBigVoiceRpc(byte[] data) => Hear(data);

        private void Hear(byte[] data)
        {
            if (data == null || data.Length < 3) return;
            if (source == null) CreatePlayer();
            int count = data[0], at = 1;
            for (int i = 0; i < count && at + 2 <= data.Length; i++)
            {
                int length = data[at] | (data[at + 1] << 8);
                at += 2;
                if (length < 2 || at + length > data.Length) return; // битая пачка
                var chunk = new byte[length];
                System.Buffer.BlockCopy(data, at, chunk, 0, length);
                at += length;
                HearChunk(chunk);
            }
        }

        private void HearChunk(byte[] chunk)
        {
            float[] samples = Decode(chunk);
            if (samples == null || samples.Length == 0) return;
            PacketsHeard++;
            LastVoiceTime = Time.time;
            float sum = 0f;
            foreach (var s in samples) sum += s * s;
            Level = Mathf.Clamp01(Mathf.Sqrt(sum / samples.Length) * 4f);
            Push(samples);
        }

        // ---------- Слышим ----------

        private float[] Decode(byte[] data)
        {
            if (data[0] == CodecPcm16)
            {
                if (data.Length < 5) return null;
                int rate = data[1] | (data[2] << 8);
                // Частота пришла из сети: со странной (1 Гц) перегонка раздувала кусочек в десятки тысяч раз
                // у каждого слушателя. Тест-тон — 8 кГц, больше 48 кГц голоса не бывает
                if (rate < MinPcmRate || rate > MaxPcmRate) return null;
                int count = (data.Length - 3) / 2;
                var raw = new float[count];
                for (int i = 0; i < count; i++) raw[i] = (short)(data[3 + i * 2] | (data[4 + i * 2] << 8)) / 32768f;
                return Resample(raw, rate);
            }
            if (!SteamClient.IsValid) return null; // голос Steam без Steam не распаковать
            if (SteamUser.SampleRate != (uint)sampleRate) SteamUser.SampleRate = (uint)sampleRate;
            readStream.SetLength(0);
            readStream.Write(data, 1, data.Length - 1);
            readStream.Position = 0;
            pcmStream.SetLength(0);
            int bytes = SteamUser.DecompressVoice(readStream, data.Length - 1, pcmStream);
            if (bytes <= 0) return null;
            var buffer = pcmStream.GetBuffer();
            var result = new float[bytes / 2];
            for (int i = 0; i < result.Length; i++) result[i] = (short)(buffer[i * 2] | (buffer[i * 2 + 1] << 8)) / 32768f;
            return result;
        }

        // Простая перегонка частоты (тест-тон 8 кГц → частота проигрывания)
        private float[] Resample(float[] raw, int rate)
        {
            if (rate == sampleRate || rate <= 0) return raw;
            int count = Mathf.Max(1, Mathf.RoundToInt(raw.Length * (float)sampleRate / rate));
            var result = new float[count];
            for (int i = 0; i < count; i++)
            {
                float src = i * (float)rate / sampleRate;
                int a = Mathf.Min((int)src, raw.Length - 1), b = Mathf.Min(a + 1, raw.Length - 1);
                result[i] = Mathf.Lerp(raw[a], raw[b], src - a);
            }
            return result;
        }

        private void Push(float[] samples)
        {
            lock (ringLock)
            {
                foreach (var s in samples)
                {
                    if (ringCount == ring.Length) { ringRead = (ringRead + 1) % ring.Length; ringCount--; } // переполнение — выкидываем старое
                    ring[ringWrite] = s;
                    ringWrite = (ringWrite + 1) % ring.Length;
                    ringCount++;
                }
            }
        }

        // Звуковой поток: берём из буфера; кончился — тишина и снова копим startBuffer
        private void OnAudioRead(float[] data)
        {
            lock (ringLock)
            {
                if (!playing && ringCount >= startBuffer * sampleRate) playing = true;
                for (int i = 0; i < data.Length; i++)
                {
                    if (playing && ringCount > 0)
                    {
                        data[i] = ring[ringRead];
                        ringRead = (ringRead + 1) % ring.Length;
                        ringCount--;
                    }
                    else
                    {
                        data[i] = 0f;
                        playing = false;
                    }
                }
            }
        }

        // Громкость и сторона — от своей спички до говорящей
        private void UpdateVolume()
        {
            if (source == null || !controller.Body.IsBuilt) return;
            var listener = LocalListener();
            float volume = 1f, pan = 0f;
            // Голосование «Предателя» — слышно всех, где бы ни стояли
            if (listener != null && listener != controller && !PushPals.Level.TraitorRound.EveryoneHears)
            {
                Vector2 from = listener.Body.Head.Body.position, to = controller.Body.Head.Body.position;
                float d = Vector2.Distance(from, to);
                volume = 1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(nearDistance, farDistance, d));
                pan = Mathf.Clamp((to.x - from.x) / farDistance * 2f, -maxPan, maxPan);
            }
            bool ghost = controller.IsGhost;
            if (echo != null) echo.enabled = ghost;
            source.volume = volume * VoiceSettings.FriendsVolume * (ghost ? ghostVolume : 1f);
            source.panStereo = pan;
        }

        // Своя спичка на этом ПК (по сети — одна)
        private static RagdollController LocalListener()
        {
            var manager = PlayerManager.Instance;
            if (manager == null) return null;
            foreach (var p in manager.Visible)
            {
                var no = p != null ? p.GetComponent<NetworkObject>() : null;
                if (no != null && no.IsSpawned && no.IsOwner && !p.IsDummy) return p.Ragdoll;
            }
            return null;
        }

        // «Звуковые волны» у головы, пока спичка говорит
        private void UpdateWaves()
        {
            if (!controller.Body.IsBuilt) return;
            if (waves == null)
            {
                waves = MatchVisual.NewChild(transform, "Voice Waves");
                waveArt = new SpriteRenderer[3];
                for (int i = 0; i < 3; i++)
                {
                    waveArt[i] = MatchVisual.AddPill(waves, 0.05f, 0.14f + i * 0.09f, new Color(1f, 1f, 1f, 0.9f), 45);
                    waveArt[i].transform.localPosition = new Vector3(0.12f + i * 0.09f, 0f, 0f);
                }
            }
            bool on = Speaking;
            waves.gameObject.SetActive(on);
            if (!on) return;
            var head = controller.Body.Head;
            waves.position = (Vector3)(head.Body.position + Vector2.right * (head.Width * 0.5f + 0.04f));
            for (int i = 0; i < waveArt.Length; i++)
            {
                float k = 0.5f + 0.5f * Mathf.Sin(Time.time * 14f - i * 1.3f);
                var c = waveArt[i].color;
                c.a = 0.35f + 0.6f * k;
                waveArt[i].color = c;
            }
        }
    }
}
