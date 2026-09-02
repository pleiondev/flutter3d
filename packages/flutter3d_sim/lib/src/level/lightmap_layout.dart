/// Where each brush face lives in the lightmap, decided from the level alone.
///
/// ## Planned, not stored
///
/// The baker and the geometry both need to know which texels a face owns:
/// the baker to write them, the geometry to hand each vertex its second
/// texture coordinate. Rather than the baker writing a table that the
/// geometry then reads — a second thing to keep beside the level, a second
/// thing to go stale — the layout is a pure function of the level and the
/// texel density, computed the same way on both sides. The sidecar carries
/// only pixels and a hash; anything that would change the layout changes
/// the hash, and a stale sidecar is refused with a word.
///
/// ## Planar, because the faces are
///
/// A brush face is a rectangle with its own two axes, so its unwrap is the
/// rectangle itself: texel `(i, j)` is the point `origin + u·(i+½)/density +
/// v·(j+½)/density`. There is no seam to hide and no distortion to spread,
/// which is the whole reason a brush level is the one kind of level a
/// lightmap is cheap for. Faces are packed on shelves, tallest first, with a
/// texel of padding between them so a bilinear sample at a face's edge
/// reads its own padding and not the neighbour's light.
///
/// A ramp's slope and end triangles are not planned: a wedge is not a box
/// face, and a level has a handful of them. They point every vertex at the
/// reserved texel in the corner, which the baker leaves at the level's
/// average indirect light rather than black.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'brush_geometry.dart';
import 'level.dart';

