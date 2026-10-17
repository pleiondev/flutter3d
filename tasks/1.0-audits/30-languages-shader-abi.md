# 30. The languages and the shader ABI before 1.0 (2026-10-15)

This is a read-only audit of branch `1.0.0` at `da3b09a6e`. It covers the parts of 1.0 that third parties write against outside Dart signatures:

- the material language (`.f3dmat`), with `flutter3d_shaders`, `flutter3d_build` and `flutter3d_build_hooks`;
- the kernel language;
- the shader ABI;
- the Wasm plugin ABI, both the data ABI of today and the render ABI that decision 120 moves into rc.1;
- the generated GLSL, WGSL and MSL, but only where their names are a contract.

The yardstick is `docs/CONTRACTS.md` from "The shader ABI" (:397) through "Frame resources a stage reads" (:693), plus "Names" (:695-745) and "Reserved names" (:366-383). Decided items are referenced, not argued again: 50 (rc.2 additive under rc.1), 67, 68, 92, 99-110, 116, 120 and 123.

Nothing was changed. No suite was run. I did run two probes: scratch scripts in the session scratchpad that call `parseMaterial`, `emitMaterialFragment` and `ComputeKernel.parse` through the root package config. Their results are quoted where used. Counts come from `rg`, `awk` and `fd` over the tree. I say where a count is heuristic.

Abbreviations:

| Short | Path |
|---|---|
| **MP** | `packages/flutter3d_core/lib/src/formats/material_language/material_parser.dart` |
| **MA** | `packages/flutter3d_core/lib/src/formats/material_language/material_ast.dart` |
| **MG** | `packages/flutter3d_core/lib/src/formats/material_language/material_glsl.dart` |
| **KP** | `packages/flutter3d_shaders/lib/src/kernel/kernel_parser.dart` |
| **CK** | `packages/flutter3d_shaders/lib/src/compute_kernel.dart` |
| **ABI** | `packages/flutter3d_shaders/api/flutter3d_shaders.abi` |
| **W** | `packages/flutter3d_plugin_runtime/lib/src/wasm` |
| **C** | `docs/CONTRACTS.md` |

Tags:
- **blocker**: only a major fixes it once 1.0 is tagged.
- **before rc.1**: cheap now; later it is a broken promise or an unguarded window.
- **additive 1.x**: can be done in any minor.

## Verdict

Most of this surface is close to freezable. Each of the three languages has a version field with the same rule: absent means 1, older versions read as before, and a newer file is refused with a sentence that names both numbers (MP:1169-1192, KP:356-380, W/abi.dart:60-73). The material language goes further than most engines do. Each input and builtin carries `since` (MA:150-166, :558), block names are frozen together with a reserved shape (MP:296-371), and a test holds the engine to that shape. The shader ABI has a one-fact-a-line snapshot, and a structure rule says it only grows (ABI, `tool/structure/rules.dart:5199`). The Wasm ABI feature-detects its imports by the version each arrived in (W/abi.dart:76-82).

What it does not have yet is the same discipline everywhere. Three gaps would take a major to fix after the tag:

1. **The `<ns>.name` → shader-identifier mapping of decision 68 is not injective as it stands.** It is `<ns>_<Name>` (`lighting_model.dart:559-565, 636-643`). Plugin ids contain `_`, so `acme.ink_glow` and `acme_ink.glow` map to the same entry point. That entry point is written into every plugin bundle and into the asset key `flutter3d_generated/shaders/<material>.f3dshaders` (`engine_bundle.dart:48-52`). The `.f3dmat` grammar also takes only a bare name (MP:553), so nothing yet says how a source names its namespaced model.
2. **The kernel language's reserved words are one unversioned set** (KP:84-136). Version 2's `atomic…` words are already refused as locals in a version 1 source (probe below). Version 3 (decision 108, rc.2) adds barriers, workgroup memory and uniform blocks. If those words go into the same set, rc.2 refuses rc.1 kernels, which decision 50 forbids. After 1.0 the same mechanism would turn every kernel version into a break.
3. **The Wasm render ABI lands in rc.1 (decision 120) with four shape decisions unmade.** They are:
   - whether a render node shares an instance, and so the saved state and the digest, with a step system;
   - whether a render module may use `f32`, which the decoder refuses today (W/module.dart:319-325);
   - who owns the memory that encoder commands cross;
   - whether a render-only module still has to export `f3d_step` (W/module.dart:651-660).

   Each of these is frozen by whatever rc.1 ships.

There is also one cosmetic gap of the same class. `scene_colour_texture`, `SceneColourCopy` and `LayerInfo.scene_colour` are British spellings inside the ABI that "only grows" (ABI:69, 832, 868, 908, 944, 1058). Once the base is re-recorded at the tag, only 2.0 can rename them.

The before-rc.1 band is cheap and mostly about making promises checkable:
- the material vocabulary has no snapshot;
- varyings and sampler dimensions are outside the ABI file;
- GLSL keywords pass the parser;
- `parseMaterial` ignores everything after its first block;
- CONTRACTS is wrong in three places;
- the ABI base is older than the commit that will be tagged.

## 1. The contract as it stands

