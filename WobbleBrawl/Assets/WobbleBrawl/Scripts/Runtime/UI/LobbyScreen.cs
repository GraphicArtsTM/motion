using UnityEngine;
using UnityEngine.UI;

namespace WobbleBrawl
{
    /// <summary>Drop-in lobby: up to four humans join from any device; bots fill the rest.</summary>
    public sealed class LobbyScreen
    {
        public const int MaxHumans = 4;
        public readonly GameObject root;
        readonly GameManager gm;
        readonly MenuList menu;
        readonly Text title, description, joinHint;
        readonly Image[] cards = new Image[MaxHumans];
        readonly Image[] cardAccents = new Image[MaxHumans];
        readonly Text[] cardNames = new Text[MaxHumans];
        readonly Text[] cardInfo = new Text[MaxHumans];

        public LobbyScreen(Transform canvas, GameManager gm)
        {
            this.gm = gm;
            root = UIKit.Stretch(canvas, "Lobby").gameObject;
            UIKit.Fill(root.transform, new Color(0.04f, 0.03f, 0.08f, 0.55f));

            title = UIKit.Label(root.transform, "", 84, Palette.UiAccent, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), new Vector2(0, -90f), new Vector2(1600f, 110f));
            description = UIKit.Label(root.transform, "", 28, Palette.UiText, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), new Vector2(0, -170f), new Vector2(1500f, 60f), true, FontStyle.Normal);

            for (int i = 0; i < MaxHumans; i++)
            {
                var pos = new Vector2(-555f + i * 370f, 130f);
                cards[i] = UIKit.Card(root.transform, Color.gray, new Vector2(0.5f, 0.5f), pos, new Vector2(340f, 230f));
                cardAccents[i] = cards[i].transform.Find("Accent").GetComponent<Image>();
                cardNames[i] = UIKit.Label(cards[i].transform, "", 40, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), new Vector2(0, -55f), new Vector2(320f, 60f));
                cardInfo[i] = UIKit.Label(cards[i].transform, "", 22, Palette.UiDim, TextAnchor.UpperCenter, new Vector2(0.5f, 0.5f), new Vector2(0, -40f), new Vector2(320f, 130f), false, FontStyle.Normal);
            }

            joinHint = UIKit.Label(root.transform, "", 24, Palette.UiDim, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, -20f), new Vector2(1700f, 60f), false, FontStyle.Normal);

            menu = new MenuList(root.transform, new Vector2(0.5f, 0.5f), new Vector2(0, -70f), 900f, 56f, 36);
            menu.Add(() => "Арена: " + ArenaCatalog.BrawlTitles[gm.Config.arenaIndex], null,
                d => gm.Config.arenaIndex = (gm.Config.arenaIndex + d + ArenaCatalog.BrawlCount) % ArenaCatalog.BrawlCount,
                () => gm.Config.mode != ModeKind.Climb);
            menu.Add(() => "Ботов: " + gm.Config.botCount, null,
                d => gm.Config.botCount = Mathf.Clamp(gm.Config.botCount + d, 0, 6),
                () => gm.Config.mode != ModeKind.Climb);
            menu.Add(() => "Сложность ботов: " + SkillName(gm.Config.botSkill), null,
                d => gm.Config.botSkill = (BotSkill)(((int)gm.Config.botSkill + d + 3) % 3),
                () => gm.Config.mode != ModeKind.Climb && gm.Config.botCount > 0);
            menu.Add(() => "Побед для победы в матче: " + gm.Config.roundsToWin, null,
                d => gm.Config.roundsToWin = Mathf.Clamp(gm.Config.roundsToWin + d, 1, 7),
                () => gm.Config.mode == ModeKind.Brawl);
            menu.Add(() => "НАЧАТЬ!", gm.StartMatch);
            menu.Add(() => "НАЗАД", gm.BackToTitle);
        }

        static string SkillName(BotSkill s) => s == BotSkill.Easy ? "лёгкие" : s == BotSkill.Hard ? "злые" : "нормальные";

        public void Show(bool on)
        {
            root.SetActive(on);
            if (!on) return;
            var mode = GameMode.Create(gm.Config.mode);
            title.text = mode.Title;
            description.text = mode.Description;
            menu.Reset();
        }

        public void Tick(MenuNav nav)
        {
            menu.Tick(nav);
            var humans = gm.Lobby;
            for (int i = 0; i < MaxHumans; i++)
            {
                if (i < humans.Count)
                {
                    var p = humans[i];
                    cards[i].color = Palette.UiPanel;
                    cardAccents[i].color = p.color;
                    cardNames[i].text = p.name;
                    cardNames[i].color = p.color;
                    cardInfo[i].text = p.slot.Label + "\nШляпа: " + Hats.Name(p.hat) +
                        "\n\n<color=#FFFFFF88>удар — шляпа · " + ColorKey(p.slot) + " — цвет</color>";
                }
                else
                {
                    cards[i].color = new Color(0.1f, 0.09f, 0.14f, 0.7f);
                    cardAccents[i].color = new Color(1f, 1f, 1f, 0.15f);
                    cardNames[i].text = "Свободно";
                    cardNames[i].color = Palette.UiDim;
                    float blink = 0.5f + 0.5f * Mathf.Sin(Time.unscaledTime * 4f + i);
                    cardInfo[i].text = "<color=#FFFFFF" + ((int)(blink * 200 + 55)).ToString("X2") + ">Нажми, чтобы войти</color>";
                }
            }

            var sb = new System.Text.StringBuilder("Войти: ");
            bool first = true;
            foreach (var s in gm.Input.Slots)
            {
                if (!s.Connected || gm.IsJoined(s)) continue;
                if (!first) sb.Append("   ·   ");
                sb.Append("<color=#FFC733>").Append(s.JoinHint).Append("</color> ").Append(s.Label);
                first = false;
            }
            if (first) sb.Length = 0;
            sb.Append("\nВыйти из слота: BACKSPACE / DELETE / SELECT");
            joinHint.text = sb.ToString();
        }

        static string ColorKey(InputSlot s)
        {
            if (s is KeyboardMouseSlot) return "Q";
            if (s is KeyboardArrowsSlot) return "P";
            return "Y";
        }
    }
}
