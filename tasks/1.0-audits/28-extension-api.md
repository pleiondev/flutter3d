# 28. The extension API before 1.0 (read-only audit, 2026-10-14)

This audit reads the working tree of branch `1.0.0` at `9f4312f64`. It covers everything a third party extends:

- plugins and their lifecycle;
- render steps and frame-graph nodes, compute and workloads;
- lighting models, light types, shadow producers and decals;
- draw-list, LOD, skinning and pacing hooks;
- post effects, codecs and decoders;
- data and Wasm plugins;
- editor pieces, panels and MCP tools;
- `create plugin` templates and conformance.

It checks each against decisions 17, 21–24, 26, 28, 37, 42–44 and D22b (`tasks/1.0-readiness-review.md` §6, `tasks/1.0-rc1-plan.md` rows 2X/2X3/2K). It builds on audit 10, which mapped the same surface on 2026-10-09 before waves 2.2 and 3.

Abbreviations used for paths:

| Short | Path |
|---|---|
| **P** | `packages/flutter3d_plugin_api/lib/src` |
| **R** | `packages/flutter3d_core/lib/src/engine/render` |
| **F** | `packages/flutter3d_core/lib/src/formats` |
| **PR** | `packages/flutter3d_plugin_runtime/lib/src` |
| **API.md** | `packages/flutter3d_plugin_api/API.md` |

No tests were run. A claim marked "read" was checked in the code. Everything else is cited to the line that says it.

Severity:
- **BLOCKER**: the shape must change before the tag, because 1.x cannot change it without a break.
- **SHOULD**: fix before the tag, but a 1.x patch or minor could still do it, at the cost of a behaviour change or a broken promise in the docs.
- **LATER**: additive in 1.x.

## Verdict

The plugin kernel is in good shape for a 1.0. That covers the manifest, versions, dependency ordering, step-boundary switching with a journal, registries scoped per plugin and per engine, `<namespace>.` enforcement, `base` classes with defaults, open value classes, and `API.md`. Most D22b hooks exist, are exported, are documented, and have a test. Seven of them have a render conformance check that runs on all four backends.

Three shape problems should be fixed before the tag:
1. **Four `RendererSteps` registrations are asynchronous** (`Future<Registration>`), but `install` is synchronous. They race with disable and lose their errors.
2. **Lighting models are named `<ns>_Name`**, while every other plugin name is `<ns>.name`. These names are written into material and level files.
3. **`FrameGraphBuilder.place` is a public method that nothing wires**, so a node that calls it is dropped from the frame.

Several hooks also exist on paper but do not reach production:
- plugin texture codecs are never consulted;
- plugin shader needs are dropped by the build;
- `placeSkinningHook` refuses every outside plugin;
- `viewIndex` is 0 in every node;
- `RuntimeShaders` is constructed by nobody.

There is no fault isolation: a throwing plugin node loses every frame. The Wasm render ABI (D28/D29) is reserved and not implemented.

## 1. Hook status

"Conf." is the render conformance in `flutter3d_conformance_render/lib/src/render_checks.dart:57-65`. It runs on CPU and a recording fake on every CI run. It runs on WebGL2, WebGPU and Impeller only in the nightly job (`.github/workflows/nightly.yml:72-78`, the self-hosted Mac). None of the render checks counts toward the badge: `earnsBadge` reads the seven loop-level checks only (P/… `flutter3d_conformance/lib/src/plugins/plugin_checks.dart:21-29`).

