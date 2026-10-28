hl.monitor({
    output = "DP-1",
    mode = "3440x1440@280",
    position = "0x0",
    scale = 1,
    bitdepth = 10,
    cm = "hdr",
    -- MSI MAG 341CQ X28; luminance values from EDID HDR static metadata
    max_luminance = 519,
    max_avg_luminance = 308,
    min_luminance = 0,
    sdr_max_luminance = 300,  -- SDR white level; panel's rated SDR brightness
    sdr_eotf = "gamma22",  -- decode SDR as gamma 2.2 (fixes washed-out look)
    vrr = 3,  -- adaptive sync only for fullscreen games and video
})

hl.monitor({
    output = "DP-2",
    mode = "2560x1440@165",
    position = "3440x-415",
    scale = 1,
    transform = 3,
    bitdepth = 10,
    vrr = 3,  -- adaptive sync only for fullscreen games and video
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
