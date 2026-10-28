using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Xml;
using PushPals.UI;
using TMPro;
using UnityEditor;
using UnityEditor.U2D.Sprites;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.TextCore.LowLevel;
using UnityEngine.UI;

namespace PushPals.EditorTools
{
    /// <summary>
    /// Набор интерфейса (Этап 17.3). Меню: PushPals → Интерфейс → Собрать набор UI. Делает по порядку:
    /// шрифты TextMeshPro с кириллицей (Rubik — текст, Lora — заголовки; статичный атлас + динамический запас),
    /// нарезку подсказок кнопок Kenney по их XML (Resources/UI/InputPrompts), тему (Resources/UI/UiTheme)
    /// и 16 префабов в Assets/Prefabs/UI. Префабы ПЕРЕЗАПИСЫВАЮТСЯ — правки делать здесь, в коде.
    /// Размеры — в пикселях холста 1920×1080.
    /// </summary>
    public static class UiKitBuilder
    {
        private const string FontDir = "Assets/Art/Fonts/";
        private const string PromptDir = "Assets/Art/InputPrompts/";
        private const string PrefabDir = "Assets/Prefabs/UI/";
        private const string ResourceDir = "Assets/Resources/UI/";
        private const string ControlsPath = "Assets/Settings/PushPalsControls.inputactions";

        // Латиница, кириллица, знаки препинания и стрелки — всё, что пишем в игре
        private static string Charset
        {
            get
            {
                var sb = new StringBuilder();
                for (char c = ' '; c <= '~'; c++) sb.Append(c);
                for (char c = 'А'; c <= 'я'; c++) sb.Append(c);
                sb.Append("ЁёІіЇїЄєЎў«»—–…№•×·©®™°±€₽“”„‘’"); // стрелок и галочки в шрифтах нет — для них иконки
                return sb.ToString();
            }
        }

        [MenuItem("PushPals/Интерфейс/Собрать набор UI (шрифты, подсказки, префабы)")]
        public static string BuildAll()
        {
            var log = new StringBuilder();
            log.AppendLine(BuildFonts());
            log.AppendLine(BuildPrompts());
            log.AppendLine(BuildTheme());
            log.AppendLine(BuildPrefabs());
            AssetDatabase.SaveAssets();
            Debug.Log(log.ToString());
            return log.ToString();
        }

        // ---------- Шрифты ----------

        public static string BuildFonts()
        {
            var rubik = AssetDatabase.LoadAssetAtPath<Font>("Assets/Resources/Fonts/Rubik.ttf");
            var lora = AssetDatabase.LoadAssetAtPath<Font>(FontDir + "Lora-SemiBold.ttf");
            if (rubik == null || lora == null) return "Шрифты: нет Rubik.ttf или Lora-SemiBold.ttf";
            var bodyFallback = MakeFont(rubik, FontDir + "Rubik Dynamic.asset", true, null);
            var body = MakeFont(rubik, FontDir + "Rubik SDF.asset", false, bodyFallback);
            var heading = MakeFont(lora, FontDir + "Lora SemiBold SDF.asset", false, body);
            // Шрифт по умолчанию у TextMeshPro — наш (новые надписи сразу с кириллицей)
            var settings = AssetDatabase.LoadAssetAtPath<TMP_Settings>("Assets/TextMesh Pro/Resources/TMP Settings.asset");
            if (settings != null)
            {
                var so = new SerializedObject(settings);
                so.FindProperty("m_defaultFontAsset").objectReferenceValue = body;
                so.ApplyModifiedPropertiesWithoutUndo();
            }
            return "Шрифты: " + body.name + " (" + body.characterTable.Count + " знаков), " + heading.name + " (" + heading.characterTable.Count + ")";
        }

        // Статичный — атлас заполняется набором Charset один раз; динамический — добирает редкие знаки в игре
        private static TMP_FontAsset MakeFont(Font font, string path, bool dynamic, TMP_FontAsset fallback)
        {
            var old = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(path);
            if (old != null) AssetDatabase.DeleteAsset(path);
            var fa = TMP_FontAsset.CreateFontAsset(font, 72, 8, GlyphRenderMode.SDFAA, dynamic ? 512 : 2048, dynamic ? 512 : 2048,
                AtlasPopulationMode.Dynamic, dynamic);
            fa.name = Path.GetFileNameWithoutExtension(path);
            AssetDatabase.CreateAsset(fa, path);
            fa.atlasTexture.name = fa.name + " Atlas";
            AssetDatabase.AddObjectToAsset(fa.atlasTexture, fa);
            fa.material.name = fa.name + " Material";
            AssetDatabase.AddObjectToAsset(fa.material, fa);
            if (!dynamic)
            {
                string missing;
                fa.TryAddCharacters(Charset, out missing);
                fa.atlasPopulationMode = AtlasPopulationMode.Static;
                if (!string.IsNullOrEmpty(missing)) Debug.Log("[PushPals] В шрифте " + font.name + " нет знаков: " + missing);
            }
            if (fallback != null) fa.fallbackFontAssetTable = new List<TMP_FontAsset> { fallback };
            EditorUtility.SetDirty(fa);
            AssetDatabase.SaveAssets();
            return fa;
        }