| Decision / hook | Status | Evidence |
|---|---|---|
| D20 `RenderStep.velocity` as its own step | done | R/render_step.dart:420; tests `flutter3d_core/test/engine/frame_views_test.dart`; Conf. `render.velocity` |
| D20 `FrameContext.previousViewProjection`, `views`, `viewIndex` | partial | Declared at R/render_node.dart:100,111,121; `perView` at :127. **`viewIndex` is never passed when nodes run** (R/renderer.dart:5770-5797 builds `RenderFrame` without it), so `perView()` returns the base id in every node. Only contributors get real indices (R/renderer_scene_pass.dart:582). This contradicts the promise at R/render_node.dart:108-110. No conformance |
| D21 extra uniform blocks and textures for a plugin lit model | done | `MaterialSlotTable` F/material_language/material_slots.dart:133; binding R/renderer_mesh_encode.dart:1527-1560; budget `flutter3d_shaders/lib/src/stage_budget.dart:36,41` (3 textures, 4 blocks, frozen); ABI in `docs/CONTRACTS.md:471-520`; Conf. `render.lit model`, `render.lit model defaults`. WebGPU refuses own slots at run time (build-time only) |
| D22 light-loop hook (own `LightType`, packing) | done, narrow | `LightTypeHook`/`LightTypes` R/light_types.dart:62,76; codes from 16 (:85); Conf. `render.light type`. The engine's lit stages **skip** plugin lights, so only a plugin's own lit model sees them (API.md:950-953). `LightBuffer.maxLights = 8` is constant |
| D22 replaceable shadow producer incl. cube atlas | done | `ShadowTechnique.shadowMapProducer`/`cubeAtlasProducer` R/shadow_technique.dart:363,378; called R/renderer_shadow_pass.dart:622,643,1111,1127; Conf. `render.shadows`. Chosen through settings, **not a registry**, so it is not scoped to a plugin. `name` is free text (:328) |
| D22 decals through a `LightingModel`, limits as settings | done | `DecalNode.lighting` scene/decal_node.dart:97; `DecalSettings` R/render_settings.dart:950, caps fixed at 16/4 (:975,:978); Conf. `render.decal` |
| D22b declared vertex attributes and layouts (instanced, lightmapped) | partial | Fixed variants only: `vertexVariants` F/lighting_model.dart:402, `MeshVertexLayouts` R/renderer_resources.dart:354-380. A plugin cannot declare an attribute. Instance data is fixed (`i_row0-2`, `i_color`, `i_data`). A stage cannot be skinned and instanced at once (material_glsl.dart:408-410). No conformance |
| D22b/D37 plugin resources and MRT as API | done, with holes | `FrameGraphNode.setup(FrameGraphBuilder)` R/frame_graph.dart:188; `create` :245; `FrameGraph.compile` R/frame_graph_compile.dart:104. Holes: `ResourceDesc` is texture-only (R/resource_desc.dart:127-138). `FrameResources.declare` from `execute` is not namespace-checked and can overwrite an engine description (R/frame_resources.dart:248). **`FrameGraphBuilder.place` is never wired** (no `placer` is passed), so a node that calls it is dropped as unsupported |
| D22b per-view resources, view list | partial | `FrameView.resource` R/frame_view.dart:123,134. Broken for nodes by the `viewIndex` issue above |
| D22b `RenderList` hook (culling, sort key) | done, narrow | `DrawListHook` R/render_hooks.dart:59, called R/render_list.dart:237-243,406-414. It can only narrow the list, and the first hook to answer a sort key wins. The context has no material or bounds and is a shared mutable object (:428). No conformance |
| D22b `TextureCodecRegistry` | **done in API, dead in production** | `TextureCodecs` F/texture_codecs.dart:66 (per engine, namespaced :87-101). Its only consumer is `uploadEncodedImage(codecs:)` (`flutter3d_core/lib/src/engine/assets/texture_upload.dart:157-175`), and **no production caller passes `codecs:`** (read: `flutter3d/lib/src/engine/assets/model_asset.dart:239`, `material_loader.dart:173`, `flutter3d_app/lib/src/level/level_loader.dart:515,860`, `hot_swap.dart:331`) |
| D22b LOD policy hook | done, narrow | `LodPolicy` R/render_hooks.dart:99. **The last one added wins silently** (:376). The context has no node or mesh. No conformance |
| D22b skinning hook beside `SkinBlend` | **broken for plugins** | `SkinningHook` R/render_hooks.dart:171. `placeSkinningHook` R/renderer_steps.dart:391-410 names its node `'skinning N'` and then calls `addNode` on the scoped view. `_inNamespace` (:194) refuses that name with a `PluginException` for any plugin that is not the engine's (read). Its only test calls it unscoped (`flutter3d_cpu/test/skinning_hook_test.dart`). Shadow, pick and instanced draws still use the engine's skinning (R/render_hooks.dart:165-166) |
| D22b pacing hook | partial | `PacingPolicy`/`QualityPolicy` R/render_hooks.dart:308,347 are fields on `FramePacing`/`AdaptiveQuality` (`Renderer.pacing` is a mutable field, R/renderer.dart:981). The application can set them; **a plugin cannot register one**, and nothing tracks it when the plugin is switched off |
| D22b/2K compute steps with typed refusal | done | `ComputeStep` R/compute_step.dart:106, `refusal` :158; `ComputePlacementException`, `ComputeRefusalReason` (open class) `flutter3d_hardware/lib/src/compute_placement.dart:114,174`; `PassSkip.unsupported`. Tests: `compute_step_test.dart`, `flutter3d_cpu/test/compute_wiring_test.dart`. Device-level `computeChecks` exist; **no plugin compute check** (`PluginRenderPoints` has no compute member) |
| D22b `.f3dmat compute` on WebGPU | done | Per `site/content/reference/material-language.md:226-244`; Impeller/WebGL2 refuse with `UnsupportedCapabilityException(DeviceFeature.compute)` |
| D22b/D28/D29 Wasm plugins on the render surface | **missing** | Only the constants exist: `wasmRenderAbi`, `wasmRenderNodeExport` (PR/wasm/abi.dart:34-56). API.md:1177-1184 calls it "reserved". D28 (readiness review :1276-1282) moved it into rc.1. A `.f3dplugin` can carry Wasm systems beside `materials`/`renderSteps`, but a module cannot drive a node. There are no data sections for light types, vertex layouts or LOD tables (deferred, `tasks/1.0-api-migrations.md:625-635`) |
| D23 `<pluginId>.` on every registration, `PluginException` | done, with holes | `nameProblem` (P/manifest.dart:389) is called from about 25 registries (read). Holes: `RendererSteps.provide` (R/renderer_steps.dart:525) lets any plugin claim a built-in step; `addMaterials` (:630) lets a plugin library shadow built-in stages; `addContributor`/`removeContributor` (:476,:484) are unchecked and unscoped; `FrameResources.declare` (above); `ShadowTechnique.name`; hook objects carry no names at all. Lighting models use `<ns>_Name` (F/lighting_model.dart:631-643), not `<ns>.name`. Hook-compiled material names have neither a namespace check nor a cross-package collision check (`flutter3d_build/lib/src/shader_build.dart:684-700`) |
| D23 registries per engine instance | done | `PluginRegistry` doc P/registration.dart:41-45; `LightingModels` per renderer (R/renderer_steps.dart:791); `MaterialCompilerRegistry` per build or engine (`flutter3d_shaders/lib/src/material_compiler.dart:172-179`). The only process-wide state is the frozen `LightingModels.shipped` (F/lighting_model.dart:576) and `FrameCompute.of`, an `Expando` keyed by device |
| D23 render conformance on four backends | partial | 7 checks (render_checks.dart:57-65): GPU backends nightly only; not part of the badge; no compute, draw-list, LOD, skinning, codec or vertex-layout check |
| D24 material AST opened, visitor with `visitUnknown` | done (shape) | `MaterialStatement` F/material_language/material_ast.dart:687, visitor :701/:709; expressions are foundation's `Expression` (`flutter3d_foundation/lib/src/expressions/expression_ast.dart:422`); `ResourceSize` R/resource_desc.dart:14 with visitor. **A plugin still cannot add an expression**: `parseMaterial` takes no hook and builtins are fixed (`material_parser.dart:216-225,458`). `ResourceSizeVisitor` has no test |
| D17/D21 build hook compiles plugins' `.f3dmat`; typed missing-stage refusal; `doctor` | partial | The hook compiles `assets_src/**/*.f3dmat` of every package with the plugin marker (`shader_build.dart:625-701`). `MissingShaderStageException` (`flutter3d_shaders/lib/src/stage_need.dart:141-195`) is thrown in four places. **Plugin shader needs are dropped**: `ShaderStageNeed.byName` knows only engine needs and `shader_build.dart:333` discards the null (read). The WebGPU section is silently skipped without `glslangValidator`/`naga` (`flutter3d_build_hooks/lib/src/material_compile.dart:156-158`). `doctor` checks neither missing stages, unknown needs nor the WebGPU toolchain (`flutter3d_build/lib/src/doctor.dart:262-372`) |
| D26 `MaterialCompilerRegistry` | done in API, not in the build | Consulted by `RuntimeShaders` (`flutter3d_core/lib/src/data_plugin/runtime_shaders.dart:252-298`) and by `material_compile.dart:364-410`. But `shader_build.dart:30-35` says the hook, `flutter3d shaders` and `material_build.dart` "hand it none yet", so an outside backend's compiler never runs in a project build |
| D42/D43 one entrance per thing | done | `extraBundles` is internal (`flutter3d_impeller/lib/src/gpu_device.dart:1589-1603`). `LightingModelAddon.stagesFor` is gone from `flutter3d_core.api`. (`ShaderStageNeed.stagesFor` in `flutter3d_shaders.api:352` is a different, legitimate API) |
| D44 `f3d.pipeline`, `RendererSteps.fromDocument` | done | F/pipeline_document.dart:121; R/renderer_steps.dart:667 (rolls back on failure :745-748). The document's `reads`/`writes` are not compared with the node it makes |
| D37 `SceneBinding` | done | P/scene_binding.dart; core `SceneBindings`; `.f3dplugin` `bindings` |

