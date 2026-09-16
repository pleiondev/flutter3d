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
import 'package:flutter3d_modeler/src/mcp_ui_actions.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/modeler_ui_actions.dart';
import 'package:flutter3d_modeler/src/settings.dart' show Workspace;
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
  return ModelerCubit()
    ..opened(
      history,
      renderer: Renderer.create(device: it.device),
      stage: stage,
    )
    // `ux-37`: these tests are about modes, not about which workspace offers
    // them, and Essential — the default a first launch gets — offers three of
    // the five. `workspace_test.dart` is where the gate itself is checked.
    ..workspace(Workspace.full);
}

ModelerReady _ready(ModelerCubit cubit) => cubit.state as ModelerReady;

/// [openExportDialog]/[openLatheDialog] count their own calls rather than
/// doing anything — [ModelerUiActions.openDialog] does not wait for either
/// to finish, so the count is all a test not pumping a real dialog can ask
/// about.
final class _Counters {
  int export = 0;
  int lathe = 0;

  /// `ux-36`: the two `ui.openDialog` used to refuse, both built since.
  int autorig = 0;
  int preview = 0;

  /// `ux-25`: every id `run_command` pressed, in order.
  final List<String> ran = <String>[];
}

ModelerUiActions _actions(ModelerCubit cubit, _Counters counters) =>
    ModelerUiActions(
      cubit: cubit,
      openExportDialog: () async => counters.export++,
      openLatheDialog: () async => counters.lathe++,
      openAutorigDialog: () async => counters.autorig++,
      openGamePreview: () async => counters.preview++,
      runTool: counters.ran.add,
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

    // `ux-20`'s own acceptance. The live run asked for face level and then
    // for everything, and got the object: the level was set and the
    // selection's *mode* was not, because until this row the only thing that
    // ever set it was a click in the viewport.
    test('it puts the document into mesh mode, not only at the level', () {
      final cubit = _opened();
      // An object picked, the way a person picks one before dropping into
      // its mesh — there has to be something with topology to point at.
      _ready(cubit).history.selection = ProjectSelection(objects: <int>[1]);
      final answer = _actions(cubit, _Counters()).setSubmode('face');

      expect(answer.did, isTrue);
      final ProjectSelection selection = _ready(cubit).selection;
      expect(selection.mode, SelectionMode.mesh);
      expect(selection.level, ElementLevel.face);

      expect(_ready(cubit).history.run(const SelectAll()), isNull);
      // Mutation: leave it an object-mode selection. `selectAll` then selects
      // the object, which is what the live run watched happen.
      expect(_ready(cubit).selection.mode, SelectionMode.mesh);
      expect(_ready(cubit).selection.elements, hasLength(6));
    });

    test('with nothing selected it sets the level and says nothing else', () {
      final cubit = _opened();
      expect(_actions(cubit, _Counters()).setSubmode('face').did, isTrue);
      // Mutation: claim mesh mode anyway. A mesh selection of no object
      // refuses every command with a sentence about the wrong thing — "no
      // mesh to edit" rather than "nothing is selected".
      expect(_ready(cubit).selection.mode, SelectionMode.object);
      expect(_ready(cubit).selection.level, ElementLevel.face);
    });

    test('and does so even for the level that was already live', () {
      final cubit = _opened();
      _ready(cubit).history.selection = ProjectSelection(objects: <int>[1]);
      // `vertex` is where a document opens, so this is the call an agent
      // makes first — and returning early on it was how a selection ended up
      // at the right level in the wrong mode.
      final answer = _actions(cubit, _Counters()).setSubmode('vertex');

      expect(answer.did, isTrue);
      expect(_ready(cubit).selection.mode, SelectionMode.mesh);
      expect(_ready(cubit).selection.level, ElementLevel.vertex);
    });
  });

  group('screenshot', () {
    // `ux-44`. The picture itself is a `RepaintBoundary` at the root of the
    // screen — `ready_parts.dart`'s own `_screen` — and what this file can
    // ask about is the seam: a server with no window says so rather than
    // answering with an empty picture, and one with a window hands the bytes
    // through.
    test(
      'with no window it refuses rather than answering with nothing',
      () async {
        final UiPicture shot = await _actions(
          _opened(),
          _Counters(),
        ).screenshot();
        expect(shot.did, isFalse);
        expect(shot.png, isNull);
        expect(shot.says, contains('no window'));
      },
    );

    test('a capture that finds nothing laid out says that instead', () async {
      final ModelerUiActions actions = ModelerUiActions(
        cubit: _opened(),
        openExportDialog: () async {},
        openLatheDialog: () async {},
        openAutorigDialog: () async {},
        openGamePreview: () async {},
        runTool: (_) {},
        captureWindow: () async => null,
      );
      final UiPicture shot = await actions.screenshot();
      expect(shot.did, isFalse);
      expect(shot.says, contains('laid out'));
    });

    test('and bytes come back as bytes', () async {
      final ModelerUiActions actions = ModelerUiActions(
        cubit: _opened(),
        openExportDialog: () async {},
        openLatheDialog: () async {},
        openAutorigDialog: () async {},
        openGamePreview: () async {},
        runTool: (_) {},
        captureWindow: () async => <int>[1, 2, 3, 4],
      );
      final UiPicture shot = await actions.screenshot();
      expect(shot.did, isTrue);
      expect(shot.png, <int>[1, 2, 3, 4]);
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

    test('ux-36: "autorig" and "preview" open, since both are built', () {
      final cubit = _opened();
      final counters = _Counters();
      final ModelerUiActions actions = _actions(cubit, counters);

      // **This used to answer "not built in this app yet".** It was true
      // when it was written, and stopped being true when `S8` built the
      // auto-rig dialog and `S9` the game preview — a refusal nobody
      // re-read, which a screenshot script reads as a thing this
      // application cannot do.
      expect(actions.openDialog('autorig').did, isTrue);
      expect(actions.openDialog('preview').did, isTrue);
      expect(counters.autorig, 1);
      expect(counters.preview, 1);
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
    expect(actions.runCommand('object.duplicate').did, isFalse);
    expect(counters.export, 0);
    expect(counters.ran, isEmpty);
  });

  group('ux-25: run_command', () {
    test('presses the same button the rail and the palette do', () {
      final cubit = _opened();
      final counters = _Counters();

      final answer = _actions(cubit, counters).runCommand('mesh.triangulate');

      // Mutation: run the command here rather than through the screen's own
      // `_ranTool`. The ones that arm a tool, open a dialog or need a mesh
      // then behave differently for an agent than for a person, which is the
      // one thing "one table for both" exists to prevent.
      expect(answer.did, isTrue);
      expect(counters.ran, <String>['mesh.triangulate']);
    });

    test('an id the editor does not have refuses and presses nothing', () {
      final cubit = _opened();
      final counters = _Counters();

      final answer = _actions(cubit, counters).runCommand('mesh.explode');

      expect(answer.did, isFalse);
      expect(answer.says, contains('mesh.explode'));
      expect(counters.ran, isEmpty);
    });

    test('the catalogue names every tool once, with its mode', () {
      final List<({String id, String label, String mode})> all = _actions(
        _opened(),
        _Counters(),
      ).commands();

      final ids = all.map(
        (({String id, String label, String mode}) it) => it.id,
      );
      expect(ids.toSet().length, ids.length, reason: 'no id twice');
      expect(ids, contains('mesh.bevel'));
      expect(ids, contains('object.duplicate'));
      expect(
        all
            .firstWhere(
              (({String id, String label, String mode}) it) =>
                  it.id == 'mesh.bevel',
            )
            .mode,
        'mesh',
      );
    });
  });

  group('ux-26: get_console', () {
    test('answers with what the session has said, in order', () {
      final cubit = _opened();
      var at = DateTime.utc(2026, 9, 16, 14);
      cubit.now = () => at = at.add(const Duration(seconds: 1));
      cubit
        ..say('opened teapot.glb')
        ..say('saved');

      final answer = _actions(cubit, _Counters()).console();

      expect(answer.did, isTrue);
      // Mutation: hand back only the last line — the one the strip is
      // already showing. An agent asking what the person has been doing then
      // learns exactly what it could already see.
      expect(answer.says, contains('opened teapot.glb'));
      expect(answer.says, contains('saved'));
      expect(
        answer.says.indexOf('opened'),
        lessThan(answer.says.indexOf('saved')),
      );
    });

    test('and with only what happened since a stamp', () {
      final cubit = _opened();
      var at = DateTime.utc(2026, 9, 16, 14);
      cubit.now = () => at = at.add(const Duration(seconds: 1));
      cubit.say('opened teapot.glb');
      final DateTime seen = cubit.console.entries.last.at;
      cubit.say('saved');

      final answer = _actions(cubit, _Counters()).console(since: seen);

      expect(answer.says, isNot(contains('opened teapot.glb')));
      expect(answer.says, contains('saved'));
    });

    test('an empty session says so rather than answering with nothing', () {
      final answer = _actions(_opened(), _Counters()).console();

      // Mutation: answer with an empty string. An agent cannot tell that
      // from a tool that failed quietly, and the natural next move is to
      // call it again.
      expect(answer.did, isTrue);
      expect(answer.says, contains('nothing has been said'));
    });

    test('a refusal is marked in the line an agent reads', () {
      final cubit = _opened();
      var at = DateTime.utc(2026, 9, 16, 14);
      cubit.now = () => at = at.add(const Duration(seconds: 1));
      cubit.ran(const DeleteObjects());

      final answer = _actions(cubit, _Counters()).console();

      expect(answer.says, contains('refusal'));
    });
  });
}
