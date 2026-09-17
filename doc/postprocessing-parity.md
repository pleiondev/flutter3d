# Postprocessing, against flutter_scene

*Established 2026-09-17/18 by three fan-out surveys: 90 agents, 2 800 tool
calls, 7.8M tokens. Every load-bearing claim was handed to an independent
agent told to refute it and to default to refuted when it could not confirm
from source it had fetched itself. The counts below are what survived, and
what did not survive is kept rather than tidied away, because the pattern in
the failures is the most useful thing here.*

Pinned at `bdero/flutter_scene@77c7dbaae8963cfaf95922d171166a73507408e1`
(branch `master`, monorepo, `packages/flutter_scene`, pubspec 0.23.0). Engine
claims are against `flutter/flutter@master` and our own pinned
`5f77625673`; where a capability is master-only that is said, because it is
the difference between a plan and a wish.

## 1. The premise this started from was wrong

The survey was commissioned as "take ideas from flutter_scene's
postprocessing and plan for parity". That framing assumed flutter_scene is
the thin glTF renderer it was a year ago. It is not. Its postprocessing is
the most developed part of it: a 324-line `POST_PROCESSING.md` publishing an
18-step order, ~25 post passes in `lib/src/render/`, and 133 shaders. Bloom
pyramid, TAA, SMAA, FXAA and MSAA with auto-selection, depth of field with
three quality tiers, SSR, SSAO/GTAO, god rays, a velocity buffer, a depth
prepass, GPU auto-exposure through a 1×1 ping-pong that never returns to the
CPU, four tone curves, a `.cube` LUT, vignette, grain, chromatic aberration,
radial distortion, a selection outline, caller-supplied `PostEffect`s, and
quality tiers with adaptive resolution.

So "parity" was the wrong axis, and finding that out was worth the survey on
its own.

## 2. Where we actually stand

**Architecture: level, and ahead in two places.** The single fused resolve
pass that flutter_scene's own docs argue for is already here.
`composite.frag` *is* that resolve, operator for operator — chromatic
aberration at sample time, AO, bloom, exposure, four tone curves, grade, a
2D-strip LUT applied after the sRGB encode, vignette, grain — one draw, with
defaults that are exact no-ops. Demand-driven buffer production is here and
finer-grained than their declared `Set<RenderInput>`:
`CompiledFrameGraph.isConsumed` plus `optionalReads` decide per frame. The
1×1 white placeholder that makes an absent input an exact identity is
already in the composite, for the same stated reason.

Ahead in two: our graph versions resources, culls nodes nothing consumes, and
releases textures at `retiredAfter` so two non-overlapping passes share one —
which their `render_graph.dart` explicitly declines to do, its class doc
saying it does not cull unused passes. And we have a CPU reference rasteriser
plus 44 golden scenes agreed across four backends. Their repository has 228
test files and zero golden PNGs.

**Effects: plainly behind, and the list is pixels.** No DoF, no god rays, no
lens flare, no SMAA or TAA, no velocity buffer, no GTAO, no AO denoiser, no
dither, no sharpen, no render scale, and a grade of three scalars against
their lift/gamma/gain plus white balance.

**And the same golden set that makes us more trustworthy is what makes
catching up expensive.** A new post effect costs one GLSL stage, a WebGL
transpile, a WGSL translation, a hand-written Dart transcription for the CPU
rasteriser, and a new golden scene whose three GPU sets cannot be recorded on
this machine. Roughly five implementations per effect, where flutter_scene
pays one. Their `render_pass_compat.dart` is a `try`/`NoSuchMethodError` shim
in a published package, so a new engine API costs them one implementation and
no SDK floor bump.

## 3. Can a render-graph step be switched off by name? Yes, in one line

The machinery is built and tested. What is missing is a way to *address* a
node. `FrameGraphNode.isActive` (`frame_graph.dart:140`) is consulted at
exactly one place — `frame_graph_compile.dart:102`, verbatim
`final active = _nodes.where((n) => n.isActive).toList();` — and every
built-in hard-wires its answer to the one settings field it happens to read.

