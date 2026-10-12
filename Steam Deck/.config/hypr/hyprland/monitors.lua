-- Steam Deck LCD: the panel is physically portrait (800x1280). transform = 3
-- rotates it 270 degrees so the desktop is landscape (1280x800).
hl.monitor({
    output = "eDP-1",
    mode = "800x1280@60",
    position = "0x0",
    scale = 1,
    transform = 3,
})

-- Anything else (a monitor on a USB-C dock): preferred mode, placed automatically
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.workspace_rule({ workspace = "1", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "2", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "eDP-1", persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "eDP-1", persistent = true })
