import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart' as web;

import 'pointer_lock_platform_interface.dart';

/// The pointer capture a browser build gets.
PointerLockPlatform defaultPointerLockPlatform() => WebPointerLock();

/// Pointer capture through the browser's own Pointer Lock API.
///
/// **The gap this closes was not a missing platform, it was a missing
/// question.** A browser has had `requestPointerLock` for a decade; this package
/// answered `isSupported == false` for it because it only knew about method
/// channels, and the game above read that answer and turned the camera with a
/// drag instead. So the web build of a first-person game was played by dragging
/// the world around, which is what a phone does because a phone has no choice.
///
/// ## Pure Dart, and therefore no plugin registration
///
/// The whole implementation is four DOM calls. Nothing native means nothing to
/// register, which is also what lets `flutter test --platform chrome` exercise
/// it — see `platform_default.dart`.
///
/// ## Three things a browser does that a desktop does not
///
/// **Capture must come out of a user gesture.** `requestPointerLock` from a
/// timer, a future or a frame callback is refused. In practice the game asks on
/// a click and the browser's transient activation window is seconds wide, so a
/// capture requested a frame or two later still lands — but a capture requested
/// from a load, or after an `await` on something slow, does not.
///
/// **A refusal is not an exception.** It arrives as a `pointerlockerror` event,
/// and on browsers that return a promise it also arrives as a rejected promise
/// nobody is holding. Both are handled here so a refused capture leaves the game
/// in the released state it was already in, rather than in a state where it
/// believes it has the pointer.
///
/// **The player can leave without asking.** Escape releases the lock, and so
/// does switching tab; the browser fires `pointerlockchange` and this reports
/// [CaptureState.released] — the unrequested release a game is meant to pause
/// on.
///
/// ## Where it says no
///
/// A coarse pointer — a phone or a tablet — reports [isSupported] as false. The
/// API is often present there and locking a pointer that does not exist gives a
/// player nothing to move; the honest answer is the one that makes the game show
/// its touch controls instead.
final class WebPointerLock extends PointerLockPlatform {
  WebPointerLock() {
    // Registered once and left registered. Unsubscribing on release would mean
    // a listener whose lifetime has to be right at exactly the moments — a
    // refused capture, a tab switch, a release nobody asked for — when it is
    // most likely not to be, and a `mousemove` handler that returns immediately
    // costs nothing measurable.
    _listen('pointerlockchange', (web.Event _) => _readState());
    _listen('pointerlockerror', (web.Event _) => _readState());
    _listen('mousemove', (web.Event event) {
      if (!_captured) return;
      _deltas.add(deltaOf(event as web.MouseEvent));
    });
  }

  final StreamController<Offset> _deltas = StreamController<Offset>.broadcast();
  final StreamController<CaptureState> _states =
      StreamController<CaptureState>.broadcast();

  bool _captured = false;

  /// The element the lock is asked for, and **it has to be Flutter's own view.**
  ///
  /// This was `document.documentElement` for exactly one session, and the bug it
  /// caused is the reason the choice is written down. A locked pointer does not
  /// merely hide the cursor: the specification says every mouse event is
  /// *targeted at the element holding the lock*. Flutter's pointer binding
  /// listens for `pointerdown` on its view root and for `pointerup` and
  /// `pointermove` on the window — so locking `<html>`, an ancestor of the view,
  /// left the up and move events arriving (they bubble as far as the window) and
  /// the down events landing on an element no Flutter listener is attached to.
  ///
  /// What that looks like in a game is precise and misleading: **the camera
  /// turns and the trigger does nothing.** Half the input works, so the capture
  /// looks correct.
  ///
  /// `flutter-view` is the tag the framework gives that root, and the fallback
  /// is the old answer — a document with no Flutter view in it is a test page,
  /// where locking the document element is exactly right.
  web.Element get _target =>
      web.document.querySelector('flutter-view') ??
      web.document.documentElement!;

  @override
  bool get isSupported {
    // Feature-detected rather than assumed from a browser list, and detected on
    // `document` because that is where the exit half lives — an element always
    // has a `requestPointerLock` property on the interface whether the browser
    // implements the feature or not.
    if (!web.document.has('exitPointerLock')) return false;

    // A phone or a tablet: the API may well be there, and there is no pointer
    // for it to hold. Answering false here is what puts the on-screen stick on
    // the screen, so this line decides more than it looks like it does.
    return !web.window.matchMedia('(pointer: coarse)').matches;
  }

  @override
  Stream<Offset> get deltas => _deltas.stream;

  @override
  Stream<CaptureState> get stateChanges => _states.stream;

  @override
  Future<void> capture() async {
    if (!isSupported || _captured) return;

    // **Called for its side effect and not awaited**, and the return value is
    // read through `callMethod` rather than through the typed binding because
    // the two live specifications disagree about it: the newer one returns a
    // promise, the older one returns nothing, and `package:web` types it as the
    // former. Awaiting `undefined` on a browser that implements the older shape
    // is a type error in the middle of the one call this class exists to make.
    //
    // When it is a promise, its rejection is swallowed here: the refusal is
    // already reported through `pointerlockerror`, and an unhandled rejection
    // would put a red line in the console for a case the caller has handled.
    final returned = (_target as JSObject).callMethod<JSAny?>(
      'requestPointerLock'.toJS,
    );
    if (returned.isA<JSPromise<JSAny?>>()) {
      unawaited(
        (returned! as JSPromise<JSAny?>).toDart.catchError((Object _) => null),
      );
    }
  }

  @override
  Future<void> release() async {
    if (!_captured) return;
    web.document.exitPointerLock();
  }

  @override
  Future<void> reset() async {
    // No `_captured` check: the point of reset is a Dart side that has been
    // replaced by a hot restart and remembers nothing, while the browser is
    // still holding the pointer from before it.
    if (web.document.pointerLockElement != null) {
      web.document.exitPointerLock();
    }
  }

  /// The motion a locked `mousemove` carries, in logical pixels.
  ///
  /// Visible for testing, along with [debugTarget], because they are the two
  /// things a test can check without a real capture: a browser refuses
  /// `requestPointerLock` outside a user gesture, and a test harness has no
  /// gestures to offer.
  ///
  /// CSS pixels are Flutter's logical pixels on this platform, so there is no
  /// scaling to do — and doing any would make the sensitivity of a browser build
  /// differ from a desktop one on the same monitor.
  @visibleForTesting
  static Offset deltaOf(web.MouseEvent event) =>
      Offset(event.movementX, event.movementY);

  /// The element [capture] would lock, so a test can say which one that is.
  ///
  /// Pinned because getting it wrong costs half the input and looks like it
  /// works: see [_target].
  @visibleForTesting
  web.Element get debugTarget => _target;

  void _readState() {
    final captured = web.document.pointerLockElement != null;
    if (captured == _captured) return;
    _captured = captured;
    _states.add(captured ? CaptureState.captured : CaptureState.released);
  }

  void _listen(String type, void Function(web.Event) handler) =>
      web.document.addEventListener(type, handler.toJS);
}
