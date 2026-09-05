## 0.5.1

* **The occlusion agrees with Impeller to 0.253% and the reflections to
  zero**, from 0.522% and 0.001%. The surface buffer's alpha no longer holds a
  window depth, which is a number a half float cannot hold usefully past twenty
  metres and which both GPU backends were rounding into bands; see
  `flutter3d_shaders` 0.5.1. `engine_shaders.dart` is regenerated with the new
  block members.
* This backend's check that a bound uniform member exists is what caught the
  block going out of step, in the browser, on the run that introduced it.

## 0.5.0

* **A `WebGlProgram`'s attributes, blocks and samplers are unmodifiable.** They
  describe a program that has been linked; nothing should be adding to them
  afterwards.
* The engine parity reference catches up with a fixture that grew two torches.

## 0.4.3

* **Anisotropic filtering, where the context has the extension.**
  `EXT_texture_filter_anisotropic` is asked for at `create()` like every
  other extension, and `maxAnisotropy` is its ceiling — one without it.
  Every bind sets `TEXTURE_MAX_ANISOTROPY_EXT` beside the four parameters
  it already set, clamped to that ceiling first, because in GL the value is
  texture state rather than sampler state and a number above the ceiling is
  `INVALID_VALUE`: an error in the queue and a bind that did not land.
  `anisotropic-floor` gets a provisional cross-backend budget; its reference
  is recorded at merge.
* **Known, and not fixed here: the minification filter never names the mip
  chain.** `minMagFilterToGl` maps `minFilter` alone, so a trilinear sampler
  binds as `LINEAR` rather than `LINEAR_MIPMAP_LINEAR` — the levels are
  uploaded and `TEXTURE_MAX_LEVEL` is set, and none of them is sampled.
  The anisotropic taps above are therefore taken from the base level, not
  across the chain as `SamplerOptions` describes, and the far half of
  `anisotropic-floor` aliases here where Impeller's blurs and then sharpens.
  The fix is a `TEXTURE_MIN_FILTER` derived from the pair (`minFilter`,
  `mipFilter`) and the texture's level count; it moves every textured
  web golden at once and is its own change.
* **A bundle loaded from bytes, compiled by the browser on first use.**
  `WebGlDevice.loadShaders` reads the bundle's `webgl` section — GLSL ES
  sources by name, as JSON, the document `webgl_bundle_section.dart` writes
  and reads — and `WebGlLoadedShaderLibrary.refresh` recompiles every stage
  already handed out from the new text before swapping any of them, so a
  stage that no longer compiles refuses the whole refresh by name and the
  picture stays. The compiled object is swapped *behind* the handle, which is
  how GL keeps the identity promise flutter_gpu keeps by mutating in place.
* **The program cache keys on the handles, not the names.** Two libraries
  answering one name — a loaded `Pbr` layered over the engine's — used to
  share whichever program linked first; identity is what a pipeline depends
  on, so identity is the key, and a refresh evicts through `forgetPrograms`.
* **A refresh retires the old programs; it does not delete them.** The
  renderer's pipeline cache holds a `PipelineHandle` over the program linked
  from the old code until `Renderer.relinkShaders` runs, and nothing says the
  two happen in one turn: an application refreshing from a file watcher's
  callback draws a frame in between, and that frame used to bind a deleted
  program — `INVALID_VALUE`, and every material on the loaded look gone for
  a frame where flutter_gpu kept drawing the old code. The program is now
  kept until the next refresh or `dispose`, which is what the HAL promises;
  the pixel test reads the frame in between and expects the old colour.
* `tool/pack_shaders.dart` writes a `.f3dshaders` bundle from a manifest and
  impellerc's output, translating the GLSL for this backend the way
  `generate_shaders.dart` does; `tool/source_package.dart` is the package
  resolver both now share. `golden_web.sh` wants the example's own bundle
  built first, since the example's pubspec declares it. The packer reads the
  container through `flutter3d_hardware/shader_bundle.dart`, the Flutter-free
  entry point, and says so on stderr when it stamps the SDK token from a
  `dart` that is not a Flutter SDK's beside an impeller section — the one
  way the header goes wrong silently, and said only then, because a warning
  that fires on every correct run too is read on none of them. An
  `--include` root with a trailing slash is normalised like the package
  root, rather than losing the first character of every key under it.
