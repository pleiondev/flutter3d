/// The `paintWeights` MCP tool, now that `anim-10`'s own `PaintWeights` is a
/// real `ModelCommand` behind it — `rig_pipeline_mcp_test.dart` already
/// drives one real call to this tool as part of its own end-to-end
/// scenario; this file is about the row this change actually closes: that a
/// stroke is one real, undoable step, not "changed for real, but undo
/// cannot take it back."
///
///     dart test test/paint_weights_mcp_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelTool _toolNamed(String name) =>
    modelTools.firstWhere((ModelTool it) => it.name == name);

Future<Answer> _call(
  ModelSession session,
  String name,
  Map<String, Object?> arguments,
) async => _toolNamed(name).run(session, arguments);

ModelSession _skinnedSession() {
  final mesh = EditMesh.cuboid();
  mesh.beginStep();
  for (var v = 0; v < 8; v++) {
    mesh.setSkin(
      v,
      VertexAttributes(
        joints: Vector4(0, 0, 0, 0),
        weights: Vector4(1, 0, 0, 0),
      ),
    );
  }
  mesh.endStep();

  final project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 1,
        name: 'root',
        geometry: const SocketGeometry(),
        transform: Matrix4.identity(),
      ),
      ModelObject(
        id: 2,
        name: 'tip',
        geometry: const SocketGeometry(),
        transform: Matrix4.identity(),
      ),
      ModelObject(
        id: 10,
        name: 'box',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
        skeletonIndex: 0,
      ),
    ],
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(
        joints: <int>[1, 2],
        inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
      ),
    ],
  );
  return ModelSession(ModelHistory(project));
}

void main() {
  test('a stroke through the tool is a real, undoable step', () async {
    final session = _skinnedSession();

    final painted = await _call(session, 'paintWeights', <String, Object?>{
      'objectId': 10,
      'skeletonIndex': 0,
      'joint': 2,
      'samples': <Map<String, Object?>>[
        <String, Object?>{
          'center': <double>[0.5, -0.5, -0.5],
          'radius': 0.05,
        },
      ],
      'strength': 1.0,
      'mode': 'assign',
    });
    expect(painted.did, isTrue, reason: painted.says);
    expect(session.history.canUndo, isTrue);
    expect(session.history.undoSays, 'paint weights');
    expect(
      session.history.journal.map((c) => c.name),
      contains('paintWeights'),
    );

    final mesh = (session.history.project[10]!.geometry as EditedGeometry).mesh;
    expect(
      weightsOf(mesh, 1).single.joint,
      1,
      reason: 'vertex 1 was assigned fully to local joint 1 (object id 2)',
    );

    expect(session.history.undo(), isTrue);
    final revertedMesh =
        (session.history.project[10]!.geometry as EditedGeometry).mesh;
    expect(
      weightsOf(revertedMesh, 1).single.joint,
      0,
      reason: 'undo puts vertex 1 back on local joint 0, its original bind',
    );
  });

  test('a call the command refuses is a refusal, not a crash', () async {
    final session = _skinnedSession();

    final refused = await _call(session, 'paintWeights', <String, Object?>{
      'objectId': 999,
      'skeletonIndex': 0,
      'joint': 2,
      'samples': <Map<String, Object?>>[
        <String, Object?>{
          'center': <double>[0, 0, 0],
          'radius': 0.05,
        },
      ],
      'strength': 1.0,
    });
    expect(refused.did, isFalse);
    expect(refused.says, contains('999'));
    expect(session.history.canUndo, isFalse);
  });
}
