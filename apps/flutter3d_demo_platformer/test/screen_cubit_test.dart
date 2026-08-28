/// What the screen is showing, and when a run is worth writing down.
///
///     flutter test test/screen_cubit_test.dart
///
/// **None of this could be tested before.** Four fields lived in `setState`
/// inside `_GameScreenState` — the title card, whether the run came off the
/// disk, the startup error and the last saved checkpoint — and reaching any of
/// them meant pumping a widget with a graphics device behind it. That is the
/// hole `ARCHITECTURE.md` §11.3 names as the reason `flutter_bloc` is in this
/// repository at all.
library;

import 'package:flutter3d_demo_platformer/src/screen_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('the title card', () {
    test('is up until somebody asks to play', () {
      expect(ScreenCubit().state.started, isFalse);
    });

    test('and goes down once', () {
      // Mutation: drop the `if (state.started) return` guard — this passes
      // either way, and the emission count below is what fails.
      final screen = ScreenCubit();
      final seen = <bool>[];
      screen.stream.listen((ScreenState s) => seen.add(s.started));

      screen
        ..begin()
        ..begin()
        ..begin();

      expect(screen.state.started, isTrue);
      return Future<void>.delayed(Duration.zero, () {
        // **Once, not three times.** Every press of a key goes through `begin`,
        // and a cubit that emitted on each would rebuild the tree for a fact
        // that had not changed.
        expect(seen, hasLength(1));
      });
    });
  });

  group('a save is written when the respawn point moves', () {
    test('the first checkpoint is always worth writing', () {
      expect(ScreenCubit().shouldSave(Vector3(1.0, 2.0, 3.0)), isTrue);
    });

    test('and standing still is not', () {
      // Asked every frame and answered no almost every time — which is why the
      // answer is not a state emission. Mutation: return true unconditionally
      // and a file write lands in the frame budget, sixty times a second.
      final screen = ScreenCubit();
      final at = Vector3(1.0, 2.0, 3.0);

      expect(screen.shouldSave(at), isTrue);
      expect(screen.shouldSave(at), isFalse);
      expect(
        screen.shouldSave(at.clone()),
        isFalse,
        reason: 'compared by distance, not by identity',
      );
    });

    test('and moving on is', () {
      final screen = ScreenCubit();
      expect(screen.shouldSave(Vector3(0.0, 0.0, 0.0)), isTrue);
      expect(screen.shouldSave(Vector3(0.0, 0.0, 4.0)), isTrue);
    });

    test('and a hair of drift is not a checkpoint', () {
      // The comparison is squared distance against 1e-6, so a respawn point
      // that jitters in the last bits of a float is the same point. Mutation:
      // compare with `!=` — this fails, and nothing else would.
      final screen = ScreenCubit();
      expect(screen.shouldSave(Vector3(2.0, 0.0, 0.0)), isTrue);
      expect(screen.shouldSave(Vector3(2.0 + 1e-9, 0.0, 0.0)), isFalse);
    });

    test('and a new run forgets where the last one saved', () {
      // Mutation: make `forgetSave` a no-op — the first checkpoint of the new
      // run is silently skipped, and a player who dies before the second one
      // loses the level they had already reached.
      final screen = ScreenCubit();
      final at = Vector3(5.0, 0.0, 0.0);

      expect(screen.shouldSave(at), isTrue);
      screen.forgetSave();
      expect(screen.shouldSave(at), isTrue);
    });
  });

  group('what stopped the game starting', () {
    test('is nothing, normally', () {
      expect(ScreenCubit().state.error, isNull);
    });

    test('and is remembered when the device refuses', () {
      final screen = ScreenCubit()..failed('no device');
      expect(screen.state.error, 'no device');
    });

    test('and does not erase whether the run resumed', () {
      // Both arrive from separate futures that race, so neither may drop the
      // other. Mutation: emit a fresh `ScreenState` in `failed` instead of
      // copying — the title card forgets it was resuming.
      final screen = ScreenCubit()
        ..resumedFromDisk(resumed: true)
        ..failed('no device');

      expect(screen.state.resumed, isTrue);
      expect(screen.state.error, 'no device');
    });
  });
}
