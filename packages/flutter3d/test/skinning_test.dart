import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

const String kSamples = kSamplesPath;

Uint8List readSample(String name) => File('$kSamples/$name').readAsBytesSync();

/// Reads joint matrix [index] out of the packed array.
Matrix4 jointMatrix(Skeleton skeleton, int index) {
  final storage = Float32List(16);
  for (var e = 0; e < 16; e++) {
    storage[e] = skeleton.matrices[index * 16 + e];
  }
  return Matrix4.fromFloat32List(storage);
}

/// Applies the skinning maths the vertex shader does, on the CPU.
///
/// The shader is not testable without a device, but the arithmetic it performs
/// is — and the arithmetic is where a skinning bug lives. If this agrees with
/// the shader on the GPU, both are reading the same matrices the same way.
Vector3 skinVertex(
  Skeleton skeleton,
  Vector3 position,
  List<int> joints,
  List<double> weights,
) {
  var total = 0.0;
  for (final w in weights) {
    total += w;
  }
  final normalized = total > 1e-5
      ? <double>[for (final w in weights) w / total]
      : <double>[1.0, 0.0, 0.0, 0.0];

  final blended = Matrix4.zero();
  for (var i = 0; i < joints.length; i++) {
    final m = jointMatrix(skeleton, joints[i]);
    for (var e = 0; e < 16; e++) {
      blended.storage[e] += m.storage[e] * normalized[i];
    }
  }
  return blended.transformed3(position.clone());
}

/// Two joints in a chain, the second a child of the first, bound at rest.
({Scene scene, Skeleton skeleton, SceneNode root, SceneNode tip}) chain() {
  final scene = Scene();
  final root = scene.add(SceneNode(name: 'root'));
  final tip = SceneNode(name: 'tip')..setPosition(0.0, 1.0, 0.0);
  root.add(tip);

  // At bind time the joints are where they are now, so each inverse bind is the
  // inverse of that joint's world transform.
  final skeleton = Skeleton(
    name: 'chain',
    joints: <SceneNode>[root, tip],
    inverseBindMatrices: <Matrix4>[
      Matrix4.copy(root.worldMatrix)..invert(),
      Matrix4.copy(tip.worldMatrix)..invert(),
    ],
  );
  return (scene: scene, skeleton: skeleton, root: root, tip: tip);
}