## 2. Developer journeys

### (a) A custom material, unlit and lit, shipped as a pub package for Impeller, WebGL2, WebGPU and CPU

**Files the author touches:**
- `pubspec.yaml`: the `flutter3d_plugins:` marker, and optionally `shaders:`.
- `assets_src/hair.f3dmat`.
- `lib/hair.dart`: a `LightingModelAddon` or a plugin calling `host.registry<LightingModels>().register` (F/lighting_model.dart:566) and `RendererSteps.addMaterials`.
- A test using `checkPluginRender`.

**Friction:**
1. There is no `create plugin --kind material` (`flutter3d_build/lib/src/plugin_template.dart:37-92`) and no end-to-end guide. The pieces are spread over `material-language.md`, `asset-pipeline.md`, API.md §18 and CONTRACTS.
2. The lit path is build-time on two of four backends. Impeller refuses every run-time compile (`runtime_shaders.dart:385-391`). WebGPU refuses lit, `vertex`, scene depth, own slots and `instance` at run time (`flutter3d_core/lib/src/data_plugin/material_wgsl.dart:77-113,426-441`). The application's build hook therefore must run, and must have `glslang` and `naga`, or WebGPU silently lacks the section.
3. **Loading the bundle the hook wrote is left to each plugin.** No engine or app code constructs `RuntimeShaders` (the only non-test mention is a doc comment, `flutter3d_webgpu/lib/src/runtime_material_host.dart:19`). There is also no helper that loads `EngineBundleStamp.projectMaterialAsset`. `asset-pipeline.md:293` says plugin loaders do this; none does.
4. `LightingModelAddon` takes an already-loaded `ShaderLibrary` in its constructor (`lighting_model_addon.dart:22-40`). Discovery needs a constructor that takes nothing (`plugin_discovery.dart:4-12`), so a model with its own stages cannot be installed by discovery alone. There is no asynchronous "load your assets" step in the plugin lifecycle.
5. `shaders: [acme.hair]` in the pubspec is accepted and silently dropped (above). A missing stage then reports no plugin need.
6. A plugin's model is `acme_hair_Hair`, while its light type is `acme_hair.tube` and its step is `acme_hair.glow`. Material files store the first form.
7. The engine's own `.fmat` loader reads against `LightingModels.shipped` (`flutter3d/lib/src/engine/assets/material_loader.dart:97`). The modeller's material commands list only built-ins (`flutter3d_model_core/lib/src/material_commands.dart:891`). A material file naming a plugin model therefore falls back to a default.
8. Run-time materials from a data plugin build a model with `shaderName: name` and do not register it in `LightingModels` or check its namespace (`runtime_shaders.dart:595-601`).
9. Conformance on GPU backends needs the author to build and supply a bundle per backend (`checkPluginRender(materials:)`; the sample does this with a private `tool/build_bundle.dart`, `packages/flutter3d_plugin_runtime/example/gpu/README.md`).
10. Docs contradict each other: `material-language.md:66` still says a surface texture "must be a slot the engine binds", against :7 and :31. The backend table has no row for own slots.

