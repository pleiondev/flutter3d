# pointer_lock

Locks the mouse pointer in place and reports its motion as relative deltas.

Flutter exposes no pointer lock on any desktop platform and does not surface the
browser's either, so a first-person camera cannot work out of the box: the
cursor reaches the edge of the window and the view stops turning. This plugin
adds pointer lock on both.

```dart
final capture = MouseCapture.instance;

if (capture.isSupported) {
  await capture.capture();
}

// Once per simulation step:
final delta = capture.takeDelta();
yaw   += delta.dx * sensitivity;
pitch += delta.dy * sensitivity;
```

## Pull, not push

The caller drains the delta with `takeDelta` instead of receiving it from a
stream, because that is the shape a game wants. A simulation on a fixed
timestep asks "how far did the mouse move since the last step" once per step.
A stream of individual mouse events would move the accumulation into every
caller, and each of them would have to get it right.

`takeDelta` is synchronous for the same reason. It is called from inside the
step, and awaiting anything there would mean the step no longer sees a
consistent snapshot of its inputs.

## Releasing

Losing window focus drops the capture and announces it on `onStateChanged`.
Otherwise a hidden cursor would be left over another application, and the user
could not get it back. Treat an unrequested `CaptureState.released` as a reason
to pause.

The plugin does not watch for Escape. Key handling belongs to the application,
which calls `release()` itself.

## Platforms

| Platform | Status | How |
|---|---|---|
| macOS | supported | `CGAssociateMouseAndMouseCursorPosition(0)`, `NSCursor.hide()`, a local `NSEvent` monitor |
| Web, desktop browser | supported | `document.requestPointerLock` through `package:web`. Pure Dart, so nothing is registered and `flutter test --platform chrome` reaches it |
| Web, phone or tablet | not applicable | reported by `(pointer: coarse)`; `isSupported` is false so the game shows its touch controls |
| Windows | not yet | Raw Input plus `ClipCursor` |
| Linux | not yet | `gdk_seat_grab`, or XI2 raw events |
| iOS, Android | not applicable | no pointer to capture; `isSupported` is false |

The backend answers `isSupported`; the caller does not have to guess. An
application can then offer another control scheme instead of discovering the
gap at the first call. The engine above this plugin reads exactly that flag: in
a build where it is false, the camera turns by dragging.

### What a browser does that a desktop does not

A capture must come from a user gesture. The browser refuses
`requestPointerLock` when it is called from a timer, a future or a frame
callback, so ask inside the handler of the press that prompted it.

A refusal arrives as an event, not an exception. It comes as
`pointerlockerror`, and on browsers that return a promise, also as a rejected
promise. The plugin handles both, and a refused capture leaves the state
released instead of pretending it succeeded.

The player can leave without asking. Escape releases the lock, and so does
switching tabs. Both arrive as an unrequested `CaptureState.released`, which is
the signal to pause.

In an iframe the parent page decides. A page embedding the game needs
`allow="pointer-lock"` on the iframe, or every capture is refused and nothing in
the console says why.

## Hot restart

The native side outlives the Dart isolate. Without a reset, a hot restart while
the pointer is captured would leave the cursor hidden, with nothing left that
remembers to ask for it back. So construction always issues a reset first.

## Prior art

[helgoboss/pointer_lock](https://github.com/helgoboss/pointer_lock) (MIT) solves
the same problem across more platforms, and the macOS technique here came from
it. It is not published on pub.dev. This plugin exists because of three things
that package does not do, each of which a game needs:

- no observer for focus loss, so Cmd+Tab strands the cursor system-wide;
- one channel message per mouse event, at a 1000 Hz polling rate;
- no `isSupported`, which a build targeting mobile needs.

## Cost

One platform-channel message per mouse event, carrying a two-element
`Float64List`. Nobody has yet measured whether that shows up in a frame profile
at a 1000 Hz polling rate. If it does, the fix is to accumulate natively and
flush once per frame.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
