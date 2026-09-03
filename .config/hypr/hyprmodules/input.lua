------------
---- INPUT ----
------------

hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        -- The later duplicate in the legacy file is the effective value.
        kb_options = "caps:escape",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
            disable_while_typing = false,
            tap_to_click = true,
            clickfinger_behavior = false,
            middle_button_emulation = false,
        },
    },
})

hl.device({
    name = "epic-mouse-v1",
    sensitivity = -0.5,
})
