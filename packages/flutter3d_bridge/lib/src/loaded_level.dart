import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'visibility_culler.dart';

/// A loaded level, in the two forms the game needs it.
///
/// One authored document produces both, which is the point: geometry the player
/// can see and geometry the player can walk into are generated from the same
/// brushes, so they cannot drift apart. Deriving colliders from the rendered
/// triangles instead would work until the first time somebody added a visual
/// detail and made it solid by accident.
final class LoadedLevel {
  LoadedLevel({
    required this.level,
    required this.scene,
    required this.collision,
    required this.issues,
    required this.drawCallCount,
    Map<String, TextureHandle?>? materialTextures,
    List<DeviceMesh>? brushMeshes,
    List<ReflectionProbeNode>? probes,
    this.culler,
  }) : materialTextures = materialTextures ?? const <String, TextureHandle?>{},
       brushMeshes = brushMeshes ?? const <DeviceMesh>[],
       probes = probes ?? const <ReflectionProbeNode>[];

  /// Hides what the camera cannot see, when the level came with a visibility
  /// table that matched its brushes. Null when it did not, and then every
  /// batch is drawn from everywhere, as before there were tables.
  ///
  /// Dropped by `LevelLoader.rebuildBrushes`: a table baked from walls
  /// without holes in them hides rooms a hole has since opened.
  ///
  /// Applied through [cull] rather than directly, which is what keeps it
  /// from hiding a room a probe has not seen yet.
  VisibilityCuller? culler;

  /// The reflection probes the document placed, in [scene] — one per
  /// `reflection_probe` entity, kept rather than rolling.
  final List<ReflectionProbeNode> probes;

  /// Whether every probe has been drawn whole — or never will be, on a device
  /// that builds none, which must not be waited for.
  bool probesCaptured(GraphicsDevice device) =>
      !ReflectionProbeNode.supportedOn(device) ||
      probes.every((ReflectionProbeNode probe) => probe.isCaptured);

  /// Hides what [eye] cannot see, once the level's probes have seen it whole.
  ///
  /// **The culler waits for the probes, and the order is the whole point.**
  /// A kept probe is captured on the first frame it is seen, from where it
  /// stands; a culler applied from the player's cell before that has already
  /// hidden every room but the player's, and the probe in the vault would
  /// capture the vault's walls with nothing behind them. So until every probe
  /// stands, every batch shows, which costs a frame or two of the whole
  /// level and nothing after. Does nothing for a level with no table.
  void cull(Vector3 eye, {required GraphicsDevice device}) {
    final culler = this.culler;
    if (culler == null) return;
    if (probesCaptured(device)) {
      culler.apply(eye);
    } else {
      culler.showAll();
    }
  }

  /// The nodes the brush batches are drawn through, in [scene], so a rebuild
  /// can take them out before putting the new ones in.
  final List<MeshNode> brushNodes = <MeshNode>[];

  final Level level;
  final Scene scene;
  final CollisionWorld collision;

  /// What the validator said. Errors stop the load before this exists, so
  /// anything here is a warning worth showing rather than acting on.
  final List<LevelIssue> issues;

  /// One per material, which is what the brush geometry merges down to.
  final int drawCallCount;

  /// Every map this level loaded, by asset path.
  ///
  /// Kept so anything built after the load — a door, a lift — can be given the
  /// same texture object rather than uploading a second copy of the same file.
  final Map<String, TextureHandle?> materialTextures;

  /// Every mesh the loader uploaded for the level's own geometry.
  ///
  /// Recorded at build so [dispose] can give exactly these back — walking the
  /// scene instead would also find meshes belonging to `SharedMeshes` and to
  /// the models, whose owners release them themselves.
  /// Replaced wholesale by `LevelLoader.rebuildBrushes`, which releases the
  /// old ones first.
  List<DeviceMesh> brushMeshes;

  /// The baked lightmap the brush batches sample, when the level came with
  /// one that matched it. Uploaded by the loader, released by [dispose].
  TextureHandle? lightmap;

  /// Gives the level's own uploads — brush meshes and material maps — back to
  /// [device].
  ///
  /// Call it when the level is over — `RunSession.close` is that moment — and
  /// after the fixtures built on [materialTextures] are gone, because they
  /// share these texture objects rather than copies. The same contract as
  /// `SharedMeshes.dispose`: a no-op release on flutter_gpu, the one real
  /// `gl.delete*` per resource on WebGL2.
  void dispose(GraphicsDevice device) {
    for (final mesh in brushMeshes) {
      device.releaseGeometry(mesh.vertices);
      device.releaseGeometry(mesh.indices);
    }
    for (final texture in materialTextures.values) {
      if (texture != null) device.releaseTexture(texture);
    }
    final map = lightmap;
    if (map != null) device.releaseTexture(map);
  }
}
