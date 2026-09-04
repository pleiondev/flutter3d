# pointer_lock

Locks the mouse pointer in place and reports its motion as relative deltas.

Flutter exposes no pointer lock on any desktop platform, and does not surface the
browser's either, which makes a first-person camera impossible out of the box:
the cursor reaches the edge of the window and the view stops turning. This plugin
is the missing piece on both.

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

The delta is drained with `takeDelta` rather than delivered by a stream, because
that is the shape a game wants. A simulation running on a fixed timestep asks
"how far did the mouse move since the last step" once per step; handing it a
stream of individual mouse events only moves the accumulation into every caller,
and each of them has to get it right.

`takeDelta` is synchronous for the same reason — it is called from inside the
step, where awaiting anything would mean the step no longer sees a consistent
snapshot of its inputs.

## Releasing

Losing window focus drops the capture and announces it on `onStateChanged`.
Anything else would leave a hidden cursor over another application, which the
user cannot recover from. Treat an unrequested `CaptureState.released` as a
reason to pause.

The plugin does **not** watch for Escape. Key handling belongs to the
application, which calls `release()` itself.

## Platforms

| Platform | Status | How |
|---|---|---|
| macOS | supported | `CGAssociateMouseAndMouseCursorPosition(0)`, `NSCursor.hide()`, a local `NSEvent` monitor |
| Web, desktop browser | supported | `document.requestPointerLock` through `package:web`. Pure Dart, so nothing is registered and `flutter test --platform chrome` reaches it |
| Web, phone or tablet | not applicable | reported by `(pointer: coarse)`; `isSupported` is false so the game shows its touch controls |
| Windows | not yet | Raw Input plus `ClipCursor` |
| Linux | not yet | `gdk_seat_grab`, or XI2 raw events |
| iOS, Android | not applicable | no pointer to capture; `isSupported` is false |

`isSupported` is answered by the backend rather than guessed by the caller, so an
application can offer another control scheme instead of discovering the gap at the
first call. The engine above this reads exactly that: a build where it is false
turns the camera by dragging.

### What a browser does that a desktop does not

**A capture must come out of a user gesture.** `requestPointerLock` called from a
timer, a future or a frame callback is refused — ask inside the handler of the
press that prompted it.

**A refusal is an event, not an exception.** It arrives as `pointerlockerror`, and
on browsers that return a promise as a rejected promise as well; both are handled
here, and a refused capture leaves the state released rather than pretending.

**The player can leave without asking.** Escape releases the lock, as does
switching tab, and both arrive as an unrequested `CaptureState.released` — the
signal to pause.

**In an iframe the parent decides.** A page embedding the game needs
`allow="pointer-lock"` on the iframe, or every capture is refused with nothing in
the console to say why.

## Hot restart

The native side outlives the Dart isolate. A hot restart while the pointer is
captured would otherwise leave the cursor hidden with nothing left that
remembers to ask for it back, so construction always issues a reset first.

## Prior art

[helgoboss/pointer_lock](https://github.com/helgoboss/pointer_lock) (MIT) solves
the same problem across more platforms and is where the macOS technique here came
from. It is not published on pub.dev. This plugin exists because three things it
does not do matter to a game:

- no observer for focus loss, so Cmd+Tab strands the cursor system-wide;
- one channel message per mouse event, at a 1000 Hz polling rate;
- no `isSupported`, which a build targeting mobile needs.

## Cost

One platform-channel message per mouse event, carrying a two-element
`Float64List`. Whether that shows up in a frame profile at a 1000 Hz polling rate
has not been measured yet; if it does, the fix is to accumulate natively and
flush once per frame.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from the
editor's scaffold, which writes one from a template: <https://flutter3d.pleion.dev/first-project/>.
Documentation: <https://flutter3d.pleion.dev>.
