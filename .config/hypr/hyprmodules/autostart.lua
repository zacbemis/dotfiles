-----------------
---- AUTOSTART ----
-----------------

hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 20")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("wlsunset -S 05:00 -s 17:00 -t 3700 -T 6500")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("awww img ~/.config/hypr/current_wallpaper --transition-type center")
    hl.exec_cmd("~/.config/hypr/scripts/restore-colors.sh")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("~/.config/swaync/scripts/update-count.sh")
end)

hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