The API is data, not a closure: `final Set<String> disabledPasses` on
`RenderSettings`, defaulting to `const <String>{}`, and line 102 becomes
`_nodes.where((n) => n.isActive && !disabled.contains(n.name))`. A closure
was considered and rejected: every pixel test in this repository is driven
from a `RenderSettings`, and a frame with a predicate applied is a frame no
golden can describe. A predicate also cannot be typo-checked even in
principle, which is the failure `frame_graph_compile.dart:83-88` already
guards against for resource names.

**It must go through the active filter and must not unregister the node.**
`known` is built over all `_nodes` including inactive ones
(`frame_graph_compile.dart:61-78`), so an inactive producer keeps its name
known and a read of it still compiles. The registration block says this twice
already, at `renderer.dart:1726-1730` and `:1770-1775`: a name has to be
*known* for a read of it to compile, and leaving the node out when the
setting is off would make that read conditional too — the branch moved rather
than deleted.

### What happens when a suppressed step's output is still read

This was the crux, and three of the four answers need no new code.

| The read | What happens | Where it is already locked |
|---|---|---|
| Optional | Reader is never starved, gets null | comment at `frame_graph_compile.dart:201`; this is how bloom and ssao work today |
| Hard | Reader is culled with it, transitively, **without throwing** | `produced()` at `:181-187`, fixed point at `:189-202`, test "an inactive node takes its consumers with it, and does not throw" |
| A link in a read-modify-write chain | Free — the next pass binds the version before it | argued at `:96-101`, locked by `frame_graph_test.dart:723` |
| The sole producer of a requested output | **Breaks, four ways, each needing a refusal by name** | below |

So `reflections`, `antialias`, `ssao`, `bloom`, `luminance`, every shadow
node and every present-phase application node degrade correctly with zero
extra code. The four that break:

- `{'composite'}` — no version of `frame` exists, so `renderer.dart:2872`
  hands the caller `_ldrColor` holding whatever was in it: a stale picture
  and no error. The fallback is deliberate and documented; a general toggle
  turns a rare case into a routine one.
- `{'scene'}` — composite starves and the message names `frame` rather than
  `scene`, blaming the wrong node.
- `{'object ids'}` with a pick pending — the requests are already off
  `_pendingPicks` and `_failPicks` runs only from the catch paths, so a
  modeller click awaits forever. `modeler_viewport.dart` awaits
  `renderer.pickPixel` on every press.
- `'reflection probe $index'` — a computed name that exists only on frames
  with that many probes, so a set saved against three probes and loaded
  against one must validate under `assert` and be ignored in release,
  against the graph's usual habit of throwing.

## 4. The switch is not a differentiator. The reason is

This is the answer to "будет очень круто если у нас это будет, а у них нет",
and it is no.

flutter_scene already ships the per-pass boolean for a caller's own passes:
`CustomRenderPass.enabled`, filtered in `Scene._passesAt`
(`scene.dart:1400-1401`), and `PostEffect.enabled` (`:2985`). It withholds it
from its own eighteen built-ins only because those are added under local
bools inside a private method — `wantDof`, `enableFxaa`, `wantGodRays` — so a
flag beside each is an afternoon's work. And a named off-switch is the most
common design point in the industry, not a moat: three.js `Pass.enabled`,
O3DE `Pass::SetEnabled`, Unity URP `ScriptableRendererFeature.SetActive`,
Godot `CompositorEffect.enabled`, Unreal `TOverridePassSequence::SetEnabled`.
If we ship this and call it a differentiator, the first person to read their
source will say so.

Two narrower claims do survive. Their `RenderGraph` is a private
`List<RenderGraphPass>` with one mutator, `addPass` — no remove, no
predicate, no per-pass flag — so they have no demand-driven path to hang a
general switch on, and the semantics of a skipped step (the version chain
closing over the gap) is work they would have to do first. And
`POST_PROCESSING.md:103-104` says it outright: the built-in pipeline is a
fixed sequence; you turn stages on and tune them, you do not reorder them.

**What is actually ours is the opposite question: why a step did not run.**
Across three.js, O3DE, Unity URP, Godot, Bevy, Filament, Unreal and
flutter_scene, not one reports the outcome. Unity's `isActive` and three.js's
`enabled` answer only "did I ask for it". Bevy's bloom node silently no-ops
when a camera lacks the component. Filament's `View.h` will not say whether
SSR survived `setPostProcessingEnabled(false)`. Unreal's
`PassSequence.IsEnabled` is the input read back.

