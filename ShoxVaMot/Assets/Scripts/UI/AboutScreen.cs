using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using Shatranj.Core;
using Shatranj.Visual;

namespace Shatranj.UI
{
    /// <summary>
    /// «Об игре»: описание, команда, ссылки, оценка, «поделиться», факты.
    /// Все данные — из Assets/Resources/AboutInfo.asset (меню «Shox va Mot → Об игре (контакты и команда)»).
    /// </summary>
    public class AboutScreen : UIScreen
    {
        Text fact;
        int versionTaps;
        float lastTap;

        protected override void Build()
        {
            var info = AboutInfo.Load();
            RectTransform content, footer;
            Page(Loc.T("menu.about"), out content, out footer);

            var top = UIKit.Rect(content, "top");
            UIKit.Layout(top, 230);
            var em = UIKit.Emblem(top, 170);
            UIKit.Place(em, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), Vector2.zero, new Vector2(170, 170));
            em.gameObject.AddComponent<Spin>().Speed = 8f;
            var ver = UIKit.Label(top, Loc.T("app.title") + "  ·  " + Loc.T("version") + " " + Application.version, 34, UIKit.Gold, TextAnchor.LowerCenter, FontStyle.Bold);
            ver.rectTransform.offsetMin = new Vector2(0, 0);
            // скрытая диагностика: 5 касаний по версии — состояние рекламы
            ver.raycastTarget = true;
            ver.gameObject.AddComponent<Button>().onClick.AddListener(VersionTapped);

            UIKit.Paragraph(content, Loc.T("about.desc"), 34, TextAnchor.UpperCenter);

            // команда
            var team = new List<TeamMember>();
            foreach (var m in info.team)
                if (m != null && !string.IsNullOrEmpty(m.name)) team.Add(m);
            if (team.Count > 0)
            {
                UIKit.Heading(content, Loc.T("about.team"), 46);
                foreach (var member in team)
                {
                    var row = UIKit.Rect(content, "member");
                    var bg = row.gameObject.AddComponent<Image>();
                    bg.sprite = UIKit.Round;
                    bg.type = Image.Type.Sliced;
                    bg.color = new Color(1, 1, 1, 0.05f);
                    UIKit.Layout(bg, 96);
                    var n = UIKit.Label(row, member.name, 38, UIKit.Ivory, TextAnchor.MiddleLeft, FontStyle.Bold);
                    n.rectTransform.offsetMin = new Vector2(32, 0);
                    var r = UIKit.Label(row, RoleText(member), 32, UIKit.Turq, TextAnchor.MiddleRight, FontStyle.Italic);
                    r.rectTransform.offsetMax = new Vector2(-32, 0);
                }
            }

            // ссылки: показываются только заполненные
            var links = new List<KeyValuePair<string, string>>();
            AddLink(links, "Instagram", info.instagram);
            AddLink(links, "Telegram", info.telegram);
            AddLink(links, "YouTube", info.youtube);
            AddLink(links, "TikTok", info.tiktok);
            AddLink(links, Loc.T("about.website"), info.website);
            if (AboutInfo.IsSet(info.email)) links.Add(new KeyValuePair<string, string>("E-mail", MailUrl(info.email)));
            if (links.Count > 0)
            {
                UIKit.Heading(content, Loc.T("about.contacts"), 46);
                const int perRow = 3;
                for (int i = 0; i < links.Count; i += perRow)
                {
                    var rowRt = UIKit.Rect(content, "links");
                    UIKit.Layout(rowRt, 112);
                    var h = UIKit.HList(rowRt.gameObject, 18f);
                    h.childForceExpandWidth = true;
                    for (int j = i; j < Mathf.Min(i + perRow, links.Count); j++)
                    {
                        string url = links[j].Value;
                        UIKit.Btn(rowRt, links[j].Key, () => Open(url), BtnStyle.Secondary, -1, 36);
                    }
                }
            }

            // оценка, «поделиться», политика конфиденциальности
            UIKit.Btn(content, Loc.T("about.rate"), Rate, BtnStyle.Primary, 108, 40);
            UIKit.Btn(content, Loc.T("about.share"), Share, BtnStyle.Secondary, 104, 38);
            if (AboutInfo.IsSet(info.privacyPolicyUrl))
            {
                string privacy = info.privacyPolicyUrl;
                UIKit.Btn(content, Loc.T("about.privacy"), () => Open(privacy), BtnStyle.Ghost, 96, 34);
            }

            // «А вы знаете?»
            UIKit.Heading(content, Loc.T("about.fact.t"), 46);
            fact = UIKit.Paragraph(content, "", 34, TextAnchor.UpperCenter);
            fact.color = UIKit.Turq;
            fact.fontStyle = FontStyle.Italic;

            var thanks = UIKit.Paragraph(content, "\n" + Loc.T("about.thanks"), 32, TextAnchor.UpperCenter);
            thanks.color = UIKit.Gold;

            UIKit.Btn(footer, Loc.T("common.back"), () => OnBack(), BtnStyle.Primary, -1);
        }

        static string RoleText(TeamMember m)
        {
            if (!string.IsNullOrEmpty(m.customRole)) return m.customRole;
            return Loc.T("about.role." + m.role.ToString().ToLowerInvariant());
        }

        static void AddLink(List<KeyValuePair<string, string>> list, string title, string url)
        {
            if (!AboutInfo.IsSet(url)) return;
            url = url.Trim();
            if (!url.Contains("://")) url = "https://" + url;
            list.Add(new KeyValuePair<string, string>(title, url));
        }

        static string MailUrl(string email)
        {
            email = email.Trim();
            return email.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase) ? email : "mailto:" + email;
        }

        public override void OnShow()
        {
            versionTaps = 0;
            fact.text = Loc.T("about.fact." + UnityEngine.Random.Range(0, 4));
        }

        void VersionTapped()
        {
            if (Time.unscaledTime - lastTap > 1.5f) versionTaps = 0;
            lastTap = Time.unscaledTime;
            if (++versionTaps < 5) return;
            versionTaps = 0;
            UI.Banner.Toast(AdsManager.Status, 6f);
        }

        void Open(string url)
        {
            if (!AboutInfo.IsSet(url))
            {
                UI.Banner.Toast(Loc.T("about.notset"));
                return;
            }
            Application.OpenURL(url);
        }

        static string StoreUrl { get { return "https://play.google.com/store/apps/details?id=" + AboutInfo.Load().StoreId; } }

        void Rate()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            Application.OpenURL("market://details?id=" + AboutInfo.Load().StoreId);
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
