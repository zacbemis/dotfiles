.pragma library

// Freedesktop body markup only. Never pass img/style/arbitrary rich HTML through
// to Qt, so receiving a notification cannot load remote or local resources.
function escapeText(value) {
    return String(value).replace(/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[\da-f]+);)/gi, "&amp;")
        .replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function safeLink(value) {
    return /^(?:https?:\/\/|mailto:)./i.test(String(value)) && !/[\s\u0000-\u001f\u007f]/.test(String(value));
}
function format(value) {
    let anchors = 0;
    const output = String(value).split(/(<[^>]*>)/g).map(token => {
        if (/^<\/?(?:b|i|u)>$/i.test(token)) return token;
        if (/^<\/a>$/i.test(token)) { if (anchors) { --anchors; return "</a>"; } return ""; }
        if (/^<a>$/i.test(token)) return "";
        if (/^<br\s*\/?\s*>$/i.test(token)) return "<br/>";
        const link = token.match(/^<a\s+href\s*=\s*(["'])(.*?)\1\s*>$/i);
        if (link) {
            const url = link[2].replace(/&amp;/gi, "&").replace(/&quot;/gi, '"').replace(/&apos;/gi, "'");
            if (!safeLink(url)) return "";
            ++anchors;
            return '<a href="' + url.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;") + '">';
        }
        return escapeText(token).replace(/\r?\n/g, "<br/>");
    }).join("");
    return output + "</a>".repeat(anchors);
}