| Contract | Version field and rule | Reserved identifiers | How it grows | Pinned by | Outside-author docs |
|---|---|---|---|---|---|
| `.f3dmat` grammar | `f3dmat <N>` first line, absent = 1, newest 3, newer refused with both numbers (MP:184, :1169-1192); format `f3d.materialLanguage`, `enveloped: false` (MP:201-208) | Locals (C++ style lists, private): `_reservedNames` (MP:246-263), `_vertexReservedNames` (:268-287), `_version2ReservedNames` (:391-406), `_variantReservedNames` (:376-386), `f3d_` from v2, `gl_` always, `F3dLightRow` from v3 (:1436-1446). Blocks: 67 frozen names plus `F3d…`/`…Info` (MP:296-371) | New word or input arrives with a new N (C:526-536); `MaterialInput.since` (MA:141), `materialBuiltinVersions` (MA:558) | Fixtures v1-v3 (`flutter3d_core/test/fixtures/v<N>/rim_glow.f3dmat`) under the "fixture per version" rule (`tool/structure/repository.dart:1456-1462`); `material_language_read_as_before_test.dart` pins tree + GLSL + CPU colour of **7 files, not v3** (:23-31); `material_language_growth_test.dart` | `site/content/reference/material-language.md` (244 lines, prose and examples; no grammar, no keyword or reserved-name list) |
| Builtins | Closed list of 16, all `since: 1` (MA:535-575) | Builtin names are taken only where the version has them (MP:1338-1345) | `materialBuiltinVersions` | API snapshot elides it as `= …` (`flutter3d_core.api:5864`) | Listed in the MA doc comment only |
| Material's own version, `updates` | `material X version N`, f3dmat 3 (MP:555-567, :1020-1125) | none | rename / scale / remove | v3 fixture; `level_material_lift_test.dart` | Site :34-50 |
| Kernel language | `kernel <N>`, absent = 1, newest 2 (`kernel_version.dart:17`); refused with both numbers (KP:370-377); exempt from the fixture rule (`repository.dart:1610-1618`) | `_reserved`, 51 words, **one set for every version** (KP:84-136) | v2 gated `atomic` (KP:515) | `compute_kernel_test.dart` "versions" group (:86-123); no versioned fixtures | `CK` library doc (:1-59); `docs/kernels.md` is decision 106, not written |
| Entry points | Stable within a major; a minor may add (C:405-413) | `requiredShaders`, `computeShaders` | Add only | ABI: 109 `entry` lines (19 vertex, 86 fragment, 4 compute) | C:415-430; site rule "the site names every shader…" |
| Blocks, members, samplers | std140 offsets; "only grow in a minor" (C:432-446) | Block shape `F3d…`/`…Info` | Append | ABI: 178 block, 894 member, 261 sampler lines; rule `the shader ABI only grows` (rules.dart:5199-5230) against `tool/api/abi_base/flutter3d_shaders.abi` | `package:flutter3d_shaders/backend.dart`, C |
| Vertex layouts | "Frozen within 1.x" (C:588-589) | `i_row0..2`, `i_color`, `i_data` | none | ABI: 83 `vertex … in` lines (location, type, name) | C:574-589 |
| Varyings between stages | Not stated | `v_world_position`, `v_normal`, `v_texcoord`, `v_tangent`, `v_color`, `v_lightmap_uv`, `v_instance` (`shaders/mesh.vert:35-43`, no `layout(location)`), `v_uv` | — | **Nothing at run time**; `checkStageAgreement` runs only inside one bundle writer (C:664-676) | Not documented |
| Defines | Table of 11 (C:453-465) | `F3D_*` | — | Not in the ABI; all 11 used in the sources (`rg` count) | C:448-468 (one claim wrong, F3) |
| Light codes | 0-3 engine, under 16 engine-later, 16 and up plugin (C:553-572) | `lightKind`, `lightParams`, `lighttype` (v3) | Per renderer, by name | `plugin_light_code_test.dart` (skip order in GLSL); `render.light type` conformance | C, site |
| Decal stage interface | `DecalInfo` (16 a draw), `decal_texture_0..3`, `surface_texture`, `albedo_texture`, `params.w` (C:591-598) | — | — | ABI:297-316 | C |
| Material's own slots | Table order: `MaterialParams`, blocks by first mention, textures by declaration (C:470-488); std140 in declaration order (`material_slots.dart:191-210`) | `f3d_block_<Name>`, `material_<name>` | Budget 3 textures, 4 blocks "in every 1.x" (`stage_budget.dart:36, 41`) | `render.lit model defaults`; budget test | C |
| Frame resources | 4 of 24 ids with frozen encodings (C:685-690) | `FrameResourceIds` (`frame_plan.dart:44+`, 24 ids, `rg` count) | Add only | Rule "surface buffer keeps carrying depth in metres" | C (renames pending, decision 67) |
| Backend material compiler | `MaterialCompiler` `abstract base`, growing `MaterialCompileRequest` (`material_compiler.dart:52-93, 137-170`) | Section names of the engine's three and `flutter3d.stamp` | Members with defaults; options by key | No conformance check (`rg` finds none in `flutter3d_conformance*`) | C:628-662, `backend.dart` |
| Pubspec marker | `flutter3d_plugins:` with `plugin`, `shaders`, app's `without`/`set`/`with` (`plugin_discovery.dart:1-60, 127, 346`) | — | Unknown app keys warn and are ignored (:402-414) | Snapshot of `flutter3d_build.api`; no schema snapshot | Doc comment; the compiler marker (decision 92) is not written yet |
| Wasm data ABI | `f3d_abi() -> i32`; host runs 1..2 (W/abi.dart:19-30) | `f3d_abi`, `f3d_step`, `f3d_render_node` (W/abi.dart:50); imports from `f3d` only | `wasmImportSince` (W/abi.dart:76-82), feature-detected | API snapshot carries the map in full (`flutter3d_plugin_runtime.api:279-287`); modules assembled in tests (`test/wasm/assemble.dart`), no committed binary per ABI | `API.md:1155-1218`, W/wasm.dart doc; no toolchain guide |
| `.f3dplugin` | Envelope, version 4 (`data_plugin.dart:177`); unknown sections kept in `extra`; `requires` checked against registered readers (:267-299) | `DataSections.runtimeKeys` | New sections, new versions | Fixtures v1-v4 | `API.md` |
| Permissions | `network`, `files`, `tools` (`manifest.dart:90-98`); declared and granted (`permissions.dart`) | — | Open set | — | `API.md` |

