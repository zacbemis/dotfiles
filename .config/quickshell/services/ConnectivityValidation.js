.pragma library

function utf8Length(value) {
    try { return encodeURIComponent(value).replace(/%[0-9a-f]{2}/gi, "x").length; }
    catch (error) { return -1; }
}

function validPsk(value, sae) {
    if (typeof value !== "string" || value.indexOf("\x00") >= 0) return false;
    const length = utf8Length(value);
    return sae ? length >= 1 && length <= 63 : (length >= 8 && length <= 63) || /^[0-9a-f]{64}$/i.test(value);
}

function validAlias(value) {
    return typeof value === "string" && value.trim() !== "" && utf8Length(value) >= 1
        && utf8Length(value) <= 248 && !/[\x00-\x1f\x7f]/.test(value);
}
