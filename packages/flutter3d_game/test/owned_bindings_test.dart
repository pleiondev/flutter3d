/// The map the game reads and the map the file saves are the same map.
///
///     flutter test test/owned_bindings_test.dart
///
/// **A shipped bug in both games**, and one that could only ever happen to a
/// player who had never changed a setting — which is why it lasted: the
/// keyboard read a fresh table on a first launch, the rebinding screen edited
/// it, and the save wrote another. The controller holds the one live map now,
/// and the settings it saves keep a copy of it taken on every change.
library;

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _jump = GameAction('jump');
const GameAction _dash = GameAction('dash');

ActionMap _defaults() => ActionMap(
  actions: const ActionSet('test', <ActionDeclaration>[
    ActionDeclaration(_jump),
    ActionDeclaration(_dash),
  ]),
  buttons: Bindings()
    ..bind(InputSource.key(32), _jump)
    ..bind(InputSource.key(81), _dash),
);

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  Future<String?> read(String name) async => documents[name];

  @override
  Future<void> write(String name, String contents) async =>
      documents[name] = contents;

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

void main() {
  test('a rebind made on a first launch survives the save', () async {
    final storage = _Storage();
    final file = SettingsFile(
      appName: 'test',
      storage: storage,
      defaultActions: _defaults,
    );
    final first = await file.read();
    final live = first.actionsOr(_defaults);
    final controller = GameSettingsController(
      settings: first,
      file: file,
      apply: (_) {},
      actions: live,
    );

    // The rebinding screen edits the map the keyboard reads.
    expect(identical(controller.rebinding.actions, live), isTrue);
    controller.rebind(_dash);
    controller.capture(InputSource.key(70));
    await controller.saved;

    // Mutation: drop the copy `_changed` takes — the settings keep the map
    // they were read with, and the rebind is gone on the next launch.
    final saved = await file.read();
    expect(saved.actions!.buttons[InputSource.key(70)], _dash);
    expect(
      saved.actions!.buttons[InputSource.key(81)],
      isNull,
      reason: 'the old key still works, so nothing was moved',
    );
  });

  test('the settings keep a copy, so the value a widget holds is still', () {
    final live = _defaults();
    final controller = GameSettingsController(
      settings: const GameSettings(),
      file: SettingsFile(appName: 'test', storage: _Storage()),
      apply: (_) {},
      actions: live,
    );
    controller.rebind(_dash);
    controller.capture(InputSource.key(70));
    final before = controller.settings;

    controller.rebind(_dash);
    controller.capture(InputSource.key(71));

    expect(before.actions!.buttons[InputSource.key(70)], _dash);
    expect(controller.settings.actions!.buttons[InputSource.key(71)], _dash);
  });

  test('a later launch keeps what the player chose, defaults and all', () {
    // Mutation: have `actionsOr` answer the defaults whenever it is asked —
    // every launch resets the controls.
    final settings = const GameSettings().copyWith(
      actions: ActionMap(
        actions: _defaults().actions,
        buttons: Bindings()..bind(InputSource.key(70), _dash),
      ),
    );

    final map = settings.actionsOr(_defaults);

    expect(map.buttons[InputSource.key(70)], _dash);
    expect(
      map.buttons[InputSource.key(81)],
      isNull,
      reason: 'the defaults were put back over the player',
    );
    expect(identical(map, settings.actions), isFalse);
  });
}
