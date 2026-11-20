"use client";

import {
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
  type CSSProperties,
  type ReactNode,
} from "react";
import { controller, type ActivePopup } from "./controller.js";
import "./overlay.css";
import {
  colorWithAlpha,
  gradientStops,
  isDarkBackground,
  isGradientUrl,
  type PopupButton,
  type PopupContent,
  type PopupImage,
  type PopupSize,
} from "./parse.js";

const DESKTOP = 768;

function useViewport() {
  const [size, setSize] = useState(() =>
    typeof window === "undefined"
      ? { width: DESKTOP, height: 800 }
      : { width: window.innerWidth, height: window.innerHeight }
  );
  useEffect(() => {
    const update = () => setSize({ width: window.innerWidth, height: window.innerHeight });
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);
  return { width: size.width, height: size.height, desktop: size.width >= DESKTOP };
}

function themeVars(content: PopupContent): CSSProperties {
  return {
    background: content.theme.background,
    color: content.theme.text,
    ["--popup-bg" as string]: content.theme.background,
    ["--popup-text" as string]: content.theme.text,
    ["--popup-radius" as string]: `${content.theme.radius}px`,
  };
}

/** Shrinks a fixed-ratio card so both sides stay inside the viewport. `ratio` is width / height. */
function fitRatio(
  width: number,
  ratio: number,
  screenWidth: number,
  screenHeight: number
): { width: number; height: number } {
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

function cardWidth(size: PopupSize, desktop: boolean, screenWidth: number) {
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

function CloseButton({
  content,
  dark,
  onClose,
  inset,
}: {
  content: PopupContent;
  dark: boolean;
  onClose: () => void;
  inset?: boolean;
}) {
  if (!content.close.show) return null;
  const left = content.close.position === "topLeft";
  return (
    <button
      type="button"
      aria-label="Close"
      onClick={onClose}
      style={{
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
      }}
    >
      <span
        style={{
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
        }}
      >
        ×
      </span>
    </button>
  );
}

function PopupImageView({
  image,
  tappable,
  onTap,
  placeholder,
  radius,
}: {
  image: PopupImage;
  tappable: boolean;
  onTap: () => void;
  placeholder: string;
  radius?: number;
}) {
  const alt = image.alt?.trim();
  const body = isGradientUrl(image.url) ? (
    <div
      role={!tappable && alt ? "img" : undefined}
      aria-label={!tappable ? alt : undefined}
      style={{
        width: "100%",
        height: "100%",
        background: `linear-gradient(135deg, ${gradientStops(image.url).join(", ")})`,
      }}
    />
  ) : (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={image.url}
      alt={image.alt ?? ""}
      style={{ width: "100%", height: "100%", objectFit: "cover", background: colorWithAlpha(placeholder, 0x14 / 0xff) }}
    />
  );
  const clipped = (
    <div style={{ width: "100%", height: "100%", overflow: "hidden", borderRadius: radius }}>
      {body}
    </div>
  );
  if (!tappable) return clipped;
  return (
    <button
      type="button"
      onClick={onTap}
      aria-label={alt || "Image"}
      style={{
        padding: 0,
        border: "none",
        background: "transparent",
        width: "100%",
        height: "100%",
        cursor: "pointer",
        display: "block",
      }}
    >
      {clipped}
    </button>
  );
}

function Buttons({
  buttons,
  content,
  compact,
  onButton,
}: {
  buttons: PopupButton[];
  content: PopupContent;
  compact?: boolean;
  onButton: (index: number) => void;
}) {
  if (!buttons.length) return null;
  return (
    <div className={compact ? undefined : "optikpi-actions"}
      style={
        compact
          ? { marginTop: 0, display: "flex", flexDirection: "row", gap: 8 }
          : undefined
      }
    >
      {buttons.map((button, index) => {
        const primary = button.style === "primary";
        return (
          <button
            key={index}
            type="button"
            onClick={() => onButton(index)}
            style={{
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
            }}
          >
            {button.label || "Button"}
          </button>
        );
      })}
    </div>
  );
}

function TextBlock({
  content,
  titleSize = 16,
  bodySize = 14,
  fluid = false,
}: {
  content: PopupContent;
  titleSize?: number;
  bodySize?: number;
  fluid?: boolean;
}) {
  return (
    <div>
      {content.title ? (
        <div
          className="optikpi-title"
          style={{ fontSize: fluid ? undefined : titleSize, fontWeight: 600, lineHeight: 1.375 }}
        >
          {content.title}
        </div>
      ) : null}
      {content.body ? (
        <div
          className="optikpi-copy"
          style={{
            marginTop: content.title ? 6 : 0,
            fontSize: fluid ? undefined : bodySize,
            lineHeight: 1.625,
            color: content.theme.text,
            opacity: 0.8,
          }}
        >
          {content.body}
        </div>
      ) : null}
    </div>
  );
}

const TABBABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

function dialogLabel(content: PopupContent): string {
  const title = content.title?.trim();
  if (title) return title;
  const alt = content.image?.alt?.trim();
  if (alt) return alt;
  return "Pop-up";
}

/** Title and body the layout actually shows, so a screen reader hears the same message. */
function liveMessage(content: PopupContent): string {
  const hideBody = content.layout === "banner" && content.size === "iab_320x50";
  const parts = [content.title, hideBody ? undefined : content.body, content.image?.alt]
    .map((part) => part?.trim())
    .filter((part): part is string => Boolean(part));
  return parts.join(". ") || "Pop-up";
}

const POLITE_LIVE_STYLE: CSSProperties = {
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

function PoliteStatus({ text }: { text: string }) {
  const [message, setMessage] = useState("");
  useEffect(() => {
    const id = window.setTimeout(() => setMessage(text), 50);
    return () => window.clearTimeout(id);
  }, [text]);
  return (
    <div role="status" aria-live="polite" aria-atomic="true" style={POLITE_LIVE_STYLE}>
      {message}
    </div>
  );
}

function tabbable(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(TABBABLE)].filter((el) => {
    if (el.getAttribute("aria-hidden") === "true") return false;
    const style = window.getComputedStyle(el);
    return style.display !== "none" && style.visibility !== "hidden";
  });
}

/** Marks every element outside the dialog inert, including siblings of its ancestors. */
function isolateBackground(dialog: HTMLElement): () => void {
  const touched: HTMLElement[] = [];
  let node: HTMLElement | null = dialog;
  while (node && node !== document.body) {
    const parent: HTMLElement | null = node.parentElement;
    if (!parent) break;
    for (const child of parent.children) {
      if (child === node || !(child instanceof HTMLElement)) continue;
      if (child.inert || child.getAttribute("aria-hidden") === "true") continue;
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

function moveFocusInside(dialog: HTMLElement) {
  const [first] = tabbable(dialog);
  (first ?? dialog).focus();
}

function trapTab(dialog: HTMLElement, event: KeyboardEvent) {
  if (event.key !== "Tab") return;
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

function BlockingFrame({
  active,
  className,
  style,
  children,
}: {
  active: ActivePopup;
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    const previouslyFocused = document.activeElement;
    const restoreBackground = isolateBackground(dialog);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    moveFocusInside(dialog);
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        controller.close(active, true);
        return;
      }
      trapTab(dialog, event);
    };
    const onFocusIn = (event: FocusEvent) => {
      if (event.target instanceof Node && dialog.contains(event.target)) return;
      moveFocusInside(dialog);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("focusin", onFocusIn);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("focusin", onFocusIn);
      document.body.style.overflow = previousOverflow;
      restoreBackground();
      if (
        previouslyFocused instanceof HTMLElement &&
        previouslyFocused !== document.body &&
        document.contains(previouslyFocused)
      ) {
        previouslyFocused.focus();
      }
    };
  }, [active]);

  return (
    <div
      ref={ref}
      className={className}
      style={{ outline: "none", ...style }}
      role="dialog"
      aria-modal="true"
      aria-label={dialogLabel(active.popup.content)}
      tabIndex={-1}
    >
      {children}
    </div>
  );
}

function OverlayScrim({ content, onOutside }: { content: PopupContent; onOutside: () => void }) {
  return (
    <div
      onClick={content.close.tapOutsideToClose ? onOutside : undefined}
      style={{
        position: "absolute",
        inset: 0,
        background: `rgba(0,0,0,${content.theme.overlayOpacity})`,
      }}
    />
  );
}

function PopupCard({
  active,
  desktop,
  screenWidth,
  screenHeight,
}: {
  active: ActivePopup;
  desktop: boolean;
  screenWidth: number;
  screenHeight: number;
}) {
  const content = active.popup.content;
  const width = screenWidth;
  const dark = isDarkBackground(content.theme.background);
  const onClose = () => controller.close(active, true);
  const onButton = (index: number) => controller.tapButton(active, index);
  const onImage = () => controller.tapImage(active);
  const image = content.image;

  if (content.layout === "banner") {
    const top = content.position !== "bottom";
    const iab = content.size === "iab_320x50";
    const bannerWidth = iab ? Math.min(320, width) : width;
    return (
      <div
        style={{
          position: "fixed",
          left: "env(safe-area-inset-left, 0px)",
          right: "env(safe-area-inset-right, 0px)",
          top: top ? "env(safe-area-inset-top, 0px)" : undefined,
          bottom: top ? undefined : "env(safe-area-inset-bottom, 0px)",
          zIndex: 10050,
          display: "flex",
          justifyContent: "center",
          pointerEvents: "none",
        }}
      >
        <PoliteStatus text={liveMessage(content)} />
        <div
          style={{
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
          }}
        >
          {image ? (
            <div style={{ width: iab ? 32 : 40, height: iab ? 32 : 40, flexShrink: 0 }}>
              <PopupImageView
                image={image}
                tappable={Boolean(image.tapAction)}
                onTap={onImage}
                placeholder={content.theme.text}
                radius={6}
              />
            </div>
          ) : null}
          <div style={{ flex: 1, minWidth: 0 }}>
            {content.title ? (
              <div style={{ fontWeight: 600, fontSize: iab ? 12 : 14, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                {content.title}
              </div>
            ) : null}
            {content.body && !iab ? (
              <div style={{ fontSize: 12, opacity: 0.8, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                {content.body}
              </div>
            ) : null}
          </div>
          {content.buttons.length ? (
            <div style={{ maxWidth: "45%" }}>
              <Buttons buttons={content.buttons} content={content} compact onButton={onButton} />
            </div>
          ) : null}
          {content.close.show ? (
            <button type="button" aria-label="Close" onClick={onClose} style={{ border: "none", background: "transparent", cursor: "pointer", color: content.theme.text, opacity: 0.7 }}>
              ×
            </button>
          ) : null}
        </div>
      </div>
    );
  }

  if (content.layout === "toast") {
    const bottom = content.position === "bottomRight";
    const safeToastWidth =
      "calc(100% - 24px - env(safe-area-inset-left, 0px) - env(safe-area-inset-right, 0px))";
    const toastWidth = desktop ? (content.size === "sm" ? 280 : 340) : safeToastWidth;
    const showImage = Boolean(image) && content.size === "md";
    return (
      <div
        style={{
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
        }}
      >
        <PoliteStatus text={liveMessage(content)} />
        {showImage && image ? (
          <div style={{ width: 64, flexShrink: 0 }}>
            <PopupImageView
              image={image}
              tappable={Boolean(image.tapAction)}
              onTap={onImage}
              placeholder={content.theme.text}
            />
          </div>
        ) : null}
        <div style={{ padding: "12px 32px 12px 12px", flex: 1 }}>
          <TextBlock content={content} titleSize={14} bodySize={12} />
          {content.buttons.length ? (
            <div style={{ marginTop: 8 }}>
              <Buttons buttons={content.buttons} content={content} compact onButton={onButton} />
            </div>
          ) : null}
        </div>
        <CloseButton content={content} dark={dark} onClose={onClose} />
      </div>
    );
  }

  if (content.layout === "bottomSheet") {
    return (
      <BlockingFrame active={active} className="optikpi-inapp optikpi-stage">
        <OverlayScrim content={content} onOutside={onClose} />
        <div
          className="optikpi-sheet-panel optikpi-card"
          data-size={content.size}
          style={{ ...themeVars(content), overflow: "auto" }}
        >
          <div style={{ width: 40, height: 4, borderRadius: 2, background: "#D1D5DB", margin: "8px auto 0" }} />
          {image && content.size !== "sm" ? (
            <div
              className="optikpi-hero"
              style={{ height: desktop ? 180 : 160, margin: "12px 16px 0", width: "auto" }}
            >
              <PopupImageView
                image={image}
                tappable={Boolean(image.tapAction)}
                onTap={onImage}
                placeholder={content.theme.text}
                radius={8}
              />
            </div>
          ) : null}
          <div className="optikpi-body">
            <TextBlock content={content} fluid />
            <Buttons buttons={content.buttons} content={content} onButton={onButton} />
          </div>
          <CloseButton content={content} dark={dark} onClose={onClose} />
        </div>
      </BlockingFrame>
    );
  }

  if (content.layout === "imageOnly") {
    const iab = content.size === "iab_300x250";
    const ratio = iab ? 300 / 250 : 4 / 5;
    const fitted = fitRatio(cardWidth(content.size, desktop, width), ratio, width, screenHeight);
    const w = fitted.width;
    return (
      <BlockingFrame active={active} style={{ position: "fixed", inset: 0, zIndex: 10050 }}>
        <OverlayScrim content={content} onOutside={onClose} />
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            width: w,
            height: fitted.height,
            transform: "translate(-50%, -50%)",
            borderRadius: content.theme.radius,
            overflow: "hidden",
            boxShadow: "0 25px 50px -12px rgba(0,0,0,0.25)",
          }}
        >
          {image ? (
            <PopupImageView
              image={image}
              tappable
              onTap={onImage}
              placeholder={content.theme.text}
            />
          ) : null}
          <CloseButton content={content} dark onClose={onClose} />
        </div>
      </BlockingFrame>
    );
  }

  const iab = content.size === "iab_300x250";
  const buttons = iab ? content.buttons.slice(0, 1) : content.buttons;
  return (
    <BlockingFrame active={active} className="optikpi-inapp optikpi-stage">
      <OverlayScrim content={content} onOutside={onClose} />
      <div
        className="optikpi-modal optikpi-card"
        data-size={content.size}
        style={themeVars(content)}
      >
        {image && !iab ? (
          <div className="optikpi-hero">
            <PopupImageView
              image={image}
              tappable={Boolean(image.tapAction)}
              onTap={onImage}
              placeholder={content.theme.text}
            />
          </div>
        ) : null}
        <div className="optikpi-body" style={iab ? { padding: 16 } : undefined}>
          <TextBlock content={content} fluid />
          <Buttons buttons={buttons} content={content} onButton={onButton} />
        </div>
        <CloseButton content={content} dark={dark || Boolean(image)} onClose={onClose} />
      </div>
    </BlockingFrame>
  );
}

function subscribeActive(onChange: () => void) {
  return controller.subscribe(onChange);
}

function currentActive() {
  return controller.current;
}

function serverActive(): ActivePopup | null {
  return null;
}

export default function OptikpiInAppOverlay() {
  const active = useSyncExternalStore(subscribeActive, currentActive, serverActive);
  const { width, height, desktop } = useViewport();

  useEffect(() => {
    if (!active) return;
    let drawn = false;
    let timer: number | undefined;
    const hidden = () =>
      typeof document !== "undefined" && document.visibilityState === "hidden";
    const draw = () => {
      if (hidden()) return;
      if (!drawn) {
        drawn = true;
        controller.didDraw(active);
      }
      const seconds = active.popup.content.autoDismissSec;
      if (!seconds || timer != null) return;
      timer = window.setTimeout(() => controller.close(active, true), seconds * 1000);
    };
    draw();
    document.addEventListener("visibilitychange", draw);
    window.addEventListener("pageshow", draw);
    return () => {
      document.removeEventListener("visibilitychange", draw);
      window.removeEventListener("pageshow", draw);
      if (timer != null) window.clearTimeout(timer);
    };
  }, [active]);

  const card = useMemo(() => {
    if (!active) return null;
    return <PopupCard active={active} desktop={desktop} screenWidth={width} screenHeight={height} />;
  }, [active, desktop, width, height]);

  return card;
}

export { OptikpiInAppOverlay };
