/// `fmt-10`'s own acceptance line: an original `ModelDocument`, rendered,
/// against the same document written out through `GltfWriter` and read back
/// in, rendered again — compared pixel for pixel at zero tolerance.
///
///     flutter test test/differential_frame_test.dart
///
/// **Deliberately not one of `kGoldenScenes`.** A golden asks whether a
/// picture still looks like a saved reference; this asks whether two renders
/// of the same model agree with each other, which needs no reference image at
/// all — only that a round trip through the writer and the loader left the
/// picture exactly where it found it. `gltf_writer_test.dart`'s own "8 models
/// round-trip through writeGlb with nothing lost" already proves the
/// *document* survives byte-for-byte, at its default zero tolerance; this is
/// the same claim asked of the thing the document is actually for.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

/// The same eight models `gltf_writer_test.dart` round-trips, so a document
/// already known to survive the writer byte-for-byte is what gets rendered
/// here.
final Map<String, Future<ModelDocument> Function()> _kModels =
    <String, Future<ModelDocument> Function()>{
      'Box.glb': () => GltfLoader().load(_sample('Box.glb')),
      'BoxTextured.glb': () => GltfLoader().load(_sample('BoxTextured.glb')),
      'BoxVertexColors.glb': () =>
          GltfLoader().load(_sample('BoxVertexColors.glb')),
      'NormalTangentTest.glb': () =>
          GltfLoader().load(_sample('NormalTangentTest.glb')),
      'NormalTangentMirrorTest.glb': () =>
          GltfLoader().load(_sample('NormalTangentMirrorTest.glb')),
      'Triangle.gltf': () => GltfLoader().load(_sample('Triangle.gltf')),
      'cube/Cube.gltf': () => GltfLoader().load(
        _sample('cube/Cube.gltf'),
        resolveUri: (request) async => _sample('cube/${request.uri}'),
      ),
      'teapot.obj': () => ObjLoader().load(_sample('teapot.obj')),
    };

/// Renders [document] on a fresh software device: instantiated as a scene,
/// framed to its own bounds by [OrbitController.frameBounds], and lit by one
/// directional light so a wrong normal changes the picture rather than only
/// the flat colour an unlit material would give it.
///
/// Builds the device, renderer and read-back by hand rather than through
/// `renderFrame` — that helper's `build` callback is synchronous, and
/// uploading a [ModelDocument] through [ModelAsset.fromDocument] is not, since
/// decoding its images is. The two renders in each test below need meshes and
/// textures on the *same* device they are read back from, which rules out
/// building the asset on a throwaway device first.
Future<RenderedFrame> _renderDocument(ModelDocument document) async {
  const width = 160;
  const height = 120;
  final kit = cpuTestDevice(width: width, height: height);
  final asset = await ModelAsset.fromDocument(document, device: kit.device);
  final scene = Scene();
  asset.instantiate(scene);

  final bounds = scene.computeBounds();
  final centre = (bounds.min + bounds.max)..scale(0.5);
  final radius = math.max(((bounds.max - bounds.min)..scale(0.5)).length, 1e-3);

  scene.add(
    LightNode(intensity: 3.0)
      ..setPosition(
        centre.x - radius * 1.4,
        centre.y + radius * 2.0,
        centre.z - radius * 1.1,
      )
      ..lookAt(centre),
  );

  final camera = scene.add(
    CameraNode(projection: const PerspectiveProjection(fovYRadians: 0.8)),
  );
  final orbit = OrbitController(camera, yaw: 0.7, pitch: 0.35)
    ..frameBounds(bounds);
  orbit.syncProjectionDepth(camera);

  final renderer = Renderer.create(
    device: kit.device,
    fallbackAlbedo: kit.albedo,
    fallbackNormal: kit.normal,
  );
  final result = renderer.render(
    width: width,
    height: height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.05, 0.05, 0.08, 1.0)),
    ],
    settings: const RenderSettings(
      shadows: ShadowSettings(enabled: false),
      bloom: BloomSettings(enabled: false),
    ),
  );
  final pixels = await kit.device.readPixels(result.frame);
  return (
    pixels: pixels!.buffer.asUint8List(),
    width: width,
    height: height,
    drawCalls: result.drawCalls,
  );
}

void main() {
  group('a model rendered, written through GltfWriter and read back, renders '
      'the same picture', () {
    for (final entry in _kModels.entries) {
      test(entry.key, () async {
        final source = await entry.value();
        final rewritten = await GltfLoader().load(
          GltfWriter(source).writeGlb(),
        );

        final before = await _renderDocument(source);
        final after = await _renderDocument(rewritten);

        final difference = compareFrames(
          before.pixels,
          after.pixels,
          channel: 0,
        );
        expect(difference.differing, 0, reason: difference.toString());
      });
    }
  });
}
