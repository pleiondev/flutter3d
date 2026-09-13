/// Turning `EditMesh` islands into paintable UV-layout data — `pro-uv-07`'s
/// own bridge between `pro-uv-04`'s `stretchOf` and the screen's own
/// `CustomPainter`.
///
/// **A value the painter reads, not the mesh itself.** `UvLayoutView` is a
/// dumb widget in this app's own house style (`modifier_stack_panel.dart`'s
/// doc comment states the same rule for a panel): it takes triangles and
/// colours and knows nothing about half-edges, so it can be tested with no
/// `EditMesh` anywhere near it. Deciding which triangles and which colour is
/// this file's job instead.
library;

import 'dart:ui';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

/// One triangle in UV space, corners in the mesh's own winding order.
final class UvTriangle {
  const UvTriangle(this.a, this.b, this.c);

  final Offset a;
  final Offset b;
  final Offset c;
}

/// One island's own triangles, and how stretched its current UV mapping is.
final class UvIslandData {
  const UvIslandData({
    required this.id,
    required this.faceCount,
    required this.triangles,
    required this.stretch,
  });

  /// The island's own position in [buildUvIslandData]'s input order — stable
  /// for as long as a caller keeps re-deriving the same `splitIslands` list,
  /// and what a tap or a list row names it by.
  final int id;

  /// How many of the mesh's own faces made up this island, before the fan
  /// triangulation [triangles] is drawn from — an n-gon face becomes more
  /// than one triangle, so this is not `triangles.length`.
  final int faceCount;

  final List<UvTriangle> triangles;

  /// [stretchOf]'s own answer for this island — 1.0 is a perfect isometry,
  /// above one is stretched, below one is compressed.
  final double stretch;

  /// [uvStretchColor] of [stretch] — the metric is already an island-wide
  /// average, so every triangle of one island paints in the same colour.
  Color get color => uvStretchColor(stretch);
}

/// [islands] (as [splitIslands] returns them), read back off [mesh] as
/// [UvIslandData] — each face fan-triangulated from its own first corner,
/// the same convention [stretchOf] itself reads a face by, so what is drawn
/// is the same shape the stretch beside it was measured from.
///
/// A face with fewer than three corners contributes nothing rather than a
/// degenerate triangle, the same refusal [stretchOf] makes for a collinear
/// one.
List<UvIslandData> buildUvIslandData(EditMesh mesh, List<List<int>> islands) {
  final result = <UvIslandData>[];
  for (var i = 0; i < islands.length; i++) {
    final island = islands[i];
    final triangles = <UvTriangle>[];
    for (final face in island) {
      final corners = <int>[];
      mesh.forEachHalfEdge(face, corners.add);
      if (corners.length < 3) continue;

      final uv0 = mesh.uvOf(corners[0]);
      final a = Offset(uv0.x, uv0.y);
      for (var k = 1; k + 1 < corners.length; k++) {
        final uv1 = mesh.uvOf(corners[k]);
        final uv2 = mesh.uvOf(corners[k + 1]);
        triangles.add(
          UvTriangle(a, Offset(uv1.x, uv1.y), Offset(uv2.x, uv2.y)),
        );
      }
    }
    result.add(
      UvIslandData(
        id: i,
        faceCount: island.length,
        triangles: triangles,
        stretch: stretchOf(mesh, island),
      ),
    );
  }
  return result;
}

/// The acceptance's own colour: what a maximally-stretched island paints.
const Color kUvMaxStretchColor = Color(0xFFFF458E);

/// A neutral tone for a perfectly isometric island — [ModelerColors.wire]'s
/// own hex, so an unstretched island reads the same grey as an ordinary
/// wireframe edge rather than a colour invented just for this screen.
const Color kUvNeutralColor = Color(0xFF8C9399);

/// Maps a stretch value — [stretchOf]'s own scale, where 1.0 is a perfect
/// isometry — to a paint colour: [kUvNeutralColor] at 1.0 or below, ramping
/// linearly up to the acceptance's own [kUvMaxStretchColor] at [severe] and
/// beyond.
///
/// Compression (a stretch below 1.0) reads the same as a perfect isometry:
/// this ramp exists to flag "this island needs re-unwrapping", not to tell a
/// compressed island from an isometric one — [stretchOf]'s own doc comment
/// gives the same reason for not telling the two apart itself.
///
/// A non-finite [stretch] — [stretchOf]'s own signal that nothing about an
/// island was measurable — reads as neutral rather than propagating a NaN
/// into a colour nothing can draw.
Color uvStretchColor(double stretch, {double severe = 2.5}) {
  if (!stretch.isFinite || stretch <= 1.0) return kUvNeutralColor;
  final t = ((stretch - 1.0) / (severe - 1.0)).clamp(0.0, 1.0);
  if (t >= 1.0) return kUvMaxStretchColor;
  return Color.lerp(kUvNeutralColor, kUvMaxStretchColor, t)!;
}
