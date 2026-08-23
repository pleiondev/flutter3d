# flutter3d_hardware

The vocabulary `flutter3d` writes a frame in: texture and buffer handles,
formats, render targets, pipelines, a command encoder and a shader library.

**No implementation, and that is the whole of it.** Three exist —
`flutter3d_impeller` over `flutter_gpu`, `flutter3d_webgl` over WebGL2 and
`flutter3d_cpu` in plain Dart — and what they have in common is this package.
An engine written against it can be handed a backend as a value, which is what
makes a software renderer able to draw the same frame a GPU does and a test able
to check that it did.

## What is deliberately not here

Anything a backend can decide for itself. There is no device enumeration, no
swapchain, no window: an application opens a backend, hands it over, and the
engine never learns which one it got.

## The contract

What a backend must actually *do* is `flutter3d_conformance`, which is a suite
each backend runs against itself. An interface can only say a call exists; the
conformance suite is what says a clear covers the whole attachment and that
uploaded pixels keep their row order.
