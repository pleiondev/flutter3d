/// One `SKILL.md`, ready to write into a game project — `par-03`'s own
/// output. Every claim in [body] is a fact about the engine as it stands
/// today (a class, a field, a default, an incident a real test now guards),
/// not a general description of what a 3D engine is like.
final class EngineUserSkill {
  const EngineUserSkill({required this.slug, required this.body});

  /// Directory name under `.claude/skills/` — also the SKILL.md's own
  /// `name:` frontmatter field, by the convention every skill in this
  /// repository already follows.
  final String slug;

  /// The whole file, frontmatter included.
  final String body;
}

/// `par-03`: skills for someone building a game *on* flutter3d, as opposed
/// to the skills under `packages/*/skills/*/SKILL.md`, which are for
/// someone working *on* the engine itself. Written into a project by
/// [writeEngineUserSkills] — see that function for where.
const List<EngineUserSkill> engineUserSkills = <EngineUserSkill>[
  EngineUserSkill(
    slug: 'flutter3d-user-idioms-and-pitfalls',
    body: '''
---
name: flutter3d-user-idioms-and-pitfalls
description: Use when a flutter3d scene draws the wrong level of detail, a debug view or wireframe request seems to do nothing, or a RenderSettings change silently reverts something else — the traps that fail without an exception.
---

# What fails silently, rather than with a stack trace

Every trap here has the same shape: the call succeeds, nothing throws, and
the picture is wrong or unchanged. None of them are bugs in the engine —
each is either a documented boundary or a real incident a test now guards —
but all of them cost more time to notice than to read once.

## `LodGroup.select()` is not automatic

A `LodGroup` picks a level by screen coverage, but only when something calls
`select(camera)` — nothing inside the engine calls it for you. Before the
first `select()`, and whenever it is skipped, the group shows the finest
level it was built with, at full cost, at any distance. There is no
exception and no warning: a level with LODs that nobody ever selects against
a camera looks identical to one with no LODs at all, except slower.

```dart
// once per frame, per LodGroup, with the camera the frame is drawn from:
lodGroup.select(camera);
```

A model loaded with `ModelDocument.lods` only becomes a `LodGroup`
automatically when its base mesh is a single surface and every `ModelLod` is
also exactly one surface. A model split across several materials at any
level falls back to drawing every surface directly — still correct, just
never switched by distance, and nothing says so at load time.

## `RenderSettings.copyWith` — every field, every time

Building a settings object from the last one (`settings.copyWith(exposure:
2.0)`) has to carry every other field along, and the class carries a scar
that proves the point: seven fields (`surfaceBuffer`, `showSurfaceBuffer`,
`showShadowMap`, `showStaticShadowMap`, `showPointShadowDebug`,
`reflections`, `fog`) were once missing from `copyWith`'s own parameter
list, so a call meant only to change exposure silently turned reflections
and fog back off and switched four debug views off with them. It is now
caught by `render_settings_test.dart` round-tripping every field through an
argument-less call — if a game wraps its own settings in a similar
`copyWith` (a quality-preset switcher, say), that round-trip test is the
one worth copying, because a dropped field there produces no error, only a
feature that quietly stopped doing anything.

## Wireframe is declined, not drawn wrong

`RenderSettings.wireframe = true` is a polygon mode, and two of the three
backends have no such thing — WebGL2 has no `glPolygonMode` and the software
rasteriser has never implemented one. Both simply decline the request rather
than fail. `FrameResult.wireframeDeclined` is how a caller finds out: check
it rather than assuming a `true` you set actually reached the picture.

## Anisotropy has no effect on a bilinear sampler

`RenderSettings.anisotropy` is applied to every sampler that is trilinear
and asks for none of its own. A material using nearest or bilinear filtering
ignores the setting completely and silently — this matches `flutter_gpu`'s
own rule (anisotropy on a nearest filter is refused there too), but nothing
in this engine surfaces that refusal upward.
''',
  ),
  EngineUserSkill(
    slug: 'flutter3d-user-lighting-and-post',
    body: '''
---
name: flutter3d-user-lighting-and-post
description: Use when lighting, a sky, bloom, ambient occlusion or reflections in a flutter3d scene look wrong, too bright, or unexpectedly expensive — real defaults and the units each setting is actually in.
---

# What is on by default, and what units each number is in

`RenderSettings` bundles every scene-wide shading knob passed to
`Renderer.render` for one frame — nothing here is retained state, so a debug
view can be switched on for one frame and off for the next with no
"switching back" step.

## Defaults that are easy to get backwards

- `tonemap` — **on**. Turn it off only for a debug view whose colour is not
  light at all (a decoded normal, say); a tone curve applied to one of those
  corrupts it into a plausible-looking wrong answer.
- `bloom` — **on** (`BloomSettings(enabled: true)`), but subtle by default:
  threshold `1.0` (display white — nothing below it blooms) and intensity
  `0.06`. A scene with nothing overexposed shows no visible glow even
  though bloom is running.
- `sky`, `reflections`, `ambientOcclusion`, `xray` — all **off** by default.
  Sixty golden images are recorded against there being no sky at all, so
  turning it on changes every pixel a frame did not otherwise draw.

## Sky colour is linear, and the clear colour is not

`SkySettings`'s colours (`zenith`, `horizon`, `nadir`, `sunColor`) are
linear and scene-referred: they are multiplied by `RenderSettings.exposure`
and pass through the tone curve exactly like everything else in the frame.
`RenderView.clearColor`, by contrast, is decoded from sRGB by the renderer.
The first sky value copied from a colour picker will look far too bright,
and it reads as a shader defect rather than as the units mismatch it is.

## Ambient occlusion changes the whole frame's antialiasing, not just the corners

`AmbientOcclusionSettings.enabled = true` makes the scene pass read back its
own surface buffer, and reading that buffer turns MSAA off for the *entire*
scene pass — the average of two encoded normals at an edge is not a normal,
so multisampling and this technique cannot coexist. Switching occlusion on
is therefore also a decision about the antialiasing of everything else in
the picture, which is why the engine's own reference frame for it is a scene
of its own rather than a flag added to an existing one.

## `ReflectionSettings.thickness` is in world metres

Not window depth — a value in the wrong unit there once meant the whole
effect looked broken (a few centimetres near the camera, several metres a
room away, so no single value worked as both "thick enough to be a surface a
ray can land in" and "thin enough that a distant wall does not always
count as a hit"). If a screen-space reflection or occlusion setting is
being hand-tuned and nothing seems to respond, check which quantities are
metres and which are texels or degrees before assuming the pass itself is
broken — `SkySettings.sunAngularRadiusDegrees` and
`AmbientOcclusionSettings.radius` are two more that look interchangeable
and are not.

## A stereo pair needs `RenderSettings.forStereo()`, not a hand-picked subset

Reflections and ambient occlusion both reconstruct world positions from
`views.first`'s camera; on a side-by-side stereo frame that means the right
eye's pass runs against the left eye's matrix — occlusion in the wrong
places and a reflection ray marching along the wrong line, silently, on
half the picture. Bloom is a nearer problem: it blurs across the seam
between eyes. `forStereo()` turns off exactly these three (and only these
three — fog, auto exposure and shadows are correct on a pair and stay on);
reaching for `copyWith` by hand risks disabling the wrong set or leaving a
tuned radius sitting beside a disabled effect, which is a value that lies
about what the frame actually did.
''',
  ),
  EngineUserSkill(
    slug: 'flutter3d-user-performance',
    body: '''
---
name: flutter3d-user-performance
description: Use when a flutter3d scene needs to draw faster — level of detail, anisotropic filtering cost, and which post-processing passes are and are not expensive to leave on.
---

# What actually costs a frame, and what is free until asked for

## LOD is screen coverage, not distance

`LodGroup.select(camera)` (see `flutter3d-user-idioms-and-pitfalls` for why
it has to be called every frame) measures how much of the *viewport's
height* an object's bounding sphere covers, not how far away it is —
`screenFraction` divides the sphere's radius by the half-height of the view
volume at the object's distance, so the same object at the same distance
covers more of a narrow field of view than a wide one. A LOD budget tuned on
one camera's field of view does not automatically transfer to a different
one; `LodGroup.select` takes an explicit `verticalFieldOfView` (or
`orthographicHeight`) for exactly that reason, when the camera in use is not
`CameraNode.projection`'s own.

## Anisotropy is one number, clamped for you

`RenderSettings.anisotropy` is clamped to `GraphicsDevice.maxAnisotropy`
before it reaches a sampler, so asking for sixteen is always safe — a
device that only filters isotropically simply draws the picture it always
drew, with no branch a game has to write for it. The setting only touches
trilinear samplers that ask for none of their own (see the pitfalls skill
for the bilinear case, which pays nothing and gets nothing).

## Ambient occlusion's cost is not only its own pass

Beyond the samples it takes (`AmbientOcclusionSettings.samples`, bounded at
twelve in the shader regardless of what is asked for), turning it on forces
the scene pass to read back its own surface buffer, which turns MSAA off
for the whole frame — a change to the cost and look of every other edge in
the picture, not an isolated line item. Budget it as "antialiasing changes
its shape," not as "one more pass."

## Reflections march a bounded loop, and bound it further yourself

`ReflectionSettings.steps` is a request; the shader's own loop is capped at
64 regardless of what a caller asks for, specifically because a loop a
uniform can lengthen without limit is a hang. A lower `steps` and a larger
`stride` (world metres between samples) both cut cost by covering less
ground per pixel, at the expense of stepping over thinner geometry — the
knob to reach for first on a budget is `stride`, not `enabled`.

## Bloom's cost knob is `levels`, not `intensity`

`BloomSettings.levels` is how many halvings the mip-style chain does; each
one doubles how far the glow can reach, so it is the radius control and the
cost control at once — there is no real mip pyramid underneath it to lean
on for free (this engine builds no mip levels at all), so every level is a
real downsample-and-blur pass. `filterRadius` is a tent-filter width on the
way back up and cheaper to tune than `levels` for the same visual change.

## A stereo frame pays for three effects it should not

See `flutter3d-user-lighting-and-post`'s note on `RenderSettings.forStereo()`
— on a stereo pair, bloom, reflections and ambient occlusion are not merely
wasteful when left on with a hand-picked `copyWith`, they are wrong for the
second eye. `forStereo()` is the one call that turns off exactly the three
that need it and leaves the rest — fog, auto exposure, shadows — alone.
''',
  ),
  EngineUserSkill(
    slug: 'flutter3d-user-playtests-and-network',
    body: '''
---
name: flutter3d-user-playtests-and-network
description: Use when recording or replaying a run (.f3drun / Demo), verifying a run against a reference, or wiring up flutter3d_net's rollback session — inputDelay, the rollback window, and where a checkpoint digest is actually safe to take.
---

# A run is a tape, not a recording of positions

`Demo` (a `.f3drun` file) is a level, a starting `Snapshot`, and an
`InputTape` — replayed through the same simulation the player ran, it
reproduces the run exactly, because a fixed step fed the same intents
always does the same thing. It is deliberately not a recording of
positions: that would survive a physics change silently reaching a
different, wrong destination, and a `Demo` must not.

`Demo` requires `levelHash`, `buildStamp` and `checkpoints` — none are
optional, and a document missing one is refused rather than read with a
gap filled in. The reasoning is the same for all three: a tape replayed
into a level that has since changed walks into geometry that is no longer
there, a bug "reproduced" on a different build may already be fixed, and a
run nobody can verify against its own recorded checkpoints has quietly
degraded into a video nobody can check, only watch.

## `GameRandom` — the seed is the only thing that has to survive a save

A step must reach for no clock and no loose dice (`dart run
tool/structure.dart`'s own rule on this engine's simulation layer, if
building against `flutter3d_sim`/`flutter3d_game` directly rather than
through a shipped genre). `GameRandom(seed)`'s `.state` is one number;
writing it into a save and restoring it on load is what makes a saved
game's future rolls continue rather than restart.

## `NetSession`'s three numbers trade against each other, not independently

`NetSession(inputDelay: 2, maxRollbackFrames: 8, redundancy: 8)` — the
defaults are a starting point, not a universal answer:

- `inputDelay` — steps a captured local input waits before it is applied.
  Too low and a correction fires on almost every step from ordinary
  latency; the number has to fit the connection it runs on.
- `maxRollbackFrames` — how many past steps keep a snapshot a correction can
  restore. `droppedCorrections` (a public counter on the session) increments
  every time a confirmation arrives for a step that has already aged out of
  this window — a non-zero count on a connection the other two numbers were
  actually sized for is the signal the window is too small, not a
  transport bug.
- `redundancy` — how many past steps each outgoing message repeats, trading
  bandwidth against tolerance for a dropped packet.

## `onSettled` is the only correct moment to take a checkpoint digest

A step that has just run is still a guess about the far side until its
confirmation lands — a digest taken the moment a step executes is a digest
of a guess, and two honest peers holding different guesses is not a
desync, only two sides that have not compared notes yet. `NetSession`'s
`onSettled(step, after)` callback fires exactly once a step ages out of the
rollback window, which is the first moment no later correction can ever
touch it again — call `DigestTrace.observe` from there, and nowhere else,
or "did the two sides disagree" and "did they happen to still be guessing
differently this instant" become the same question by accident.
''',
  ),
];
