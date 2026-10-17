# 25. The public API rechecked before 1.0 (2026-10-14)

Branch `1.0.0` at `9f4312f64`, read-only. The subject is the committed
snapshots (`packages/*/api/*.api`: 62 snapshots, 135 public libraries,
about 5,500 top-level declarations), the barrels and `lib/src` behind them,
and `tool/structure.dart` with its tables in `tool/structure/`. All 102
structure rules were run once and held (80 s). Counts come from `rg` over the
snapshots and from two throwaway scripts; where a count is a heuristic, it
says so. Findings already in `03-public-api.md` are marked "still open since
03" and are not argued again.

## Summary verdict

The contract has moved a long way since 2026-10-09. Every public class now
carries a modifier: 3,209 `final`, 205 `abstract base`, 59 `base`, and no
plain `class`. Only 20 enums and 9 sealed types are left, each on
`closedForGood` with a reason. Every exception hangs from
`Flutter3dException`, nothing is `@Deprecated`, no type name is declared in
two packages, and null-as-error is gone from the HAL. **Not freezable as it
stands, though.** Four kinds of break remain that only a major can fix later.
First, 139 record-returning members sit on a "pending" list whose own remedy
is a break. Second, five implementable types escape the base-class rule
(`StepClock`, `LightEmitter` and the three Flame interfaces). Third,
pre-1.0 and fast-moving third-party types (dashwire, analysis_server_plugin,
analyzer, vm_service, pointycastle) appear in packages numbered 1.0. Fourth,
built-in render names go on the wire without the `f3d.` that decision 23
asked for. Each is cheap now. Below that is a band of SHOULDs:
`release()` as the teardown verb on GPU nodes, `Settings` without `==`,
public `late final` setters, `BackendId` never done, `UnsupportedError`
used as a capability refusal, the `Matrix4` trap, and naming drift.

## Principles and decisions against the tree

