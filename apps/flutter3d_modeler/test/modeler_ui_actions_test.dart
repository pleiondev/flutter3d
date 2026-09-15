/// [ModelerUiActions] — `mcp-16d`'s own `ui.*` tools, asked without pumping
/// a screen or a socket. `modeler_cubit_test.dart`'s own reason applies
/// here: every method is a state transition worth writing down as a
/// sentence, so this reaches [ModelerUiActions] straight, over a real
/// [ModelerCubit] with a document open, the software rasteriser standing in
/// for a window the same way that file's own `opened()` does.
///
///     flutter test test/modeler_ui_actions_test.dart
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/modeler_ui_actions.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A cubit with one cube open, drawn by the software rasteriser — no GPU,
/// no window.
ModelerCubit _opened() {
  final it = cpuTestDevice(width: 8, height: 8);
  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'a',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
    ),
  );
  final history = ModelHistory(project);
  final stage = ModelerStage.fromProject(
    device: it.device,
    project: history.project,
  );
  return ModelerCubit()..opened(
    history,
    renderer: Renderer.create(device: it.device),
    stage: stage,
  );
}

ModelerReady _ready(ModelerCubit cubit) => cubit.state as ModelerReady;

/// [openExportDialog]/[openLatheDialog] count their own calls rather than
/// doing anything — [ModelerUiActions.openDialog] does not wait for either
/// to finish, so the count is all a test not pumping a real dialog can ask
/// about.
final class _Counters {
  int export = 0;
  int lathe = 0;
}

ModelerUiActions _actions(ModelerCubit cubit, _Counters counters) =>
    ModelerUiActions(
      cubit: cubit,
      openExportDialog: () async => counters.export++,
      openLatheDialog: () async => counters.lathe++,
    );

