-- DP-1 runs SDR by default (accurate for photo editing). HDR turns on by
-- itself for fullscreen HDR games/video (render.cm_auto_hdr), or manually
-- with SUPER + SHIFT + D (needed for YouTube in Chromium, which only offers
-- HDR when the screen is already in HDR mode when the page loads)
local dp1 = {
    output = "DP-1",
    mode = "3440x1440@280",
    position = "0x0",
    scale = 1,
    bitdepth = 10,
    cm = "srgb",
    supports_hdr = 1,
    -- MSI MAG 341CQ X28; luminance values from EDID HDR static metadata
    -- (only used while in HDR mode)
    max_luminance = 519,
    max_avg_luminance = 308,
    min_luminance = 0,
    sdr_max_luminance = 300,  -- SDR white level; panel's rated SDR brightness
    sdr_min_luminance = 0,  -- true black for SDR content in HDR mode (default 0.2 lifts shadows)
    sdr_eotf = "gamma22",  -- decode SDR as gamma 2.2 (fixes washed-out look)
    vrr = 3,  -- adaptive sync only for fullscreen games and video
}

hl.monitor(dp1)

-- manual HDR switch for DP-1, bound in keybinds.lua; a config reload
-- puts it back to SDR
local dp1_hdr = false
function toggle_dp1_hdr()
    dp1_hdr = not dp1_hdr
    dp1.cm = dp1_hdr and "hdr" or "srgb"
    hl.monitor(dp1)
    hl.notification.create({
        text = dp1_hdr and "DP-1: HDR on" or "DP-1: HDR off (SDR)",
        timeout = 2000,
    })
end

hl.monitor({
    output = "DP-2",
    mode = "2560x1440@165",
    position = "3440x-415",
    scale = 1,
    transform = 3,
    bitdepth = 10,
    supports_hdr = -1,  -- never auto-switch this one to HDR
    vrr = 3,  -- adaptive sync only for fullscreen games and video
})

hl.config({
    render = {
        cm_auto_hdr = 1,  -- HDR only while fullscreen HDR content is on screen
    },
})

hl.monitor({
    output = "HDMI-A-1",
    mirror = "DP-1",
})

hl.workspace_rule({ workspace = "1", monitor = "DP-1", persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "DP-1", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "DP-1" })
hl.workspace_rule({ workspace = "6", monitor = "DP-2" })
hl.workspace_rule({ workspace = "7", monitor = "DP-1" })
hl.workspace_rule({ workspace = "8", monitor = "DP-2" })
hl.workspace_rule({ workspace = "9", monitor = "DP-1" })
hl.workspace_rule({ workspace = "10", monitor = "DP-2" })