* **A refresh is held to the header's stage list as well as the section.**
  A bundle whose header dropped a stage in use while its `webgl` section
  still carried the source was accepted; the conformance suite now asks, and
  the refusal names the stage as it did for a source that went missing.
* A pixel test draws a wall through a loaded look, refreshes the bundle and
  reads the new colour back through the same handle.
* **`readback`, through a pixel-pack buffer behind a fence.** `readPixels`
  with a buffer bound to `PIXEL_PACK_BUFFER` is a command in the stream like
  any draw — it reads the texture as the commands before it left it — and
  returns at once where the client-memory form stalls until the GPU has
  drained everything ahead of it. A `fenceSync` says when the copy is done,
  polled on a timer rather than blocked on, since the whole engine runs on the
  thread `clientWaitSync` would block. The region's own y is measured from the
  bottom for a rendered texture, the way the rows already were, and the rows
  inside it are turned over the same way; the conformance check that holds a
  region of a drawn picture to its rows from the top is what found both edges.
* `Luminance` and `ObjectId`, generated with the rest from `flutter3d_shaders`;
  `auto-exposure` joins the golden set, its web reference recorded at merge.
  `ObjectId` samples the material's texture against its cutoff, so a pick
  through a masked material's hole answers with what is behind it.
* A readback of anything but an eight-bit RGBA texture is refused before it
  reaches `readPixels`, by the rule every backend shares. Asked for a
  half-float target, this backend's `readPixels(RGBA, UNSIGNED_BYTE)` was an
  `INVALID_OPERATION` that left the pack buffer at zeros and the future
  completing successfully with a black picture.
* **The stencil test, as context state kept honest.** Enabled whenever the
  attachment carries a stencil and reset to the disabled configuration at
  every pass, so nothing carries over; the reference re-issued with the
  compare, because GL keeps the two on one `stencilFunc`; a stencil clear
  through a write mask of every bit, for the reason the depth clear sets
  `depthMask` first. The reference is narrowed to eight bits before it reaches
  `stencilFunc`, which would otherwise clamp it and make this the one backend
  where a wider value means something else. `stencil-xray` joins the golden set
  with a provisional budget, recorded at merge.
* `Xray` is generated with the rest from `flutter3d_shaders`, and linked
  against all three mesh vertex stages in the parity grid. It is the entry
  point that makes this backend's `setBlend` limitation moot: the index it
  ignores would otherwise have been the only way to keep a silhouette out of
  the surface buffer here.
* **A pass renders into a cube face and a mip level.** A cube attachment goes
  through `framebufferTexture2D` with the face's own target and the level, a
  pass starts with a viewport the size of that level, and a multisample
  resolve lands on the same face and level; `createCubeRenderTarget` is one
  `texStorage2D` on the cube target, so every face of every level is
  attachable and the texture is complete for a mipmap filter with nothing
  uploaded. `supportsRenderToMip` is true. The resolve blits the *level's*
  extent on both sides rather than the base texture's, which nothing in the
  engine needs yet — every pass that names a level is single-sampled — and
  which is where to look when one does.
* **A sampler asking for `MipFilter.linear` gets a mipmap minification
  filter.** GL keeps the mip filter on the minification filter, and a plain
  `LINEAR` reads the base level whatever level `textureLod` names — so a
  prefiltered environment was a mirror at every roughness here. The nearest
  mip filter stays the plain filter, so every picture drawn from single-level
  textures stays where it is; the ones whose textures carry a chain now
  minify through it, which is the filtering the asset asked for and this
  backend was quietly not giving. `particles-textured` is that case in the
  golden set — its sprite is a checkerboard with a hand-built chain and
  `SamplerOptions.trilinearRepeat` under it — so that reference is to be
  re-recorded and its cross-backend budget re-measured in the same pass that
  records `probe-car`. `ProbePrefilter` is generated with the rest;
  `probe-car` joins the golden set, recorded at merge.
* **`setBlendColor` is `glBlendColor`**, and a pass now starts with the
  constant back at transparent black — context state that would otherwise
  carry into the next pass, the same reason the stencil's setters are reset.
  `supportsBlendColor` answers true.

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
