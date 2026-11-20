const LAYOUTS = {
    modal: {
        sizes: ["sm", "md", "lg", "iab_300x250"],
        hasText: true,
        maxButtons: 2,
        autoDismiss: false,
    },
    bottomSheet: {
        sizes: ["sm", "md", "lg"],
        hasText: true,
        maxButtons: 2,
        autoDismiss: false,
    },
    banner: {
        sizes: ["md", "iab_320x50"],
        positions: ["top", "bottom"],
        hasText: true,
        maxButtons: 1,
        autoDismiss: true,
    },
    toast: {
        sizes: ["sm", "md"],
        positions: ["topRight", "bottomRight"],
        hasText: true,
        maxButtons: 1,
        autoDismiss: true,
    },
    imageOnly: {
        sizes: ["md", "lg", "iab_300x250"],
        hasText: false,
        maxButtons: 0,
        autoDismiss: false,
    },
};
const LAYOUT_NAMES = Object.keys(LAYOUTS);
const SIZE_NAMES = ["sm", "md", "lg", "iab_300x250", "iab_320x50"];
const POSITION_NAMES = [
    "top",
    "bottom",
    "center",
    "topRight",
    "bottomRight",
];
const ACTION_TYPES = ["deeplink", "url", "dismiss", "custom"];
function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}
function asEnum(value, allowed) {
    return typeof value === "string" && allowed.includes(value)
        ? value
        : null;
}
function parseColor(value, fallback) {
    if (typeof value !== "string")
        return fallback;
    const match = /^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.exec(value.trim());
    if (!match)
        return fallback;
    let digits = match[1];
    if (digits.length === 3) {
        digits = digits
            .split("")
            .map((channel) => channel + channel)
            .join("");
    }
    return `#${digits.toUpperCase()}`;
}
function parseCustomData(json) {
    const data = new Map();
    if (!Array.isArray(json))
        return [];
    for (const entry of json) {
        if (!isRecord(entry))
            continue;
        const key = typeof entry.key === "string" ? entry.key.trim() : "";
        if (!key || typeof entry.value !== "string")
            continue;
        data.set(key, entry.value);
    }
    return [...data.entries()].map(([key, value]) => ({ key, value }));
}
function parseAction(json) {
    if (!isRecord(json))
        return null;
    const type = asEnum(json.type, ACTION_TYPES);
    if (!type)
        return null;
    if (type === "custom") {
        const customData = parseCustomData(json.customData);
        if (customData.length === 0)
            return { type: "dismiss" };
        return { type, customData };
    }
    const value = typeof json.value === "string" ? json.value.trim() : "";
    if (type !== "dismiss" && !value)
        return { type: "dismiss" };
    return { type, value: type === "dismiss" ? undefined : value };
}
function parseButton(json) {
    if (!isRecord(json))
        return null;
    const action = parseAction(json.action);
    if (!action)
        return null;
    return {
        label: typeof json.label === "string" ? json.label : "",
        style: json.style === "secondary" ? "secondary" : "primary",
        action,
    };
}
function parseImage(json) {
    if (!isRecord(json))
        return undefined;
    const url = typeof json.url === "string" ? json.url.trim() : "";
    if (!url)
        return undefined;
    return {
        url,
        alt: typeof json.alt === "string" ? json.alt : undefined,
        tapAction: parseAction(json.tapAction) ?? undefined,
    };
}
function parseDelivery(json) {
    if (!isRecord(json) || !isRecord(json.availableFor))
        return undefined;
    const value = json.availableFor.value;
    const unit = json.availableFor.unit;
    if (typeof value !== "number" ||
        !Number.isFinite(value) ||
        (unit !== "hours" && unit !== "days")) {
        return undefined;
    }
    return {
        availableFor: { value, unit },
        customEndsAt: typeof json.customEndsAt === "string" ? json.customEndsAt : undefined,
        timeZone: typeof json.timeZone === "string" ? json.timeZone : undefined,
    };
}
export function isGradientUrl(url) {
    return url.startsWith("gradient:");
}
export function gradientStops(url) {
    const parts = url.slice("gradient:".length).split(",");
    const from = parseColor(parts[0], "#98A2B3");
    const to = parseColor(parts[1], from);
    return [from, to];
}
function rgbChannels(color) {
    let hex = color.startsWith("#") ? color.slice(1) : color;
    if (!/^[0-9A-Fa-f]+$/.test(hex))
        return null;
    if (hex.length === 3) {
        hex = hex
            .split("")
            .map((channel) => channel + channel)
            .join("");
    }
    if (hex.length === 8)
        hex = hex.slice(0, 6);
    if (hex.length !== 6)
        return null;
    return [
        parseInt(hex.slice(0, 2), 16),
        parseInt(hex.slice(2, 4), 16),
        parseInt(hex.slice(4, 6), 16),
    ];
}
export function isDarkBackground(background) {
    const channels = rgbChannels(background);
    if (!channels)
        return false;
    const [r, g, b] = channels;
    return r * 0.299 + g * 0.587 + b * 0.114 < 140;
}
/** CSS color with `alpha` (0–1) applied to a parsed `#RGB`, `#RRGGBB`, or `#RRGGBBAA` color. */
export function colorWithAlpha(color, alpha) {
    const channels = rgbChannels(color);
    if (!channels)
        return color;
    const [r, g, b] = channels;
    const opacity = Math.min(1, Math.max(0, alpha));
    return `rgba(${r}, ${g}, ${b}, ${opacity})`;
}
export function parsePopupContent(json) {
    if (!isRecord(json))
        return null;
    if (json.version != null && json.version !== 1)
        return null;
    const layout = asEnum(json.layout, LAYOUT_NAMES);
    if (!layout)
        return null;
    const spec = LAYOUTS[layout];
    const size = asEnum(json.size, SIZE_NAMES);
    const position = asEnum(json.position, POSITION_NAMES);
    const buttons = (Array.isArray(json.buttons) ? json.buttons : [])
        .map(parseButton)
        .filter((button) => button != null)
        .slice(0, spec.maxButtons);
    const autoDismiss = json.autoDismissSec;
    const close = isRecord(json.close) ? json.close : {};
    const theme = isRecord(json.theme) ? json.theme : {};
    const opacity = theme.overlayOpacity;
    const radius = theme.radius;
    return {
        version: 1,
        layout,
        size: size && spec.sizes.includes(size) ? size : spec.sizes[0],
        position: spec.positions
            ? position && spec.positions.includes(position)
                ? position
                : spec.positions[0]
            : undefined,
        image: parseImage(json.image),
        title: spec.hasText && typeof json.title === "string" ? json.title : undefined,
        body: spec.hasText && typeof json.body === "string" ? json.body : undefined,
        buttons,
        close: {
            show: typeof close.show === "boolean" ? close.show : true,
            position: close.position === "topLeft" ? "topLeft" : "topRight",
            tapOutsideToClose: typeof close.tapOutsideToClose === "boolean" ? close.tapOutsideToClose : true,
        },
        theme: {
            background: parseColor(theme.background, "#FFFFFF"),
            text: parseColor(theme.text, "#101828"),
            primary: parseColor(theme.primary, "#7F56D9"),
            overlayOpacity: typeof opacity === "number" && Number.isFinite(opacity)
                ? Math.min(1, Math.max(0, opacity))
                : 0.5,
            radius: typeof radius === "number" && Number.isFinite(radius) && radius >= 0 ? radius : 16,
        },
        autoDismissSec: !spec.autoDismiss
            ? undefined
            : typeof autoDismiss === "number" && Number.isFinite(autoDismiss) && autoDismiss > 0
                ? Math.ceil(autoDismiss)
                : undefined,
        delivery: parseDelivery(json.delivery),
    };
}
function parseDate(value) {
    if (typeof value !== "string")
        return undefined;
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? undefined : date;
}
export function parseInAppPopup(json) {
    if (!isRecord(json))
        return null;
    if (json.kind != null && json.kind !== "popup")
        return null;
    if (typeof json.id !== "string" || !json.id)
        return null;
    if (typeof json.trackingId !== "string" || !json.trackingId)
        return null;
    const content = parsePopupContent(json.content);
    if (!content)
        return null;
    return {
        id: json.id,
        trackingId: json.trackingId,
        campaignId: typeof json.campaignId === "string" ? json.campaignId : undefined,
        createdAt: parseDate(json.createdAt) ?? new Date(0),
        expiresAt: parseDate(json.expiresAt),
        content,
    };
}
export function parseFetchResult(json) {
    const map = isRecord(json) ? json : {};
    const list = Array.isArray(map.popups) ? map.popups : [];
    const next = map.nextCheckAfterSec;
    return {
        popups: list
            .map(parseInAppPopup)
            .filter((popup) => popup != null),
        nextCheckAfterSec: typeof next === "number" && Number.isFinite(next) ? Math.round(next) : undefined,
    };
}
export function popupBlocksPage(layout) {
    return layout !== "banner" && layout !== "toast";
}
//# sourceMappingURL=parse.js.map