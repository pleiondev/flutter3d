/// A skinned mesh is culled by a box that contains it.
///
///     flutter test test/skinned_bounds_test.dart
///
/// **The bounds were the bone box padded by two centimetres.** A skinned
/// mesh's own bounding box describes the bind pose, so the renderer culls one
/// against its joints instead — and pads that by `skinReach`, "how far the
/// surface reaches from its bones", measured at instantiation from the mesh's
/// bounding radius.
///
/// That radius is in the mesh's own space, and a rig's own space is not metres:
/// this fixture is authored at a fortieth of one, the crypt's monsters at a
/// hundredth. So a body reaching half a metre off the bone reported a reach of
/// 0.02, the padding did nothing, and a character you were standing beside
/// blinked out as the camera turned — the mesh still on screen, the box around
/// its bones no longer in the frustum.
///
/// What this checks is the property the bounds exist for: every vertex the
/// shader will draw is inside them. The vertices are skinned here, by the
/// formula in `mesh_skinned.vert`, so the check shares no arithmetic with the
/// code that computes the box.
library;

import 'package:flutter3d/src/engine/geometry/mesh_data.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'hero_skin_sharing_test.dart' show loadHero, sourcesOf;

/// Every vertex of [node], where the vertex shader will put it.
///
/// `skinnedModel = model * blend(jointMatrices)`, which is `mesh_skinned.vert`
/// line for line.
List<Vector3> _drawnVertices(MeshNode node, MeshData data) {
  final skin = node.skeleton!;
  skin.update(node.worldMatrix);

  final layout = data.layout;
  final stride = layout.floatsPerVertex;
  final at = layout.floatOffsetOf('position');
  final named = layout.floatOffsetOf('joints');
  final shares = layout.floatOffsetOf('weights');

  final blended = Matrix4.zero();
  final joint = Matrix4.zero();
  final out = <Vector3>[];
  for (var v = 0; v < data.vertexCount; v++) {
    final base = v * stride;
    blended.setZero();
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
      total += data.vertices[base + shares + i];
    }
    if (total <= 1e-5) total = 1.0;
    for (var i = 0; i < 4; i++) {
      final weight = data.vertices[base + shares + i] / total;
      if (weight == 0.0) continue;
      final index = data.vertices[base + named + i].toInt();
      for (var e = 0; e < 16; e++) {
        joint.storage[e] = skin.matrices[index * 16 + e];
      }
      for (var e = 0; e < 16; e++) {
        blended.storage[e] += joint.storage[e] * weight;
      }
    }
    final place = Vector3(
      data.vertices[base + at],
      data.vertices[base + at + 1],
      data.vertices[base + at + 2],
    );
    out.add(node.worldMatrix.transformed3(blended.transformed3(place)));
  }
  return out;
}

void main() {
  test('every vertex the shader draws is inside the bounds it is culled by',
      () async {
    final (:document, :asset) = await loadHero();
    final scene = Scene();
    final instance = asset.instantiate(scene, name: 'hero');
    // Somewhere that is not the origin, because bounds that forgot to move
    // would still pass at the origin.
    instance.root.setPosition(3.0, 1.0, -12.0);

    final sources = sourcesOf(document, asset, instance);

    var checked = 0;
    for (final MapEntry(key: node, value: data) in sources.entries) {
      if (node.skeleton == null) continue;

      final bounds = node.worldBounds;
      final radius = node.worldBoundsRadius;
      final centre = node.worldBoundsCentre;
      for (final vertex in _drawnVertices(node, data)) {
        expect(bounds.containsVector3(vertex), isTrue,
            reason: 'a vertex at $vertex is outside the box $bounds the '
                'renderer culls this mesh by');
        expect(vertex.distanceTo(centre), lessThanOrEqualTo(radius + 1e-4),
            reason: 'a vertex at $vertex is outside the sphere the frustum '
                'test uses');
        checked++;
      }
    }
    expect(checked, greaterThan(100), reason: 'nothing skinned was checked');
  });
}
