/// Which keys belong to the settings, and in what order.
///
///     flutter test test/settings_keys_test.dart
///
/// **All three games had written this sequence out**, and one of them had
/// broken its own first rule. The order is not a matter of taste: each clause
/// above the next is there because of something that went wrong when it was
/// below.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

SettingsCubit _open() => SettingsCubit(
  config: GameConfig(),
  file: SettingsFile(appName: 'test', storage: _Storage()),
  apply: (GameConfig _) {},
);

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.keyA,
  timeStamp: Duration.zero,
);

KeyUpEvent _up(LogicalKeyboardKey key) => KeyUpEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.keyA,
  timeStamp: Duration.zero,
);

void main() {
  test('a key the settings have no use for goes to the game', () {
    // Null, not `ignored`: `ignored` would let the key travel up Flutter's tree
    // instead of reaching the game at all.
    expect(
      settingsKeys(_down(LogicalKeyboardKey.keyW), _open(), opening: () {}),
      isNull,
    );
  });

  test('a rebinding takes the next key before anything else looks at it', () {
    // **The rule the platformer wrote down and broke.** Its restart clause sat
    // above the rebinding, so a player at the end of a run pressed R to bind it
    // and restarted the run instead. Asking here first is what fixes that, and
    // the game's own clauses now run only when this says null.
    final settings = _open()..rebind(GameAction.jump);

    final says = settingsKeys(
      _down(LogicalKeyboardKey.keyR),
      settings,
      opening: () {},
    );

    expect(
      says,
      KeyEventResult.handled,
      reason: 'the game got a key the panel was waiting for',
    );
    expect(
      settings.config.bindings[InputSource.key(LogicalKeyboardKey.keyR.keyId)],
      GameAction.jump,
    );
  });

  test('and Escape during one is how a player says not that one', () {
    final settings = _open()..rebind(GameAction.jump);

    settingsKeys(_down(LogicalKeyboardKey.escape), settings, opening: () {});

    expect(settings.state.waitingFor, isNull);
    expect(
      settings.config.bindings
          .sourcesFor(GameAction.jump)
          .contains(InputSource.key(LogicalKeyboardKey.escape.keyId)),
      isFalse,
      reason: 'it bound Escape to jumping',
    );
  });

  test('Escape opens the panel as well as closing it', () {
    // A player on a controller never took the pointer, and had no way in.
    final settings = _open();

    settingsKeys(_down(LogicalKeyboardKey.escape), settings, opening: () {});
    expect(settings.state.isOpen, isTrue);

    settingsKeys(_down(LogicalKeyboardKey.escape), settings, opening: () {});
    expect(settings.state.isOpen, isFalse);
  });

  test('and opening runs before the panel is on screen, closing does not', () {
    // What `opening` does differs by game — let the pointer go, drop the keys
    // the car was holding — but every one of them is something that has to have
    // happened by the time the panel is up. On the way out there is nothing to
    // undo: the panel had the keys while it was open.
    final settings = _open();
    var openings = 0;

    settingsKeys(
      _down(LogicalKeyboardKey.escape),
      settings,
      opening: () {
        expect(settings.state.isOpen, isFalse, reason: 'it ran too late');
        openings++;
      },
    );
    settingsKeys(
      _down(LogicalKeyboardKey.escape),
      settings,
      opening: () => openings++,
    );

    expect(openings, 1);
  });

  test('and a game with a screen the panel adds nothing to can refuse', () {
    // The platformer's title card carries the same credits, so Escape there
    // does what it always did and gives the pointer back.
    final settings = _open();

    final says = settingsKeys(
      _down(LogicalKeyboardKey.escape),
      settings,
      opening: () {},
      canOpen: false,
    );

    expect(says, isNull);
    expect(settings.state.isOpen, isFalse);
  });

  test('and refusing to open never traps a panel that is open', () {
    // A game that closed its title card would never say `canOpen: false` with
    // the panel up — but a panel that cannot be closed is a game nobody can get
    // back to, so the clause does not depend on being asked nicely.
    final settings = _open()..show();

    settingsKeys(
      _down(LogicalKeyboardKey.escape),
      settings,
      opening: () {},
      canOpen: false,
    );

    expect(settings.state.isOpen, isFalse);
  });

  group('with the panel open the keys belong to the panel', () {
    test('the game is offered nothing', () {
      // Two things at once: Flutter\'s focus traversal never sees Tab or the
      // arrows, so a player with no mouse cannot reach a slider at all — and a
      // key held as the panel opened stays held in the `InputState`, so closing
      // it sends the player walking off on their own.
      final settings = _open()..show();

      expect(
        settingsKeys(_down(LogicalKeyboardKey.tab), settings, opening: () {}),
        KeyEventResult.ignored,
      );
      expect(
        settingsKeys(_down(LogicalKeyboardKey.keyW), settings, opening: () {}),
        KeyEventResult.ignored,
      );
    });

    test('and neither is it offered the release of a key', () {
      // The half that is easy to leave out: a game that is handed the key-up
      // but not the key-down has an action that never stops.
      final settings = _open()..show();

      expect(
        settingsKeys(_up(LogicalKeyboardKey.keyW), settings, opening: () {}),
        KeyEventResult.ignored,
      );
    });

    test('and a key-up while it is closed still reaches the game', () {
      expect(
        settingsKeys(_up(LogicalKeyboardKey.keyW), _open(), opening: () {}),
        isNull,
      );
    });
  });
}