Our compile already computes four distinct answers and throws the distinction
away into a bare `List<FrameGraphNode>`: off by its own setting (the `where`
at `:102`), disabled by name (new), starved by a missing input
(`runnable[i] = false` at `:189-202`), unconsumed (runnable but not in `keep`
after `_reachable` at `:224`). flutter_scene cannot report three of those
even in principle.

And this project has the one user for whom absence is unreadable: an agent
driving `renderProject` cannot look at a 256px picture and infer that the
occlusion it asked for was culled because nothing consumed it. `FrameResult`
already carries `shadowsDenied`, `wireframeDeclined` and `exposure` for
exactly this reason. This is that convention finished, not a new idea.

## 5. The use nobody asked for in those words

Nobody driving this engine says "switch off pass seven". What they ask for,
four times, answered four different ways by hand, is the **measurement
frame** — render this so the bytes are the numbers the material wrote, not a
photograph of them.

- `render_project.dart:313-320` builds `lit.copyWith(tonemap: false,
  exposure: 1.0)` for the weights and wireframe modes.
- `display_modes.dart:157` builds the same pair for the viewport's chips.
- `weight_gradient.dart` builds it a third time.
- `CompositeMix` builds a fourth inside the engine, forcing exposure, tone
  mapping *and* bloom off because "a debug buffer is data rather than light
  and any of the three would misreport it" (`composite_mix.dart:44-46`).

**The four do not agree, and the disagreement is a bug.** `settingsFor` sets
`wireframe`, `tonemap` and `exposure` and touches neither bloom nor
occlusion, so a normals view over a viewport with bloom on is a lie today and
nothing catches it. `forStereo()` is both the precedent and the warning: it
disables by replacing three settings objects, deliberately, which is three
names hardcoded in 2026 that no later effect joins.

## 6. Three defects this survey found in our own code

Found by trying things, not by reading. All three verified directly here, not
taken from an agent's report.

**A second colour attachment with no gate, on a backend that aborts.**
`_toRenderTarget` (`gpu_device.dart:801`) loops over `descriptor.colors` with
no count check. `renderer_scene_pass.dart:83` opens a second attachment in
the ordinary path — `colors: <ColorTarget>[colorAttachment, ?surfaceAttachment]`
— whenever SSAO or reflections consume the surface buffer. There is no gate
anywhere: `maxColorAttachments` and `supportsMrt` return zero hits across
`flutter3d_hardware`, `flutter3d_impeller` and `flutter3d_core`. On
Impeller-GLES that reaches an `FML_CHECK`: the process aborts in release, it
does not degrade. Mitigated only by SSAO and reflections being off by
default, so it needs a user to switch one on.

**And the diagnostic cannot diagnose it.** `probeMultipleRenderTargets`
(`renderer.dart:3101`) opens two attachments itself, so it takes the same
abort it exists to measure. Its own comment says "'looks supported in the
bindings' has been wrong twice in this project already" — and then walks into
it a third time.

**`texelFetch` does not compile in our bundle.** It aborts `impellerc` at the
default GLES target and compiles only with `--gles-language-version=300`,
which `build_shaders.sh` never passes. So every atlas lookup must be
`texture()` at a computed texel centre with NEAREST. This is a live
constraint on every shader row below, not a future concern.

## 7. Engine patches: the answer is nearly none

The user's mandate was explicit — patch `flutter_gpu`, Impeller or anything
else in the engine if it buys a competitive advantage. It mostly does not, and
the arithmetic is the reason.

**Eleven of fourteen "cheap patch" claims were refuted.** They were all of
the form "Impeller already implements this, only the `flutter_gpu` Dart
surface is missing, so the patch is small". The refuters read both sides and
killed: mipmap generation, 2D texture arrays, compute pipelines, storage
buffers, framebuffer fetch, timestamp queries, several enum gaps, more than
one render pass per command buffer, and the compute stage in a shader bundle.
Three survived, and none is worth a row.

