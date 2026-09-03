-- Compatibility bridge for the existing Pywal/Matugen colors.conf.
-- Lives in hyprmodules so it is tracked; ~/.config/hypr/colors/ is generated-only.
-- The generated colors.conf remains the source of truth for hyprlock and rollback.

local home = assert(os.getenv("HOME"), "HOME is not set")
local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
    config_home = home .. "/.config"
end
local path = config_home .. "/hypr/colors/colors.conf"
local file, err = io.open(path, "r")

if not file then
    error("unable to read " .. path .. ": " .. tostring(err))
end

local colors = {}

for line in file:lines() do
    local name, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
    if name and value then
        colors[name] = value
    end
end

file:close()

if not colors.primary or not colors.secondary then
    error("colors.conf did not provide primary and secondary")
end

return colors