        // ---------- Подсказки кнопок (Kenney) ----------

        public static string BuildPrompts()
        {
            var all = new List<Sprite>();
            foreach (var name in new[] { "keyboard", "xbox", "playstation" })
            {
                string png = PromptDir + "prompts_" + name + ".png", xml = PromptDir + "prompts_" + name + ".xml";
                if (!File.Exists(png) || !File.Exists(xml)) return "Подсказки: нет " + png;
                SliceByXml(png, xml);
                foreach (var o in AssetDatabase.LoadAllAssetsAtPath(png)) { var s = o as Sprite; if (s != null) all.Add(s); }
            }
            Directory.CreateDirectory(ResourceDir);
            string path = ResourceDir + "InputPrompts.asset";
            var set = AssetDatabase.LoadAssetAtPath<InputPrompts>(path);
            if (set == null) { set = ScriptableObject.CreateInstance<InputPrompts>(); AssetDatabase.CreateAsset(set, path); }
            set.sprites = all.ToArray();
            EditorUtility.SetDirty(set);
            return "Подсказки кнопок: " + all.Count + " картинок";
        }

        // Лист Kenney: прямоугольники и имена — из его XML (SubTexture name x y width height, y — снизу, как в Unity)
        private static void SliceByXml(string png, string xmlPath)
        {
            AssetDatabase.ImportAsset(png, ImportAssetOptions.ForceUpdate);
            var importer = (TextureImporter)AssetImporter.GetAtPath(png);
            importer.textureType = TextureImporterType.Sprite;
            importer.spriteImportMode = SpriteImportMode.Multiple;
            importer.mipmapEnabled = false;
            importer.alphaIsTransparency = true;
            importer.spritePixelsPerUnit = 128f;
            importer.maxTextureSize = 4096;
            importer.textureCompression = TextureImporterCompression.CompressedHQ;
            importer.SaveAndReimport();
            var doc = new XmlDocument();
            doc.Load(xmlPath);
            var factory = new SpriteDataProviderFactories();
            factory.Init();
            var dp = factory.GetSpriteEditorDataProviderFromObject(importer);
            dp.InitSpriteEditorDataProvider();
            var oldIds = new Dictionary<string, GUID>();
            foreach (var r in dp.GetSpriteRects()) oldIds[r.name] = r.spriteID;
            var rects = new List<SpriteRect>();
            foreach (XmlNode n in doc.SelectNodes("//SubTexture"))
            {
                string name = n.Attributes["name"].Value;
                if (name.EndsWith("_outline")) continue; // контурные варианты не нужны
                float x = float.Parse(n.Attributes["x"].Value), y = float.Parse(n.Attributes["y"].Value);
                float w = float.Parse(n.Attributes["width"].Value), h = float.Parse(n.Attributes["height"].Value);
                GUID id;
                rects.Add(new SpriteRect
                {
                    name = name,
                    rect = new Rect(x, y, w, h), // у Kenney y в XML — снизу (проверено: на месте keyboard_enter иначе Q)
                    alignment = SpriteAlignment.Center,
                    pivot = new Vector2(0.5f, 0.5f),
                    spriteID = oldIds.TryGetValue(name, out id) ? id : GUID.Generate(),
                });
            }
            dp.SetSpriteRects(rects.ToArray());
            var ids = dp.GetDataProvider<ISpriteNameFileIdDataProvider>();
            if (ids != null)
            {
                var pairs = new List<SpriteNameFileIdPair>();
                foreach (var r in rects) pairs.Add(new SpriteNameFileIdPair(r.name, r.spriteID));
                ids.SetNameFileIdPairs(pairs);
            }
            dp.Apply();
            importer.SaveAndReimport();
        }

        // ---------- Тема ----------

        public static string BuildTheme()
        {
            Directory.CreateDirectory(ResourceDir);
            string path = ResourceDir + "UiTheme.asset";
            var theme = AssetDatabase.LoadAssetAtPath<UiTheme>(path);
            if (theme == null) { theme = ScriptableObject.CreateInstance<UiTheme>(); AssetDatabase.CreateAsset(theme, path); }
            theme.body = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(FontDir + "Rubik SDF.asset");
            theme.heading = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>(FontDir + "Lora SemiBold SDF.asset");
            theme.cursors = AssetDatabase.LoadAssetAtPath<CursorSet>("Assets/Data/UI/Cursors.asset");
            theme.controls = AssetDatabase.LoadAssetAtPath<InputActionAsset>(ControlsPath);
            theme.menuBackground = AssetDatabase.LoadAssetAtPath<Sprite>("Assets/Art/UI/Backgrounds/bg_main_menu.png");
            theme.menuBackgroundBlur = AssetDatabase.LoadAssetAtPath<Sprite>("Assets/Art/UI/Backgrounds/bg_main_menu_blur.png");
            theme.worldMap = AssetDatabase.LoadAssetAtPath<Sprite>("Assets/Art/UI/Backgrounds/bg_world_map.png");
            var loading = new List<Sprite>();
            foreach (var guid in AssetDatabase.FindAssets("bg_loading_ t:Sprite", new[] { "Assets/Art/UI/Backgrounds" }))
            {
                string file = AssetDatabase.GUIDToAssetPath(guid);
                if (!file.Contains("_blur")) loading.Add(AssetDatabase.LoadAssetAtPath<Sprite>(file));
            }
            theme.loadingBackgrounds = loading.ToArray();
            EditorUtility.SetDirty(theme);
            AssetDatabase.SaveAssets();
            return "Тема: " + path;
        }

