-- Compatibility bridge for the existing Pywal/Matugen colors.conf.
-- Lives in hyprmodules so it is tracked; ~/.config/hypr/colors/ is generated-only.
-- The generated colors.conf remains the source of truth for hyprlock and rollback.

local home = assert(os.getenv("HOME"), "HOME is not set")
local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
    config_home = home .. "/.config"
end
local path = config_home .. "/hypr/colors/colors.conf"
local file = io.open(path, "r")
local colors = {}

if file then
    for line in file:lines() do
        local name, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
        if name and value then
            colors[name] = value
        end
    end
    file:close()
end

-- Generated files may not exist on first login or after cache cleanup.
-- Keep the compositor usable until the wallpaper pipeline regenerates them.
local defaults = {
    primary = "rgba(89b4faff)",
    secondary = "rgba(cba6f7ff)",
}
for name, fallback in pairs(defaults) do
    local value = colors[name]
    if not value or not (value:match("^rgba%(%x%x%x%x%x%x%x%x%)$")
        or value:match("^rgb%(%x%x%x%x%x%x%)$")) then
        colors[name] = fallback
    end
end

return colors
