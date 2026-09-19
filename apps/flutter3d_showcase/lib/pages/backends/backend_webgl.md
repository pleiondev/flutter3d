# WebGL2

In a browser this engine draws through WebGL2 by default, over a canvas the
browser composites into the page. Like every backend page here, this one
does not force WebGL2 open. It reads whichever device actually did.

## Step 1: How the choice is made

A web build registers WebGL2 unconditionally, and WebGPU only when compiled
with a flag that keeps its code out of an ordinary build entirely.

{{code fallback}}

> **Note.** `--dart-define=FLUTTER3D_WEBGPU=true` is a bundle-size decision,
> not a quality one. WebGPU is still the newer, less exercised backend; an
> ordinary web build drawing through WebGL2 is not a fallback so much as the
> default this engine was built against first.

## Step 2: Ask, do not guess

WebGL2 has no polygon mode that draws triangle edges as lines, so it refuses
wireframe the same honest way the software rasteriser does: by answering
false rather than filling the shape and staying quiet about it.

{{code read}}

## Step 3: A setting that asks anyway

This page asks for wireframe unconditionally. The frame's answer has to
agree with whatever the open device said it could do.

{{code settings}}