        // ---------- Префабы ----------

        private static UiTheme Theme => AssetDatabase.LoadAssetAtPath<UiTheme>(ResourceDir + "UiTheme.asset");

        public static string BuildPrefabs()
        {
            Directory.CreateDirectory(PrefabDir);
            var controls = AssetDatabase.LoadAssetAtPath<InputActionAsset>(ControlsPath);
            var names = new List<string>();
            var primary = Save(Button("PrimaryButton", "btn_primary", Theme.inkLight), names);
            var secondary = Save(Button("SecondaryButton", "btn_secondary", Theme.ink), names);
            Save(IconButton(), names);
            Save(MenuListItem(), names);
            Save(ToggleSwitch("Toggle", "toggle_off", "toggle_on", new Vector2(120f, 56f)), names);
            Save(ToggleSwitch("Checkbox", "checkbox_off", "checkbox_on", new Vector2(56f, 56f)), names);
            Save(SliderBar(), names);
            Save(Dropdown(), names);
            Save(KeybindRowPrefab(controls), names);
            Save(Dialog(primary, secondary), names);
            Save(Tabs(), names);
            Save(TooltipPrefab(), names);
            Save(LevelCardPrefab(), names);
            Save(PlayerBadgePrefab(), names);
            Save(BurnBarPrefab(), names);
            Save(CounterPrefab(), names);
            Save(CountdownPrefab(), names);
            // Реестр для экранов, собираемых в игре (UiPrefabs.Spawn)
            string reg = ResourceDir + "UiPrefabs.asset";
            var set = AssetDatabase.LoadAssetAtPath<UiPrefabs>(reg);
            if (set == null) { set = ScriptableObject.CreateInstance<UiPrefabs>(); AssetDatabase.CreateAsset(set, reg); }
            var list = new List<GameObject>();
            foreach (var n in names) list.Add(AssetDatabase.LoadAssetAtPath<GameObject>(PrefabDir + n + ".prefab"));
            set.prefabs = list.ToArray();
            EditorUtility.SetDirty(set);
            return "Префабы (" + names.Count + "): " + string.Join(", ", names.ToArray());
        }

        private static GameObject Save(GameObject go, List<string> names)
        {
            string path = PrefabDir + go.name + ".prefab";
            var prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
            Object.DestroyImmediate(go);
            names.Add(prefab.name);
            return prefab;
        }

        private static GameObject Root(string name, Vector2 size)
        {
            var go = new GameObject(name, typeof(RectTransform));
            ((RectTransform)go.transform).sizeDelta = size;
            return go;
        }

        private static Image Sliced(Transform parent, string sprite, string name = null)
        {
            var img = UiFactory.Image(parent, sprite, true, name);
            UiRoot.Stretch(img.rectTransform);
            return img;
        }

        private static TextMeshProUGUI Label(Transform parent, string key, float size, Color color, bool heading)
        {
            var t = UiFactory.LocText(parent, key, size, color, heading);
            if (Theme != null) t.font = heading ? Theme.heading : Theme.body;
            UiRoot.Stretch(t.rectTransform);
            return t;
        }

        // Кнопка: корень (Button) → Visual (картинка с 4 состояниями, двигает UiButtonFx) → Label
        private static GameObject Button(string name, string sprite, Color ink)
        {
            var go = Root(name, new Vector2(380f, 86f));
            var visual = Sliced(go.transform, sprite + "_normal", "Visual");
            visual.raycastTarget = true;
            var label = Label(visual.transform, "ui.ok", 34f, ink, false);
            label.fontStyle = FontStyles.Bold;
            label.rectTransform.offsetMin = new Vector2(24f, 6f);
            label.rectTransform.offsetMax = new Vector2(-24f, -2f);
            label.enableAutoSizing = true;
            label.fontSizeMin = 20f;
            label.fontSizeMax = 34f;
            var b = go.AddComponent<Button>();
            b.targetGraphic = visual;
            b.transition = Selectable.Transition.SpriteSwap;
            b.spriteState = new SpriteState
            {
                highlightedSprite = UiSprites.Get(sprite + "_hover"),
                selectedSprite = UiSprites.Get(sprite + "_hover"),
                pressedSprite = UiSprites.Get(sprite + "_pressed"),
                disabledSprite = UiSprites.Get(sprite + "_disabled"),
            };
            go.AddComponent<UiButtonFx>();
            return go;
        }

        private static GameObject IconButton()
        {
            var go = Root("IconButton", new Vector2(96f, 96f));
            var visual = Sliced(go.transform, "btn_square", "Visual");
            visual.raycastTarget = true;
            var icon = UiFactory.Image(visual.transform, "ic_settings", false, "Icon");
            UiRoot.Stretch(icon.rectTransform);
            icon.rectTransform.offsetMin = new Vector2(16f, 16f);
            icon.rectTransform.offsetMax = new Vector2(-16f, -16f);
            var b = go.AddComponent<Button>();
            b.targetGraphic = visual;
            b.transition = Selectable.Transition.ColorTint;
            b.colors = Tints();
            go.AddComponent<UiButtonFx>();
            return go;
        }

