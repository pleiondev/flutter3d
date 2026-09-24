/// `C4`: an octahedral impostor — a node baked into [kImpostorGrid] ×
/// [kImpostorGrid] pictures from every direction on the sphere, drawn as one
/// card that turns to the eye and shows the three pictures nearest the way it
/// is seen.
///
/// **The grid, the card and the bake camera are one convention**, written
/// three times — here for the bake, in `lib/impostor.glsl` for the GPU, in
/// `flutter3d_cpu`'s `cpu_shaders_impostor.dart` for the reference — and a
/// sign that differs between them reads a view mirrored. `impostor_test.dart`
/// holds the Dart half to the round trip.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import '../geometry/device_mesh.dart';
import '../render/material.dart';
import 'mesh_node.dart';

/// Views along each side of an impostor atlas: the plan's eight, fixed in
/// 0.8 so no shader block has to carry it.
const int kImpostorGrid = 8;

/// A direction on the sphere as a point of the unit square — the octahedral
/// map with +Y at the centre and -Y at the four corners, so the views a tree
/// is mostly seen from, level and from above, take the middle of the atlas.
Vector2 impostorEncode(Vector3 d) {
  final l1 = math.max(d.x.abs() + d.y.abs() + d.z.abs(), 1e-8);
  final px = d.x / l1, py = d.z / l1;
  final sx = px >= 0.0 ? 1.0 : -1.0, sy = py >= 0.0 ? 1.0 : -1.0;
  final (x, y) = d.y >= 0.0
      ? (px, py)
      : ((1.0 - py.abs()) * sx, (1.0 - px.abs()) * sy);
  return Vector2(x * 0.5 + 0.5, y * 0.5 + 0.5);
}

/// The inverse of [impostorEncode].
Vector3 impostorDecode(double u, double v) {
  final px = u * 2.0 - 1.0, py = v * 2.0 - 1.0;
  final y = 1.0 - px.abs() - py.abs();
  final sx = px >= 0.0 ? 1.0 : -1.0, sy = py >= 0.0 ? 1.0 : -1.0;
  final (x, z) = y >= 0.0
      ? (px, py)
      : ((1.0 - py.abs()) * sx, (1.0 - px.abs()) * sy);
  return Vector3(x, y, z)..normalize();
}

/// The direction view [column], [row] of the grid was baked looking back
/// along: from the middle of the sphere towards the camera that took it.
Vector3 impostorViewDirection(int column, int row) =>
    impostorDecode(column / (kImpostorGrid - 1), row / (kImpostorGrid - 1));

/// The right-hand axis of a card, or a baked view, facing along [d]: level
/// with the ground, except looking straight up or down, where level has no
/// direction and -Z stands in for up.
Vector3 impostorRight(Vector3 d) {
  final up = d.y.abs() > 0.999 ? Vector3(0, 0, -1) : Vector3(0, 1, 0);
  return up.cross(d)..normalize();
}

/// The card an [ImpostorNode] draws, in the layout `impostor.vert` reads.
///
/// Four corners standing upright in the XY plane around [centre] — not where
/// the stage draws them, which is turned to the eye, but what the engine
/// measures bounds from, so the card is culled and chosen by a `LodGroup` by
/// the sphere it stands in. The texcoord says which corner; the tangent's w
/// the sphere's [radius].
MeshData impostorCard({required Vector3 centre, required double radius}) {
  const corners = <(double, double)>[(0, 0), (1, 0), (1, 1), (0, 1)];
  return MeshData(
    layout: VertexLayout.standard,
    vertices: Float32List.fromList(<double>[
      for (final (u, v) in corners) ...<double>[
        centre.x + (u * 2 - 1) * radius,
        centre.y + (1 - v * 2) * radius,
        centre.z,
        0, 0, 1, // normal: the way the card as built faces
        u, v,
        0, 0, 0, radius,
        1, 1, 1, 1,
      ],
    ]),
    indices: Uint32List.fromList(<int>[0, 3, 2, 0, 2, 1]),
  );
}

/// An impostor, drawn — the coarsest level a `LodGroup` can end in.
///
/// A [MeshNode] whose geometry is [impostorCard] and whose material is
/// [Material.impostor], so the renderer draws it the way it draws any mesh:
/// sorted, culled and lit by the same lights, with nothing special-cased.
///
/// **One card, one draw.** A forest of them is a draw per tree rather than one
/// instanced draw: the instanced path keeps the engine's own vertex stage,
/// which knows nothing of turning a card to the eye.
///
/// **Casts no shadow.** The shadow passes draw through the engine's own vertex
/// stage too, and would draw the card as built — an upright square — rather
/// than as seen. A tree far enough away to be a card has a shadow far enough
/// away to be a smudge; the ground under it keeps whatever the mesh levels
/// nearer the camera cast.
final class ImpostorNode extends MeshNode {
  /// Uploads [impostorCard] for [centre] and [radius] to [device].
  ImpostorNode(
    GraphicsDevice device, {
    required TextureHandle albedo,
    required TextureHandle normalDepth,
    required Vector3 centre,
    required double radius,
    String? name,
  }) : this.withCard(
         DeviceMesh.upload(
           device,
           impostorCard(centre: centre, radius: radius),
         ),
         albedo: albedo,
         normalDepth: normalDepth,
         centre: centre,
         radius: radius,
         name: name,
       );

  /// Draws a [card] already uploaded — the one every copy of a model shares,
  /// so a forest of one tree uploads four vertices once.
  ImpostorNode.withCard(
    MeshGeometry card, {
    required TextureHandle albedo,
    required TextureHandle normalDepth,
    required Vector3 centre,
    required this.radius,
    super.name,
  }) : centre = centre.clone(),
       super(
         card,
         Material.impostor(albedo: albedo, normalDepth: normalDepth),
       ) {
    shadowCasting = ShadowCastingMode.off;
  }

  /// The middle of the baked sphere, in this node's own space.
  final Vector3 centre;

  /// The baked sphere's radius — half the side of the card.
  final double radius;
}
