/// The browser backend, run in a browser.
///
/// **`@TestOn('browser')`, and the package's other tests are the opposite.**
/// Everything in `pointer_lock_test.dart` is about the accumulator above the
/// platform and runs anywhere; this file is about the platform itself, and
/// `dart:js_interop` is not a library the VM has. `tool/ci.sh` runs this package
/// both ways for that reason.
///
/// ## What a test can and cannot reach here
///
/// It cannot capture. `requestPointerLock` is refused outside a user gesture,
/// and a test harness has no gestures — so every assertion below is about what
/// happens *around* a capture, which is where this backend's real defects would
/// be anyway: reporting motion that nobody asked for, mistaking a refusal for a
/// success, saying it is supported on a phone.
///
/// Each test names the mutation it was written against.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pointer_lock/src/platform_default_web.dart';
import 'package:pointer_lock/src/pointer_lock_platform_interface.dart';
import 'package:web/web.dart' as web;

void main() {
  test('a browser is a platform with a pointer to take', () {
    // Broken by returning false unconditionally, which is what this package did
    // for the web before this file existed: the whole point is that the answer
    // is now yes, and a game reads it to decide between a captured mouse and a
    // drag.
    expect(WebPointerLock().isSupported, isTrue);
  });

  test('motion is not reported while nothing is captured', () async {
    // Broken by dropping the `if (!_captured) return` guard: every mouse
    // movement over the page then turns the camera, which is the one failure
    // that makes a game unplayable rather than merely awkward — the view spins
    // whenever the player reaches for a menu.
    final platform = WebPointerLock();
    final seen = <Offset>[];
    final subscription = platform.deltas.listen(seen.add);

    web.document.dispatchEvent(_mouseMove(dx: 12.0, dy: -4.0));
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    await subscription.cancel();
  });

  test('a capture that is refused leaves the state released', () async {
    // Broken by having `capture()` announce CaptureState.captured itself rather
    // than waiting for `pointerlockchange`. The browser refuses this one — there
    // is no user gesture behind it — and a backend that assumed success would
    // leave the game believing it holds a pointer it does not: no camera, and a
    // pause menu that will not open because the game thinks it is already in
    // play.
    final platform = WebPointerLock();
    final states = <CaptureState>[];
    final subscription = platform.stateChanges.listen(states.add);

    await platform.capture();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(states, isEmpty);
    expect(web.document.pointerLockElement, isNull);
    await subscription.cancel();
  });

  test('releasing and resetting with nothing held do nothing', () async {
    // Broken by dropping the guards in `release` and `reset`, which then call
    // `exitPointerLock` on a document that holds nothing. It is harmless in
    // Chrome and it is the shape of the hot-restart bug this package's `reset`
    // exists for, so the two are pinned together.
    final platform = WebPointerLock();
    await platform.release();
    await platform.reset();
    expect(web.document.pointerLockElement, isNull);
  });

  test('the lock is asked for on Flutter\'s own view when there is one', () {
    // **Broken by locking `document.documentElement`, which is how this backend
    // shipped and what the first player to try it found.** A locked pointer
    // targets its events at the element holding the lock; Flutter listens for
    // `pointerdown` on its view root and for `pointerup`/`pointermove` on the
    // window. Lock an ancestor of the view and the moves still arrive — they
    // bubble to the window — while every press lands on an element with no
    // listener on it. The camera turns and the trigger does nothing.
    final view = web.document.createElement('flutter-view');
    web.document.body!.append(view);
    addTearDown(() => view.remove());

    // By tag rather than by identity: two reads of the same DOM node come back
    // as two Dart wrappers over it, so `same` compares the wrappers and fails
    // on an element that is the right one.
    expect(WebPointerLock().debugTarget.tagName.toLowerCase(), 'flutter-view');
  });

  test('and on the document element in a page that has no view', () {
    // Broken by making the fallback null or throwing: a page with no Flutter
    // view in it is this test file, and every other test here would stop
    // reaching the backend at all.
    //
    // The document is cleared of views first rather than trusting the previous
    // test to have tidied up — a test that passes or fails on what ran before it
    // is a test that will do both.
    final views = web.document.querySelectorAll('flutter-view');
    for (var i = 0; i < views.length; i++) {
      (views.item(i)! as web.Element).remove();
    }

    expect(WebPointerLock().debugTarget.tagName.toLowerCase(), 'html');
  });

  test('a delta is the movement the event carries, axis for axis', () {
    // Broken by negating the vertical, which is the mistake with a plausible
    // argument behind it — every other surface in this repository that turns a
    // camera has an inverted axis somewhere — and by swapping the two, which is
    // the one a reader cannot see. Both make the test fail here.
    //
    // Deliberately not asserted by scaling: a headless browser reports a device
    // pixel ratio of 1, so a backend that multiplied by it would pass this and
    // fail on a retina display. What holds that is the comment in `deltaOf`,
    // not this test, and saying so is better than a test that looks like it
    // covers it.
    expect(
      WebPointerLock.deltaOf(_mouseMove(dx: 7.0, dy: -3.0)),
      const Offset(7.0, -3.0),
    );
  });
}

/// A `mousemove` carrying the movement a locked pointer would report.
///
/// Built through `MouseEventInit` rather than by setting properties afterwards,
/// because `movementX` and `movementY` are read-only on the event.
web.MouseEvent _mouseMove({required double dx, required double dy}) =>
    web.MouseEvent(
      'mousemove',
      web.MouseEventInit(movementX: dx.toInt(), movementY: dy.toInt()),
    );
