-- Window and layer rules. Each app gets ONE rule carrying all its properties
-- (float + size + center ...) instead of one rule per property.

-- Small utility windows: float, sized, centered
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
-- Minecraft (title "Minecraft 1.21.4", modded "Minecraft* 1.21.4") and
-- Wine/Proton games outside Steam (Heroic, Faugus: class "game.exe"). Their
-- launchers aren't fullscreen, so idle and the lock screen only wait while
-- the game is fullscreen.
hl.window_rule({ match = { title = "^Minecraft\\*? [0-9].*" }, opaque = true, immediate = true, idle_inhibit = "fullscreen", content = "game" })
hl.window_rule({ match = { class = ".*\\.exe" }, opaque = true, immediate = true, idle_inhibit = "fullscreen", content = "game" })

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

-- Layer rules (blur + animations for the Quickshell frame and its popups)
-- Quickshell's layers are see-through except for their glass: ignore_alpha
-- leaves the transparent parts alone (the desktop inside the frame, the
-- invisible full-screen layer around a popup) and blurs the glass (28-42 %
-- opaque). Blur gets a rule of its own: a rule with a setting Hyprland
-- doesn't accept (an animation) is dropped whole, without a config error. The
-- extras (xray off, animations) are separate and in pcall, so a Hyprland
-- version without them skips them instead of stopping here.
-- The names: vk-top / vk-left / vk-right are the frame around the screen with
-- the bar on that side. The popups that grow out of the frame (control
-- center, calendar, power menu, mixer, Bluetooth, network, launcher,
-- wallpaper picker, clipboard), the notifications and the volume popup are
-- drawn in that same layer, so they share its blur; they animate themselves
-- (growing out of the frame). vk-polkit-* and vk-switcher-* float in the
-- middle of the screen, vk-overview covers the focused monitor. frame-zone is
-- the invisible space the frame keeps free.
-- The wallpaper itself is "wallpaper" (nothing to blur). See quickshell/shell.qml.
local shell = "^vk-.*$"
hl.layer_rule({ match = { namespace = shell }, blur = true, ignore_alpha = 0.2 })
pcall(hl.layer_rule, { match = { namespace = shell }, blur_popups = true })
pcall(hl.layer_rule, { match = { namespace = shell }, xray = false })

-- the frame never animates (it moves above fullscreen apps while a popup is
-- open, which must not look like it opens again)
pcall(hl.layer_rule, { match = { namespace = "^vk-(top|left|right)$" }, no_anim = true })

-- the password dialog rises from the bottom, in the middle of the screen
pcall(hl.layer_rule, { match = { namespace = "^vk-polkit-.*$" }, animation = "slide bottom" })
-- the workspace overview zooms in a little
pcall(hl.layer_rule, { match = { namespace = "vk-overview" }, animation = "popin 95%" })
-- the window switcher fades, so a quick Alt + Tab doesn't fly across the screen
pcall(hl.layer_rule, { match = { namespace = "^vk-switcher-.*$" }, animation = "fade" })