### (b) A custom post-processing effect

**Path:** `FullscreenEffect.material(...)` or `.overlay/.present` (`flutter3d_core.api:1928-1937`), with `RendererSteps.addStep` and `addNode(at: RenderAnchor.beforeTonemap)`. Template `--kind render-step` covers this.

**Friction:**
1. The parameters of `.overlay/.present` are raw `Map<String, Map<String, Float32List>>` keyed by block name, as a mutable field (`flutter3d_core.api:1933`). D38's typed parameters reached materials but not this constructor.
2. The `.f3dmat` fullscreen route is fine.

This is the most finished journey.

### (c) A render step reading depth and normals and writing a new target

**Path:** a `RenderNode` subclass; `setup(builder)` with `read(FrameResourceIds.surfaceBuffer)` and `create(ResourceDesc(id: 'acme.mask', …))`; `execute(RenderFrame)` drawing through `frame.device` / `frame.services.drawFullscreen`. Encodings are frozen in API.md:823-833.

**Friction:**
1. A per-view node reads `viewIndex == 0` always.
2. A buffer cannot be created by the graph, only provided.
3. `place` is a trap (above).
4. An exception in `execute` loses the frame, every frame (§3).
5. There is no conformance check for a plugin node's output beyond "the pass ran".

### (d) A custom compute step

**Path:** `ComputeStep` (R/compute_step.dart:106) with `.f3dmat compute` kernels; `RendererSteps.addComputeStep`.

**Friction:**
1. `addComputeStep` returns `Future<Registration>` (R/renderer_steps.dart:274-285), and so do `addWorkload` (:304), `addFieldUpload` (:350) and `placeSkinningHook` (:391). `install` is `void` (P/manifest.dart:562), so the plugin cannot await. The consequences:
   - A placement that throws becomes an unhandled asynchronous error.
   - If the plugin is disabled while `prepare` is pending, the later `addNode` is tracked into a scope that has already been cleared. The node stays in a disabled plugin's frame.
   - Re-enabling then collides on the name.
