using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Bitta kadrdagi kiritish holati (mutlaq yo'nalishlar).</summary>
    public struct InputFrame
    {
        public bool up, down, left, right;
        public Btn held, pressed;

        public bool Held(Btn b) => (held & b) != 0;
        public bool Pressed(Btn b) => (pressed & b) != 0;

        /// <summary>Nisbiy numpad yo'nalishi (6 — raqib tomon).</summary>
        public int Numpad(int facing)
        {
            int h = 0;
            if (right && !left) h = 1;
            else if (left && !right) h = -1;
            h *= facing;
            int v = up && !down ? 1 : (down && !up ? -1 : 0);
            return 5 + h + v * 3;
        }
    }

    public interface IInputSource
    {
        InputFrame Poll(Fighter self);
    }

    /// <summary>Klaviatura sxemasi.</summary>
    public class KeyMap
    {
        public KeyCode up, down, left, right, lp, hp, lk, hk, block, throwKey;
        public KeyCode[] altUp = new KeyCode[0], altDown = new KeyCode[0], altLeft = new KeyCode[0], altRight = new KeyCode[0];

        public static KeyMap Player1() => new KeyMap
        {
            up = KeyCode.W, down = KeyCode.S, left = KeyCode.A, right = KeyCode.D,
            lp = KeyCode.U, hp = KeyCode.I, lk = KeyCode.J, hk = KeyCode.K, block = KeyCode.L, throwKey = KeyCode.O
        };

        public static KeyMap Player2() => new KeyMap
        {
            up = KeyCode.UpArrow, down = KeyCode.DownArrow, left = KeyCode.LeftArrow, right = KeyCode.RightArrow,
            lp = KeyCode.Keypad4, hp = KeyCode.Keypad5, lk = KeyCode.Keypad1, hk = KeyCode.Keypad2, block = KeyCode.Keypad6, throwKey = KeyCode.Keypad3
        };
    }

    /// <summary>
    /// Klaviatura kiritishi. Update'da bosilishlarni "latch" qiladi, FixedUpdate'da o'qiladi —
    /// shunda qisqa bosishlar ham yo'qolmaydi.
    /// </summary>
    public class KeyboardInput : IInputSource
    {
        public KeyMap map;
        Btn latched;

        public KeyboardInput(KeyMap map) { this.map = map; }

        public void Latch()
        {
            if (Input.GetKeyDown(map.lp)) latched |= Btn.LP;
            if (Input.GetKeyDown(map.hp)) latched |= Btn.HP;
            if (Input.GetKeyDown(map.lk)) latched |= Btn.LK;
            if (Input.GetKeyDown(map.hk)) latched |= Btn.HK;
            if (Input.GetKeyDown(map.block)) latched |= Btn.Block;
            if (Input.GetKeyDown(map.throwKey)) latched |= Btn.Throw;
        }

        public InputFrame Poll(Fighter self)
        {
            var f = new InputFrame
            {
                up = Input.GetKey(map.up),
                down = Input.GetKey(map.down),
                left = Input.GetKey(map.left),
                right = Input.GetKey(map.right)
            };
            if (Input.GetKey(map.lp)) f.held |= Btn.LP;
            if (Input.GetKey(map.hp)) f.held |= Btn.HP;
            if (Input.GetKey(map.lk)) f.held |= Btn.LK;
            if (Input.GetKey(map.hk)) f.held |= Btn.HK;
            if (Input.GetKey(map.block)) f.held |= Btn.Block;
            if (Input.GetKey(map.throwKey)) f.held |= Btn.Throw;
            f.pressed = latched;
            latched = Btn.None;
            return f;
        }
    }

    /// <summary>Oxirgi kadrlar tarixi — maxsus usul kombinatsiyalarini aniqlash uchun.</summary>
    public class InputBuffer
    {
        public const int Size = 64;
        readonly int[] dirs = new int[Size];
        readonly Btn[] pressed = new Btn[Size];
        readonly Btn[] held = new Btn[Size];
        int head;
        public int Count { get; private set; }

        public void Push(InputFrame f, int facing)
        {
            head = (head + 1) % Size;
            dirs[head] = f.Numpad(facing);
            pressed[head] = f.pressed;
            held[head] = f.held;
            if (Count < Size) Count++;
        }

        public void Clear()
        {
            for (int i = 0; i < Size; i++) { dirs[i] = 5; pressed[i] = Btn.None; held[i] = Btn.None; }
            Count = 0;
        }

        /// <summary>ago=0 — joriy kadr.</summary>
        public int Dir(int ago) => ago < Count ? dirs[(head - ago + Size) % Size] : 5;
        public Btn Pressed(int ago) => ago < Count ? pressed[(head - ago + Size) % Size] : Btn.None;
        public Btn Held(int ago) => ago < Count ? held[(head - ago + Size) % Size] : Btn.None;

        public bool PressedWithin(Btn b, int frames)
        {
            for (int i = 0; i < frames; i++) if ((Pressed(i) & b) != 0) return true;
            return false;
        }

        /// <summary>Tugma oxirgi n kadrda bosilganmi, va qaysi kadrda.</summary>
        public int PressedAgo(Btn b, int frames)
        {
            for (int i = 0; i < frames; i++) if ((Pressed(i) & b) != 0) return i;
            return -1;
        }

        public static bool DirMatches(int required, int actual)
        {
            if (required == 5) return actual == 5;
            if (required == 2) return actual == 1 || actual == 2 || actual == 3;
            if (required == 8) return actual == 7 || actual == 8 || actual == 9;
            if (required == 4) return actual == 1 || actual == 4 || actual == 7;
            if (required == 6) return actual == 3 || actual == 6 || actual == 9;
            return required == actual;
        }

        /// <summary>Kombinatsiyani teskari tartibda qidiradi (startAgo — tugma bosilgan kadr).</summary>
        public bool MatchMotion(int[] motion, int startAgo, int window)
        {
            int last = motion.Length - 1;
            int limit = Mathf.Min(Count, startAgo + window);
            int i = startAgo;
            bool found = false;
            for (; i < limit && i < startAgo + 8; i++)
                if (DirMatches(motion[last], Dir(i))) { found = true; break; }
            if (!found) return false;
            for (int idx = last - 1; idx >= 0; idx--)
            {
                bool gapSeen = motion[idx] != motion[idx + 1];
                found = false;
                for (i = i + 1; i < limit; i++)
                {
                    int d = Dir(i);
                    if (!gapSeen)
                    {
                        if (!DirMatches(motion[idx + 1], d)) gapSeen = true;
                        continue;
                    }
                    if (DirMatches(motion[idx], d)) { found = true; break; }
                }
                if (!found) return false;
            }
            return true;
        }

        /// <summary>Ikki marta bosish (dash): 6,5,6 — oxirgi 12 kadrda, joriy kadrda yangi bosilgan.</summary>
        public bool DoubleTap(int dir)
        {
            if (!DirMatches(dir, Dir(0)) || DirMatches(dir, Dir(1))) return false;
            bool neutral = false;
            for (int i = 1; i < 14 && i < Count; i++)
            {
                int d = Dir(i);
                if (!DirMatches(dir, d)) neutral = true;
                else if (neutral) return true;
            }
            return false;
        }
    }
}
