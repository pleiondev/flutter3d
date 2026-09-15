/// Case 1 — "A prop from a scan": what both `tool/make_case1_fixtures.dart`
/// (which writes the fixtures beside this file) and
/// `tutorial_scenarios_test.dart` (which replays them) need to agree on, so
/// the two cannot silently drift apart the way two copies of the same
/// scenario would.
///
///     dart test test/tutorial_scenarios_test.dart
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show importMeshData;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

/// `packages/flutter3d_samples/assets/teapot.stl`, brought in at
/// `ImportUnit.millimetres` (`0.001`) the way
/// `apps/flutter3d_modeler/lib/src/import_plan.dart`'s own import screen
/// would with "mm" chosen, then welded through `importMeshData` the way
/// `files.dart`'s own `_applyImportCleanup` does when the screen's "weld"
/// checkbox is on.
///
/// **This is `ModelSession.import`'s own missing half** (`tut-01`, see
/// `doc/modeler-tutorial-gaps.md`): nothing at the session/MCP layer accepts
/// an `ImportOptions`, so a case that needs units or axis on a fresh import
/// builds its starting project directly from `flutter3d_model_core`'s own
/// import functions instead of through `session.import` — which is also why
/// the import step itself is not on `case1.jsonl`: `ReplaceDocument`
/// (what `session.import` would run) is deliberately not journalable
/// (`command.dart`'s own doc comment), so this case's journal starts *after*
/// import, replayed against the project this function returns rather than
/// against `const ModelProject()`.
Future<ModelProject> case1ImportedProject({
  String stlPath = '../flutter3d_samples/assets/teapot.stl',
}) async {
  final bytes = File(stlPath).readAsBytesSync();
  final document = await StlLoader().load(bytes);
  var project = fromModelDocument(
    document,
    options: const ImportOptions(scale: 0.001),
  );
  for (final object in project.objects) {
    if (object.geometry case ImportedGeometry(:final data)) {
      final (mesh, _, _) = importMeshData(data);
      project = project.withObject(
        object.copyWith(geometry: EditedGeometry(mesh)),
      );
    }
  }
  return project;
}

/// Every step case1's own page (`cloud/server/content/learn/modeler/
/// 01-prop-from-a-scan.md`) walks through, run against [session] — name it,
/// give it a material, and paint it. `Answer.did` is checked after each call
/// the way `make_table_fixtures.dart`'s own `run` helper does.
void runCase1Scenario(ModelSession session) {
  void must(Answer answer, String step) {
    if (!answer.did) throw StateError('$step refused: ${answer.says}');
  }

  must(session.run(const Rename(id: 1, to: 'teapot')), 'rename');
  // Worth calling right after import, per its own tool description — a
  // no-op here (see the case's own page for why), left in so the journal
  // shows the check actually being made rather than skipped.
  session.cleanup();
  must(
    session.run(const AddMaterial(materialName: 'glazed ceramic')),
    'addMaterial',
  );
  must(
    session.run(
      const SetMaterialField(
        index: 0,
        field: 'baseColor',
        value: <double>[0.92, 0.89, 0.82, 1.0],
      ),
    ),
    'setMaterialField(baseColor)',
  );
  must(
    session.run(
      const SetMaterialField(index: 0, field: 'metallic', value: 0.0),
    ),
    'setMaterialField(metallic)',
  );
  must(
    session.run(
      const SetMaterialField(index: 0, field: 'roughness', value: 0.28),
    ),
    'setMaterialField(roughness)',
  );
  must(session.run(const AssignMaterial(id: 1, to: 0)), 'assignMaterial');
}