        private static ColorBlock Tints()
        {
            var c = ColorBlock.defaultColorBlock;
            c.normalColor = new Color(0.92f, 0.92f, 0.92f);
            c.highlightedColor = Color.white;
            c.selectedColor = Color.white;
            c.pressedColor = new Color(0.8f, 0.8f, 0.8f);
            c.disabledColor = new Color(0.6f, 0.6f, 0.6f, 0.6f);
            c.fadeDuration = 0.08f;
            return c;
        }

        // Пункт текстового меню: подсветка, спичка-указатель слева, текст Lora
        private static GameObject MenuListItem()
        {
            var go = Root("MenuListItem", new Vector2(560f, 76f));
            var hit = go.AddComponent<Image>();
            hit.color = new Color(1f, 1f, 1f, 0f); // невидимая — ловит мышь по всей строке
            var hl = Sliced(go.transform, "menu_highlight", "Highlight");
            var hlGroup = hl.gameObject.AddComponent<CanvasGroup>();
            var pointer = UiFactory.Image(go.transform, "menu_pointer", false, "Pointer");
            UiFactory.Place(pointer.rectTransform, new Vector2(0f, 0.5f), new Vector2(110f, 48f), new Vector2(-50f, 0f));
            var label = Label(go.transform, "menu.play", 40f, Theme.ink, true);
            label.alignment = TextAlignmentOptions.MidlineLeft;
            // Текст — на бумажной части подсветки (снизу у неё красная полоса ~14 px)
            label.rectTransform.offsetMin = new Vector2(40f, 14f);
            label.rectTransform.offsetMax = new Vector2(-20f, -2f);
            var b = go.AddComponent<Button>();
            b.targetGraphic = hit;
            b.transition = Selectable.Transition.None;
            go.AddComponent<UiMenuItem>().Setup(hlGroup, pointer.rectTransform, label.rectTransform);
            var fx = go.AddComponent<UiButtonFx>();
            SetField(fx, "visual", hl.rectTransform);
            return go;
        }

        private static GameObject ToggleSwitch(string name, string off, string on, Vector2 size)
        {
            var go = Root(name, size);
            var visual = UiFactory.Rect(go.transform, "Visual");
            UiRoot.Stretch(visual);
            var back = UiFactory.Image(visual, off, false, "Off");
            UiRoot.Stretch(back.rectTransform);
            back.raycastTarget = true;
            var check = UiFactory.Image(visual, on, false, "On");
            UiRoot.Stretch(check.rectTransform);
            var t = go.AddComponent<Toggle>();
            t.targetGraphic = back;
            t.graphic = check;
            t.transition = Selectable.Transition.ColorTint;
            t.colors = Tints();
            t.toggleTransition = Toggle.ToggleTransition.Fade;
            go.AddComponent<UiButtonFx>();
            return go;
        }

        private static GameObject SliderBar()
        {
            var go = Root("Slider", new Vector2(480f, 56f));
            var track = UiFactory.Image(go.transform, "slider_track", true, "Track");
            UiFactory.Place(track.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(480f, 40f), Vector2.zero);
            track.rectTransform.anchorMin = new Vector2(0f, 0.5f);
            track.rectTransform.anchorMax = new Vector2(1f, 0.5f);
            track.rectTransform.sizeDelta = new Vector2(0f, 40f);
            var fillArea = UiFactory.Rect(go.transform, "Fill Area");
            fillArea.anchorMin = new Vector2(0f, 0.5f);
            fillArea.anchorMax = new Vector2(1f, 0.5f);
            fillArea.sizeDelta = new Vector2(-24f, 26f);
            var fill = UiFactory.Image(fillArea, "slider_fill", true, "Fill");
            fill.rectTransform.anchorMin = Vector2.zero;
            fill.rectTransform.anchorMax = new Vector2(0f, 1f);
            fill.rectTransform.sizeDelta = new Vector2(10f, 0f);
            var handleArea = UiFactory.Rect(go.transform, "Handle Area");
            UiRoot.Stretch(handleArea);
            handleArea.offsetMin = new Vector2(20f, 0f);
            handleArea.offsetMax = new Vector2(-20f, 0f);
            var handle = UiFactory.Image(handleArea, "slider_knob", false, "Handle");
            handle.raycastTarget = true;
            handle.rectTransform.sizeDelta = new Vector2(56f, 56f);
            handle.rectTransform.anchorMin = new Vector2(0f, 0.5f);
            handle.rectTransform.anchorMax = new Vector2(0f, 0.5f);
            var s = go.AddComponent<Slider>();
            s.fillRect = fill.rectTransform;
            s.handleRect = handle.rectTransform;
            s.targetGraphic = handle;
            s.direction = Slider.Direction.LeftToRight;
            s.transition = Selectable.Transition.ColorTint;
            s.colors = Tints();
            s.value = 0.5f;
            var fx = go.AddComponent<UiButtonFx>();
            SetField(fx, "visual", handle.rectTransform);
            // Невидимый фон по всей полосе — клик в любое место
            var hit = go.AddComponent<Image>();
            hit.color = new Color(1f, 1f, 1f, 0f);
            return go;
        }

