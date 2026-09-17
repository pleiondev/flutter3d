// Generates test/fixtures/tutorial/case1.* by running the scenario
// `case1_scenario.dart` describes — the same shape make_table_fixtures.dart
// already uses for `table.*`. Also renders the two headless "expected
// result" frames the case's own page embeds under
// cloud/server/web/assets/learn/modeler/prop-from-a-scan/. Run once by hand
// after a deliberate change to the scenario or the writers it exercises;
// read the diff before committing it.
//
//     dart run tool/make_case1_fixtures.dart
import 'dart:io';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

import '../test/fixtures/tutorial/case1_scenario.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Future<void> _renderTo(ModelProject project, String path) async {
  final png = await renderProject(
    RenderRequest(project: project, view: RenderProjectView.iso),
    deviceFactory: _cpuDevice,
  );
  File(path).writeAsBytesSync(png);
  stderr.writeln('wrote $path');
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('make_case1_fixtures');
  final path = '${dir.path}/case1.f3dproj';

  final imported = await case1ImportedProject();
  final renderDir = Directory(
    '../../cloud/server/web/assets/learn/modeler/prop-from-a-scan',
  );
  renderDir.createSync(recursive: true);
  // The raw import's own "expected result" frame — undecorated, no material
  // beyond the loader's own default grey.
  await _renderTo(imported, '${renderDir.path}/05-imported-raw.png');

  final session = ModelSession(ModelHistory(imported), path: path);
  runCase1Scenario(session);

  final readiness = ExportReadiness.check(session.project);
  stderr.writeln('readiness: ${readiness.says}');

  final saved = session.save(path);
  if (!saved.did) throw StateError('save refused: ${saved.says}');
  final exported = session.export('${dir.path}/case1.glb');
  if (!exported.did) throw StateError('export refused: ${exported.says}');
  final journaled = session.journal('${dir.path}/case1.jsonl');
  if (!journaled.did) throw StateError('journal refused: ${journaled.says}');

  await _renderTo(session.project, '${renderDir.path}/06-final-material.png');

  const fixtures = 'test/fixtures/tutorial';
  Directory(fixtures).createSync(recursive: true);
  for (final name in <String>['case1.f3dproj', 'case1.glb', 'case1.jsonl']) {
    File('${dir.path}/$name').copySync('$fixtures/$name');
    stderr.writeln('wrote $fixtures/$name');
  }
  dir.deleteSync(recursive: true);
}
