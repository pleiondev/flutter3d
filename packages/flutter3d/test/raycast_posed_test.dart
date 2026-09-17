/// `gfx-11n`: a ray hits the pose, not the shape the model was exported in.
///
///     flutter test test/raycast_posed_test.dart
///
/// **The defect, in one sentence.** The vertex stage poses a skinned mesh and
/// the CPU copy is the bind pose, so a raycast answered about a character
/// standing still however hard they were running: a shot missed the arm that
/// was raised and hit the air where the arm used to be. The bounding volumes
/// already followed the pose, which made it worse — the node was found as a
/// candidate and then the triangle test said no.
///
/// The fixture is the smallest thing that can show it: one bar bound to one
/// joint, tested by two rays. One goes through where the bar *is* once the
/// joint has swung it up, the other through where the bind pose left it. The
/// two swap verdicts when the pose changes, which no test against a single ray
/// could tell from a test that simply moved the object.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A bar lying along +X from the origin, bound entirely to one joint.
///
/// Skinned with every weight on joint zero and an identity inverse bind, so
/// the joint's own transform is the whole of the pose: turning the joint
/// turns the bar, exactly as the vertex stage would.
({Scene scene, MeshNode bar, SceneNode joint}) _arm(CpuDevice device) {
  final scene = Scene();

  final data = CuboidShape(size: Vector3(2.0, 0.3, 0.3)).build();
  final skinned = _withSkinWeights(data);

  final bar = MeshNode(
    DeviceMesh.upload(device, skinned),
    Material(name: 'bar'),
    name: 'bar',
  )..skinReach = 3.0;
  // The bar's own geometry is centred on the origin, so it reaches from -1 to
  // +1 along x; shifting it here would confuse the pose with the placement.
  scene.add(bar);

  final joint = SceneNode(name: 'shoulder');
  scene.add(joint);
  bar.skeleton = Skeleton(
    name: 'one bone',
    joints: <SceneNode>[joint],
    inverseBindMatrices: <Matrix4>[Matrix4.identity()],
  );

  return (scene: scene, bar: bar, joint: joint);
}

/// [data] with joints and weights added: every vertex fully on joint zero.
MeshData _withSkinWeights(MeshData data) {
  final layout = VertexLayout(<VertexAttribute>[
    ...data.layout.attributes,
    VertexLayout.joints,
    VertexLayout.weights,
  ]);
  final oldStride = data.layout.floatsPerVertex;
  final stride = layout.floatsPerVertex;
  final count = data.vertices.length ~/ oldStride;
  final vertices = Float32List(count * stride);
  final jointsAt = layout.floatOffsetOf(VertexLayout.joints.name);
  final weightsAt = layout.floatOffsetOf(VertexLayout.weights.name);

  for (var v = 0; v < count; v++) {
    for (var f = 0; f < oldStride; f++) {
      vertices[v * stride + f] = data.vertices[v * oldStride + f];
    }
    vertices[v * stride + jointsAt] = 0.0;
    vertices[v * stride + weightsAt] = 1.0;
  }
  return MeshData(layout: layout, vertices: vertices, indices: data.indices);
}

/// Whether a ray straight down through ([x], [z]) finds the bar.
bool _hitsFromAbove(Scene scene, double x, double z, {bool posed = true}) {
  final caster = Raycaster()..posed = posed;
  caster.ray.origin.setValues(x, 6.0, z);
  caster.ray.direction.setValues(0.0, -1.0, 0.0);
  final hit = caster.intersectScene(scene);
  return hit != null && !hit.approximate;
}

void main() {
  late CpuDevice device;

  setUp(() {
    device = CpuDevice(
      width: 8,
      height: 8,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
  });

  group('the bind pose, before anything is asked of the joint', () {
    test('the bar is where it was modelled', () {
      final it = _arm(device);
      it.bar.skeleton!.update(it.bar.worldMatrix);

      expect(_hitsFromAbove(it.scene, 0.8, 0.0), isTrue);
      expect(_hitsFromAbove(it.scene, 0.0, 1.5), isFalse);
    });
  });

  group('a hit on a raised arm registers; a miss past it does not', () {
    test('turning the joint moves what the ray finds', () {
      final it = _arm(device);
      // A quarter turn about +Y swings the bar from along x to along z.
      it.joint.setLocalMatrix(Matrix4.rotationY(1.5707963));
      it.bar.skeleton!.update(it.bar.worldMatrix);

      expect(
        _hitsFromAbove(it.scene, 0.0, 0.8),
        isTrue,
        reason: 'the bar is along z now and the ray goes through it',
      );
      expect(
        _hitsFromAbove(it.scene, 0.8, 0.0),
        isFalse,
        reason: 'and nothing is left where the bind pose had it',
      );
    });

    test('with posing off, the old answer comes back exactly', () {
      final it = _arm(device);
      it.joint.setLocalMatrix(Matrix4.rotationY(1.5707963));
      it.bar.skeleton!.update(it.bar.worldMatrix);

      // The defect, on purpose: the caster is told to use the authored shape
      // and duly answers about a bar that is no longer there.
      expect(_hitsFromAbove(it.scene, 0.8, 0.0, posed: false), isTrue);
      expect(_hitsFromAbove(it.scene, 0.0, 0.8, posed: false), isFalse);
    });

    test('a joint that moves the bar aside takes the hit with it', () {
      final it = _arm(device);
      it.joint.setLocalMatrix(Matrix4.translation(Vector3(0.0, 0.0, 2.0)));
      it.bar.skeleton!.update(it.bar.worldMatrix);

      expect(_hitsFromAbove(it.scene, 0.8, 2.0), isTrue);
      expect(_hitsFromAbove(it.scene, 0.8, 0.0), isFalse);
    });
  });

  group('the posed copy is made once and kept', () {
    test('it follows the pose version rather than the call count', () {
      final it = _arm(device);
      final skeleton = it.bar.skeleton!;
      skeleton.update(it.bar.worldMatrix);

      final posed = PosedMesh();
      final source = it.bar.mesh.source!;
      final first = posed.positionsOf(source, skeleton)!;
      final again = posed.positionsOf(source, skeleton);
      expect(identical(first, again), isTrue);
      expect(posed.vertexCount, greaterThan(0));

      // Read out *before* the re-pose: the buffer is reused, so comparing it
      // with itself afterwards would compare the new value with the new
      // value — which is exactly the mistake the first version of this test
      // made and which passed for the wrong reason until the pose moved.
      final wasX = first[0];

      it.joint.setLocalMatrix(Matrix4.rotationY(1.0));
      skeleton.update(it.bar.worldMatrix);
      final moved = posed.positionsOf(source, skeleton)!;
      // The same buffer, refilled — the point is that it is not reallocated,
      // and that its contents moved.
      expect(identical(first, moved), isTrue);
      expect(moved[0], isNot(wasX));
    });

    test('an unskinned mesh poses nothing at all', () {
      final plain = CuboidShape(size: Vector3(1.0, 1.0, 1.0)).build();
      final skeleton = Skeleton(
        joints: <SceneNode>[SceneNode()],
        inverseBindMatrices: <Matrix4>[Matrix4.identity()],
      );
      expect(PosedMesh().positionsOf(plain, skeleton), isNull);
    });
  });
}
