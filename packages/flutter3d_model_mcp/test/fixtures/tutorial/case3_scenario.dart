/// Case 3 — "A lit corner: two assets in one scene": what both
/// `tool/make_case3_fixtures.dart` (which writes the fixtures beside this
/// file) and `tutorial_scenarios_test.dart` (which drives it against a live
/// [ModelSession]) need to agree on.
///
/// **Starts from case 2's own saved project, read the same way a person
/// reopening it would.** [case3StartingProject] reads the committed
/// `case2.f3dproj` fixture through [readProject] — the exact bytes
/// `ModelSession.open` itself would read — rather than re-running
/// [runCase2Scenario] a second time to rebuild an equivalent project by
/// hand: the plan's own row says "case 2's saved project," and this is that
/// file, not a project that merely looks like it. The one thing this
/// approach costs is a dependency on `case2.f3dproj` staying the fixture
/// case 2's own test already pins — exactly the file this repository already
/// keeps honest, since `tutorial_scenarios_test.dart`'s own case-2 group
/// fails first if it ever drifts.
///
/// **Like case 1's own import, `ImportInto` is not on this case's journal.**
/// `ModelSession.import`'s own doc comment already explains why
/// (`ReplaceDocument` is deliberately not journalable — a whole
/// [ModelProject] is not something a `.jsonl` line can hold) — the same
/// reason case 1's own STL import happens before its journal starts, not on
/// it. So [case3StartingProject] merges `BoxTextured.glb` in through the
/// free `importInto` function directly, the same way [case1ImportedProject]
/// builds its own starting point through `fromModelDocument` rather than
/// through a session.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:vector_math/vector_math.dart';

/// Case 2's own project, plus `BoxTextured.glb` merged in as two objects —
/// deterministically object ids 2 and 3, since case 2's own project holds
/// exactly one object (id 1, "vase") and [importInto] renumbers an incoming
/// document's objects starting at `project.nextId`.
///
/// **Two objects, not one, because `BoxTextured.glb` itself has two nodes.**
/// A throwaway probe run once while writing this file (`GltfLoader().load`
/// on the real asset) found the file's single mesh sitting on a child node
/// under an empty root — `doc.nodes.length == 2`, `doc.surfaces.length == 1`
/// — so [fromModelDocument] (which [importInto] reuses wholesale, see that
/// function's own doc comment) gives the merged project object 2, the empty
/// root with no geometry of its own, as the parent of object 3, the box's
/// actual mesh. [case3BoxId] names the *root*: selecting and moving it is
/// what a person clicking the imported asset once in the outliner would do,
/// and carries the mesh child along the same way any parent/child pair in
/// this project already does — `render_project.dart`'s own doc comment:
/// "An object's transform is local to its parent."
Future<ModelProject> case3StartingProject({
  String case2ProjectPath = 'test/fixtures/tutorial/case2.f3dproj',
  String boxGlbPath = '../flutter3d_samples/assets/BoxTextured.glb',
}) async {
  final projectBytes = File(case2ProjectPath).readAsBytesSync();
  final ModelProject caseTwo = switch (readProject(projectBytes)) {
    ProjectOpened(:final project) => project,
    ProjectRefused(:final because) => throw StateError(
      'case2.f3dproj would not open: $because',
    ),
  };

  final boxBytes = File(boxGlbPath).readAsBytesSync();
  final ModelDocument boxDocument = await GltfLoader().load(boxBytes);
  final ImportReport report = importInto(caseTwo, boxDocument);
  if (report.counts.objects != 2) {
    throw StateError(
      'expected BoxTextured.glb to bring in exactly two objects (an empty '
      'root plus its mesh child), got ${report.counts.objects}',
    );
  }
  return report.project;
}

/// The object id [case3StartingProject] gives the imported box's own root —
/// see that function's own doc comment for why this is a fixed number
/// rather than something this file re-derives every time it is read.
const int case3BoxId = 2;

