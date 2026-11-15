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
            -- frosted glass (the frame, its popups, see-through windows): a
            -- strong, smooth blur (3 passes of 6 px) with a little grain
            -- (noise) and color (vibrancy), so the glass can be very
            -- see-through and text on it still reads
            size = 6,
            passes = 3,
            noise = 0.03,
            vibrancy = 0.2,
        },
        shadow = {
            enabled = false,
            range = 20,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },
    },
})
