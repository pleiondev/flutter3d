/// What each build is told about how it is played.
///
/// **These three getters decide whether a game has controls at all**, and until
/// this file nothing checked them: they read `kIsWeb` and a platform list, both
/// of which a test can see and neither of which anybody looked at. Two of the
/// answers were wrong for a year — a desktop browser was told it could not
/// capture a pointer, and a phone in a browser was told it had no fingers, which
/// is a demo opened on a phone with no stick, no buttons and no keyboard.
///
/// Each test names the mutation it was written against.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointer_lock/pointer_lock.dart';

/// A capture backend whose answer the test sets.
///
/// The real one answers from the platform it was compiled for, which is the one
/// thing a test cannot vary — so the question `Playing` asks is stubbed and the
/// arithmetic it does with the answer is what gets checked.
final class _Backend extends PointerLockPlatform {
  _Backend({required this.supported});

  final bool supported;

  @override
  bool get isSupported => supported;

  @override
  Stream<Offset> get deltas => const Stream<Offset>.empty();

  @override
  Stream<CaptureState> get stateChanges => const Stream<CaptureState>.empty();

  @override
  Future<void> capture() async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> reset() async {}
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  void on(TargetPlatform platform, {required bool captureAvailable}) {
    debugDefaultTargetPlatformOverride = platform;
    PointerLockPlatform.instance = _Backend(supported: captureAvailable);
  }

  group('a desktop', () {
    test('with a capture backend takes the pointer', () {
      // Broken by keeping the old platform whitelist: it named Windows and
      // Linux, where `pointer_lock` has no native side, so those builds
      // captured nothing *and* turned off drag-look — a camera that does not
      // move however the player holds the mouse.
      on(TargetPlatform.macOS, captureAvailable: true);
      expect(Playing.capturesPointer, isTrue);
      expect(Playing.dragLook, isFalse);
      expect(Playing.touch, isFalse);
    });

    test('without one turns the camera by dragging', () {
      // Broken by asking the platform instead of the backend, which is what the
      // list did. This is the Windows and Linux case, and the assertion that
      // matters is the second one: something has to turn the camera.
      on(TargetPlatform.windows, captureAvailable: false);
      expect(Playing.capturesPointer, isFalse);
      expect(Playing.dragLook, isTrue);
      expect(Playing.touch, isFalse);
    });
  });

  group('a phone', () {
    test('has fingers, whatever the capture backend says', () {
      // Broken by dropping the `!touch` guard in `capturesPointer`. A mobile
      // browser does carry the Pointer Lock API, so the backend can answer yes
      // there; taking it would hide the on-screen controls and leave the player
      // dragging a pointer that does not exist.
      on(TargetPlatform.android, captureAvailable: true);
      expect(Playing.touch, isTrue);
      expect(Playing.capturesPointer, isFalse);
      expect(Playing.dragLook, isTrue);
    });

    test('running in a browser is still a phone', () {
      // Broken by putting `!kIsWeb &&` back in front of `touch`, which is how
      // this was written and what made the web build unplayable on a handset:
      // Flutter reports a mobile browser as iOS or Android, and the guard threw
      // that answer away.
      on(TargetPlatform.iOS, captureAvailable: false);
      expect(Playing.touch, isTrue);
      expect(Playing.dragLook, isTrue);
    });
  });
}
