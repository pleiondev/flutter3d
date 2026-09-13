import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// Which of the renderer's own debug outputs a frame is asked for — the four
/// ways `RenderSettings` already knows how to answer "why is the frame
/// wrong", and the whole of what this diagnostic adds on top: reading them
/// back as raw floats rather than as a picture nobody who is not looking at
/// it can act on.
///
/// **Not "any pass in the frame graph".** ROADMAP's own phrasing reaches
/// further than this — the output of an arbitrary node, shadow cascades
/// named individually, overdraw. What is here is what `RenderSettings`
/// genuinely exposes today: [lit] is the ordinary frame, [normals] is the
/// surface buffer (octahedral normal in two channels, roughness in the
/// third, view depth in world metres in the fourth — see
/// `packages/flutter3d_shaders/shaders/lib/color.glsl`'s own
/// `WriteSurfaceGeometry`), and [shadowMap]/[staticShadowMap] are the two
/// cube atlases the point-shadow pass fills. A per-node texture, a per-cascade
/// break-out and an overdraw counter are none of them anywhere in
/// `RenderSettings`, and building them is a wider spike than this one.
enum DiagnosticView { lit, normals, shadowMap, staticShadowMap }

RenderSettings _settingsFor(DiagnosticView view) => switch (view) {
  DiagnosticView.lit => const RenderSettings(),
  // Both flags: `surfaceBuffer` is what makes the scene pass write the
  // attachment at all, `showSurfaceBuffer` is what composites it into the
  // frame this renderer hands back — asking for only the second would show
  // whatever the buffer held last, per `RenderSettings.surfaceBuffer`'s own
  // doc.
  DiagnosticView.normals => const RenderSettings(
    surfaceBuffer: true,
    showSurfaceBuffer: true,
  ),
  DiagnosticView.shadowMap => const RenderSettings(showShadowMap: true),
  DiagnosticView.staticShadowMap => const RenderSettings(
    showStaticShadowMap: true,
  ),
};

/// One rendered frame, read back two ways: [png] is what a person or a model
/// looks at, [raw] is what a diagnostic actually computes from — the same
/// texture, before [CpuDevice.readPixels]'s clamp to 8 bits throws away
/// everything a depth or a NaN needed.
final class DiagnosticFrame {
  const DiagnosticFrame({
    required this.view,
    required this.width,
    required this.height,
    required this.png,
    required this.raw,
    required this.passes,
  });

  final DiagnosticView view;
  final int width;
  final int height;
  final Uint8List png;

  /// RGBA floats, row-major from the top — [CpuDevice.readHdrPixels]'s own
  /// promise, unclamped and unconverted.
  final Float32List raw;

  /// One entry per pass the frame graph kept this frame, in order —
  /// `FrameResult.passes`, named rather than re-derived: naming which pass
  /// ran is exactly the question a diagnostic exists to answer, and the
  /// renderer already answers it for free.
  final List<({String name, bool active, int micros})> passes;

  int get _stride => width * 4;

  /// The four raw floats at ([x], [y]), whatever [view] put there.
  Vector4 rawAt(int x, int y) {
    final i = y * _stride + x * 4;
    return Vector4(raw[i], raw[i + 1], raw[i + 2], raw[i + 3]);
  }

  /// The first pixel where any channel is not finite (a NaN or an
  /// infinity), scanning left to right then top to bottom — the "empty
  /// target" ROADMAP asks for is a frame of all zeros, which is finite and
  /// ordinary, and not what this looks for; a target nothing wrote is a
  /// different, and much easier, question a caller can put to [rawAt](0, 0)
  /// once instead.
  ({int x, int y, int channel})? firstNonFinite() {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * _stride + x * 4;
        for (var c = 0; c < 4; c++) {
          if (!raw[i + c].isFinite) return (x: x, y: y, channel: c);
        }
      }
    }
    return null;
  }
}

/// Decodes [DiagnosticView.normals]'s R and G channels back into a unit
/// vector — the exact inverse of `EncodeOctahedral` in
/// `packages/flutter3d_shaders/shaders/lib/color.glsl`, transcribed rather
/// than re-derived so the two cannot silently disagree about which fold a
/// negative Z takes.
Vector3 decodeOctahedralNormal(double r, double g) {
  final fx = r * 2.0 - 1.0;
  final fy = g * 2.0 - 1.0;
  var nx = fx;
  var ny = fy;
  final nz = 1.0 - fx.abs() - fy.abs();
  final t = (-nz).clamp(0.0, 1.0);
  nx += nx >= 0.0 ? -t : t;
  ny += ny >= 0.0 ? -t : t;
  return Vector3(nx, ny, nz)..normalize();
}

/// A level's own scene, drawn with no GPU, in whichever of
/// [DiagnosticView]'s four readings a caller asks for — `par-02`.
///
/// **Genre-agnostic, unlike `flutter3d_sim_mcp`'s own `SimRenderer`.** A
/// frame's normals, depth and NaNs are not a property of any genre, so
/// [open] takes the [EntityRegistry] as a parameter rather than importing
/// one game's own sample vocabulary — the caller (a real host, or this
/// package's own tests) decides what the level is allowed to spawn, and
/// this package never needs to know.
final class DiagnosticRenderer {
  DiagnosticRenderer._(this._device, this._renderer, this._scene);

  final CpuDevice _device;
  final Renderer _renderer;
  final Scene _scene;

  static const int width = 320;
  static const int height = 200;

  static Future<DiagnosticRenderer> open(
    String levelPath, {
    required EntityRegistry registry,
  }) async {
    final it = cpuTestDevice(width: width, height: height);
    const marker = '/assets/levels/';
    final markerAt = levelPath.indexOf(marker);
    final assetRoot = markerAt >= 0
        ? levelPath.substring(0, markerAt)
        : File(levelPath).parent.path;
    final loaded = await LevelLoader().load(
      levelPath,
      device: it.device,
      registry: registry,
      sidecars: false,
      readDocument: (request) => File(request.uri).readAsString(),
      readAsset: (request) async {
        final path = request.uri.startsWith('/')
            ? request.uri
            : '$assetRoot/${request.uri}';
        return ByteData.sublistView(await File(path).readAsBytes());
      },
    );
    return DiagnosticRenderer._(
      it.device,
      Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      ),
      loaded.scene,
    );
  }

  /// One frame, from [at] looking at [aim], in [view].
  Future<DiagnosticFrame> frame({
    required Vector3 at,
    required Vector3 aim,
    DiagnosticView view = DiagnosticView.lit,
  }) async {
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovYRadians: 1.2,
        near: 0.05,
        far: 200.0,
      ),
    )..setPositionFrom(at);
    camera.lookAt(at + aim);
    _scene.add(camera);
    try {
      final result = _renderer.render(
        width: width,
        height: height,
        scene: _scene,
        views: <RenderView>[
          RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
        ],
        settings: _settingsFor(view),
      );
      final raw = _device.readHdrPixels(result.frame);
      final pixels = await _device.readPixels(result.frame);
      if (pixels == null) {
        throw StateError('the frame could not be read back');
      }
      return DiagnosticFrame(
        view: view,
        width: width,
        height: height,
        png: encodePng(pixels.buffer.asUint8List(), width, height),
        raw: raw,
        passes: result.passes,
      );
    } finally {
      _scene.remove(camera);
    }
  }
}
