/// `fmt-07`'s own acceptance line: a rigged model's pose at t=0.5, sampled
/// through the real [AnimationPlayer], survives a GLB round trip through
/// `GltfWriter` — not just the byte-level checks `flutter3d_formats` already
/// holds, but the thing those bytes are actually for.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/model_asset.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String kSamples = kSamplesPath;

Uint8List readSample(String name) => File('$kSamples/$name').readAsBytesSync();

/// Instantiates [document] on a device that draws nothing, plays its first
/// clip to [time] and reads back the world pose of node [nodeIndex].
Future<({Vector3 position, Quaternion rotation})> poseAt(
  ModelDocument document,
  int nodeIndex,
  double time,
) async {
  final asset = await ModelAsset.fromDocument(
    document,
    device: FakeBackend(),
    lighting: LightingModel.unlit,
  );
  final instance = asset.instantiate(Scene());
  instance.player!.play();
  instance.player!.update(time);
  final node = instance.nodes[nodeIndex];
  return (position: node.readPosition(), rotation: node.readRotation());
}

void main() {
  test(
    'RiggedSimple.glb: a joint\'s pose at t=0.5 matches after writeGlb and decode',
    () async {
      final source = await GltfLoader().load(readSample('RiggedSimple.glb'));
      expect(source.animations, isNotEmpty);
      final track = source.animations.first.tracks.first;

      final rewritten = await GltfLoader().load(GltfWriter(source).writeGlb());

      final before = await poseAt(source, track.nodeIndex, 0.5);
      final after = await poseAt(rewritten, track.nodeIndex, 0.5);

      expect(after.position.x, closeTo(before.position.x, 1e-5));
      expect(after.position.y, closeTo(before.position.y, 1e-5));
      expect(after.position.z, closeTo(before.position.z, 1e-5));
      expect(after.rotation.x, closeTo(before.rotation.x, 1e-5));
      expect(after.rotation.y, closeTo(before.rotation.y, 1e-5));
      expect(after.rotation.z, closeTo(before.rotation.z, 1e-5));
      expect(after.rotation.w, closeTo(before.rotation.w, 1e-5));
    },
  );

  test('BoxAnimated.glb: the same check on a second rig, so this is not one '
      'model\'s coincidence', () async {
    final source = await GltfLoader().load(readSample('BoxAnimated.glb'));
    final track = source.animations.first.tracks.first;

    final rewritten = await GltfLoader().load(GltfWriter(source).writeGlb());

    final before = await poseAt(source, track.nodeIndex, 0.5);
    final after = await poseAt(rewritten, track.nodeIndex, 0.5);

    expect(after.position.x, closeTo(before.position.x, 1e-5));
    expect(after.position.y, closeTo(before.position.y, 1e-5));
    expect(after.position.z, closeTo(before.position.z, 1e-5));
    expect(after.rotation.w, closeTo(before.rotation.w, 1e-5));
  });
}