void main() {
  group('setMode', () {
    test('a valid name changes ModelerReady.mode', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).setMode('animation');

      expect(answer.did, isTrue);
      expect(_ready(cubit).mode, ModelerMode.animation);
    });

    test('an invalid name refuses cleanly, changing nothing', () {
      final cubit = _opened();
      final before = _ready(cubit).mode;

      final answer = _actions(cubit, _Counters()).setMode('not-a-mode');

      expect(answer.did, isFalse);
      expect(_ready(cubit).mode, before);
    });

    test('ux-07: a mode this build has not made yet refuses, and names it', () {
      for (final ModelerMode target in ModelerMode.values) {
        if (target.ready) continue;
        final cubit = _opened();
        final before = _ready(cubit).mode;

        final answer = _actions(cubit, _Counters()).setMode(target.name);

        // The live run asked for `uv` and was told "mode set to uv". The
        // mode did change, the screen showed a mode nothing has built, and
        // an agent driving a screenshot script had no way to know it was
        // looking at nothing.
        //
        // Mutation: leave the gate out, which is what this was. Every one of
        // these answers `did: true` and the mode really moves.
        expect(answer.did, isFalse, reason: '${target.name} was accepted');
        expect(answer.says, contains(target.name));
        expect(_ready(cubit).mode, before);
      }
    });

    test('and every ready mode is still reachable', () {
      for (final ModelerMode target in ModelerMode.values) {
        if (!target.ready) continue;
        final cubit = _opened();

        final answer = _actions(cubit, _Counters()).setMode(target.name);

        // The other half, so the gate above cannot be "refuse everything".
        expect(answer.did, isTrue, reason: '${target.name} was refused');
        expect(_ready(cubit).mode, target);
      }
    });
  });

  group('setSubmode', () {
    test('a valid name changes the submode', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).setSubmode('edge');

      expect(answer.did, isTrue);
      expect(_ready(cubit).submode, MeshSubmode.edge);
    });

    test('an invalid name refuses cleanly', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).setSubmode('not-a-submode');

      expect(answer.did, isFalse);
      expect(_ready(cubit).submode, MeshSubmode.vertex);
    });

    // `ui-40d`'s own widening: a name from either submode enum reaches the
    // matching one, `MeshSubmode` tried first.
    test('an animation submode name changes the animation submode', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).setSubmode('weights');

      expect(answer.did, isTrue);
      expect(_ready(cubit).animationSubmode, AnimationSubmode.weights);
    });
  });

  group('setTool', () {
    test('lights the tool rail id, the same as ModelerCubit.tool', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).setTool('object.select');

      expect(answer.did, isTrue);
      expect(_ready(cubit).tool, 'object.select');
    });

    test('a null id clears it', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).setTool(null);

      expect(answer.did, isTrue);
      expect(_ready(cubit).tool, isNull);
    });
  });

  group('standardView', () {
    test('a valid name points the camera', () {
      final cubit = _opened();
      final stage = _ready(cubit).stage;
      expect(stage.orbit.isTurning, isFalse);

      final answer = _actions(cubit, _Counters()).standardView('right');

      expect(answer.did, isTrue);
      // `lookFrom` animates rather than snapping — a turn now in progress is
      // what shows this reached `OrbitController.animateTo` at all.
      expect(stage.orbit.isTurning, isTrue);
    });

    test('an invalid name refuses cleanly', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).standardView('diagonal');

      expect(answer.did, isFalse);
    });
  });

  test('frameSubject frames the stage', () {
    final cubit = _opened();
    final answer = _actions(cubit, _Counters()).frameSubject();

    expect(answer.did, isTrue);
  });

  group('openDialog', () {
    test('"export" calls the export dialog callback', () async {
      final cubit = _opened();
      final counters = _Counters();

      final answer = _actions(cubit, counters).openDialog('export');
      expect(answer.did, isTrue);
      // The callback is not awaited by `openDialog` itself — give the
      // microtask it fired a turn to run before counting it.
      await Future<void>.delayed(Duration.zero);
      expect(counters.export, 1);
      expect(counters.lathe, 0);
    });

    test('"lathe" calls the lathe dialog callback', () async {
      final cubit = _opened();
      final counters = _Counters();

      final answer = _actions(cubit, counters).openDialog('lathe');
      expect(answer.did, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(counters.lathe, 1);
      expect(counters.export, 0);
    });

    test('"autorig" and "preview" refuse cleanly — not built here yet', () {
      final cubit = _opened();
      final counters = _Counters();

      expect(_actions(cubit, counters).openDialog('autorig').did, isFalse);
      expect(_actions(cubit, counters).openDialog('preview').did, isFalse);
      expect(counters.export, 0);
      expect(counters.lathe, 0);
    });

    test('an unknown name refuses cleanly', () {
      final cubit = _opened();
      final answer = _actions(cubit, _Counters()).openDialog('nonsense');

      expect(answer.did, isFalse);
    });
  });

  group('say', () {
    test('reaches the status line ModelerReady.said carries', () {
      final cubit = _opened();

      final answer = _actions(cubit, _Counters()).say('step 3: add a lathe');

      expect(answer.did, isTrue);
      expect(_ready(cubit).said, 'step 3: add a lathe');
    });

    test('is marked important, surviving a routine clear', () {
      final cubit = _opened();
      _actions(cubit, _Counters()).say('caption');

      // A routine clear (`say(null)`, unmarked) is what a selection change
      // fires — it must leave an important sentence alone.
      cubit.say(null);

      expect(_ready(cubit).said, 'caption');
    });
  });

  test('every action refuses cleanly with no document open', () {
    final cubit = ModelerCubit();
    final counters = _Counters();
    final actions = _actions(cubit, counters);

    expect(actions.setMode('animation').did, isFalse);
    expect(actions.setSubmode('edge').did, isFalse);
    expect(actions.setTool('x').did, isFalse);
    expect(actions.standardView('front').did, isFalse);
    expect(actions.frameSubject().did, isFalse);
    expect(actions.openDialog('export').did, isFalse);
    expect(actions.say('hi').did, isFalse);
    expect(counters.export, 0);
  });
}
