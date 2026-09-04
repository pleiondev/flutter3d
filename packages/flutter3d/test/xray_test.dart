/// What the x-ray stage asks of a pass, and — as important — when it asks
/// nothing.
///
/// Recorded through the fake device rather than drawn, because what is being
/// pinned here is a sequence: every mark before any silhouette, the marking
/// draw blended to leave the picture alone, the silhouette behind the depth
/// test rather than in front of it, and the stencil switched off again
/// before anything else draws. The picture is `stencil-xray` in the three
/// golden sets; the order is this file.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/device_mesh.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The layer the marked nodes live on, beside the default one.
const int _marked = 1 << 3;

final class _Frame {
  _Frame({
    required this.device,
    required this.renderer,
    required this.scene,
    required this.camera,
  });

  factory _Frame.build({
    bool supportsStencil = true,
    int markedNodes = 1,
    int plainNodes = 1,
  }) {
    final device = FakeBackend(supportsStencil: supportsStencil);
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
    final scene = Scene(name: 'x-ray');
    final camera = CameraNode(name: 'eye')..setPosition(0.0, 0.0, 4.0);
    scene.root.add(camera);
    final cube = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(1.0)).build(),
    );
    for (var i = 0; i < plainNodes; i++) {
      scene.root.add(
        MeshNode(cube, Material(name: 'wall $i'), name: 'wall $i')
          ..setPosition(i * 0.1, 0.0, 0.0),
      );
    }
    for (var i = 0; i < markedNodes; i++) {
      scene.root.add(
        MeshNode(cube, Material(name: 'monster $i'), name: 'monster $i')
          ..layerMask = 1 | _marked
          ..setPosition(i * 0.1, 0.0, -1.0),
      );
    }
    return _Frame(
      device: device,
      renderer: renderer,
      scene: scene,
      camera: camera,
    );
  }

  final FakeBackend device;
  final Renderer renderer;
  final Scene scene;
  final CameraNode camera;

  /// The scene pass of one frame drawn with [xray].
  FakePass render(XraySettings xray) {
    renderer.render(
      width: 64,
      height: 48,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: RenderSettings(
        bloom: const BloomSettings(enabled: false),
        shadows: const ShadowSettings(enabled: false),
        xray: xray,
      ),
    );
    return device.passes.first;
  }
}

/// The state calls and draws of a pass, as short strings in order.
List<String> _sequence(FakePass pass) => <String>[
  for (final command in pass.commands)
    switch (command) {
      RecordedDraw() => 'draw',
      RecordedBlend(:final state) =>
        state == null
            ? 'blend off'
            : state == BlendState.keepDestination
            ? 'blend keepDestination'
            : 'blend on',
      RecordedDepthWrite(:final enabled) => 'depthWrite $enabled',
      RecordedDepthCompare(:final compare) => 'depthCompare ${compare.name}',
      RecordedStencil(:final front) =>
        'stencil ${front.compare.name}/${front.passOp.name}',
      RecordedStencilReference(:final value) => 'stencilReference $value',
      _ => '',
    },
]..removeWhere((line) => line.isEmpty);

void main() {
  test('a scene with no x-ray layer never mentions the stencil', () {
    // The property every recorded picture rests on: unset means emit
    // nothing, and a stage that emitted even a harmless `disabled` would be
    // a call thirty-four goldens were recorded without.
    final pass = _Frame.build().render(const XraySettings());
    expect(pass.recordedOf<RecordedStencil>(), isEmpty);
    expect(pass.recordedOf<RecordedStencilReference>(), isEmpty);
    expect(pass.drawCount, 2, reason: 'a wall and a monster, once each');
  });

  test('a marked node is drawn three times: lit, marked, painted', () {
    final pass = _Frame.build().render(const XraySettings(layerMask: _marked));
    final sequence = _sequence(pass);

    expect(pass.drawCount, 4, reason: 'two lit draws, one mark, one paint');

    final fromReference = sequence.sublist(
      sequence.indexOf('stencilReference 1'),
    );
    expect(fromReference, <String>[
      'stencilReference 1',
      'stencil always/setToReferenceValue',
      'blend keepDestination',
      'depthWrite false',
      'depthCompare lessEqual',
      'draw',
      'stencil notEqual/keep',
      'blend off',
      'depthWrite false',
      'depthCompare greater',
      'draw',
      'stencil always/keep',
    ]);
    expect(
      pass.stencilFront,
      StencilState.disabled,
      reason: 'the pass is left with the test off',
    );
  });

  test('every mark is written before any silhouette is painted', () {
    // The whole reason the stencil is there: the second monster's silhouette
    // must be masked by the first monster's visible part, which only holds if
    // the first monster's mark exists when the second is painted.
    final pass = _Frame.build(
      markedNodes: 3,
    ).render(const XraySettings(layerMask: _marked));
    expect(pass.drawCount, 1 + 3 + 3 + 3);

    final stencils = pass.recordedOf<RecordedStencil>().toList();
    expect(stencils, hasLength(3), reason: 'mark, paint, off — once each');
    final sequence = _sequence(pass);
    final marks = sequence.indexOf('stencil always/setToReferenceValue');
    final paints = sequence.indexOf('stencil notEqual/keep');
    final off = sequence.lastIndexOf('stencil always/keep');
    expect(
      sequence.sublist(marks, paints).where((c) => c == 'draw'),
      hasLength(3),
      reason: 'three marks between the two stencil states',
    );
    expect(
      sequence.sublist(paints, off).where((c) => c == 'draw'),
      hasLength(3),
      reason: 'and three paints after',
    );
  });

  test('a device without a stencil draws no silhouettes and asks for none', () {
    // Asked before requested. A stencil configured against an attachment
    // with none is a test that passes always on one API and an invalid
    // descriptor on another, and a picture without silhouettes is the honest
    // answer to both.
    final pass = _Frame.build(
      supportsStencil: false,
    ).render(const XraySettings(layerMask: _marked));
    expect(pass.recordedOf<RecordedStencil>(), isEmpty);
    expect(pass.drawCount, 2);
  });

  test('a layer nothing visible is on costs nothing', () {
    final pass = _Frame.build(
      markedNodes: 0,
    ).render(const XraySettings(layerMask: _marked));
    expect(pass.recordedOf<RecordedStencil>(), isEmpty);
    expect(pass.drawCount, 1);
  });

  test('the silhouette is the colour the settings name, unlit', () {
    final frame = _Frame.build();
    final pass = frame.render(
      XraySettings(layerMask: _marked, color: Vector3(0.1, 0.9, 0.2)),
    );
    // The last FragInfo block bound in the pass belongs to the silhouette
    // draw, and its base colour is what the flat colour comes from.
    final blocks = pass
        .recordedOf<RecordedUniformBlock>()
        .where((b) => b.block == 'FragInfo')
        .toList();
    final silhouette = blocks.last.members['base_color']!;
    expect(silhouette, Float32List.fromList(<double>[0.1, 0.9, 0.2, 1.0]));
    expect(
      blocks.last.shader.name,
      'Xray',
      reason:
          'a silhouette is a flat colour, whatever the node is made of — and '
          'the stage draws it with the one shader that declares no surface '
          'output, so a hidden node describes no surface',
    );
    // And the fog block bound beside it says no fog, so a far monster reads
    // as far rather than as absent.
    final fog = pass
        .recordedOf<RecordedUniformBlock>()
        .where((b) => b.block == 'FogInfo')
        .last;
    expect(fog.members['fog']![3], 0.0);
  });
}
