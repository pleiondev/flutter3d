/// Case 1 — "A prop from a scan": what both `tool/make_case1_fixtures.dart`
/// (which writes the fixtures beside this file) and
/// `tutorial_scenarios_test.dart` (which replays them) need to agree on, so
/// the two cannot silently drift apart the way two copies of the same
/// scenario would.
///
///     dart test test/tutorial_scenarios_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';

/// `packages/flutter3d_samples/assets/teapot.stl`, brought in through
/// `ModelSession.import` at `ImportUnit.millimetres` (`0.001`) with `weld`
/// on — the identical choice `apps/flutter3d_modeler/lib/src/
/// import_plan.dart`'s own import screen offers a person choosing "mm" and
/// ticking "weld coincident vertices".
///
/// **Goes through the real MCP surface now that `tut-01` is fixed** (see
/// `doc/modeler-tutorial-gaps.md`): `ModelSession.import` used to take only
/// a path, so this case built its starting project directly from
/// `flutter3d_model_core`'s own `fromModelDocument`/`importMeshData`
/// instead. The import step is still not on `case1.jsonl` — `ReplaceDocument`
/// (what `session.import` runs) is deliberately not journalable
/// (`command.dart`'s own doc comment) — so this case's journal still starts
/// *after* import, replayed against the project this function returns
/// rather than against `const ModelProject()`.
Future<ModelProject> case1ImportedProject({
  String stlPath = '../flutter3d_samples/assets/teapot.stl',
}) async {
  final session = ModelSession(ModelHistory(const ModelProject()));
  final answer = await session.import(
    stlPath,
    options: const ImportOptions(scale: 0.001),
    weld: true,
  );
  if (!answer.did) throw StateError('import refused: ${answer.says}');
  return session.history.project;
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
