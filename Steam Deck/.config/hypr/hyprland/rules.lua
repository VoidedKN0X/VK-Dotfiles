-- Window and layer rules. Each app gets ONE rule carrying all its properties
-- (float + size + center ...) instead of one rule per property.

-- Small utility windows: float, sized, centered
hl.window_rule({ match = { class = "foot", title = "nmtui" }, float = true, size = "60% 70%", center = true })
hl.window_rule({ match = { class = "org\\.pulseaudio\\.pavucontrol|yad-icon-browser" }, float = true, size = "60% 70%", center = true })
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

-- Games: opaque, tearing allowed, never go idle
hl.window_rule({ match = { class = "(steam_app_(default|[0-9]+))|gamescope" }, opaque = true, immediate = true, idle_inhibit = "always" })

-- Wine/XWayland helper windows
hl.window_rule({ match = { xwayland = true, title = "win[0-9]+" }, no_dim = true, no_shadow = true, rounding = 10 })

-- Special workspaces
hl.window_rule({ match = { class = "feishin|Spotify|Supersonic|Cider|com.github.th_ch.youtube_music|Plexamp" }, workspace = "special:music" })
hl.window_rule({ match = { class = "discord|equibop|vesktop|whatsapp" }, workspace = "special:communication" })

-- General fixes (these used to live in workspaces.lua)
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

-- Layer rules (blur + animations for swaync, rofi and the app menu)
hl.layer_rule({ match = { namespace = "swaync-control-center" }, blur = true, ignore_alpha = 0.45, animation = "slide left" })
hl.layer_rule({ match = { namespace = "swaync-notification-window" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "rofi" }, blur = true, ignore_alpha = 0, animation = "slide bottom" })
hl.layer_rule({ match = { namespace = "nwg-drawer" }, blur = true, ignore_alpha = 0, animation = "fade" })
