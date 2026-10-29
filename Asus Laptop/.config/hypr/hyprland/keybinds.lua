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

-- osd.sh changes the level and shows it in the bar's popup
-- (waybar/scripts/osd.py) on the focused monitor (5% steps, max 100%)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --output-volume raise"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --output-volume lower"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --output-volume mute-toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --input-volume mute-toggle"), { locked = true })
-- Caps Lock popup: on release (the light has switched by then), and the key
-- still reaches the keyboard (non_consuming), so Caps Lock keeps working
hl.bind("Caps_Lock", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --caps-lock"), { release = true, non_consuming = true, ignore_mods = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --brightness raise"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/scripts/osd.sh --brightness lower"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind("Print", hl.dsp.exec_cmd('mkdir -p "$HOME/Pictures/Screenshots" && flameshot full --clipboard --path "$HOME/Pictures/Screenshots"'), { locked = true })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd('mkdir -p "$HOME/Pictures/Screenshots" && flameshot gui --clipboard --path "$HOME/Pictures/Screenshots"'))

hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd("pavucontrol"))
hl.bind("SUPER + W", hl.dsp.exec_cmd(browser))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("rofi -show wallpaper -modi \"wallpaper:~/.config/hypr/scripts/wallpaper-picker.sh\" -theme ~/.config/rofi/wallpaper-picker.rasi -show-icons -p \"\""))
hl.bind("SUPER + SHIFT + H", hl.dsp.exec_cmd("~/.config/hypr/scripts/clipboard.sh"))
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(fileManager))
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd(menu), { release = true })
hl.bind("SUPER + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/restart-waybar-swaync.sh"))
-- move the bar between the top and the left edge (OLED: no static bar)
hl.bind("SUPER + B", hl.dsp.exec_cmd("~/.config/waybar/scripts/bar-position.sh"))

hl.bind("CTRL + SUPER + left", hl.dsp.focus({ workspace = "-1" }))
hl.bind("CTRL + SUPER + right", hl.dsp.focus({ workspace = "+1" }))
hl.bind("SUPER + Z", hl.dsp.window.drag())
hl.bind("SUPER + X", hl.dsp.window.resize())

hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen({ mode = 1 }))

hl.bind("SUPER + N", hl.dsp.exec_cmd("swaync-client -t -sw"))

hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"))
-- Lid closed: lock via hypridle's lock_cmd ("pidof hyprlock || hyprlock"), so
-- hyprlock never starts twice. Opening the lid doesn't need a bind.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("loginctl lock-session"), { locked = true })
