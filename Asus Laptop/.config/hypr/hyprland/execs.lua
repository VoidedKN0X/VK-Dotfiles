hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")

    hl.exec_cmd("hyprctl setcursor " .. cursorTheme .. " " .. cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme '" .. cursorTheme .. "'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. cursorSize)

    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme " .. gtktheme)
    hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')
    hl.exec_cmd('gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"')

    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")

    hl.exec_cmd("hypridle")

    -- Autostart apps
    hl.exec_cmd("solaar --window=hide")
    hl.exec_cmd("element-desktop --hidden")
    hl.exec_cmd("discord --start-minimized")
    hl.exec_cmd("localsend --hidden")
end)
