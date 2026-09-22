/// `gfx-04n`: edges smoothed after the composite, so occlusion and clean
/// silhouettes stop being a choice.
///
///     flutter test test/antialias_test.dart
///
/// **The exclusion this ends, stated plainly.** The scene pass turns MSAA off
/// whenever anything consumes the surface buffer, because a multisampled
/// attachment and a buffer a later pass reads back are the same decision made
/// twice. Ambient occlusion consumes it. So a game got shadows in its corners
/// or smooth edges and not both, and nothing in the repository said so — the
/// two settings were in different files and the connection was a sentence in
/// a comment.
///
/// What is measured here is the staircase itself: a diagonal edge against a
/// flat background produces a run of hard steps, and the count of pixels that
/// are neither the subject's colour nor the background's is how many of those
/// steps have been softened. It is a number that moves for the right reason,
/// which a golden of a lit sphere is not.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 128;
const int _height = 96;

({CpuDevice device, Renderer renderer}) _engine() {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return (device: device, renderer: Renderer.create(device: device));
}

/// A bright quad turned off the axes, so its edges are diagonals and every
/// one of them staircases.
Scene _diagonal(CpuDevice device) {
  final scene = Scene();
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(2.2, 2.2, 0.2)).build(),
      ),
      Material(
        name: 'card',
        baseColor: Vector4(0.95, 0.95, 0.95, 1.0),
        lighting: LightingModel.unlit,
      ),
    )..setLocalMatrix(Matrix4.rotationZ(0.37)),
  );
  return scene;
}

Future<Uint8List> _draw(
  ({CpuDevice device, Renderer renderer}) it,
  RenderSettings settings,
) async {
  final frame = it.renderer.render(
    width: _width,
    height: _height,
    scene: _diagonal(it.device),
    views: <RenderView>[
      RenderView(
        camera: CameraNode()..setPosition(0.0, 0.0, 4.0),
        clearColor: Vector4(0.0, 0.0, 0.0, 1.0),
      ),
    ],
    settings: settings,
  );
  final pixels = await it.device.readPixels(frame.frame);
  return pixels!.buffer.asUint8List();
}

/// Pixels that are neither near-black nor near-white — the softened steps of
/// a staircase, and nothing else in this scene.
int _intermediate(Uint8List rgba) {
  var count = 0;
  for (var at = 0; at < rgba.length; at += 4) {
    final green = rgba[at + 1];
    if (green > 24 && green < 231) count++;
  }
  return count;
}

void main() {
  group('off, nothing changes', () {
    test('the setting is off by default', () {
      expect(const RenderSettings().antiAlias.enabled, isFalse);
    });

    test('off draws exactly what it drew before the pass existed', () async {
      final it = _engine();
      final a = await _draw(it, const RenderSettings());
      final b = await _draw(
        it,
        const RenderSettings(antiAlias: AntiAliasSettings()),
      );
      expect(a, b);
    });

    test('an inactive pass is culled rather than run', () async {
      final it = _engine();
      final frame = it.renderer.render(
        width: _width,
        height: _height,
        scene: _diagonal(it.device),
        views: <RenderView>[
          RenderView(camera: CameraNode()..setPosition(0.0, 0.0, 4.0)),
        ],
        settings: const RenderSettings(),
      );
      // Absence rather than `active: false` — the graph drops a node whose
      // own `isActive` says no before the order is built, which is what
      // `FrameResult.passes` documents and what makes the profiler's list
      // describe the frame that ran.
      expect(
        frame.passes.map((FramePass pass) => pass.name),
        isNot(contains('antialias')),
      );
    });
  });

  group('on, the staircase softens', () {
    test('a diagonal edge gains intermediate pixels', () async {
      final it = _engine();
      final hard = await _draw(it, const RenderSettings());
      final soft = await _draw(
        it,
        const RenderSettings(antiAlias: AntiAliasSettings(enabled: true)),
      );

      expect(
        _intermediate(soft),
        greaterThan(_intermediate(hard)),
        reason:
            'the edge has ${_intermediate(hard)} intermediate pixels hard and '
            '${_intermediate(soft)} smoothed',
      );
    });

    test('it is a pass of its own, with its own cost', () async {
      final it = _engine();
      final frame = it.renderer.render(
        width: _width,
        height: _height,
        scene: _diagonal(it.device),
        views: <RenderView>[
          RenderView(camera: CameraNode()..setPosition(0.0, 0.0, 4.0)),
        ],
        settings: const RenderSettings(
          antiAlias: AntiAliasSettings(enabled: true),
        ),
      );

      // `gfx-04n`'s own acceptance asks for a pass cost from the profiler,
      // which `gfx-01n` is what makes answerable: one full-screen draw, named.
      final pass = frame.passes.firstWhere(
        (FramePass each) => each.name == 'antialias',
      );
      expect(pass.drawCalls, 1);
      expect(pass.triangles, 0);
    });

    test(
      'a threshold of one smooths nothing, which is the knob working',
      () async {
        final it = _engine();
        final hard = await _draw(it, const RenderSettings());
        // Nothing in a picture has more local contrast than its own maximum, so
        // a threshold of one refuses every pixel and the pass becomes a copy.
        final refused = await _draw(
          it,
          const RenderSettings(
            antiAlias: AntiAliasSettings(enabled: true, contrastThreshold: 1.0),
          ),
        );
        expect(_intermediate(refused), _intermediate(hard));
      },
    );
  });

  group('the exclusion it was written to end', () {
    test('occlusion and smooth edges at the same time', () async {
      // The whole row in one test. Ambient occlusion consumes the surface
      // buffer, which turns MSAA off for the scene; with this pass on, the
      // edges come back anyway.
      final it = _engine();
      const occluded = RenderSettings(
        ambientOcclusion: AmbientOcclusionSettings(enabled: true),
      );
      final withoutAa = await _draw(it, occluded);
      final withAa = await _draw(
        it,
        occluded.copyWith(antiAlias: const AntiAliasSettings(enabled: true)),
      );

      expect(_intermediate(withAa), greaterThan(_intermediate(withoutAa)));
    });
  });
}
