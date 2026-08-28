/// A press told apart from a hold.
///
///     flutter test test/pad_presses_test.dart
///
/// **The bug this exists to make unwritable**: a player who dies with a thumb
/// on Start restarts the run sixty times a second and never reads the screen
/// that told them they died. Every one of the three games knew that and two of
/// them had it right; the third read a *held* button where it meant a pressed
/// one, in the one place a controller can be rebound from the controller.
library;

import 'dart:async';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pad_input/pad_input.dart';

final class _FakePad extends GamepadPlatform {
  final PadSnapshot state = PadSnapshot()..connected = true;
  final StreamController<PadConnection> _connections =
      StreamController<PadConnection>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges => _connections.stream;

  @override
  void read(PadSnapshot out) => out.copyFrom(state);

  @override
  Future<void> dispose() async => _connections.close();
}

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

SettingsCubit _settings() => SettingsCubit(
  config: GameConfig(),
  file: SettingsFile(appName: 'test', storage: _Storage()),
  apply: (GameConfig _) {},
);

({_FakePad fake, PadInput pad}) _pad() {
  final fake = _FakePad();
  return (
    fake: fake,
    pad: PadInput(
      state: InputState(),
      pad: Gamepad(platform: fake),
    ),
  );
}

void main() {
  test('a button held is a press once and then nothing', () {
    final it = _pad();
    final presses = PadPresses();
    final settings = _settings();

    it.fake.state.setDown(PadButton.start, down: true);
    it.pad.tick(1 / 60);
    expect(presses.offer(it.pad, settings), isTrue);

    // The same thumb, four more frames of it.
    for (var frame = 0; frame < 4; frame++) {
      it.pad.tick(1 / 60);
      expect(
        presses.offer(it.pad, settings),
        isFalse,
        reason: 'a held button pressed itself again',
      );
    }
  });

  test('and letting go and pressing again is a second press', () {
    final it = _pad();
    final presses = PadPresses();
    final settings = _settings();

    it.fake.state.setDown(PadButton.start, down: true);
    it.pad.tick(1 / 60);
    presses.offer(it.pad, settings);

    it.fake.state.setDown(PadButton.start, down: false);
    it.pad.tick(1 / 60);
    presses.offer(it.pad, settings);

    it.fake.state.setDown(PadButton.start, down: true);
    it.pad.tick(1 / 60);
    expect(presses.offer(it.pad, settings), isTrue);
  });

  test('and nothing pressed is not a press', () {
    final it = _pad()..pad.tick(1 / 60);
    expect(PadPresses().offer(it.pad, _settings()), isFalse);
  });

  test('a waiting rebinding takes the press, and the screen does not', () {
    // Both halves matter. A controller that cannot be remapped from the
    // controller is no use to a player who has only one of the two devices —
    // and a press that bound a button and *also* restarted the run would take
    // the player out of the panel they were setting up.
    final it = _pad();
    final settings = _settings()..rebind(GameAction.jump);

    it.fake.state.setDown(PadButton.faceSouth, down: true);
    it.pad.tick(1 / 60);
    final left = PadPresses().offer(it.pad, settings);

    expect(left, isFalse, reason: 'the screen acted on a rebinding press');
    expect(
      settings.config.bindings[InputSource.pad(PadButton.faceSouth.id)],
      GameAction.jump,
    );
    expect(settings.state.waitingFor, isNull);
  });

  test('and it takes a press rather than a hold', () {
    // **The dungeon\'s bug**: it read `heldButtons.isNotEmpty` every frame, so a
    // controller resting against something — a thumb still on the button that
    // opened the panel — bound itself to whatever the panel was next waiting
    // for, without the player touching it.
    final it = _pad();
    final settings = _settings();

    it.fake.state.setDown(PadButton.faceSouth, down: true);
    it.pad.tick(1 / 60);
    PadPresses().offer(it.pad, settings);

    // The button is still down when the player asks to rebind.
    final presses = PadPresses()..offer(it.pad, settings);
    settings.rebind(GameAction.jump);
    it.pad.tick(1 / 60);
    presses.offer(it.pad, settings);

    expect(
      settings.state.waitingFor,
      GameAction.jump,
      reason: 'a button nobody pressed bound itself',
    );
  });
}
