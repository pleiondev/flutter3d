---
name: pointer-lock-capturing-the-mouse
description: Use when a Flutter app needs relative mouse motion or a locked cursor — a first-person camera or a browser build — including the browser rules that make a capture fail.
---

# The pointer, held still, reporting how far it moved

Flutter exposes no pointer lock on any desktop platform and does not surface the
browser's, so the cursor reaches the edge of the window and the view stops
turning.

```dart
final capture = PointerLock.instance;

if (capture.isSupported) {
  await capture.capture();      // from inside a gesture handler — see below
}

// Once per simulation step:
final delta = capture.takeDelta();
yaw   += delta.dx * sensitivity;
pitch += delta.dy * sensitivity;
```

`takeDelta` drains accumulated motion rather than a stream delivering events: a
fixed-step simulation asks how far the mouse moved since the last step once per
step, and a stream moves that accumulation into every caller. It is synchronous
for the same reason — it is called from inside the step, where awaiting anything
would mean the step no longer sees a consistent snapshot of its inputs.

## Releasing is a signal, not an error

Losing window focus drops the capture and announces it on `onStateChanged`;
anything else would leave a hidden cursor over another application. **Treat an
unrequested `CaptureState.released` as a reason to pause the game.**

The plugin does not watch for Escape. Key handling belongs to the application,
which calls `release()` itself.

## Ask `isSupported` before offering the control scheme

It is answered by the backend rather than guessed, so an application can offer
another scheme instead of discovering the gap at the first call. False on a
phone or tablet browser, on iOS and Android, and on Windows and Linux, where the
implementation is not written yet. A build where it is false turns the camera by
dragging.

## What a browser does that a desktop does not

**A capture must come out of a user gesture.** `requestPointerLock` from a
timer, a future or a frame callback is refused; ask inside the handler of the
press that prompted it.

**A refusal is an event, not an exception** — `pointerlockerror`, and a rejected
promise on browsers that return one. Both are handled, and a refused capture
leaves the state released rather than pretending.

**The player can leave without asking.** Escape releases the lock, as does
switching tab, and both arrive as an unrequested release.

**In an iframe the parent decides.** A page embedding the game needs
`allow="pointer-lock"` on the iframe, or every capture is refused with nothing
in the console to say why.

## Hot restart

The native side outlives the Dart isolate, so a hot restart while captured would
leave the cursor hidden with nothing left to ask for it back. Construction
issues a reset first, which is why "no cursor anywhere after a hot restart" is a
symptom this package already answers.