        private static GameObject Dropdown()
        {
            var res = new TMP_DefaultControls.Resources
            {
                standard = UiSprites.Get("input_field"),
                background = UiSprites.Get("panel_dialog"),
                inputField = UiSprites.Get("input_field"),
                knob = UiSprites.Get("scroll_thumb"),
                checkmark = UiSprites.Get("ic_check"),
                dropdown = UiSprites.Get("dropdown"),
                mask = UiSprites.Get("input_field"),
            };
            var go = TMP_DefaultControls.CreateDropdown(res);
            go.name = "Dropdown";
            ((RectTransform)go.transform).sizeDelta = new Vector2(420f, 66f);
            var dd = go.GetComponent<TMP_Dropdown>();
            var bg = go.GetComponent<Image>();
            bg.sprite = UiSprites.Get("dropdown");
            bg.type = Image.Type.Sliced;
            dd.transition = Selectable.Transition.ColorTint;
            dd.colors = Tints();
            var arrow = go.transform.Find("Arrow");
            if (arrow != null) arrow.gameObject.SetActive(false); // стрелка нарисована на самой картинке
            foreach (var t in go.GetComponentsInChildren<TMP_Text>(true))
            {
                t.font = Theme.body;
                t.fontSize = 28f;
                t.color = Theme.ink;
            }
            if (dd.captionText != null) { dd.captionText.rectTransform.offsetMin = new Vector2(24f, 4f); dd.captionText.rectTransform.offsetMax = new Vector2(-64f, -4f); }
            var template = go.transform.Find("Template");
            if (template != null)
            {
                var ti = template.GetComponent<Image>();
                ti.sprite = UiSprites.Get("input_field");
                ti.type = Image.Type.Sliced;
                ((RectTransform)template).sizeDelta = new Vector2(0f, 260f);
                var item = template.Find("Viewport/Content/Item");
                if (item != null)
                {
                    ((RectTransform)item).sizeDelta = new Vector2(0f, 52f);
                    var check = item.Find("Item Checkmark");
                    if (check != null) ((RectTransform)check).sizeDelta = new Vector2(36f, 36f);
                }
                var content = template.Find("Viewport/Content");
                if (content != null) ((RectTransform)content).sizeDelta = new Vector2(0f, 56f);
            }
            dd.options = new List<TMP_Dropdown.OptionData> { new TMP_Dropdown.OptionData("—") };
            go.AddComponent<UiButtonFx>();
            return go;
        }

        private static GameObject KeybindRowPrefab(InputActionAsset controls)
        {
            var go = Root("KeybindRow", new Vector2(980f, 76f));
            var label = UiFactory.LocText(go.transform, "action.Jump", 32f, Theme.ink, false);
            label.font = Theme.body;
            label.alignment = TextAlignmentOptions.MidlineLeft;
            label.rectTransform.anchorMin = new Vector2(0f, 0f);
            label.rectTransform.anchorMax = new Vector2(0.5f, 1f);
            label.rectTransform.offsetMin = new Vector2(16f, 0f);
            label.rectTransform.offsetMax = Vector2.zero;
            InputGlyph kGlyph, pGlyph;
            var kb = BindButton(go.transform, "Keyboard", new Vector2(0.62f, 0.5f), out kGlyph);
            var pad = BindButton(go.transform, "Gamepad", new Vector2(0.86f, 0.5f), out pGlyph);
            var row = go.AddComponent<KeybindRow>();
            row.Setup(label.GetComponent<LocText>(), kb, kGlyph, pad, pGlyph);
            SetField(row, "actions", controls);
            SetField(row, "actionName", "Jump");
            return go;
        }

        private static Button BindButton(Transform parent, string name, Vector2 anchor, out InputGlyph glyph)
        {
            var root = UiFactory.Rect(parent, name);
            UiFactory.Place(root, anchor, new Vector2(200f, 68f), Vector2.zero);
            var visual = Sliced(root, "input_field", "Visual");
            visual.raycastTarget = true;
            var icon = UiFactory.Image(visual.transform, "keyboard_space", false, "Glyph");
            UiFactory.Place(icon.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(60f, 60f), Vector2.zero);
            icon.sprite = null;
            var fallback = UiFactory.Text(visual.transform, "", 26f, Theme.ink, false);
            fallback.font = Theme.body;
            UiRoot.Stretch(fallback.rectTransform);
            glyph = icon.gameObject.AddComponent<InputGlyph>();
            SetField(glyph, "fallback", fallback);
            var b = root.gameObject.AddComponent<Button>();
            b.targetGraphic = visual;
            b.transition = Selectable.Transition.ColorTint;
            b.colors = Tints();
            root.gameObject.AddComponent<UiButtonFx>();
            return b;
        }

