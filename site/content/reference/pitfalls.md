---
description: The platform conditions without which Flutter GPU either does not start or silently renders nothing, each with the symptom, the cause and the fix.
---

# Pitfalls

None of these are project setup. They are conditions without which Flutter GPU either refuses to start or silently renders nothing, collected from hitting each one.

They are grouped by what you see, because that is what you have when you go looking.

## It will not start

| Symptom | Cause and fix |
|---|---|
| `Failed to initialize ShaderLibrary: Flutter GPU must be enabled via the Flutter GPU manifest setting` | Flutter GPU is enabled **per application**, not just per channel. Set `FLTEnableFlutterGPU` to `true` in `macos/Runner/Info.plist`, or pass `--enable-flutter-gpu`. On Android the key is `io.flutter.embedding.android.EnableFlutterGPU` in `AndroidManifest.xml` |
| `Failed to initialize ShaderLibrary: Flutter GPU requires the Impeller rendering backend` | Impeller is not the default renderer on macOS yet. Without `FLTEnableImpeller` set to `true` in `Info.plist`, the app only works through `flutter run --enable-impeller` and double-clicking the built `.app` fails |
| Shaders stop loading after `flutter upgrade` | The shader bundle format is tied to the Flutter version. Re-run `tool/build_shaders.sh` |
| `MACOSX_DEPLOYMENT_TARGET is set to 10.15, but the range of supported deployment target versions is 12.0 to 27.0.x` | `flutter create` generates 10.15 and current Xcode will not build it. Raise it to 12.0 in `macos/Runner.xcodeproj/project.pbxproj` |

## Nothing appears

| Symptom | Cause and fix |
|---|---|
| A black viewport with no errors at all | `Viewport` and `Scissor` default to a **zero-sized** rect and the API does not complain about drawing into one. Set both explicitly every frame |
| A draw is submitted, the counter goes up, nothing appears | There is **no non-indexed draw**. `draw()` with only a vertex buffer bound succeeds and renders nothing. Bind an index buffer even when the indices are the identity `0, 1, 2, …` sequence |
| The model is clipped against the near plane, or "half of it vanished" | `vector_math.makePerspectiveMatrix` produces OpenGL depth `[-1, 1]` while Impeller follows the Metal/Vulkan convention `[0, 1]`. The engine's matrix is in `PerspectiveProjection.toMatrix` |
| Everything is culled away | Y must **not** be flipped in the projection. Metal NDC has +Y up while the framebuffer origin is top-left, which already gives the right orientation. Flipping mirrors the image and therefore reverses on-screen winding, so culling discards exactly the visible faces |
| Frame targets fail to allocate, every frame, from the first | A model was put in the scene before the renderer ever built its targets. Start with an empty `Scene`, load asynchronously and swap the node in |

## It crashes

| Symptom | Cause and fix |
|---|---|
| `SIGSEGV` in `AGXG15XFamilyRenderContext setFragmentBuffer:offset:atIndex:` inside `RenderPass::Draw()` | A shader *declared* a uniform block (via a shared `#include`) but never reads it. Reflection still reports the block with a non-zero size while the compiled Metal function binds no buffer for it, and binding that phantom block kills the process with no Dart stack trace. Checking `sizeInBytes` is **not enough**: the permutation needs explicit metadata (`LightingModel.usesFragInfo`), and a shader with no material inputs should not declare the block at all, which is why the header is split into `lib/color.glsl` and `lib/surface.glsl` |
| `Bad state: The shader has no uniform block named "frame_info"` | Impeller reflects a uniform block under its **struct type name**, not the variable name. For `uniform FrameInfo { … } frame_info;` the key is `FrameInfo`. Textures are the opposite: `bindTexture` looks them up by variable name (`base_color_texture`) |
| `A command encoder is already encoding to this command buffer` | Metal allows one open encoder per command buffer, and `flutter_gpu` has no way to end a `RenderPass`. A multi-pass frame needs a **command buffer per pass**, submitted in order — buffers on the same queue execute in submission order, so that is also how the passes get sequenced |
| `failed to bind texture` on one lighting model and not the others | The model's metadata claims a sampler the compiled shader does not have. `LightingModel` now asserts that a model sampling no material maps cannot sample the metallic-roughness one either |
| A texture is bound but the shader has no such slot | The compiler drops a sampler whose result never reaches the output, exactly as it does an unused uniform block. A model that samples a map and then ignores the value — Lambert reading metallic-roughness — ends up without the slot. `tool/build_shaders.sh` prints the compiled binding table so the metadata can be checked against it |
| `Binding has not yet been initialized` when reading assets off the UI isolate | `BackgroundIsolateBinaryMessenger.ensureInitialized(token)` grants a background isolate a working channel but creates no `ServicesBinding`, and `rootBundle` resolves through `ServicesBinding.instance`. Routing `flutter/assets` by hand fails deeper still — Flutter's own reply handler throws on a cast. Keep file reads on the UI isolate and request siblings over a port |
| `PathAccessException … Operation not permitted` when writing a file | macOS Flutter apps are sandboxed. Anything outside `~/Library/Containers/<bundle id>/Data` is refused, so frame captures resolve relative paths against the app's own temp directory |

## It looks wrong

