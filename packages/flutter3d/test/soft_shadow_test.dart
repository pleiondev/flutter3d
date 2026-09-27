/// `gfx-15n`: a directional shadow whose edge widens with the occluder's
/// distance, instead of one that is always equally hard.
///
///     flutter test test/soft_shadow_test.dart
///
/// **What a fixed kernel cannot be.** A 3×3 filter gives every shadow the same
/// edge: a box resting on the floor and a box a metre above it cast the same
/// blur, which is the one thing a real shadow never does. The five-tap version
/// searches for what is blocking first and sizes the filter from how far away
/// it turned out to be, so the edge under a box stays sharp and the edge of
/// its shadow spreads as the box rises.
///
/// Measured rather than looked at: the penumbra is the count of pixels that
/// are neither fully lit nor fully shadowed along a line across the shadow's
/// edge, and the test is that the count grows with the gap. A golden would
/// say the picture has not changed; this says the shadow behaves like one.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 120;

/// A floor with one box floating [gap] metres above it, lit from straight up
/// so the shadow lands directly underneath.
Scene _floorAndBox(CpuDevice device, double gap) {
  final scene = Scene();
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(14.0, 0.2, 14.0)).build(),
      ),
      Material(name: 'floor', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      name: 'floor',
    )..setPosition(0.0, -0.1, 0.0),
  );
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(1.6, 0.2, 1.6)).build(),
      ),
      Material(name: 'box', baseColor: Vector4(0.7, 0.7, 0.7, 1.0)),
      name: 'box',
    )..setPosition(0.0, gap, 0.0),
  );

  final sun = LightNode(name: 'sun', intensity: 3.0)..castsShadow = true;
  sun.lookAt(Vector3(-0.85, -1.0, -0.2));
  scene.add(sun);
  return scene;
}

Future<Uint8List> _draw(double gap, {required double radius}) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final camera = CameraNode()..setPosition(0.0, 12.0, 0.01);
  camera.lookAt(Vector3.zero());
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: _floorAndBox(device, gap),
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      shadows: ShadowSettings(
        cascades: 1,
        viewDistance: 20.0,
        directionalLightRadius: radius,
      ),
    ),
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

/// How many pixels of the frame are part-way between lit floor and full
/// shadow — the width of the penumbra, summed over the whole edge.
///
/// Counted over the frame rather than along one scanline: the shadow is a
/// quadrilateral and its edges run at an angle, so a single row crosses two
/// of them at whatever width the angle happens to give.
int _penumbra(Uint8List rgba, {required int low, required int high}) {
  var count = 0;
  for (var at = 0; at < rgba.length; at += 4) {
    final green = rgba[at + 1];
    if (green > low && green < high) count++;
  }
  return count;
}

void main() {
  group('off, the kernel is the one every golden holds', () {
    test('zero is the default', () {
      expect(const ShadowSettings().directionalLightRadius, 0.0);
    });

    test('zero draws what it drew before the five taps existed', () async {
      expect(await _draw(0.4, radius: 0.0), await _draw(0.4, radius: 0.0));
    });

    test('and a radius changes the picture', () async {
      expect(
        await _draw(0.4, radius: 0.1),
        isNot(await _draw(0.4, radius: 0.0)),
      );
    });
  });

  group('on, the penumbra widens with the gap', () {
    test('a box further from the floor casts a softer edge', () async {
      // The row's own acceptance. Three heights, so the reading is a trend
      // rather than one comparison that might have gone either way.
      final near = _penumbra(
        await _draw(0.3, radius: 0.1),
        low: 130,
        high: 220,
      );
      final middle = _penumbra(
        await _draw(1.2, radius: 0.1),
        low: 130,
        high: 220,
      );
      final far = _penumbra(await _draw(2.4, radius: 0.1), low: 130, high: 220);

      expect(
        middle,
        greaterThan(near),
        reason: 'near $near, middle $middle, far $far',
      );
      expect(
        far,
        greaterThan(middle),
        reason: 'near $near, middle $middle, far $far',
      );
    });

    test('the hard kernel does not, which is the whole difference', () async {
      // The same three heights through the 3×3 filter. Its edge is the width
      // of the kernel wherever the box is, so the counts stay close — a few
      // pixels of drift from the shadow itself changing size with the height,
      // not from the filter.
      final near = _penumbra(
        await _draw(0.3, radius: 0.0),
        low: 130,
        high: 220,
      );
      final far = _penumbra(await _draw(2.4, radius: 0.0), low: 130, high: 220);
      final soft = _penumbra(
        await _draw(2.4, radius: 0.1),
        low: 130,
        high: 220,
      );

      expect(
        soft - far,
        greaterThan(far - near),
        reason:
            'the filter should account for more of the widening than the '
            'shadow growing does: hard $near to $far, soft $soft',
      );
    });
  });
}
