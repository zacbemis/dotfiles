--------------------
---- WINDOW RULES ----
--------------------

-- Ignore maximize requests from apps
hl.window_rule({
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland (special empty class/title)
hl.window_rule({
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

-- File dialogs: float + center
hl.window_rule({
    match = {
        title = "^(Open File|Open Files|Open|Save|Save As|Export|Import|Choose File|Rename)$",
        class = ".*",
    },
    float = true,
    center = true,
})

hl.window_rule({
    match = { class = "^(xdg-desktop-portal-gtk)$" },
    float = true,
    center = true,
})

hl.window_rule({
    match = { class = "^(xdg-desktop-portal-hyprland)$" },
    float = true,
    center = true,
})

hl.window_rule({
    match = { class = "^(Xdg-desktop-portal-gtk)$" },
    float = true,
    center = true,
})

hl.window_rule({
    match = { class = "^(Xdg-desktop-portal-hyprland)$" },
    float = true,
    center = true,
})

-- Visual: opacity for all windows (active/inactive)
hl.window_rule({
    match = { class = ".*" },
    opacity = "0.98 0.98",
})

-------------------
---- LAYER RULES ----
-------------------

-- Quickshell surfaces.
hl.layer_rule({
    match = { namespace = "^quickshell-(bar|compare-.*|dev-.*)$" },
    blur = true,
    ignore_alpha = 0.5,
})
hl.layer_rule({
    name = "quickshell-card-motion",
    match = { namespace = "^quickshell-dev-(launcher|wallpaper|notifications|controls|settings|panel)$" },
    no_anim = true,
})