| Symptom | Cause and fix |
|---|---|
| Geometry and lighting flicker under load | `CommandBuffer.submit()` is **asynchronous**. Calling `HostBuffer.reset()` right after it rewinds a bump allocator the GPU may still be reading, so the next frame overwrites live uniform data. Use a ring of ~3 host buffers, one per frame in flight |
| The scene is all ambient, as if the light shone away from the camera | Getters shaped like `readDirection([out])` ending in `result.normalized()` return a **new** vector and leave `out` holding the un-normalised, un-negated value. The renderer read its own variable, the direction was inverted, `N·L` went negative and clamped to zero. Normalise **in place**, and pin it with `expect(returned, same(out))` |
| The background washes out after moving to an HDR target | The clear colour is authored display-referred, but the scene target holds linear light and the composite pass encodes on the way out. Convert the clear to linear or it goes through the encode twice |
| A normal-mapped surface lights from the wrong side, on half the model | The bitangent sign. glTF's bitangent is `cross(normal, tangent) * w`, and it is **minus** dP/dv — texture V grows downwards while a normal map's green channel points up. Deriving `w` from `+dP/dv` gives tangent directions that agree with an exporter to seven digits and signs that are backwards everywhere, which only shows up on mirrored UV islands |
| Textures are upside down on an OBJ import | OBJ texture space has its origin at the bottom left, so V is flipped by default. This is the single most common cause |
| A teapot looks faceted and broken | With no `vn`, OBJ needs **smooth** (area-weighted) normals generated. The format prescribes nothing, files routinely omit them, and the geometry they omit them for is curved |
| Additive particles occlude each other | `setDepthWrite(false)` did nothing until Flutter 3.47. Fixed in the SDK; the software backend mirrored the bug on purpose so the two would stay comparable |
| A character's shadow is drawn as a blurred slab beside them | A directional map fitted to the whole scene. On 120 m × 260 m that is fourteen centimetres of world per texel. Use `ShadowSettings(cascades: 3, resolution: 1024)`, and remember the atlas is `resolution × cascades` wide |
| The view stops turning when the cursor reaches the edge of the window | Flutter exposes no pointer lock on any desktop platform. `packages/pointer_lock` supplies it on macOS by turning off the association between the physical mouse and the on-screen cursor |
| No cursor anywhere after a hot restart | A plugin holding the pointer outlives the Dart isolate, because the engine's registrar owns it. The Dart side comes back remembering nothing, so nothing asks for the cursor back. `MouseCapture` issues a reset on construction for exactly this |

## It looks fine and is not

The most expensive category, because nothing is obviously broken.

| Symptom | Cause and fix |
|---|---|
| Shadows look right but toggling them changes nothing | Check the setting actually reaches `RenderSettings`. A control wired to a panel but not to the renderer looks completely convincing. Capture the same frame with the feature on and off and diff the two, a zero difference is the whole answer |
| Golden references that all pass and all look the same | Five of six lighting goldens recorded byte-identical images: the scene's lighting model reached the UI field but never the materials, so every one rendered as PBR. Swap one reference for another's and confirm the comparison **fails**. A golden suite that cannot fail is worse than none, because it is believed |
| `copyWith` silently turns features off | A `copyWith` that drops a field does exactly what was asked *and* something else, and the something else looks like the feature never worked. `RenderSettings.copyWith` was missing six fields, so changing the exposure switched reflections and fog back off. `test/render_settings_test.dart` round-trips every field through an argument-less call |
| Two runs of the same save diverge | Monster thinking was staggered across steps by `Object.hashCode`, which is an address. It is an ordinal now. Anything using `math.Random` has the same problem — use `GameRandom`, which has readable state |
| A lift will not move while anybody is on it | A `Mover` refuses to move into any body, and a passenger standing on it overlaps where it is about to be on every step. `Rider` is what tells being carried from being in the way |
| A platform stops carrying its passenger | `clearKinematicDeltas()` called before `body.step`. Note it is a *sideways* platform that shows this: a rising lift penetrates the capsule and the controller pushes it out upwards, delta or no delta, so the obvious test passes |
| Monsters walk straight at the player in exactly the corridors where a route matters | The nav grid's cell size. A cell touching a wall has a clearance of one however far the wall is, so at `cellSize: 0.5` a one-metre corridor refuses any body needing clearance two. Bake at 0.25 |
| An agent looks stuck | Two callers sharing one `Navigation` with different destinations. `update` re-targets every field it holds, so the second one's fields quietly flow to the first one's goal |
| The whole population of a level is standing on the roof | One height per column, and the **lowest** surface wins, a ceiling's upper face is a perfectly good standing surface by every local test there is. Where that is genuinely wrong, the bake reports a `LevelIssue` warning |
| There are no enemies, and everything is wired up | The `ActorSystem` was built and never stepped. "Wired up" and "running" are two different claims |
| The first frame after loading spends its whole budget catching up | Loading blocked the ticker and all of that time is in the accumulator. Call `loop.clock.reset()` after a load — none of it happened in the game |

## The habit worth keeping

When a setting looks like it does nothing, do not argue from the finished picture. Capture the same frame twice, once with it on and once with it off, and diff the two. Two explanations for a broken contact-hardening estimate were argued from a screenshot and both turned out wrong; the quantity that settled it never left the shader, and nothing displayed it, so the debugging was five runs of guessing where it should have been one run of looking.