/// One face's place in the atlas and its frame in the world.
final class LightmapFace {
  const LightmapFace({
    required this.brush,
    required this.face,
    required this.origin,
    required this.u,
    required this.v,
    required this.normal,
    required this.extentU,
    required this.extentV,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Index of the brush in `Level.brushes`, and which of
  /// [BrushGeometry.faceAxes] this is.
  final int brush;
  final int face;

  /// The face's corner at texel `(0, 0)`, and the unit axes texels run along.
  final Vector3 origin;
  final Vector3 u;
  final Vector3 v;
  final Vector3 normal;

  /// The face's size along [u] and [v], in metres.
  final double extentU;
  final double extentV;

  /// The rectangle of texels this face owns.
  final int x;
  final int y;
  final int width;
  final int height;

  int get texelCount => width * height;
}

/// The atlas: its size, its density, and every face's place in it.
final class LightmapLayout {
  LightmapLayout._({
    required this.texelsPerMetre,
    required this.width,
    required this.height,
    required this.faces,
  }) : _byFace = <(int, int), LightmapFace>{
         for (final face in faces) (face.brush, face.face): face,
       };

  /// Texels along a metre of face.
  final double texelsPerMetre;

  final int width;
  final int height;
  final List<LightmapFace> faces;
  final Map<(int, int), LightmapFace> _byFace;

  /// A texel between neighbouring faces, and around the reserved corner.
  static const int padding = 1;

  /// Where the reserved texel is: the one every unplanned vertex points at.
  static const int reservedX = 0;
  static const int reservedY = 0;

  /// The largest atlas this will plan. Past it the level wants a lower
  /// density, and the planner says so rather than guessing one.
  static const int maxSize = 4096;

  int get texelCount => width * height;

  LightmapFace? faceOf(int brush, int face) => _byFace[(brush, face)];

  /// The second texture coordinate of a face's corner, where `su` and `sv`
  /// are −1 or 1 along [LightmapFace.u] and [LightmapFace.v] — the same
  /// corners `BrushGeometry` emits.
  (double, double) uvAt(LightmapFace face, double su, double sv) => (
    (face.x + (su + 1.0) * 0.5 * face.extentU * texelsPerMetre) / width,
    (face.y + (sv + 1.0) * 0.5 * face.extentV * texelsPerMetre) / height,
  );

  /// The centre of the reserved texel.
  (double, double) get neutralUv =>
      ((reservedX + 0.5) / width, (reservedY + 0.5) / height);

  /// The texel a point on [face] falls in, clamped to the face's rectangle.
  (int, int) texelOf(LightmapFace face, Vector3 point) {
    final dx = point.x - face.origin.x;
    final dy = point.y - face.origin.y;
    final dz = point.z - face.origin.z;
    final along = dx * face.u.x + dy * face.u.y + dz * face.u.z;
    final across = dx * face.v.x + dy * face.v.y + dz * face.v.z;
    return (
      (along * texelsPerMetre).floor().clamp(0, face.width - 1),
      (across * texelsPerMetre).floor().clamp(0, face.height - 1),
    );
  }

  /// The world position of the centre of texel `(i, j)` of [face].
  void texelCentre(LightmapFace face, int i, int j, Vector3 out) {
    final along = (i + 0.5) / texelsPerMetre;
    final across = (j + 0.5) / texelsPerMetre;
    out
      ..setFrom(face.origin)
      ..addScaled(face.u, along)
      ..addScaled(face.v, across);
  }

  /// Plans the atlas for [level] at [texelsPerMetre].
  ///
  /// Deterministic: the faces come in brush order, the packing sorts them
  /// stably, and nothing here reads anything but the level. Throws
  /// [StateError] when the level wants more than [maxSize] texels on a side,
  /// which is a level that wants a lower density.
  static LightmapLayout plan(
    Level level, {
    double texelsPerMetre = 4.0,
    bool cullHiddenFaces = true,
    double cellSize = 8.0,
  }) {
    final geometry = BrushGeometry(
      cullHiddenFaces: cullHiddenFaces,
      cellSize: cellSize,
    );
    final planned = <_Planned>[
      for (final face in geometry.blockFaces(level))
        _Planned(face, texelsPerMetre),
    ];
    // Tallest first, then widest, then the level's own order, so two runs
    // over the same level pack the same way.
    planned.sort((a, b) {
      final byHeight = b.height.compareTo(a.height);
      if (byHeight != 0) return byHeight;
      final byWidth = b.width.compareTo(a.width);
      if (byWidth != 0) return byWidth;
      final byBrush = a.face.brush.compareTo(b.face.brush);
      if (byBrush != 0) return byBrush;
      return a.face.face.compareTo(b.face.face);
    });

    final area = planned.fold<int>(
      0,
      (sum, p) => sum + (p.width + padding) * (p.height + padding),
    );
    final width = _powerOfTwoAtLeast(
      math.sqrt(area * 1.2).ceil(),
    ).clamp(64, maxSize);

    // Shelves down the atlas, starting below the reserved corner.
    final faces = <LightmapFace>[];
    var shelfY = 1 + padding;
    var shelfHeight = 0;
    var cursorX = padding;
    for (final p in planned) {
      if (p.width > width - padding) {
        throw StateError(
          'a ${p.width}-texel face does not fit an atlas $width wide; lower '
          'the density',
        );
      }
      if (cursorX + p.width > width - padding) {
        shelfY += shelfHeight + padding;
        shelfHeight = 0;
        cursorX = padding;
      }
      faces.add(p.placedAt(cursorX, shelfY));
      cursorX += p.width + padding;
      shelfHeight = math.max(shelfHeight, p.height);
    }
    final used = shelfY + shelfHeight + padding;
    final height = _powerOfTwoAtLeast(used).clamp(64, maxSize);
    if (used > maxSize) {
      throw StateError(
        'the level wants $used rows of lightmap at $texelsPerMetre texels a '
        'metre, more than $maxSize; lower the density',
      );
    }
    return LightmapLayout._(
      texelsPerMetre: texelsPerMetre,
      width: width,
      height: height,
      faces: faces,
    );
  }

  static int _powerOfTwoAtLeast(int n) {
    var p = 1;
    while (p < n) {
      p <<= 1;
    }
    return p;
  }
}

/// A face measured and waiting for a place.
final class _Planned {
  _Planned(this.face, double density)
    : width = math.max(1, (face.halfU * 2.0 * density).ceil()),
      height = math.max(1, (face.halfV * 2.0 * density).ceil());

  final BrushFace face;
  final int width;
  final int height;

  LightmapFace placedAt(int x, int y) => LightmapFace(
    brush: face.brush,
    face: face.face,
    origin: Vector3(
      face.centreX - face.u.x * face.halfU - face.v.x * face.halfV,
      face.centreY - face.u.y * face.halfU - face.v.y * face.halfV,
      face.centreZ - face.u.z * face.halfU - face.v.z * face.halfV,
    ),
    u: face.u,
    v: face.v,
    normal: face.normal,
    extentU: face.halfU * 2.0,
    extentV: face.halfV * 2.0,
    x: x,
    y: y,
    width: width,
    height: height,
  );
}
