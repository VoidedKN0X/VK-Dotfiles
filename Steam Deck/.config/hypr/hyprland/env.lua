hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- every Qt app in the Kvantum style (the frosted glass, hypr/scripts/
-- kvantum-glass.sh), also the ones that don't take it from qt6ct: Qt 5 apps
-- (qt6ct is Qt 6 only) and apps that pick a style themselves (Prism Launcher)
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("XCURSOR_THEME", cursorTheme)
hl.env("XCURSOR_SIZE", cursorSize)

hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Shader cache (AMD's Mesa driver): 12 GB instead of 1 GB, so games don't
-- have to recompile shaders that were dropped (only uses disk space as it fills)
hl.env("MESA_SHADER_CACHE_MAX_SIZE", "12G")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
