import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointer_lock/pointer_lock.dart';

/// A platform whose events the test drives by hand.
///
/// Worth the twenty lines: everything that is easy to get wrong here — dropping
/// a delta, missing an unrequested release, accumulating motion from before the
/// capture — lives above the channel and would otherwise only be reachable by
/// running the app and waving a mouse at it.
final class FakePointerLockPlatform extends PointerLockPlatform {
  FakePointerLockPlatform({this.supported = true});

  final bool supported;

  final StreamController<Offset> _deltas = StreamController<Offset>.broadcast();
  final StreamController<CaptureState> _states =
      StreamController<CaptureState>.broadcast();

  final List<String> calls = <String>[];

  @override
  bool get isSupported => supported;

  @override
  Stream<Offset> get deltas => _deltas.stream;

  @override
  Stream<CaptureState> get stateChanges => _states.stream;

  @override
  Future<void> capture() async {
    calls.add('capture');
    _states.add(CaptureState.captured);
    // The state event reaches listeners on a microtask, and callers of
    // PointerLock.capture() await this future, so let it land first.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> release() async {
    calls.add('release');
  }

  @override
  Future<void> reset() async {
    calls.add('reset');
  }

  /// Simulates the native side reporting motion.
  Future<void> move(double dx, double dy) async {
    _deltas.add(Offset(dx, dy));
    await Future<void>.delayed(Duration.zero);
  }

  /// Simulates a release the application did not ask for — losing focus.
  Future<void> loseFocus() async {
    _states.add(CaptureState.released);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    await _deltas.close();
    await _states.close();
  }
}

void main() {
  late FakePointerLockPlatform platform;
  late PointerLock capture;

  setUp(() {
    platform = FakePointerLockPlatform();
    capture = PointerLock(platform: platform);
  });

  tearDown(() async {
    await capture.dispose();
    await platform.close();
  });

  group('accumulating motion', () {
    test('takeDelta sums every event since the last call', () async {
      await capture.capture();
      await platform.move(3.0, -1.0);
      await platform.move(2.0, 4.0);

      expect(capture.takeDelta(), const Offset(5.0, 3.0));
    });

    test('takeDelta resets, so motion is never counted twice', () async {
      await capture.capture();
      await platform.move(3.0, 3.0);

      expect(capture.takeDelta(), const Offset(3.0, 3.0));
      expect(capture.takeDelta(), Offset.zero);
    });

    test(
      'no motion between steps reads as zero, not as the last value',
      () async {
        await capture.capture();
        await platform.move(7.0, 7.0);
        capture.takeDelta();

        expect(capture.takeDelta(), Offset.zero);
      },
    );

    test('motion from before the capture is discarded', () async {
      // Cursor movement that happened while the pointer was free belongs to the
      // cursor. Carrying it into the capture snaps the camera on the first frame.
      await capture.capture();
      await platform.move(100.0, 100.0);
      await capture.release();

      await capture.capture();

      expect(capture.takeDelta(), Offset.zero);
    });

    test('motion arriving between release and the next step is kept', () async {
      // The opposite case: a release must not swallow the fragment of motion
      // that the simulation has not read yet.
      await capture.capture();
      await platform.move(4.0, 4.0);
      await capture.release();

      expect(capture.takeDelta(), const Offset(4.0, 4.0));
    });
  });

  group('capture state', () {
    test('starts released', () {
      expect(capture.isCaptured, isFalse);
    });

    test('capture and release move the state and reach the platform', () async {
      await capture.capture();
      expect(capture.isCaptured, isTrue);

      await capture.release();
      expect(capture.isCaptured, isFalse);
      expect(
        platform.calls,
        containsAllInOrder(<String>['capture', 'release']),
      );
    });

    test('losing focus releases without the application asking', () async {
      await capture.capture();
      await platform.loseFocus();

      expect(capture.isCaptured, isFalse);
    });

    test('an unrequested release is announced, so a game can pause', () async {
      await capture.capture();

      final states = <CaptureState>[];
      final subscription = capture.onStateChanged.listen(states.add);

      await platform.loseFocus();
      await subscription.cancel();

      expect(states, <CaptureState>[CaptureState.released]);
    });

    test('capturing twice does not reach the platform twice', () async {
      await capture.capture();
      await capture.capture();

      expect(
        platform.calls.where((String call) => call == 'capture'),
        hasLength(1),
      );
    });

    test('releasing when not captured does nothing', () async {
      await capture.release();

      expect(platform.calls, isNot(contains('release')));
    });

    test('the state stream does not repeat a state it is already in', () async {
      final states = <CaptureState>[];
      final subscription = capture.onStateChanged.listen(states.add);

      await capture.capture();
      await platform.loseFocus();
      await platform.loseFocus();
      await subscription.cancel();

      expect(states, <CaptureState>[
        CaptureState.captured,
        CaptureState.released,
      ]);
    });
  });

  group('hot restart', () {
    test(
      'construction resets the platform, which may still hold the pointer',
      () async {
        // The native side outlives the Dart isolate. Without this the developer is
        // left with a hidden cursor and nothing that will ever ask for it back.
        await Future<void>.delayed(Duration.zero);

        expect(platform.calls, contains('reset'));
      },
    );
  });

  group('unsupported platforms', () {
    late FakePointerLockPlatform unsupported;
    late PointerLock unsupportedCapture;

    setUp(() {
      unsupported = FakePointerLockPlatform(supported: false);
      unsupportedCapture = PointerLock(platform: unsupported);
    });

    tearDown(() async {
      await unsupportedCapture.dispose();
      await unsupported.close();
    });

    test('reports itself unsupported instead of failing at the first call', () {
      expect(unsupportedCapture.isSupported, isFalse);
    });

    test('capture is a no-op rather than a throw', () async {
      await unsupportedCapture.capture();

      expect(unsupportedCapture.isCaptured, isFalse);
      expect(unsupported.calls, isEmpty);
    });

    test('takeDelta keeps working and reads zero', () async {
      await unsupportedCapture.capture();

      expect(unsupportedCapture.takeDelta(), Offset.zero);
    });

    test('no reset is attempted where there is nothing to reset', () async {
      await Future<void>.delayed(Duration.zero);

      expect(unsupported.calls, isEmpty);
    });
  });

  group('the shared instance', () {
    tearDown(PointerLock.disposeInstance);

    test('is made on first use, not at load', () {
      // A build that never captures a pointer never subscribes to a platform
      // channel — which on a plugin with a native half is the difference
      // between "unused" and "installed".
      PointerLockPlatform.instance = FakePointerLockPlatform();

      final platform = PointerLockPlatform.instance as FakePointerLockPlatform;
      expect(platform.calls, isEmpty);

      PointerLock.instance;

      expect(
        platform.calls,
        contains('reset'),
        reason: 'the instance never reached the platform it was given',
      );
    });

    test('and is the same one twice', () {
      PointerLockPlatform.instance = FakePointerLockPlatform();

      expect(identical(PointerLock.instance, PointerLock.instance), isTrue);
    });

    test('and can be dropped, so the next caller gets a fresh one', () async {
      // **What this is for.** A dozen test files share one process: an instance
      // built by the first of them goes on listening to the platform it was
      // handed, through every file that follows — so a fake installed later is
      // one the live instance never sees.
      PointerLockPlatform.instance = FakePointerLockPlatform();
      final first = PointerLock.instance;

      await PointerLock.disposeInstance();
      PointerLockPlatform.instance = FakePointerLockPlatform();
      final second = PointerLock.instance;

      expect(identical(first, second), isFalse);
    });
  });
}