## 2. Probes

These are scratch scripts against the working tree. They are not tests.

| Input | Result | Meaning |
|---|---|---|
| `material A { fragment {…} } junk { more }` | accepted | `parseMaterial` never checks for the end (MP:227-235, :776) |
| `material A {…}` then `material B {…}` | accepted, name `A` | The second material is dropped without a word |
| v1 kernel with `let atomicAdd = 1u;` | refused: "already a word or a binding" | v2 words are reserved in v1 sources |
| v1 kernel with `let barrier` / `let shared` | accepted | Today's legal names that v3 is likely to take |
| `f3dmat 2` + material `compute C { workgroup 8 8; kernel { return vec4(1.0); } }` through `ComputeKernel.parse` | refused: `expected ";", found "8"` | The kernel parser names the material form only on `uniform`/`param` (KP:425-434), not as C:549-550 says |
| `let shared`, `buffer`, `patch`, `precise`, `double`, `noperspective`, `sampler3D`, `atomic_uint`, `subroutine`, `coherent`, `readonly`, `common`, `input`, `output`, `filter`, `half` in a fragment body | all accepted and emitted as `float <name>` | GLSL keywords and reserved words reach glslang, not the parser; `float`, `vec3`, `sample` are refused |

## 3. Findings

### F1. Decision 68's shader identifier is not injective, and the source has no way to name a namespaced model. Blocker.

Evidence:
- `LightingModels.register` requires a plugin model's `shaderName` to start with `<namespace>_` (`lighting_model.dart:636-643`), and the doc gives `acme_ink_Ink` for `acme_ink.ink` (:559-565). Namespaces contain `_` (`flutter3d_post`, `acme_ink`), so `acme` + `ink_Glow` and `acme_ink` + `Glow` are one identifier. Registration would throw `ArgumentError` for whichever plugin installs second (:645-650). Two legitimate plugins cannot be installed together, and the user cannot tell why.
- That identifier is more than a registry key. It is the GLSL entry point. It is the name of every vertex stage (`<name>Vertex`, plus `Skinned`/`Instanced`/`Lightmapped`, `lighting_model.dart:486-506`). It is the asset key `projectMaterialAsset(material)` (`engine_bundle.dart:48-52`). It is the typed accessor's class name (`materialAccessorName`, `material_accessors.dart`).
- `.f3dmat` reads `material <name>` as one bare token (MP:553). Decision 68 says lighting models become `<ns>.name` and the shader identifier "is derived mechanically". The rc.1 plan row (4.3A) lists the rename and nothing about the grammar.

Why it is a blocker: whatever mapping rc.1 ships is written into bundles, asset keys and generated Dart. Changing it later renames every plugin's stages.

Fix: an injective mapping, for example `.` → `__` with `__` refused in plugin ids and model names. Also one sentence in C and on the site saying how a source names its model (Q1).

### F2. The kernel language reserves every version's words in every version. Blocker, with a cheap fix before rc.1.

Evidence:
- `_reserved` (KP:84-136) is consulted for bindings (:481) and locals (:587, :610) with no version check. The probe shows `atomicAdd` refused as a local in a source without `kernel 2`.
- `CK`:120-121 already expects v3 to add binding kinds such as uniform blocks. Decision 108 adds workgroup memory, barriers, uniform blocks and per-binding storage-texture formats in rc.2.
- Decision 50 says rc.2 is additive under rc.1. The material language solved the same problem with `since` (MP:1338-1345, :1436-1446). The kernel language did not.

Fix: give each reserved word, builtin and binding word the version it arrived in, as `materialBuiltinVersions` does, and test that a v1 source may still use every v2 or v3 word as a local (Q2).

Version 3 itself can then be additive. The public shapes already leave room:
- `KernelBindingKind` is open (CK:122-156);
- `KernelBinding.element` is a `String` (CK:177);
- `KernelInputs` takes named maps (CK:214-225);
- `DartKernel.runWorkgroup` already runs a workgroup as a unit (CK:241).

