/// One tick of the measured camera orbit and the edit-convert-upload churn
/// loop, turned into the one-line report `_onTick` prints — see
/// `main.dart`.
///
///     flutter test test/measurement_runs_test.dart
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/churn_run.dart';
import 'package:flutter3d_modeler/src/measurement_runs.dart';
import 'package:flutter3d_modeler/src/orbit_run.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/fake_graphics_backend.dart';

/// A stage over a single cube, and the device behind it.
({ModelerStage stage, GraphicsDevice device}) staged() {
  final it = fakeTestDevice(width: 8, height: 8);
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  return (
    stage: ModelerStage.fromProject(device: it.device, project: project),
    device: it.device,
  );
}

/// A [ChurnRun] over the stage's own subject node — the same
/// `subject is MeshNode ? subject : …` search `main.dart`'s own `_open` does.
ChurnRun churnFor(({ModelerStage stage, GraphicsDevice device}) made) {
  final subject = made.stage.subject;
  final node = subject is MeshNode
      ? subject
      : subject.children.whereType<MeshNode>().first;
  return ChurnRun(device: made.device, node: node, from: node.mesh.source!);
}

void main() {
  test('a tick with no run asked for never reports, and does not throw', () {
    final runs = MeasurementRuns(what: 'the cube');

    expect(runs.step(1000, null), isNull);
    expect(runs.step(2000, 500), isNull);
  });

  test('an unfinished orbit reports nothing yet', () {
    final made = staged();
    final runs = MeasurementRuns(what: 'the cube')
      ..orbit = OrbitRun(frames: 2, stage: made.stage);

    expect(runs.step(1000, null), isNull);
  });

  test('the finished orbit reports once, naming what was measured and how '
      'long opening took', () {
    final made = staged();
    final runs = MeasurementRuns(what: 'the cube')
      ..openedInMs = 42
      ..orbit = OrbitRun(frames: 1, stage: made.stage);

    final said = runs.step(1000, null);

    expect(said, isNotNull);
    expect(said, contains('orbit: the cube'));
    expect(said, contains('opened in    42 ms'));
    // Mutation: leave `churn:` in the report when no churn ran. A person
    // reading the console would then look for numbers that were never
    // measured.
    expect(said, isNot(contains('churn:')));
  });

  test('the report is delivered once — a further tick answers null again', () {
    final made = staged();
    final runs = MeasurementRuns(what: 'the cube')
      ..orbit = OrbitRun(frames: 1, stage: made.stage);

    final first = runs.step(1000, null);
    final second = runs.step(2000, null);

    expect(first, isNotNull);
    // Mutation: leave `orbit`/`churn` set after the report is built. `_onTick`
    // would then print the same finished run's numbers every frame after.
    expect(second, isNull);
  });

  test('a churn run alongside the orbit is folded into the same report', () {
    final made = staged();
    final runs = MeasurementRuns(what: 'the cube')
      ..churn = churnFor(made)
      ..orbit = OrbitRun(frames: 1, stage: made.stage);

    final said = runs.step(1000, null);

    expect(said, contains('churn:'));
  });
}
