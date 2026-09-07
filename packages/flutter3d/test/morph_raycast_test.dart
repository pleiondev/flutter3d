/// What a ray finds on a morphed model, which is not what the eye sees.
///
///     flutter test test/morph_raycast_test.dart
///
/// **A known limit, kept as a test so it stays known.** `Raycaster` intersects
/// the CPU geometry, and that geometry is the base shape: the weights are
/// applied in the vertex stage, which a ray never enters. So a face's jaw is
/// hit shut however wide the expression has it open — exactly as a skinned
/// character's arm is hit where the bind pose left it.
///
/// The bounding volumes are the half that *does* follow, so a deformed model is
/// still found as a candidate and still culled correctly. Only the triangle
/// test underneath answers about the older shape.
///
/// If this file ever fails, the limit was closed and the assertions are the
/// thing to update — that is what it is for.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// How far the one target slides the whole cube.
const double _slide = 8.0;

({Scene scene, MeshNode node}) _scene() {
  final device = FakeBackend();
  final base = CuboidShape(size: Vector3.all(1.0)).build();
  final source = MeshData(
    layout: base.layout,
    vertices: base.vertices,
    indices: base.indices,
    morphTargets: <MorphTarget>[
      MorphTarget(
        vertexCount: base.vertexCount,
        name: 'slide',
        positions: Float32List.fromList(<double>[
          for (var v = 0; v < base.vertexCount; v++) ...<double>[_slide, 0, 0],
        ]),
      ),
    ],
  );

  final packed = MorphTexture.pack(source)!;
  final texture = device.createTextureFromPixels(
    width: packed.width,
    height: packed.height,
    format: TextureFormat.r32g32b32a32Float,
    pixels: packed.bytes,
  )!;

  final scene = Scene();
  final node =
      MeshNode(
          DeviceMesh.upload(device, source),
          Material(name: 'cube'),
          name: 'cube',
        )
        ..morph = (MorphState(
          texture: texture,
          targetCount: 1,
          reaches: packed.reaches,
        )..setWeights(<double>[1.0]));
  scene.add(node);
  return (scene: scene, node: node);
}

HitResult? _castAt(Scene scene, double x) {
  final caster = Raycaster();
  caster.ray.origin.setValues(x, 0.0, 10.0);
  caster.ray.direction.setValues(0.0, 0.0, -1.0);
  return caster.intersectScene(scene);
}

void main() {
  test('a ray hits the base shape, where nothing is drawn', () {
    final it = _scene();
    final hit = _castAt(it.scene, 0.0);

    expect(hit?.node?.name, 'cube');
    expect(
      hit?.approximate,
      isFalse,
      reason: 'it is a real triangle hit — on the shape before the morph',
    );
  });

  test('and misses the shape the vertex stage actually draws', () {
    final it = _scene();
    expect(_castAt(it.scene, _slide), isNull);
  });

  test('but the bounds do follow, so it is still a candidate', () {
    // The half that was fixed. Without it the node would be culled out of the
    // frustum as well, and the model would be neither hit nor drawn.
    final it = _scene();
    expect(it.node.worldBounds.max.x, greaterThan(_slide));
    expect(it.node.morph!.growth.max.x, closeTo(_slide, 1e-6));
  });

  test('MorphBlend is the way out for a caller that needs the real shape', () {
    // Not a workaround so much as the tool: it produces the deformed vertices
    // on the host, and a mesh built from those is one a ray hits exactly.
    final it = _scene();
    final source = (it.node.mesh as DeviceMesh).source!;
    final blend = MorphBlend(source)..blend(<double>[1.0]);

    final at = source.layout.floatOffsetOf(VertexLayout.position.name);
    final stride = source.layout.floatsPerVertex;
    expect(
      blend.vertices[at],
      closeTo(source.vertices[at] + _slide, 1e-5),
      reason: 'the blended copy is where the picture is',
    );
    expect(blend.vertices.length, source.vertices.length);
    expect(stride, greaterThan(0));
  });
}
