using System.Collections.Generic;
using UnityEngine;

// Description of one playable character.
// Characters differ by look (CharacterRig builds a model for each of them), colour and stats.
// Want your own 3D model? Add a prefab to GameAssets.characterModels at the right index.
public class CharacterDef
{
    public string key;                   // localization key: Loc.T(key) = name, Loc.T(key + ".desc") = description
    public Color tint;
    public float moveMult = 1f;          // lane-change speed
    public float coinMult = 1f;          // score multiplier per coin
    public float startTimeBonus = 0f;    // extra seconds on the starting timer
    public float checkpointBonus = 0f;   // extra seconds at a checkpoint
    public float hitSlowMult = 1f;       // 1 = normal slowdown on a hit, 0.5 = half as much

    // The name and the description in the current language.
    public string Name { get { return Loc.T(key); } }
    public string Description { get { return Loc.T(key + ".desc"); } }

    // Short lines describing the hero's perks for the selection screen.
    public List<string> StatLines()
    {
        List<string> l = new List<string>();
        if (moveMult > 1f) l.Add(Loc.F("stat.move", Mathf.RoundToInt((moveMult - 1f) * 100f)));
        if (coinMult > 1f) l.Add(Loc.F("stat.coin", Mathf.RoundToInt((coinMult - 1f) * 100f)));
        if (startTimeBonus > 0f) l.Add(Loc.F("stat.start", Mathf.RoundToInt(startTimeBonus)));
        if (checkpointBonus > 0f) l.Add(Loc.F("stat.checkpoint", Mathf.RoundToInt(checkpointBonus)));
        if (hitSlowMult < 1f) l.Add(Loc.F("stat.hit", Mathf.RoundToInt((1f - hitSlowMult) * 100f)));
        if (l.Count == 0) l.Add(Loc.T("stat.none"));
        return l;
    }

    public string TintHex
    {
        get { return "#" + ColorUtility.ToHtmlStringRGB(tint); }
    }
}

public static class CharacterCatalog
{
    public static readonly CharacterDef[] All =
    {
        new CharacterDef {
            key = "char.king", tint = Color.white,
        },
        new CharacterDef {
            key = "char.knight", tint = new Color(0.45f, 0.65f, 1f),
            moveMult = 1.3f,
        },
        new CharacterDef {
            key = "char.ranger", tint = new Color(0.55f, 0.95f, 0.5f),
            coinMult = 1.5f,
        },
        new CharacterDef {
            key = "char.alchemist", tint = new Color(0.85f, 0.6f, 1f),
            startTimeBonus = 5f, checkpointBonus = 3f,
        },
        new CharacterDef {
            key = "char.pyro", tint = new Color(1f, 0.55f, 0.35f),
            hitSlowMult = 0.5f,
        },
    };

    public static int Count { get { return All.Length; } }
}

// Tints the character model without creating copies of materials.
public static class ModelTint
{
    static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
    static readonly int ColorId = Shader.PropertyToID("_Color");

    public static void Apply(GameObject model, Color tint)
    {
        // A model built by code knows which of its parts are "clothes" - only they are tinted.
        CharacterRig rig = model.GetComponentInChildren<CharacterRig>();
        if (rig != null)
        {
            rig.ApplyTint(tint);
            return;
        }

        if (tint == Color.white) return;

        MaterialPropertyBlock block = new MaterialPropertyBlock();
        foreach (Renderer r in model.GetComponentsInChildren<Renderer>())
        {
            r.GetPropertyBlock(block);
            block.SetColor(BaseColorId, tint);   // URP Lit
            block.SetColor(ColorId, tint);       // Standard (built-in pipeline)
            r.SetPropertyBlock(block);
        }
    }
}
