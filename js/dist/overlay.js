"use client";
import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore, } from "react";
import { controller } from "./controller.js";
import "./overlay.css";
import { colorWithAlpha, gradientStops, isDarkBackground, isGradientUrl, } from "./parse.js";
const DESKTOP = 768;
function useViewport() {
    const [size, setSize] = useState(() => typeof window === "undefined"
        ? { width: DESKTOP, height: 800 }
        : { width: window.innerWidth, height: window.innerHeight });
    useEffect(() => {
        const update = () => setSize({ width: window.innerWidth, height: window.innerHeight });
        update();
        window.addEventListener("resize", update);
        return () => window.removeEventListener("resize", update);
    }, []);
    return { width: size.width, height: size.height, desktop: size.width >= DESKTOP };
}
function themeVars(content) {
    return {
        background: content.theme.background,
        color: content.theme.text,
        ["--popup-bg"]: content.theme.background,
        ["--popup-text"]: content.theme.text,
        ["--popup-radius"]: `${content.theme.radius}px`,
    };
}
/** Shrinks a fixed-ratio card so both sides stay inside the viewport. `ratio` is width / height. */
function fitRatio(width, ratio, screenWidth, screenHeight) {
    const maxWidth = Math.max(0, screenWidth);
    const maxHeight = Math.max(0, screenHeight) * 0.9;
    let nextWidth = Math.min(width, maxWidth);
    let nextHeight = nextWidth / ratio;
    if (nextHeight > maxHeight) {
        nextHeight = maxHeight;
        nextWidth = nextHeight * ratio;
    }
    return { width: nextWidth, height: nextHeight };
}
function cardWidth(size, desktop, screenWidth) {
    switch (size) {
        case "sm":
            return desktop ? 320 : screenWidth * 0.72;
        case "lg":
            return desktop ? 520 : screenWidth * 0.92;
        case "iab_300x250":
            return desktop ? 300 : Math.min(300, screenWidth * 0.92);
        default:
            return desktop ? 400 : screenWidth * 0.84;
    }
}
function CloseButton({ content, dark, onClose, inset, }) {
    if (!content.close.show)
        return null;
    const left = content.close.position === "topLeft";
    return (_jsx("button", { type: "button", "aria-label": "Close", onClick: onClose, style: {
            position: "absolute",
            top: inset ? 0 : 0,
            left: left ? 0 : undefined,
            right: left ? undefined : 0,
            width: 40,
            height: 40,
            border: "none",
            background: "transparent",
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 2,
        }, children: _jsx("span", { style: {
                width: 24,
                height: 24,
                borderRadius: 12,
                background: dark ? "rgba(0,0,0,0.4)" : "rgba(255,255,255,0.8)",
                color: dark ? "#fff" : "#374151",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: 16,
                lineHeight: 1,
            }, children: "\u00D7" }) }));
}
function PopupImageView({ image, tappable, onTap, placeholder, radius, }) {
    const alt = image.alt?.trim();
    const body = isGradientUrl(image.url) ? (_jsx("div", { role: !tappable && alt ? "img" : undefined, "aria-label": !tappable ? alt : undefined, style: {
            width: "100%",
            height: "100%",
            background: `linear-gradient(135deg, ${gradientStops(image.url).join(", ")})`,
        } })) : (
    // eslint-disable-next-line @next/next/no-img-element
    _jsx("img", { src: image.url, alt: image.alt ?? "", style: { width: "100%", height: "100%", objectFit: "cover", background: colorWithAlpha(placeholder, 0x14 / 0xff) } }));
    const clipped = (_jsx("div", { style: { width: "100%", height: "100%", overflow: "hidden", borderRadius: radius }, children: body }));
    if (!tappable)
        return clipped;
    return (_jsx("button", { type: "button", onClick: onTap, "aria-label": alt || "Image", style: {
            padding: 0,
            border: "none",
            background: "transparent",
            width: "100%",
            height: "100%",
            cursor: "pointer",
            display: "block",
        }, children: clipped }));
}
function Buttons({ buttons, content, compact, onButton, }) {
    if (!buttons.length)
        return null;
    return (_jsx("div", { className: compact ? undefined : "optikpi-actions", style: compact
            ? { marginTop: 0, display: "flex", flexDirection: "row", gap: 8 }
            : undefined, children: buttons.map((button, index) => {
            const primary = button.style === "primary";
            return (_jsx("button", { type: "button", onClick: () => onButton(index), style: {
                    padding: compact ? "6px 12px" : undefined,
                    borderRadius: compact ? 8 : undefined,
                    border: primary ? "none" : `1px solid ${colorWithAlpha(content.theme.text, 0x33 / 0xff)}`,
                    background: primary ? content.theme.primary : "transparent",
                    color: primary ? "#fff" : content.theme.text,
                    fontWeight: compact ? 600 : undefined,
                    fontSize: compact ? 12 : undefined,
                    cursor: "pointer",
                    whiteSpace: compact ? "nowrap" : undefined,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                }, children: button.label || "Button" }, index));
        }) }));
}
function TextBlock({ content, titleSize = 16, bodySize = 14, fluid = false, }) {
    return (_jsxs("div", { children: [content.title ? (_jsx("div", { className: "optikpi-title", style: { fontSize: fluid ? undefined : titleSize, fontWeight: 600, lineHeight: 1.375 }, children: content.title })) : null, content.body ? (_jsx("div", { className: "optikpi-copy", style: {
                    marginTop: content.title ? 6 : 0,
                    fontSize: fluid ? undefined : bodySize,
                    lineHeight: 1.625,
                    color: content.theme.text,
                    opacity: 0.8,
                }, children: content.body })) : null] }));
}
const TABBABLE = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
function dialogLabel(content) {
    const title = content.title?.trim();
    if (title)
        return title;
    const alt = content.image?.alt?.trim();
    if (alt)
        return alt;
    return "Pop-up";
}
/** Title and body the layout actually shows, so a screen reader hears the same message. */
function liveMessage(content) {
    const hideBody = content.layout === "banner" && content.size === "iab_320x50";
    const parts = [content.title, hideBody ? undefined : content.body, content.image?.alt]
        .map((part) => part?.trim())
        .filter((part) => Boolean(part));
    return parts.join(". ") || "Pop-up";
}
const POLITE_LIVE_STYLE = {
    position: "absolute",
    width: 1,
    height: 1,
    padding: 0,
    margin: -1,
    overflow: "hidden",
    clip: "rect(0, 0, 0, 0)",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
    border: 0,
    pointerEvents: "none",
};
function PoliteStatus({ text }) {
    const [message, setMessage] = useState("");
    useEffect(() => {
        const id = window.setTimeout(() => setMessage(text), 50);
        return () => window.clearTimeout(id);
    }, [text]);
    return (_jsx("div", { role: "status", "aria-live": "polite", "aria-atomic": "true", style: POLITE_LIVE_STYLE, children: message }));
}
function tabbable(root) {
    return [...root.querySelectorAll(TABBABLE)].filter((el) => {
        if (el.getAttribute("aria-hidden") === "true")
            return false;
        const style = window.getComputedStyle(el);
        return style.display !== "none" && style.visibility !== "hidden";
    });
}
/** Marks every element outside the dialog inert, including siblings of its ancestors. */
function isolateBackground(dialog) {
    const touched = [];
    let node = dialog;
    while (node && node !== document.body) {
        const parent = node.parentElement;
        if (!parent)
            break;
        for (const child of parent.children) {
            if (child === node || !(child instanceof HTMLElement))
                continue;
            if (child.inert || child.getAttribute("aria-hidden") === "true")
                continue;
            child.inert = true;
            child.setAttribute("aria-hidden", "true");
            touched.push(child);
        }
        node = parent;
    }
    return () => {
        for (const el of touched) {
            el.inert = false;
            el.removeAttribute("aria-hidden");
        }
    };
}
function moveFocusInside(dialog) {
    const [first] = tabbable(dialog);
    (first ?? dialog).focus();
}
function trapTab(dialog, event) {
    if (event.key !== "Tab")
        return;
    const items = tabbable(dialog);
    if (items.length === 0) {
        event.preventDefault();
        dialog.focus();
        return;
    }
    const first = items[0];
    const last = items[items.length - 1];
    const current = document.activeElement;
    if (event.shiftKey) {
        if (current === first || current === dialog || !dialog.contains(current)) {
            event.preventDefault();
            last.focus();
        }
        return;
    }
    if (current === last) {
        event.preventDefault();
        first.focus();
    }
}
function BlockingFrame({ active, className, style, children, }) {
    const ref = useRef(null);
    useEffect(() => {
        const dialog = ref.current;
        if (!dialog)
            return;
        const previouslyFocused = document.activeElement;
        const restoreBackground = isolateBackground(dialog);
        const previousOverflow = document.body.style.overflow;
        document.body.style.overflow = "hidden";
        moveFocusInside(dialog);
        const onKey = (event) => {
            if (event.key === "Escape") {
                controller.close(active, true);
                return;
            }
            trapTab(dialog, event);
        };
        const onFocusIn = (event) => {
            if (event.target instanceof Node && dialog.contains(event.target))
                return;
            moveFocusInside(dialog);
        };
        document.addEventListener("keydown", onKey);
        document.addEventListener("focusin", onFocusIn);
        return () => {
            document.removeEventListener("keydown", onKey);
            document.removeEventListener("focusin", onFocusIn);
            document.body.style.overflow = previousOverflow;
            restoreBackground();
            if (previouslyFocused instanceof HTMLElement &&
                previouslyFocused !== document.body &&
                document.contains(previouslyFocused)) {
                previouslyFocused.focus();
            }
        };
    }, [active]);
    return (_jsx("div", { ref: ref, className: className, style: { outline: "none", ...style }, role: "dialog", "aria-modal": "true", "aria-label": dialogLabel(active.popup.content), tabIndex: -1, children: children }));
}
function OverlayScrim({ content, onOutside }) {
    return (_jsx("div", { onClick: content.close.tapOutsideToClose ? onOutside : undefined, style: {
            position: "absolute",
            inset: 0,
            background: `rgba(0,0,0,${content.theme.overlayOpacity})`,
        } }));
}
function PopupCard({ active, desktop, screenWidth, screenHeight, }) {
    const content = active.popup.content;
    const width = screenWidth;
    const dark = isDarkBackground(content.theme.background);
    const onClose = () => controller.close(active, true);
    const onButton = (index) => controller.tapButton(active, index);
    const onImage = () => controller.tapImage(active);
    const image = content.image;
    if (content.layout === "banner") {
        const top = content.position !== "bottom";
        const iab = content.size === "iab_320x50";
        const bannerWidth = iab ? Math.min(320, width) : width;
        return (_jsxs("div", { style: {
                position: "fixed",
                left: "env(safe-area-inset-left, 0px)",
                right: "env(safe-area-inset-right, 0px)",
                top: top ? "env(safe-area-inset-top, 0px)" : undefined,
                bottom: top ? undefined : "env(safe-area-inset-bottom, 0px)",
                zIndex: 10050,
                display: "flex",
                justifyContent: "center",
                pointerEvents: "none",
            }, children: [_jsx(PoliteStatus, { text: liveMessage(content) }), _jsxs("div", { style: {
                        pointerEvents: "auto",
                        boxSizing: "border-box",
                        width: iab ? bannerWidth : "100%",
                        maxWidth: "100%",
                        height: iab ? bannerWidth * (50 / 320) : undefined,
                        background: content.theme.background,
                        color: content.theme.text,
                        borderRadius: !desktop && !iab ? 0 : Math.min(content.theme.radius, 8),
                        boxShadow: "0 10px 15px -3px rgba(0,0,0,0.1), 0 4px 6px -4px rgba(0,0,0,0.1)",
                        padding: iab ? "0 12px" : "10px 12px",
                        display: "flex",
                        alignItems: "center",
                        gap: 12,
                    }, children: [image ? (_jsx("div", { style: { width: iab ? 32 : 40, height: iab ? 32 : 40, flexShrink: 0 }, children: _jsx(PopupImageView, { image: image, tappable: Boolean(image.tapAction), onTap: onImage, placeholder: content.theme.text, radius: 6 }) })) : null, _jsxs("div", { style: { flex: 1, minWidth: 0 }, children: [content.title ? (_jsx("div", { style: { fontWeight: 600, fontSize: iab ? 12 : 14, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }, children: content.title })) : null, content.body && !iab ? (_jsx("div", { style: { fontSize: 12, opacity: 0.8, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }, children: content.body })) : null] }), content.buttons.length ? (_jsx("div", { style: { maxWidth: "45%" }, children: _jsx(Buttons, { buttons: content.buttons, content: content, compact: true, onButton: onButton }) })) : null, content.close.show ? (_jsx("button", { type: "button", "aria-label": "Close", onClick: onClose, style: { border: "none", background: "transparent", cursor: "pointer", color: content.theme.text, opacity: 0.7 }, children: "\u00D7" })) : null] })] }));
    }
    if (content.layout === "toast") {
        const bottom = content.position === "bottomRight";
        const safeToastWidth = "calc(100% - 24px - env(safe-area-inset-left, 0px) - env(safe-area-inset-right, 0px))";
        const toastWidth = desktop ? (content.size === "sm" ? 280 : 340) : safeToastWidth;
        const showImage = Boolean(image) && content.size === "md";
        return (_jsxs("div", { style: {
                position: "fixed",
                right: "calc(12px + env(safe-area-inset-right, 0px))",
                top: bottom
                    ? undefined
                    : `calc(${desktop ? 12 : 8}px + env(safe-area-inset-top, 0px))`,
                bottom: bottom
                    ? "calc(12px + env(safe-area-inset-bottom, 0px))"
                    : undefined,
                zIndex: 10050,
                width: toastWidth,
                maxWidth: safeToastWidth,
                background: content.theme.background,
                color: content.theme.text,
                borderRadius: Math.min(content.theme.radius, 12),
                boxShadow: "0 20px 25px -5px rgba(0,0,0,0.1)",
                overflow: "hidden",
                display: "flex",
            }, children: [_jsx(PoliteStatus, { text: liveMessage(content) }), showImage && image ? (_jsx("div", { style: { width: 64, flexShrink: 0 }, children: _jsx(PopupImageView, { image: image, tappable: Boolean(image.tapAction), onTap: onImage, placeholder: content.theme.text }) })) : null, _jsxs("div", { style: { padding: "12px 32px 12px 12px", flex: 1 }, children: [_jsx(TextBlock, { content: content, titleSize: 14, bodySize: 12 }), content.buttons.length ? (_jsx("div", { style: { marginTop: 8 }, children: _jsx(Buttons, { buttons: content.buttons, content: content, compact: true, onButton: onButton }) })) : null] }), _jsx(CloseButton, { content: content, dark: dark, onClose: onClose })] }));
    }
    if (content.layout === "bottomSheet") {
        return (_jsxs(BlockingFrame, { active: active, className: "optikpi-inapp optikpi-stage", children: [_jsx(OverlayScrim, { content: content, onOutside: onClose }), _jsxs("div", { className: "optikpi-sheet-panel optikpi-card", "data-size": content.size, style: { ...themeVars(content), overflow: "auto" }, children: [_jsx("div", { style: { width: 40, height: 4, borderRadius: 2, background: "#D1D5DB", margin: "8px auto 0" } }), image && content.size !== "sm" ? (_jsx("div", { className: "optikpi-hero", style: { height: desktop ? 180 : 160, margin: "12px 16px 0", width: "auto" }, children: _jsx(PopupImageView, { image: image, tappable: Boolean(image.tapAction), onTap: onImage, placeholder: content.theme.text, radius: 8 }) })) : null, _jsxs("div", { className: "optikpi-body", children: [_jsx(TextBlock, { content: content, fluid: true }), _jsx(Buttons, { buttons: content.buttons, content: content, onButton: onButton })] }), _jsx(CloseButton, { content: content, dark: dark, onClose: onClose })] })] }));
    }
    if (content.layout === "imageOnly") {
        const iab = content.size === "iab_300x250";
        const ratio = iab ? 300 / 250 : 4 / 5;
        const fitted = fitRatio(cardWidth(content.size, desktop, width), ratio, width, screenHeight);
        const w = fitted.width;
        return (_jsxs(BlockingFrame, { active: active, style: { position: "fixed", inset: 0, zIndex: 10050 }, children: [_jsx(OverlayScrim, { content: content, onOutside: onClose }), _jsxs("div", { style: {
                        position: "absolute",
                        left: "50%",
                        top: "50%",
                        width: w,
                        height: fitted.height,
                        transform: "translate(-50%, -50%)",
                        borderRadius: content.theme.radius,
                        overflow: "hidden",
                        boxShadow: "0 25px 50px -12px rgba(0,0,0,0.25)",
                    }, children: [image ? (_jsx(PopupImageView, { image: image, tappable: true, onTap: onImage, placeholder: content.theme.text })) : null, _jsx(CloseButton, { content: content, dark: true, onClose: onClose })] })] }));
    }
    const iab = content.size === "iab_300x250";
    const buttons = iab ? content.buttons.slice(0, 1) : content.buttons;
    return (_jsxs(BlockingFrame, { active: active, className: "optikpi-inapp optikpi-stage", children: [_jsx(OverlayScrim, { content: content, onOutside: onClose }), _jsxs("div", { className: "optikpi-modal optikpi-card", "data-size": content.size, style: themeVars(content), children: [image && !iab ? (_jsx("div", { className: "optikpi-hero", children: _jsx(PopupImageView, { image: image, tappable: Boolean(image.tapAction), onTap: onImage, placeholder: content.theme.text }) })) : null, _jsxs("div", { className: "optikpi-body", style: iab ? { padding: 16 } : undefined, children: [_jsx(TextBlock, { content: content, fluid: true }), _jsx(Buttons, { buttons: buttons, content: content, onButton: onButton })] }), _jsx(CloseButton, { content: content, dark: dark || Boolean(image), onClose: onClose })] })] }));
}
function subscribeActive(onChange) {
    return controller.subscribe(onChange);
}
function currentActive() {
    return controller.current;
}
function serverActive() {
    return null;
}
export default function OptikpiInAppOverlay() {
    const active = useSyncExternalStore(subscribeActive, currentActive, serverActive);
    const { width, height, desktop } = useViewport();
    useEffect(() => {
        if (!active)
            return;
        let drawn = false;
        let timer;
        const hidden = () => typeof document !== "undefined" && document.visibilityState === "hidden";
        const draw = () => {
            if (hidden())
                return;
            if (!drawn) {
                drawn = true;
                controller.didDraw(active);
            }
            const seconds = active.popup.content.autoDismissSec;
            if (!seconds || timer != null)
                return;
            timer = window.setTimeout(() => controller.close(active, true), seconds * 1000);
        };
        draw();
        document.addEventListener("visibilitychange", draw);
        window.addEventListener("pageshow", draw);
        return () => {
            document.removeEventListener("visibilitychange", draw);
            window.removeEventListener("pageshow", draw);
            if (timer != null)
                window.clearTimeout(timer);
        };
    }, [active]);
    const card = useMemo(() => {
        if (!active)
            return null;
        return _jsx(PopupCard, { active: active, desktop: desktop, screenWidth: width, screenHeight: height });
    }, [active, desktop, width, height]);
    return card;
}
export { OptikpiInAppOverlay };
//# sourceMappingURL=overlay.js.map