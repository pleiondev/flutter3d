/// A masked material's edge as multisample coverage — `P7`,
/// `Material.alphaToCoverage`.
///
///     flutter test test/alpha_to_coverage_test.dart
///
/// Two backends of four can, so these claims are about what the engine asks
/// of a device and what it tells the caller: the coverage switched on for the
/// material that wants it and off again before anything else, the cutoff
/// handed to the shader as the coverage encoding only when the call was made,
/// and a refusal said out loud where the device cannot.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_core/src/engine/geometry/device_mesh.dart';
import 'package:flutter3d_core/src/engine/render/material.dart';
import 'package:flutter3d_core/src/engine/render/render_view.dart';
import 'package:flutter3d_core/src/engine/render/renderer.dart';
import 'package:flutter3d_core/src/engine/scene/camera_node.dart';
import 'package:flutter3d_core/src/engine/scene/mesh_node.dart';
import 'package:flutter3d_core/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A frame of one cube of [material] on a device that [supported] says can
/// or cannot, and what came of it.
({FrameResult result, FakePass scenePass}) _frame(
  Material material, {
  bool supported = true,
}) {
  final device = FakeBackend(supportsAlphaToCoverage: supported);
  final texel = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(4),
  )!;
  final renderer = Renderer.create(
    device: device,
    fallbackAlbedo: texel,
    fallbackNormal: texel,
  );
  final scene = Scene(name: 'coverage');
  final camera = CameraNode(name: 'eye')..setPosition(0.0, 0.0, 4.0);
  scene.root
    ..add(camera)
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
        material,
        name: 'leaf',
      ),
    );
  final result = renderer.render(
    width: 64,
    height: 48,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  // The pass that drew the leaf: the one that bound its material's block.
  final scenePass = device.passes.firstWhere(
    (FakePass pass) => pass.recordedOf<RecordedUniformBlock>().any(
      (RecordedUniformBlock b) => b.block == 'FragInfo',
    ),
  );
  return (result: result, scenePass: scenePass);
}

Material _leaf({bool coverage = true}) => Material(
  name: 'leaf',
  alphaMode: MaterialAlphaMode.mask,
  alphaCutoff: 0.4,
  alphaToCoverage: coverage,
);

/// The calls the pass made to `setAlphaToCoverage`, in order.
List<bool> _coverageCalls(FakePass pass) => <bool>[
  for (final call in pass.recordedOf<RecordedAlphaToCoverage>()) call.enabled,
];

/// `FragInfo.material2.x` as the leaf's draw bound it.
double _cutoffBound(FakePass pass) => pass
    .recordedOf<RecordedUniformBlock>()
    .lastWhere((RecordedUniformBlock b) => b.block == 'FragInfo')
    .members['material2']![0];

void main() {
  test('a leaf that asks gets coverage, and the pass turns it off after', () {
    // Mutation: drop the reset before the contributors in
    // `renderer_scene_pass.dart`, and the pass ends with coverage on for
    // whatever the particles draw next.
    final frame = _frame(_leaf());
    expect(_coverageCalls(frame.scenePass), <bool>[true, false]);
    expect(frame.result.alphaToCoverageDeclined, isFalse);
  });

  test('the shader is told to keep the fragment only when coverage is on', () {
    // Mutation: write `1 + cutoff` whatever the device answered, and the
    // shader keeps every fragment on a device that cannot spread them, which
    // draws the leaf's whole card.
    expect(_cutoffBound(_frame(_leaf()).scenePass), closeTo(1.4, 1e-6));
    expect(
      _cutoffBound(_frame(_leaf(), supported: false).scenePass),
      closeTo(0.4, 1e-6),
    );
  });

  test('a device that cannot says so, and draws the hard cutoff', () {
    // Mutation: drop the `coverageDeclined` line in the mesh encoder, and a
    // leaf drawn as a cut-out on Impeller looks like a success.
    final frame = _frame(_leaf(), supported: false);
    expect(_coverageCalls(frame.scenePass), isEmpty);
    expect(frame.result.alphaToCoverageDeclined, isTrue);
  });

  test('a scene that does not ask emits nothing, and refuses nothing', () {
    // Unset means no call at all, as the depth test's tracker promises: a
    // backend that never hears of coverage is drawn as it always was.
    final frame = _frame(_leaf(coverage: false));
    expect(_coverageCalls(frame.scenePass), isEmpty);
    expect(frame.result.alphaToCoverageDeclined, isFalse);
    expect(_cutoffBound(frame.scenePass), closeTo(0.4, 1e-6));
  });
}
