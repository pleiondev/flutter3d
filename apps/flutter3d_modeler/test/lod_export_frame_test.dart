/// The levels a project exports, drawn by the game's renderer with a shadow.
///
///     flutter test test/lod_export_frame_test.dart
///
/// **The file went out and nothing had ever drawn it.** A level is a simplified
/// copy of the object, and the simplifier answers in the attributes it reads:
/// eight floats a vertex, with no tangent. The renderer's vertex stage reads
/// every mesh through one layout, so a level as it came read past the end of
/// its own vertices the first time a pass asked for a tangent, and the
/// software backend stopped with a `RangeError`. The document a project turns
/// into is checked for its layout in `flutter3d_model_core`; this is the same
/// document, loaded as a game loads it and drawn at each distance.
@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const int _size = 96;

ModelProject _project() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'ball',
    geometry: EditedGeometry(
      const ParametricSphere(segments: 24, rings: 12).toEditMesh(),
    ),
    transform: vm.Matrix4.identity(),
    lods: const <LodSpec>[
      LodSpec(ratio: 0.5, maxScreenFraction: 0.4),
      LodSpec(ratio: 0.2, maxScreenFraction: 0.1),
    ],
  ),
);

/// One frame of [asset] from [away] metres, and how many pixels it lit.
Future<int> _litPixels(
  ModelDocument document,
  CpuDevice device,
  double away,
) async {
  final asset = await ModelAsset.fromDocument(document, device: device);
  final renderer = Renderer.create(
    device: device,
    fallbackNormal: device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[128, 128, 255, 255]),
      ),
    )!,
  );
  final scene = Scene();
  asset.instantiate(scene, name: 'ball');
  scene.add(
    LightNode(type: LightType.directional, intensity: 2.0, castsShadow: true)
      ..setLocalForward(vm.Vector3(-0.3, -0.9, 0.2)),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, -away)
    ..lookAt(vm.Vector3.zero());
  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = (await device.readPixels(frame.frame))!.buffer.asUint8List();
  var lit = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] + pixels[i + 1] + pixels[i + 2] > 30) lit++;
  }
  return lit;
}

void main() {
  test('an object with levels of detail draws at every distance', () async {
    // Mutation: export a level as the simplifier answers it (eight floats a
    // vertex). The first draw of that level throws a `RangeError` from the
    // vertex stage, so this fails at whichever distance selects it.
    final document = toModelDocument(_project(), withLods: true);
    expect(document.nodes.single.lods, hasLength(2));

    for (final away in <double>[2.5, 12.0, 60.0]) {
      final device = CpuDevice(
        width: _size,
        height: _size,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      expect(
        await _litPixels(document, device, away),
        greaterThan(0),
        reason: 'drawn from $away m away',
      );
    }
  });
}
