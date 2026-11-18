hl.config({
    input = {
        -- for an external keyboard (the on-screen keyboard has its own layouts)
        kb_layout = "us",
        numlock_by_default = true,
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        accel_profile = "flat",
        follow_mouse = 1,
        sensitivity = 0,
        -- Map the touchscreen to the built-in panel, so touches land where you
        -- tap even though the panel is rotated (and stay there with a dock monitor).
        -- The touchscreen reports raw portrait coordinates (800x1280), so it
        -- needs the same transform as the monitor (see rotation.lua).
        touchdevice = {
            output = "eDP-1",
            transform = screenTransform,
        },
    },
})

-- the mouse pointer stays where it is when the workspace changes (scrolling
-- over the bar's workspaces, a keybind, a click in the overview) instead of
-- jumping to the middle of the monitor. In pcall: a Hyprland version without
-- the option skips it instead of stopping here.
pcall(hl.config, {
    cursor = {
        no_warps = true,
    },
})
