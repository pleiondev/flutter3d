/// Reading a level document into something playable: brushes become mesh
/// nodes, lights become light nodes, and a shared mesh cache uploads each
/// repeated shape once.
///
/// Quoted by `level_loader.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class LevelLoaderDemo extends ShowcaseDemo {
  late LoadedLevel _loaded;
  late SharedMeshes _shared;

  // #region document
  static Level _document() => Level(
    name: 'room',
    brushes: <Brush>[
      Brush(centre: Vector3(0, -0.5, 0), size: Vector3(4, 1, 4)),
    ],
    lights: <LevelLight>[
      LevelLight(position: Vector3(0, 3, 0), intensity: 5.0, range: 10.0),
    ],
  );
  // #endregion document

  @override
  Future<void> prepare(DemoContext context) async {
    // #region build
    _loaded = await const LevelLoader().build(
      _document(),
      device: context.device,
      registry: EntityRegistry(const <EntityKind>[]),
    );
    // #endregion build

    // #region shared
    // Three torch posts that all ask the cache for the same box, uploaded
    // once and reused by all three nodes.
    _shared = SharedMeshes(context.device);
    for (var i = 0; i < 3; i++) {
      final mesh = _shared.box(Vector3(0.2, 1.0, 0.2));
      final post = MeshNode(
        mesh,
        Material(name: 'post', baseColor: Vector4(0.4, 0.3, 0.2, 1.0)),
      )..setPosition(-1.0 + i.toDouble(), 0.0, 1.5);
      _loaded.scene.add(post);
    }
    // #endregion shared
  }

  @override
  Scene build(DemoContext context) => _loaded.scene;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the loaded level was not drawn');
    }
    if (_loaded.brushNodes.length != 1) {
      throw StateError(
        'the one brush in the document should become one '
        'mesh node',
      );
    }
    if (_loaded.issues.isNotEmpty) {
      throw StateError(
        'a clean document should load with no issues, got '
        '${_loaded.issues}',
      );
    }
  }
}