2. Two "Breaking in 1.0.0-rc.1+1" notes on these methods (:270, :387) show the surface is still moving.
3. There is no compute template and no plugin compute conformance.

### (e) A custom component and system

**Path:** `host.registry<ComponentRegistry>().register(codec)` (P/ecs.dart:290), `host.loop.addSystem('acme.x', LoopPhase.rules, fn)` (P/loop.dart:257), and `SnapshotPart` for outside state.

This journey is mature: namespacing, `view`/`tooling` refusals, `DeterminismCheck`, lints, the determinism conformance check and the `genre`/`element` templates are all in place.

**Friction:**
1. Duplicate names are `ArgumentError` rather than a `PluginException` (`flutter3d_sim/lib/src/ecs/ecs_world.dart:516`).
2. Systems declare no reads or writes, so nothing can be scheduled in parallel or checked for conflicts (LATER).
3. A system that throws aborts the step with nothing to identify the plugin.
4. Expression-language systems in `.f3dplugin` are refused at install, although the evaluator exists (PR/data/data_plugin.dart:761-770).

### (f) An asset codec or model format

**Path:** `host.registry<ModelDecoders>().addModelDecoder` (`flutter3d_core/lib/src/formats/model_decoders.dart:150`), `addSource('acme-x', …)`, `host.registry<TextureCodecs>().add` (F/texture_codecs.dart:66), and `Decoders.addMaterialDecoder` in `flutter3d`.

**Friction:**
1. **Texture codecs are never asked** (§1).
2. There are two decoder registries in two packages (`ModelDecoders` in core, `Decoders` in `flutter3d`). `README.md:160` lists both under one slot.
3. There is no template.

Model decoders themselves are wired and tested (`model_decoders_test.dart`).

### (g) An editor panel, tool, or MCP tool

**Path:**
- hints through `package:flutter3d_plugin_api/editor.dart`;
- commands, gizmos and importers through `EditorPieces` (`flutter3d_editor_core/lib/src/editor_pieces.dart:186`);
- panels through `EditorPanels` (`flutter3d_editor_widgets/lib/src/editor_panels.dart:79-135`);
- tools through `McpTools.addTool` (P/tools/project_tools.dart:185).

**Friction:**
1. Three packages are involved, and `EditorRegistry` is an empty marker (`editor_pieces.dart:136-138`).
2. **The editor app installs Dart plugins only from its own `plugins.g.dart`** (`apps/flutter3d_editor/lib/src/editor_plugins.dart:33-57`), so a third-party panel needs a rebuilt editor. Data plugins contribute hints and entity kinds only.
3. There is no menu, toolbar, shortcut or modal tool-mode API. Panels edit through untyped command JSON over a raw document map (`editor_panels.dart:43-75`).
4. **Permission bypass:** `addTool` demands `PluginPermission.tools` (project_tools.dart:191-197). But `shareCommands` publishes every editor command as an MCP tool through the root registry (`flutter3d_mcp/lib/src/editor/plugin_commands.dart:26-66`), with no permission and no `ToolHints`. The sample's `stoke` command reaches agents with no permission declared (`example/lib/acme_editor.dart:191-198`).
5. Templates exist for `tool` only.

### (h) A data-only Wasm plugin

**Path:** a `.f3dplugin` v4 with `wasm:` systems (API.md:1098-1214), loaded by `DataPluginLoader(grants:)`.

The sandbox is sound:
- fuel is counted in instructions, plus memory and call-depth limits (PR/wasm/abi.dart:96-139);
- imports are limited to `f3d` (`module.dart:498`);
- i32 only, so there is no NaN problem;
- a trap latches the system off, publishes `wasm.trapped`, and the latch is part of snapshots (`system.dart:327-347`);
- the unmetered browser runtime is refused under a bit-exact profile (`system.dart:480-493`).

**Friction:**
1. There is no template and no Wasm in any example. The plan's "once from data plus Wasm" (rc1-plan :364) was not done.
2. i32 only, with no tables, `call_indirect` or bulk memory (`wasm.dart:43-67`), so ordinary Rust, C or AssemblyScript output is refused. Authors hand-write Q16.16 arithmetic.
3. There is no render node (D29) and no data sections for light types, layouts or LOD.
4. A remote `.wasm` has no integrity hash (`data_plugin.dart:663-700`).
5. There is no conformance path for a data or Wasm plugin; `runPluginConformance` takes Dart classes.

## 3. Lifecycle and isolation

