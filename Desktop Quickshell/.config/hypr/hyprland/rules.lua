-- Window and layer rules. Each app gets ONE rule carrying all its properties
-- (float + size + center ...) instead of one rule per property.

-- Small utility windows: float, sized, centered
hl.window_rule({ match = { class = "nmtui" }, float = true, size = "60% 70%", center = true })
hl.window_rule({ match = { class = "nwg-look" }, float = true, size = "50% 60%", center = true })

-- Steam / Moonlight
hl.window_rule({ match = { class = "steam" }, rounding = 10 })
hl.window_rule({ match = { class = "steam", title = "Friends List" }, float = true })
hl.window_rule({ match = { class = "com\\.moonlight_stream\\.Moonlight", title = ".* - Moonlight$" }, fullscreen = true })

-- Dialogs
hl.window_rule({ match = { title = "(Select|Open)( a)? (File|Folder)(s)?" }, float = true })
hl.window_rule({ match = { title = "File (Operation|Upload)( Progress)?" }, float = true })
hl.window_rule({ match = { title = ".* Properties" }, float = true })
hl.window_rule({ match = { title = "Export Image as PNG" }, float = true })
hl.window_rule({ match = { title = "GIMP Crash Debug" }, float = true })
hl.window_rule({ match = { title = "Save As" }, float = true })
hl.window_rule({ match = { title = "Library" }, float = true })

-- Games: opaque, tearing allowed, never go idle, marked as game content (VRR
-- then ignores cursor movement instead of rendering extra frames for it)
hl.window_rule({ match = { class = "(steam_app_(default|[0-9]+))|gamescope" }, opaque = true, immediate = true, idle_inhibit = "always", content = "game" })

-- Wine/XWayland helper windows
hl.window_rule({ match = { xwayland = true, title = "win[0-9]+" }, no_dim = true, no_shadow = true, rounding = 10 })


-- General fixes
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

hl.window_rule({
    name = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move = "20 monitor_h-120",
    float = true,
})

-- Layer rules (blur + animations for the Quickshell bar and its popups)
-- Quickshell's layers are see-through except for their glass: ignore_alpha
-- leaves the transparent parts alone (the gaps between the bar's islands, the
-- invisible full-screen layer around the control center) and blurs the glass
-- (40-60% opaque). Blur gets a rule of its own: a rule with a setting Hyprland
-- doesn't accept (an animation) is dropped whole, without a config error. The
-- extras (xray off, animations) are separate and in pcall, so a Hyprland
-- version without them skips them instead of stopping here.
-- The names: vk-top / vk-left / vk-right (the bar), vk-control-center-*,
-- vk-calendar-*, vk-power-*, vk-mixer-*, vk-bluetooth-*, vk-network-*
-- (popups, by the edge of the bar they open from), vk-launcher-*,
-- vk-wallpaper-*, vk-clipboard-*, vk-polkit-*, vk-switcher-* (in the middle of
-- the screen), vk-overview (over every monitor), vk-notifications, vk-osd
-- (volume popup).
-- The wallpaper itself is "wallpaper" (nothing to blur). See quickshell/shell.qml.
local shell = "^vk-.*$"
hl.layer_rule({ match = { namespace = shell }, blur = true, ignore_alpha = 0.2 })
pcall(hl.layer_rule, { match = { namespace = shell }, blur_popups = true })
pcall(hl.layer_rule, { match = { namespace = shell }, xray = false })

-- the control center, calendar and power menu slide in and out from the top
-- with the bar on top, from the side with a side bar (left or right)
for _, popup in ipairs({ "vk-control-center", "vk-calendar", "vk-power", "vk-mixer", "vk-bluetooth", "vk-network" }) do
    pcall(hl.layer_rule, { match = { namespace = popup .. "-top" }, animation = "slide top" })
    pcall(hl.layer_rule, { match = { namespace = popup .. "-left" }, animation = "slide left" })
    pcall(hl.layer_rule, { match = { namespace = popup .. "-right" }, animation = "slide right" })
end
pcall(hl.layer_rule, { match = { namespace = "vk-notifications" }, animation = "slide right" })
pcall(hl.layer_rule, { match = { namespace = "vk-osd" }, animation = "fade" })

-- launcher, wallpaper picker, clipboard and password dialog: in the middle of
-- the screen, they rise from the bottom (like rofi did)
pcall(hl.layer_rule, { match = { namespace = "^vk-(launcher|wallpaper|clipboard|polkit)-.*$" }, animation = "slide bottom" })
-- the workspace overview zooms in a little (over both monitors)
pcall(hl.layer_rule, { match = { namespace = "vk-overview" }, animation = "popin 95%" })
-- the window switcher fades, so a quick Alt + Tab doesn't fly across the screen
pcall(hl.layer_rule, { match = { namespace = "^vk-switcher-.*$" }, animation = "fade" })
