---------------------
---- LOOK AND FEEL ----
---------------------

local palette = require("hyprmodules.colors")

hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border = {
                colors = { palette.primary, palette.secondary },
                angle = 45,
            },
            inactive_border = "rgba(00000000)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding = 10,
        rounding_power = 2,
        active_opacity = 1.0,
        inactive_opacity = 0.98,

        shadow = {
            enabled = false,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },

        blur = {
            enabled = true,
            size = 5,
            passes = 2,
            ignore_opacity = true,
            new_optimizations = true,
            special = false,
            popups = true,
            xray = true,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

hl.curve("wind", {
    type = "bezier",
    points = { { 0.05, 0.85 }, { 0.03, 0.97 } },
})
hl.curve("winIn", {
    type = "bezier",
    points = { { 0.07, 0.88 }, { 0.04, 0.99 } },
})
hl.curve("winOut", {
    type = "bezier",
    points = { { 0.20, -0.15 }, { 0, 1 } },
})
hl.curve("liner", {
    type = "bezier",
    points = { { 1, 1 }, { 1, 1 } },
})
hl.curve("md3_standard", {
    type = "bezier",
    points = { { 0.12, 0 }, { 0, 1 } },
})
hl.curve("md3_decel", {
    type = "bezier",
    points = { { 0.05, 0.80 }, { 0.10, 0.97 } },
})
hl.curve("md3_accel", {
    type = "bezier",
    points = { { 0.20, 0 }, { 0.80, 0.08 } },
})
hl.curve("overshot", {
    type = "bezier",
    points = { { 0.05, 0.85 }, { 0.07, 1.04 } },
})
hl.curve("crazyshot", {
    type = "bezier",
    points = { { 0.1, 1.22 }, { 0.68, 0.98 } },
})
hl.curve("hyprnostretch", {
    type = "bezier",
    points = { { 0.05, 0.82 }, { 0.03, 0.94 } },
})
hl.curve("menu_decel", {
    type = "bezier",
    points = { { 0.05, 0.82 }, { 0, 1 } },
})
hl.curve("menu_accel", {
    type = "bezier",
    points = { { 0.20, 0 }, { 0.82, 0.10 } },
})
hl.curve("easeInOutCirc", {
    type = "bezier",
    points = { { 0.75, 0 }, { 0.15, 1 } },
})
hl.curve("easeOutCirc", {
    type = "bezier",
    points = { { 0, 0.48 }, { 0.38, 1 } },
})
hl.curve("easeOutExpo", {
    type = "bezier",
    points = { { 0.10, 0.94 }, { 0.23, 0.98 } },
})
hl.curve("softAcDecel", {
    type = "bezier",
    points = { { 0.20, 0.20 }, { 0.15, 1 } },
})
hl.curve("md2", {
    type = "bezier",
    points = { { 0.30, 0 }, { 0.15, 1 } },
})
hl.curve("OutBack", {
    type = "bezier",
    points = { { 0.28, 1.40 }, { 0.58, 1 } },
})
-- Preserve the later legacy definition; it shadows the earlier one.
hl.curve("easeInOutCirc", {
    type = "bezier",
    points = { { 0.78, 0 }, { 0.15, 1 } },
})

hl.animation({ leaf = "border", enabled = true, speed = 1.6, bezier = "liner" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 82, bezier = "liner", style = "loop" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.2, bezier = "winIn", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.8, bezier = "easeOutCirc" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.0, bezier = "wind", style = "slide" })
hl.animation({ leaf = "fade", enabled = true, speed = 1.8, bezier = "md3_decel" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.0, bezier = "menu_decel", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.3, bezier = "md3_decel", style = "slidefadevert 15%" })

hl.config({
    dwindle = {
        preserve_split = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = false,
    },
})
