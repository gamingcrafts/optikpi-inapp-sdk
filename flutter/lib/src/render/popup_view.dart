import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/popup_content.dart';
import 'popup_image_cache.dart';

/* Draws one PopupContent over the whole screen. A port of app_next
   `app/shared/popup/components/PopupRenderer.tsx` (dev): the same layouts, sizes and spacing, with
   Tailwind units turned into logical pixels. Differences, all Flutter-side:
   - The web preview draws inside a fake device frame; here the system insets (status bar, home
     indicator) come from MediaQuery, so fixed offsets such as `top-9` become "below the inset".
   - Widths use the reference's `mobile` values below 600 px and its `desktop` values above, so a
     tablet doesn't get a 90%-wide modal.
   - A modal or a sheet whose text is longer than the screen scrolls instead of overflowing.
   - The renderer does no merge-tag filling: the server sends the text already filled.
   This widget only draws and reports taps. Tracking and actions live in the controller. */

/// Widget keys, for tests and for apps that drive the pop-up in their own tests.
abstract final class PopupKeys {
  static const card = ValueKey('optikpi_inapp.card');
  static const overlay = ValueKey('optikpi_inapp.overlay');
  static const close = ValueKey('optikpi_inapp.close');
  static const image = ValueKey('optikpi_inapp.image');
  static ValueKey<String> button(int index) => ValueKey('optikpi_inapp.button.$index');
}

/// The breakpoint between the reference's `mobile` and `desktop` surfaces.
const double popupDesktopBreakpoint = 600;

/// Banners and toasts leave the page usable. The other layouts block it: Android back and
/// screen readers reach the pop-up, not the page under it.
bool popupBlocksPage(PopupLayout layout) =>
    layout != PopupLayout.banner && layout != PopupLayout.toast;

class PopupView extends StatelessWidget {
  const PopupView({
    super.key,
    required this.content,
    required this.onButton,
    required this.onImageTap,
    required this.onClose,
    required this.onOutsideTap,
    this.images,
  });

  final PopupContent content;

  /// Index into `content.buttons`.
  final ValueChanged<int> onButton;

  /// The image was tapped where it is a tap target (always for imageOnly, else with a tapAction).
  final VoidCallback onImageTap;

  /// The close button.
  final VoidCallback onClose;

  /// A tap on the dimmed area, only when `close.tapOutsideToClose`.
  final VoidCallback onOutsideTap;

  final PopupImageCache? images;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: content.theme.text),
        child: LayoutBuilder(
          builder:
              (context, constraints) =>
                  _Layout(
                    view: this,
                    screen: constraints.biggest,
                    insets: MediaQuery.paddingOf(context),
                  ).build(),
        ),
      ),
    );
  }
}

class _Layout {
  _Layout({required this.view, required this.screen, required this.insets});

  final PopupView view;
  final Size screen;
  final EdgeInsets insets;

  PopupContent get content => view.content;
  PopupTheme get theme => content.theme;
  bool get desktop => screen.width >= popupDesktopBreakpoint;

  Widget build() {
    return switch (content.layout) {
      PopupLayout.fullscreen => _fullscreen(),
      PopupLayout.bottomSheet => _bottomSheet(),
      PopupLayout.banner => _banner(),
      PopupLayout.toast => _toast(),
      PopupLayout.imageOnly => _imageOnly(),
      PopupLayout.modal => _modal(),
    };
  }

  // ---- shared pieces ------------------------------------------------------------------------

  Widget _overlay() => Positioned.fill(
    child: GestureDetector(
      key: PopupKeys.overlay,
      behavior: HitTestBehavior.opaque,
      onTap: content.close.tapOutsideToClose ? view.onOutsideTap : () {},
      child: ColoredBox(color: Color.fromRGBO(0, 0, 0, theme.overlayOpacity)),
    ),
  );

