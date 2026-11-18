hl.config({
    input = {
        kb_layout = "be",
        numlock_by_default = true,
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        accel_profile = "flat",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            clickfinger_behavior = 1,
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
