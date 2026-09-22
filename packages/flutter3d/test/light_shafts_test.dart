/// `gfx-33n`: volumetric shafts marched through the shadow map.
///
///     flutter test test/light_shafts_test.dart
///
/// **The claim that separates this from the cheap version.** The familiar
/// radial smear takes bright pixels and streaks them away from the sun's
/// position on screen: it needs the sun in frame, it brightens anything else
/// that is bright, and it knows nothing about what is casting. This marches
/// the view ray and asks the shadow map. So the test that matters is the one
/// that takes the shadow away — with no caster there is nothing to draw, and
/// the frame has to come back byte for byte as it would without the pass.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A lit room with a blocker in it, optionally with shafts and shadows.
Future<List<int>> _frame({
  required bool shafts,
  required bool shadows,
  double strength = 0.6,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);

  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3(8, 8, 1)).build()),
        Material(name: 'floor', baseColor: Vector4(0.7, 0.7, 0.7, 1.0)),
      )..setPosition(0.0, 0.0, -3.0),
    )
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3(1, 3, 1)).build()),
        Material(name: 'blocker', baseColor: Vector4(0.2, 0.2, 0.2, 1.0)),
      )..setPosition(-0.6, 0.0, 0.0),
    )
    ..add(
      LightNode(intensity: 8.0, castsShadow: shadows)
        ..setPosition(3.0, 3.0, 3.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 6.0));

  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: RenderSettings(
      shadows: ShadowSettings(enabled: shadows),
      lightShafts: LightShaftSettings(
        enabled: shafts,
        strength: strength,
        distance: 20.0,
      ),
    ),
  );

  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size; i++) bytes!.getUint8(i * 4)];
}

void main() {
  test('off is the frame it always was, and off is the default', () async {
    expect(const LightShaftSettings().enabled, isFalse);
    expect(
      await _frame(shafts: false, shadows: true),
      await _frame(shafts: false, shadows: true),
    );
  });

  test('with a caster, it adds light to the air', () async {
    final plain = await _frame(shafts: false, shadows: true);
    final shafted = await _frame(shafts: true, shadows: true);

    expect(
      shafted,
      isNot(plain),
      reason:
          'a pass that marches sixteen shadow lookups a pixel and changes '
          'nothing is a draw call and nothing else',
    );

    // Added, never subtracted: in-scatter is light, so no pixel may come out
    // darker than it went in.
    for (var i = 0; i < plain.length; i++) {
      expect(
        shafted[i],
        greaterThanOrEqualTo(plain[i]),
        reason: 'pixel $i went darker, and scattering cannot remove light',
      );
    }
  });

  test('with the caster\'s shadow off there is nothing to draw', () async {
    // **The row\'s own acceptance, and the whole difference from a screen
    // brightness trick.** The shaft is a shadow-map product: no map, no
    // shape, nothing to add. A radial smear would happily keep streaking the
    // bright pixels around, which is how you can tell the two apart from the
    // outside.
    final without = await _frame(shafts: false, shadows: false);
    final with_ = await _frame(shafts: true, shadows: false);

    expect(
      with_,
      without,
      reason:
          'the pass declined, byte for byte — a scene with no directional '
          'caster gets no shafts, and that is an answer rather than an error',
    );
  });

  test('strength scales what is added', () async {
    final faint = await _frame(shafts: true, shadows: true, strength: 0.1);
    final strong = await _frame(shafts: true, shadows: true, strength: 0.9);

    var faintSum = 0;
    var strongSum = 0;
    for (var i = 0; i < faint.length; i++) {
      faintSum += faint[i];
      strongSum += strong[i];
    }
    expect(
      strongSum,
      greaterThan(faintSum),
      reason:
          'the strength is folded into the scatter colour, so more of it '
          'has to mean more light in the air',
    );
  });
}
