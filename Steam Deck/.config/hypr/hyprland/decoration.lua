hl.config({
    decoration = {
        rounding = 15,
        blur = {
            enabled = true,
            -- off: see-through windows, the bar and popups blur what is really
            -- behind them (on: only the wallpaper, which on a smooth wallpaper
            -- looks like no blur at all)
            xray = false,
            special = false,
            ignore_opacity = true,
            new_optimizations = true,
            popups = true,
            input_methods = true,
            -- softer blur plus a little grain (noise) and color (vibrancy):
            -- frosted glass instead of a heavy smear (waybar, swaync, rofi, ...)
            size = 2,
            passes = 2,
            noise = 0.02,
            vibrancy = 0.17,
        },
        shadow = {
            enabled = false,
            range = 20,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },
    },
})
