using System.Collections.Generic;
using PushPals.Level;
using PushPals.Ragdoll;
using PushPals.Ragdoll.Visual;
using UnityEngine;

namespace PushPals.Players
{
    /// <summary>Метка по сети (задаёт сетевой модуль): клиент → хост → всем.</summary>
    public interface IRemotePing
    {
        /// <summary>Показать метку у всех; false — сеть не готова (тогда только у себя).</summary>
        bool SendPing(Vector2 at);
    }

    /// <summary>
    /// Метка «сюда» (действие Ping: R3 / колёсико мыши): булавка цвета игрока там, куда он показал прицелом
    /// (стиком или мышью), круги по месту и надпись «Сюда!». Живёт несколько секунд; новая метка того же игрока
    /// заменяет прежнюю. По сети её видят все (решает хост — чужой спичкой метку не поставить).
    /// </summary>
    public class PingMarker : MonoBehaviour
    {
        private const float Life = 4f, FadeTime = 0.6f, Cooldown = 0.35f, PinHeight = 0.9f, DropTime = 0.25f;
        private const int Order = 60; // поверх уровня и спичек

        private static readonly Dictionary<RagdollController, PingMarker> active = new Dictionary<RagdollController, PingMarker>();
        private static readonly Dictionary<RagdollController, float> lastPing = new Dictionary<RagdollController, float>();

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStatics() { active.Clear(); lastPing.Clear(); }

        private RagdollController owner;
        private Color color;
        private float age;
        private Transform pin;
        private SpriteRenderer pinArt, dot, ripple;
        private string label;

        /// <summary>Игрок показал «сюда» — с этого ПК (по сети — у всех через хоста).</summary>
        public static void Request(RagdollController who, Vector2 at)
        {
            if (who == null) return;
            float last;
            if (lastPing.TryGetValue(who, out last) && Time.unscaledTime - last < Cooldown) return;
            lastPing[who] = Time.unscaledTime;
            if (Online.IsActive)
            {
                var remote = who.GetComponent<IRemotePing>();
                if (remote != null && remote.SendPing(at)) return;
            }
            Show(who, at);
        }

        /// <summary>Показать метку игрока who в точке at (на этом ПК).</summary>
        public static void Show(RagdollController who, Vector2 at)
        {
            if (who == null) return;
            PingMarker old;
            if (active.TryGetValue(who, out old) && old != null) Destroy(old.gameObject);
            var go = new GameObject("Ping");
            go.transform.position = at;
            var marker = go.AddComponent<PingMarker>();
            marker.Build(who);
            active[who] = marker;
            PushPals.Audio.Sfx.Play("pluck", at, 0.8f, 0.05f);
        }

        private void Build(RagdollController who)
        {
            owner = who;
            var player = who.GetComponent<Player>();
            color = player != null ? player.Color : Color.white;
            label = PushPals.UI.Loc.T("ping.here");

            // Круги по месту: плоский эллипс цвета игрока расходится и тает
            ripple = MatchVisual.AddEllipse(transform, new Vector2(1f, 0.35f), color, Order);

            // Булавка: остриё — в точке, кружок — цветом игрока (видно, кто показал)
            pin = MatchVisual.NewChild(transform, "Pin");
            pinArt = new GameObject("Art").AddComponent<SpriteRenderer>();
            pinArt.transform.SetParent(pin, false);
            pinArt.sprite = PushPals.UI.UiSprites.Get("ic_ping");
            pinArt.sortingOrder = Order + 1;
            float height = PinHeight;
            if (pinArt.sprite != null)
            {
                float scale = PinHeight / Mathf.Max(0.01f, pinArt.sprite.bounds.size.y);
                pinArt.transform.localScale = Vector3.one * scale;
                // Центр спрайта — посередине: поднять, чтобы остриё (низ) было в точке
                pinArt.transform.localPosition = new Vector3(0f, PinHeight * 0.5f, 0f);
                dot = MatchVisual.AddEllipse(pin, Vector2.one * PinHeight * 0.3f, color, Order + 2);
                dot.transform.localPosition = new Vector3(0f, PinHeight * 0.7f, 0f);
            }
            else
            {
                // Листы интерфейса не нарезаны — звёздочка цвета игрока
                pinArt.sprite = MatchArt.Star;
                pinArt.color = color;
                pinArt.transform.localScale = Vector3.one * PinHeight * 0.6f;
                pinArt.transform.localPosition = new Vector3(0f, PinHeight * 0.4f, 0f);
                height = PinHeight * 0.8f;
            }
            pin.localPosition = Vector3.up * 0.6f; // падает сверху
            labelHeight = height + 0.35f;
        }

        private float labelHeight;

        private void Update()
        {
            age += Time.deltaTime;
            if (age >= Life || owner == null) { Destroy(gameObject); return; }
            float alpha = Mathf.Clamp01((Life - age) / FadeTime);
            // Булавка падает с отскоком, потом чуть покачивается
            float drop = Mathf.Clamp01(age / DropTime);
            float bounce = drop < 1f ? (1f - drop) * (1f - drop) * 0.6f : Mathf.Abs(Mathf.Sin((age - DropTime) * 6f)) * 0.08f * Mathf.Exp(-(age - DropTime) * 2f);
            pin.localPosition = new Vector3(0f, bounce + Mathf.Sin(age * 3f) * 0.03f, 0f);
            SetAlpha(pinArt, alpha);
            SetAlpha(dot, alpha);
            // Круги: раз в секунду расходятся заново
            float wave = Mathf.Repeat(age, 1f);
            float s = 0.4f + wave * 1.2f; // эллипс лёжа на полу: ширина : высота = 1 : 0,35 (AddEllipse задаёт размер масштабом)
            ripple.transform.localScale = new Vector3(s, s * 0.35f, 1f);
            var c = color;
            c.a = (1f - wave) * 0.55f * alpha;
            ripple.color = c;
        }

        private static void SetAlpha(SpriteRenderer sr, float alpha)
        {
            if (sr == null) return;
            var c = sr.color;
            c.a = alpha;
            sr.color = c;
        }

        // «Сюда!» над булавкой — первые секунды
        private void OnGUI()
        {
            if (PushPals.UI.UiScreen.BlocksGame || age > Life - FadeTime) return;
            float alpha = Mathf.Clamp01((Life - FadeTime - age) / 0.5f);
            WorldLabel.Draw(transform.position + Vector3.up * labelHeight, label, alpha, 14, -1, 110f);
        }

        private void OnDestroy()
        {
            if (owner != null)
            {
                PingMarker current;
                if (active.TryGetValue(owner, out current) && current == this) active.Remove(owner);
            }
        }
    }
}
