hl.config({
    general = {
        layout = "dwindle",
        allow_tearing = true,
        gaps_workspaces = 20,
        gaps_in = 5,
        gaps_out = 10,
        border_size = 3,
    },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = true,
    },
    misc = {
        -- plain dark background instead of the Hyprland logo + splash text
        -- until the wallpaper is drawn
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
    ecosystem = {
        -- no "what's new" window after each Hyprland update
        no_update_news = true,
    },
})
