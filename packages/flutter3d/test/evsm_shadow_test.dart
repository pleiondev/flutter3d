/// `S2`: the directional shadow filtered as exponential variance moments.
///
///     flutter test test/evsm_shadow_test.dart
///
/// Drawn on the software rasteriser, which filters 32-bit float targets and
/// so makes the moments; the golden scene `evsm-soft` is the same floor and
/// box, recorded on the other backends with the rest of the goldens.
///
/// What is held here: the filter is off unless asked for and the frame then
/// does not move by a byte; asked for, it still shadows what the fixed
/// kernel shadows and softens the edge more widely; its moments are made
/// again only when the depth they come from changed; and a device that
/// cannot filter them says so instead of drawing something else under the
/// same name.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 120;

/// A floor with a box held [gap] metres above it, lit from nearly straight
/// up so the shadow lands beside and under it.
Scene _floorAndBox(GraphicsDevice device, {double gap = 0.6}) {
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

CameraNode _camera() => CameraNode()
  ..setPosition(0.0, 12.0, 0.01)
  ..lookAt(Vector3.zero());

RenderSettings _settings(ShadowSettings shadows) =>
    RenderSettings(shadows: shadows);

const ShadowSettings _base = ShadowSettings(cascades: 1, viewDistance: 20.0);

CpuDevice _cpu() => CpuDevice(
  width: _width,
  height: _height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// One frame of the floor and box under [shadows], as its pixels and the
/// frame's own report.
Future<(Uint8List, FrameResult)> _draw(ShadowSettings shadows) async {
  final device = _cpu();
  final renderer = Renderer.create(device: device);
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: _floorAndBox(device),
    views: <RenderView>[RenderView(camera: _camera())],
    settings: _settings(shadows),
  );
  final pixels = (await device.readPixels(frame.frame))!.buffer.asUint8List();
  return (pixels, frame);
}

/// Pixels part-way between lit floor and full shadow, over the whole frame:
/// the width of the penumbra summed along its edge. The measure
/// `soft_shadow_test.dart` uses, for the reason it gives.
int _penumbra(Uint8List rgba) {
  var count = 0;
  for (var at = 0; at < rgba.length; at += 4) {
    final green = rgba[at + 1];
    if (green > 130 && green < 220) count++;
  }
  return count;
}

/// Pixels at least as dark as full shadow on this floor.
int _umbra(Uint8List rgba) {
  var count = 0;
  for (var at = 0; at < rgba.length; at += 4) {
    if (rgba[at + 1] <= 130) count++;
  }
  return count;
}

void main() {
  group('off unless asked for', () {
    test('the filter follows the light radius when none is named', () {
      expect(const ShadowSettings().filter, isNull);
      expect(const ShadowSettings().directionalFilter, ShadowFilter.pcf);
      expect(
        const ShadowSettings(directionalLightRadius: 0.01).directionalFilter,
        ShadowFilter.pcss,
      );
      expect(
        const ShadowSettings().copyWith(filter: ShadowFilter.evsm).filter,
        ShadowFilter.evsm,
      );
    });

    test('pcf by name draws the frame the default draws', () async {
      final (unnamed, frame) = await _draw(_base);
      final (named, _) = await _draw(_base.copyWith(filter: ShadowFilter.pcf));
      expect(named, unnamed);
      expect(frame.skipReasonOf('shadow moments'), PassSkip.settings);
    });
  });

  group('evsm-soft', () {
    test('shadows what the kernel shadows, with a wider edge', () async {
      final (hard, _) = await _draw(_base);
      final (soft, frame) = await _draw(
        _base.copyWith(filter: ShadowFilter.evsm, evsmBlurRadius: 4),
      );

      expect(frame.passes.map((pass) => pass.name), contains('shadow moments'));
      expect(soft, isNot(hard));
      // Still a shadow: most of the kernel's umbra survives the blur, so the
      // moments were read as moments and not as depth.
      expect(
        _umbra(soft),
        greaterThan(_umbra(hard) ~/ 2),
        reason: 'umbra: kernel ${_umbra(hard)}, evsm ${_umbra(soft)}',
      );
      // And softer: a blur four texels to each side spreads the edge further
      // than a 3×3 square does.
      expect(
        _penumbra(soft),
        greaterThan(_penumbra(hard)),
        reason: 'penumbra: kernel ${_penumbra(hard)}, evsm ${_penumbra(soft)}',
      );
    });

    test('a wider blur widens the edge', () async {
      final (narrow, _) = await _draw(
        _base.copyWith(filter: ShadowFilter.evsm, evsmBlurRadius: 1),
      );
      final (wide, _) = await _draw(
        _base.copyWith(filter: ShadowFilter.evsm, evsmBlurRadius: 6),
      );
      expect(
        _penumbra(wide),
        greaterThan(_penumbra(narrow)),
        reason: 'radius 1: ${_penumbra(narrow)}, radius 6: ${_penumbra(wide)}',
      );
    });

    test('the moments are made again only when the depth changed', () async {
      // Two frames of a still scene: the second keeps the depth atlas, so it
      // keeps the moments too, and costs the same draws as the kernel does.
      Future<List<int>> drawCalls(ShadowSettings shadows) async {
        final device = _cpu();
        final renderer = Renderer.create(device: device);
        final scene = _floorAndBox(device);
        final camera = _camera();
        return <int>[
          for (var i = 0; i < 2; i++)
            renderer
                .render(
                  width: _width,
                  height: _height,
                  scene: scene,
                  views: <RenderView>[RenderView(camera: camera)],
                  settings: _settings(shadows),
                )
                .drawCalls,
        ];
      }

      final kernel = await drawCalls(_base);
      final evsm = await drawCalls(_base.copyWith(filter: ShadowFilter.evsm));
      expect(evsm.first, kernel.first + 2, reason: 'two blur passes');
      expect(evsm.last, kernel.last, reason: 'nothing to blur again');
    });
  });

  test('a device that cannot filter the moments refuses them by name', () {
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    expect(device.supportsFloat32Filtering, isFalse);
    final frame = renderer.render(
      width: _width,
      height: _height,
      scene: _floorAndBox(device),
      views: <RenderView>[RenderView(camera: _camera())],
      settings: _settings(_base.copyWith(filter: ShadowFilter.evsm)),
    );
    expect(frame.skipReasonOf('shadow moments'), PassSkip.unsupported);
    expect(frame.passes.map((pass) => pass.name), contains('scene'));
  });
}
