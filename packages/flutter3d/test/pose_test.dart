/// `anim-01`: `Pose` — local TRS in flat typed arrays, sampled from a clip
/// and composed into world/joint matrices without a `Scene` — agrees with
/// the scene-graph pipeline (`AnimationPlayer` + `SceneNode` + `Skeleton`)
/// it is meant to be a drop-in alternative to.
///
///     dart test test/pose_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

const String kSamples = kSamplesPath;

Uint8List readSample(String name) => File('$kSamples/$name').readAsBytesSync();

/// Builds a live `SceneNode` mirror of [nodes]/[roots] — the same walk
/// `ModelAsset.instantiate` does, minus meshes and materials, since this
/// test's reference implementation is the scene graph itself, the thing
/// `Pose` exists not to need.
({Scene scene, List<SceneNode> created}) _buildScene(
  List<ModelNode> nodes,
  List<int> roots,
) {
  final scene = Scene();
  final created = List<SceneNode?>.filled(nodes.length, null);
  final pending = <(int, SceneNode)>[
    for (final r in roots.reversed)
      if (r >= 0 && r < nodes.length) (r, scene.root),
  ];
  while (pending.isNotEmpty) {
    final (index, parent) = pending.removeLast();
    if (created[index] != null) continue;
    final model = nodes[index];
    final node = SceneNode(name: model.name)
      ..setPosition(
        model.translation.x,
        model.translation.y,
        model.translation.z,
      )
      ..setRotation(model.rotation)
      ..setScale(model.scale.x, model.scale.y, model.scale.z);
    parent.add(node);
    created[index] = node;
    for (final child in model.children.reversed) {
      if (child >= 0 && child < nodes.length) pending.add((child, node));
    }
  }
  return (
    scene: scene,
    created: <SceneNode>[
      for (var i = 0; i < created.length; i++) created[i] ?? scene.root,
    ],
  );
}

void _expectMatrixClose(
  Matrix4 a,
  Matrix4 b, {
  double tol = 1e-5,
  String? reason,
}) {
  for (var e = 0; e < 16; e++) {
    expect(
      a.storage[e],
      closeTo(b.storage[e], tol),
      reason: '$reason, element $e',
    );
  }
}

