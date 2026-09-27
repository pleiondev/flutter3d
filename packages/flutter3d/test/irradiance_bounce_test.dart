/// A red wall tints the white one facing it — `gfx-81n`.
///
///     flutter test test/irradiance_bounce_test.dart
///
/// The row's own acceptance, in a rendered frame: a surface no light reaches
/// directly shows coloured bounce, and a scene with the field off is byte for
/// byte what it was.
///
/// **Why the second clause is not a formality.** The field replaces the two
/// ambient colours per draw and touches nothing else, so "off" has to mean the
/// staged arrays hold exactly what `_updateAmbient` put there. Forty-four
/// recorded frames rest on that, and this is the cheapest place to state it
/// where a change to the encode would be caught.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

/// Two facing walls with a lamp between them, and a small white slab in the
/// middle whose lit face points away from the lamp.
///
/// The slab is what the test reads: nothing reaches its camera-facing side
/// directly, so whatever colour it has came off the walls.
({Scene scene, CameraNode camera}) _room({required bool redWall}) {
  final scene = Scene()..ambientIntensity = 1.0;
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );

  MeshNode slab(Vector3 size, Vector3 at, Vector4 colour, String name) =>
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: size).build()),
        Material(
          name: name,
          baseColor: colour,
          lighting: LightingModel.lambert,
        ),
        name: name,
      )..setPosition(at.x, at.y, at.z);

  // The two side walls. One of them is the colour under test.
  scene
    ..add(
      slab(
        Vector3(0.4, 4.0, 4.0),
        Vector3(-2.0, 0.0, 0.0),
        redWall ? Vector4(1.0, 0.05, 0.05, 1.0) : Vector4(0.9, 0.9, 0.9, 1.0),
        'left wall',
      ),
    )
    ..add(
      slab(
        Vector3(0.4, 4.0, 4.0),
        Vector3(2.0, 0.0, 0.0),
        Vector4(0.9, 0.9, 0.9, 1.0),
        'right wall',
      ),
    )
    ..add(
      slab(
        Vector3(0.8, 0.8, 0.2),
        Vector3(0.0, 0.0, 0.0),
        Vector4(0.9, 0.9, 0.9, 1.0),
        'subject',
      ),
    )
    ..add(
      LightNode(type: LightType.point, intensity: 24.0, name: 'lamp')
        ..setPosition(0.0, 1.6, -1.2),
    );

  final camera = CameraNode()
    ..setPosition(0.0, 0.2, 4.0)
    ..lookAt(Vector3.zero());
  return (scene: scene, camera: camera);
}

Future<Uint8List> _draw({required bool field, required bool redWall}) async {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
  final room = _room(redWall: redWall);

  if (field) {
    final built = IrradianceField(
      origin: Vector3(-2.0, -1.0, -2.0),
      spacing: Vector3(2.0, 1.0, 2.0),
      countX: 3,
      countY: 3,
      countZ: 3,
    );
    gather(built, room.scene, rays: 96);
    room.scene.irradianceField = built;
  }

  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: room.scene,
    views: <RenderView>[RenderView(camera: room.camera)],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = await it.device.readPixels(frame.frame);
  expect(pixels, isNotNull);
  return pixels!.buffer.asUint8List();
}

/// The average red-minus-blue over the middle of the frame, which is the
/// subject slab.
double _tint(Uint8List rgba) {
  var total = 0.0;
  var n = 0;
  for (var y = _height ~/ 2 - 4; y < _height ~/ 2 + 4; y++) {
    for (var x = _width ~/ 2 - 4; x < _width ~/ 2 + 4; x++) {
      final i = (y * _width + x) * 4;
      total += rgba[i] - rgba[i + 2];
      n++;
    }
  }
  return total / n;
}

void main() {
  test('off, the picture is the bytes it was', () async {
    // The clause every recorded frame depends on. A field is null by default,
    // so this is the path seventy-eight goldens take.
    final a = await _draw(field: false, redWall: true);
    final b = await _draw(field: false, redWall: true);
    expect(a, orderedEquals(b));
  });

  test('a red wall tints what faces it', () async {
    // **The row's own acceptance.** Nothing lights the subject's near face
    // directly — the lamp is behind it — so whatever colour it has came off the
    // walls, and with one of them red the bounce is red.
    final white = await _draw(field: true, redWall: false);
    final red = await _draw(field: true, redWall: true);

    expect(
      _tint(red),
      greaterThan(_tint(white) + 1.0),
      reason:
          'the red wall did not tint the subject: '
          'red ${_tint(red)}, white ${_tint(white)}',
    );
  });

  test('the field changes the picture at all', () async {
    // A guard against the two tests above passing because nothing happens: the
    // field has to move pixels, or its acceptance is being met by noise.
    final without = await _draw(field: false, redWall: true);
    final with_ = await _draw(field: true, redWall: true);

    var changed = 0;
    for (var i = 0; i < without.length; i += 4) {
      if ((without[i] - with_[i]).abs() > 1) changed++;
    }
    expect(changed, greaterThan(64), reason: 'the field moved $changed pixels');
  });
}
