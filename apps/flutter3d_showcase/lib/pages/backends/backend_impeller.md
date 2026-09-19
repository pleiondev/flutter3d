# Impeller

On macOS, Windows, Linux, Android and iOS this engine draws through
`flutter_gpu`, Flutter's own rendering layer, itself built on Impeller. This
page does not force that backend open. It reads the device that actually did
open, and asks it what it can do, the same way every ordinary page does.

## Step 1: How the choice is made

Nothing in `flutter3d_app` picks Impeller by name. It registers every native
backend it has and asks a shared registry to open one, trying them in order
until one starts.

{{code fallback}}

> **Note.** A build never names the backend that opened. Two backends
> registered the same way means the fallback needs no change the day a third
> one exists.

## Step 2: Ask what differs, not what it is called

`GraphicsDevice.supportsWireframe` is the one capability that answers
differently on all three backends here: true on Impeller's Metal and Vulkan
path, false on its own OpenGL ES path, false on WebGL2 and false on the
software rasteriser. Asking it, rather than checking a name, is what keeps a
page correct the day a backend's answer changes.

{{code read}}

## Step 3: A setting that asks for it anyway

This page asks for wireframe unconditionally. Whatever the device answers,
the frame has to agree with it: declined when the device cannot draw it,
given when it can.

{{code settings}}

The panel above shows what the device actually open right now says about
itself, not a description of Impeller in the abstract.
