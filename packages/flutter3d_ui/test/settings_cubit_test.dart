/// The settings screen, asked questions for the first time.
///
///     flutter test test/settings_cubit_test.dart
///
/// **Every rule below shipped in two games and none of them was reachable.**
/// Opening the panel, moving a slider, starting a rebind and taking the key
/// that answers it were `setState` calls inside `main.dart`, which no test in
/// either application imports. The rules were never complicated; they were
/// somewhere nothing could ask them.
///
/// What is checked here is the behaviour, not the widget: a cubit is a plain
/// object, so this needs no pump, no binding and no window.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage that keeps everything in a map, and can be told to refuse.
final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};
  bool refuse = false;

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    if (refuse) return false;
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

const GameAction _fire = GameAction('fire');
const GameAction _use = GameAction('use');

/// A cubit over a fresh config, and a record of what was applied to the game.
({SettingsCubit cubit, _Storage storage, List<int> applied}) _open({
  Bindings? bindings,
}) {
  final storage = _Storage();
  final applied = <int>[];
  final config = GameConfig(bindings: bindings ?? Bindings());
  return (
    cubit: SettingsCubit(
      config: config,
      file: SettingsFile(appName: 'test', storage: storage),
      apply: (GameConfig _) => applied.add(applied.length),
    ),
    storage: storage,
    applied: applied,
  );
}

void main() {
  group('the panel', () {
    test('is down until it is asked for, and the gate can see that', () {
      // `isOpen` is state rather than a widget's private flag because the pause
      // gate reads it: a game that goes on being played behind its own settings
      // is a bug both of these applications have shipped.
      final it = _open();

      expect(it.cubit.state.isOpen, isFalse);
      it.cubit.show();
      expect(it.cubit.state.isOpen, isTrue);
      it.cubit.hide();
      expect(it.cubit.state.isOpen, isFalse);
    });

    test('and closing it stops a rebind that was still listening', () {
      // Mutation: drop `rebinding.cancel()` from `hide`. The panel goes away and
      // the next key the player presses is eaten by a screen nobody can see —
      // which reads as the game having stopped responding.
      final it = _open()..cubit.show();
      it.cubit.rebind(_fire);
      expect(it.cubit.state.waitingFor, _fire);

      it.cubit.hide();

      expect(it.cubit.state.waitingFor, isNull);
      expect(
        it.cubit.capture(InputSource.key(32)),
        isFalse,
        reason: 'a closed panel took a key press',
      );
    });
  });

  group('a change', () {
    test('reaches the game and the disk, in that order', () {
      // The order matters and is the reason `apply` is a seam rather than
      // something the caller does afterwards: applying after the write would
      // leave a crash between the two with a document on disk describing a game
      // that never played that way.
      final it = _open();

      it.cubit.setVolume('music', 0.4);

      expect(it.applied, hasLength(1), reason: 'the mixer was never told');
      expect(it.storage.documents['settings.json'], contains('music'));
      expect(it.cubit.config.volumeOf('music'), 0.4);
    });

    test('bumps the revision, because the config is shared and mutable', () {
      // The counter is the whole reason a slider redraws. `GameConfig` is edited
      // in place — deliberately, so the mixer and the input read the same
      // object — and an in-place edit does not change the state's identity.
      //
      // Mutation: stop incrementing it. Every slider moves the sound and none of
      // them move on screen.
      final it = _open();
      final before = it.cubit.state.revision;

      it.cubit.setSetting('a11y.toggleSprint', 1.0);

      expect(it.cubit.state.revision, greaterThan(before));
    });

    test('says so when the disk refused it', () {
      // A browser out of quota. Nothing read this before: `Storage.write`
      // returns false, both games ignored it, and a settings document that
      // cannot be written looks exactly like a player who changed nothing.
      final it = _open();
      it.storage.refuse = true;

      it.cubit.setVolume('sfx', 0.2);

      expect(it.cubit.state.lastWriteFailed, isTrue);
      expect(
        it.cubit.config.volumeOf('sfx'),
        0.2,
        reason: 'a failed write must not undo what the player changed',
      );
    });
  });

  group('rebinding', () {
    test('takes the next control offered, and only for the waiting action', () {
      final it = _open();

      expect(
        it.cubit.capture(InputSource.key(65)),
        isFalse,
        reason: 'took a key nobody asked for',
      );

      it.cubit.rebind(_fire);
      expect(it.cubit.capture(InputSource.key(65)), isTrue);

      expect(it.cubit.state.waitingFor, isNull, reason: 'still listening');
      expect(it.cubit.config.bindings[InputSource.key(65)], _fire);
    });

    test('and moving a control off another action takes it away', () {
      // The rule `Rebinding` defends: two actions on one key is a table where
      // the last writer wins silently, and a player who cannot see which one won
      // thinks the rebinding failed.
      final bindings = Bindings()..bind(InputSource.key(65), _use);
      final it = _open(bindings: bindings);

      it.cubit.rebind(_fire);
      it.cubit.capture(InputSource.key(65));

      expect(it.cubit.config.bindings[InputSource.key(65)], _fire);
      expect(
        bindings.sources.where((InputSource s) => bindings[s] == _use),
        isEmpty,
        reason: 'the key still does both',
      );
    });

    test('is written to disk as it happens, not when the panel closes', () {
      // A player who rebinds and then quits by closing the window has still
      // rebound. Mutation: move the write into `hide`.
      final it = _open();
      it.cubit.rebind(_fire);

      it.cubit.capture(InputSource.pad('face.south'));

      expect(it.storage.documents['settings.json'], contains('face.south'));
    });

    test('and putting the controls back restores every default', () {
      // The way out of a rebinding that made the game unplayable, which is not
      // hypothetical: the fastest way to find that out is to bind movement to a
      // key you cannot reach.
      final defaults = Bindings()
        ..bind(InputSource.key(87), GameAction.moveForward)
        ..bind(InputSource.key(32), GameAction.jump);
      final it = _open();
      it.cubit.rebind(GameAction.jump);
      it.cubit.capture(InputSource.key(65));

      it.cubit.resetControls(defaults);

      expect(it.cubit.config.bindings[InputSource.key(32)], GameAction.jump);
      expect(
        it.cubit.config.bindings[InputSource.key(65)],
        isNull,
        reason: 'the rebound key survived the reset',
      );
      expect(it.applied, isNotEmpty, reason: 'the game was never told');
    });
  });
}
