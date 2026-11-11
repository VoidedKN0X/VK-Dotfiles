hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind("SUPER + D", hl.dsp.exec_cmd("discord"))
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + J", hl.dsp.layout("togglesplit"))

hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))

-- Workspaces 1-10 (key 0 = workspace 10): SUPER switches, SUPER + ALT moves the window there
for i = 1, 10 do
    local key = tostring(i % 10)
    local ws = tostring(i)
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = ws }))
    hl.bind("SUPER + ALT + " .. key, hl.dsp.window.move({ workspace = ws }))
end

hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- osd.sh changes the level and shows it in the volume popup
-- (quickshell/popups/Osd.qml) on the focused monitor (5% steps, max 100%)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --output-volume raise"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --output-volume lower"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --output-volume mute-toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --input-volume mute-toggle"), { locked = true })
-- Caps Lock popup: on release (the light has switched by then), and the key
-- still reaches the keyboard (non_consuming), so Caps Lock keeps working
hl.bind("Caps_Lock", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --caps-lock"), { release = true, non_consuming = true, ignore_mods = true })

-- screenshot of both monitors: saved to ~/Pictures/Screenshots and copied
hl.bind("Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh"), { locked = true })
-- window switcher: hold Alt, Tab / Shift + Tab to pick, let go of Alt to switch
-- (quickshell/popups/WindowSwitcher.qml). Alt's release also tells it, in case
-- the switcher didn't get the key itself; non_consuming, so apps still see Alt.
hl.bind("ALT + Tab", hl.dsp.exec_cmd("qs ipc call switcher next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd("qs ipc call switcher prev"))
hl.bind("ALT + Alt_L", hl.dsp.exec_cmd("qs ipc call switcher commit"), { release = true, non_consuming = true })
-- workspace overview on both monitors: click to go, drag windows to move them,
-- type to find one (quickshell/popups/Overview.qml)
hl.bind("SUPER + Tab", hl.dsp.exec_cmd("qs ipc call overview toggle"))

-- the volume mixer (outputs, inputs, a volume per app)
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd("qs ipc call mixer toggle"))
hl.bind("SUPER + W", hl.dsp.exec_cmd(browser))
-- wallpaper picker and clipboard history (quickshell/popups)
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))
hl.bind("SUPER + SHIFT + H", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(fileManager))
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd(menu), { release = true })
hl.bind("SUPER + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/restart-quickshell.sh"))
-- move the bar between the top and the left edge (OLED: no static bar)
hl.bind("SUPER + B", hl.dsp.exec_cmd("qs ipc call bar toggle"))

hl.bind("CTRL + SUPER + left", hl.dsp.focus({ workspace = "-1" }))
hl.bind("CTRL + SUPER + right", hl.dsp.focus({ workspace = "+1" }))
hl.bind("SUPER + Z", hl.dsp.window.drag())
hl.bind("SUPER + X", hl.dsp.window.resize())

hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen({ mode = 1 }))

-- the control center (notifications, toggles, system info), on the focused monitor
hl.bind("SUPER + N", hl.dsp.exec_cmd("qs ipc call controlCenter toggle"))

hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"))

-- switch DP-1 between SDR and HDR (function defined in monitors.lua)
hl.bind("SUPER + SHIFT + D", toggle_dp1_hdr)
