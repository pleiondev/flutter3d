/// `GltfWriter`'s skins/animations/morph-target half — `fmt-07` — checked
/// against seven rigged or morphing sample models.
///
/// `compareModelDocuments` only counts skins and animations and compares
/// geometry byte for byte; it says nothing about a track's own keyframes or a
/// skin's own joints, so this file checks those directly rather than
/// widening a shared comparator every other writer's test also relies on.
///
///     dart test test/gltf_writer_animation_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

void main() {
  group('7 rigged or morphing models keep their skins and clips', () {
    final cases = <String, Future<ModelDocument> Function()>{
      'RiggedSimple.glb': () => GltfLoader().load(_sample('RiggedSimple.glb')),
      'RiggedFigure.glb': () => GltfLoader().load(_sample('RiggedFigure.glb')),
      'BoxAnimated.glb': () => GltfLoader().load(_sample('BoxAnimated.glb')),
      'AnimatedMorphCube.glb': () =>
          GltfLoader().load(_sample('AnimatedMorphCube.glb')),
      'InterpolationTest.glb': () =>
          GltfLoader().load(_sample('InterpolationTest.glb')),
      'RobotExpressive.glb (skinned and morphing at once)': () =>
          GltfLoader().load(_sample('RobotExpressive.glb')),
      'simple_skin/SimpleSkin.gltf': () =>
          GltfLoader().load(_sample('simple_skin/SimpleSkin.gltf')),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final source = await entry.value();
        final bytes = GltfWriter(source).writeGlb();
        final readBack = await GltfLoader().load(bytes);

        final problems = compareModelDocuments(source, readBack);
        expect(problems, isEmpty, reason: problems.join('\n'));

        expect(readBack.skins.length, source.skins.length, reason: 'skins');
        for (var s = 0; s < source.skins.length; s++) {
          final a = source.skins[s];
          final b = readBack.skins[s];
          expect(b.joints, a.joints, reason: 'skins[$s].joints');
          expect(
            b.inverseBindMatrices.map((m) => m.storage.toList()).toList(),
            a.inverseBindMatrices.map((m) => m.storage.toList()).toList(),
            reason: 'skins[$s].inverseBindMatrices',
          );
          expect(
            b.skeletonRoot,
            a.skeletonRoot,
            reason: 'skins[$s].skeletonRoot',
          );
        }

        expect(
          readBack.animations.length,
          source.animations.length,
          reason: 'animations',
        );
        for (var c = 0; c < source.animations.length; c++) {
          final a = source.animations[c];
          final b = readBack.animations[c];
          expect(b.tracks.length, a.tracks.length, reason: 'clip[$c].tracks');
          for (var t = 0; t < a.tracks.length; t++) {
            final trackA = a.tracks[t];
            final trackB = b.tracks[t];
            expect(trackB.nodeIndex, trackA.nodeIndex, reason: 'track[$t]');
            expect(trackB.path, trackA.path, reason: 'track[$t].path');
            expect(
              trackB.interpolation,
              trackA.interpolation,
              reason: 'track[$t].interpolation',
            );
            expect(
              trackB.times.toList(),
              trackA.times.toList(),
              reason: 'track[$t].times',
            );
            expect(
              trackB.values.toList(),
              trackA.values.toList(),
              reason: 'track[$t].values',
            );
          }
        }
      });
    }

    test(
      'animated_cube/AnimatedCube.gltf (external buffer and image)',
      () async {
        Future<Uint8List> resolve(AssetRequest request) async =>
            _sample('animated_cube/${request.uri}');
        final source = await GltfLoader().load(
          _sample('animated_cube/AnimatedCube.gltf'),
          resolveUri: resolve,
        );
        final bytes = GltfWriter(source).writeGlb();
        final readBack = await GltfLoader().load(bytes);
        final problems = compareModelDocuments(source, readBack);
        expect(problems, isEmpty, reason: problems.join('\n'));
        expect(readBack.animations.length, source.animations.length);
      },
    );
  });

  group('morph targets', () {
    test('positions, and names where the file has them', () async {
      final source = await GltfLoader().load(_sample('AnimatedMorphCube.glb'));
      final bytes = GltfWriter(source).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      final a = source.surfaces.single.mesh.morphTargets;
      final b = readBack.surfaces.single.mesh.morphTargets;
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i].positions.toList(), a[i].positions.toList());
        expect(b[i].name, a[i].name);
      }
    });
  });
}
