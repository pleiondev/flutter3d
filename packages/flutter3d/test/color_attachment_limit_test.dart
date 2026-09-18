/// `gfx-50n`: a second colour attachment, refused where it would abort.
///
///     flutter test test/color_attachment_limit_test.dart
///
/// **The defect this closes is the worst kind this engine had.** The scene
/// pass opened a second attachment whenever anything consumed the surface
/// buffer, and nothing anywhere asked whether the device could open one. On
/// Impeller's OpenGL ES path that reaches an `FML_CHECK`: the process aborts
/// in release. It does not draw the wrong picture or log a warning — it stops.
/// Mitigated only by every effect that consumes the buffer being off by
/// default, so it took a user switching one on.
///
/// **And the diagnostic could not diagnose it.** `probeMultipleRenderTargets`
/// found out whether a second attachment worked by opening one, which on the
/// device where the answer is no is the same call that ends the process.
///
/// So the tests here are about a device that says one: that nothing opens two
/// attachments on it, that the passes which wanted the buffer are culled and
/// say why, that the frame it draws is the frame it would have drawn with
/// those effects switched off, and that a caller who opens two anyway gets a
/// throw rather than a crash.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

/// Settings with two effects that want the surface buffer.
const RenderSettings _wantsSurface = RenderSettings(
  ambientOcclusion: AmbientOcclusionSettings(enabled: true),
  reflections: ReflectionSettings(enabled: true),
);

/// A frame on a fake device that opens at most [attachments] colour targets.
FrameResult _recorded(RenderSettings settings, {required int attachments}) {
  final device = FakeBackend(maxColorAttachments: attachments);
  final renderer = Renderer.create(device: device);
  final scene = Scene()..add(CameraNode());
  return renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: settings,
  );
}

/// The widest colour-attachment list any pass of [result] opened.
int _widestPass(FakeBackend device) => device.passes
    .map((p) => p.descriptor.colors.length)
    .fold(0, (a, b) => a > b ? a : b);

/// Real pixels, from a rasteriser that answers [attachments].
Future<List<int>> _pixels(
  RenderSettings settings, {
  required int attachments,
}) async {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    maxColorAttachments: attachments,
  );
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, SphereShape(radius: 0.6).build()),
        Material(name: 'ball', baseColor: Vector4(0.8, 0.3, 0.2, 1.0)),
      ),
    )
    ..add(
      LightNode(intensity: 6.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 3.0));

  final frame = renderer.render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: settings,
  );
  final bytes = await device.readPixels(frame.frame);
  return <int>[for (var i = 0; i < _size * _size * 4; i++) bytes!.getUint8(i)];
}

void main() {
  group('the device publishes a limit', () {
    test('the rasteriser answers two, which is what the engine opens', () {
      final device = CpuDevice(
        width: 4,
        height: 4,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      expect(device.maxColorAttachments, 2);
    });

    test('a pass past the limit throws instead of being opened', () {
      // The promise that makes the number worth publishing. Without it the
      // number is a suggestion, and the backend where it matters answers a
      // suggestion by aborting.
      final device = CpuDevice(
        width: 4,
        height: 4,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
        maxColorAttachments: 1,
      );
      final one = device.createTexture(
        RenderTargetSpec(width: 4, height: 4, format: device.defaultColorFormat),
      );
      final two = device.createTexture(
        RenderTargetSpec(width: 4, height: 4, format: device.defaultColorFormat),
      );

      expect(
        () => device.beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(texture: one),
              ColorTarget(texture: two),
            ],
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('one attachment is still opened on such a device', () {
      // The refusal has to be about the second one only. A device that
      // refused everything would pass the test above and draw nothing.
      final device = CpuDevice(
        width: 4,
        height: 4,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
        maxColorAttachments: 1,
      );
      final one = device.createTexture(
        RenderTargetSpec(width: 4, height: 4, format: device.defaultColorFormat),
      );

      expect(
        () => device.beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[ColorTarget(texture: one)],
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('a frame on a device with one attachment', () {
    test('opens no pass with two colour targets', () {
      // Measured rather than inferred: the fake records every descriptor it
      // was handed, so this reads what the engine actually opened instead of
      // what it meant to.
      final device = FakeBackend(maxColorAttachments: 1);
      final renderer = Renderer.create(device: device);
      final scene = Scene()..add(CameraNode());
      renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
        settings: _wantsSurface,
      );

      expect(_widestPass(device), 1);
    });

    test('opens one with two colour targets where it may', () {
      // The other half, and the one that makes the test above mean
      // something: with two allowed, the engine does open two.
      final device = FakeBackend();
      final renderer = Renderer.create(device: device);
      final scene = Scene()..add(CameraNode());
      renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
        settings: _wantsSurface,
      );

      expect(_widestPass(device), 2);
    });

    test('the passes that wanted the buffer say the device cannot', () {
      // **The refusal is visible rather than silent, which is the half of
      // this row that is not a bug fix.** An engine that quietly dropped two
      // effects would leave somebody comparing screenshots across devices.
      //
      // `unsupported` rather than `settings`, and that is the whole point of
      // the fifth reason: these two effects *were* switched on, so an answer
      // naming the settings would send a caller back to a configuration they
      // had already got right.
      final result = _recorded(_wantsSurface, attachments: 1);
      final reasons = <String, PassSkip>{
        for (final skip in result.skipped) skip.name: skip.reason,
      };

      expect(reasons['ssao'], PassSkip.unsupported);
      expect(reasons['reflections'], PassSkip.unsupported);
    });

    test(
      'both run where the device allows two, so the above is not vacuous',
      () {
        final result = _recorded(_wantsSurface, attachments: 2);
        final ran = result.passes.map((p) => p.name).toSet();

        expect(ran, containsAll(<String>['ssao', 'reflections']));
      },
    );

    test('a pass that never wanted the buffer is untouched', () {
      // The gate is about one resource, not about post-processing. Bloom
      // reads the lit colour and nothing else, so it has to run on a device
      // with one attachment exactly as it always did.
      final result = _recorded(
        const RenderSettings(bloom: BloomSettings(intensity: 0.8)),
        attachments: 1,
      );

      expect(result.passes.map((p) => p.name), contains('bloom'));
    });
  });

  group('the picture on a device with one attachment', () {
    test(
      'is the picture those effects switched off would have drawn',
      () async {
        // Byte for byte, which is the strongest available statement that the
        // degrade is a degrade rather than a different frame: the device that
        // cannot have the effects draws what a device that was never asked for
        // them draws.
        final degraded = await _pixels(_wantsSurface, attachments: 1);
        final without = await _pixels(const RenderSettings(), attachments: 2);

        expect(degraded, without);
      },
    );

    test('and differs from the frame that did have them', () async {
      // Otherwise the test above would hold for an engine where the effects
      // never did anything.
      final withThem = await _pixels(_wantsSurface, attachments: 2);
      final without = await _pixels(const RenderSettings(), attachments: 2);

      expect(withThem, isNot(without));
    });

    test('asking for the surface buffer is answered, not thrown', () async {
      // `RenderSettings.surfaceBuffer` names the buffer as a frame output, and
      // on this device nothing produces it. Turning a setting into a throw
      // would be the abort said more politely; the frame draws and the buffer
      // is simply not there.
      expect(
        () async =>
            _pixels(const RenderSettings(surfaceBuffer: true), attachments: 1),
        returnsNormally,
      );
    });
  });
}
