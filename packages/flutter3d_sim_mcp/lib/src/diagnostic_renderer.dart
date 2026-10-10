import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mcp/kit.dart' show ProjectRoot;
import 'package:flutter3d_sim/flutter3d_sim.dart';

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
  final List<FramePass> passes;

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
  DiagnosticRenderer._(
    this._device,
    this._renderer,
    this._scene, {
    this.issues = const <LevelIssue>[],
  });

  /// What the loader said about the level as it read it: a texture it could
  /// not load (or that [open]'s root refused), a field it did not know.
  final List<LevelIssue> issues;

  final CpuDevice _device;
  final Renderer _renderer;
  final Scene _scene;

  static const int width = 320;
  static const int height = 200;

  ///
  /// Every file the level names — a document it includes, a texture — is
  /// read through [root] and refused outside it, the project around
  /// [levelPath] when not given: a level is somebody's file, and its
  /// `"/Users/x/.ssh/id_rsa"` or `"../../../etc/passwd"` is a read the
  /// person opening it never asked for.
  static Future<DiagnosticRenderer> open(
    String levelPath, {
    required EntityRegistry registry,
    ProjectRoot? root,
  }) async {
    final inside = root ?? ProjectRoot.around(levelPath);
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
      readDocument: (request) =>
          File(inside.resolve(request.uri)).readAsString(),
      readAsset: (request) async {
        final path = request.uri.startsWith('/')
            ? request.uri
            : '$assetRoot/${request.uri}';
        return ByteData.sublistView(
          await File(inside.resolve(path)).readAsBytes(),
        );
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
      issues: List<LevelIssue>.unmodifiable(loaded.issues),
    );
  }

  /// How far, in metres, the eye may be from the scene's origin before
  /// [frameFrom] moves the origin to it: a kilometre, where float32 holds a
  /// tenth of a millimetre.
  static const double rebaseBeyond = 1000.0;

  /// One frame from [eye], a place in the world in doubles, looking along
  /// [aim], in [view].
  ///
  /// **The eye goes through the scene's own origin**, not the default one:
  /// past [rebaseBeyond] the scene's origin is first moved to the eye,
  /// rounded to whole metres (`Scene.rebaseAround`'s rule), so the camera
  /// is narrowed to float32 near zero rather than at its distance from the
  /// world's origin, where float32 steps are a metre at 10 000 km.
  Future<DiagnosticFrame> frameFrom({
    required WorldPosition eye,
    required Vector3 aim,
    DiagnosticView view = DiagnosticView.lit,
  }) {
    if (eye.distanceSquaredTo(_scene.origin) > rebaseBeyond * rebaseBeyond) {
      _scene.shiftOrigin(
        WorldPosition(
          eye.x.roundToDouble(),
          eye.y.roundToDouble(),
          eye.z.roundToDouble(),
        ),
      );
    }
    return frame(at: _scene.toScene(eye), aim: aim, view: view);
  }

  /// One frame, from [at] — in the scene's own space, an offset from its
  /// origin — looking at [aim], in [view].
  Future<DiagnosticFrame> frame({
    required Vector3 at,
    required Vector3 aim,
    DiagnosticView view = DiagnosticView.lit,
  }) async {
    final camera = CameraNode(
      projection: const PerspectiveProjection(
        fovY: 1.2,
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
          RenderView(
            camera: camera,
            clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0),
          ),
        ],
        settings: _settingsFor(view),
      );
      final raw = _device.readHdrPixels(result.frame);
      final pixels = await _device.readback(result.frame);
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
