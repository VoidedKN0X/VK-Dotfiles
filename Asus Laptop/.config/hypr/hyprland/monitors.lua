hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
    vrr = 3,  -- adaptive sync only for fullscreen games and video
})

hl.workspace_rule({ workspace = "1", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "eDP-1", persistent = true })
