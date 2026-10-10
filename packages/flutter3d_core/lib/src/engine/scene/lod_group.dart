import 'dart:math' as math;

import 'package:flutter3d_core/geometry.dart';

import '../render/material.dart';
import 'camera_node.dart';
import 'mesh_node.dart';
import 'projection.dart';
import 'scene.dart';
import 'scene_node.dart';

/// One level of detail: a mesh, the screen size below which it takes over,
/// and — when somebody measured it — how far it is from the full mesh.
final class LodLevel {
  const LodLevel({
    required this.node,
    required this.maxScreenFraction,
    this.error,
  });

  final MeshNode node;

  /// How far this level's surface strays from the finest level's, in the
  /// group's own units: `ModelLod.error`, which the converter measures.
  ///
  /// **When it is there, the level is switched by it.** Projected at the
  /// object's distance it is how many pixels the level is wrong by, and a
  /// level wrong by less than [LodGroup.pixelError] cannot be told from the
  /// full mesh — which is the question a level of detail answers, asked
  /// directly rather than through a rule of thumb about triangles per
  /// pixel. Null leaves the level on [maxScreenFraction]; zero, as on a
  /// finest level, means it is always good enough.
  final double? error;

  /// Fraction of the viewport's height this level's bounding sphere may cover
  /// before the next-finer level is used — the rule for a level without an
  /// [error], and the order the levels are sorted in either way.
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
  LodGroup({
    required List<LodLevel> levels,
    this.hysteresis = defaultHysteresis,
    this.pixelError = defaultPixelError,
    this.crossFade = defaultCrossFade,
    super.name,
  }) : _levels = List<LodLevel>.of(levels)
         ..sort((a, b) => b.maxScreenFraction.compareTo(a.maxScreenFraction)) {
    if (_levels.isEmpty) {
      throw ArgumentError('A LOD group needs at least one level.');
    }
    if (!(pixelError >= 0.0)) {
      throw ArgumentError.value(
        pixelError,
        'pixelError',
        'must be zero or positive: it is a number of pixels',
      );
    }
    if (hysteresis < 0.0) {
      throw ArgumentError.value(
        hysteresis,
        'hysteresis',
        'must be zero or positive: a negative band would switch finer before '
            'the threshold it is meant to widen',
      );
    }
    if (!(crossFade >= 0.0)) {
      throw ArgumentError.value(
        crossFade,
        'crossFade',
        'must be zero or positive: it is a share of each threshold, and zero '
            'is the hard switch',
      );
    }
    for (final level in _levels) {
      add(level.node);
    }
    // Nothing is chosen until the first select(), and showing every level at
    // once in the meantime would draw the object several times over.
    _apply(0);
  }

  /// Builds a group from one mesh drawn with several materials.
  ///
  /// The case this exists for is texture level of detail. the engine on this
  /// channel cannot create a texture with mip levels — `createTexture` takes no
  /// level count and `Texture.overwrite` writes only the base — so a distant
  /// object cannot be made to sample a smaller image the usual way. What it can
  /// do is sample a smaller *texture*, and that is a different material on the
  /// same geometry.
  ///
  /// It does not fix minification within one surface: a floor running to the
  /// horizon still aliases, because the choice is per object and not per pixel.
  /// What it does fix is the common case — a prop that is a thousand pixels
  /// across when the player is next to it and thirty when they are not, holding
  /// a four-thousand-pixel texture the whole time.
  ///
  /// Materials run finest first, matching [levels].
  factory LodGroup.forMaterials({
    required MeshGeometry mesh,
    required List<RenderMaterial> materials,
    required List<double> maxScreenFractions,
    double hysteresis = defaultHysteresis,
    double crossFade = defaultCrossFade,
    String? name,
  }) {
    if (materials.length != maxScreenFractions.length) {
      throw ArgumentError(
        'materials (${materials.length}) and maxScreenFractions '
        '(${maxScreenFractions.length}) must have the same length: each '
        'material is the one used below its own threshold.',
      );
    }
    return LodGroup(
      name: name,
      hysteresis: hysteresis,
      crossFade: crossFade,
      levels: <LodLevel>[
        for (var i = 0; i < materials.length; i++)
          LodLevel(
            // The same geometry object in every level, so the GPU buffers are
            // uploaded once however many texture sets there are.
            node: MeshNode(mesh, materials[i], name: '${name ?? 'lod'}$i'),
            maxScreenFraction: maxScreenFractions[i],
          ),
      ],
    );
  }

  /// The band given by default: a tenth of each threshold.
  /// A 0..1 fraction of each threshold.
  static const double defaultHysteresis = 0.1;

  /// How far past a threshold, as a fraction of it, the object has to grow
  /// before a finer level takes back over from a coarser one.
  ///
  /// **A hard threshold flips every frame at its edge.** An object parked on
  /// one, under a camera that bobs or a TAA jitter that moves the eye by a
  /// fraction of a pixel, lands a hair either side of it frame after frame, and
  /// each crossing swaps the mesh — a flicker far more visible than either
  /// level alone. With a band the coarser level is let go only once the object
  /// is clearly bigger than the threshold it came in under, and coarsening
  /// still happens at the threshold itself, so the declared numbers keep their
  /// meaning on the way out. Zero restores the hard switch.
  final double hysteresis;

