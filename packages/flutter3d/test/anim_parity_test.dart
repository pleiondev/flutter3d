/// `anim-28`'s own row: `Pose.sampleClip`, `AnimationPlayer.seek` and
/// `BakedPoses.of` agree on one clip's joint matrices within 1e-5, and a
/// changed tangent moves all three the same way — the row's own literal
/// "мутация тангенсов ловится всеми" (a tangent mutation is caught by all).
///
/// All three ultimately sample through `AnimationTrack.sample`, so what
/// this actually guards against is divergence in the *surrounding*
/// plumbing each path adds on top of that shared call — `Pose`'s own world-
/// matrix composition, `AnimationPlayer` writing through `SceneNode`, and
/// `BakedPoses` folding the result into a texture-ready table — not a
/// second, independent reimplementation of interpolation math.
///
///     dart test test/anim_parity_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

const String kSamples = kSamplesPath;

Uint8List readSample(String name) => File('$kSamples/$name').readAsBytesSync();

/// A live `SceneNode` mirror of [nodes]/[roots] — the same walk
/// `ModelAsset.instantiate` does, minus meshes and materials, matching
/// `pose_test.dart`'s own helper of the same shape.
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

/// A single-track, cubic-spline clip translating node [nodeIndex] along X,
/// with [outTangent] as its first key's own outgoing slope — the value the
/// "tangent mutation" half of this row's acceptance moves between two runs.
AnimationClip _cubicClip(int nodeIndex, {required double outTangent}) =>
    AnimationClip(
      tracks: <AnimationTrack>[
        AnimationTrack(
          nodeIndex: nodeIndex,
          path: AnimationPath.translation,
          interpolation: AnimationInterpolation.cubicSpline,
          times: Float32List.fromList(<double>[0.0, 1.0]),
          // Cubic-spline storage: in-tangent, value, out-tangent, per key.
          values: Float32List.fromList(<double>[
            0.0, 0.0, 0.0, // key 0 in-tangent
            0.0, 0.0, 0.0, // key 0 value
            outTangent, 0.0, 0.0, // key 0 out-tangent
            0.0, 0.0, 0.0, // key 1 in-tangent
            1.0, 0.0, 0.0, // key 1 value
            0.0, 0.0, 0.0, // key 1 out-tangent
          ]),
          componentCount: 3,
        ),
      ],
    );

/// One joint's matrix through all three paths, at the frame boundary
/// `duration * frame / framesPerClip` — the exact time [BakedPoses] itself
/// samples at, so the three are compared at a point none of them has to
/// interpolate to reach.
Map<String, Matrix4> _matricesAt({
  required ModelDocument document,
  required AnimationClip clip,
  required int frame,
  required int framesPerClip,
}) {
  final skin = document.skins.single;
  final built = _buildScene(document.nodes, document.roots);
  final player = AnimationPlayer(clips: <AnimationClip>[clip], targets: List<AnimationTarget?>.of(built.created));
  final skeleton = Skeleton(
    joints: <SceneNode>[for (final j in skin.joints) built.created[j]],
    inverseBindMatrices: skin.inverseBindMatrices,
  );
  final meshNodeIndex = document.nodes.indexWhere((n) => n.surfaces.isNotEmpty);
  final meshNode = built.created[meshNodeIndex];

  final time = clip.duration * frame / framesPerClip;

  // Path 1: Pose.sampleClip.
  final pose = Pose.fromNodes(document.nodes);
  pose.sampleClip(clip, time);
  final poseJoints = pose.jointMatrices(
    joints: skin.joints,
    inverseBindMatrices: skin.inverseBindMatrices,
    meshWorld: pose.worldMatrices()[meshNodeIndex],
  );
  // `Float32List.fromList`, not `sublistView`: a view shares the backing
  // buffer, and `skeleton.matrices` below is a long-lived array `update()`
  // mutates in place — including from inside `BakedPoses.of`'s own baking
  // loop, several calls after this one. A view taken here would silently
  // read back whatever frame that loop left the buffer holding, which is
  // exactly the trap this copy exists to avoid.
  final poseMatrix = Matrix4.fromFloat32List(
    Float32List.fromList(poseJoints.sublist(0, 16)),
  );

  // Path 2: AnimationPlayer.seek + Skeleton.update.
  player.play(0);
  player.seek(time);
  skeleton.update(meshNode.worldMatrix);
  final playerMatrix = Matrix4.fromFloat32List(
    Float32List.fromList(skeleton.matrices.sublist(0, 16)),
  );

  // Path 3: BakedPoses.of, read back at the same frame. Baking moves the
  // playhead and mutates `skeleton.matrices` itself several times over —
  // both already-captured matrices above are plain copies, so neither is
  // disturbed by it.
  final baked = BakedPoses.of(
    player,
    skeleton: skeleton,
    meshWorld: meshNode.worldMatrix,
    framesPerClip: framesPerClip,
  );
  final bakedMatrix = baked.matrixAt(0, frame, 0);

  return <String, Matrix4>{
    'Pose.sampleClip': poseMatrix,
    'AnimationPlayer.seek': playerMatrix,
    'BakedPoses.of': bakedMatrix,
  };
}

void _expectAllAgree(Map<String, Matrix4> matrices, {String? reason}) {
  final entries = matrices.entries.toList();
  final first = entries.first.value;
  for (final entry in entries.skip(1)) {
    for (var e = 0; e < 16; e++) {
      expect(
        entry.value.storage[e],
        closeTo(first.storage[e], 1e-5),
        reason: '${reason ?? ''}: ${entries.first.key} vs ${entry.key}, element $e',
      );
    }
  }
}

void main() {
  test(
    'Pose.sampleClip, AnimationPlayer.seek and BakedPoses.of agree on a '
    'cubic-spline clip within 1e-5, and a changed tangent moves all three',
    () async {
      final document = await GltfLoader().load(readSample('RiggedSimple.glb'));
      expect(document.skins, hasLength(1));
      final jointNode = document.skins.single.joints.first;

      const framesPerClip = 8;
      const frame = 3;

      final original = _cubicClip(jointNode, outTangent: 2.0);
      final originalMatrices = _matricesAt(
        document: document,
        clip: original,
        frame: frame,
        framesPerClip: framesPerClip,
      );
      // Mutation: read the tangent triple's slots in the wrong order inside
      // whichever path got it wrong — this is what the three-way agreement
      // check exists to catch, on real cubic data rather than a fixture
      // built to avoid the case.
      _expectAllAgree(originalMatrices, reason: 'original clip');

      final mutated = _cubicClip(jointNode, outTangent: -6.0);
      final mutatedMatrices = _matricesAt(
        document: document,
        clip: mutated,
        frame: frame,
        framesPerClip: framesPerClip,
      );
      _expectAllAgree(mutatedMatrices, reason: 'mutated clip');

      // The row's own "тангенсов ловится всеми": every path's own answer
      // has to actually move in response to the tangent change, not just
      // agree with the other two while all three silently ignored it.
      for (final key in originalMatrices.keys) {
        final before = originalMatrices[key]!;
        final after = mutatedMatrices[key]!;
        final moved = (before.getTranslation() - after.getTranslation()).length;
        expect(moved, greaterThan(1e-3), reason: '$key did not react to the tangent change');
      }
    },
  );
}