| Principle / decision | Status | Evidence |
|---|---|---|
| A.1 / dec. 5: what a user implements is `abstract base` with defaults | **partial** | All 30 named types are `abstract base` or `abstract base mixin` (`GraphicsDevice`, `PhysicsBackend`, `AudioBackend`, `Storage`, `TimeSource`, `PeerWire`, `XrSession`…). Five escape: `Bridged3d`, `Drawn3d`, `StepFollower` are `abstract interface` (flame_flutter3d `bridged3d.dart:21,45`, `step_clock.dart:11`; still on `interfaceClassPending`, `repository.dart:1711`). `StepClock` is `abstract mixin class` with 3 abstract members (`step_clock.dart:34`). `LightEmitter` is a plain `mixin class` (particles `light_emitter.dart:17`) |
| A.2 / dec. 10: growing sets are open classes; `sealed`/`enum` only on an allowlist | **holds** | 20 enums and 9 sealed types, all 26 names in `closedForGood` (`repository.dart:1740`); 95 in `openedSets`. Every A.2 type is now `final class` with constants (`LightType`, `TextureFormat`, `ColliderKind`, `GameState`, `RacePhase`…) |
| A.3: explicit wire names | **holds** | No `values.byName`/`asNameMap` on a wire; JSON `.name` writes are on classes with explicit names (`UnwrapMethod`, `DriverAxis`, `ConvertOutcome`). Remaining enums read through tables (`project_wire.dart:173`) |
| A.4: no global mutable state | **mostly holds** | `LightingModels.shipped` is frozen (`lighting_model.dart:572`). Left: `HotSwap.instance` (`hot_swap.dart:79`), and `Gamepad.instance` and `PointerLock.instance` on their own 0.5 lines. `SceneNode` keeps process-wide counters (`scene_node.dart:39,48`) |
| A.5: no third-party or private types in signatures | **partial** | `dart_mcp` wrapped (`ToolSpec`, `ToolTableServer` take `StreamChannel` only); `flutter_bloc` gone. 23 entries in `thirdPartyTypeAllowed` (`repository.dart:3234`), several pre-1.0 or fast-moving (see B3). 33 constructors take `this._x`, 14 of them named |
| A.6: backend internals leave the snapshot | **revised, holds as revised** | CPU shaders and `*InfoBlock` moved to `builtin.dart` and `internal.dart`, which the classifier treats as outside semver (`tool/structure/api.dart:223`). `RigidBody` and `CollisionWorld` stay public by the 2026-10-13 decision (`1.0-api-migrations.md:801`) |
| A.7: demos out of packages | **holds** | `flutter3d_demo_content` is `publish_to: none` |
| A.8 / dec. 2: no collisions, no duplicates | **holds, with 4 allowed collisions** | 0 type names declared in two snapshots. `nameCollisionAllowed` (`repository.dart:2482`) keeps `RenderView`, `AssetManifest`, `LicenseEntry`, `Scene`, `FrameInfo`, `ResourceHandle`, `Link`, `Pipe` |
| E.1: American identifiers | **holds** | Rule green, allowlist empty. One British wire word: `OriginPlacement.boundsCenter` writes `'boundsCentre'` (model_core.api:1252) |
| E.2: teardown is `dispose()` | **partial** | `dispose` 97, `close` 23 (connections, writers), but `release()` ends GPU-owning render nodes (S1). The rule cannot see it |
| E.3: creation verbs | **holds** | Rule green; 12 entries in `verbAllowed`. All four device `open`s are async with width and height. Exception: `WgpuSidecar.open()` (S11) |
| E.4: radians, seconds | **holds for angles, drifts for time** | 0 `Degrees`/`Deg`. Time appears as `Duration` (36), `*Seconds` doubles (19), bare `time`/`duration` doubles, and `*Micros` ints (S7) |
| E.5: booleans, no positional bool | **holds** | Rule green; `booleanAllowed` has 2 entries |
| E.6 / dec. 4: exception root | **holds; Dart-core errors drift** | 125 exception types, all under the root; 2 `*Error extends Error`; 0 bare `FormatException`; 0 thrown strings. 207 `throw UnsupportedError` act as capability refusals (S5) |
| E.7: null is not an error | **holds** | HAL `createTextureFromPixels`, `readPixels` and `decodeTexture` are non-null; `nullAsErrorAllowed` has 21 reasoned entries |
| E.8 / dec. 13: ownership, `dispose` on handles | **holds in the HAL** | Every HAL handle type has `dispose`. Render nodes have no lifecycle at all (S1) |
| E.9 / dec. 6: two event styles | **mostly** | `Registration on*`/`listen*` 19, `Stream` 23, `ValueListenable` 9. A few public mutable callback fields remain (`Breaches.onRestore`/`onHole` sim.api:426-427, `PagedSplatOctree.onPage` core.api:3577) |
| E.10: settings `final`, `const`, full `copyWith` | **holds; no `==`** | Rule green. 60 of 61 `*Settings` classes have no `==`/`hashCode` (S2) |
| E.11 / dec. 11: one linear colour type | **holds** | Flutter `Color` only in widget and UI packages (game_ui 118, genres' readout styles). `Vector3` colours only in CPU and shader internals |
| E.12: no sync IO or readback on the main API | **holds** | `SynchronousBufferReadback` only in `backend.dart` and `testing.dart`; `Storage` is async (app.api:640). `writeFileAtomicallySync` is still in app.api:1183,1187 |
| E.14: two imports, no `hide` | **partial** | Quickstart is two imports (`site/content/quickstart.md:108-109`). The `Matrix4` trap forces a `hide` or a prefix (S8) |
| Dec. 10 (2026-10-08): bloc wrapped | **holds** | No `flutter_bloc` in any pubspec; `GameSettingsController implements ValueListenable` (game.api:567) |
| §6.11: `Flutter3dView` the one way in, parameters grouped | **holds** | 21 parameters, grouped into `DeviceSettings`, `ViewSettings`, `LoopSettings` and `PluginSettings` (app.api:142) |
| §6.12: flame_multiplayer on the engine number | **holds** | Both on `1.0.0-rc.1`. This is what makes B3's dashwire case a 1.0 issue |
| §6.14: no `@Deprecated` in 1.0.0, a rule forbids it | **holds by fact, rule missing** | 0 deprecations; 698 transforms across 43 `fix_data.yaml`. `_deprecationsDated` (`rules.dart:5524`, `api.dart:1225`) checks only the message's shape and would pass `Deprecated in 1.0.0, removed in 2.0.0` |
| §6.23: `<pluginId>.` on plugin names, `f3d.` on built-ins | **partial** | Plugin side enforced through `PluginManifest.nameProblem` (sim `engine_loop.dart:1349`, `subsystems.dart:44,133`, elements). Built-ins have no prefix and contain spaces: `RenderAnchor._('after bloom')` (plugin_api `render.dart:231`), `ResourceId('scene_color')` (`frame_plan.dart:133`), steps `'color grade'`. All three are already in the v1 fixture `flutter3d_core/test/fixtures/v1/standard.pipeline.json`. The plan row 2X dropped the built-in half silently (`1.0-rc1-plan.md:364`). No structure rule holds either half |
| §6.24: material AST open with `visitUnknown` | **holds** | `Expression` is `abstract base` (foundation.api:86); `visitUnknown` on the expression, statement and `ResourceSize` visitors |
| §6.25: HAL default bodies, "a new HAL member arrives with a body" | **holds for the shape, no rule for growth** | `PassEncoder` is `abstract base mixin class`. The diff classifier marks an added abstract member major, so the snapshot rule catches it; no separate rule exists |
| §6.35: one way to write a system | **holds** | `StepSystems` and `StepContext` gone; genres take `GenreStepContext` |
| §6.38: `MaterialParameters`, raw map private | **holds** | `Map<String, Float32List>` only at the HAL's `bindUniformBlock` |
| §6.39: `ScriptRuntime` gone | **holds** | 0 hits |
| §6.41: `*Patch` types and `BackendId` | **partial** | `WorldPropertiesPatch` and `RenderSettingsPatch` exist. `BackendId` does not: backends are `String` in `PluginManifest.backends`, `MaterialCompilerRegistry.forBackend(String)` (shaders.api:47), `checkFeatures(…, backend:)` (hardware.api:99,106,289), `runDeviceConformance(backend:)` and `ShaderCompileException.backend` |
| §6.43: one entrance; `stagesFor` not API | **partial** | `ShaderStageNeed.stagesFor` is still public (shaders `stage_need.dart:117`, shaders.api:352). `extraBundles` is gone |

## Findings

### BLOCKER: breaking to fix after 1.0.0

**B1. 139 public members return records, on a list that only shrinks if
somebody breaks them. Still open since 03 (1.2), and the count is now
across all packages.**
`_recordResultsPending` (`tool/structure/repository.dart:3445`) exempts 139
members. The generated reason (`:3439`) promises each "becomes a class
with a recordToClass migration before it is asked to carry more". Under
the semver the same tool enforces, that is a major. About half are
genuine maths tuples (`Portable.sinCos`, `ColorField.hsvToRgb`,
`LightmapLayout.uvAt`, `symmetricEigen3`). The rest are results that will
grow:

- `createProject → ({bool did, String says})` (build `project_template.dart:197`);
- `selectPlugins → (kept, excluded, warnings)` (`plugin_discovery.dart:296`);
- `callGameExtension → Future<({json, refused})>` (editor_play `game_extension.dart:16`), which is a result-or-refusal and wants to be a sealed result;
- `ProjectRoot.tryResolve` (mcp `project_root.dart:95`);
- `RollbackSession.agreedEnd` (net `rollback_session.dart:238`);
- `NativeWorld.readTransforms` and `readFires` (`native_world.dart:2025`);
- `eventsSince`, `renderPost`, `importMeshData`, `ModelHistory.authorship` and `PieceReport.*`.

`recordInResultAllowed` (`:3374`) also lets through record typedefs whose
reason the type already contradicts:

- `LightSample` "fixed by the shading equation" already carries an optional `ltc` and more (cpu.api:126);
- `DescribedElement` has optional `area` and `length` (model_core.api:595);
- `CommandTarget` has four optional fields (mcp.api:141);
- `Held` is "the mixer's own tuple".

*Fix:* sort the 139 into maths tuples, which go to `recordInResultAllowed`
with their reason, and results, which become `final class`es now with
`recordToClass` migrations. Do the same for the 5 typedefs above. Then
change the generated reason, so the list does not promise a remedy that
breaks.

**B2. Five implementable types are outside the base-class contract, and
the rule cannot see four of them.**
`Bridged3d`, `Drawn3d` and `StepFollower` are still `abstract interface`
on the "to-do" list `interfaceClassPending` (`repository.dart:1711`). The
rule passes them while they are listed.

- `StepClock` is an `abstract mixin class` with 3 abstract members (flame.api:590). The wave 3d decision kept it an interface, but it is now a non-`base` mixin class.
- `mixin class LightEmitter` (particles.api:156) can be implemented and extended with no `base`. `TorchFire` uses it (game `fixture_appearance.dart:12`).

`_noNewInterfaces` reads only `interface class`
(`tool/structure/api.dart:1320`, `_isInterfaceClass`). Non-`base` mixins
and mixin classes, the other way to be implemented from outside, are
invisible to it.

*Fix:* make the three `abstract base` with defaults, or write each into
`interfaceClassAllowed` with why it never grows. Make `LightEmitter` a
`base mixin class`. Give `StepClock`'s three members bodies, or record why
it stays. Extend `_isInterfaceClass` to non-`base` `mixin` and
`mixin class` headers.

**B3. Pre-1.0 and fast-moving third-party types in packages numbered 1.0
(A.5).** `thirdPartyTypeAllowed` (`repository.dart:3234`, 23 entries)
lets through:

| Package | Type | Source | Where |
|---|---|---|---|
| flame_multiplayer_dashwire | `WireConnection` | `dashwire ^0.1.0` | dashwire.api:11 |
| flutter3d_lints | `Plugin` | `analysis_server_plugin ^0.3.17` | lints.api:28 |
| flutter3d_lints | `CompilationUnit` in `scanSimulationCode` | `analyzer >=13.2.0 <15.0.0`, a major a year | lints.api:24 |
| flutter3d_editor_play | `VmService`, `Event`, `StreamSubscription<Event>` | `vm_service ^15.3.0` | editor_play.api:24, 27, 32, 86 |
| flutter3d_education_lti | `pc.RSAPrivateKey`, `djwt.RSAPublicKey`, `Map<String, dynamic>` | pointycastle, dart_jsonwebtoken | lti.api:143, 214, 218, 222 |

When dashwire 0.2, analyzer 15 or vm_service 16 lands, these packages
must either hold their users back or break their own 1.0 API.

*Fix, cheapest first:*

1. Put `flutter3d_lints`, `flutter3d_editor_play` and `flame_multiplayer_dashwire` on version lines of their own, as `pad_input` has. Decision 12 would need amending for dashwire.
2. Or wrap: `scanSimulationCode` takes a path or source string, `editor_play` exposes its own `GameEvent`, LTI takes JWK maps and returns opaque key types.

The analyzer plugin's top-level `plugin` is forced by
`analysis_server_plugin`, which is one more reason for lints to have its
own line.

**B4. Built-in render names are on the wire without `f3d.`, contrary to
decision 23.** Anchors (`'after bloom'`, `plugin_api/lib/src/render.dart:231`
and 25 siblings), resource ids (`'scene_color'`, `frame_plan.dart:133`) and
step names (`'color grade'`) are written into `f3d.pipeline` v1
(`flutter3d_core/test/fixtures/v1/standard.pipeline.json`). They also
contain spaces, unlike every other id in the engine. In practice the
collision cannot happen, because plugin names always carry a dot and
built-ins never do. The decision says otherwise, though, and once
pipeline v1 ships, renaming means a format migration.

*Fix:* choose one. (a) Amend decision 23 to "no dot means the engine" and
write that into CONTRACTS and `PluginManifest.reservedNamespace`'s doc. Or
(b) rename to `f3d.after_bloom`, `f3d.scene_color` and so on before rc.1,
with the v1 fixture rewritten. Either way, add the structure rule decision
23 promised.

### SHOULD: fix before 1.0, cheap

**S1. GPU-owning render nodes end with `release()`, and a plugin's node is
never told it is gone.**
`FieldUpload.release` (`field_upload.dart:294`), `WorkloadStep.release`
(`compute_step.dart:375`), `SplatGpuSort.release` (`splat_sort_gpu.dart:214`)
and `EnvironmentDepthNode.release` (`view_layers.dart:240`) each free GPU
memory. The renderer calls them on concrete types (`renderer.dart:6488`,
`renderer_steps.dart:318,368`). `FrameGraphNode`/`RenderNode`
(core.api:1679-1689, 4128-4131) declare no teardown, so a plugin node that
allocates in `setup` or `execute` leaks. The teardown rule cannot fire on
any of this: `teardownVerbs` (`tool/structure/naming.dart:275`) omits
`release`.

*Fix:* `void dispose() {}` on `FrameGraphNode`, called by
`RendererSteps.remove` and renderer teardown. Rename the four to `dispose`
with migrations. Add `release` to the detector, allowlisting the
refcount (`ResourceHandle.release`) and the turn lock (`SceneTurn.release`).

**S2. Value types without equality.** 60 of 61 `*Settings` classes have no
`==`/`hashCode`; only `AxisSettings` has one. This includes `RenderSettings`
(`render_settings.dart:1556`), `BloomSettings` (`:3263`) and the four
`Flutter3dView` groups. `ViewportRect` is `const` with four positional
fields and no `==` (`render_view.dart:423`). Widgets that take these in
`didUpdateWidget` can only compare identity. Adding `==` in 1.x changes
`Set`/`Map` semantics for anyone keying on them. Of the core value types
checked, `LinearColor`, `WorldPosition`, `Quantity`, `Unit`, `Dimension`,
`RenderAnchor`, `WorldRay` and `SimulationVersion` all have it.

*Fix:* add `==`/`hashCode` to every `*Settings`, and extend "a settings
class is final, const, and copies every field" to require them.

**S3. Public `late final` fields without an initializer expose a one-shot
setter.** 54 such sites in `lib/`, among them `EngineLoop.snapshots` and
`EngineLoop.plugins` (`engine_loop.dart:203,283`) and
`IrradianceField.irradiance`, `depth` and `active`
(`irradiance_field.dart:149-175`). A caller can write `loop.plugins = …`,
which compiles and then throws `LateInitializationError`. Removing the
setter later is a break.

*Fix:* a private `late final _x` with a public getter.

**S4. `BackendId` (decision 41) was not done.** Backends are `String`
throughout (list in the table above). A breaking change of the parameter
types is not needed. `extension type const BackendId(String name)
implements String` with `impeller`/`webgl`/`webgpu`/`cpu` constants can be
passed wherever a `String` is taken, so it can still come additively.
Changing the parameters themselves after 1.0 cannot.

*Fix:* decide now: either the extension type, with parameters left as
`String`, or record that decision 41 is dropped.

**S5. `UnsupportedError` is the capability refusal on the backends'
default arms.** 207 `throw UnsupportedError` in `lib/`. Most are `_ =>`
arms of switches over sets that are now open:

- `flutter3d_webgl/lib/src/webgl_formats.dart:41,52,66` and 11 more there;
- `webgpu_formats.dart` 13;
- `gpu_formats_pass_state.dart` 8.

A `TextureFormat` or `PrimitiveType` added in hardware 1.1 then reaches an
outside backend as an untyped `Error`. Decision 25 asked for the typed
`refuse()` / `UnsupportedCapabilityException` (hardware.api:549). Changing
what is thrown later breaks anyone catching it. `ArgumentError` (721) and
`StateError` (285) for programmer errors are as Effective Dart wants.

*Fix:* route backend default arms through `refuse(feature, reason:)`.

**S6. About one public member in five has no doc comment, and nothing
counts it.** This is a heuristic over the export graph: overrides and
unnamed constructors are excluded. It finds 3,610 of 17,805 members and
210 of 4,609 top-level declarations undocumented. The worst are
`flutter3d_hardware` (419 of 1,242 members, 68 of 253 top-level),
`flutter3d_core` (746 of 3,553) and `flutter3d_sim` (387 of 1,882), with
`model_core`, `mesh`, `game_ui` and `physics_native` above 15%.

By file: `hardware/lib/src/trace/trace_event.dart` 167,
`hardware/lib/src/formats.dart` 102, `core/…/ktx2/ktx2_format.dart` 62,
`hardware/lib/src/resources.dart` 50,
`physics_native/lib/src/native_world.dart` 47.

Small visible gaps: `Registration.cancel` and `isCanceled`
(`foundation/lib/src/registration.dart:15,17`), the `ToolSpec` constructor
(`plugin_api/lib/src/tools/tool_spec.dart:96`), `VertexLayout`'s members
(`core/lib/src/geometry/vertex_layout.dart:25-149`).
`analysis_options.yaml` (`:60-76`) does not enable
`public_member_api_docs`.

*Fix:* enable it per package, starting with foundation, plugin_api and
hardware (the outside author's surface), with a pending count in
`repository.dart` that only shrinks, as `unitsUndocumentedPending` does.

**S7. One concept, several names.** Each is a rename with a migration now,
and a major later.

- **Creation callbacks.** `Flutter3dView(onCreated:)` (`flutter3d_view.dart:316`), but `Scene3D(onSceneCreated:)` (`scene_widgets.dart:181`).
- **Advancing time.** `step(double dt)` 49, `update(double dt)` 32 (camera, effects), `advance(dt)` 14 (particles, game_kit, camera), `tick(dt)` 3 (game, racing).
- **Time units.** The contract says seconds as `double`. The surface mixes `*Seconds` (19), bare `duration`/`*Duration` doubles (8, e.g. `MonsterDef.alertDuration`), `Duration` fields inside the simulation (`FrameSpan.from/to`, sim.api:1117), and `*Micros` ints in frame stats (`FrameResult.cpuMicros`).
- **The glTF camera.** `ModelPerspectiveCamera.yfov`, `znear` and `zfar` (`model_camera.dart:18`) beside `fovY` everywhere else. Still open since 03 (3.3).
- **Generic names.** `Outcome` (model_core `command.dart:86`) takes 36 `hide Outcome` lines in `apps/flutter3d_modeler/test`; rename it `CommandOutcome`.

**S8. The `Matrix4` trap.** The engine's signatures name `vector_math`'s
`Matrix4` 100 times in core.api, among them `SceneNode.setLocalMatrix`,
`worldMatrix` and `CameraNode.viewMatrix`. The facade deliberately
re-exports only `Matrix3, Quaternion, Vector2, Vector3, Vector4`
(`packages/flutter3d/lib/flutter3d.dart:1016`), because
`package:flutter/widgets.dart:16` exports `vector_math_64`'s `Matrix4`. So
a user who writes `node.setLocalMatrix(Matrix4.identity())` beside
`material.dart` gets a type error between two `Matrix4`s. The apps carry
15 `hide Matrix4`. Neither the quickstart nor CONTRACTS mentions it.

*Fix, all additive:*

- a sentence and a snippet in the quickstart and CONTRACTS (`import 'package:vector_math/vector_math.dart' as vm`);
- an extension `Matrix4 toEngine()` on `vector_math_64.Matrix4`, under a name that does not collide;
- a `flutter3d_lints` quick fix.

Decide now that the float32 `Matrix4` stays, because changing it later
breaks.

**S9. Collisions kept "until somebody imports both".**
`nameCollisionAllowed` (`repository.dart:2482`) keeps `RenderView`, which
collides with `package:flutter/rendering.dart` (any custom
`RenderObject`), and `LicenseEntry`. The reason itself says "renamed with
a migration before 1.0.0 if a game is seen importing both". No rule can
observe that trigger, and after 1.0.0 the rename is a major.

*Fix:* decide now. `RenderView` is the costly one, because it is the
render-view object of the 3b decisions.

**S10. The deprecation rule decision 14 asked for does not exist.**
`deprecationProblem` (`tool/structure/api.dart:1225`) accepts a
`Deprecated in 1.0.0, removed in 2.0.0.` inside 1.0.0. There are 0
deprecations today, so the decision holds by fact, not by rule.

*Fix:* return a problem when `since` equals the package's version and that
version is `X.0.0` or a pre-release of it.

**S11. Loose entry points.**

- `WgpuSidecar.open()` takes nothing (`flutter3d_wgpu/lib/flutter3d_wgpu.dart:35`). It does not fit `BackendOpener` (width, height), and it is a function that can never take an option without breaking.
- `ShaderStageNeed.stagesFor` is still public, against decision 43 (`stage_need.dart:117`).
- `PeerWire` has two ways to listen for a message, `listen(Map)` and `listenFrom(PeerMessage)` (net.api:152-154).

*Fix:* `open({required int width, required int height})`; make
`stagesFor` private or move it to `internal.dart`; keep one listener
shape.

### LATER: additive, can wait for 1.x

**L1. 131 open sets without `values`/`byName`.** `openSetShapePending`
(`repository.dart:3595-3732`) lists them. Adding these is additive, as its
comment says. The list also holds types that are not sets (`LinearColor`,
`Dimension`, `SamplerDescriptor`, `BufferUsage`, `SolidColorTexture`), so
its detector over-matches. Clean the list, so it says what is true.

**L2. Outside-semver libraries have no guard outside the repository.**
`internal.dart` (shaders, foundation) and `builtin.dart` (cpu) are in the
snapshots and outside semver (`api.dart:223`). The repository rule keeps
the engine's own packages honest, but an application or plugin that
imports them gets no signal. Add a `flutter3d_lints` rule
`avoid_engine_internal_imports`.

**L3. Result types are treated inconsistently.** `ScrubAnswer`,
`CloudFetch` and `CloudPut` are sealed, while `RunStatus` and
`StrategyOrder` are `abstract final` (no exhaustive switch). Moving from
`abstract final` to `sealed` later breaks no code that has a default arm.

**L4. 92 static-only `abstract final class` namespaces.** These are
`EdgeFlags`, `CollisionLayers`, `Portable`, `EnvironmentMap` and others.
Effective Dart says to avoid them, but here they are deliberate constant
tables: keep them.

**L5. Two singletons and one process-wide registry left.**
`HotSwap.instance` follows hot reload, which is process-wide, so it is
acceptable; say so in its doc. `Gamepad.instance` and
`PointerLock.instance` are the federated-plugin pattern on their own
lines.

**L6. `List` versus `Iterable` getters, and live versus snapshot lists, are
undocumented.** Still open since 03 (3.9).

### What the rules claim and cannot see

| Rule (where) | Gap |
|---|---|
| "a type somebody implements is a base class" (`rules.dart:6228`, `api.dart:1320`) | Reads `interface class` only; non-`base` `mixin` and `mixin class` escape (B2) |
| "a type has one teardown verb" (`naming.dart:275`) | `release` is not a teardown verb (S1) |
| "a result a caller reads names no record" | 139 members on `_recordResultsPending`; the exemption's remedy is itself a major (B1) |
| "a signature names only types a caller can import" plus `thirdPartyTypeAllowed` | Allows pre-1.0 packages that A.5 excludes (B3) |
| "no public name collides…" plus `nameCollisionAllowed` | Entries wait for a trigger no rule observes (S9) |
| "every deprecation names its versions" | Does not forbid a deprecation inside x.0.0 (S10) |
| "the plugin API's number moves when the plugin API grows" (`rules.dart:6438`) | Returns nothing until a `v1.x.y` tag exists. This is by design, but plugin_api growth between rc.1 and 1.0.0 is unchecked |
| "an open set carries values, name and byName" | Pending list includes non-sets (L1) |
| `hookParametersAllowed` (135) plus `hookValueParameters` (131) | 266 reasoned exemptions; most are whole HAL classes. Fine, but the largest allowlist in the tree |
| decision 23's rule | Not written (B4) |

## What is good and should stay

- **Modifiers everywhere.** No public plain `class` (`plainClassAllowed` is empty). 3,209 `final` classes keep the surface growable. `SceneNode` and `MeshNode` are `base`: extendable, not implementable.
- **Closed sets decided one by one.** 20 enums, every one explained in `closedForGood`; for example `ShadowCasterFaces`' doc says why it can never grow. 9 sealed types, all operation results. The A.2 list became open classes with explicit wire names.
- **Exceptions.** One root, four families, 125 types, `…Exception` naming, 0 thrown strings, 0 bare `FormatException`.
- **Migration machinery.** Snapshot, classifier, migration table, generated `fix_data.yaml` (698 transforms) and 0 deprecations. The classifier marks an added abstract member and a new sealed subtype as majors, which is what makes the base-class policy enforceable.
- **Naming.** 0 duplicate type names across 62 snapshots, 0 British identifiers, 0 positional booleans, acronyms as words (`Gltf`, `Hdr`, `Lti`), one options suffix (`Settings`; `Descriptor` only in the HAL).
- **Contracts honoured.** Null-as-error converted. HAL handles all `dispose`. `Storage` is async. `readBufferSync` is out of the main library. `dart_mcp` and bloc are wrapped or gone. Flutter `Color` only in widgets. `LinearColor` and `WorldPosition` are value types with `==`.
- **The two facades** re-export by explicit `show` lists (926 names in `flutter3d`, 947 plus 469 in `flutter3d_game`). `Flutter3dView`'s parameters are grouped into four settings objects.
- **Plugin names are enforced at registration** (`PluginManifest.nameProblem`), case-sensitive, through every registry checked.
- **The structure runner proves its detectors before running.** Every exemption table fails on a stale entry, so the lists stay true. The gaps above are holes in what a detector looks at, not rot.
