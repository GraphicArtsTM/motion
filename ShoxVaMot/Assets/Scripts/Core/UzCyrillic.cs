using System.Collections.Generic;
using System.Text;

namespace Shatranj.Core
{
    /// <summary>
    /// Транслитерация узбекской латиницы в кириллицу (Ўзбекча): o' → ў, g' → ғ, sh → ш, ch → ч,
    /// yo/yu/ya → ё/ю/я, начальное e → э, q → қ, h → ҳ, x → х, апостроф → ъ.
    /// Теги разметки &lt;...&gt; и подстановки {0} не трогаются.
    /// </summary>
    public static class UzCyrillic
    {
        static readonly Dictionary<string, string> cache = new Dictionary<string, string>();

        static bool IsApostrophe(char c) { return c == '\'' || c == '’' || c == 'ʻ' || c == 'ʼ' || c == '`' || c == '‘'; }

        static bool IsLetter(char c) { return char.IsLetter(c); }

        public static string Convert(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            string cached;
            if (cache.TryGetValue(s, out cached)) return cached;

            var sb = new StringBuilder(s.Length);
            int i = 0;
            while (i < s.Length)
            {
                char c = s[i];
                // разметка и подстановки копируются как есть
                if (c == '<' || c == '{')
                {
                    char close = c == '<' ? '>' : '}';
                    int end = s.IndexOf(close, i);
                    if (end < 0) end = s.Length - 1;
                    sb.Append(s, i, end - i + 1);
                    i = end + 1;
                    continue;
                }
                if (!IsLetter(c))
                {
                    // апостроф после согласной (tutuq belgisi) — твёрдый знак
                    if (IsApostrophe(c) && i > 0 && IsLetter(s[i - 1]) && i + 1 < s.Length && IsLetter(s[i + 1])) sb.Append('ъ');
                    else sb.Append(c);
                    i++;
                    continue;
                }

                bool upper = char.IsUpper(c);
                bool nextUpper = i + 1 < s.Length && char.IsUpper(s[i + 1]);
                char lc = char.ToLowerInvariant(c);
                char n1 = i + 1 < s.Length ? char.ToLowerInvariant(s[i + 1]) : '\0';
                bool wordStart = i == 0 || !IsLetter(s[i - 1]) && !IsApostrophe(s[i - 1]);
                string outStr = null;
                int used = 1;

                if ((lc == 'o' || lc == 'g') && i + 1 < s.Length && IsApostrophe(s[i + 1]))
                {
                    outStr = lc == 'o' ? "ў" : "ғ";
                    used = 2;
                }
                else if (lc == 's' && n1 == 'h') { outStr = "ш"; used = 2; }
                else if (lc == 'c' && n1 == 'h') { outStr = "ч"; used = 2; }
                else if (lc == 'y' && (n1 == 'o' || n1 == 'u' || n1 == 'a' || n1 == 'e'))
                {
                    bool o2 = n1 == 'o' && i + 2 < s.Length && IsApostrophe(s[i + 2]);
                    if (!o2)
                    {
                        outStr = n1 == 'o' ? "ё" : n1 == 'u' ? "ю" : n1 == 'a' ? "я" : "е";
                        used = 2;
                    }
                }

                if (outStr == null)
                {
                    switch (lc)
                    {
                        case 'a': outStr = "а"; break;
                        case 'b': outStr = "б"; break;
                        case 'c': outStr = "ц"; break;
                        case 'd': outStr = "д"; break;
                        case 'e': outStr = wordStart ? "э" : "е"; break;
                        case 'f': outStr = "ф"; break;
                        case 'g': outStr = "г"; break;
                        case 'h': outStr = "ҳ"; break;
                        case 'i': outStr = "и"; break;
                        case 'j': outStr = "ж"; break;
                        case 'k': outStr = "к"; break;
                        case 'l': outStr = "л"; break;
                        case 'm': outStr = "м"; break;
                        case 'n': outStr = "н"; break;
                        case 'o': outStr = "о"; break;
                        case 'p': outStr = "п"; break;
                        case 'q': outStr = "қ"; break;
                        case 'r': outStr = "р"; break;
                        case 's': outStr = "с"; break;
                        case 't': outStr = "т"; break;
                        case 'u': outStr = "у"; break;
                        case 'v': outStr = "в"; break;
                        case 'w': outStr = "в"; break;
                        case 'x': outStr = "х"; break;
                        case 'y': outStr = "й"; break;
                        case 'z': outStr = "з"; break;
                        default: outStr = c.ToString(); upper = false; break;
                    }
                }

                // «Sh» → «Ш», «SH» → «Ш»: регистр берём с первой буквы
                if (upper) outStr = outStr.ToUpperInvariant();
                else if (used == 1 && nextUpper && char.IsUpper(c)) outStr = outStr.ToUpperInvariant();
                sb.Append(outStr);
                i += used;
            }
            string r = sb.ToString();
            cache[s] = r;
            return r;
        }
    }
}
