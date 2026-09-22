/// `renderSnapshot` — `pro-rn-04`: a full-quality picture at a size a
/// caller chooses, through `pro-rn-02`'s own tiled job.
///
///     dart test test/render_snapshot_tool_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelSession opened({bool empty = false}) => ModelSession(
  ModelHistory(
    ModelProject(
      objects: empty
          ? const <ModelObject>[]
          : <ModelObject>[
              ModelObject(
                id: 1,
                name: 'cube',
                geometry: EditedGeometry(
                  EditMesh.cuboid(size: Vector3(2, 2, 2)),
                ),
                transform: Matrix4.identity(),
              ),
            ],
      nextId: 2,
    ),
  ),
);

Future<PictureAnswer> snapshot(
  ModelSession session,
  Map<String, Object?> arguments,
) async => renderSnapshotTool.run(session, arguments);

void main() {
  test('a 96×64 snapshot is a real picture of that size', () async {
    final PictureAnswer answer = await snapshot(opened(), <String, Object?>{
      'width': 96,
      'height': 64,
    });

    expect(answer.did, isTrue, reason: answer.says);
    final decoded = decodePng(answer.png!);
    // **The row's own "a 96×64 snapshot = `renderFrame`".** Mutation: hand
    // back the cheap `render` tool's own square. The caller asked for a
    // shape and got another one, which is the thing a snapshot is for.
    expect(decoded!.width, 96);
    expect(decoded.height, 64);
    expect(answer.says, contains('96×64'));
  });

  test('and it is not blank: the cube is in shot', () async {
    final PictureAnswer answer = await snapshot(opened(), <String, Object?>{
      'width': 96,
      'height': 64,
    });
    final decoded = decodePng(answer.png!)!;
    final Set<int> reds = <int>{
      for (var i = 0; i < decoded.width * decoded.height; i++)
        decoded.rgba[i * 4],
    };
    // A framed camera puts the model in the middle of the frame, so the
    // picture has more than one shade in it. A camera pointed at nothing
    // would give exactly one.
    expect(reds.length, greaterThan(1));
  });

  test('tiles that do not divide the frame are refused by name', () async {
    final PictureAnswer answer = await snapshot(opened(), <String, Object?>{
      'width': 100,
      'height': 64,
      'tiles': 3,
    });
    expect(answer.did, isFalse);
    expect(answer.says, contains('3 tiles'));
    expect(answer.png, isNull);
  });

  test('four tiles stitch back into one frame of the asked size', () async {
    final PictureAnswer answer = await snapshot(opened(), <String, Object?>{
      'width': 64,
      'height': 64,
      'tiles': 2,
    });
    expect(answer.did, isTrue, reason: answer.says);
    final decoded = decodePng(answer.png!)!;
    expect(decoded.width, 64);
    expect(decoded.height, 64);
    expect(answer.says, contains('4 tiles'));
  });

  test('and an empty project refuses rather than drawing nothing', () async {
    final PictureAnswer answer = await snapshot(
      opened(empty: true),
      <String, Object?>{},
    );
    expect(answer.did, isFalse);
    expect(answer.png, isNull);
    expect(answer.says, contains('no objects'));
  });
}