Two members will need to grow:
- `KernelBinding.textureFormat` is hard-wired to RGBA8 (CK:186);
- the public `KernelBinding` has no `atomic` flag, although the tree has one (`kernel_ast.dart`, `KBinding.atomic`), so an executor from outside cannot tell an atomic buffer from a plain one.

Both are additive.

### F3. CONTRACTS says three things the code does not do. Before rc.1.

- C:467-468 says "A material written in the material language sets none of them." MG:84-93 writes `#define F3D_NO_POINT_SHADOW` and `#define F3D_NO_LIGHT_LIST` for every material without a `light` block, and the read-as-before record shows six such defines (`rg -c`).
- C:549-550 says the kernel parser names the material form "when it meets a material `compute` block". It does so only on `uniform`/`param` (KP:425-434). A material compute block with neither gets `expected ";", found "8"` (probe).
- C:366-383 ("Reserved names") still says the Wasm render nodes "have a name in rc.1 and no implementation". Decision 120 implements them in rc.1. `tasks/1.0-api-migrations.md:625-635` still says "ABI 3" and "rc.2", while C:381 says "no ABI number is set aside". After 4.3I, the three texts need one wording.

Smaller doc drifts:
- `MaterialStageSource.name` says the vertex stages are `<name>Vertex` and `<name>VertexSkinned` (`material_compiler.dart:33-35`). v3 also hands a compiler `…VertexInstanced` and `…VertexLightmapped`.
- C:577-581 writes `<name>Skinned` where `<name>` means the vertex stage's name, but C:584 writes `<name>VertexInstanced` with `<name>` meaning the material's. One `<name>` should be used throughout.
- MP:76 has a doubled `/// ///`.
- MA:527 calls the builtins "the sixteen versions 1 and 2 have". Version 3 has the same sixteen.
- The generated GLSL carries an internal ticket id ("— gfx-84n", MG:80) into every user's shader.

### F4. The material vocabulary has no snapshot, and "a new word comes with a new N" is not enforced. Before rc.1.

The API snapshot writes `materialInputs = …`, `materialBuiltinVersions = …` and `materialReservedBlockNames = …` (`flutter3d_core.api:5864, 5888, 5914`). This is the same blindness that rules.dart:5186-5196 gives as the reason the `.abi` exists. The local-name reservations (MP:246-406) are private, and so are the state keys, the blend names and `materialDepthCompares`.

So suppose a minor adds an input with `since: 3`, the current version. A 1.0 build that reads a `f3dmat 3` file using it refuses with an unknown-name error instead of the version sentence that C:345-346 promises. The growth test checks only that `since` is within range (`material_language_growth_test.dart:35-60`). The same gap exists for a kernel builtin, which has no `since` at all (F2), and for a new entry in `wasmImportSince` written with the current ABI number.

Fix: a vocabulary snapshot per language, one fact a line, like the `.abi` (`f3dmat input fragment albedo vec3 1`, `kernel word atomicAdd 2`, `wasm import field_frac 2`). Add a rule that every line absent from the 1.0 base carries a version above the base's newest (Q10).

### F5. The ABI file does not see varyings, sampler kinds or the vertex buffer's formats. Before rc.1.

`tool/shader_abi.dart:27-50` writes entries, blocks, members, samplers by name, and vertex inputs. Not written:

- **Vertex outputs and fragment inputs.**
  - Pairing: a material that does not ship a vertex variant draws its fragment stage with the engine's vertex stage from another bundle (C:581-582, `material_bundle.dart:33-43`). A data plugin's full-screen stage reads `FullscreenVertex`'s `v_uv`.
  - Locations: `mesh.vert:35-43` declares its outputs without `layout(location)`. Their locations are their declaration order.
  - Effect: a minor that inserts a varying before `v_instance` moves locations under every prebuilt plugin fragment stage on the location-bound backends.
  - Coverage: `checkStageAgreement` runs only inside one bundle writer (C:664-676), so nothing catches it.
- **A sampler's kind.** The line is `stage Decal sampler decal_texture_0`, with no 2D, cube, array or depth. Moving `shadow_texture` to an array, or a decal slot to an array texture, passes the rule.
- **The vertex buffer's formats.** `VertexLayout.standard` is 64 bytes of `float32` because every input is a float vector (`vertex_layout.dart:103-115`). That is pinned only implicitly. A packed colour in a minor would keep the `in vec4 color` line and change what a `SkinningHook`, which writes `VertexLayout.standard` (C:609-614), must write.

Fix: add `vertex <stage> out <index> <type> <name>`, `fragment <stage> in …` and `stage <stage> sampler <name> <kind>` lines before the base is recorded at the tag. Write the attribute formats as well, or state "float32 throughout" in C:574-589 (Q8).

### F6. The base of "the shader ABI only grows" is not the rc.1 tag. Before rc.1.

The rule's doc and C:443-446 say the base was "recorded at 1.0.0-rc.1". `tool/api/abi_base/flutter3d_shaders.abi` was committed in `aa1fe2abb` (2026-10-13) and is identical to the current file (`diff` is empty).

A local tag `v1.0.0-rc.1` points at `3b63c000e` (2026-10-14), 24 commits behind HEAD. Wave 4.3 is still the rc.1 plan, and it changes the ABI: 123 adds PBR injection points, 120 adds the render ABI's data, and F1, F5 and F7 add more.

