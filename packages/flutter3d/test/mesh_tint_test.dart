/// A node's own tint over a shared material: a colour it multiplies, and an
/// opacity it fades by, drawn by the software backend through a real
/// renderer.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 24;

/// A white cube filling the middle of a frame over a blue clear, each node
/// in [tints] one cube side by side; the frame and its draw count.
Future<({Uint8List rgba, int draws})> _frame(
  List<Vector4> tints, {
  bool batch = false,
}) async {
  final it = cpuTestDevice(width: _size, height: _size);
  final mesh = DeviceMesh.upload(
    it.device,
    CuboidShape(size: Vector3.all(1.0)).build(),
  );
  final material = RenderMaterial(
    baseColor: LinearColor.fromSrgb(0.8, 0.8, 0.8, 1.0),
    lighting: LightingModel.unlit,
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 2.2)
    ..lookAt(Vector3.zero());
  final scene = Scene()..add(camera);
  for (var i = 0; i < tints.length; i++) {
    scene.add(
      MeshNode(mesh, material)
        ..setPosition((i - (tints.length - 1) / 2.0) * 0.02, 0.0, 0.0)
        ..tint = tints[i].toLinearColor(),
    );
  }
  final result =
      Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      ).render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[
          RenderView(
            camera: camera,
            clearColorSrgb: Vector4(0.0, 0.0, 1.0, 1.0),
          ),
        ],
        settings: RenderSettings(
          tonemap: false,
          bloom: const BloomSettings(enabled: false),
          batchIdenticalDraws: batch,
        ),
      );
  final pixels = await it.device.readback(result.frame);
  return (rgba: pixels.buffer.asUint8List(), draws: result.drawCalls);
}

({int r, int g, int b}) _middle(Uint8List rgba) {
  final at = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
  return (r: rgba[at], g: rgba[at + 1], b: rgba[at + 2]);
}

void main() {
  test('white leaves the material as it is', () async {
    // The byte-for-byte promise is the golden suites': every frame in them
    // is drawn at white.
    final plain = await _frame(<Vector4>[Vector4.all(1.0)]);
    final grey = _middle(plain.rgba);
    expect(grey.r, grey.b, reason: 'an untinted grey is grey');
    expect(grey.r, greaterThan(150));
  });

  test('a tint colours the node, not the material', () async {
    final red = _middle(
      (await _frame(<Vector4>[Vector4(1.0, 0.2, 0.2, 1.0)])).rgba,
    );
    expect(red.r, greaterThan(red.g + 60));
    expect(red.r, greaterThan(red.b + 60));
  });

  test('below one alpha the node is blended over what is behind it', () async {
    // Mutation: leave an opaque material in the opaque pass whatever its
    // node's tint.
    final half = _middle(
      (await _frame(<Vector4>[Vector4(1.0, 1.0, 1.0, 0.5)])).rgba,
    );
    final solid = _middle((await _frame(<Vector4>[Vector4.all(1.0)])).rgba);
    // The cube alone is near white; half of it over blue loses red and keeps
    // blue.
    expect(half.r, lessThan(solid.r - 30));
    expect(half.b, greaterThan(half.r + 30), reason: 'the blue shows through');
  });

  test('a tinted node is never folded into an automatic batch', () async {
    // Four identical cubes batch into one draw; tint one and it is drawn on
    // its own, or the batch would give it the others' colour.
    final white = List<Vector4>.generate(4, (_) => Vector4.all(1.0));
    final together = await _frame(white, batch: true);
    final oneRed = await _frame(<Vector4>[
      ...white.take(3),
      Vector4(1.0, 0.0, 0.0, 1.0),
    ], batch: true);
    expect(oneRed.draws, greaterThan(together.draws));
  });
}