| Concern | State | Evidence and finding |
|---|---|---|
| Manifest and version constraints | good | `PluginApiVersion` major/minor policy (API.md:218-240); `dependsOn` with ranges, both numbers named on refusal (P/manifest.dart:161-178; P/manager.dart:181-191); unknown keys kept in `extra`. Missing: requirements on device features (compute, texture3D, MRT count) beyond backend names (`backends`, :184). A compute plugin finds out at placement, not at install |
| Dependency ordering | good | `orderByConstraints`, `ConstraintCycleException`, stable preferred order (P/manager.dart:366-375) |
| Install, uninstall, switching | good, one gap | Registrations are tracked and cancelled newest first (:475-480); switching happens at step boundaries with a journal and a replay schedule (:314-327). **Gap: one plugin whose `install` throws aborts `installAll`** (:454-459 rethrows; plugins already installed stay installed; `installAll` cannot be retried, :155-157). It should be held off with a `PluginStatus.reason`, as a backend mismatch is (:195-200). An `uninstall` that throws propagates out of `applyPending` at a step boundary (:464-473) |
| Hot reload | missing | `hot_swap.dart` relinks pipelines but never re-runs `install`. A system added in code during a session appears only after a restart (LATER) |
| Error isolation in the frame | missing | `node.execute` is in try/finally only (R/renderer.dart:5769). The outer catch abandons the frame and rethrows (:5842-5872). `renderPost` has no catch (:6232). No node is quarantined and the owning plugin is not named. `SceneSurface` turns it into a build error every frame (`flutter3d_app/lib/src/surface/scene_surface.dart:229`). Loop systems have no isolation either. Wasm is the only path with a latch |
| Namespacing | good, with holes | See D23 in §1 |
| Capability declarations | partial | `PluginPermission` is declared for Dart and enforced for run-time plugins (`PluginGrants`) and MCP tools. It is bypassed by `shareCommands` (above) |
| Two engines in one isolate | good | Registries per engine (P/registration.dart:41-45); no mutable statics found in the extension packages (read: `rg` for static collections and registries) |
| Wasm security | good for a sandbox | Metered interpreter, no I/O imports, grants for `files`/`network`. Missing: integrity pinning of remote modules |
| Determinism of simulation plugins | good | `PluginTouches` gate; `DeterminismCheck`; `flutter3d_lints`; conformance `determinism`; `simulationVersion` per plugin in the run's version (P/manager.dart:119-124); Wasm fuel, never time |

## 4. Capabilities mature engines have that this surface lacks

This is about capabilities only, not names.

- **A fault policy per extension.** Engines with plugins keep the frame alive when one pass fails: they disable the pass and report its owner. Here, every frame is lost.
- **An asynchronous plugin build step.** Bevy plugins have a `finish`/`ready` phase for loading assets before the first frame. Here, `install` is synchronous, yet four registrations are asynchronous and lit models need a loaded library.
- **Material extension by injection.** Three.js `onBeforeCompile` and Babylon material plugins patch a built-in material, adding a uniform or a term to PBR without rewriting it. Here, a plugin must write a whole lit model. A plugin light type cannot light PBR materials at all, and plugin expressions cannot enter the language.
- **Graph-allocated buffers and per-view node execution.** Unity's RenderGraph and Bevy's render graph allocate transient buffers and run a node once per view. Here, buffers can only be provided, and nodes see view 0 only.
- **Custom vertex attributes.** Godot's custom arrays and Unity's custom vertex streams carry a user attribute through to the shader. Here, the variants are a fixed set.
- **Composable culling and LOD.** Here, the draw-list hook can only narrow the list, the first sort key to answer wins, and the last LOD policy wins with no chaining.
- **Editor plugins without rebuilding the editor.** Godot GDExtension and editor plugins load into a stock editor. Here, panels require a rebuilt editor app.
- **A typed post-effect parameter block.** Unity's renderer features expose serialized settings. Here, `FullscreenEffect` takes raw float maps, although `SettingsSlot` exists for the step's settings.

## 5. API hygiene

- **Good:**
  - `abstract base` with defaults on every host, registry, hook and context.
  - Open value classes: `PluginTouches`, `PluginPermission`, `RenderAnchor`, `LoopPhase`, `ComputeRefusalReason`.
  - One-context-object hooks, held by a structure rule (API.md:299-372).
  - Snapshots per package, and the plugin API minor tied to the registries' snapshots (API.md:230-236).
  - `RenderListInternals` and similar extensions are hidden from the facades.
- **Typed exceptions are uneven.**
  - Namespace refusals are `PluginException`.
  - Duplicate names are `ArgumentError` in `RendererSteps`, `LightTypes`, `EditorPieces`, `ComponentRegistry`, `MaterialCompilerRegistry` and `LoopRegistry` (P/loop.dart:244-256).
  - `FrameGraphError extends Error` (`flutter3d_core.api` `FrameGraphError`).
  - `RuntimeShadersException` messages are untyped.
  - Changing `ArgumentError` to `PluginException` after the tag changes what a `catch` sees.