So either each 4.3 change re-records the base by hand, or the rule fails on legitimate rc.1 work. Nothing ties the final base to the commit that is tagged (Q7).

### F7. British spellings are about to freeze in the ABI. Blocker (cosmetic).

These are bound by name on Impeller, WebGL2 and the CPU (C:482-483):
- entry `SceneColourCopy` (ABI:69);
- member `LayerInfo.scene_colour` (ABI:832, :908);
- sampler `scene_colour_texture` (ABI:868, :944).

C:703-709 asks for American spelling in identifiers, and "public identifiers spell in American" reads only Dart snapshots. The ABI cannot rename: a rename is a dropped line. The backend alias `'the software rasteriser'` (`runtime_shaders.dart:75-82`) is a wire name too, but decision 72 replaces that table.

Fix: rename now, before the base is re-recorded (Q6).

### F8. GLSL keywords pass the material parser. Before rc.1.

`_reservedNames` (MP:246-263) lists about 60 GLSL words. GLSL 4.60 has more keywords, and more words reserved for future use. Sixteen of them pass the parser and are emitted as `float <name>` (probe, §2).

Such a material:
- fails in glslang at build time, with glslang's message rather than a line and column in the `.f3dmat`;
- runs on the software backend;
- runs on runtime WebGPU, whose translator prefixes locals (`m_<name>`, `data_plugin/material_wgsl.dart:503, 556`).

So it "works" on two backends and fails on two. Tightening after 1.0 refuses sources that parse today.

Fix: complete the list from the GLSL 4.60 and GLSL ES 3.00 keyword and reserved tables, valid in every version. These sources never compiled for a GPU (Q11).

### F9. A multi-block `.f3dmat` has no grammar. Before rc.1.

C:546-548 and KP:26-28 allow a `.f3dmat` to hold a material and kernel-language `compute` blocks. `parseMaterial` reads its first block and ignores the rest without checking (MP:227-235, :776). That silence is what lets the kernel blocks ride along. It also drops a second `material` and accepts trailing garbage (probe).

The kernel parser does the reverse: it skips `material` and `fullscreen` and refuses other words (KP:332-344).

Fix: say what may follow the first block. Probably only kernel-language `compute` blocks, after the material, at most one material, and nothing else. Make `parseMaterial` refuse the rest with a sentence (Q12).

### F10. A header identifier added in a minor can take an old `let`'s name. Additive 1.x, cheap with F4.

Material locals are emitted under their own names (MP:237-245) into a `main()` that calls the headers' functions (`ShadeLight`, `AccumulateLights`, `SampleLightmap` …). The frozen-plus-shape rule protects block names (MP:289-371, growth test :89-97), but nothing protects function and struct names in the 31 header files.

Suppose a minor adds `SampleSheen` to `surface.glsl`. A v1 material with `let SampleSheen = …` then shadows it. It fails to compile, or worse, compiles reading the wrong value.

Fix: a rule that every identifier a header declares after 1.0 is `F3d…` or `f3d_…`, a shape v1 sources effectively never use and v2+ sources may not use (MP:1438-1440). Check it by a frozen list of the 1.0 header identifiers, as the block names are checked.

### F11. The v3 language output is not in the read-as-before record. Before rc.1.

The record pins tree, GLSL and CPU colour for v1, v2 and five repository materials (`material_language_read_as_before_test.dart:23-31`). The v3 fixture and `flutter3d/test/fixtures/materials/hatch.f3dmat` are not among them.

The v3 fixture is the only source that exercises:
- `updates`;
- `directional off`;
- the instanced and lightmapped vertex halves (MG:540, :1062).

Nothing exercises `lighttype`, `lightKind` or `lightParams` in a fixture at all (`rg` over `test/fixtures`). The fixture's own comment says it is "never rewritten once a release has read it". Only its parse is pinned, not what it emits.

Fix: add the v3 fixture to the record. Add a fixture with `lighttype` before rc.1, or give 123's injection points a fixture when they land.

### F12. What a backend's material compiler must accept is not testable. Before rc.1 (the sentence); additive 1.x (the check).

C:628-662 says a compiler may refuse with `MaterialCompileException`. It does not say what a compiler for a GPU backend must accept: every construct of the language version, or only what its device can draw. There is no conformance entry for compilers. `flutter3d_conformance*` has device and render checks, and `rg MaterialCompiler` finds nothing there.

Decision 92 lands D26's build half in rc.1 with the null backend as the example. That is the place for a corpus check: v1-v3 fixtures, every `F3D_*`-free engine stage, own blocks and textures, the budget refusal.

Smaller point: `MaterialCompileRequest.options` carries `Map<String, PackedStage>` under `webGpuStagesOption` (`material_compiler.dart:63-67`). That makes `PackedStage` from `translate.dart` part of a compiler's contract through an untyped key.

### F13. A prebuilt plugin bundle does not say which ABI it was built against. Additive 1.x.

The engine's own bundle carries `EngineBundleStamp` (`engine_bundle.dart:19-30`). A project rebuilds plugin materials for its SDK (`projectMaterialAsset`), but "a plugin's own loader asks for this key before any bundle the plugin ships" (:46-52), so a shipped bundle is still loaded.

A bundle built against 1.1 headers, with a block grown at its end, runs on a 1.0 engine that fills the smaller block. Nothing refuses it.

