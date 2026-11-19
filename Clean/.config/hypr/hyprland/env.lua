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

-- Shader cache (AMD/Intel Mesa drivers): 12 GB instead of 1 GB, so games don't
-- have to recompile shaders that were dropped (only uses disk space as it fills)
hl.env("MESA_SHADER_CACHE_MAX_SIZE", "12G")

-- NVIDIA as the only graphics card (its driver installed by Install.sh): the
-- driver's own VA-API video decoding and OpenGL library, and the same 12 GB
-- shader cache (its default is 1 GB, and old shaders get cleaned out). Not
-- with a second, built-in graphics chip (most laptops): the desktop and apps
-- stay on that one, for the battery; start a game on NVIDIA with prime-run.
local gpus = {}
for i = 0, 9 do
    local f = io.open("/sys/class/drm/card" .. i .. "/device/vendor", "r")
    if f then
        gpus[(f:read("*l") or "")] = true
        f:close()
    end
end
if gpus["0x10de"] and not gpus["0x1002"] and not gpus["0x8086"] then
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("__GL_SHADER_DISK_CACHE_SIZE", "12000000000")
    hl.env("__GL_SHADER_DISK_CACHE_SKIP_CLEANUP", "1")
end

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