- **A leaked helper:** the top-level `standardVertices` (`flutter3d_core.api:6092`).
- **A frozen public method with no behaviour:** `FrameGraphBuilder.place`.
- **Three name grammars:** `<ns>.name` for most things, `<ns>_Name` for lighting models and stages, and `<ns-with-dashes>` for asset schemes.

## 6. Findings by severity

### BLOCKER

1. **Asynchronous registrations under a synchronous `install`.**
   - Where: R/renderer_steps.dart:274 (`addComputeStep`), :304 (`addWorkload`), :350 (`addFieldUpload`), :391 (`placeSkinningHook`); P/manifest.dart:562.
   - Fix: return `Registration` synchronously. Add the node at once, with its placement pending, and report `PassSkip.pending` until `prepare` finishes. Cancelling cancels the pending placement. Report a placement failure through `ComputeStep.refusal` and the plugin's status, not as an unhandled `Future` error.
   - The alternative is an asynchronous `Flutter3dPlugin.prepare(PluginHost)` that the manager awaits before the first step. Either changes a frozen signature now.
2. **Lighting-model names are `<ns>_Name`, not `<ns>.name`.**
   - Where: F/lighting_model.dart:631-643, the opposite of D23.
   - Material and level files store these names, so the grammar is frozen by the first saved document.
   - Fix: give `LightingModel` a dotted id (`acme_hair.hair`) that documents store. Mangle it to a shader-safe stage name inside the compiler only. Built-ins keep their bare names as the engine's.
3. **`FrameGraphBuilder.place` is public and unwired.**
   - Where: R/frame_graph.dart:255,336; no `placer` is passed to `compile`.
   - A node that calls it is dropped as unsupported.
   - Fix: wire it to the hardware layer's placement, as compute is, or remove it (and `FramePlacer`/`PlacementRequest`) before the snapshot freezes.

### SHOULD (fix before the tag)

4. **Fault isolation in the frame.** R/renderer.dart:5769,5842-5872,6232. Catch per node. Mark the node failed (`PassSkip.failed` with the error), name the owning plugin from the scope recorded in `_AnchoredNode`, and skip the node until the plugin is switched off and on. Draw the rest of the frame. Publish a `PluginFaulted` event. Apply the same rule to loop systems in frame phases. In step phases, keep failing loudly, because determinism comes first.
5. **`installAll` aborts on one plugin's `install` throwing.** P/manager.dart:454-459. Leave that plugin off with a reason, as for a backend mismatch, and switch off its dependents with reasons.
6. **`placeSkinningHook` refuses every outside plugin.** R/renderer_steps.dart:392-396. Name the step `<namespace>.skinning.<n>` from the scope. Add a scoped test.
7. **`viewIndex` is never set for nodes.** R/renderer.dart:5770-5797. Pass it when a node runs per view, or remove the promise at R/render_node.dart:108-110 and document that nodes loop over `views`. Add a conformance check with two views.
8. **Texture codecs are never consulted.** `texture_upload.dart:157`. Pass the engine's `TextureCodecs` in `model_asset.dart:239`, `material_loader.dart:173`, `level_loader.dart:515,860` and `hot_swap.dart:331`. Add a test that loads a `.pix` through a level.
9. **Plugin shader needs are dropped.** `flutter3d_build/lib/src/shader_build.dart:333`. Resolve dotted needs to the plugin's compiled stages, or refuse an unknown need with the package named. `asset-pipeline.md:273` promises this.
10. **No production code loads the hook's plugin bundle.** `RuntimeShaders` is constructed nowhere. Have `Flutter3dView` load `projectMaterialAsset` per marked package and hand it to `RendererSteps.addMaterials`, so a lit-model plugin works by discovery alone. Fix the docs at `asset-pipeline.md:293` and `flutter3d_plugin_runtime/README.md:131-133`.
11. **Unchecked takeovers.** `provide` (R/renderer_steps.dart:525) should refuse a non-engine plugin providing a built-in step unless it is a `RenderStepAddon` with that declared purpose. `addMaterials` (:630) should refuse a stage name that collides with an engine stage. `removeContributor` (:484) should only remove the caller's own. `FrameResources.declare` should apply `_inNamespace` and refuse engine ids.
12. **Editor commands reach agents without the `tools` permission.** `flutter3d_mcp/lib/src/editor/plugin_commands.dart:26-66`. Gate them on the owning plugin's manifest, and carry `ToolHints` from the command (or default to `writes`).
13. **Hooks that are settings fields, not registrations:** `PacingPolicy`, `QualityPolicy`, `ShadowTechnique`. Add `RenderHooks.setPacingPolicy` and the like, returning a tracked `Registration`, or document them as application-only and drop them from the D22b list.
14. **Composition rules for `LodPolicy` (last wins) and `DrawListHook.sortKey` (first wins).** R/render_hooks.dart:376. Decide now. Either refuse a second LOD policy with the owner named, or chain policies where `null` defers. Changing the rule later changes frames.
15. **Duplicate-name refusals are `ArgumentError`.** See §5. Make them a `PluginException` subtype (`NameTakenException`) before catchers start depending on `ArgumentError`.
16. **D28/D29 Wasm render ABI** is reserved, not implemented, against a decision that put it in rc.1. The reservation is sound (PR/wasm/abi.dart:34-56). Either implement it or record the deferral as a decision, and drop it from the rc.1 acceptance (rc1-plan :364).
17. **Render conformance does not count toward the badge, and has gaps.** Add `render.*` to `earnsBadge` for plugins whose manifest touches the view and registers a node. Add checks for compute, draw-list, LOD, skinning and codecs. Make the GPU runs required on the nightly badge.
18. **Templates.** Add `material`/`lit-model`, `compute`, `codec`, `editor` and `data`/`wasm` kinds. Compile every generated kind in CI (`pub get` plus `dart analyze`). Today `plugin_template_test.dart:54-160` checks text only.
19. **Engine readers ignore plugin lighting models.** `material_loader.dart:97`, `material_commands.dart:891`, `project_format.dart:2376`. Read against the engine's `LightingModels`.
20. **`MaterialCompilerRegistry` is not passed to the build** (`shader_build.dart:30-35`). An outside backend cannot ship materials in a project.
21. **Remote Wasm modules have no integrity check** (`data_plugin.dart:663-700`). Accept `sha256` in the spec and refuse a mismatch.
22. **The leaked `standardVertices`** (`flutter3d_core.api:6092`). Make it internal.
23. **Stale docs:**
    - the README registries table (`flutter3d_plugin_api/README.md:158-166` omits `LightingModels`, `TextureCodecs`, `RuntimeShaders`, `LightTypes`, `RenderHooks`);
    - `material-language.md:66`;
    - `addWorkload` is missing from API.md:761-773;
    - `site/content/reference/plugins.md:30` says "seven checks" without the render suite.