Fix: a `flutter3d.abi` section, a number or the base's hash, with absence read as 1.0. That is additive.

### F14. Only 4 of the 24 frame resources say what their channels hold. Before rc.1 (the doc).

C:685-690 freezes `hdr_color`, `surface_buffer`, `velocity` and `frame`. `FrameResourceIds` has 24 (`frame_plan.dart:44+`), among them:
- `albedo_buffer` ("sRGB in eight bits" in its doc);
- `shadow_map`, `shadow_moments`, `cube_shadow`;
- `ao`, `depth_pyramid`, `object_ids`;
- `skinned_vertices`.

A plugin reads any of them by name (C:680-683). An outside author cannot tell which encodings are promised. Decision 67 renames all of them to `f3d.<name>`, so the table is rewritten in 4.3A anyway (Q13).

### F15. The ABI rule freezes array lengths. Not a gap: a consequence to write down.

`FragInfo.light_*` are `8` elements (ABI:748-751) and `DecalInfo.*` are `16` (ABI:298-309). Growing either changes those lines and moves every later offset, so through 1.x the forward path keeps 8 lights a draw and a decal draw keeps 16. Lifting the limit means a new block, not a longer array.

The review already counted these `static const` limits in the shader ABI (`1.0-readiness-review.md:593-595`). What is new is that the rule now enforces them. C should say so where it promises "only grow" (Q14).

### F16. The Wasm ABI's growth rules are written only for the render export. Before rc.1 (doc), with 120.

- **Exports.** Only `f3d_render_node` is reserved, with the rule "a module of an older ABI that exports the name is not read for it" (W/abi.dart:47-50, C:375-383). The same rule should cover every `f3d_`-prefixed export a later ABI adds. A minor's `f3d_init` or `f3d_teardown` would otherwise be called on an ABI-2 module that happens to export a function of that name.
- **Minimum.** `API.md:1218` says an ABI-1 module "runs on every engine whose minimum is still 1". That implies the minimum may rise in a minor. C:342 says a 1.x engine reads every 1.x file. The snapshot carries `wasmPluginAbiMin = 1` (`tool/api/baseline/v1.0.0-rc.1/flutter3d_plugin_runtime.api:285`), but the documents should say outright that it stays 1 through 1.x.
- **Fixtures.** Every ABI-1 and ABI-2 module in the tests is assembled by `test/wasm/assemble.dart`, so a change to the assembler moves the "fixture" with the decoder. Nothing compiled by an outside toolchain is in the tree. Whether today's i32-only, no-table, no-`call_indirect` profile (W/wasm.dart:44-70) is reachable from Rust, C or AssemblyScript output is not shown anywhere. My expectation, untested, is that default `wasm32` output of those toolchains uses tables and bulk-memory opcodes the decoder refuses. A guide for building a module, with a committed `.wasm` per ABI built by it, belongs with the Wasm sample of decision 120.

### F17. The Wasm render ABI's shape. Blocker for 4.3I: decide before it lands.

Decision 120 puts D29 in rc.1. The sketch (`1.0-api-migrations.md:625-635`) fixes the export and "records encoder commands through `Recorded` against declared resources". Four things are not decided, and each is frozen by rc.1:

1. **Instance and state.** `WasmInstance.save` is the simulation's state, and it is folded into the digest (W/abi.dart:236-262). If one instance serves both `f3d_step` and `f3d_render_node`, a frame's render call that writes memory changes the digest on clients and not on a headless server. The run parts at the next check.
2. **Values.** The decoder refuses `f32` anywhere in a module (W/module.dart:319-325). A render node computes colours, matrices and uniforms. It either uses `f32`, or it pushes bit patterns through `i32`.
3. **Memory.** Today nothing crosses but `i32` scalars (W/wasm.dart:36-44). Commands with bulk data, such as uniform bytes or vertex data, need a rule. Either the host copies from `(ptr, len)` in module memory during the call and never keeps the pointer, or the module returns a command buffer.
4. **Required exports and budgets.** `f3d_step` is required by the decoder (W/module.dart:651-660). `WasmLimits` counts fuel per step (W/abi.dart:91-135). A render-only module and a per-frame budget both need words. Adding a field to `WasmLimits` and gating `f3d_step` by ABI are both additive, if they are designed in.

Permissions: a render node has no I/O, so it needs no new `PluginPermission`. A takeover of a built-in step needs one (decision 117). The capability model stays "declared in `.f3dplugin`, nothing else reachable", and C should say that it covers render resources too (Q3-Q5).

### F18. Kernel-language versions have no fixtures, on the ground that kernels are "no file a reader opens". Additive 1.x.

