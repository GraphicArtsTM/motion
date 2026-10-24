using System.Collections.Generic;
using UnityEngine;
#if WB_INPUT_SYSTEM && ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

namespace WobbleBrawl
{
    /// <summary>Owns all input slots, tracks hot-plugged gamepads and merges menu navigation.</summary>
    public sealed class InputHub
    {
        public readonly List<InputSlot> Slots = new List<InputSlot>();
        public readonly KeyboardMouseSlot KeyboardMouse = new KeyboardMouseSlot();
        public readonly KeyboardArrowsSlot KeyboardArrows = new KeyboardArrowsSlot();

        public InputHub()
        {
            Slots.Add(KeyboardMouse);
            Slots.Add(KeyboardArrows);
        }

        public void Refresh(float unscaledDt)
        {
#if WB_INPUT_SYSTEM && ENABLE_INPUT_SYSTEM
            foreach (var pad in Gamepad.all)
            {
                bool known = false;
                foreach (var s in Slots)
                    if (s is GamepadSlot gs && gs.pad == pad) { known = true; break; }
                if (!known) Slots.Add(new GamepadSlot(pad));
            }
#endif
            foreach (var s in Slots) s.UpdateRumble(unscaledDt);
        }

        public MenuNav Nav()
        {
            var nav = new MenuNav();
            foreach (var s in Slots)
                if (s.Connected) nav |= s.Nav();
            return nav;
        }

        public bool PauseDown()
        {
            foreach (var s in Slots)
                if (s.Connected && s.PauseDown()) return true;
            return false;
        }

        public void StopAllRumble()
        {
            foreach (var s in Slots) s.Rumble(0f, 0f, 0.01f);
        }
    }
}
