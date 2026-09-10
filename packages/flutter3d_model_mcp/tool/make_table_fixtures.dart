// Generates test/fixtures/table.* by running the same scenario
// agent_builds_a_table_test.dart drives through the protocol, directly
// against a ModelSession. Run once by hand after a deliberate change to the
// scenario or the writers it exercises; read the diff before committing it.
import 'dart:io';

import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('make_table_fixtures');
  final path = '${dir.path}/table.f3dproj';
  final session = ModelSession.open(path);

  Future<void> run(String name, Map<String, Object?> arguments) async {
    final tool = modelTools.firstWhere((ModelTool t) => t.name == name);
    final answer = await tool.run(session, arguments);
    if (!answer.did) {
      throw StateError('$name refused: ${answer.says}');
    }
  }

  await run('addPrimitive', <String, Object?>{
    'kind': 'box',
    'size': 1.2,
    'at': <double>[0, 1.0, 0],
  });
  await run('rename', <String, Object?>{'id': 1, 'to': 'top'});

  const corners = <List<double>>[
    <double>[0.5, 0.5, 0.5],
    <double>[-0.5, 0.5, 0.5],
    <double>[0.5, 0.5, -0.5],
    <double>[-0.5, 0.5, -0.5],
  ];
  for (var i = 0; i < corners.length; i++) {
    await run('addPrimitive', <String, Object?>{
      'kind': 'cylinder',
      'size': 0.1,
      'segments': 12,
      'at': corners[i],
    });
    await run('rename', <String, Object?>{'id': 2 + i, 'to': 'leg ${i + 1}'});
  }

  await run('addMaterial', <String, Object?>{'materialName': 'oak'});
  for (var id = 1; id <= 5; id++) {
    await run('assignMaterial', <String, Object?>{'id': id, 'to': 0});
  }

  await run('save', const <String, Object?>{});
  await run('export', <String, Object?>{'to': '${dir.path}/table.f3d'});
  await run('export', <String, Object?>{'to': '${dir.path}/table.obj'});
  await run('export', <String, Object?>{'to': '${dir.path}/table.glb'});
  await run('journal', <String, Object?>{'to': '${dir.path}/table.jsonl'});

  const fixtures = 'test/fixtures';
  Directory(fixtures).createSync(recursive: true);
  for (final name in <String>[
    'table.f3dproj',
    'table.f3d',
    'table.obj',
    'table.mtl',
    'table.glb',
    'table.jsonl',
  ]) {
    File('${dir.path}/$name').copySync('$fixtures/$name');
    stderr.writeln('wrote $fixtures/$name');
  }
  dir.deleteSync(recursive: true);
}
