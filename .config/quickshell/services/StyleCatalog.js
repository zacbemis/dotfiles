.pragma library

// Original metadata/interaction design, not imported upstream settings code.
var categories = [
    {key: "bar", label: "Top bar", glyph: "󰍹", description: "Change the bar without changing your other components.", options: [
        {key: "current", label: "Wallpaper pills", description: "Rounded modules, centered clock and application workspace icons."},
        {key: "enzo", label: "Enzo · floating", description: "A floating frame with workspace pills, window title and media."},
        {key: "mm2103", label: "MM-2103 · flat", description: "Edge-to-edge bar, numbered workspaces and optional auto-hide."}]},
    {key: "launcher", label: "Launcher", glyph: "󰀻", description: "All choices share Apps, Run, Files, search and launch history.", options: [
        {key: "current", label: "Classic list", description: "A clean list with app icons and supporting descriptions."},
        {key: "mm2103", label: "MM search", description: "A denser list with a selected-row accent marker."},
        {key: "grid", label: "App grid", description: "Large app tiles, keyboard navigation and pinned favorites."}]},
    {key: "wallpaper", label: "Wallpapers", glyph: "", description: "Browsing only previews. Applying still uses your existing wallpaper setter.", options: [
        {key: "current", label: "List + preview", description: "A file list alongside the selected image."},
        {key: "gallery", label: "Thumbnail gallery", description: "Browse a grid of named wallpaper previews."},
        {key: "carousel", label: "Cover carousel", description: "Overlapping images with wheel, touchpad and arrow navigation."}]},
    {key: "notifications", label: "Notifications", glyph: "󰂚", description: "Change presentation only. Your notification server, history and DND stay shared.", options: [
        {key: "current", label: "Classic center", description: "Left-hand grouped history, updates and media controls."},
        {key: "compact", label: "Compact cards", description: "A smaller right-hand center with concise cards."},
        {key: "stacked", label: "Application stacks", description: "Collapsible app groups with recent/today filters."}]},
    {key: "controls", label: "Quick settings", glyph: "󰒓", description: "Both layouts expose the same supported actions and hardware controls.", options: [
        {key: "compact", label: "Compact rows", description: "A narrow panel with readable action rows and sliders."},
        {key: "tiles", label: "MM-style tiles", description: "Larger action tiles arranged in a three-column grid."}]},
    {key: "osd", label: "OSD", glyph: "󰕾", description: "Passive displays only; this changes neither your volume nor your brightness.", options: [
        {key: "off", label: "Off", description: "Keep volume and brightness feedback in the bar."},
        {key: "horizontal", label: "Horizontal OSD", description: "A temporary bottom-edge value and progress bar."},
        {key: "vertical", label: "Vertical OSD", description: "A temporary upright indicator at the right edge."}]}
];
var indicators = [
    {key: "volumeIndicator", kind: "volume", label: "Sound"},
    {key: "brightnessIndicator", kind: "brightness", label: "Brightness"},
    {key: "batteryIndicator", kind: "battery", label: "Battery"}
];
var indicatorModes = [
    {key: "both", label: "Icon + %"}, {key: "icon", label: "Icon only"},
    {key: "percent", label: "% only"}, {key: "hidden", label: "Hidden"}
];
var presets = [
    {key: "classic", label: "Classic", description: "Pills and familiar lists", values: {bar: "current", launcher: "current", wallpaper: "current", notifications: "current", controls: "compact", osd: "off"}},
    {key: "mm2103", label: "MM-style", description: "Flat bar, search, carousel and tiles", values: {bar: "mm2103", launcher: "mm2103", wallpaper: "carousel", notifications: "compact", controls: "tiles", osd: "horizontal"}},
    {key: "gallery", label: "Grid + gallery", description: "Floating bar and visual pickers", values: {bar: "enzo", launcher: "grid", wallpaper: "gallery", notifications: "stacked", controls: "tiles", osd: "vertical"}}
];
function choices() {
    const result = {};
    for (const category of categories) result[category.key] = category.options.map(option => option.key);
    return result;
}
function defaults() {
    return {bar: "current", launcher: "current", wallpaper: "current", notifications: "current",
        controls: "compact", osd: "off", wallpaperColors: true, autoHide: false, pinned: false,
        volumeIndicator: "both", brightnessIndicator: "both", batteryIndicator: "both"};
}
function valid(key, value) {
    const allowed = choices();
    if (indicators.some(item => item.key === key)) return indicatorModes.some(mode => mode.key === value);
    return Object.prototype.hasOwnProperty.call(allowed, key) ? allowed[key].includes(value)
        : ["wallpaperColors", "autoHide", "pinned"].includes(key) && typeof value === "boolean";
}
function sanitize(value) {
    const result = {};
    if (!value || typeof value !== "object" || Array.isArray(value)) return result;
    for (const key of Object.keys(defaults())) if (valid(key, value[key])) result[key] = value[key];
    return result;
}
