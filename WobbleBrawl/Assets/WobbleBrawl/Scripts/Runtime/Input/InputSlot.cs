using UnityEngine;
#if WB_INPUT_SYSTEM && ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

namespace WobbleBrawl
{
    /// <summary>Raw per-frame controls of one physical device (or keyboard half).</summary>
    public struct RawInput
    {
        public Vector2 move;     // stick space, |move| <= 1
        public float pitch;      // arm aim, degrees (+ is up)
        public bool jump, grabL, grabR, punch, kick;
        public bool jumpDown, punchDown, kickDown;
        public bool altDown; // lobby: change colour
    }

    public struct MenuNav
    {
        public bool up, down, left, right, confirm, back;
        public bool Any => up || down || left || right || confirm || back;

        public static MenuNav operator |(MenuNav a, MenuNav b) => new MenuNav
        {
            up = a.up || b.up, down = a.down || b.down, left = a.left || b.left,
            right = a.right || b.right, confirm = a.confirm || b.confirm, back = a.back || b.back,
        };
    }

    /// <summary>One way to control a fighter: keyboard+mouse, the arrow half of the keyboard, or a gamepad.</summary>
    public abstract class InputSlot
    {
        public abstract string Id { get; }
        public abstract string Label { get; }
        public abstract string JoinHint { get; }
        public abstract string ControlsHint { get; }
        public abstract bool Connected { get; }
        public abstract RawInput Read(float dt);
        public abstract bool JoinDown();
        public abstract bool LeaveDown();
        public abstract bool PauseDown();
        public abstract MenuNav Nav();
        public virtual void Rumble(float low, float high, float time) { }
        public virtual void UpdateRumble(float dt) { }
    }

    public sealed class KeyboardMouseSlot : InputSlot
    {
        float pitch;

        public override string Id => "kbm";
        public override string Label => "Клавиатура + мышь";
        public override string JoinHint => "ПРОБЕЛ";
        public override string ControlsHint =>
            "WASD — ходьба   ПРОБЕЛ — прыжок   ЛКМ/ПКМ — левая/правая рука (держать = схватить)\n" +
            "МЫШЬ ВВЕРХ/ВНИЗ или КОЛЕСО — высота рук   F — удар   E — пинок (в прыжке — дропкик)";
        public override bool Connected => true;

        public override RawInput Read(float dt)
        {
            var r = new RawInput();
            Vector2 m = Vector2.zero;
            if (Kb.Held(KeyId.W)) m.y += 1;
            if (Kb.Held(KeyId.S)) m.y -= 1;
            if (Kb.Held(KeyId.D)) m.x += 1;
            if (Kb.Held(KeyId.A)) m.x -= 1;
            r.move = Vector2.ClampMagnitude(m, 1f);

            pitch += Kb.MouseDelta.y * 0.28f + Kb.Scroll * 14f;
            // with no hand raised, slowly return the aim to chest height so the next grab is predictable
            if (!Kb.MouseHeld(0) && !Kb.MouseHeld(1)) pitch = Mathf.MoveTowards(pitch, 0f, 60f * dt);
            pitch = Mathf.Clamp(pitch, Tune.PitchMin, Tune.PitchMax);
            r.pitch = pitch;

            r.jump = Kb.Held(KeyId.Space);
            r.jumpDown = Kb.Down(KeyId.Space);
            r.grabL = Kb.MouseHeld(0);
            r.grabR = Kb.MouseHeld(1);
            r.punch = Kb.Held(KeyId.F) || Kb.MouseHeld(2);
            r.punchDown = Kb.Down(KeyId.F) || Kb.MouseDown(2);
            r.kick = Kb.Held(KeyId.E);
            r.kickDown = Kb.Down(KeyId.E);
            r.altDown = Kb.Down(KeyId.Q);
            return r;
        }

        public override bool JoinDown() => Kb.Down(KeyId.Space);
        public override bool LeaveDown() => Kb.Down(KeyId.Backspace);
        public override bool PauseDown() => Kb.Down(KeyId.Escape);

        public override MenuNav Nav() => new MenuNav
        {
            up = Kb.Down(KeyId.W) || Kb.Down(KeyId.Up),
            down = Kb.Down(KeyId.S) || Kb.Down(KeyId.Down),
            left = Kb.Down(KeyId.A) || Kb.Down(KeyId.Left),
            right = Kb.Down(KeyId.D) || Kb.Down(KeyId.Right),
            confirm = Kb.Down(KeyId.Enter) || Kb.Down(KeyId.NumEnter),
            back = Kb.Down(KeyId.Escape),
        };
    }

    /// <summary>Second keyboard player on the arrow keys / numpad, for couch play without gamepads.</summary>
    public sealed class KeyboardArrowsSlot : InputSlot
    {
        float pitch;

        public override string Id => "kb2";
        public override string Label => "Клавиатура (стрелки)";
        public override string JoinHint => "ПРАВЫЙ SHIFT";
        public override string ControlsHint =>
            "СТРЕЛКИ — ходьба   ПРАВЫЙ SHIFT — прыжок   , / . — левая/правая рука   L / K — руки вверх / вниз\n" +
            "/ — удар   ; — пинок   (цифровой блок: 0 прыжок, 1/2 руки, 3 удар, точка пинок, 8/5 руки вверх/вниз)";
        public override bool Connected => true;

