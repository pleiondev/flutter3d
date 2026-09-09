/// The picture, and the pointer that turns it.
///
/// **Not `SceneSurface`, and the difference is one word.** That widget takes a
/// single `RenderView`; a modeller draws a list of them — the viewport now, a
/// material preview beside it later, three of them side by side when LODs are
/// being compared. Widening the session's surface is a change to a published
/// package for a feature that does not exist yet, so this draws the list
/// directly the way `SceneSurface` draws the one, and the two converge when
/// there is a second view to converge over.
///
/// Everything the render loop owns is here rather than in a state object: the
/// camera moves sixty times a second, and a widget rebuilt on every frame is a
/// widget whose subtree is rebuilt on every frame.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;

import 'staging.dart';

/// Draws [stage] through [renderer], and orbits it under the pointer.
class ModelerViewport extends StatelessWidget {
  const ModelerViewport({
    super.key,
    required this.renderer,
    required this.stage,
    required this.onFrame,
    this.onRendered,
  });

  final Renderer renderer;
  final ModelerStage stage;

  /// Called immediately before each frame, after the camera has been placed —
  /// where a caller advances anything drawn but not simulated.
  final VoidCallback onFrame;

  /// What the frame just drawn cost inside `Renderer.render`, in microseconds.
  ///
  /// Reported rather than measured by the caller, because the number worth
  /// having is the renderer's own: a caller timing `build` measures Flutter's
  /// layout as well and cannot tell the two apart.
  final void Function(int micros)? onRendered;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Listener(
      // On the picture and nothing else. A `Listener` up at the scaffold would
      // orbit the camera when somebody drags a value in the properties panel,
      // which is the first bug every viewport in every tool has had.
      onPointerDown: (PointerDownEvent event) => _drag(event, stage),
      onPointerMove: (PointerMoveEvent event) => _drag(event, stage),
      onPointerSignal: (PointerSignalEvent event) {
        if (event is! PointerScrollEvent) return;
        // Up is closer. A scroll of one notch is about 100 logical pixels on a
        // wheel and a fraction of that on a trackpad, so the exponent keeps a
        // trackpad usable without making a wheel jump past the model.
        stage.orbit.zoom(1.0 + event.scrollDelta.dy / 400.0);
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          onFrame();
          // Near and far from where the camera ended up, every frame: a fixed
          // range spends its precision on empty space when the model is small
          // and clips it when the model is large, and a modeller meets both
          // inside one session.
          stage.orbit.syncProjectionDepth(stage.camera);
          final frame = renderer.render(
            // Clamped because a zero-sized viewport is a real state — a panel
            // animating open, a window dragged to nothing — and a render
            // target of no pixels is not.
            width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
            height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
            scene: stage.scene,
            views: stage.views(),
          );
          onRendered?.call(frame.cpuMicros);
          // From the device rather than painted from an image, for the
          // reason `SceneSurface` gives: a backend whose frame is composited
          // elsewhere has no image to paint, and `present` is the one answer
          // both can give.
          return renderer.device.present(frame.frame);
        },
      ),
    );
  }

  /// Where the pointer was last seen, per pointer, so a drag is a delta.
  ///
  /// A map rather than one value: a trackpad reports two pointers during a
  /// pinch, and remembering only the last of them turns a pinch into a spin.
  static final Map<int, Offset> _last = <int, Offset>{};

  static void _drag(PointerEvent event, ModelerStage stage) {
    final previous = _last[event.pointer];
    _last[event.pointer] = event.position;
    if (previous == null || event is PointerDownEvent) return;

    final delta = event.position - previous;
    // The middle button and any drag with a modifier pan; everything else
    // orbits. Blender's arrangement, which is what the plan settled on for the
    // keys as well.
    if (event.buttons & kMiddleMouseButton != 0) {
      stage.orbit.pan(delta.dx, delta.dy);
    } else {
      stage.orbit.rotate(delta.dx, delta.dy);
    }
  }
}
