/// A file with morph targets, all the way to a node that wears an expression.
///
/// **The pieces were each tested alone and never end to end.** `MorphTexture`
/// knows how to pack deltas, `MorphState` knows how to hold weights, and
/// `AnimationPlayer` knows how to drive a sink — and none of that draws a face
/// unless the loader packs the mesh it decoded, uploads it, hands it to the
/// node it built, and wires the node into the player. Each of those four is a
/// line that can be missing without any of the unit tests noticing.
///
/// `AnimatedMorphCube.glb` is the Khronos sample for exactly this: two targets
/// and a clip that drives their weights, so the file answers both halves.
library;

import 'dart:io';

import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/assets/model_asset.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/lighting_model.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

const String kCube = '$kSamplesPath/AnimatedMorphCube.glb';

Future<({ModelDocument document, ModelAsset asset})> loadCube() async {
  final document = await GltfLoader().load(File(kCube).readAsBytesSync());
  final asset = await ModelAsset.fromDocument(
    document,
    device: FakeBackend(),
    lighting: LightingModel.unlit,
  );
  return (document: document, asset: asset);
}

void main() {
  late ModelDocument document;
  late ModelAsset asset;

  setUpAll(() async {
    final loaded = await loadCube();
    document = loaded.document;
    asset = loaded.asset;
  });

  group('a model that morphs', () {
    test('decodes its targets and moves a vertex when they are weighted', () {
      // The floor everything else stands on: if the deltas were all nought the
      // rest of this file would pass on a cube that never changes shape.
      final mesh = document.surfaces.single.mesh;
      expect(mesh.morphTargets, hasLength(2));

      final blend = MorphBlend(mesh);
      expect(blend.blend(<double>[1.0, 0.0]), isTrue);
      expect(
        blend.vertices,
        isNot(orderedEquals(mesh.vertices)),
        reason: 'the first target has to actually move something',
      );
    });

    test('uploads the deltas with the part that draws them', () {
      // Mutation: drop `morphTexture:` from the `ModelPart` the loader builds
      // and the model loads, animates, and draws its base shape forever.
      final part = asset.parts.single;
      expect(part.morphTexture, isNotNull);
      expect(part.morphTargetCount, 2);
    });

    test('hands the uploaded deltas to the node it builds', () {
      final instance = asset.instantiate(Scene());
      final morph = instance.meshes.single.morph;

      expect(morph, isNotNull);
      expect(morph!.texture, same(asset.parts.single.morphTexture));
      expect(morph.targetCount, 2);
    });

    test('starts in the expression the file asked for', () {
      // Which for this file is none, and it is worth pinning: a loader that
      // seeded the weights with anything but the file's own defaults would put
      // every model on the screen in a pose nobody authored.
      final instance = asset.instantiate(Scene());
      expect(
        instance.meshes.single.morphWeights,
        document.surfaces.single.morphWeights.isEmpty
            ? <double>[0.0, 0.0]
            : document.surfaces.single.morphWeights,
      );
    });

    test('lets two copies wear different expressions from one upload', () {
      // The reason the weights live on the node and the deltas do not.
      final scene = Scene();
      final first = asset.instantiate(scene, name: 'first');
      final second = asset.instantiate(scene, name: 'second');

      first.meshes.single.morph!.setWeights(<double>[1.0, 0.0]);

      expect(second.meshes.single.morphWeights, <double>[0.0, 0.0]);
      expect(
        second.meshes.single.morph!.texture,
        same(first.meshes.single.morph!.texture),
      );
    });

    test('is animated by the clip the file carries', () {
      // The last wire, and the one with nothing else to catch it: the player
      // is handed a sinks list index-aligned with its targets. Mutation: pass
      // `morphs: null` and this is the only test that fails.
      final instance = asset.instantiate(Scene());
      final player = instance.player;
      expect(player, isNotNull, reason: 'the sample carries a clip');

      final node = instance.meshes.single;
      player!.play(0);

      final seen = <List<double>>[];
      for (final time in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
        player.seek(time * player.clips.first.duration);
        seen.add(List<double>.of(node.morphWeights));
      }

      expect(
        seen.map((w) => '$w').toSet().length,
        greaterThan(1),
        reason: 'the clip has to move the weights, not just set them once',
      );
      expect(
        seen.any((w) => w.any((v) => v > 0.5)),
        isTrue,
        reason: 'and reach a shape worth having packed',
      );
    });
  });
}