Mipmap generation is the instructive one. It looked perfect: `blit_pass.h`
declares `GenerateMipmap`, all three backends implement the hook, and
`context.dart:70-73` documents `CommandBuffer.generateMipmap` — a dangling
doc reference to an API that does not exist, which makes a patch a bug fix
rather than a feature request, the most landable kind. Declined anyway,
because bloom builds an explicit chain regardless and three of our four
backends would need the fallback in any case.

**The shipping path splits the whole question.** A `flutter_gpu` or Impeller
runtime patch compiles into `libflutter`/`Flutter.framework`: every developer
and every CI job needs `--local-engine` and a matching per-ABI build, and a
consumer running `flutter build` on stock stable cannot get it at all. Our
packages are pub.dev packages; a pubspec constrains SDK versions and nothing
else. So a runtime engine patch is a demo, a benchmark, or a proof attached
to a pull request — never a feature of a published package.

`impellerc` is the single exception and therefore the whole answer. It is a
prebuilt **host-only** binary: `shader_bundle_build.dart` resolves
`$SDK/bin/cache/artifacts/engine/<platform>/impellerc`. A bundle it produces
loads on a stock engine while `ShaderBundleFormatVersion` stays 2, and we
ship the built bundle as a package asset. A patch confined to
`impeller/compiler` changes our build machine and nothing a user runs.

**And no engine advantage survives the patch becoming public.**
`flutter_gpu` and `flutter_scene` are written by the same person, so they
learn when a capability lands no later than we do, and they adopt it for one
implementation against our five. Measured lead time on their own
render-to-mip-level change: merged 2026-06-09, stable 2026-08-12, 64 days,
best case. The lead time of a public patch, for us, is zero or negative.

What survives is what the engine can neither grant nor revoke: the CPU
reference rasteriser and the four-backend golden set.

**One inverted trap.** Our own filed `#192449` (sampled depth textures), if
it lands, will tempt us to throw away `surface.a` — which carries view-axis
depth in metres and is exactly what a thin-lens CoC wants. Keep the issue,
forbid the dependency.

## 8. What is possible today and absent from both engines

Every candidate below fits fragment-only, one colour target, no compute, no
storage buffers, no readback, no mip generation, no 3D textures. 65
candidates were swept, 55 claimed as ours-and-not-theirs, 20 went to
refuters, **17 survived and 3 were refuted**: ordered dither, the object-id
outline and selection mask, and screen-space fog from depth. Those three
must stop being sold as differentiation — `gfx-24n` in the earlier plan
carries exactly that claim and loses it.

Worth building, in descending order of whether anyone here would use it:

- **Viewport shading off the surface buffer** — matcap/clay/chrome,
  normals-as-colour, curvature/cavity, depth+normal edge outline. One shader
  with branches, and it *deletes a bug class* rather than adding a look: the
  modeller's normals view currently walks the subject and swaps every
  material, remembering the old one to put back, and its own docstring
  documents what happens when the remembering fails.
- **Camera motion blur by depth reprojection** — needs no velocity buffer at
  all, because `surface.a` is metres along the view axis and `WorldAtDepth`
  in `ssao.frag` already unprojects both ends of the pixel ray.
  flutter_scene built the velocity buffer first and so cannot see this.
- **Radial god rays from screen luminance** — works under an orthographic
  camera with shadows off, which are the two preconditions their own
  `god_rays.frag` refuses, and which is the combination a modeller or
  configurator is most often in.
- **Halation on the bloom pyramid** — four lines, no new stage, no asset.
- **Lens dirt over the pyramid** — one extra sampler, two lines in the
  composite.

And the whole stylise family — Kuwahara, halftone, CRT, ASCII, posterise,
pixelisation, toon depth banding, lens warp, radial blur — every one genuine,
novel against both engines, and close to useless for a CAD/asset audience and
an agent reading 256px renders. Recorded here so nobody re-derives the list;
not planned.

## 9. Rows

The earlier survey produced `gfx-19n`..`gfx-36n` (effects and infrastructure,
no engine change, every one shipping to stock stable the day it is pushed).
This survey adds `gfx-37n`..`gfx-45n` (the toggle and what it enables) and
`gfx-50n`..`gfx-58n` (our own gates plus the upstream ledger — see
`doc/upstream.md`).

