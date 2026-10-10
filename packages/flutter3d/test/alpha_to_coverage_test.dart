/// A masked material's edge as multisample coverage — `P7`,
/// `RenderMaterial.alphaToCoverage`.
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
  RenderMaterial material, {
  bool supported = true,
  bool minMax = true,
}) {
  final device = FakeBackend(
    supportsAlphaToCoverage: supported,
    extraFeatures: <DeviceFeature>[if (minMax) DeviceFeature.minMaxBlend],
  );
  final texel = device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData(4),
  );
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

RenderMaterial _leaf({bool coverage = true}) => RenderMaterial(
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

/// The blend on attachment zero when the leaf was drawn: the last one set
/// before the draw that follows the leaf's `FragInfo`.
BlendState? _leafBlend(FakePass pass) {
  final commands = pass.commands;
  final block = commands.lastIndexWhere(
    (Recorded c) => c is RecordedUniformBlock && c.block == 'FragInfo',
  );
  final draw = commands.indexWhere((Recorded c) => c is RecordedDraw, block);
  return commands
      .sublist(0, draw)
      .whereType<RecordedBlend>()
      .lastWhere((RecordedBlend b) => b.attachment == 0)
      .state;
}

/// [state]'s alpha for a fragment alpha [source] over [destination], by the
/// rule every backend blends with: the two factors, then the operation, and
/// `min`/`max` on the values themselves.
double _blendAlpha(BlendState state, double source, double destination) =>
    _apply(
      state.alphaOperation,
      source * _factor(state.sourceAlphaFactor, source),
      destination * _factor(state.destinationAlphaFactor, source),
      source,
      destination,
    );

/// [state]'s colour channel for [source] over [destination], the fragment's
/// alpha being [alpha].
double _blendColor(
  BlendState state,
  double source,
  double destination,
  double alpha,
) => _apply(
  state.colorOperation,
  source * _factor(state.sourceColorFactor, alpha),
  destination * _factor(state.destinationColorFactor, alpha),
  source,
  destination,
);

double _factor(BlendFactor factor, double sourceAlpha) => switch (factor) {
  BlendFactor.zero => 0.0,
  BlendFactor.one => 1.0,
  BlendFactor.sourceAlpha => sourceAlpha,
  BlendFactor.oneMinusSourceAlpha => 1.0 - sourceAlpha,
  _ => throw UnimplementedError('$factor'),
};

double _apply(
  BlendOperation operation,
  double s,
  double d,
  double rawS,
  double rawD,
) => switch (operation) {
  BlendOperation.add => s + d,
  BlendOperation.subtract => s - d,
  BlendOperation.reverseSubtract => d - s,
  BlendOperation.min => rawS < rawD ? rawS : rawD,
  BlendOperation.max => rawS > rawD ? rawS : rawD,
};

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

  test('a coverage edge leaves the frame opaque over an opaque frame', () {
    // The leaf's fragment alpha is what coverage is made of, and both
    // browser APIs write it into the samples it covers. Mutation: drop
    // `_coverageEdgeBlend` from the lit draw, and the leaf's draw binds no
    // blend — every covered sample takes the fragment's alpha, the resolve
    // averages it with the clear's ones, and the frame's rim is translucent.
    final blend = _leafBlend(_frame(_leaf()).scenePass);
    expect(blend, isNotNull, reason: 'the coverage draw keeps the alpha');
    // Over the opaque clear every frame starts from, whatever alpha the
    // fragment wrote — nought at the very rim, one inside — a covered sample
    // comes out at one, and so does the resolve of any mix of samples.
    for (final fragmentAlpha in <double>[0.0, 0.25, 0.5, 0.999, 1.0]) {
      expect(_blendAlpha(blend!, fragmentAlpha, 1.0), 1.0);
    }
    // The colour is the fragment's own, as an opaque draw writes it.
    expect(_blendColor(blend!, 0.3, 0.9, 0.6), closeTo(0.3, 1e-12));
  });

  test('coverage without a max on the alpha is declined, not translucent', () {
    // Mutation: drop the `minMaxBlend` condition from the scene pass, and a
    // device that cannot keep the frame opaque under coverage draws it
    // translucent instead of drawing the cutoff and saying so.
    final frame = _frame(_leaf(), minMax: false);
    expect(_coverageCalls(frame.scenePass), isEmpty);
    expect(frame.result.alphaToCoverageDeclined, isTrue);
    expect(_cutoffBound(frame.scenePass), closeTo(0.4, 1e-6));
    expect(_leafBlend(frame.scenePass), isNull);
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
