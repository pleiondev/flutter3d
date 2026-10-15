/// One view of a frame, as a node or a contributor reads it: the matrices it
/// draws through, where it lands on the target, which of the frame's views
/// it is, and what the same view saw the frame before.
library;

import 'package:vector_math/vector_math.dart' as vm;

import '../scene/projection.dart';
import 'frame_graph.dart';
import 'render_view.dart';

/// One view of a frame: a monitor's camera, one eye of a stereo pair, one
/// eye a headset's runtime hands over.
///
/// **What every node is told about each view, since 1.0** (`FrameContext.views`).
/// A frame drawn through one camera has one; a stereo pair or a headset has
/// two, each with its own pose and its own, usually asymmetric, projection.
/// The matrices are the unjittered ones, in the scene's space (see "Space" in
/// `docs/CONTRACTS.md`): [viewMatrix] takes a scene position to the eye, and
/// [projection] the eye to clip space in the engine's `[0, 1]` depth
/// convention.
///
/// **Made by the renderer from a [CameraView], or from outside.** An XR
/// runtime knows each eye's pose and its four field-of-view angles before
/// the engine does; [FrameView.posed] takes them as they come
/// (`OffAxisProjection.fromAngles` for the angles), so the session only
/// fills the views and the nodes read them the same way as a camera's.
///
/// Immutable: every matrix is copied in and copied out.
final class FrameView {
  /// A view drawn through [viewMatrix] and [projection], into [viewport] of
  /// the target, as the [index]th of the frame's views. [previousViewProjection]
  /// is what the same view drew through the frame before, or null when it
  /// has no past.
  FrameView({
    required vm.Matrix4 viewMatrix,
    required this.projection,
    this.aspect = 1.0,
    this.viewport = const ViewportRect(0.0, 0.0, 1.0, 1.0),
    this.index = 0,
    vm.Matrix4? previousViewProjection,
  }) : _view = vm.Matrix4.copy(viewMatrix),
       _previous = previousViewProjection == null
           ? null
           : vm.Matrix4.copy(previousViewProjection);

  /// A view from an eye at [position], turned by [orientation], in the
  /// scene's space — how a runtime states a pose. Its view matrix is the
  /// inverse of that placement.
  factory FrameView.posed({
    required vm.Vector3 position,
    required vm.Quaternion orientation,
    required Projection projection,
    double aspect = 1.0,
    ViewportRect viewport = const ViewportRect(0.0, 0.0, 1.0, 1.0),
    int index = 0,
    vm.Matrix4? previousViewProjection,
  }) => FrameView(
    viewMatrix: vm.Matrix4.compose(position, orientation, vm.Vector3.all(1.0))
      ..invert(),
    projection: projection,
    aspect: aspect,
    viewport: viewport,
    index: index,
    previousViewProjection: previousViewProjection,
  );

  /// [view]'s camera, drawn at [aspect]: the view a renderer makes for each
  /// of a `render` call's views.
  factory FrameView.ofCameraView(
    CameraView view, {
    required double aspect,
    int index = 0,
    vm.Matrix4? previousViewProjection,
  }) => FrameView(
    viewMatrix: view.camera.viewMatrix,
    projection: view.camera.projection,
    aspect: aspect,
    viewport: view.viewportFraction,
    index: index,
    previousViewProjection: previousViewProjection,
  );

  final vm.Matrix4 _view;
  final vm.Matrix4? _previous;

  /// The projection, as the camera or the runtime stated it. Asymmetric for
  /// a headset's eye (`OffAxisProjection`).
  final Projection projection;

  /// The width over the height of the pixels this view lands on — what
  /// [projection] is evaluated at. An `OffAxisProjection` ignores it.
  final double aspect;

  /// Where on the target this view lands, as fractions of it.
  final ViewportRect viewport;

  /// Which of the frame's views this is, from nought: the left eye before
  /// the right, the first viewport before the second.
  final int index;

  /// The scene's space to this view's eye.
  vm.Matrix4 get viewMatrix => vm.Matrix4.copy(_view);

  /// [projection] as a matrix, at [aspect], without the jitter.
  vm.Matrix4 get projectionMatrix => projection.toMatrix(aspect);

  /// [projectionMatrix] times [viewMatrix]: the unjittered view-projection.
  vm.Matrix4 get viewProjection => projectionMatrix * _view;

  /// Whether the same view was drawn the frame before, so
  /// [previousViewProjection] is that frame's rather than this one's.
  bool get hasHistory => _previous != null;

  /// The unjittered view-projection the same view drew through the frame
  /// before — what a temporal effect reprojects by. This frame's own,
  /// [viewProjection], for a view with no past (the first frame, a view
  /// that just appeared): a velocity of zero, which is the honest answer.
  vm.Matrix4 get previousViewProjection =>
      _previous == null ? viewProjection : vm.Matrix4.copy(_previous);

  /// [id] as this view keeps its own copy of it: what a node that holds a
  /// history per view declares in its `keeps`. See [resourceFor].
  ResourceId resource(ResourceId id) => resourceFor(id, index);

  /// [id] for the view at [index]: [id] itself for the first view, and
  /// `<name>#<index>` for the others.
  ///
  /// **Per-view resources through `keeps`.** A temporal effect keeps last
  /// frame's picture, and with two eyes it keeps two: one under each view's
  /// name, declared in `keeps` and provided by the node each frame. The
  /// first view's is the plain name, so a node written for one view needs
  /// no change to draw the first of several.
  static ResourceId resourceFor(ResourceId id, int index) =>
      index == 0 ? id : ResourceId('${id.name}#$index');

  @override
  String toString() => 'FrameView($index)';
}
