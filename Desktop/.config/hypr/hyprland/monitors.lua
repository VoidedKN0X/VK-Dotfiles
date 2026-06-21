hl.monitor({
    output = "DP-1",
    mode = "3440x1440@165",
    position = "0x0",
    scale = 1,
    bitdepth = 10,
})

hl.monitor({
    output = "DP-2",
    mode = "2560x1440@165",
    position = "3440x-730",
    scale = 1,
    transform = 3,
    bitdepth = 10,
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