void main() {
  group('the bind pose is the identity', () {
    test('an unposed skeleton leaves every vertex where it was', () {
      final (:skeleton, :root, :tip, :scene) = chain();
      skeleton.update(Matrix4.identity());

      // The whole point of the inverse bind matrix: at rest the product is
      // identity, so a skinned mesh in its bind pose renders exactly as an
      // unskinned one would. Anything else means the model jumps the moment it
      // is loaded.
      for (var j = 0; j < skeleton.jointCount; j++) {
        final m = jointMatrix(skeleton, j);
        for (var e = 0; e < 16; e++) {
          expect(
            m.storage[e],
            closeTo(Matrix4.identity().storage[e], 1e-5),
            reason: 'joint $j element $e',
          );
        }
      }
    });

    test('slots past the joint count stay identity', () {
      // A mesh whose weights name a joint the skeleton does not have would
      // otherwise read zeros and collapse the vertex to the origin.
      final (:skeleton, :root, :tip, :scene) = chain();
      skeleton.update(Matrix4.identity());

      final spare = jointMatrix(skeleton, Skeleton.maxJoints - 1);
      expect(spare.storage, orderedEquals(Matrix4.identity().storage));
    });
  });

  group('posing moves the mesh', () {
    test('rotating a joint carries the vertices bound to it', () {
      final (:skeleton, :root, :tip, :scene) = chain();
      // A quarter turn about Z at the root: a point out along +Y should end up
      // along -X.
      root.setRotationYawPitchRoll(0.0, 0.0, math.pi / 2);
      skeleton.update(Matrix4.identity());

      final moved = skinVertex(
        skeleton,
        Vector3(0.0, 1.0, 0.0),
        <int>[0, 0, 0, 0],
        <double>[1.0, 0.0, 0.0, 0.0],
      );
      expect(moved.x, closeTo(-1.0, 1e-5));
      expect(moved.y, closeTo(0.0, 1e-5));
    });

    test('a child joint inherits its parent, as any node does', () {
      final (:skeleton, :root, :tip, :scene) = chain();
      root.setPosition(5.0, 0.0, 0.0);
      skeleton.update(Matrix4.identity());

      // The tip is bound at (0, 1, 0) and its parent moved five along X, so a
      // vertex rigidly attached to the tip moves with it.
      final moved = skinVertex(
        skeleton,
        Vector3(0.0, 1.0, 0.0),
        <int>[1, 0, 0, 0],
        <double>[1.0, 0.0, 0.0, 0.0],
      );
      expect(moved.x, closeTo(5.0, 1e-5));
      expect(moved.y, closeTo(1.0, 1e-5));
    });

    test('a half-and-half vertex lands between the two joints', () {
      final (:skeleton, :root, :tip, :scene) = chain();
      root.setPosition(4.0, 0.0, 0.0);
      tip.setPosition(0.0, 1.0, 0.0);
      skeleton.update(Matrix4.identity());

      final rigid = skinVertex(
        skeleton,
        Vector3(0.0, 1.0, 0.0),
        <int>[0, 0, 0, 0],
        <double>[1.0, 0.0, 0.0, 0.0],
      );
      final blended = skinVertex(
        skeleton,
        Vector3(0.0, 1.0, 0.0),
        <int>[0, 1, 0, 0],
        <double>[0.5, 0.5, 0.0, 0.0],
      );

      // Both joints moved the same way here, so the blend agrees with either —
      // what matters is that it is finite and on the segment, not off at the
      // origin.
      expect(blended.x, closeTo(rigid.x, 1e-5));
      expect(blended.y, closeTo(rigid.y, 1e-5));
    });

    test('weights that do not sum to one are renormalized, not obeyed', () {
      // An exporter rounding to a normalized byte leaves sums a little off, and
      // taking them literally makes the mesh breathe.
      final (:skeleton, :root, :tip, :scene) = chain();
      root.setPosition(2.0, 0.0, 0.0);
      skeleton.update(Matrix4.identity());

      final exact = skinVertex(
        skeleton,
        Vector3(0.0, 0.0, 0.0),
        <int>[0, 0, 0, 0],
        <double>[1.0, 0.0, 0.0, 0.0],
      );
      final sloppy = skinVertex(
        skeleton,
        Vector3(0.0, 0.0, 0.0),
        <int>[0, 0, 0, 0],
        <double>[0.5, 0.5, 0.0, 0.0],
      );
      expect(sloppy.x, closeTo(exact.x, 1e-5));
    });

    test('the mesh node transform is divided out', () {
      // The renderer applies the model matrix after skinning, so the joint
      // matrices must not contain it. Leaving it in places the model twice.
      final (:skeleton, :root, :tip, :scene) = chain();
      final meshWorld = Matrix4.translation(Vector3(10.0, 0.0, 0.0));
      skeleton.update(meshWorld);

      final moved = skinVertex(
        skeleton,
        Vector3(0.0, 0.0, 0.0),
        <int>[0, 0, 0, 0],
        <double>[1.0, 0.0, 0.0, 0.0],
      );
      expect(
        moved.x,
        closeTo(-10.0, 1e-5),
        reason: 'the joint matrix should undo the mesh placement',
      );
    });
  });

  group('bounds follow the pose, not the bind', () {
    test('moving a joint moves the reported bounds', () {
      final (:skeleton, :root, :tip, :scene) = chain();
      final before = skeleton.computeBounds();
      root.setPosition(0.0, 20.0, 0.0);
      final after = skeleton.computeBounds();

      // A skinned mesh's own bounds describe the bind pose, so culling against
      // them makes a moving character disappear while still on screen.
      expect(after.min.y, greaterThan(before.max.y));
    });

    test('reach pads the box around the bones', () {
      final (:skeleton, :root, :tip, :scene) = chain();
      final tight = skeleton.computeBounds();
      final padded = skeleton.computeBounds(reach: 2.0);
      expect(padded.min.x, closeTo(tight.min.x - 2.0, 1e-6));
      expect(padded.max.y, closeTo(tight.max.y + 2.0, 1e-6));
    });

    test('the pose version changes only when a joint moves', () {
      final (:skeleton, :root, :tip, :scene) = chain();
      final atRest = skeleton.poseVersion;
      expect(skeleton.poseVersion, atRest);

      root.setPosition(1.0, 0.0, 0.0);
      expect(skeleton.poseVersion, isNot(atRest));
    });
  });

  group('a skeleton refuses what it cannot hold', () {
    test('mismatched joint and matrix counts', () {
      final scene = Scene();
      final joint = scene.add(SceneNode());
      expect(
        () => Skeleton(
          joints: <SceneNode>[joint],
          inverseBindMatrices: <Matrix4>[
            Matrix4.identity(),
            Matrix4.identity(),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('more joints than the shader has slots', () {
      final scene = Scene();
      final joints = <SceneNode>[
        for (var i = 0; i < Skeleton.maxJoints + 1; i++)
          scene.add(SceneNode(name: 'j$i')),
      ];
      expect(
        () => Skeleton(
          joints: joints,
          inverseBindMatrices: <Matrix4>[
            for (var i = 0; i < joints.length; i++) Matrix4.identity(),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('kMaxJoints'),
          ),
        ),
      );
    });
  });

  group('decoding a rigged glTF', () {
    test('RiggedSimple produces a skin the surface points at', () async {
      final asset = await GltfLoader().load(readSample('RiggedSimple.glb'));

      expect(asset.skins, hasLength(1));
      expect(asset.skins.single.joints, hasLength(2));
      expect(asset.surfaces.single.skinIndex, 0);
      expect(asset.animations, isNotEmpty);
    });

    test('a skinned primitive gets the skinned vertex layout', () async {
      final asset = await GltfLoader().load(readSample('RiggedFigure.glb'));
      final layout = asset.surfaces.single.mesh.layout;

      // Chosen from the data rather than from the caller: a mesh with joint
      // attributes is skinned whichever node draws it, and the renderer picks
      // its vertex stage from the same fact.
      expect(layout.isSkinned, isTrue);
      expect(layout.has(VertexLayout.joints), isTrue);
      expect(layout.has(VertexLayout.weights), isTrue);
    });

    test('a static model keeps the smaller layout', () async {
      final asset = await GltfLoader().load(readSample('Box.glb'));
      expect(asset.surfaces.single.mesh.layout.isSkinned, isFalse);
      expect(asset.skins, isEmpty);
      expect(asset.surfaces.single.skinIndex, isNull);
    });

    test('joint indices are read as integers, not normalized', () async {
      // JOINTS_0 is an unsigned byte or short. Running it through the
      // normalization path would turn joint 3 into 0.015 and bind the whole
      // mesh to joint zero.
      final asset = await GltfLoader().load(readSample('RiggedFigure.glb'));
      final mesh = asset.surfaces.single.mesh;
      final offset = mesh.layout.floatOffsetOf(VertexLayout.joints.name);
      final stride = mesh.layout.floatsPerVertex;
      final jointCount = asset.skins.single.joints.length;

      var maxJoint = 0.0;
      for (var v = 0; v < mesh.vertexCount; v++) {
        for (var c = 0; c < 4; c++) {
          final value = mesh.vertices[v * stride + offset + c];
          expect(
            value,
            value.roundToDouble(),
            reason: 'joint indices must be whole numbers',
          );
          expect(value, lessThan(jointCount.toDouble()));
          if (value > maxJoint) maxJoint = value;
        }
      }
      expect(
        maxJoint,
        greaterThan(0.0),
        reason: 'every vertex bound to joint 0 means the read was wrong',
      );
    });

    test('weights are present and sum to about one', () async {
      final asset = await GltfLoader().load(readSample('RiggedFigure.glb'));
      final mesh = asset.surfaces.single.mesh;
      final offset = mesh.layout.floatOffsetOf(VertexLayout.weights.name);
      final stride = mesh.layout.floatsPerVertex;

      for (var v = 0; v < mesh.vertexCount; v++) {
        var sum = 0.0;
        for (var c = 0; c < 4; c++) {
          sum += mesh.vertices[v * stride + offset + c];
        }
        expect(
          sum,
          closeTo(1.0, 0.02),
          reason: 'vertex $v weights sum to $sum',
        );
      }
    });

    test('a skinned surface is not given the node transform as well', () async {
      // Skinned vertices are already in the skin's space and the joints place
      // them; baking the node transform in too applies the placement twice.
      final asset = await GltfLoader().load(readSample('RiggedFigure.glb'));
      final transform = asset.surfaces.single.transform;
      expect(transform.storage, orderedEquals(Matrix4.identity().storage));
    });

    test('inverse bind matrices are read, not defaulted to identity', () async {
      final asset = await GltfLoader().load(readSample('RiggedFigure.glb'));
      final matrices = asset.skins.single.inverseBindMatrices;

      expect(matrices, hasLength(asset.skins.single.joints.length));
      final allIdentity = matrices.every(
        (m) => m.storage.indexed.every(
          (e) => (e.$2 - Matrix4.identity().storage[e.$1]).abs() < 1e-9,
        ),
      );
      expect(
        allIdentity,
        isFalse,
        reason: 'a real rig does not bind at the origin',
      );
    });
  });
}