  /// The error given by default: one pixel.
  static const double defaultPixelError = 1.0;

  /// How many pixels a level with a [LodLevel.error] may be wrong by on
  /// screen before a finer one takes over.
  ///
  /// **One pixel, because under it the difference is not there to see.** A
  /// surface less than a pixel from the full one rasterises to the same
  /// coverage give or take an edge; raise it for a scene that would rather
  /// have the frame time than the silhouette, and the same numbers in the
  /// file hold for every viewport size, which a screen fraction does not —
  /// a tenth of a phone and a tenth of a monitor are different pixels.
  final double pixelError;

  /// The band given by default: a tenth of each threshold.
  /// A 0..1 fraction of each threshold.
  static const double defaultCrossFade = 0.1;

  /// How far past a coarser level's threshold, as a share of it, that level
  /// starts to be drawn beside the finer one — `A1.3`. Zero is the hard
  /// switch every release before 1.0 drew, and the old picture.
  ///
  /// **A pop is the one thing a level of detail must not do**, and a hard
  /// switch is a pop by construction: one frame the finer mesh, the next the
  /// coarser, and a silhouette that jumps by however many pixels the two
  /// disagree. Over the band the two are drawn together instead, the coarser
  /// taking more of the object the nearer it is to fitting: an opaque pair
  /// splits the pixels between them through one pattern
  /// ([MeshNode.lodFade]), a transparent pair splits the opacity. At the
  /// threshold itself the coarser level is whole, so the declared numbers
  /// keep their meaning.
  ///
  /// **The band follows the measure, not the clock**, so a still camera
  /// shows a still picture and a replay or a golden draws the same frame
  /// every time. [hysteresis] then has nothing left to do for the picture:
  /// a measure that jitters across a threshold moves the split by as much as
  /// it jittered, and nothing pops. It still decides [activeLevel], which a
  /// game reads to decide something else by the same distance — so during a
  /// fade the level drawn most is not always the active one.
  final double crossFade;

  final List<LodLevel> _levels;
  int _active = -1;

