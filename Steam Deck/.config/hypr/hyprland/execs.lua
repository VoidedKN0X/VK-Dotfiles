hl.on("hyprland.start", function()
    -- the wallpaper, bar, control center, notifications, launcher and popups,
    -- and the password dialog for admin rights (~/.config/quickshell)
    hl.exec_cmd("qs")

    hl.exec_cmd("hyprctl setcursor " .. cursorTheme .. " " .. cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme '" .. cursorTheme .. "'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. cursorSize)

    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme " .. gtktheme)
    hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')
    hl.exec_cmd('gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"')

    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")

    hl.exec_cmd("hypridle")

    -- Generate accent colors from current wallpaper
    hl.exec_cmd("~/.config/hypr/scripts/wallpaper.sh")

    -- Clipboard manager (cliphist)
    hl.exec_cmd("wl-paste --watch cliphist store")

    -- ===== Steam Deck / tablet =====
    -- On-screen keyboard: squeekboard never pops up by itself in text fields
    -- (this GNOME accessibility setting is turned off); it's shown and hidden
    -- with the keyboard button in the bar (osk-toggle.sh).
    hl.exec_cmd("gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false")
    hl.exec_cmd("squeekboard")
    -- Touchscreen gestures (edge swipes, 3-finger swipes)
    hl.exec_cmd("~/.config/hypr/scripts/touch-gestures.sh")
    -- Tell me about BIOS updates (status written by steamdeck-bios-update)
    hl.exec_cmd("~/.config/hypr/scripts/bios-update-notify.sh --watch")

    -- Claude Desktop in the tray: --startup starts it without opening its
    -- window (click its tray icon in the bar to open it).
    -- --password-store=gnome-libsecret keeps its login in the GNOME keyring
    -- (gnome-keyring is installed by Install.sh).
    -- Turned off for now, so the app can be set up first; remove the "-- "
    -- below to turn it on.
    -- hl.exec_cmd("claude-desktop --startup --password-store=gnome-libsecret")

    -- Tailscale tray icon: connect/disconnect, log in, exit nodes
    hl.exec_cmd("tailscale systray")

    -- Autostart apps
    -- hl.exec_cmd("solaar --window=hide")
    -- hl.exec_cmd("element-desktop --hidden")
    -- hl.exec_cmd("discord --start-minimized")
    -- hl.exec_cmd("localsend --hidden")
end)
