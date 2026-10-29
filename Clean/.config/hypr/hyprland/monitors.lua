-- Every monitor at its preferred resolution and refresh rate, placed
-- automatically. To set one up yourself, add a block per monitor (names from
-- `hyprctl monitors`), for example:
--   hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
-- and pin workspaces to it with
--   hl.workspace_rule({ workspace = "1", monitor = "DP-1", persistent = true })
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
    vrr = 3,  -- adaptive sync only for fullscreen games and video
})