/// Every step case 3's own page (`cloud/server/content/learn/modeler/
/// 03-a-lit-corner.md`) walks through, run against [session] once it holds
/// [case3StartingProject]'s result.
///
/// **The `select` call is the same step `tut-05` fixed, now checked at the
/// object level.** `ModelSession.select` runs a real `SelectElements`
/// command through `ModelHistory.run` now, at either object or
/// mesh-element level — case 2 was the first case to depend on that at
/// *mesh*-element level; this is the first to depend on it at the plain
/// object level `MoveBy`/`RotateBy` need. A person dragging the gizmo, or
/// an agent calling `select` then `run` over MCP, reaches this scenario's
/// own fixture without trouble, and a cold `CommandJournal.replay` from
/// [case3StartingProject] now reaches the identical place, the same fix
/// `tutorial_scenarios_test.dart`'s own case-2 group already checks.
void runCase3Scenario(ModelSession session) {
  void must(Answer answer, String step) {
    if (!answer.did) throw StateError('$step refused: ${answer.says}');
  }

  // The gizmo and its pivot: pick the box up by its own origin
  // (`TransformPivot.individual` — the vases are not part of this selection,
  // so `median` would land in the same place, but naming the pivot the
  // corner actually wants is the point of this step) and carry it into the
  // corner beside the shelf, then turn it to face into that corner.
  //
  // **Past the end of the shelf, at x = 3.** Case 2's array puts three vases
  // at 0, 0.9 and 1.8, and this used to move the box to 1.3, between the
  // second and the third. Nobody saw it, because the project file did not
  // carry a modifier stack: case 2 saved a shelf, this case opened one vase,
  // and the box sat beside it in every picture. The file carries the stack
  // now, so this case opens what case 2 says it saved.
  must(session.select(objects: <int>[case3BoxId]), 'select the box');
  must(
    session.run(MoveBy(Vector3(3.0, 0.5, -0.4))),
    'move the box into the corner',
  );
  must(
    session.run(
      RotateBy(
        axis: Vector3(0, 1, 0),
        radians: 0.6,
        pivot: TransformPivot.individual,
      ),
    ),
    'turn the box to face the corner',
  );

  // Scene mode: a source, its shadow, an environment and a post setting —
  // T3.4's own four panels (sources/shadows/environment/post), each set
  // through the real command its panel already runs.
  must(session.run(const AddLight(type: ProjectLightType.point)), 'addLight');
  must(
    session.run(
      SetLightTransform(
        index: 0,
        // Between the last vase and the box, where it lights both.
        to: Matrix4.translation(Vector3(2.4, 1.4, 0.9)),
      ),
    ),
    'setLightTransform',
  );
  must(
    session.run(
      const SetLightField(
        index: 0,
        field: 'color',
        value: <double>[1.0, 0.92, 0.78],
      ),
    ),
    'setLightField(color)',
  );
  must(
    session.run(const SetLightField(index: 0, field: 'intensity', value: 4.5)),
    'setLightField(intensity)',
  );
  must(
    session.run(
      const SetLightField(index: 0, field: 'castsShadow', value: true),
    ),
    'setLightField(castsShadow)',
  );
  must(
    session.run(const SetSceneLightingField(field: 'shadows', value: true)),
    'setSceneLightingField(shadows)',
  );
  must(
    session.run(
      const SetSceneLightingField(field: 'ambientIntensity', value: 0.12),
    ),
    'setSceneLightingField(ambientIntensity)',
  );
  must(
    session.run(const SetSceneLightingField(field: 'exposure', value: 1.25)),
    'setSceneLightingField(exposure)',
  );
  must(
    session.run(
      const SetSceneLightingField(field: 'bloomEnabled', value: true),
    ),
    'setSceneLightingField(bloomEnabled)',
  );
  must(
    session.run(const SetEnvironment(SceneEnvironmentPreset.studio)),
    'setEnvironment',
  );
}