        public override RawInput Read(float dt)
        {
            var r = new RawInput();
            Vector2 m = Vector2.zero;
            if (Kb.Held(KeyId.Up)) m.y += 1;
            if (Kb.Held(KeyId.Down)) m.y -= 1;
            if (Kb.Held(KeyId.Right)) m.x += 1;
            if (Kb.Held(KeyId.Left)) m.x -= 1;
            r.move = Vector2.ClampMagnitude(m, 1f);

            float target = Kb.AnyHeld(KeyId.L, KeyId.Num8) ? 80f : Kb.AnyHeld(KeyId.K, KeyId.Num5) ? -50f : 0f;
            pitch = Mathf.MoveTowards(pitch, target, 260f * dt);
            r.pitch = pitch;

            r.jump = Kb.AnyHeld(KeyId.RightShift, KeyId.Num0);
            r.jumpDown = Kb.AnyDown(KeyId.RightShift, KeyId.Num0);
            r.grabL = Kb.AnyHeld(KeyId.Comma, KeyId.Num1);
            r.grabR = Kb.AnyHeld(KeyId.Period, KeyId.Num2);
            r.punch = Kb.AnyHeld(KeyId.Slash, KeyId.Num3);
            r.punchDown = Kb.AnyDown(KeyId.Slash, KeyId.Num3);
            r.kick = Kb.AnyHeld(KeyId.Semicolon, KeyId.NumPeriod);
            r.kickDown = Kb.AnyDown(KeyId.Semicolon, KeyId.NumPeriod);
            r.altDown = Kb.AnyDown(KeyId.P, KeyId.Num9);
            return r;
        }

        public override bool JoinDown() => Kb.AnyDown(KeyId.RightShift, KeyId.Num0);
        public override bool LeaveDown() => Kb.Down(KeyId.Delete);
        public override bool PauseDown() => false; // Escape is owned by the keyboard+mouse slot
        public override MenuNav Nav() => default;  // menu navigation on the keyboard is handled by the KBM slot
    }

#if WB_INPUT_SYSTEM && ENABLE_INPUT_SYSTEM
    public sealed class GamepadSlot : InputSlot
    {
        public readonly Gamepad pad;
        readonly string id;
        int lastNavY, lastNavX;
        float navRepeat;
        float rumbleTime;

        public GamepadSlot(Gamepad pad)
        {
            this.pad = pad;
            id = "pad:" + pad.deviceId;
        }

        public override string Id => id;
        public override string Label => string.IsNullOrEmpty(pad.displayName) ? "Геймпад" : pad.displayName;
        public override string JoinHint => "A / START";
        public override string ControlsHint =>
            "ЛЕВЫЙ СТИК — ходьба   A — прыжок   LT/RT (или LB/RB) — руки   ПРАВЫЙ СТИК/Y — высота рук\n" +
            "X — удар (держишь врага обеими руками — удар головой)   B — пинок (в прыжке — дропкик)";
        public override bool Connected => pad != null && pad.added;

        public override RawInput Read(float dt)
        {
            var r = new RawInput();
            if (!Connected) return r;
            Vector2 m = pad.leftStick.ReadValue() + pad.dpad.ReadValue();
            if (m.magnitude < 0.18f) m = Vector2.zero;
            r.move = Vector2.ClampMagnitude(m, 1f);

            float rs = pad.rightStick.ReadValue().y;
            r.pitch = Mathf.Abs(rs) > 0.2f ? rs * 80f : (pad.buttonNorth.isPressed ? 80f : 0f);

            r.jump = pad.buttonSouth.isPressed;
            r.jumpDown = pad.buttonSouth.wasPressedThisFrame;
            r.grabL = pad.leftTrigger.ReadValue() > 0.35f || pad.leftShoulder.isPressed;
            r.grabR = pad.rightTrigger.ReadValue() > 0.35f || pad.rightShoulder.isPressed;
            r.punch = pad.buttonWest.isPressed;
            r.punchDown = pad.buttonWest.wasPressedThisFrame;
            r.kick = pad.buttonEast.isPressed;
            r.kickDown = pad.buttonEast.wasPressedThisFrame;
            r.altDown = pad.buttonNorth.wasPressedThisFrame;
            return r;
        }

        public override bool JoinDown() => Connected && (pad.buttonSouth.wasPressedThisFrame || pad.startButton.wasPressedThisFrame);
        public override bool LeaveDown() => Connected && pad.selectButton.wasPressedThisFrame;
        public override bool PauseDown() => Connected && pad.startButton.wasPressedThisFrame;

        public override MenuNav Nav()
        {
            if (!Connected) return default;
            var nav = new MenuNav();
            Vector2 v = pad.leftStick.ReadValue() + pad.dpad.ReadValue();
            int y = v.y > 0.55f ? 1 : v.y < -0.55f ? -1 : 0;
            int x = v.x > 0.55f ? 1 : v.x < -0.55f ? -1 : 0;
            navRepeat -= Time.unscaledDeltaTime;
            bool repeat = navRepeat <= 0f;
            if (y != lastNavY || (y != 0 && repeat))
            {
                nav.up = y > 0; nav.down = y < 0;
                navRepeat = y != lastNavY ? 0.4f : 0.12f;
            }
            if (x != lastNavX || (x != 0 && repeat))
            {
                nav.left = x < 0; nav.right = x > 0;
                navRepeat = x != lastNavX ? 0.4f : 0.12f;
            }
            lastNavY = y; lastNavX = x;
            nav.confirm = pad.buttonSouth.wasPressedThisFrame || pad.startButton.wasPressedThisFrame;
            nav.back = pad.buttonEast.wasPressedThisFrame;
            return nav;
        }

        public override void Rumble(float low, float high, float time)
        {
            if (!Connected) return;
            pad.SetMotorSpeeds(Mathf.Clamp01(low), Mathf.Clamp01(high));
            rumbleTime = Mathf.Max(rumbleTime, time);
        }

        public override void UpdateRumble(float dt)
        {
            if (rumbleTime <= 0f) return;
            rumbleTime -= dt;
            if (rumbleTime <= 0f && Connected) pad.SetMotorSpeeds(0f, 0f);
        }
    }
#endif
}
