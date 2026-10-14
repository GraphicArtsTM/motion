using UnityEngine;
using UnityEngine.UI;
using Shatranj.Core;
using Shatranj.Visual;

namespace Shatranj.UI
{
    /// <summary>«Об игре»: описание, команда, контакты (Instagram, Telegram, e-mail), оценка, «поделиться», факты.</summary>
    public class AboutScreen : UIScreen
    {
        Text fact;

        protected override void Build()
        {
            RectTransform content, footer;
            Page(Loc.T("menu.about"), out content, out footer);

            var top = UIKit.Rect(content, "top");
            UIKit.Layout(top, 230);
            var em = UIKit.Emblem(top, 170);
            UIKit.Place(em, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), Vector2.zero, new Vector2(170, 170));
            em.gameObject.AddComponent<Spin>().Speed = 8f;
            var ver = UIKit.Label(top, Loc.T("app.title") + "  ·  " + Loc.T("version") + " " + Application.version, 34, UIKit.Gold, TextAnchor.LowerCenter, FontStyle.Bold);
            ver.rectTransform.offsetMin = new Vector2(0, 0);

            UIKit.Paragraph(content, Loc.T("about.desc"), 34, TextAnchor.UpperCenter);

            // команда
            UIKit.Heading(content, Loc.T("about.team"), 46);
            foreach (var member in AboutConfig.Team)
            {
                var row = UIKit.Rect(content, "member");
                var bg = row.gameObject.AddComponent<Image>();
                bg.sprite = UIKit.Round;
                bg.type = Image.Type.Sliced;
                bg.color = new Color(1, 1, 1, 0.05f);
                UIKit.Layout(bg, 96);
                var n = UIKit.Label(row, member[0], 38, UIKit.Ivory, TextAnchor.MiddleLeft, FontStyle.Bold);
                n.rectTransform.offsetMin = new Vector2(32, 0);
                var r = UIKit.Label(row, Loc.T(member[1]), 32, UIKit.Turq, TextAnchor.MiddleRight, FontStyle.Italic);
                r.rectTransform.offsetMax = new Vector2(-32, 0);
            }

            // контакты
            UIKit.Heading(content, Loc.T("about.contacts"), 46);
            var links = UIKit.Rect(content, "links");
            UIKit.Layout(links, 112);
            var h = UIKit.HList(links.gameObject, 18f);
            h.childForceExpandWidth = true;
            UIKit.Btn(links, "Instagram", () => Open(AboutConfig.Instagram), BtnStyle.Secondary, -1, 36);
            UIKit.Btn(links, "Telegram", () => Open(AboutConfig.Telegram), BtnStyle.Secondary, -1, 36);
            UIKit.Btn(links, "E-mail", () => Open(AboutConfig.IsSet(AboutConfig.Email) ? "mailto:" + AboutConfig.Email : ""), BtnStyle.Secondary, -1, 36);

            // оценка, «поделиться», политика конфиденциальности
            UIKit.Btn(content, Loc.T("about.rate"), Rate, BtnStyle.Primary, 108, 40);
            UIKit.Btn(content, Loc.T("about.share"), Share, BtnStyle.Secondary, 104, 38);
            UIKit.Btn(content, Loc.T("about.privacy"), () => Open(AboutConfig.PrivacyPolicyUrl), BtnStyle.Ghost, 96, 34);

            // «А вы знаете?»
            UIKit.Heading(content, Loc.T("about.fact.t"), 46);
            fact = UIKit.Paragraph(content, "", 34, TextAnchor.UpperCenter);
            fact.color = UIKit.Turq;
            fact.fontStyle = FontStyle.Italic;

            UIKit.Heading(content, Loc.T("about.tech.t"), 46);
            UIKit.Paragraph(content, Loc.T("about.tech"), 32, TextAnchor.UpperCenter);
            var thanks = UIKit.Paragraph(content, "\n" + Loc.T("about.thanks"), 32, TextAnchor.UpperCenter);
            thanks.color = UIKit.Gold;

            UIKit.Btn(footer, Loc.T("common.back"), () => OnBack(), BtnStyle.Primary, -1);
        }

        public override void OnShow()
        {
            fact.text = Loc.T("about.fact." + Random.Range(0, 4));
        }

        void Open(string url)
        {
            if (!AboutConfig.IsSet(url) || url == "mailto:")
            {
                UI.Banner.Toast(Loc.T("about.notset"));
                return;
            }
            Application.OpenURL(url);
        }

        static string StoreUrl { get { return "https://play.google.com/store/apps/details?id=" + AboutConfig.PlayStoreId; } }

        void Rate()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            Application.OpenURL("market://details?id=" + AboutConfig.PlayStoreId);
#else
            Application.OpenURL(StoreUrl);
#endif
        }

        void Share()
        {
            string url = "https://t.me/share/url?url=" + UnityEngine.Networking.UnityWebRequest.EscapeURL(StoreUrl) +
                         "&text=" + UnityEngine.Networking.UnityWebRequest.EscapeURL(Loc.T("about.share.text"));
            Application.OpenURL(url);
        }

        public override bool OnBack()
        {
            UI.Show(UI.Main);
            return true;
        }
    }
}
