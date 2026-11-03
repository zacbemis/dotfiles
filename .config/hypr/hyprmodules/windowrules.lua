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

-- Native transient parents/fixed-size dialogs already float in Hyprland.
-- Explicitly center modal dialogs, including ones without a familiar title.
hl.window_rule({
    name = "modal-dialogs",
    match = { modal = true },
    float = true,
    center = true,
})

-- File choosers and utility dialogs. Match the map-time title, not a page
-- title that might later change to something like "Open" or "Save".
hl.window_rule({
    name = "file-dialogs",
    match = {
        initial_title = "^(Open File|Open Files|Open|Save|Save As|Save File|Save Image As|Export|Import|Choose File|Select a File|Select a Folder|File Upload|Rename)$",
    },
    float = true,
    center = true,
})

hl.window_rule({
    name = "portal-dialogs",
    match = { class = "(?i)^(xdg-desktop-portal-(gtk|hyprland|kde)|org[.]gtk[.]Portal|org[.]kde[.]xdg-desktop-portal-kde)$" },
    float = true,
    center = true,
})

local browsers = "^(helium|chromium(-browser)?|[Gg]oogle-chrome(-stable)?|[Bb]rave-browser|firefox|org[.]mozilla[.]firefox)$"

-- Chromium/Helium window.open() popups can omit the Wayland transient-parent
-- hint. The reproduced popup maps as "about:blank - Helium", then changes
-- title. Keep this rule scoped to browsers and the initial title so regular
-- New Tab windows and ordinary pages stay tiled. A deliberately opened
-- standalone about:blank window also matches this fallback.
hl.window_rule({
    name = "browser-blank-popups",
    match = {
        initial_class = browsers,
        initial_title = "^about:blank( - (Helium|Chromium|Google Chrome|Brave|Mozilla Firefox))?$",
    },
    float = true,
    center = true,
})

hl.window_rule({
    name = "browser-utility-windows",
    match = {
        initial_class = browsers,
        initial_title = "(?i)^(picture[- ]in[- ]picture|devtools( - .*)?|developer tools( - .*)?)( - (helium|chromium|google chrome|brave|mozilla firefox))?$",
    },
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