**These are not in `doc/model-editor-plan.md` yet.** Adding 27 rows moves the
row counts, the `plan-status.json` entries and the dashboard, and that is a
decision about scope rather than a finding. Lifting them in is one edit when
the call is made.

Land first, in this order, because each is a precondition of the next:

| Row | What | Size |
|---|---|---|
| `gfx-50n` | Refuse the second colour attachment where it aborts, and report the refusal | M |
| `gfx-38n` | Reflections registered and culled, like every other post node — `renderer.dart:1753` is the one that still disobeys the rule the file beside it argues for | S |
| `gfx-37n` | A pass switched off by name, on the settings that carry every other frame decision | S |
| `gfx-39n` | Why a pass did not run, as four answers a caller can tell apart — **the differentiator** | M |
| `gfx-40n` | One measurement frame, instead of the four this repo hand-builds | S |
| `gfx-41n` | A device-free dry run of the frame | M |
| `gfx-42n` | Effect contribution: the same frame with one pass off, differenced exactly | S |
| `gfx-43n` | Viewport shading from the surface buffer, instead of swapping every material | M |
| `gfx-44n` | Depth and normal edge outline, as a second branch of that shader | M |
| `gfx-45n` | Curvature and cavity, as the third branch | S |

`gfx-39n`, `gfx-41n` and `gfx-42n` are the three rows nobody else can write:
each needs the toggle *and* something flutter_scene does not have — a
compile that records why, a graph that survives being compiled without a
device, or a deterministic CPU reference.

### Amendments to the earlier rows

- `gfx-19n` — the published order stops being a doc and becomes the *key
  space* `gfx-37n` and `gfx-40n` read. It must publish exact node-name
  strings, not prose names, and say which are stable and which are computed:
  `'point shadows (static)'` carries spaces and parentheses.
- `gfx-20n` — land first, but stop treating it as a one-off.
  `FrameResult.antiAliasing` is the first instance of "asked for X, got Y"
  and `gfx-39n`'s `skipped` is the general form.
- `gfx-23n` — the anchor identity test needs a fifth fixture, because
  `gfx-43n`/`44n`/`45n` each declare an optional surface-buffer read, and
  declaring it is what attaches the second attachment and switches MSAA off
  for the whole scene pass.
- `gfx-24n` — drop the differentiation claim; it was refuted. The row
  survives on its own merits, which are better anyway.
- `gfx-25n` — this is where the *blanket* disable belongs, not the per-step
  toggle.
- `gfx-28n` — the custom-effect wrapper carries a stable `name` and an
  `enabled` from day one, joining `gfx-37n`'s key space.
- `gfx-29n` — keep and state more firmly: neither flutter_scene nor Filament
  nor Godot ships output sharpening, and folding it into taps `fxaa.frag`
  already fetches costs no new pass. One of only two surviving
  differentiation claims among the effect rows.
- `gfx-30n` — honest downgrade: they ship lens flare, so this is catch-up.
  Add halation to the same commit; the pyramid is the expensive half and
  this row already pays for it.
- `gfx-32n` — the acceptance line gets exact with `gfx-42n`.
- `gfx-33n` — add a precondition readback and a second mode, or the row
  copies flutter_scene's refusal along with their shader.
- `gfx-35n`/`gfx-36n` — honest downgrade: they ship `RenderQualityTier`,
  `RenderQualitySettings` and an `AdaptiveQualityController`.

## 10. What the failures taught, which is the part worth keeping

Three surveys, and in each one the refuters killed the most attractive
findings:

- 24 of 24 claims about flutter_scene's *features* survived. The readers were
  accurate about someone else's code when they fetched it.
- 11 of 14 claims about *cheap engine patches* were refuted. "Impeller
  already has it" is the shape of a claim that feels checked and is not.
- 3 of 20 claims about *what only we could have* were refuted, and two more
  existing rows lost their differentiation claim on the evidence.

The pattern: claims about what exists held up; claims about what would be
easy, and claims about what a competitor lacks, did not. Both of those are
claims about absence, and absence is what a reader confirms by not finding
something — which is also what happens when they look in the wrong place.
