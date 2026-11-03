.pragma library

// Wallpaper colors stay the seeds. Only mix existing palette colors or move
// their tones toward an achromatic endpoint; never substitute a preset accent.
// All returned RGB colors are opaque/8-bit so audits describe rendered colors.
function clamp(value) { return Math.max(0, Math.min(1, value)); }
function rgb(color) { return [0, 1, 2].map(i => Math.round(clamp(color[i]) * 255) / 255).concat([1]); }
function over(foreground, background) {
    const fa = foreground.length > 3 ? clamp(foreground[3]) : 1;
    const ba = background.length > 3 ? clamp(background[3]) : 1;
    const alpha = fa + ba * (1 - fa);
    if (alpha === 0) return [0, 0, 0, 0];
    return [0, 1, 2].map(i => (foreground[i] * fa + background[i] * ba * (1 - fa)) / alpha).concat([alpha]);
}
function mix(first, second, amount) {
    return [0, 1, 2].map(i => first[i] + (second[i] - first[i]) * amount).concat([1]);
}
function luminance(color) {
    const linear = color.slice(0, 3).map(value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4));
    return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}
function contrast(first, second) {
    const a = luminance(first), b = luminance(second);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
function minimumContrast(color, backgrounds) {
    return Math.min.apply(null, backgrounds.map(background => contrast(rgb(over(color, background)), background)));
}
function readable(seed, backgrounds, requested) {
    backgrounds = backgrounds.map(rgb);
    // Do not silently ignore alpha on a preferred foreground.
    seed = rgb(over(seed, backgrounds[0]));
    if (minimumContrast(seed, backgrounds) >= requested) return seed;
    const endpoints = [[0, 0, 0, 1], [1, 1, 1, 1]];
    const available = Math.max.apply(null, endpoints.map(color => minimumContrast(color, backgrounds)));
    // 7:1 is not possible on every wallpaper's middle-gray base. Fall back to
    // normal-text 4.5:1, not an impossible promise or a changed desktop palette.
    const target = available >= requested ? requested : Math.min(requested, 4.5);
    const goal = Math.min(available, target + 0.05);
    const candidates = [];
    for (const endpoint of endpoints) {
        if (minimumContrast(endpoint, backgrounds) < goal) continue;
        let low = 0, high = 1;
        for (let i = 0; i < 26; ++i) {
            const middle = (low + high) / 2;
            if (minimumContrast(rgb(mix(seed, endpoint, middle)), backgrounds) >= goal) high = middle;
            else low = middle;
        }
        candidates.push({amount: high, color: rgb(mix(seed, endpoint, high))});
    }
    if (!candidates.length) return endpoints[minimumContrast(endpoints[1], backgrounds) > minimumContrast(endpoints[0], backgrounds) ? 1 : 0];
    candidates.sort((a, b) => a.amount - b.amount);
    return candidates[0].color;
}
function tone(seed, target) {
    const endpoint = luminance(seed) < target ? [1, 1, 1, 1] : [0, 0, 0, 1];
    let low = 0, high = 1;
    for (let i = 0; i < 26; ++i) {
        const middle = (low + high) / 2;
        const value = luminance(mix(seed, endpoint, middle));
        if ((luminance(seed) < target && value < target) || (luminance(seed) >= target && value > target)) low = middle;
        else high = middle;
    }
    return rgb(mix(seed, endpoint, high));
}
function panelOpacity(background) {
    const translucent = background.slice(0, 3).concat([0.98]);
    const targets = [rgb(over(translucent, [0, 0, 0, 1])), rgb(over(translucent, [1, 1, 1, 1]))];
    const available = Math.max(minimumContrast([0, 0, 0, 1], targets), minimumContrast([1, 1, 1, 1], targets));
    // Near middle gray, even 2% app/wallpaper bleed can make 4.5:1 impossible
    // for one fixed foreground. Prefer an opaque panel there.
    return available >= 4.55 ? 0.98 : 1;
}
function surface(background, hint, separation) {
    background = rgb(background);
    const base = luminance(background);
    const dark = contrast(background, [1, 1, 1, 1]) >= contrast(background, [0, 0, 0, 1]);
    // Keep all ordinary surfaces in the same text-contrast lane. Generated
    // surface_container often equals a much brighter outline/accent color.
    const target = dark ? Math.min((base + 0.05) * separation - 0.05, 1.05 / 4.55 - 0.05)
        : Math.max((base + 0.05) / separation - 0.05, 4.55 * 0.05 - 0.05);
    return tone(mix(background, rgb(hint), 0.2), clamp(target));
}
