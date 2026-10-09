import 'package:flutter3d/flutter3d.dart';

import '../declarative/scene_widgets.dart' show Scene3D;
import '../surface/scene_surface.dart' show SceneSurface;
import 'flutter3d_view.dart' show Flutter3dView;

/// What a frame callback is told about one frame: [SceneSurface.onFrame],
/// [Scene3D.onFrame], and [Flutter3dView.onBeforeFrame] and
/// [Flutter3dView.onFrame] beside their engine.
///
/// **An object, so a frame can say more later.** The callbacks took a bare
/// `double` in one widget and a bare [FrameResult] in another, and the next
/// thing one of them wanted (the result beside the seconds, a frame count)
/// would have broken every handler written against it. A field added here
/// does not.
///
/// ```dart
/// Scene3D(onFrame: (FrameInfo frame) => spin += frame.seconds)
/// ```
final class FrameInfo {
  /// A frame [seconds] after the one before, with the renderer's [result]
  /// when there is one to give.
  const FrameInfo({required this.seconds, this.result});

  /// Seconds since the frame before, by the display's clock; nought for the
  /// first.
  final double seconds;

  /// What the renderer answered for the last frame it drew: this one, to a
  /// callback that runs after the frame is drawn ([SceneSurface.onFrame]);
  /// the one before, to a callback that runs before ([Scene3D.onFrame],
  /// [Flutter3dView.onFrame]). Null before the first frame is drawn.
  ///
  /// Its [FrameResult.frame] is the renderer's own target and is good only
  /// until the next frame: keep the counters, not the texture.
  final FrameResult? result;
}

/// Where a view's ears are after a frame: [Flutter3dView.onListenerMoved].
///
/// **An object for [FrameInfo]'s reason.** The callback took a position and
/// a direction, and a binaural mix also wants which way is up; that is here
/// now, and what comes next goes beside it without breaking a handler.
///
/// ```dart
/// onListenerMoved: (ListenerPose ears) => listener.placeAt(
///   ears.position,
///   ears.forward,
///   origin: ears.origin,
///   up: ears.up,
/// ),
/// ```
final class ListenerPose {
  /// Ears at [position] in the world, facing [forward] with [up] above,
  /// drawn in a scene whose origin is [origin].
  const ListenerPose({
    required this.position,
    required this.forward,
    required this.up,
    required this.origin,
  });

  /// Where the camera is in the world.
  final WorldPosition position;

  /// The way the camera faces, a unit vector in scene space.
  final Vector3 forward;

  /// The camera's up, a unit vector in scene space.
  final Vector3 up;

  /// The origin of the scene the view draws (`Scene.origin`): the point an
  /// audio scene's emitters are placed relative to, so the listener is
  /// placed relative to it too.
  final WorldPosition origin;
}
