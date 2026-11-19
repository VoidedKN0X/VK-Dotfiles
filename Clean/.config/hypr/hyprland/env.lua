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

-- NVIDIA as the main graphics card (its driver installed by Install.sh): the
-- driver's own VA-API video decoding and OpenGL library, and the same 12 GB
-- shader cache (its default is 1 GB, and old shaders get cleaned out). That's
-- any desktop PC with an NVIDIA card (the monitors are on it, also when the
-- CPU has built-in graphics too), and a laptop with only NVIDIA. Not a laptop
-- with built-in graphics plus NVIDIA: the screen is on the built-in chip,
-- the desktop and apps stay there for the battery, and prime-run starts a
-- game on NVIDIA.
local function read(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local value = f:read("*l")
    f:close()
    return value
end
local gpus = {}
for i = 0, 9 do
    local vendor = read("/sys/class/drm/card" .. i .. "/device/vendor")
    if vendor then
        gpus[vendor] = true
    end
end
-- a laptop: a system battery, or a portable chassis type (like the install's
-- hw_is_laptop: 8 portable, 9 laptop, 10 notebook, 11 handheld, 14 sub-notebook,
-- 30 tablet, 31 convertible, 32 detachable)
local laptop = false
for _, name in ipairs({ "BAT0", "BAT1", "BAT2", "BATT", "BATC" }) do
    if read("/sys/class/power_supply/" .. name .. "/type") == "Battery" then
        laptop = true
    end
end
local portable = { ["8"] = true, ["9"] = true, ["10"] = true, ["11"] = true, ["14"] = true, ["30"] = true, ["31"] = true, ["32"] = true }
if portable[read("/sys/class/dmi/id/chassis_type") or ""] then
    laptop = true
end
local builtin = gpus["0x1002"] or gpus["0x8086"]
if gpus["0x10de"] and not (laptop and builtin) then
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
