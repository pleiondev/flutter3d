/// What a mesh carries besides its shape, and where each of them lives.
///
/// **Four domains, and which one an attribute belongs to is a decision about
/// what an edit means.** A position is per *vertex*: move it and every face
/// around it follows, which is what dragging a corner has to do. A texture
/// coordinate is per *corner* — per half-edge — because a UV seam is exactly
/// the case where the two faces meeting at a vertex disagree about where it is
/// on the texture, and a per-vertex UV cannot express that. Sharpness is per
/// *edge*, because it is a property of the crease between two faces rather than
/// of either. A material slot is per *face*.
///
/// Getting this wrong is not a performance question. A per-vertex UV makes
/// seams impossible; a per-corner position makes a mesh that comes apart when
/// somebody drags it.
///
/// **A layer that was never written does not exist, and reads answer with a
/// neutral value.** A cube from a primitive has no vertex colours, and
/// allocating four floats per corner to say "white" on every mesh in every
/// document is a megabyte per 60 000 corners for information nobody entered.
/// So layers are created on the first write; `colorOf` answers white until
/// then, `weightsOf` answers "all of the first joint", and a conversion asks
/// whether the layer is there before spending a byte on it.
library;

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

/// Where an attribute lives.
///
/// The four things a half-edge mesh is made of. A domain over the whole mesh,
/// which other tools keep attributes on, would be a fifth, so the set is open.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class MeshDomain {
  const MeshDomain._(this.name);

  /// One value per vertex. Positions, skin weights.
  static const MeshDomain vertex = MeshDomain._('vertex');

  /// One value per half-edge, so the faces meeting at a vertex may disagree.
  /// Texture coordinates, vertex colours.
  static const MeshDomain corner = MeshDomain._('corner');

  /// One value per edge, mirrored onto both half-edges of the pair. Sharpness,
  /// seams, crease weight.
  static const MeshDomain edge = MeshDomain._('edge');

  /// One value per face. RenderMaterial slot, shading flag.
  static const MeshDomain face = MeshDomain._('face');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<MeshDomain> values = <MeshDomain>[
    vertex,
    corner,
    edge,
    face,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static MeshDomain? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'MeshDomain.$name';
}

/// Which attribute, within a domain.
///
/// The set is what this mesh stores, and a caller cannot add to it: a new
/// attribute is a layer in `EditMesh`, which a later release can add, so the
/// set is open.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class MeshAttribute {
  const MeshAttribute._(this.name);

  /// The first texture coordinate set, per corner, so a seam can split it.
  static const MeshAttribute uv0 = MeshAttribute._('uv0');

  /// The vertex colour, per corner, in linear light; white where unwritten.
  static const MeshAttribute color = MeshAttribute._('color');

  /// The four skin weights, per vertex; all on the first joint where
  /// unwritten.
  static const MeshAttribute weights = MeshAttribute._('weights');

  /// The four joint indices the [weights] refer to, per vertex.
  static const MeshAttribute joints = MeshAttribute._('joints');

  /// The subdivision crease weight, per edge, from nought (smooth) to one
  /// (held through every level).
  static const MeshAttribute crease = MeshAttribute._('crease');

  /// The bitfield of [EdgeFlags] on the edge domain, or of [FaceFlags] on
  /// the face domain.
  static const MeshAttribute flags = MeshAttribute._('flags');

  /// The index of the material a face is drawn with, per face.
  static const MeshAttribute materialSlot = MeshAttribute._('materialSlot');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<MeshAttribute> values = <MeshAttribute>[
    uv0,
    color,
    weights,
    joints,
    crease,
    flags,
    materialSlot,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static MeshAttribute? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'MeshAttribute.$name';
}

/// Bits packed into the per-half-edge flag layer.
///
/// A bitfield rather than a layer apiece: these are booleans that are read
/// together — a normal calculation asks about sharpness, a UV unwrap asks about
/// seams, and a subdivision asks about both — and three `Int32List`s over the
/// same domain is three cache misses where one does.
abstract final class EdgeFlags {
  /// The edge is a hard crease: normals are not averaged across it.
  static const int sharp = 1 << 0;

  /// The edge is a UV seam: an unwrap may cut here.
  ///
  /// Separate from [sharp] because they are separate decisions — a cylinder's
  /// seam is not a hard edge, and a box's hard edges are not all seams — and
  /// conflating them is what makes an unwrap put a cut down the middle of a
  /// smooth surface.
  static const int seam = 1 << 1;
}