  @override
  void onAttachedToScene(Scene scene) => scene.registerLodGroup(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterLodGroup(this);

  List<LodLevel> get levels => List<LodLevel>.unmodifiable(_levels);

  /// Index of the level currently visible.
  ///
  /// The engine picks the level and swaps the node itself, so nothing here has
  /// to ask which one won. It is for a game that decides something else by the
  /// same distance — an animation it stops updating, or an audio source it drops
  /// — and would rather ask the group that already chose than measure again and
  /// disagree with it at the boundary.
  int get activeLevel => _active;

  MeshNode get activeNode => _levels[_active].node;

  /// Chooses a level for [camera] and returns its index.
  ///
  /// [verticalFieldOfView] is in radians; an orthographic camera has none, so
  /// pass the projection's height instead through [orthographicHeight].
  ///
  /// [viewportHeight] is the height of the view in pixels, which is what
  /// turns a level's [LodLevel.error] into pixels; the renderer passes its
  /// own. Without it every level is switched by its screen fraction.
  int select(
    CameraNode camera, {
    double? verticalFieldOfView,
    double? orthographicHeight,
    double? viewportHeight,
  }) {
    final fraction = screenFraction(
      camera,
      verticalFieldOfView: verticalFieldOfView,
      orthographicHeight: orthographicHeight,
    );
    // World units to pixels at the object's nearest point, scaled into the
    // group's own units so a level's error can be multiplied straight in.
    // Null when there is no viewport to count pixels in.
    final pixelsPerOwnUnit = viewportHeight == null
        ? null
        : pixelsPerUnit(
                camera,
                viewportHeight: viewportHeight,
                verticalFieldOfView: verticalFieldOfView,
                orthographicHeight: orthographicHeight,
              ) *
              worldMatrix.getMaxScaleOnAxis();

    // Levels run finest first, with thresholds descending. Every level whose
    // threshold the object still fits under is a candidate, and the right one
    // is the *last* of them — the coarsest that still qualifies. Taking the
    // first instead would always answer "finest", because the finest level's
    // threshold is the largest.
    //
    // The level already showing, and every finer one, is held a little longer:
    // its threshold widens by [hysteresis], so leaving it for a finer level
    // takes a clear step past the line rather than a jitter across it. Levels
    // coarser than the active one keep their plain threshold.
    //
    // A level that carries a measured error asks the same question in
    // pixels: is it wrong by no more than [pixelError] from here? The two
    // rules mix freely along one chain, so a converted mesh chain ending in
    // an impostor, which has no error, switches to the card by its fraction.
    var chosen = 0;
    for (var i = 0; i < _levels.length; i++) {
      final level = _levels[i];
      final widen = i <= _active ? 1.0 + hysteresis : 1.0;
      final error = level.error;
      final fits = error != null && pixelsPerOwnUnit != null
          // Zero first: inside the sphere the scale is infinite, and zero
          // times it is not a number that compares as anything.
          ? error == 0.0 || error * pixelsPerOwnUnit <= pixelError * widen
          : fraction <= level.maxScreenFraction * widen;
      if (!fits) break;
      chosen = i;
    }
    if (crossFade <= 0.0) {
      _apply(chosen);
      return chosen;
    }

    // `A1.3`: the picture by the measure alone. The coarsest level that fits
    // its own threshold unwidened is drawn, and the next coarser one beside
    // it once the object is within [crossFade] of that one's threshold — a
    // share rising from nought at the band's far edge to the whole object at
    // the threshold, where it fits and the next frame draws it alone.
    var base = 0;
    double? next;
    for (var i = 0; i < _levels.length; i++) {
      final ratio = _ratio(_levels[i], fraction, pixelsPerOwnUnit);
      if (ratio > 1.0) {
        // The first level that does not fit is the one after [base]; with
        // none fitting at all the finest is drawn whole.
        if (i > 0) next = ratio;
        break;
      }
      base = i;
    }
    final share = next == null || base + 1 >= _levels.length
        ? 0.0
        : ((1.0 + crossFade - next) / crossFade).clamp(0.0, 1.0);
    _active = chosen;
    for (var i = 0; i < _levels.length; i++) {
      final node = _levels[i].node;
      if (i == base) {
        node
          ..isVisible = share < 1.0
          ..lodFade = share > 0.0 ? 1.0 - share : 1.0;
      } else if (i == base + 1 && share > 0.0) {
        node
          ..isVisible = true
          ..lodFade = share < 1.0 ? -share : 1.0;
      } else {
        node
          ..isVisible = false
          ..lodFade = 1.0;
      }
    }
    return chosen;
  }

  /// How far [level] is from fitting, as a share of its own threshold: one
  /// or below fits, above is too coarse for the object at this size.
  double _ratio(LodLevel level, double fraction, double? pixelsPerOwnUnit) {
    final error = level.error;
    if (error != null && pixelsPerOwnUnit != null) {
      if (error == 0.0) return 0.0;
      return pixelError > 0.0
          ? error * pixelsPerOwnUnit / pixelError
          : double.infinity;
    }
    return level.maxScreenFraction > 0.0
        ? fraction / level.maxScreenFraction
        : double.infinity;
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
      final height =
          orthographicHeight ?? (projection as OrthographicProjection).height;
      if (height <= 0.0) return 0.0;
      // No perspective divide: an orthographic object's size on screen does not
      // depend on where it is.
      return (radius * 2.0) / height;
    }

    // The projection is asked rather than type-tested. This read
    // `is PerspectiveProjection`, and every other projection — an off-axis one
    // for a headset above all — got 45 degrees whatever it actually saw. The
    // fallback stays for a projection that answers null and is not the
    // orthographic case handled above, which is a projection this engine does
    // not ship.
    final fovY =
        verticalFieldOfView ?? projection.verticalFieldOfView ?? math.pi / 4;

    final eye = camera.readWorldPosition();
    final distance = (node.worldBoundsCenter - eye).length;
    // Inside the sphere the object fills the frame, and the formula below would
    // divide by a distance smaller than the radius and blow up.
    if (distance <= radius) return 1.0;

    // The half-height of the view volume at the object's distance; the sphere's
    // diameter over that is the fraction of the frame it covers.
    final halfHeight = math.tan(fovY * 0.5) * distance;
    if (halfHeight <= 0.0) return 1.0;
    return math.min(1.0, radius / halfHeight);
  }

  /// How many pixels of a viewport [viewportHeight] pixels tall one world
  /// unit covers at this object's nearest point.
  ///
  /// **The nearest point, not the centre**: the error a level carries can be
  /// anywhere on it, and the side facing the camera is where it is largest
  /// on screen. Inside the bounding sphere that point is at the eye, and the
  /// answer is infinite — no measured level is good enough there. An
  /// orthographic view has one answer everywhere.
  double pixelsPerUnit(
    CameraNode camera, {
    required double viewportHeight,
    double? verticalFieldOfView,
    double? orthographicHeight,
  }) {
    final projection = camera.projection;
    if (projection is OrthographicProjection || orthographicHeight != null) {
      final height =
          orthographicHeight ?? (projection as OrthographicProjection).height;
      return height <= 0.0 ? double.infinity : viewportHeight / height;
    }

    final fovY =
        verticalFieldOfView ?? projection.verticalFieldOfView ?? math.pi / 4;
    final node = _levels.first.node;
    final distance =
        (node.worldBoundsCenter - camera.readWorldPosition()).length -
        node.worldBoundsRadius;
    final viewHeight = 2.0 * math.tan(fovY * 0.5) * distance;
    return viewHeight <= 0.0 ? double.infinity : viewportHeight / viewHeight;
  }

  void _apply(int index) {
    if (index == _active) return;
    for (var i = 0; i < _levels.length; i++) {
      _levels[i].node
        ..isVisible = i == index
        ..lodFade = 1.0;
    }
    _active = index;
  }

  @override
  String toString() =>
      'LodGroup(${name ?? 'unnamed'}, ${_levels.length} levels, active '
      '$_active)';
}