`notAVersionedFormat` exempts `kernelLanguageVersion` because kernels are "source text inside a bundle's kernel section and no file a reader opens" (`repository.dart:1610-1618`). But a `.f3dmat` file may hold kernel blocks (C:546-548). A kernel section carries the source verbatim (CK:366-384), and that section is a file on disk that outlives its build (as the WebGPU section's doc argues, `wgsl_section.dart:49-57`).

A `kernel 1` and a `kernel 2` fixture, read by every 1.x build, cost nothing. They are what makes "a 1.x engine reads every 1.x kernel" checkable.

### F19. Error messages: good sentences, no stability statement, two styles. Additive 1.x.

- Material errors are full sentences with line and column and a way out (`MaterialSyntaxException`, MP:214-224).
- Kernel errors are fragments ("expected "x", found y", KP:306), and the exception's field is `reason`, not `message` (`kernel_exception.dart:7-13`).
- Wasm errors are sentences.

No document says message wording is not part of the contract, and no error has a stable code an editor, an MCP tool or a test could match. The statement belongs in C now. Codes are additive.

### F20. Smaller language points. Additive 1.x.

- The material syntax has no exponents (`1e-3`) and no comparisons or conditionals (MP:125-130). The kernel language has both (KP:208-223). Both can be added with a version.
- The builtins lack `cross`, `exp`, `log`, `atan2`, `reflect`, `mod`, `sign`, `distance` and `inversesqrt` (MA:535-552). `cross` is the one a hair or anisotropic model (D49) will ask for first.
- `.f3dmat` has no `include` or import. A plugin with five materials repeats its shared functions, and there are no functions either. This is a design choice. It is fine for 1.0 and worth one line on the site.

## 4. What the structure rules claim and cannot see

| Rule | Claims | Cannot see |
|---|---|---|
| `the shader ABI only grows` (rules.dart:5199) | Every line of the rc.1 base is still in the `.abi` | Varyings, sampler kinds, attribute formats (F5); defines; header function names (F10). Its base predates the tag (F6) |
| `every versioned format has a fixture for each version it reads` (rules.dart:234, repository.dart:1436-1516) | `.f3dmat` v1-v3, `.f3dplugin` v1-v4, F3SB … | Kernel language, exempted on a ground C contradicts (F18); Wasm ABI versions, which are not a format (F16); fixtures prove a parse, not an emitted stage (F11) |
| `public identifiers spell in American` | Dart API snapshots | ABI wire names (`scene_colour_texture`, F7) and backend alias strings |
| `every published API is the snapshot its package commits` | Signatures and short constants | Long constants (`materialInputs = …`, `materialBuiltinVersions = …`, `materialReservedBlockNames = …`); private vocabularies (`_reservedNames`, kernel `_reserved`) (F4) |
| `the plugin API's number moves when the plugin API grows` | `PluginApiVersion` against the plugin API snapshots | The three language numbers and the Wasm ABI number, none of which a rule ties to growth (F4) |
| `the site names every shader a bundle must answer to` | The site lists `requiredShaders` | Fine as it is |

## 5. Additive later or a break now

| Item | Tag |
|---|---|
| F1 shader identifier mapping and the source's model name | blocker |
| F2 versioned kernel reserved words | blocker (cheap before rc.1) |
| F17 Wasm render ABI shape (instance, f32, memory, exports, budget) | blocker for 4.3I |
| F7 British names in the ABI | blocker (cosmetic) |
| F3 CONTRACTS corrections | before rc.1 |
| F4 vocabulary snapshots and the "grows with its version" rule | before rc.1 |
| F5 varyings, sampler kinds and formats in the `.abi` | before rc.1 |
| F6 base recorded from the tagged commit | before rc.1 |
| F8 GLSL keywords refused | before rc.1 |
| F9 multi-block grammar | before rc.1 |
| F11 v3 in the read-as-before record, a `lighttype` fixture | before rc.1 |
| F12 the "must accept" sentence | before rc.1 |
| F14 frame resource encodings named | before rc.1 (docs, with 67) |
| F15 array lengths stated | before rc.1 (docs) |
| F16 export rule, minimum stays 1, toolchain guide | before rc.1 (docs, with 120) |
| F10 header identifier shape rule | additive 1.x (before the first minor that adds a header function) |
| F12 compiler conformance corpus | additive 1.x (or with 92 in rc.1) |
| F13 ABI marker in plugin bundles | additive 1.x |
| F18 kernel fixtures | additive 1.x |
| F19 message statement now, codes later | additive 1.x |
| F20 exponents, comparisons, builtins | additive 1.x |
| Kernel v3 itself (108) | additive, given F2 |

## 6. What is good

- **One version rule, said three times alike.** It covers absence, the lift and the refusal of a newer file with both numbers, and it is tested in each language.
- **The material language already grows correctly.** Inputs and builtins carry `since`. Block names are frozen with a reserved shape, and a test stops the engine from taking a material's name. `f3d_` is reserved for locals from v2. The `updates` block carries an instance's values across a material's own versions.
- **The ABI file is the right tool.** It has one fact a line and a text-only rule, and it already found the blindness of the API snapshot (rules.dart:5186-5196).
- **`MaterialCompiler` and `MaterialCompileRequest` are built to grow.** The compiler is `abstract base` with defaults; the request is one growing object with options by key.
- **The WebGPU section describes its own bindings by name.** It carries its own `sectionVersion` (`wgsl_section.dart:44-58`), so a prebuilt WebGPU bundle does not depend on the engine's numbering.
- **Wasm imports are feature-detected by the version each arrived in.** A module that claims an older ABI and imports something newer is refused by name.
- **The budget is stated and checked from emitted GLSL on every backend.** A material fails on its author's machine and not on a phone.

## Questions for Dmitrii

1. **The shader identifier of a `<ns>.name` lighting model (F1).**
   - Recommended: `<ns>.<name>` maps to `<ns>__<Name>`, and `__` is refused in plugin ids and model names. A `.f3dmat` keeps a bare `material Ink` line. The namespace comes from the plugin that ships or registers the source, and the site says so.
   - Alternative: from `f3dmat 3` the `material` line takes the dotted id (`material acme_ink.ink`). The parser then derives the identifier, and a bare name stays legal for a project's own materials.
2. **Versioning the kernel language's words (F2).**
   - Recommended: every word, builtin and binding word carries the version it arrived in, as in the material language. The v2 `atomic…` words stay reserved in v1 sources as they are today, since nothing depends on freeing them. v3 takes its words only in `kernel 3` sources.
   - Alternative: reserve now, in every version, the words v3 will need (`shared`, `barrier`, `workgroupBarrier`, `uniform`, `local_id`, `group_id`, the storage formats), and keep one set.
3. **Wasm render nodes and the simulation's state (F17.1).**
   - Recommended: a render node runs in an instance of its own, never in the step system's, and its state is outside `save` and the digest. A module may export both, and gets two instances.
   - Alternative: one instance, with the render call forbidden to write memory the step reads. That cannot be checked, so I would not take it.
4. **Floats in render modules (F17.2, F17.4).**
   - Recommended: a module is a step module (i32-only, `f3d_step` required, as today) or a render module (`f32` allowed, `f3d_step` not required, budget per frame). They are told apart by the `.f3dplugin` section that declares it, and checked at decode.
   - Alternative: i32-only everywhere, with floats crossing as bit patterns through imports.
5. **Memory across the render ABI (F17.3).**
   - Recommended: commands are imports with scalar arguments. Bulk data is `(ptr, len)` in module memory, copied by the host during the call and never kept. Resources are named by their index in the `.f3dplugin` declaration, as fields are.
   - Alternative: `f3d_render_node` returns a command buffer in module memory that the host decodes after the call.
6. **`scene_colour` in the ABI (F7).**
   - Recommended: rename to `scene_color`, `scene_color_texture` and `SceneColorCopy` before the base is re-recorded.
   - Alternative: keep them and list them in C as the ABI's spelling until 2.0.
7. **When the ABI base is recorded (F6).**
   - Recommended: tagging rc.1 records the base from the tagged commit, as one step of the tag (beside the API baseline in `tool/api/baseline/v1.0.0-rc.1/`). Until then the rule compares against the current base and 4.3 re-records with a line in the commit.
   - Alternative: keep the 2026-10-13 base and let every 4.3 change re-record it by hand.
8. **Varyings and sampler kinds in the `.abi` (F5).**
   - Recommended: add `out`/`in` lines per engine stage, the sampler's kind, and the attribute formats, before the base is recorded.
   - Alternative: document the varyings in C and leave the file as it is.
9. **The language version of decision 123's injection points.**
   - Recommended: if they land in 4.3I before the rc.1 tag, they are `f3dmat 3`, with the v3 fixture extended. Anything after the tag is `f3dmat 4`.
   - Alternative: they open `f3dmat 4` in any case, so version 3 stays what 2026-10-15's tree reads.
10. **A rule that each vocabulary grows only with its version (F4).**
    - Recommended: one vocabulary snapshot per language (`.f3dmat`, kernel, Wasm imports and exports), with a rule that every line new since the 1.0 base carries a version above the base's newest.
    - Alternative: package tests only, as the material growth test does now.
11. **GLSL keywords as material names (F8).**
    - Recommended: refuse the full GLSL 4.60 and GLSL ES 3.00 keyword and reserved lists in every version, with the existing sentence.
    - Alternative: mangle every local in the GLSL emitter, as the WGSL translator does (`m_<name>`). The generated shader stops reading like the source, and the read-as-before record is rewritten.
12. **What a `.f3dmat` may hold after its first block (F9).**
    - Recommended: at most one material-language block, first, then only kernel-language `compute` blocks. `parseMaterial` refuses anything else with a sentence.
    - Alternative: document "the first block is the material, everything after it is the kernel parser's" and leave the parser as it is.
13. **Which frame resources are promised (F14).**
    - Recommended: the table in C lists all 24 ids after the `f3d.` rename. Each gets either its encoding or "readable, encoding not frozen".
    - Alternative: freeze the four and refuse plugin reads of the others until a minor promises them.
14. **Array lengths in the ABI (F15).**
    - Recommended: accept 8 forward lights and 16 decals a draw as fixed through 1.x, and say so in C. More lights come through the light list or a new block.
    - Alternative: exempt array lengths from the rule and have stages read the count from a member. This breaks every prebuilt plugin stage the day it changes.
15. **Error messages (F19).**
    - Recommended: C says the wording is not a contract. Codes (`f3dmat.E012`) come additively in 1.x, beside the sentence.
    - Alternative: codes in rc.1 for all three languages.
16. **A conformance check for material compilers (F12).**
    - Recommended: with decision 92 in rc.1, the null backend's compiler runs a corpus check (the v1-v3 fixtures, own blocks and textures, the budget refusal). C says a GPU backend's compiler accepts every construct of the versions it claims, or refuses the whole material by name.
    - Alternative: the sentence now, the check in 1.x.
