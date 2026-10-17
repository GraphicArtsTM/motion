using System;
using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public enum HitLevel { High, Mid, Low, Overhead, Unblockable }
    public enum MoveKind { Normal, Special, Super, Throw, Finisher }
    public enum HitFx { Blunt, Slash, Magic, Star, Water, Arrow, Gold, Wind, Earth }

    public static class Trail
    {
        public const int WeaponR = 1, WeaponL = 2, FootL = 4, FootR = 8, HandR = 16, HandL = 32;
    }

    [Flags]
    public enum Btn : byte { None = 0, LP = 1, HP = 2, LK = 4, HK = 8, Block = 16, Throw = 32 }

    /// <summary>Bitta harakat (zarba, maxsus usul, otish) — kadr ma'lumotlari bilan (60 FPS).</summary>
    public class MoveData
    {
        public string id;
        public string name;          // o'zbekcha nom
        public string notation;      // masalan "← → + LP"
        public string description;
        public MoveKind kind = MoveKind.Normal;

        public int startup = 6, active = 3, recovery = 12;
        public int TotalFrames => startup + active + recovery;

        public float damage = 40;
        public float chip = 0.04f;           // blokdagi zarar ulushi
        public HitLevel level = HitLevel.Mid;
        public Rect hitbox = new Rect(0.2f, 1.0f, 0.8f, 0.4f);  // x — oldinga, y — yuqoriga (lokal)
        public int hits = 1;
        public int hitInterval = 4;
        public int hitstun = 18;
        public int blockstun = 12;
        public Vector2 knockback = new Vector2(2.2f, 0f); // urilganda tezlik (x — hujumchidan uzoqlashish)
        public float blockPush = 2.6f;
        public bool launch;                   // havoga ko'tarish (juggle)
        public bool lastHitLaunch;            // ko'p zarbali usulda oxirgi zarba ko'taradi
        public bool knockdown;                // yiqitish
        public bool sweep;                    // oyoqdan chalish
        public int hitstop = 7;
        public float meterGain = 10;
        public HitFx fx = HitFx.Blunt;
        public Sfx whoosh = Sfx.WhooshLight;
        public Sfx hitSfx = Sfx.HitLight;
        public float shake = 0.08f;

        public bool crouching;                // cho'kkalab bajariladi
        public bool air;                      // havoda bajariladi
        public bool airOK;                    // maxsus usul havoda ham ishlaydi

        public Vector2 moveVel;               // harakat davomida tezlik (oldinga)
        public int moveStart, moveEnd = -1;
        public bool keepMomentum;

        public int invulStart = -1, invulEnd = -1;
        public int armorStart = -1, armorEnd = -1;
        public int projectileInvulStart = -1, projectileInvulEnd = -1;

        public bool isThrow;
        public float throwRange = 1.15f;
        public float throwDamage = 120f;
        public bool forwardThrow = true;

        public Dictionary<Btn, string> chains;     // kombo zanjirlari (string)
        public bool specialCancel = true;
        public bool whiffChain = true;             // MK uslubi: zanjir havoga ham ishlaydi
        public int counterStart = -1, counterEnd = -1; // qarshi turish (parry) oynasi
        public string counterMove;
        public int reflectStart = -1, reflectEnd = -1; // snaryadni qaytarish

        public int trails;                    // qurol/oyoq izi: Trail.* bayroqlari
        public Color trailColor = new Color(1f, 0.85f, 0.6f, 0.9f);
        public float trailFrom = -1;

        public AnimClip clip;

        // Maxsus xatti-harakat
        public Action<Fighter> onStart;
        public Action<Fighter, int> onFrame;
        public Action<Fighter, Fighter> onHit;
        public Action<Fighter> onEnd;

        public bool HasHitbox => hitbox.width > 0.001f && hitbox.height > 0.001f;

        public MoveData Chain(Btn b, string next)
        {
            chains ??= new Dictionary<Btn, string>();
            chains[b] = next;
            return this;
        }
    }

    /// <summary>Maxsus usul uchun buyruq kombinatsiyasi (numpad yozuvi, nisbiy: 6 — oldinga, 4 — orqaga).</summary>
    public class SpecialInput
    {
        public int[] motion;
        public Btn button;
        public string moveId;
        public int window = 22;
        public SpecialInput(string moveId, Btn button, params int[] motion)
        {
            this.moveId = moveId; this.button = button; this.motion = motion;
            window = motion.Length >= 3 ? 30 : 22;
        }
    }

    /// <summary>Kinematik sahna (super zarba / yakuniy zarba) bosqichi.</summary>
    public class CineStep
    {
        public float time;
        public Action<CineContext> action;
        public CineStep(float t, Action<CineContext> a) { time = t; action = a; }
    }

    public class CineContext
    {
        public Fighter attacker, defender;
        public MatchController match;
        public FightCamera cam;
        public float dir => attacker.facing;
    }

    public class FighterDefinition
    {
        public string id;
        public string name;
        public string title;
        public string years;
        public string bio;
        public string quote;
        public string style;             // jang uslubi tavsifi
        public Color mainColor, accentColor;
        public BodyShape body = new BodyShape();

        public float walkFwd = 2.6f, walkBack = 2.1f;
        public float jumpVel = 11.4f, jumpX = 3.5f;
        public float damageMult = 1f, defenseMult = 1f;
        public float juggleWeight = 1f;
        public float dashSpeed = 7.5f;
        public float runSpeed = 6.2f;

        // Jonlilik: jang turishidagi ritm va gaplar
        public float bounceAmp = 0.015f, bounceRate = 4.5f;
        public string introLine;
        public string[] winLines;
        public readonly System.Collections.Generic.Dictionary<string, string> vsLines = new System.Collections.Generic.Dictionary<string, string>();

        public Func<Transform, Rig> buildVisual;
        public AnimSet anims = new AnimSet();
        public readonly Dictionary<string, MoveData> moves = new Dictionary<string, MoveData>();
        public readonly List<SpecialInput> specials = new List<SpecialInput>();
        public string superMoveId;
        public SpecialInput finisherInput;
        public string finisherName;
        public Func<CineContext, List<CineStep>> superScript;
        public Func<CineContext, List<CineStep>> finisherScript;
        public HitFx signatureFx = HitFx.Slash;
        public Color energyColor = Color.white;

        public MoveData Add(MoveData m)
        {
            moves[m.id] = m;
            return m;
        }

        public MoveData Get(string id) => id != null && moves.TryGetValue(id, out var m) ? m : null;
    }
}