void main() {
  group('BoxAnimated: world matrices, against the scene graph', () {
    test('Pose.worldMatrices agrees with SceneNode.worldMatrix at several '
        'times', () async {
      final asset = await GltfLoader().load(readSample('BoxAnimated.glb'));
      expect(asset.animations, isNotEmpty);
      final clip = asset.animations.first;

      final built = _buildScene(asset.nodes, asset.roots);
      final player = AnimationPlayer(
        clips: asset.animations,
        targets: List<AnimationTarget?>.of(built.created),
      );
      final pose = Pose.fromNodes(asset.nodes);

      for (final t in <double>[
        0.0,
        clip.duration * 0.25,
        clip.duration * 0.5,
        clip.duration * 0.9,
        clip.duration,
      ]) {
        player.play(0);
        player.seek(t);
        pose.sampleClip(clip, t);
        final world = pose.worldMatrices();

        // Mutation: swap the parent/child multiplication order in
        // `worldMatrices` (`local * parentWorld` instead of the reverse) —
        // this catches it on the first node that has a parent, since the
        // two orders only agree for a pure translation.
        for (var i = 0; i < asset.nodes.length; i++) {
          _expectMatrixClose(
            world[i],
            built.created[i].worldMatrix,
            reason: 'node $i at t=$t',
          );
        }
      }
    });

    test('a track-free node keeps its rest transform, not identity', () async {
      final asset = await GltfLoader().load(readSample('BoxAnimated.glb'));
      final clip = asset.animations.first;

      // Every node BoxAnimated has is animated, so this checks the general
      // machinery on a hand-built document instead: a second root with no
      // track, spliced onto the same clip.
      final untouched = ModelNode(
        translation: Vector3(1.0, 2.0, 3.0),
        children: const <int>[],
      );
      final withExtra = <ModelNode>[...asset.nodes, untouched];
      final withExtraPose = Pose.fromNodes(withExtra);
      withExtraPose.sampleClip(clip, clip.duration * 0.5);

      final world = withExtraPose.worldMatrices();
      final extraWorld = world.last;
      // Mutation: reset every node's rest transform to identity instead of
      // its own — this node would then read (0, 0, 0) instead of (1, 2, 3).
      expect(extraWorld.getTranslation().x, closeTo(1.0, 1e-6));
      expect(extraWorld.getTranslation().y, closeTo(2.0, 1e-6));
      expect(extraWorld.getTranslation().z, closeTo(3.0, 1e-6));
    });
  });

  group('RiggedSimple: joint matrices, against Skeleton', () {
    test('Pose.jointMatrices agrees with Skeleton.matrices at several '
        'times', () async {
      final asset = await GltfLoader().load(readSample('RiggedSimple.glb'));
      expect(asset.skins, hasLength(1));
      expect(asset.animations, isNotEmpty);
      final skin = asset.skins.single;
      final clip = asset.animations.first;

      final built = _buildScene(asset.nodes, asset.roots);
      final player = AnimationPlayer(
        clips: asset.animations,
        targets: List<AnimationTarget?>.of(built.created),
      );
      final skeleton = Skeleton(
        joints: <SceneNode>[for (final j in skin.joints) built.created[j]],
        inverseBindMatrices: skin.inverseBindMatrices,
        name: skin.name,
      );

      final meshNodeIndex = asset.nodes.indexWhere(
        (n) => n.surfaces.isNotEmpty,
      );
      expect(meshNodeIndex, greaterThanOrEqualTo(0));

      final pose = Pose.fromNodes(asset.nodes);

      for (final t in <double>[
        0.0,
        clip.duration * 0.25,
        clip.duration * 0.5,
        clip.duration * 0.75,
        clip.duration,
      ]) {
        player.play(0);
        player.seek(t);
        skeleton.update(built.created[meshNodeIndex].worldMatrix);

        pose.sampleClip(clip, t);
        final poseWorld = pose.worldMatrices();
        final poseJoints = pose.jointMatrices(
          joints: skin.joints,
          inverseBindMatrices: skin.inverseBindMatrices,
          meshWorld: poseWorld[meshNodeIndex],
        );

        // Mutation: drop the `inverse(meshWorld)` term in `jointMatrices` —
        // this diverges the moment the mesh node itself is not at the
        // origin, which RiggedSimple's is not.
        for (var e = 0; e < poseJoints.length; e++) {
          expect(
            poseJoints[e],
            closeTo(skeleton.matrices[e], 1e-5),
            reason: 'element $e at t=$t',
          );
        }
      }
    });
  });

  group('Pose on its own, without a sample file', () {
    Pose chainPose() => Pose(
      parents: <int>[-1, 0, 1],
      restTranslations: Float32List.fromList(<double>[
        0, 0, 0, // root
        0, 1, 0, // mid, one unit above root
        0, 1, 0, // tip, one more unit above mid
      ]),
      restRotations: Float32List.fromList(<double>[
        0, 0, 0, 1, //
        0, 0, 0, 1, //
        0, 0, 0, 1, //
      ]),
      restScales: Float32List.fromList(<double>[
        1, 1, 1, //
        1, 1, 1, //
        1, 1, 1, //
      ]),
    );

    test('world positions accumulate down a chain', () {
      final pose = chainPose();
      final world = pose.worldMatrices();
      expect(world[0].getTranslation().y, closeTo(0.0, 1e-9));
      expect(world[1].getTranslation().y, closeTo(1.0, 1e-9));
      expect(world[2].getTranslation().y, closeTo(2.0, 1e-9));
    });

    test('restOf reads the bind pose without disturbing a live sample', () {
      final pose = chainPose();
      pose.sampleClip(chainClipMoving(), 0.0);

      // The live sample moved node 1 to (9, 9, 9); its rest transform is
      // still (0, 1, 0), and reading one must not perturb the other.
      final rest = pose.restOf(1);
      expect(rest.getTranslation().x, closeTo(0.0, 1e-9));
      expect(rest.getTranslation().y, closeTo(1.0, 1e-9));
      expect(rest.getTranslation().z, closeTo(0.0, 1e-9));
      // Mutation: have `restOf` read `translations`/`rotations`/`scales`
      // instead of the `_rest*` arrays — this would then read (9, 9, 9).
      expect(pose.translations[3], closeTo(9.0, 1e-9));
    });

    test('a parent index that points forward is handled the same as one '
        'that points back', () {
      // The tip (index 0) is parented to a node that comes after it in the
      // array (index 1) — legal for a `parents` array even though no
      // ordinary glTF `nodes` list would produce it this way, and exactly
      // what `worldMatrices`'s own memoized walk exists to handle.
      final pose = Pose(
        parents: <int>[1, -1],
        restTranslations: Float32List.fromList(<double>[0, 1, 0, 0, 2, 0]),
        restRotations: Float32List.fromList(<double>[
          0, 0, 0, 1, //
          0, 0, 0, 1, //
        ]),
        restScales: Float32List.fromList(<double>[1, 1, 1, 1, 1, 1]),
      );
      final world = pose.worldMatrices();
      // Mutation: skip the parent-first recursion and read `localMatrix`
      // straight into `result` — node 0 would then read y=1 instead of 3.
      expect(world[0].getTranslation().y, closeTo(3.0, 1e-9));
      expect(world[1].getTranslation().y, closeTo(2.0, 1e-9));
    });

    test('a cyclic parents array terminates instead of recursing forever', () {
      final pose = Pose(
        parents: <int>[1, 0],
        restTranslations: Float32List.fromList(<double>[1, 0, 0, 0, 1, 0]),
        restRotations: Float32List.fromList(<double>[
          0, 0, 0, 1, //
          0, 0, 0, 1, //
        ]),
        restScales: Float32List.fromList(<double>[1, 1, 1, 1, 1, 1]),
      );
      // The point of this test is that it returns at all; a naive recursive
      // walk with no cycle guard would blow the stack instead.
      final world = pose.worldMatrices();
      expect(world, hasLength(2));
    });

    test('sampleClip resets a node a track does not touch back to rest, '
        'not to wherever it was left', () {
      final pose = chainPose();
      final rotatingRoot = AnimationClip(
        tracks: <AnimationTrack>[
          AnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.translation,
            interpolation: AnimationInterpolation.step,
            times: Float32List.fromList(<double>[0.0]),
            values: Float32List.fromList(<double>[5.0, 0.0, 0.0]),
            componentCount: 3,
          ),
        ],
      );
      pose.sampleClip(rotatingRoot, 0.0);
      expect(pose.translations[0], closeTo(5.0, 1e-9));
      // Node 1 and 2 carry no track in this clip, so they stay at rest —
      // (0, 1, 0) each — not at whatever a previous sample left them at.
      pose.sampleClip(chainClipMoving(), 0.0);
      pose.sampleClip(rotatingRoot, 0.0);
      expect(pose.translations[3], closeTo(0.0, 1e-9));
      expect(pose.translations[4], closeTo(1.0, 1e-9));
    });

    test('jointMatrices pads past the joint count with identity, like '
        'Skeleton.matrices does', () {
      final pose = chainPose();
      final joints = pose.jointMatrices(
        joints: <int>[0],
        inverseBindMatrices: <Matrix4>[Matrix4.identity()],
        meshWorld: Matrix4.identity(),
      );
      final identity = Matrix4.identity().storage;
      for (var e = 0; e < 16; e++) {
        expect(
          joints[16 + e],
          closeTo(identity[e], 1e-9),
          reason: 'element $e',
        );
      }
    });

    test('jointMatrices refuses mismatched joint and matrix counts', () {
      final pose = chainPose();
      expect(
        () => pose.jointMatrices(
          joints: <int>[0, 1],
          inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          meshWorld: Matrix4.identity(),
        ),
        throwsArgumentError,
      );
    });

    test('jointMatrices refuses more joints than it was asked to hold', () {
      final pose = chainPose();
      expect(
        () => pose.jointMatrices(
          joints: <int>[0, 1, 2],
          inverseBindMatrices: <Matrix4>[
            Matrix4.identity(),
            Matrix4.identity(),
            Matrix4.identity(),
          ],
          meshWorld: Matrix4.identity(),
          maxJoints: 2,
        ),
        throwsArgumentError,
      );
    });
  });
}

/// A clip that would move the chain's mid/tip if sampled, used only to prove
/// a later sample of a clip that does *not* touch them puts them back.
AnimationClip chainClipMoving() => AnimationClip(
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: 1,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.step,
      times: Float32List.fromList(<double>[0.0]),
      values: Float32List.fromList(<double>[9.0, 9.0, 9.0]),
      componentCount: 3,
    ),
  ],
);