### LATER (additive in 1.x)

24. Custom vertex attributes declared in `.f3dmat` beyond the fixed variants; skinned plus instanced.
25. Plugin expressions and builtins in the material language (the parser hook D24 implied).
26. Graph-created buffers (`ResourceDesc` for buffers); document `reads`/`writes` checked against the node made from it.
27. Plugin light types visible to the engine's PBR loop; `maxLights` beyond 8; time and frame in `LightPackContext`.
28. Data sections for light types, vertex layouts and LOD tables; expression systems in `.f3dplugin` evaluated.
29. Wasm ABI 3 with f32, tables and bulk memory under canonical-NaN rules, so ordinary toolchains work.
30. Manifest requirements on device features (`requires: [compute, texture3D]`) checked at install.
31. Editor plugins loaded into a stock editor; menu, toolbar and tool-mode APIs; typed panel commands.
32. Re-running `install` on hot reload in debug builds.
33. System access declarations (reads and writes) for scheduling and conflict checks.
34. One decoder registry instead of `ModelDecoders` plus `Decoders`.

## 7. What is good

- **The plugin kernel is better than most engines'.** It has:
  - per-plugin scoped registries that withdraw everything on disable;
  - switching only at step boundaries, journalled and replayed;
  - `view`/`tooling` refusals that keep replays honest;
  - one `PluginHost` for Dart, data and Wasm plugins.
- **Namespacing is enforced, not advised.** About 25 registries call `nameProblem`. The reserved areas are frozen with a test, the engine's rights go by a list rather than a prefix, and the pre-1.0 ids are lifted.
- **Hooks follow a growth rule.** Each takes one context object, held by a structure rule, and everything implementable is `abstract base`. API.md says, for every point, what grows in 1.x and what is frozen. Few 1.0 engines write that down.
- **The frame-graph seam is mature.** It has 50 anchors with a defined meaning, `setup` before `execute`, frozen encodings for `hdr_color`, `surface_buffer` and `velocity`, and per-plugin anchors.
- **D20 to D22 are real.** Plugin lit models with their own blocks and textures, plugin light types, replaceable shadow and cube-atlas producers, decals through a lit model, and velocity on demand all exist. All of them pass render checks on four backends.
- **Compute by placement with a typed refusal is a clean shape.** The frame reports where a step ran and why a step did not.
- **The Wasm sandbox is deterministic by design.** Fuel is counted in instructions, the module is i32 only, and the latch is part of snapshots.
- **The samples use the published API.** `examples/outside_plugin` and the plugin runtime's sample use published libraries only, held by a rule.