/// Bits packed into the per-face flag layer.
abstract final class FaceFlags {
  /// Normals are averaged with the neighbours across every edge that is not
  /// [EdgeFlags.sharp].
  static const int smooth = 1 << 0;
}

/// What a corner carries, gathered for an operation that has to move one.
///
/// **A value rather than a set of out parameters**, because the callers are
/// splits and extrusions: they read a corner, read another, and write a third
/// somewhere between. Three named fields is what that reads like; six out
/// parameters is what it read like before.
final class CornerAttributes {
  /// A corner at [uv] and [color]; null takes the origin and white, the
  /// values an unwritten layer reads as.
  CornerAttributes({Vector2? uv, LinearColor? color})
    : uv = uv ?? Vector2.zero(),
      color = color ?? neutralColor;

  /// The corner's texture coordinate in the first UV set, unitless, with
  /// nought to one spanning the texture.
  final Vector2 uv;

  /// The corner's vertex colour, in linear light as every vertex colour is.
  final LinearColor color;

  /// The corner half way between [a] and [b] at [t].
  ///
  /// Linear in both, which is what a split down the middle of an edge means:
  /// the new corner sits where the texture would have been at that point. A
  /// texture that was stretched non-linearly across the face was already
  /// stretched non-linearly, and pretending otherwise here would move the
  /// pixels that were there before the cut.
  static CornerAttributes lerp(
    CornerAttributes a,
    CornerAttributes b,
    double t,
  ) => CornerAttributes(
    uv: a.uv + (b.uv - a.uv) * t,
    color: LinearColor.lerp(a.color, b.color, t),
  );

  @override
  String toString() => 'CornerAttributes(uv: $uv, colour: $color)';
}

/// What a vertex carries besides its position.
final class VertexAttributes {
  /// A vertex skinned by [joints] with [weights]; null takes joint nought
  /// at full weight, the values an unwritten layer reads as. Both are
  /// copied.
  VertexAttributes({Vector4? joints, Vector4? weights})
    : joints = joints ?? Vector4.copy(neutralJoints),
      weights = weights ?? Vector4.copy(neutralWeights);

  /// Which four joints deform this vertex, as indices held in floats — the way
  /// `VertexLayout` carries them, so nothing converts on the way to a GPU.
  final Vector4 joints;

  /// How much each of those four pulls. Sums to one on a well-formed vertex.
  final Vector4 weights;

  /// The vertex half way between [a] and [b] at [t], with the weights
  /// renormalised.
  ///
  /// **Renormalised, and that is the whole reason this is not a lerp.** Two
  /// vertices bound to *different* joints interpolate into a vertex bound to up
  /// to eight, and this keeps the four that pull hardest — which is what a
  /// shader with four weight slots can carry. Dropping the smallest and letting
  /// the rest sum to less than one is how a limb ends up half its size at the
  /// seam of a split.
  ///
  /// Limiting to four is `mesh-60`'s subject in general; what is here is the
  /// case a split creates, and it is the common one.
  static VertexAttributes lerp(
    VertexAttributes a,
    VertexAttributes b,
    double t,
  ) {
    // Joint index to weight, summed across both sides.
    final pull = <int, double>{};
    void gather(VertexAttributes from, double scale) {
      for (var i = 0; i < 4; i++) {
        final joint = from.joints[i].round();
        final weight = from.weights[i] * scale;
        if (weight <= 0) continue;
        pull[joint] = (pull[joint] ?? 0) + weight;
      }
    }

    gather(a, 1 - t);
    gather(b, t);
    if (pull.isEmpty) return VertexAttributes();

    final ranked = pull.entries.toList(growable: false)
      ..sort(
        (MapEntry<int, double> x, MapEntry<int, double> y) =>
            y.value.compareTo(x.value),
      );
    final kept = ranked.take(4).toList(growable: false);
    final total = kept.fold<double>(
      0,
      (double sum, MapEntry<int, double> entry) => sum + entry.value,
    );

    final joints = Vector4.zero();
    final weights = Vector4.zero();
    for (var i = 0; i < kept.length; i++) {
      joints[i] = kept[i].key.toDouble();
      weights[i] = total == 0 ? 0 : kept[i].value / total;
    }
    return VertexAttributes(joints: joints, weights: weights);
  }

  @override
  String toString() => 'VertexAttributes(joints: $joints, weights: $weights)';
}
