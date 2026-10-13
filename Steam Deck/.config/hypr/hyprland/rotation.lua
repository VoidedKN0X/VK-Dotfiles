-- Screen rotation of the built-in panel, shared by monitors.lua (display) and
-- input.lua (touchscreen). scripts/rotate.sh (the rotate button in the
-- notification center) switches it live and saves it here, so it survives
-- reloads and reboots. 3 = landscape (default), 0 = portrait.
screenTransform = 3

local f = io.open(os.getenv("HOME") .. "/.local/state/hypr/rotation", "r")
if f then
    if f:read("l") == "0" then
        screenTransform = 0
    end
    f:close()
end