        private static GameObject Dialog(GameObject primary, GameObject secondary)
        {
            var go = Root("DialogPanel", new Vector2(980f, 600f));
            go.AddComponent<CanvasGroup>();
            Sliced(go.transform, "panel_dialog", "Paper").raycastTarget = true; // окно ловит клики (не сквозь)
            var banner = UiFactory.Image(go.transform, "banner_header", true, "Banner");
            UiFactory.Place(banner.rectTransform, new Vector2(0.5f, 1f), new Vector2(660f, 120f), new Vector2(0f, -10f));
            var title = Label(banner.transform, "kit.dialog_title", 46f, Theme.inkLight, true);
            title.rectTransform.offsetMin = new Vector2(90f, 22f);
            title.rectTransform.offsetMax = new Vector2(-90f, -10f);
            var body = Label(go.transform, "kit.dialog_body", 32f, Theme.ink, false);
            body.textWrappingMode = TextWrappingModes.Normal;
            body.rectTransform.offsetMin = new Vector2(80f, 140f);
            body.rectTransform.offsetMax = new Vector2(-80f, -140f);
            var row = UiFactory.Rect(go.transform, "Buttons");
            row.anchorMin = new Vector2(0f, 0f);
            row.anchorMax = new Vector2(1f, 0f);
            row.pivot = new Vector2(0.5f, 0f);
            row.sizeDelta = new Vector2(-120f, 90f);
            row.anchoredPosition = new Vector2(0f, 44f);
            var layout = row.gameObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 30f;
            layout.childAlignment = TextAnchor.MiddleCenter;
            layout.childControlWidth = layout.childControlHeight = false;
            layout.childForceExpandWidth = layout.childForceExpandHeight = false;
            go.AddComponent<UiPanel>();
            go.AddComponent<UiDialog>().Setup(title.GetComponent<LocText>(), body.GetComponent<LocText>(), row, primary, secondary);
            return go;
        }

        private static GameObject Tabs()
        {
            var go = Root("Tabs", new Vector2(1100f, 600f));
            var bar = UiFactory.Rect(go.transform, "Tab Bar");
            bar.anchorMin = new Vector2(0f, 1f);
            bar.anchorMax = new Vector2(1f, 1f);
            bar.pivot = new Vector2(0.5f, 1f);
            bar.sizeDelta = new Vector2(0f, 92f);
            var layout = bar.gameObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 8f;
            layout.childAlignment = TextAnchor.LowerLeft;
            layout.childControlWidth = layout.childControlHeight = false;
            layout.childForceExpandWidth = layout.childForceExpandHeight = false;
            layout.padding = new RectOffset(24, 24, 0, 0);
            var page = Sliced(go.transform, "panel_dialog", "Page Paper");
            page.rectTransform.offsetMax = new Vector2(0f, -84f);
            string[] keys = { "settings.tab.video", "settings.tab.sound", "settings.tab.controls" };
            var tabs = new Button[keys.Length];
            var pages = new GameObject[keys.Length];
            for (int i = 0; i < keys.Length; i++)
            {
                var tab = UiFactory.Rect(bar, "Tab " + (i + 1));
                tab.sizeDelta = new Vector2(250f, 92f);
                var visual = Sliced(tab, i == 0 ? "tab_on" : "tab_off", "Visual");
                visual.raycastTarget = true;
                var label = Label(visual.transform, keys[i], 30f, Theme.ink, false);
                label.rectTransform.offsetMin = new Vector2(20f, 8f);
                label.rectTransform.offsetMax = new Vector2(-20f, -14f);
                var b = tab.gameObject.AddComponent<Button>();
                b.targetGraphic = visual;
                b.transition = Selectable.Transition.None;
                tab.gameObject.AddComponent<UiButtonFx>();
                tabs[i] = b;
                var p = UiFactory.Rect(page.transform, "Page " + (i + 1));
                UiRoot.Stretch(p);
                p.offsetMin = new Vector2(60f, 60f);
                p.offsetMax = new Vector2(-60f, -50f);
                var hint = Label(p, keys[i], 30f, Theme.inkMuted, true);
                hint.alignment = TextAlignmentOptions.Top;
                pages[i] = p.gameObject;
            }
            go.AddComponent<UiTabs>().Setup(tabs, pages);
            return go;
        }

        private static GameObject TooltipPrefab()
        {
            var go = Root("Tooltip", new Vector2(420f, 110f));
            Sliced(go.transform, "tooltip", "Paper");
            var text = Label(go.transform, "kit.tooltip", 24f, Theme.ink, false);
            text.textWrappingMode = TextWrappingModes.Normal;
            text.rectTransform.offsetMin = new Vector2(26f, 34f);
            text.rectTransform.offsetMax = new Vector2(-26f, -14f);
            return go;
        }

