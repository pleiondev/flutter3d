import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter3d/flutter3d.dart';

/// Bridges Flutter pointer input to an [OrbitController].
///
/// Kept in the app layer so the engine has no Flutter dependency. On desktop the
/// interesting part is the scroll wheel; on touch it is telling a one-finger
/// orbit apart from a two-finger pan and pinch, which `ScaleGestureRecognizer`
/// reports through the same callbacks.
class OrbitGestureDetector extends StatefulWidget {
  const OrbitGestureDetector({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.child,
    this.onTapPoint,
  });

  final OrbitController controller;

  /// Called after the controller moves, so the host can repaint.
  final VoidCallback onChanged;

  /// A tap, reported in the detector's own logical coordinates along with the
  /// size those coordinates are relative to.
  ///
  /// Both are needed to build a picking ray, and the size has to come from here
  /// rather than from the caller: only this widget knows the box the pointer
  /// position was measured against.
  final void Function(Offset localPosition, Size size)? onTapPoint;

  final Widget child;

  @override
  State<OrbitGestureDetector> createState() => _OrbitGestureDetectorState();
}

class _OrbitGestureDetectorState extends State<OrbitGestureDetector> {
  Offset _lastFocalPoint = Offset.zero;
  double _lastScale = 1.0;

  void _handleScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
    _lastScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.localFocalPoint - _lastFocalPoint;
    _lastFocalPoint = details.localFocalPoint;

    if (details.pointerCount >= 2) {
      // Two fingers: pinch zooms, drag pans. Zoom is applied as a ratio between
      // updates, because details.scale is cumulative from the gesture start.
      if (details.scale != 0.0) {
        final ratio = details.scale / _lastScale;
        _lastScale = details.scale;
        if (ratio != 1.0) widget.controller.zoom(1.0 / ratio);
      }
      widget.controller.pan(
        delta.dx,
        delta.dy,
        viewportHeight: context.size?.height ?? 600.0,
      );
    } else {
      widget.controller.rotate(delta.dx, delta.dy);
    }
    widget.onChanged();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Exponential response, so one notch feels the same at any distance.
    final factor = event.scrollDelta.dy > 0 ? 1.1 : 1.0 / 1.1;
    widget.controller.zoom(factor);
    widget.onChanged();
  }

  void _handleTapUp(TapUpDetails details) {
    final size = context.size;
    if (size == null) return;
    widget.onTapPoint?.call(details.localPosition, size);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        // Opaque so drags land here rather than passing through to the scaffold.
        behavior: HitTestBehavior.opaque,
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        // Tap coexists with scale: the arena hands a press that never moves to
        // the tap recognizer, so picking does not cost the orbit gesture
        // anything.
        onTapUp: widget.onTapPoint == null ? null : _handleTapUp,
        child: widget.child,
      ),
    );
  }
}
