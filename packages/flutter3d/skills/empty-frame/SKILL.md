---
name: empty-frame
description: Use when a frame renders nothing, renders black, or renders something that looks right and is not — the causes look identical from the picture and each one has a known symptom.
---

# A frame that drew nothing, and why

A black viewport has several causes that look identical, and the picture can
name none of them. `site/content/reference/pitfalls.md` is the full table,
grouped by what you see, because that is what you have when you go looking.
`packages/flutter3d/test/empty_frame_test.dart` pins the sentence each one
produces.

## It will not start

Flutter GPU is enabled **per application**, not per channel: `FLTEnableFlutterGPU`
and `FLTEnableImpeller` in `macos/Runner/Info.plist`, or
`io.flutter.embedding.android.EnableFlutterGPU` in `AndroidManifest.xml`.
Without them the app draws nothing and says nothing about why — and a structure
rule now asks every application that draws whether it asked its platform for the
GPU.

Shaders that stop loading after `flutter upgrade` are the bundle format tracking
the SDK. In a checkout, rebuild both: `flutter3d_impeller/tool/build_shaders.sh`
for the bundle every application links, and `flutter3d/example/tool/build_shaders.sh`
for the one the demo loads at runtime.

## Nothing appears

- `Viewport` and `Scissor` default to a **zero-sized** rect and the API does not
  complain about drawing into one. Set both explicitly every frame.
- There is **no non-indexed draw**. `draw()` with only a vertex buffer bound
  succeeds and renders nothing. Bind an index buffer even when the indices are
  the identity `0, 1, 2, …` sequence.
- Y must **not** be flipped in the projection. Metal NDC has +Y up while the
  framebuffer origin is top-left, which already gives the right orientation.
  Flipping mirrors the image and therefore reverses on-screen winding, so
  culling discards exactly the visible faces.
- `vector_math.makePerspectiveMatrix` produces OpenGL depth `[-1, 1]`; Impeller
  follows the Metal and Vulkan convention `[0, 1]`.
- Frame targets that fail to allocate from the very first frame mean a model was
  put in the scene before the renderer built its targets. Start with an empty
  `Scene`, load asynchronously, swap the node in.

## It looks fine and is not

The most expensive category, because nothing is obviously broken. A setting
wired to a panel but not to the renderer looks completely convincing. A
`copyWith` that drops a field does what was asked *and* something else, and the
something else looks like the feature never worked — `RenderSettings.copyWith`
was missing six fields, so changing the exposure switched reflections and fog
back off.

## The habit worth keeping

When a setting looks like it does nothing, do not argue from the finished
picture. Capture the same frame twice, once with it on and once with it off, and
diff the two. A zero difference is the whole answer.

Two explanations for a broken contact-hardening estimate were argued from a
screenshot and both turned out wrong; the quantity that settled it never left
the shader, and nothing displayed it, so the debugging was five runs of guessing
where it should have been one run of looking.