        private static GameObject LevelCardPrefab()
        {
            var go = Root("LevelCard", new Vector2(340f, 360f));
            var visual = UiFactory.Rect(go.transform, "Visual");
            UiRoot.Stretch(visual);
            var frameRoot = UiFactory.Rect(visual, "Card");
            frameRoot.anchorMin = new Vector2(0f, 1f);
            frameRoot.anchorMax = new Vector2(1f, 1f);
            frameRoot.pivot = new Vector2(0.5f, 1f);
            frameRoot.sizeDelta = new Vector2(0f, 260f);
            var mask = UiFactory.Rect(frameRoot, "Picture Mask");
            UiRoot.Stretch(mask);
            mask.offsetMin = new Vector2(18f, 18f);
            mask.offsetMax = new Vector2(-18f, -18f);
            mask.gameObject.AddComponent<RectMask2D>();
            var picture = mask.gameObject.AddComponent<Image>();
            picture.color = new Color(0.85f, 0.78f, 0.66f);
            picture.raycastTarget = true;
            var preview = UiFactory.Rect(mask, "Preview").gameObject.AddComponent<Image>();
            UiRoot.Stretch(preview.rectTransform);
            preview.preserveAspect = false;
            preview.raycastTarget = false;
            var frame = Sliced(frameRoot, "card_level", "Frame");
            var number = UiFactory.Text(mask, "", 120f, new Color(0.45f, 0.36f, 0.28f, 0.55f), true);
            number.font = Theme.heading;
            UiRoot.Stretch(number.rectTransform);
            var lockIcon = UiFactory.Image(frameRoot, "ic_lock", false, "Lock");
            UiFactory.Place(lockIcon.rectTransform, new Vector2(0.5f, 0.5f), new Vector2(110f, 110f), Vector2.zero);
            // Название — на бумажной дощечке (читается на любом фоне)
            var plate = UiFactory.Image(visual, "hud_team_plate", true, "Title Plate");
            UiFactory.Place(plate.rectTransform, new Vector2(0.5f, 0f), new Vector2(320f, 74f), new Vector2(0f, 76f));
            // Обычный текст (не LocText): название ставит LevelCard.Set, перевод его не перезапишет
            var title = UiFactory.Text(plate.transform, "", 26f, Theme.ink, true);
            title.font = Theme.heading;
            UiRoot.Stretch(title.rectTransform);
            title.rectTransform.offsetMin = new Vector2(30f, 16f);
            title.rectTransform.offsetMax = new Vector2(-30f, -16f);
            title.enableAutoSizing = true;
            title.fontSizeMin = 14f;
            title.fontSizeMax = 26f;
            var row = UiFactory.Rect(visual, "Golden");
            UiFactory.Place(row, new Vector2(0.5f, 0f), new Vector2(180f, 48f), new Vector2(0f, 16f));
            var icons = new Image[3];
            for (int i = 0; i < 3; i++)
            {
                icons[i] = UiFactory.Image(row, "ic_golden_match_empty", false, "Golden " + (i + 1));
                UiFactory.Place(icons[i].rectTransform, new Vector2(0.5f, 0.5f), new Vector2(46f, 46f), new Vector2((i - 1) * 54f, 0f));
            }
            var b = go.AddComponent<Button>();
            b.targetGraphic = picture;
            b.transition = Selectable.Transition.ColorTint;
            b.colors = Tints();
            go.AddComponent<UiButtonFx>();
            var card = go.AddComponent<LevelCard>();
            card.Setup(preview, title, icons, lockIcon.gameObject);
            card.SetNumberText(number);
            lockIcon.gameObject.SetActive(false);
            return go;
        }

        private static GameObject PlayerBadgePrefab()
        {
            var go = Root("PlayerBadge", new Vector2(270f, 110f));
            go.AddComponent<CanvasGroup>();
            var tag = UiFactory.Image(go.transform, "hud_nametag", true, "Name Tag");
            UiFactory.Place(tag.rectTransform, new Vector2(0f, 0.5f), new Vector2(190f, 60f), new Vector2(170f, -6f));
            // Обычный текст (не LocText): имя ставит PlayerBadge.Set
            var name = UiFactory.Text(tag.transform, "", 26f, Theme.ink, false);
            name.font = Theme.body;
            UiRoot.Stretch(name.rectTransform);
            name.rectTransform.offsetMin = new Vector2(74f, 10f); // слева — дырочка с ниткой
            name.rectTransform.offsetMax = new Vector2(-16f, -8f);
            name.enableAutoSizing = true;
            name.fontSizeMin = 16f;
            name.fontSizeMax = 26f;
            var badge = UiFactory.Image(go.transform, "badge_red", false, "Badge");
            UiFactory.Place(badge.rectTransform, new Vector2(0f, 0.5f), new Vector2(104f, 104f), new Vector2(54f, 0f));
            var speaking = UiFactory.Image(go.transform, "ic_speaking", false, "Speaking");
            UiFactory.Place(speaking.rectTransform, new Vector2(0f, 0.5f), new Vector2(44f, 44f), new Vector2(100f, 38f));
            var host = UiFactory.Image(go.transform, "ic_host", false, "Host");
            UiFactory.Place(host.rectTransform, new Vector2(0f, 0.5f), new Vector2(48f, 40f), new Vector2(54f, 58f));
            speaking.gameObject.SetActive(false);
            host.gameObject.SetActive(false);
            go.AddComponent<PlayerBadge>().Setup(badge, name, speaking.gameObject, host.gameObject);
            return go;
        }