  /// `CloseButton`: a 24 px circle 8 px in from the corner, inside a 40 px tap target.
  Widget _closeButton({required bool dark, double top = 0}) {
    if (!content.close.show) return const SizedBox.shrink();
    final left = content.close.position == PopupClosePosition.topLeft;
    return Positioned(
      top: top,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: Semantics(
        button: true,
        label: 'Close',
        child: GestureDetector(
          key: PopupKeys.close,
          behavior: HitTestBehavior.opaque,
          onTap: view.onClose,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dark ? const Color(0x66000000) : const Color(0xCCFFFFFF),
                ),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: dark ? const Color(0xFFFFFFFF) : const Color(0xFF374151),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _image({BorderRadius? radius, bool forceTappable = false}) {
    final image = content.image!;
    final tappable = forceTappable || image.tapAction != null;
    Widget child = PopupImageView(image: image, images: view.images, placeholder: theme.text);
    if (radius != null) child = ClipRRect(borderRadius: radius, child: child);
    if (!tappable) return child;
    return GestureDetector(
      key: PopupKeys.image,
      behavior: HitTestBehavior.opaque,
      onTap: view.onImageTap,
      child: Semantics(button: true, child: child),
    );
  }

  Widget _title({double size = 16, double? height = 1.375, int? maxLines}) => Text(
    content.title!,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, height: height),
  );

  Widget _body({double size = 14, double? height = 1.625, int? maxLines}) => Text(
    content.body!,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: size,
      height: height,
      color: theme.text.withValues(alpha: theme.text.a * 0.8),
    ),
  );

  bool get _hasTitle => content.title != null && content.title!.isNotEmpty;
  bool get _hasBody => content.body != null && content.body!.isNotEmpty;

  /// `textBlock`
  Widget _textBlock() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_hasTitle) _title(),
      if (_hasBody) ...[if (_hasTitle) const SizedBox(height: 6), _body()],
    ],
  );

  /// `Buttons`: stacked full width with `mt-4`, or a compact row for banner and toast.
  Widget _buttons(List<PopupButton> buttons, {bool compact = false}) {
    if (buttons.isEmpty) return const SizedBox.shrink();
    final items = [
      for (final (index, button) in buttons.indexed) _button(index, button, compact: compact),
    ];
    if (compact) {
      // Flexible so a long label ellipsises instead of overflowing the banner or toast.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Flexible(child: item),
          ],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, item) in items.indexed) ...[if (i > 0) const SizedBox(height: 8), item],
        ],
      ),
    );
  }

  Widget _button(int index, PopupButton button, {required bool compact}) {
    final primary = button.style == PopupButtonStyle.primary;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: PopupKeys.button(index),
        behavior: HitTestBehavior.opaque,
        onTap: () => view.onButton(index),
        child: Container(
          padding:
              compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: primary ? theme.primary : null,
            border: primary ? null : Border.all(color: theme.text.withValues(alpha: 0x33 / 0xFF)),
          ),
          child: Text(
            button.label.isEmpty ? 'Button' : button.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              height: compact ? 16 / 12 : 20 / 14,
              fontWeight: FontWeight.w600,
              color: primary ? const Color(0xFFFFFFFF) : theme.text,
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _card({BorderRadius? radius, List<BoxShadow>? shadow, BoxBorder? border}) =>
      BoxDecoration(
        color: theme.background,
        borderRadius: radius,
        boxShadow: shadow,
        border: border,
      );

  /// A modal-style card's width (`MODAL_WIDTH`).
  double _cardWidth(PopupSize size) {
    final w = screen.width;
    return switch (size) {
      PopupSize.sm => desktop ? 320 : w * 0.72,
      PopupSize.lg => desktop ? 520 : w * 0.92,
      PopupSize.iab_300x250 => desktop ? 300 : math.min(300, w * 0.92),
      _ => desktop ? 400 : w * 0.84,
    };
  }

  /// Shrinks a fixed-ratio card to fit the screen height (landscape phones).
  Size _fitRatio(double width, double ratio) {
    final maxHeight = (screen.height - insets.vertical) * 0.9;
    final height = width / ratio;
    return height <= maxHeight ? Size(width, height) : Size(maxHeight * ratio, maxHeight);
  }

  // ---- layouts ------------------------------------------------------------------------------

  Widget _fullscreen() {
    final hasImage = content.image != null;
    return Stack(
      key: PopupKeys.card,
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: theme.background,
            // Fills the screen when the content fits; scrolls as a whole when it doesn't.
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasImage) SizedBox(height: screen.height * 0.52, child: _image()),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            24 + insets.left,
                            24 + (hasImage ? 0 : insets.top),
                            24 + insets.right,
                            24 + insets.bottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [_textBlock(), _buttons(content.buttons)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _closeButton(dark: true, top: insets.top),
      ],
    );
  }

  Widget _bottomSheet() {
    final fraction = switch (content.size) {
      PopupSize.sm => 0.34,
      PopupSize.lg => 0.72,
      _ => 0.50,
    };
    final height = screen.height * fraction;
    final radius = Radius.circular(theme.radius);
    return Stack(
      children: [
        _overlay(),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: height,
          child: Container(
            key: PopupKeys.card,
            clipBehavior: Clip.antiAlias,
            decoration: _card(radius: BorderRadius.only(topLeft: radius, topRight: radius)),
            child: Stack(
              children: [
                // Fills the sheet when the content fits; scrolls as a whole on short screens.
                CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1D5DB),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          if (content.image != null && content.size != PopupSize.sm)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: SizedBox(
                                height: height * 0.38,
                                child: _image(radius: BorderRadius.circular(8)),
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + insets.bottom),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [_textBlock(), _buttons(content.buttons)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                _closeButton(dark: theme.isDarkBackground),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _banner() {
    final top = content.position != PopupPosition.bottom;
    final iab = content.size == PopupSize.iab_320x50;
    final width = iab ? math.min(320.0, screen.width) : screen.width;
    final radius = !desktop && !iab ? 0.0 : math.min(theme.radius, 8.0);
    final row = Row(
      children: [
        if (content.image != null) ...[
          SizedBox.square(
            dimension: iab ? 32 : 40,
            child: _image(radius: BorderRadius.circular(6)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasTitle)
                _title(size: iab ? 12 : 14, height: iab ? 16 / 12 : 20 / 14, maxLines: 1),
              if (_hasBody && !iab) _body(size: 12, height: 16 / 12, maxLines: 1),
            ],
          ),
        ),
        if (content.buttons.isNotEmpty) ...[
          const SizedBox(width: 12),
          // Natural width up to a cap, so a long label ellipsises instead of pushing the title
          // and the close button off screen.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * 0.45),
            child: _buttons(content.buttons, compact: true),
          ),
        ],
        if (content.close.show) ...[
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: 'Close',
            child: GestureDetector(
              key: PopupKeys.close,
              behavior: HitTestBehavior.opaque,
              onTap: view.onClose,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: theme.text.withValues(alpha: 0.7)),
              ),
            ),
          ),
        ],
      ],
    );
    final card = Container(
      key: PopupKeys.card,
      width: width,
      height: iab ? width * 50 / 320 : null,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: iab ? 0 : 10),
      decoration: _card(
        radius: BorderRadius.circular(radius),
        shadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 10),
            blurRadius: 15,
            spreadRadius: -3,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 4),
            blurRadius: 6,
            spreadRadius: -4,
          ),
        ],
      ),
      child: row,
    );
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: top ? (desktop ? 0 : insets.top) : null,
          bottom: top ? null : insets.bottom,
          child: Center(child: card),
        ),
      ],
    );
  }

  Widget _toast() {
    final bottom = content.position == PopupPosition.bottomRight;
    final width =
        desktop
            ? (content.size == PopupSize.sm ? 280.0 : 340.0)
            : screen.width - 24 - insets.horizontal;
    final showImage = content.image != null && content.size == PopupSize.md;
    final card = Container(
      key: PopupKeys.card,
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: _card(
        radius: BorderRadius.circular(math.min(theme.radius, 12)),
        border: Border.all(color: const Color(0x0D000000)),
        shadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 20),
            blurRadius: 25,
            spreadRadius: -5,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 8),
            blurRadius: 10,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Stack(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showImage) SizedBox(width: 64, child: _image()),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 32, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_hasTitle) _title(size: 14, height: 20 / 14),
                        if (_hasBody) ...[
                          if (_hasTitle) const SizedBox(height: 2),
                          _body(size: 12, height: 16 / 12),
                        ],
                        if (content.buttons.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buttons(content.buttons, compact: true),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _closeButton(dark: theme.isDarkBackground),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned(
          right: 12 + insets.right,
          top: bottom ? null : (desktop ? 12 : insets.top + 4),
          bottom: bottom ? 12 + insets.bottom : null,
          child: card,
        ),
      ],
    );
  }

  Widget _imageOnly() {
    final iab = content.size == PopupSize.iab_300x250;
    final size = _fitRatio(_cardWidth(content.size), iab ? 300 / 250 : 4 / 5);
    return Stack(
      children: [
        _overlay(),
        Center(
          child: Container(
            key: PopupKeys.card,
            width: size.width,
            height: size.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(theme.radius),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  offset: Offset(0, 25),
                  blurRadius: 50,
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Stack(
              children: [
                if (content.image != null) Positioned.fill(child: _image(forceTappable: true)),
                _closeButton(dark: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modal() {
    final iab = content.size == PopupSize.iab_300x250;
    final width = _cardWidth(content.size);
    final buttons = iab ? content.buttons.take(1).toList() : content.buttons;
    final Widget inner;
    if (iab) {
      inner = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SingleChildScrollView(child: _textBlock())),
            _buttons(buttons),
          ],
        ),
      );
    } else {
      // Sizes to its content; past the 90% height cap (long text, a landscape phone, large
      // text) the whole card scrolls.
      inner = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (content.image != null)
              SizedBox(height: content.size == PopupSize.sm ? 96 : 144, child: _image()),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_textBlock(), _buttons(buttons)],
              ),
            ),
          ],
        ),
      );
    }
    final fixed = iab ? _fitRatio(width, 300 / 250) : null;
    return Stack(
      children: [
        _overlay(),
        Center(
          child: Container(
            key: PopupKeys.card,
            width: fixed?.width ?? width,
            height: fixed?.height,
            constraints: BoxConstraints(maxHeight: (screen.height - insets.vertical) * 0.9),
            clipBehavior: Clip.antiAlias,
            decoration: _card(
              radius: BorderRadius.circular(theme.radius),
              shadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  offset: Offset(0, 25),
                  blurRadius: 50,
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Stack(
              children: [
                inner,
                _closeButton(dark: theme.isDarkBackground || content.image != null),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `PopupImage`: `gradient:#a,#b` draws a 135° gradient, anything else is loaded through the
/// cache and drawn with `object-cover`.
class PopupImageView extends StatelessWidget {
  const PopupImageView({super.key, required this.image, this.images, required this.placeholder});

  final PopupImage image;
  final PopupImageCache? images;

  /// The pop-up's text colour; the empty image area is a faint wash of it.
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (image.isGradient) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: image.gradientColors,
          ),
        ),
        child: const SizedBox.expand(),
      );
    } else {
      child = _bitmap();
    }
    return Semantics(image: true, label: image.alt, excludeSemantics: true, child: child);
  }

  Widget _bitmap() {
    final empty = ColoredBox(
      color: placeholder.withValues(alpha: 0.08),
      child: const SizedBox.expand(),
    );
    Widget draw(Uint8List? bytes) =>
        bytes == null
            ? empty
            : Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => empty,
            );
    final cache = images;
    if (cache == null) {
      return Image.network(image.url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => empty);
    }
    final ready = cache.peek(image.url);
    if (ready != null) return SizedBox.expand(child: draw(ready));
    return FutureBuilder(
      future: cache.load(image.url),
      builder: (context, snapshot) => SizedBox.expand(child: draw(snapshot.data)),
    );
  }
}
