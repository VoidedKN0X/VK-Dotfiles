-- Window and layer rules. Each app gets ONE rule carrying all its properties
-- (float + size + center ...) instead of one rule per property.

-- Small utility windows: float, sized, centered
hl.window_rule({ match = { class = "nmtui" }, float = true, size = "60% 70%", center = true })
hl.window_rule({ match = { class = "org\\.pulseaudio\\.pavucontrol" }, float = true, size = "60% 70%", center = true })
hl.window_rule({ match = { class = "nwg-look" }, float = true, size = "50% 60%", center = true })
hl.window_rule({ match = { class = "blueman-manager" }, float = true })

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

-- Layer rules (blur + animations for waybar, swaync, the bar's popups and rofi)
-- waybar: the bar is transparent, only its islands are see-through glass, so
-- ignore_alpha keeps the empty gaps between islands unblurred. Waybar uses its
-- config's "name" as the layer namespace: vk-top / vk-left / vk-right
-- (waybar/layouts)
local bar = "^(waybar|vk-top|vk-left|vk-right)$"
hl.layer_rule({ match = { namespace = bar }, blur = true, ignore_alpha = 0.2 })
-- also blur waybar's tooltips (calendar, track info) and tray menus. In pcall,
-- so a Hyprland version without this option skips it instead of stopping here
pcall(hl.layer_rule, { match = { namespace = bar }, blur_popups = true })
pcall(hl.layer_rule, { match = { namespace = bar }, xray = false })
-- swaync draws its panel inside an invisible full-screen layer: ignore_alpha
-- 0.1 leaves that empty part alone and blurs everything that's visible (the
-- glass panel is 50% opaque).
-- Blur gets a rule of its own, like the bar's: a rule with a setting Hyprland
-- doesn't accept (the animation) is dropped whole, without a config error,
-- which is why swaync and rofi weren't blurred before. The extras (xray off,
-- animations) are separate and in pcall.
local notifications = "^swaync-(control-center|notification-window)$"
hl.layer_rule({ match = { namespace = notifications }, blur = true, ignore_alpha = 0.1 })
pcall(hl.layer_rule, { match = { namespace = notifications }, xray = false })
pcall(hl.layer_rule, { match = { namespace = "swaync-control-center" }, animation = "slide left" })

-- the bar's popups (waybar/scripts/calendar.py, music.py, power.py, osd.py)
-- blur themselves (GTK4, like swaync). The calendar, music and power popups
-- slide in and out from the top with the bar on top, from the side with a
-- side bar (left or right)
pcall(hl.layer_rule, { match = { namespace = "vk-calendar-top" }, animation = "slide top" })
pcall(hl.layer_rule, { match = { namespace = "vk-calendar-left" }, animation = "slide left" })
pcall(hl.layer_rule, { match = { namespace = "vk-music-top" }, animation = "slide top" })
pcall(hl.layer_rule, { match = { namespace = "vk-music-left" }, animation = "slide left" })
pcall(hl.layer_rule, { match = { namespace = "vk-calendar-right" }, animation = "slide right" })
pcall(hl.layer_rule, { match = { namespace = "vk-music-right" }, animation = "slide right" })
pcall(hl.layer_rule, { match = { namespace = "vk-power-top" }, animation = "slide top" })
pcall(hl.layer_rule, { match = { namespace = "vk-power-left" }, animation = "slide left" })
pcall(hl.layer_rule, { match = { namespace = "vk-power-right" }, animation = "slide right" })

hl.layer_rule({ match = { namespace = "rofi" }, blur = true, ignore_alpha = 0 })
pcall(hl.layer_rule, { match = { namespace = "rofi" }, animation = "slide bottom" })