        private static GameObject BurnBarPrefab()
        {
            var go = Root("BurnBar", new Vector2(190f, 34f));
            go.AddComponent<CanvasGroup>();
            var fill = UiFactory.Image(go.transform, "hud_burn_fill", false, "Fill");
            UiRoot.Stretch(fill.rectTransform);
            fill.rectTransform.offsetMin = new Vector2(7f, 6f);
            fill.rectTransform.offsetMax = new Vector2(-7f, -6f);
            fill.preserveAspect = false;
            fill.type = Image.Type.Filled;
            fill.fillMethod = Image.FillMethod.Horizontal;
            fill.fillOrigin = 0;
            Sliced(go.transform, "hud_burn_frame", "Frame");
            go.AddComponent<BurnBar>().Setup(fill);
            return go;
        }

        private static GameObject CounterPrefab()
        {
            var go = Root("CollectibleCounter", new Vector2(250f, 84f));
            Sliced(go.transform, "hud_collectible_plate", "Plate");
            var icon = UiFactory.Image(go.transform, "ic_golden_match", false, "Icon");
            UiFactory.Place(icon.rectTransform, new Vector2(0f, 0.5f), new Vector2(64f, 64f), new Vector2(150f, 2f));
            var count = UiFactory.Text(go.transform, "0 / 3", 36f, Theme.inkLight, false);
            count.font = Theme.body;
            count.fontStyle = FontStyles.Bold;
            UiFactory.Place(count.rectTransform, new Vector2(0f, 0.5f), new Vector2(110f, 60f), new Vector2(205f, 2f));
            // Иконка спички на самой дощечке уже нарисована слева — наша золотая встаёт в окошко
            icon.rectTransform.anchoredPosition = new Vector2(95f, 2f);
            count.rectTransform.anchoredPosition = new Vector2(180f, 2f);
            go.AddComponent<CollectibleCounter>().Setup(count, icon.rectTransform);
            return go;
        }

        // Отсчёт перед стартом: корень с Countdown, части собирает сам компонент — в префабе их можно двигать,
        // длительность и прочее — в его инспекторе
        private static GameObject CountdownPrefab()
        {
            var go = Root(Countdown.PrefabName, new Vector2(1920f, 1080f));
            go.AddComponent<Countdown>().BuildView();
            foreach (var t in go.GetComponentsInChildren<TextMeshProUGUI>(true)) t.font = t.gameObject.name == "Hint" ? Theme.body : Theme.heading;
            return go;
        }

        // ---------- Витрина ----------

        public const string DemoScene = "Assets/Scenes/UiKitDemo.unity";

        /// <summary>Сцена-витрина всех префабов (не в Build Settings). Текущая сцена не должна иметь несохранённых правок.</summary>
        [MenuItem("PushPals/Интерфейс/Открыть витрину набора UI")]
        public static string BuildDemoScene()
        {
            if (UnityEditor.SceneManagement.EditorSceneManager.GetActiveScene().isDirty) return "Сначала сохраните текущую сцену.";
            var scene = UnityEditor.SceneManagement.EditorSceneManager.NewScene(UnityEditor.SceneManagement.NewSceneSetup.EmptyScene,
                UnityEditor.SceneManagement.NewSceneMode.Single);
            var cam = new GameObject("Main Camera", typeof(Camera)).GetComponent<Camera>();
            cam.tag = "MainCamera";
            cam.orthographic = true;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.12f, 0.09f, 0.07f);
            cam.gameObject.AddComponent<AudioListener>();
            var demo = new GameObject("UI Kit Demo").AddComponent<UiKitDemo>();
            var so = new SerializedObject(demo);
            var list = new List<GameObject>();
            foreach (var guid in AssetDatabase.FindAssets("t:Prefab", new[] { PrefabDir.TrimEnd('/') }))
                list.Add(AssetDatabase.LoadAssetAtPath<GameObject>(AssetDatabase.GUIDToAssetPath(guid)));
            var prop = so.FindProperty("prefabs");
            prop.arraySize = list.Count;
            for (int i = 0; i < list.Count; i++) prop.GetArrayElementAtIndex(i).objectReferenceValue = list[i];
            so.FindProperty("controls").objectReferenceValue = AssetDatabase.LoadAssetAtPath<InputActionAsset>(ControlsPath);
            so.FindProperty("background").objectReferenceValue = AssetDatabase.LoadAssetAtPath<Sprite>("Assets/Art/UI/Backgrounds/bg_main_menu.png");
            so.FindProperty("backgroundBlur").objectReferenceValue = AssetDatabase.LoadAssetAtPath<Sprite>("Assets/Art/UI/Backgrounds/bg_main_menu_blur.png");
            so.ApplyModifiedPropertiesWithoutUndo();
            UnityEditor.SceneManagement.EditorSceneManager.SaveScene(scene, DemoScene);
            return "Витрина: " + DemoScene + " (префабов " + list.Count + ") — нажмите Play";
        }

        private static void SetField(Object target, string field, Object value)
        {
            var so = new SerializedObject(target);
            so.FindProperty(field).objectReferenceValue = value;
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        private static void SetField(Object target, string field, string value)
        {
            var so = new SerializedObject(target);
            so.FindProperty(field).stringValue = value;
            so.ApplyModifiedPropertiesWithoutUndo();
        }
    }
}
