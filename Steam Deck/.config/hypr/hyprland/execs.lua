hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("waybar")
    -- on-screen display for the volume/brightness keys (swayosd-client talks to it)
    hl.exec_cmd("swayosd-server")
    -- swaync runs as a systemd user service, so D-Bus activation can't start a
    -- second copy (on the Deck the brightness slider's device is set first)
    hl.exec_cmd("~/.config/hypr/scripts/backlight-device.sh; systemctl --user start swaync")

    hl.exec_cmd("hyprctl setcursor " .. cursorTheme .. " " .. cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme '" .. cursorTheme .. "'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. cursorSize)

    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme " .. gtktheme)
    hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')
    hl.exec_cmd('gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"')

    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")

    hl.exec_cmd("hypridle")

    -- Generate accent colors from current wallpaper
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper.sh")

    -- Clipboard manager (cliphist)
    hl.exec_cmd("wl-paste --watch cliphist store")

    -- ===== Steam Deck / tablet =====
    -- On-screen keyboard: squeekboard pops up by itself when a text field is
    -- focused (only while this GNOME accessibility setting is on). osk-auto.sh
    -- turns that setting off while a physical keyboard is connected.
    hl.exec_cmd("~/.config/hypr/scripts/osk-auto.sh")
    hl.exec_cmd("squeekboard")
    -- Touch-friendly app menu, kept in memory so it opens instantly
    hl.exec_cmd("~/.config/hypr/scripts/app-drawer.sh start")
    -- Touchscreen gestures (edge swipes, 3-finger swipes)
    hl.exec_cmd("~/.config/hypr/scripts/touch-gestures.sh")
    -- Tell me about BIOS updates (status written by steamdeck-bios-update)
    hl.exec_cmd("~/.config/hypr/scripts/bios-update-notify.sh --watch")

    -- Claude Desktop in the tray: --startup starts it without opening its
    -- window (click its tray icon in waybar to open it)
    hl.exec_cmd("claude-desktop --startup")

    -- Tailscale tray icon: connect/disconnect, log in, exit nodes
    hl.exec_cmd("tailscale systray")

    -- Autostart apps
    -- hl.exec_cmd("solaar --window=hide")
    -- hl.exec_cmd("element-desktop --hidden")
    -- hl.exec_cmd("discord --start-minimized")
    -- hl.exec_cmd("localsend --hidden")
end)
