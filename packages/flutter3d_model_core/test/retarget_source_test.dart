/// `anim-18`'s own `RetargetSource.fromDocument` — a file read for
/// [retargetClip] alone, never merged into the project being edited.
///
///     dart test test/retarget_source_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final class _Doc extends ModelDocument {
  _Doc({
    required this.nodes,
    required this.roots,
    this.skins = const <ModelSkin>[],
    this.animations = const <AnimationClip>[],
  });

  @override
  List<ModelSurface> get surfaces => const <ModelSurface>[];
  @override
  final List<ModelNode> nodes;
  @override
  final List<int> roots;
  @override
  final List<SurfaceMaterial> materials = const <SurfaceMaterial>[];
  @override
  final List<EncodedImage> images = const <EncodedImage>[];
  @override
  final List<String> warnings = const <String>[];
  @override
  final List<ModelSkin> skins;
  @override
  final List<AnimationClip> animations;
}

ModelNode _joint(String name, {List<int> children = const <int>[]}) =>
    ModelNode(
      name: name,
      translation: Vector3.zero(),
      rotation: Quaternion.identity(),
      scale: Vector3(1, 1, 1),
      children: children,
    );

AnimationTrack _rotationTrack(int nodeIndex) => AnimationTrack(
  nodeIndex: nodeIndex,
  path: AnimationPath.rotation,
  interpolation: AnimationInterpolation.linear,
  times: Float32List.fromList(<double>[0.0]),
  values: Float32List.fromList(<double>[0.0, 0.0, 0.0, 1.0]),
  componentCount: 4,
);

void main() {
  group('RetargetSource.fromDocument', () {
    test('a file with a real skin comes back with it, and no warning', () {
      final doc = _Doc(
        nodes: <ModelNode>[
          _joint('root', children: <int>[1]),
          _joint('tip'),
        ],
        roots: <int>[0],
        skins: <ModelSkin>[
          ModelSkin(
            name: 'rig',
            joints: <int>[0, 1],
            inverseBindMatrices: <Matrix4>[
              Matrix4.identity(),
              Matrix4.identity(),
            ],
            skeletonRoot: 0,
          ),
        ],
        animations: <AnimationClip>[
          AnimationClip(
            name: 'take',
            tracks: <AnimationTrack>[_rotationTrack(1)],
          ),
        ],
      );

      final source = RetargetSource.fromDocument('mocap.fbx', doc);

      expect(source.name, 'mocap.fbx');
      expect(source.warning, isNull);
      expect(source.skeletonIndex, 0);
      expect(source.skeleton.joints.length, 2);
      expect(source.clips.length, 1);
      expect(source.clips.single.tracks, hasLength(1));
    });

    test('a file with no skin synthesises one from its animated nodes, and '
        'warns', () {
      final doc = _Doc(
        nodes: <ModelNode>[
          _joint('hips', children: <int>[1, 2]),
          _joint('spine'),
          _joint('prop'), // Not driven by any clip — not a joint either.
        ],
        roots: <int>[0],
        animations: <AnimationClip>[
          AnimationClip(
            name: 'take',
            tracks: <AnimationTrack>[_rotationTrack(0), _rotationTrack(1)],
          ),
        ],
      );

      final source = RetargetSource.fromDocument('mocap.bvh', doc);

      expect(
        source.warning,
        'Imported without a skin — mapped by node names only.',
      );
      expect(source.project.skeletons, hasLength(1));
      expect(source.skeleton.joints, hasLength(2));
      expect(source.skeleton.inverseBindMatrices, hasLength(2));

      final joints = <String>[
        for (final id in source.skeleton.joints) source.project[id]!.name,
      ];
      expect(joints, containsAll(<String>['hips', 'spine']));
      expect(joints, isNot(contains('prop')));
    });

    test('a file with no skin and no animation at all synthesises an empty '
        'skeleton rather than throwing', () {
      final doc = _Doc(nodes: <ModelNode>[_joint('lone')], roots: <int>[0]);

      final source = RetargetSource.fromDocument('static.obj', doc);

      expect(source.warning, isNotNull);
      expect(source.skeleton.joints, isEmpty);
      expect(source.skeleton.inverseBindMatrices, isEmpty);
    });
  });
}
