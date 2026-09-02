## 0.4.2

* The lightmapped vertex stage, generated with the rest from
  `flutter3d_shaders`; `lightmapped-room` joins the golden set.
* **Compressed textures, from the extensions the context actually has.**
  `CompressedTextureSupport` asks for the six extensions once at `create()`
  (ETC2 is WebGL2 core and still has to be asked for), a compressed upload
  goes through `compressedTexSubImage2D` with block-rounded sizes, and
  `supportsTextureFormat` answers from the same table the upload reads, so
  a format it says yes to is one it takes. Verified in a real Chrome: ETC2
  uploads and samples, a chain uploads block by block, a short buffer is
  refused before any GL call, and every LDR format either loads clean or
  throws naming the missing extension.

## 0.4.1

* **Phones render.** The MSAA sample count is now proven at `create()` rather
  than assumed: desktop GL happily multisamples a half-float renderbuffer and
  mobile GLES very often refuses, and the refusal was not an answer at create
  time but a `GL_INVALID_OPERATION` out of `renderbufferStorageMultisample` on
  every frame — a white screen on every phone. Proven by a real one-pixel
  allocation checked with `getError`, not by asking: the Android emulator's GL
  translator advertises the capability and then errors on the allocation
  anyway. Where the driver refuses, the renderer takes its ordinary
  single-sample path and the picture arrives, aliased and alive.

## 0.4.0

* **Shaders and programs are deleted at last.** The library gained `dispose`
  — every cached stage and every linked program — wired into the device's own,
  and counted by `debugTrackedResourceCount`; a failed compile or link deletes
  its object before throwing instead of leaking one per retry.
* Disposing the device loses the GL context and removes the canvas from the
  DOM (the platform-view registry still pins the element; it has no
  unregister). The encoder cleans up its framebuffer and every transient and
  uniform buffer on any failure path, and a second `submit` is a `StateError`
  rather than resolve blits against a deleted framebuffer. `_blitToCanvas` no
  longer leaks a framebuffer per frame when the frame is unreadable.

## 0.3.0

* Regenerated against the current sources, including the environment sampling
  and the composite look.

## 0.2.0

* The GLSL is generated from `flutter3d_shaders` and CI fails on the diff,
  after a stale table turned out to be drawing last month's sky in the browser
  while nothing could see it.
* A pass sets its viewport and scissor to the attachment it draws into rather
  than to the size of the canvas.

## 0.1.0

* A WebGL2 backend: the second implementation of `flutter3d_hardware`, and the
  one that says whether the HAL is a seam or a description of Impeller.
