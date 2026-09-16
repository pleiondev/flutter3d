// Generates test/fixtures/tutorial/case6.* by running the scenario
// `case6_scenario.dart` describes, and renders the one real headless
// "expected result" frame the case's own page embeds.
// Run once by hand after a deliberate change to the scenario or the writers
// it exercises; read the diff before committing the new fixtures.
//
// `tut-22` (`doc/modeler-tutorial-gaps.md`): 02-final-material.png was
// found to differ, deterministically, from a clean regenerate of the same
// HEAD — not because renderProject is nondeterministic (it isn't; see
// `render_project_test.dart`'s own `tut-22` group), but because `tut-07`'s
// own commit moved bloom's and shadows' defaults onto `SceneLighting`'s own
// (see `render_project.dart`'s doc comment) and this case never sets its
// own lighting at all, so the PNG quietly went stale without anyone
// regenerating it. Regenerated deliberately as part of `tut-22`'s own fix.
//
//     dart run tool/make_case6_fixtures.dart
import 'dart:io';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

import '../test/fixtures/tutorial/case1_scenario.dart';
import '../test/fixtures/tutorial/case6_scenario.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Future<void> _renderTo(ModelProject project, String path) async {
  final png = await renderProject(
    RenderRequest(
      project: project,
      view: RenderProjectView.iso,
    ),
    deviceFactory: _cpuDevice,
  );
  File(path).writeAsBytesSync(png);
  stderr.writeln('wrote $path');
}

/// The same five-by-seven glyph table `make_case4_fixtures.dart`'s own doc
/// comment already explains copying rather than sharing — see that file for
/// why; this is the fifth copy in the tutorial fixture tools.
Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('make_case6_fixtures');
  final path = '${dir.path}/case6.f3dproj';

  final imported = await case1ImportedProject();
  final session = ModelSession(ModelHistory(imported), path: path);
  await runCase6Scenario(session);

  final readiness = ExportReadiness.check(session.project);
  stderr.writeln('readiness: ${readiness.says}');

  final saved = session.save(path);
  if (!saved.did) throw StateError('save refused: ${saved.says}');
  final exported = session.export('${dir.path}/case6.glb');
  if (!exported.did) throw StateError('export refused: ${exported.says}');
  // Both the agent's own five tool calls and the person's own roughness
  // edit (straight through `session.history.run`, never through
  // `ModelSession.run`'s own tool surface) land here now — `ModelHistory
  // .run` itself records to the attached journal regardless of the door
  // a caller came in through (`tut-15`, closed).
  final journaled = session.journal('${dir.path}/case6.jsonl');
  if (!journaled.did) throw StateError('journal refused: ${journaled.says}');

  const fixtures = 'test/fixtures/tutorial';
  Directory(fixtures).createSync(recursive: true);
  for (final name in <String>['case6.f3dproj', 'case6.glb', 'case6.jsonl']) {
    File('${dir.path}/$name').copySync('$fixtures/$name');
    stderr.writeln('wrote $fixtures/$name');
  }

  final assetDir = Directory(
    '../../cloud/server/web/assets/learn/modeler/an-agent-beside-you',
  )..createSync(recursive: true);

  // The one real render: this exact mixed-authorship project — case 1's
  // teapot, the agent's own baseColor/metallic, the person's own roughness
  // (0.35, not the agent's 0.28 from case 1) — through the same
  // `renderProject` every other case's own reference picture comes from.
  await _renderTo(session.project, '${assetDir.path}/02-final-material.png');

  // Screen 26 ("Сеанс агента") used to be a text-labelled placeholder
  // written here, there being no live screen to point a camera at. There is
  // one now, and it is photographed where every other screen of the editor
  // is: `apps/flutter3d_modeler/test/tutorial_case_screenshots_test.dart`,
  // with a real client on the other end of the port.

  dir.deleteSync(recursive: true);
}
