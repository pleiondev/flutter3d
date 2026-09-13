import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_game_shooter/sample.dart' show sampleRegistry;
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityRegistry;
import 'package:vector_math/vector_math.dart';

/// A picture of the room, drawn with no GPU — [SimSession.frame]'s other
/// half.
///
/// **Loaded once per level, separately from [Staged].** [Staged] is built
/// from `Level.addTo`, which is collision only — geometry a body can push
/// against, nothing a renderer can draw. A picture needs the level's own
/// scene, which is [LevelLoader]'s job, and [LevelLoader] wants a
/// [GraphicsDevice] and a way to find a level's textures on disk that this
/// process's own working directory already answers for — the same
/// `readAsset`/`readDocument` seam `apps/flutter3d_editor` reads a level
/// from outside any bundle through.
final class SimRenderer {
  SimRenderer._(this._device, this._renderer, this._scene);

  final CpuDevice _device;
  final Renderer _renderer;
  final Scene _scene;

  static const int width = 320;
  static const int height = 200;

  /// [registry] is what turns a level's own entity kinds into the things a
  /// scene actually draws — [sampleRegistry] by default, the same roster
  /// [SimSession] steps through, so a monster [snapshot] can name is a
  /// monster [frame] can show. Overridable the same way
  /// `flutter3d_render_mcp`'s own `open` takes one, for a caller with a
  /// different roster, or none.
  static Future<SimRenderer> open(
    String levelPath, {
    EntityRegistry? registry,
  }) async {
    final it = cpuTestDevice(width: width, height: height);
    // A material names its textures relative to the application's own asset
    // root (`assets/textures/wall_albedo.jpg`), not to wherever the level
    // document itself happens to sit — this repository's own convention
    // puts every level under `<app root>/assets/levels/`, so finding that
    // marker in [levelPath] is what turns one back into the other.
    const marker = '/assets/levels/';
    final markerAt = levelPath.indexOf(marker);
    final assetRoot = markerAt >= 0
        ? levelPath.substring(0, markerAt)
        : File(levelPath).parent.path;
    final loaded = await LevelLoader().load(
      levelPath,
      device: it.device,
      registry: registry ?? sampleRegistry(),
      sidecars: false,
      readDocument: (request) => File(request.uri).readAsString(),
      readAsset: (request) async {
        final path = request.uri.startsWith('/')
            ? request.uri
            : '$assetRoot/${request.uri}';
        return ByteData.sublistView(await File(path).readAsBytes());
      },
    );
    return SimRenderer._(
      it.device,
      Renderer.create(
        device: it.device,
        fallbackAlbedo: it.albedo,
        fallbackNormal: it.normal,
      ),
      loaded.scene,
    );
  }

  /// A PNG, looking from [at] in the direction [aim] points — both the
  /// player's own `eye()`/`aim()`, unless a caller wants a different vantage
  /// than whoever is standing in the room.
  Future<Uint8List> frame({required Vector3 at, required Vector3 aim}) async {
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
        settings: const RenderSettings(),
      );
      final pixels = await _device.readPixels(result.frame);
      if (pixels == null) {
        throw StateError('the frame could not be read back');
      }
      return encodePng(pixels.buffer.asUint8List(), width, height);
    } finally {
      _scene.remove(camera);
    }
  }
}
