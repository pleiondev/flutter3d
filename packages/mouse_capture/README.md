# mouse_capture

Locks the mouse pointer in place and reports its motion as relative deltas.

Flutter exposes no pointer lock on any desktop platform, which makes a
first-person camera impossible out of the box: the cursor reaches the edge of the
window and the view stops turning. This plugin is the missing piece.

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
| Windows | not yet | Raw Input plus `ClipCursor` |
| Linux | not yet | `gdk_seat_grab`, or XI2 raw events |
| iOS, Android | not applicable | no pointer to capture; `isSupported` is false |

`isSupported` is a whitelist rather than a try-and-see, so an application can
offer another control scheme instead of discovering the gap at the first call.

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
