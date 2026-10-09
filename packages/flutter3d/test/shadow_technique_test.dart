/// `ShadowTechnique`: the interface the directional filter is drawn through.
///
///     flutter test test/shadow_technique_test.dart
///
/// Drawn on the software rasteriser, as `evsm_shadow_test.dart` is. What is
/// held here: the built-in filters are techniques and read the settings as
/// the renderer did before there was an interface; a custom filter without a
/// technique is drawn as its base; and a technique of one's own changes the
/// frame only through what it answers, so one that answers what a built-in
/// would draws that built-in's frame to the byte.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 120;

Scene _floorAndBox(GraphicsDevice device) {
  final scene = Scene();
  final floorMesh = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(14.0, 0.2, 14.0)).build(),
  );
  final boxMesh = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(1.6, 0.2, 1.6)).build(),
  );
  scene
    ..add(
      MeshNode(floorMesh, RenderMaterial(name: 'floor'), name: 'floor')
        ..setPosition(0.0, -0.1, 0.0),
    )
    ..add(
      MeshNode(boxMesh, RenderMaterial(name: 'box'), name: 'box')
        ..setPosition(0.0, 0.6, 0.0),
    );
  final sun = LightNode(name: 'sun', intensity: 3.0 * Photometric.legacyUnit)
    ..castsShadow = true;
  sun.lookAt(Vector3(-0.85, -1.0, -0.2));
  scene.add(sun);
  return scene;
}

const ShadowSettings _base = ShadowSettings(cascades: 1, viewDistance: 20.0);

Future<(Uint8List, FrameResult)> _draw(ShadowSettings shadows) async {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final renderer = Renderer.create(device: device);
  final camera = CameraNode()
    ..setPosition(0.0, 12.0, 0.01)
    ..lookAt(Vector3.zero());
  final frame = renderer.render(
    width: _width,
    height: _height,
    scene: _floorAndBox(device),
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(shadows: shadows),
  );
  final pixels = (await device.readback(frame.frame)).buffer.asUint8List();
  return (pixels, frame);
}

/// Answers whatever [inner] answers, under a name of its own: a technique
/// that changes nothing, so any difference in the frame is the interface's.
final class _Wrapping extends ShadowTechnique {
  const _Wrapping(this.inner);

  final ShadowTechnique inner;

  @override
  String get name => 'wrapping ${inner.name}';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => inner.kernelFor(settings);

  @override
  ShadowPrefilter? prefilterFor(ShadowSettings settings) =>
      inner.prefilterFor(settings);

  @override
  int cascadesFor(ShadowSettings settings) => inner.cascadesFor(settings);
}

/// A sun of a fixed size, whatever the settings say.
final class _FixedSun extends ShadowTechnique {
  const _FixedSun(this.radius);

  final double radius;

  @override
  String get name => 'fixed sun';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) =>
      ShadowKernel.blockerSearch(lightRadius: radius);
}

/// One cascade, whatever the settings say.
final class _OneCascade extends ShadowTechnique {
  const _OneCascade();

  @override
  String get name => 'one cascade';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;

  @override
  int cascadesFor(ShadowSettings settings) => 1;
}

/// Moments made by a stage no library has.
final class _MissingStage extends ShadowTechnique {
  const _MissingStage();

  @override
  String get name => 'missing stage';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) =>
      const ShadowKernel.moments();

  @override
  ShadowPrefilter? prefilterFor(ShadowSettings settings) =>
      const ShadowPrefilter(stage: 'NoSuchPrefilter');
}

void main() {
  group('the built-in filters are techniques', () {
    test('each filter names its own', () {
      expect(ShadowFilter.pcf.technique, same(ShadowTechnique.pcf));
      expect(ShadowFilter.pcss.technique, same(ShadowTechnique.pcss));
      expect(ShadowFilter.evsm.technique, same(ShadowTechnique.evsm));
      expect(
        const ShadowSettings().directionalTechnique,
        same(ShadowTechnique.pcf),
      );
    });

    test('a custom filter without one is drawn as its base', () {
      const named = ShadowFilter.custom('mine', base: ShadowFilter.pcss);
      expect(named.technique, same(ShadowTechnique.pcss));
      const given = ShadowFilter.custom(
        'mine',
        base: ShadowFilter.pcf,
        technique: _FixedSun(0.02),
      );
      expect(given.base, ShadowFilter.pcf);
      expect(given.technique, isA<_FixedSun>());
    });

    test('they read the settings the renderer always read', () {
      const settings = ShadowSettings(
        evsmBlurRadius: 12,
        evsmBleedReduction: 2,
      );
      expect(ShadowTechnique.pcf.kernelFor(settings), ShadowKernel.box3x3);
      expect(
        ShadowTechnique.pcss.kernelFor(settings),
        const ShadowKernel.blockerSearch(
          lightRadius: ShadowSettings.sunAngularRadius,
        ),
      );
      expect(
        ShadowTechnique.pcss.kernelFor(
          settings.copyWith(directionalLightRadius: 0.03),
        ),
        const ShadowKernel.blockerSearch(lightRadius: 0.03),
      );
      expect(
        ShadowTechnique.evsm.kernelFor(settings),
        const ShadowKernel.moments(bleedReduction: 0.95),
      );
      expect(
        ShadowTechnique.evsm.prefilterFor(settings),
        const ShadowPrefilter(stage: 'EvsmFilter', radius: 8),
      );
      expect(ShadowTechnique.pcf.prefilterFor(settings), isNull);
      expect(ShadowTechnique.pcss.cascadesFor(settings), settings.cascades);
    });
  });

  group('a technique of one\'s own', () {
    for (final filter in ShadowFilter.values) {
      test('wrapping ${filter.name} draws ${filter.name}\'s frame', () async {
        final (builtIn, _) = await _draw(_base.copyWith(filter: filter));
        final (wrapped, frame) = await _draw(
          _base.copyWith(
            filter: ShadowFilter.custom(
              'wrapped',
              base: ShadowFilter.pcf,
              technique: _Wrapping(filter.technique),
            ),
          ),
        );
        expect(wrapped, builtIn);
        if (filter == ShadowFilter.evsm) {
          expect(frame.passes.map((p) => p.name), contains('shadow moments'));
        }
      });
    }

    test('its kernel parameters are what the lit draws read', () async {
      final (pcss, _) = await _draw(
        _base.copyWith(filter: ShadowFilter.pcss, directionalLightRadius: 0.05),
      );
      final (fixed, _) = await _draw(
        _base.copyWith(
          filter: const ShadowFilter.custom(
            'fixed',
            base: ShadowFilter.pcf,
            technique: _FixedSun(0.05),
          ),
        ),
      );
      expect(fixed, pcss);
    });

    test('its cascade count is the one drawn', () async {
      final (one, _) = await _draw(_base.copyWith(cascades: 1));
      final (asked, _) = await _draw(
        _base.copyWith(
          cascades: 3,
          filter: const ShadowFilter.custom(
            'one',
            base: ShadowFilter.pcf,
            technique: _OneCascade(),
          ),
        ),
      );
      expect(asked, one);
    });

    test('a prefilter stage no library has draws the box', () async {
      final (pcf, _) = await _draw(_base.copyWith(filter: ShadowFilter.pcf));
      final (missing, frame) = await _draw(
        _base.copyWith(
          filter: const ShadowFilter.custom(
            'missing',
            base: ShadowFilter.evsm,
            technique: _MissingStage(),
          ),
        ),
      );
      expect(missing, pcf);
      expect(
        frame.passes.map((p) => p.name),
        isNot(contains('shadow moments')),
      );
    });
  });
}
