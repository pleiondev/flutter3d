import 'dart:math' as math;

import 'camera_node.dart';
import 'mesh_node.dart';
import 'scene_node.dart';

/// One level of detail: a mesh and the screen size below which it takes over.
final class LodLevel {
  const LodLevel({required this.node, required this.maxScreenFraction});

  final MeshNode node;

  /// Fraction of the viewport's height this level's bounding sphere may cover
  /// before the next-finer level is used.
  ///
  /// Screen size rather than distance, because distance alone is the wrong
  /// measure: the same object at the same distance fills a quarter of the frame
  /// through a telephoto lens and a tenth of it through a wide one, and the
  /// question a LOD answers is how many pixels the detail is worth.
  final double maxScreenFraction;
}

/// Picks one of several meshes by how much of the screen the object covers.
///
/// A node rather than a renderer feature: the choice is a property of the
/// object, the renderer already walks a flat registry, and hiding the levels it
/// is not using keeps culling and picking honest without either of them knowing
/// LODs exist.
///
/// Levels are given finest-first and sorted on construction, so declaring them
/// out of order is not a silent bug.
final class LodGroup extends SceneNode {
  LodGroup({required List<LodLevel> levels, super.name})
      : _levels = List<LodLevel>.of(levels)
          ..sort(
            (a, b) => b.maxScreenFraction.compareTo(a.maxScreenFraction),
          ) {
    if (_levels.isEmpty) {
      throw ArgumentError('A LOD group needs at least one level.');
    }
    for (final level in _levels) {
      add(level.node);
    }
    // Nothing is chosen until the first select(), and showing every level at
    // once in the meantime would draw the object several times over.
    _apply(0);
  }

  final List<LodLevel> _levels;
  int _active = -1;

  List<LodLevel> get levels => List<LodLevel>.unmodifiable(_levels);

  /// Index of the level currently visible.
  int get activeLevel => _active;

  MeshNode get activeNode => _levels[_active].node;

  /// Chooses a level for [camera] and returns its index.
  ///
  /// [verticalFieldOfView] is in radians; an orthographic camera has none, so
  /// pass the projection's height instead through [orthographicHeight].
  int select(
    CameraNode camera, {
    double? verticalFieldOfView,
    double? orthographicHeight,
  }) {
    final fraction = screenFraction(
      camera,
      verticalFieldOfView: verticalFieldOfView,
      orthographicHeight: orthographicHeight,
    );

    // Levels run finest first, with thresholds descending. Every level whose
    // threshold the object still fits under is a candidate, and the right one
    // is the *last* of them — the coarsest that still qualifies. Taking the
    // first instead would always answer "finest", because the finest level's
    // threshold is the largest.
    var chosen = 0;
    for (var i = 0; i < _levels.length; i++) {
      if (fraction > _levels[i].maxScreenFraction) break;
      chosen = i;
    }
    _apply(chosen);
    return chosen;
  }

  /// How much of the viewport's height this object's bounding sphere covers.
  double screenFraction(
    CameraNode camera, {
    double? verticalFieldOfView,
    double? orthographicHeight,
  }) {
    final node = _levels.first.node;
    final radius = node.worldBoundsRadius;
    if (radius <= 0.0) return 0.0;

    final projection = camera.projection;
    if (projection is OrthographicProjection || orthographicHeight != null) {
      final height = orthographicHeight ??
          (projection as OrthographicProjection).height;
      if (height <= 0.0) return 0.0;
      // No perspective divide: an orthographic object's size on screen does not
      // depend on where it is.
      return (radius * 2.0) / height;
    }

    final fov = verticalFieldOfView ??
        (projection is PerspectiveProjection
            ? projection.fovYRadians
            : math.pi / 4);

    final eye = camera.readWorldPosition();
    final distance = (node.worldBoundsCentre - eye).length;
    // Inside the sphere the object fills the frame, and the formula below would
    // divide by a distance smaller than the radius and blow up.
    if (distance <= radius) return 1.0;

    // The half-height of the view volume at the object's distance; the sphere's
    // diameter over that is the fraction of the frame it covers.
    final halfHeight = math.tan(fov * 0.5) * distance;
    if (halfHeight <= 0.0) return 1.0;
    return math.min(1.0, radius / halfHeight);
  }

  void _apply(int index) {
    if (index == _active) return;
    for (var i = 0; i < _levels.length; i++) {
      _levels[i].node.visible = i == index;
    }
    _active = index;
  }

  @override
  String toString() =>
      'LodGroup(${name ?? 'unnamed'}, ${_levels.length} levels, active '
      '$_active)';
}
