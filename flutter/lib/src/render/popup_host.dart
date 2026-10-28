import 'dart:async';

import 'package:flutter/widgets.dart';

import '../controller.dart';
import 'popup_view.dart';

/// Sits above the app's navigator (through `MaterialApp.builder`) and draws the controller's
/// current pop-up over every screen.
class PopupHost extends StatelessWidget {
  const PopupHost({super.key, required this.controller, required this.child});

  final OptikpiPopupController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActivePopup?>(
      valueListenable: controller.current,
      child: child,
      builder:
          (context, active, child) => Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (active != null)
                Positioned.fill(
                  // Hides the page from screen readers while a blocking pop-up covers it.
                  child: BlockSemantics(
                    blocking: popupBlocksPage(active.content.layout),
                    child: _ActivePopup(
                      // A new pop-up gets a new State, so the old one's timer dies with it.
                      key: ObjectKey(active),
                      controller: controller,
                      active: active,
                    ),
                  ),
                ),
            ],
          ),
    );
  }
}

class _ActivePopup extends StatefulWidget {
  const _ActivePopup({super.key, required this.controller, required this.active});

  final OptikpiPopupController controller;
  final ActivePopup active;

  @override
  State<_ActivePopup> createState() => _ActivePopupState();
}

class _ActivePopupState extends State<_ActivePopup> {
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.didDraw(widget.active);
    });
    final seconds = widget.active.content.autoDismissSec;
    if (seconds != null) {
      // close() ignores a pop-up that is no longer current, so a late tick can't close the next.
      _autoDismiss = Timer(Duration(seconds: seconds), () {
        widget.controller.close(widget.active, dismissed: true);
      });
    }
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final active = widget.active;
    return PopupView(
      content: active.content,
      images: controller.images,
      onButton: (index) => controller.tapButton(active, index),
      onImageTap: () => controller.tapImage(active),
      onClose: () => controller.close(active, dismissed: true),
      onOutsideTap: () => controller.close(active, dismissed: true),
    );
  }
}
