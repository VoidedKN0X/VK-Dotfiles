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

    -- KDE Connect's background service, for the phone: the bar shows its
    -- battery, the control center a phone card (quickshell/services/Phone.qml);
    -- its own tray icon isn't used
    hl.exec_cmd("kdeconnectd")

    -- Your own autostart apps go here, for example:
    -- hl.exec_cmd("steam -silent")
end)
