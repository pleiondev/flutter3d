# 29. Formats and wire contracts before 1.0 (2026-10-15)

This audit reads the working tree of branch `1.0.0` at `da3b09a6e`. It covers every persistent or on-the-wire contract that 1.0 freezes outside the Dart signatures:

- the `.f3d` envelope and its section kinds;
- `f3d.pipeline`, the project file (`.f3dproj`), material files (`.fmat`, `.f3dmat` as files), and the bundles (F3SB shader and material bundles, `.f3dplugin`);
- saves, runs, tapes, ghosts, traces and captures;
- network protocols (`flutter3d_net`, the relay, `flutter3d_net_webrtc`, `flame_multiplayer`, `flame_multiplayer_dashwire`, `flutter3d_editor_play`, `flutter3d_hub`, `flutter3d_education_lti`);
- native ABIs (the wgpu sidecar, `flutter3d_physics_native` and its snapshot) and platform channels (`flutter3d_pointer_lock`, `pad_input`).

It measures them against `docs/CONTRACTS.md` (Files, The envelope, Reserved names, Names). It also rechecks the format, network and native findings of audit 07 (2026-10-09). It does not reopen decisions 63–126 (`tasks/1.0-readiness-review.md` §6, last subsection). Where one of those decisions changes a file or wire word, this audit names what the change needs in order to keep the file promise.

No code was changed and no suite was run. A claim marked "read" was checked in the code. Counts come from `rg` or `fd` and say so when they are a heuristic. Three parts of the reading (network, native, saves) were done by delegated readers and spot-checked at the lines cited.

Severity:
- **BLOCKER**: only a major can fix it after 1.0.
- **BEFORE RC.1**: cheap now, and after the tag it is a behaviour change or a broken promise in the docs.
- **ADDITIVE 1.x**: a minor can do it.

Abbreviations used for paths:

| Short | Path |
|---|---|
| **F** | `packages/flutter3d_core/lib/src/formats` |
| **S** | `packages/flutter3d_sim/lib/src` |
| **MC** | `packages/flutter3d_model_core/lib/src` |
| **N** | `packages/flutter3d_net/lib/src` |
| **PN** | `packages/flutter3d_physics_native` |
| **R** | `tool/structure/repository.dart` |

## Verdict

**The file formats can be frozen.** The envelope (`FormatSpec`, `flutter3d_foundation/lib/src/formats.dart:65-259`) does what CONTRACTS promises:
- it reads every version up to its own and refuses a newer one with a sentence naming both;
- it refuses 0, negative and fractional versions (audit 07 #16 is fixed at `formats.dart:192-196`);
- it keeps unknown top-level keys;
- it lifts older versions through a migration chain.

The structure rule holds 20 named formats, plus every `FormatSpec` it finds in a published package, to a fixture for every version (`R:1443-1569`). `formatWithoutFixture` is empty (`R:1589`), and every fixture is opened by a test. The `.f3d` container (section directory, must-understand flag, record stride from v2, a vendor kind range and a reserved wide magic) is a better growth story than most 1.0 engines ship.

**The native snapshot and ABIs can be frozen.** Every item of audit 07 #10 is fixed, and the snapshot fails closed under fuzzing in both C and Dart.

**The network wire is the part that cannot be frozen as it stands.** Two blockers are only cheap before the tag:

1. **`flame_multiplayer` messages are bare and unversioned** (finding 1). The keys `tape`, `frames`, `watching`, `inputs`, `snapshot` and the BatonStream `k`/`n`/`body` have no hello and no namespace. This is the same `frames` collision that protocol 3 fixed for rollback. After 1.0 a change to them cannot be told apart from today's wire.
2. **The relay's own messages use a bare top-level `relay` key and a bare `to`** (finding 2), not the reserved `f3d` key. Moving them under `f3d` later is a protocol major, and `wire_hello.dart:11-34` ties a protocol major to a package major.

Twenty-two more findings should land before rc.1 (3–16 and 24–31). The biggest are:
- saves and runs that forget which plugins they require (finding 24);
- replays checked against the base simulation, and 8 tape playbacks with no check (finding 26);
- telemetry uploads that drop the fields a replay needs (finding 27);
- the CONTRACTS sentence that network messages are "snapshotted", which is false (finding 3);
- the words decisions 67 and 68 rename inside files, which need lifts and old-spelling fixtures (finding 4);
- `.f3d` and `.f3dproj` sections that no committed fixture holds (finding 6);
- `.f3dproj` dropping sections it does not know on save (finding 7);
- the native snapshot having no committed 1.0 bytes (finding 9);
- WebRTC ignoring `reliable` (finding 11);
- `{"version": 1e999}` escaping as `UnsupportedError` from every enveloped reader (finding 25).

## 1. Contract table

"Fixture" means committed bytes minted at that version and opened by a test. "Status": **ok**, **gap** (a finding below), **0.x** (outside the 1.0 contract by decision 66).

### Files

| Format (id) | Version rule | Readers / writers | Fixture | Status |
|---|---|---|---|---|
| `.f3d` (`f3d.model`) | binary, `F3D\n`, `f3dVersion = 2` (F/f3d/f3d_format.dart:155); reads 1..2, refuses newer and 0 (F/f3d/f3d_loader.dart:104-112); unknown kind kept, `mustUnderstand` refuses (:151-167); stride from section v2 (:217-228); `F3DW` reserved and refused (:82-87); writer stays v1 unless a flag is set (F/f3d/f3d_writer.dart:288) | `F3dDocument.parse` / `F3dWriter`, `F3dWriter.carrying` (:80-90) | v1/box, v1/bundle, v2/box, v2/bundle, v2/physical; `f3d_fixture_test.dart` | ok; gaps 5, 6, 8 |
| `.fmat` (`f3d.fmat`) | JSON envelope plus legacy `fmat`, v1 (F/fmat/fmat.dart:29-48); unknown keys kept (:217, :315) | `readFmat` / `writeFmat` | v1/brass.fmat, v1/brass.enveloped.fmat | ok; gap 4 (lit model words) |
| `.f3dmat` (`f3d.materialLanguage`, alias `f3d.material`) | text, optional `f3dmat <N>` line, v3; newer refused (F/material_language/material_parser.dart:201-208, :1167-1169) | `parseMaterial` | v1, v2, v3 `rim_glow.f3dmat` | ok |
| `f3d.pipeline` | JSON envelope v1 (F/pipeline_document.dart:9-16); top-level unknown kept, node-level dropped | `PipelineDocument` | v1/standard.pipeline.json | gap 4 (decision 67), gap 10 |
| `.f3dproj` (`f3d.project`) | binary, `F3DP`, v2 (MC/project_format.dart:101-122); fixed 16-byte entries, no flags, no stride; unknown kind skipped on read and **dropped on write**; CRC in header word 12 (:150) | `readProject` / `writeProject` | v1, v2 `workshop.f3dproj` (sections 1–6 only) | gaps 6, 7 |
| `.f3dsplat` (`f3d.splat`) | binary `F3DS`, fixed 16-byte header with no reserved word, newer refused (F/splat/splat_octree.dart:491-501, :591-605) | octree reader / writer | v1/one.f3dsplat | ok; no additive headroom (Q8) |
| lightmap (`f3d.lightmap`) | binary `F3DL`, v1, newer refused (S/level/lightmap.dart:76-93, :185-189) | `Lightmap` | v1/room.lightmap.bin | ok |
| F3SB shader / material bundle | binary `F3SB`, container v2, sections versioned inside (`materialSectionVersion`, `kernelSectionVersion`), unknown stage kind refused as `stale`; Impeller section pinned to the Dart SDK token (`flutter3d_hardware/lib/src/shader_bundle.dart:138-168, :245-273, :340-371`) | `ShaderBundle.decode`, `BundledMaterials.read` (F/material_language/material_bundle.dart:57-76) | v1, v2 `effects.f3shaders` | ok as a **build artifact**; Q7 |
| `.f3dplugin` (`f3d.plugin`) | JSON envelope plus legacy `f3dplugin`, v4, migrations to v4 (`flutter3d_plugin_runtime/lib/src/data/data_plugin.dart:177, :270-277`); section `requires` resolved per registry (:285-301) | `DataPluginDocument` | v1–v4 glow.f3dplugin | ok; decision 120 adds sections |
| `.f3dtrace` (`f3d.trace`) | binary `F3DTRACE`, v2, word tables (`flutter3d_hardware/lib/src/trace/trace.dart:115-129`) | `Trace` | v1, v2 frame.f3dtrace | gap 12 (HAL decisions change its vocabulary) |
| level (`f3d.level`) | envelope v5, four migrations (S/level/level.dart:105-117); nested write-through keeps unknown keys in brushes, lights, entities, materials and prefabs (`json_write_through.dart`) | `Level` | v1–v5 first.level.json | ok |
| saves, runs, tapes, ghosts, settings | see §4 | | | see §4 |

### Wire

| Protocol | Version rule | Fixture / snapshot | Status |
|---|---|---|---|
| `flutter3d_net` PeerRoom hello | protocol 3.0; major refused with a reason, `SimulationVersion` exact, minors compatible, the lower minor is shared (N/wire_hello.dart:101-143) | Dart constants only in `api/flutter3d_net.api`; no wire golden | gap 3 |
| rollback | under reserved `{"f3d":"rollback"}` (N/rollback_session.dart:259-270) | none | gap 13 |
| relay (`bin/relay.dart`) | `protocol=<maj>.<min>` query, major refused with close 1008 (:462-478); messages use bare `relay`/`to` (:359-431) | none | **BLOCKER 2** |
| `flame_multiplayer` (party, baton, feed) | no hello, no version (`party.dart:26-291`) | none | **BLOCKER 1** |
| `flutter3d_net_webrtc` | none; signalling `{kind: offer/answer/ice}` bare (`webrtc_transport.dart:57-62`) | none | gap 11 |
| `flame_multiplayer_dashwire` | 0x00 byte frames bytes, JSON otherwise (`dashwire_wire.dart:36-71`) | none | 0.x (decision 66), still at `1.0.0-rc.1` |
| `flutter3d_editor_play` | VM extensions `ext.flutter3d.level.apply`/`.patch` with fallback (`level_push.dart:110-125`) | `flutter3d_game/api/flutter3d_game.vm:12,17` | 0.x, still at `1.0.0-rc.1` |
| `flutter3d_hub` | `HubProtocol.version` 1.0, same-major rule (`hub_protocol.dart:99, :217-264`) | `api/flutter3d_hub.hub`, `test/fixtures/references.json` | ok |
| `flutter3d_education_lti` | LTI `claim/version` never checked (`lti_launch_claims.dart:7-18`) | inline strings only | 0.x, still at `1.0.0-rc.1`; gap 14 |

### Native

| Contract | Version rule | Test | Status |
|---|---|---|---|
| wgpu sidecar C ABI | `F3D_WGPU_ABI_VERSION 1` (`flutter3d_wgpu/csrc/f3d_wgpu.h:27`) = `wgpuAbiVersion` (`lib/src/wgpu_bindings.dart:14`); exact match, a refusal sentence (`lib/src/wgpu_device.dart:57-83`, read) | **no test holds the define to the const** | gap 15 |
| physics FFI | `F3D_ABI_VERSION 42u` (PN/csrc/include/f3d_physics.h:49) = `abiVersion` (PN/lib/src/core/constants.dart:8) | `test/bindings_test.dart:23-27` (read), ~60 defines, function sets, `offsetof`/`sizeof` | ok |
| physics snapshot `F3DS` | major 1 / minor, 17 sections with id, version and length; major ≠ 1 refused (PN/csrc/src/f3d_snapshot.c:1397, read); unknown sections skipped; missing known section refused by `since_minor` (:1433); staged restore (:1445-1533) | C fuzz 1500 rounds, Dart fuzz 600 + 200 rounds; **no committed 1.0 bytes** | gap 9 |
| `flutter3d_pointer_lock` 0.5.0 | channel `dev.flutter3d/flutter3d_pointer_lock` plus `/events` (`lib/src/pointer_lock_method_channel.dart:11-18`); no handshake | channel names held against the native sources (`test/platforms_test.dart:180-209`) | gap 16 |
| `pad_input` 0.5.0 | EventChannel `dev.flutter3d/gamepad/events`; unknown `event` ignored | **no test reads the native side** | gap 16 |

## 2. Findings

### BLOCKER

**1. `flame_multiplayer` has no hello, no version and bare keys** (audit 07 #13, still open).
- `PartyTape` sends `{'tape': step, 'frames': {...}}` (`packages/flame_multiplayer/lib/src/party.dart:49-54`, read) and listens for a bare `watching` (:63).
- `AuthorityServer` and `PredictingClient` use `inputs`, `snapshot`, `ran`, `tapeFrom` and `state`. `BatonStream` uses `k`, `n` and `body` (`baton_stream.dart:105-116`). `PeerFeed` uses `n` and `body` (`peer_feed.dart:16-24`), so its filter also matches BatonStream messages on a shared wire.
- The only version check is the relay's `simulation=` query. A party on any other transport forms without one.
- Why it is a blocker: once 1.0 peers exist, a 1.x change to any of these shapes cannot be told apart from today's wire, and a game message that has a `frames` or `tape` key is taken as the engine's.
- The fix is to move the messages under the reserved key (`{"f3d":"party", ...}`), as protocol 3 did for rollback, and make the party require the PeerRoom hello. It is cheap now and a wire break later. See Q1.

**2. The relay's control messages are not under the reserved key.**
- `welcome`, `full` and `left` are `{"relay": ...}` (`packages/flutter3d_net/bin/relay.dart:359-411`, read at :359-371). Routing reads a bare top-level `to` (:392-398, :421-431).
- When observers are present, any message from slot 0 that has an integer `to` is unicast or dropped (`room.at` returns null for an unknown slot).
- The welcome carries `protocol: [3, 0]`, and the client ignores it (`party_join.dart:197-208`).
- Why it is a blocker: putting these under `f3d` later is a protocol major (`wire_hello.dart:11-34`), which the same file ties to a package major. See Q2.

### BEFORE RC.1

**3. CONTRACTS says network messages are snapshotted; they are not.**
- `docs/CONTRACTS.md:316-318` groups "network messages" with MCP and VM answers as "versioned by their server's schema version and snapshotted".
- The snapshots under `packages/*/api` that are not `.api` are `.vm` ×3, `.mcp` ×3, `.cli`, `.abi` and `.hub` (`fd`). None is a network wire.
- `flutter3d_net.api` freezes only the constants: `engineKey 'f3d'`, `messageKind 'rollback'`, `bytesFrame 'bytes'`, `currentProtocolMajor 3`, `currentProtocolMinor 0`.
- Every wire test builds its messages from those same constants (`rollback_test.dart:358`, `wire_bytes_test.dart:86`), so a renamed key passes. The one literal frozen in a test is the legacy hello (`peer_room_test.dart:22`).
- The version is "protocol 3.0", not a server schema.
- Fix: write `api/flutter3d_net.wire` (each message's tag and keys, one per line, the shape of the `.mcp` snapshot) plus golden JSON fixtures that a test parses, and have the structure rule fail a changed line within a major. Otherwise correct the sentence. See Q3.

**4. Decisions 67 and 68 rename words that are already in files, and the plan only half-covers it.**
- Decision 67 renames the built-in anchors, resources and steps to `f3d.<name>`. Wave 4.3A says "the v1 alias table and the fixture rewritten" (`tasks/1.0-rc1-plan.md:522`).
  - Rewriting `packages/flutter3d_core/test/fixtures/v1/standard.pipeline.json` contradicts the fixture rule ("minted once and never re-minted", `f3d_fixture_test.dart:5-12`). It would also leave the alias table with no file that proves it reads.
  - The same names reach `.f3dplugin` `pipeline:` sections (`F/pipeline_document.dart:97-101`) and the `v1`–`v4` plugin fixtures.
- Decision 68 changes lighting-model names from `<ns>_Name` to `<ns>.name`. `writeLightingJson` writes `model.shaderName` as the file word (`F/fmat/lighting_json.dart:74-82`, read). That word goes into `.fmat`, the `.f3d` `materialLighting` section (kind 32) and level materials. The decision says nothing about the readers.
- CONTRACTS:352-354 says words move only with the format's version, and CONTRACTS:706-709 shows how: the level moved its spelling at v5 and lifts the v4 words.
- Fix:
  - `f3d.pipeline` goes to v2 with a migration that renames, and the v1 fixture stays as it is, next to a new v2 fixture.
  - `.fmat` and `.f3d` read the old `<ns>_Name` words through an alias in `LightingModels.named`, held by the existing v1 fixtures. Both formats stay at their versions, because the word is a value and not a key.
  - See Q4.

**5. An unknown lighting model in a file opens as a different material, with only a warning.**
- `readLightingJson` returns null for a name that is neither shipped nor registered, and the scene's model is used instead (`F/fmat/lighting_json.dart:27-38`, read).
- So a `.fmat` or `.f3d` that names a plugin's model, opened without the plugin, draws with the default model. Nothing in `requires` names the plugin, though CONTRACTS:331-336 says `requires` exists so that "an older reader refuses instead of dropping it".
- Levels already do this for components (`S/level/level.dart:144-151`).
- Fix: a `.fmat` names the namespace of a plugin model in `requires`. For `.f3d`, record it in the `materialLighting` record or a must-understand section. This is additive for the reader, but files written by 1.0.0 without it stay ambiguous for good. See Q5.

**6. Seven `.f3d` sections and three `.f3dproj` sections are in no committed fixture.**
- `.f3d`, read from the fixture directories: v1/box has kinds 1–13. v1/bundle and v2/bundle have 1–22, 29–35 and a vendor kind. v2/physical adds 36–37.
  - **No fixture holds kinds 23 (variants), 24 (pointer tracks), 25 (impostors), 26 (clusters), 27 (LOD errors), 28 (extras) or 38 (asset rights).**
  - `formatSectionFixtures` names only section 36 (`R:1415-1423`).
- `.f3dproj`: both fixtures hold sections 1–6 only. **History (7), history images (8) and simulation caches (9) have no 1.0 bytes.** Neither do manifest keys like `animationGraphs` or paint layers, which needs checking.
- Fix:
  - Mint `v2/everything.f3d` with every engine kind, and list each kind in `formatSectionFixtures`.
  - Mint `v2/history.f3dproj` with sections 7–9.
  - Add a structure rule: every constant in `F3dSection` and `ProjectSection` appears in a fixture's directory. It is a few lines over the bytes.

**7. `.f3dproj` drops on save every section it does not know.**
- The reader steps over an unknown kind (MC/project_format.dart:12-18). The writer writes only the sections it builds (:495-530); there is no `extraSections` as `.f3d` has (F/f3d/f3d_loader.dart:204-208).
- A project saved by a 1.1 editor and opened and saved again in a 1.0 editor loses what 1.1 added, with no word.
- The project directory also has no flags and fixed 16-byte entries (MC/project_format.dart:157). A 1.x section that must not be skipped can only be expressed by bumping the version.
- Fix (Q6):
  - before rc.1, keep unknown sections on write as `.f3d` does;
  - take `.f3d`'s v2 directory (entry size in the header, a flags word, `mustUnderstand`) as project v3 now, while no 1.0 reader exists;
  - word 12 is the CRC, so the entry size goes in the directory or a new header word.

**8. `.f3d`: a hostile header escapes as `RangeError`, and unknown flag bits have no defined meaning.**
- Overflow. `directoryEnd = 16 + sectionCount * entryBytes` (F/f3d/f3d_loader.dart:126) is a product of two u32 values from the file.
  - From v2, `entryBytes` has no upper bound (:117-125). On the VM the product can pass 2^63 and wrap negative, so the bound check passes, and the next `getUint32` throws `RangeError` rather than `F3dFormatException`.
  - On the web the product does not wrap.
  - There is no fuzz test for `.f3d`. `rg -il fuzz` finds the CPU, WebGL, mesh and physics fuzzers, none for a model format.
- Flags. Only bit 0 (`mustUnderstand`) is defined (F/f3d/f3d_format.dart:180-184). A 1.0 reader ignores every other bit.
  - So a 1.x flag that changes how a section's bytes read, such as compression, needs a version bump.
  - Nor is there a "safe to copy" rule for the unknown sections `extraSections` writes back. A 1.0 tool that re-exports a 1.1 file after editing its tables (`F3dWriter.carrying`, F/f3d/f3d_writer.dart:80-90) keeps a 1.1 section whose indices no longer match.
- Fix:
  - cap `entryBytes` at, say, 256, and check with `BigInt`-free arithmetic (`sectionCount > (len - 16) ~/ entryBytes`);
  - add a seeded `.f3d` fuzz test (bit flips and truncation over v2/bundle, expecting only `F3dFormatException`);
  - define the flag bits in CONTRACTS now (Q9).

**9. The native snapshot has no committed 1.0 bytes.**
- Grep finds no `F3DS` bytes, no base64 `RjNEUw` and no `.bin` under `PN/test`. The migration tests build old bytes by rewriting current ones.
- The only regression guard is `sharedSceneHash = 'af9c722f'` (PN/test/scenes/shared_scene.dart:17), and its failure message invites updating it (`shared_scene_test.dart:17`).
- Joint records grew four times during the rc (PN/CHANGELOG.md:107, :139, :158).
- A 1.x field reorder would pass every test and break every save.
- Fix: commit the 1.0 bytes of a busy world (with a vehicle and a multibody, which `busyWorld` lacks, `snapshot_fuzz_test.dart:156-191`) at f32 and f64. A test restores them, steps them, and compares against a recorded digest. Add the snapshot to `versionedFormats`.

**10. Unknown keys are kept only at the top level, except in levels.**
- CONTRACTS:347-348 says "Unknown keys are kept. A document opened and saved by an earlier minor keeps what a later one added." `FormatDocument` keeps the top level only (`formats.dart:329-336`).
- Only the level writes nested unknown keys back: 7 files use `writeThrough` (`rg`), all in `S/level/`.
- Everywhere else a key a 1.x minor adds inside a nested object is lost when a 1.0 tool saves. That covers pipeline nodes (F/pipeline_document.dart, `PipelineNode.toJson`), effect emitters, action bindings, plugin sections, `.f3dproj` objects, and component rows (audit 07 #9, §4).
- Decision 115's `perView`/`once` on nodes is exactly such a key, although it arrives in rc.1.
- Fix (Q10): either narrow CONTRACTS to "top-level keys", or extend `FormatDocument` with a nested `unknown` for the documents an editor rewrites (pipeline nodes, effect emitters, plugin sections). The doc change is the minimum.

**11. WebRTC ignores `PeerSend.reliable` and opens an unordered channel.**
- `createDataChannel('net-01', RTCDataChannelInit()..ordered = false)` sets no `maxRetransmits` (`packages/flutter3d_net_webrtc/lib/src/webrtc_transport.dart:76-79`, read).
- So every message is reliable but unordered, which breaks "reliable arrives in order" (N/peer_wire.dart:61-67) that rollback and the observer rely on.
- Signalling is bare and unversioned (`webrtc_transport.dart:57-62`). The `!`/`as` casts at :135-153 throw inside an async listener.
- Fix: two channels, ordered-reliable and unordered with `maxRetransmits: 0`, and a `{"f3d":"signal","v":1,...}` shape. Because no 1.0 peer exists yet, it is cheap now.

**12. The HAL decisions change what a trace records.**
- `.f3dtrace` v2 records HAL calls through word tables (`flutter3d_hardware/lib/src/trace/trace.dart:115-129`).
- Decisions 83, 86, 87, 95, 96 and 97 change exactly those calls: topology and index features, `ClearColor`, the split blend constant, a double `Viewport` with a depth range, `bindUniformBuffer`, and the new `PassState` fields.
- Wave 4.3C (`tasks/1.0-rc1-plan.md:528`) does not name the trace.
- Fix: add to 4.3C "the trace records the new calls at v3 with a fixture, and the v2 `setViewport(ScreenRect)` lifts". Otherwise every recorded trace of rc.0 replays a different frame. A malformed trace throws `StateError` on replay (trace.dart:209, :217); a `TraceFormatException` is the right type.

**13. Network hostile input and correctness** (`flutter3d_net`, relay):
- `_same` compares frames shallowly (N/rollback_session.dart:435-437, read). A frame holding a list or map never compares equal after a JSON round trip, so it always counts as a misprediction. Either compare deeply or document and assert flat frames.
- The `hello` channel tag is reserved only by an `assert` (N/peer_room.dart:107-108, read). In release, `channel('hello')` sends frames the other side reads as hellos. Make it a `NameTakenException`.
- Floats travel as JSON doubles with nothing guarding NaN or Infinity. `jsonEncode` throws `JsonUnsupportedObjectError` out of `send()` (`websocket_transport.dart:82`, `dashwire_wire.dart:45`, `webrtc_transport.dart:166`). `LoopbackWire` never encodes (N/peer_wire.dart:354), so no test meets it.
- Malformed observer messages throw out of `deliver`: `SimulationVersion.fromJson`, `as int?` and `as List?` (N/observer.dart:158, :357-398).
- The relay:
  - has no per-message size limit, no rate limit and no per-client cap (one client can open all 4096 codes, `relay.dart:129`);
  - has no `onError` on `socket.listen` (:243, :382), which probably kills the process (not verified);
  - forwards text verbatim without stamping the sender, so any peer can forge `{"relay":"left"}` or another slot's `from`;
  - can give a returning watcher the slot of one still present (:339).
- Audit 07 #13: the hello without a body is **fixed** (N/peer_room.dart:143-160). `_early` is **fixed for count** (`maxStepsAhead = 600`, N/rollback_session.dart:107, :352-355), but not for bytes per frame.
- `flame_multiplayer` buffers grow without bound (`BatonStream._early`, `AuthorityServer._queued`, `PartyTapeWatcher._steps`, `PredictingClient._unacknowledged`), and a snapshot is accepted from any sender (`party.dart:279-284`). These go with finding 1.

**14. The four 0.x packages are still versioned `1.0.0-rc.1`.**
- `flame_multiplayer_dashwire`, `flutter3d_editor_play` and `flutter3d_education_lti` are at `1.0.0-rc.1` in their pubspecs (read). Decision 66 keeps them at 0.x, and wave 4.3A owns the move.
- Recorded here only because their wires (LTI `claim/version` never checked, AGS `'$lineItemUrl/scores'` wrong for a URL with a query string at `ags_client.dart:55`, a JWKS refetch on every unknown `kid` at `lti_launch_validator.dart:113-117`) are outside the 1.0 promise only once the number says so.

**15. The wgpu sidecar's ABI number is held by nothing.**
- `F3D_WGPU_ABI_VERSION` and `wgpuAbiVersion` are equal today, and the load check refuses a mismatch with a sentence (read).
- No test compares the header define with the Dart const, or the declared functions with the bound ones. Physics has that test (PN/test/bindings_test.dart:17-27, :131-153).
- The header documents neither threading (single error buffer) nor the lifetime of `texture_native_metal`'s borrowed pointer.
- An unknown binding kind maps to IMAGE through `default:` (`f3d_wgpu.c:485`) instead of being refused.
- `buffer_write` drops a write silently on `calloc` failure (:264-265).
- Fix: copy the physics binding test, about 20 lines, and add the header sentences.

**16. Platform channels: errors on an older native side, and an untested map.**
- `flutter3d_pointer_lock`'s `capture`, `release` and `reset` call `invokeMethod` with no `MissingPluginException` catch (`pointer_lock_method_channel.dart:120-126`). The event stream is guarded (:43-47, :81-89). A 1.x method added later throws on a native side that predates it, unless Dart catches it now.
- `pad_input`'s channel name and map keys (`event`, `device`, `slot`, `name`, `axes`, `code`, `down`; `pad_slots.dart:58-168`) are not checked against the Kotlin, Swift, Windows and Linux sources. `pointer_lock` has that test.
- `flutter3d_game` 1.0 pins both at `^0.5.0` (`flutter3d_game/pubspec.yaml:44,50`), so a breaking 0.6 needs a 1.x game release to adopt it (Q11).
- `packages/pointer_lock/` is untracked: `git ls-files` gives 0, and `fd` finds 8 files, all generated `example/macos/Flutter/ephemeral` output from the package's earlier name. Delete it.
- Two more channels were not audited here: `flutter3d/cloud_saves` (no `dev.` prefix, `flutter3d_game/lib/src/cloud/platform_cloud_saves.dart:51`) and `dev.flutter3d/stereo/head` (`flutter3d_stereo/lib/src/head_tracker.dart:51`). The names are inconsistent, and a rename later is a break (Q11).

### ADDITIVE 1.x

17. `f3d.rule` is reserved in CONTRACTS:372-374 only. A plugin cannot take it, because plugin ids are namespaced (`flutter3d_plugin_api/lib/src/formats.dart:136-160`). `FormatRegistry.add` for the application (:99-121) and any engine package can. A one-line check in `add` and a structure rule would close it.
18. `.f3d` builds `Float32List.view`s over file bytes (F/f3d/f3d_loader.dart:278-318). These are host-endian, while the format is stated as little-endian (F/f3d/f3d_format.dart:19-21). Every Dart target is little-endian today, but nothing asserts `Endian.host == Endian.little`. A one-line guard would refuse instead of misreading.
19. `.f3dproj` paint layers fall back to `normal` silently on an unknown blend word (MC/project_format.dart:3531-3534). The project's own rule is fallback plus warning (`_named`, :2329-2340).
20. Floats in JSON formats are written by `jsonEncode`, which is shortest round-trip. NaN and Infinity throw at write time, not at read time. One sentence in CONTRACTS: "a non-finite number is refused when written".
21. There is no committed golden of what the 1.0 writers produce. The fixtures prove reading only. A writer change that alters bytes but still reads is invisible. That is acceptable under the contract, but a `writer_golden_test` for `.f3d` v1 would catch a 0.8-reader break earlier than `f3d_fixture_test.dart:114-149` does.
22. Physics: `f3d_world_create` is called before the ABI check (PN/lib/src/native_world.dart:1754-1765). Bit-exactness is checked in CI on Linux x64 and Windows x64 only (`csrc/tests/test_digest.c:21-27`). arm64, Android and iOS are checked by hand (`tool/digest_platforms.sh`). An arm64 lane would help.
23. The hub has no network code yet (`hub_protocol.dart:94-96`), so it has no size or timeout limits beyond `HubCachePolicy.maxBytes` (256 MiB).

## 3. Audit 07, rechecked

| 07 # | Subject | Now |
|---|---|---|
| 10 | native `consistent()` indices, `sec_wind` allocating before the check | **fixed**: compound part hull (PN/csrc/src/f3d_snapshot.c:1343-1345), slot hull (:1224-1243, :1279), shallow reals (:1380-1381), manifold a/b (:1347-1350), chassis (:1351-1354), wind (:926-943). ABI is 42, not 07's 37 |
| 13 | hello without body, party without hello, `_early` | hello **fixed**; `_early` **fixed** for count; party **still open** (finding 1) |
| 16 | `versionOf` 0 or negative | **fixed** (`formats.dart:192-196`); the other two parts in §4 |
| 17 | `.name`/`values[]` into files | see §4; open sets (`PaintBlendMode`, `PhaseKind`, `GameState`, `ObserverMode`, `ConvertOutcome`) write their explicit `name`, which is a wire name and not a Dart identifier. Of 125 `'key': x.name` hits (`rg`, heuristic), the sampled ones are open sets or string fields |
| 5–9, 11, 12, 18, 21 | saves, replays, codecs, Wasm restore | §4 |

## 4. Saves, runs, tapes and ghosts

All of these are enveloped JSON read through `FormatSpec.open`, unless the table says otherwise. Floats go out through `jsonEncode`, which is shortest round-trip on the VM and JS. NaN or Infinity makes the *write* throw `JsonUnsupportedObjectError`. `StateDigest` (S/save/state_digest.dart) hashes values, not text: float64 bits, one NaN pattern, −0 folded to 0, a 32-bit FNV-1a. That width is now a 1.0 contract.

| Format | Version | Unknown keys | Fixture | Status |
|---|---|---|---|---|
| `f3d.save` (`Snapshot`, S/save/snapshot.dart:83) | 1; parts `{version, data}`, a newer part refused (S/ecs/snapshots.dart:196); `WorldSnapshotPart` v2 with `changedAt` (:257-271); newer component version refused (S/ecs/ecs_world.dart:374-388) | top level kept; the outer `SaveRecord` is not enveloped and drops them | v1/save.json, older than the envelope, `componentVersions` and `requires` | gaps 24, 25, 28 |
| `f3d.run` (`Demo`, S/save/demo.dart:182) | 5, writes the lowest version that fits (:324); `SimulationVersion` keeps `extra` (`flutter3d_plugin_api/lib/src/simulation_version.dart:388`) | top level kept (:551); tape-frame extras dropped (`input_tape.dart:50`) | v1–v5, synthetic; one real recording replayed (`apps/flutter3d_demo_platformer/test/tapes/ascent.f3drun`) | gap 26 |
| `f3d.inputTape` (S/input/input_tape.dart:286) | 2, v1 identity; `requires: externalInputs` (:301) | kept | v1, v2 | ok; casts (gap 29) |
| `f3d.share` (S/share/share_bundle.dart:56) | 1, level hash verified | kept, level raw | v1 | ok |
| `f3d.telemetry` (S/telemetry/telemetry_upload.dart:65) | 1 | — | v1 | gap 27 |
| `f3d.saveSlots`, `f3d.settings`, `f3d.actions` | 1, 2, 1 | kept; a newer index is listed and never overwritten | v1 (v2 settings) | ok |
| `f3d.cloudSaves` (`flutter3d_game/lib/src/cloud/save_sync.dart:122`) | 1 | a newer file reads as empty and is **overwritten** by the next `consent()`; `withdraw()` drops unknown keys | v1 | gap 29 |
| `f3d.ghostTape` (`flutter3d_game_kit/lib/src/ghost/best_run.dart:130`), `f3d.ghost` (`flutter3d_game_racing/lib/src/ghost.dart:73`, v2) | 1, 2 | **dropped** (not `FormatDocument`s) | kit v1; racing v1, v2 | additive |
| `f3d.match` (`flutter3d_game_strategy/lib/src/order_tape.dart:225`) | 2, `_toPreWater` | kept; unknown order kinds refused | v1, v2 | gap 26 |
| `f3d.frameCapture` (`flutter3d_core/lib/src/engine/render/frame_capture.dart:419`) | 2; texture formats by word table (:736) | kept; bad rows skipped | v1, v2 | ok |
| `f3d.voxelWorld` (`flutter3d_voxel/lib/src/voxel_world.dart:133`) | 1; `generatorVersion` inside | top level kept, terrain's own dropped | v1 | gap 29 |

### BEFORE RC.1

**24. A save or run forgets which plugins it requires.** CONTRACTS:333-336 promises that a save requires the namespace of every plugin whose part or component it holds, and that a restore refuses with their names. `Snapshot.requires` is read (S/save/snapshot.dart:131) and answered in `Snapshots.restore` (S/ecs/snapshots.dart:173-187). Four paths build a new `Snapshot` without it:
- `SaveRecord.read` (`run: Snapshot(run)`, S/save/save_record.dart:118, read);
- `loopStateWith` (`flutter3d_game/lib/src/run/run_part.dart:30-37`, read);
- `GenrePlugin.loopStateOf` (S/loop/genre_plugin.dart:172);
- `runStateOf`/`runStateIn`.

The result: a save holding a plugin's state restores without that plugin and saves again with `requires: []`. Separately, a component declared by the application (`declaredBy == 'app'`) is never listed. An unregistered component id or snapshot part is skipped silently (S/ecs/ecs_world.dart:379, :410; S/ecs/snapshots.dart:191) and is gone at the next save. This is the closest thing to a blocker in the saves: every save written by 1.0.0 without `requires` reads as "needs nothing" for good. Fix it before rc.1, with a test that runs a plugin part through `SaveFile.writeRecord` → `parse` → restore without the plugin and expects a refusal by name.

**25. `{"version": 1e999}` escapes as `UnsupportedError` from every enveloped reader.**
- `FormatSpec.open` checks `raw != raw.roundToDouble()` (`formats.dart:192`), and Infinity passes that check. `versionOf` then calls `toInt()` (:161) and throws.
- The same happens in the pre-checks of `Demo._read` (S/save/demo.dart:433), `MatchDemo._read` and `InputTape.fromJson` (S/input/input_tape.dart:316). It also happens to a `schema` or `step` of 1e999 in `SaveRecord`, against `SaveFile.parse`'s "never throws", and to Infinity in `componentVersions` or `changedAt` (S/ecs/ecs_world.dart:369, :482).
- Fix: `raw.isFinite` in `open`, used by the other places. It is one line plus one test.

**26. Replays are checked against the base simulation, not the one that ran** (audit 07 #8, partly fixed).
- The timeline and the recording now always check (`flutter3d_game/lib/src/run/demo_timeline.dart:48`, read; `demo_recording.dart:278`). But they check `loop.simulationBase`, not `simulationVersion` (S/loop/engine_loop.dart:240).
- `DemoRecording` records `engineOnly` by default (`demo_recording.dart:24`). So a plugin or subsystem bump replays and diverges at the checkpoint instead of refusing (stability decision 9).
- 8 direct `InputTapePlayback(demo.tape)` calls remain without a check (`rg`): `S/telemetry/resimulation.dart:142`, `flutter3d_testing/lib/src/test_replay.dart:374`, `replay_golden.dart:54`, `replay_pacing.dart:162`, `apps/flutter3d_showcase/.../sharing_ghosts.dart:172`, `replay_tests.dart:171` and `apps/flutter3d_demo_platformer/lib/src/ghost.dart:51`. Only `ghostOfRun` and `sim_mcp` (`sim_session.dart:389`) check.
- `MatchDemo.checkSimulation` has no caller in `lib/` or `apps/`.
- Fix: record and check `simulationVersion`, and make `InputTapePlayback` take the `Demo` and check it itself, with a raw-tape constructor named for tests.

**27. Telemetry uploads replay as a different run.** `TelemetryUpload.prepare` rebuilds the `Demo` from ten fields (S/telemetry/telemetry_upload.dart:108-124, read). It drops `simulation`, `levelSwaps`, `loopChanges`, `events`, `poses`, `probes` and `unknown`. The server resimulates a run with swaps or loop changes as another run, and cannot refuse on the simulation, because the field is gone and `resimulate` (`resimulation.dart:107-142`) never checks it. The server also reads the whole body before checking its length on a chunked upload (`cloud/server/lib/src/http/telemetry_routes.dart:27-37`), and a `TypeError` from `consent['at'] as String?` (:155) becomes a 500.

**28. `run_part.dart` writes `'version': 1` for every genre** (audit 07 #18, still open; `flutter3d_game/lib/src/run/run_part.dart:35`, read). `loopStateOf` uses `snapshotVersion` (S/loop/genre_plugin.dart:174). Every genre is at 1 today. The first genre that bumps has its tapes restored as v1. It is a one-line fix.

**29. Hostile input in the save-side readers** (about 7, heuristic):
- `InputTape.fromJson` uses `as` casts (S/input/input_tape.dart:52-85, :325-343);
- the ghosts use `run['seconds']! as num` and `frames as List`;
- `.f3dtrace` lets an 8–15-byte file pass the magic and then throws `RangeError` at `getUint32(8)` (trace.dart:57), and throws `TypeError` from `header['events']! as List` and `trace_values.dart:64-69`;
- telemetry has the `consent['at']` cast;
- `VoxelWorld` has an unbounded `chunks` filled eagerly, with negatives caught only by `assert` (`voxel_world.dart:80-87`);
- `SaveSync._load` catches only `FormatException`.

Each should end in the format's own exception. `f3d.cloudSaves` overwriting a newer document on `consent()` breaks "a newer file is refused … never read halfway". It should refuse to write, as `f3d.saveSlots` does.

**30. Two leftovers of audit 07 #16 and #17.**
- `EffectDocument` checks `version is! int` (`flutter3d_particles/lib/src/effect_document.dart:394`). That refuses `2.0` on the VM and accepts it on the web, so behaviour differs by platform. It should go through `FormatSpec.open`'s whole-number rule.
- `color_vision_setting.dart:15-16` still stores a 1-based position in `ColorVisionDeficiency.values`, which is documented only as "menu order". Store the name, or pin the order as a wire order with a test.
- `SettingKey<int>.decode` is fixed (`isFinite`, `game_config.dart:46`). `GamePadAxis` is fixed (`pad_device.dart:96-130`).

**31. Snapshot parts that nobody registers.** `RagdollCorpses` and `BurningWrecks` now have parts (`flutter3d_game_physics/lib/src/ragdoll/ragdoll_corpses.dart:178`, `wrecks/burning_wrecks.dart:270`). These partly fix audit 07 #11. But nothing in `lib/` or `apps/` registers either one; only tests do. Either register them on install, or document the opt-in on both classes.

### ADDITIVE 1.x (with one shape question)

32. **Component rows have no slot for unknown fields** (audit 07 #9, still open). There is still no structure rule or conformance check for codecs; the only guard is the `StateError` in `EcsWorld.save()` (S/ecs/ecs_world.dart:298).
   - A 1.1 field in a component row is lost when a 1.0 build saves.
   - The codec type is `abstract base` (decision 64's family), so a minor can add an `extra`-carrying member with a default body. The shape is therefore additive, not a blocker. But saves written in between lose the fields.
   - Q14 asks whether to add it now.
33. `SnapshotFields.enumOf` (S/save/snapshot.dart:228) is public API that reads a Dart enum's `.name` off the wire, which CONTRACTS:352-354 forbids for file words. Deprecate it in favour of an open-set `byName`, or document that its enum's names are wire names.
34. Audit 07 #5, #6, #7, #12 and #21 are **fixed**:
   - #5: `holdsNothing` counts a null capture (S/ecs/snapshots.dart:62-67), and the check throws (S/loop/engine_loop.dart:979). Left over: `_GenrePart.restore` still returns silently on a null run (S/loop/genre_plugin.dart:326).
   - #6: a newer component version is refused before anything changes (S/ecs/ecs_world.dart:374-388).
   - #7: `changedAt` is saved and restored (:314-320, :473-486; part v2).
   - #12: pending input is dropped (S/loop/local_simulation.dart:161).
   - #21: the Wasm restore checks first and throws `WasmFormatException` (`flutter3d_plugin_runtime/lib/src/wasm/interpreter.dart:416-438`).

## 5. What the structure rules claim and cannot see

- **"Every versioned format has a fixture for each version it reads"** (`tool/structure/rules.dart:5983-6150`) checks that a file *exists* at each version. That a test opens it is a convention.
  - Today every fixture directory has a reading test (`rg -l fixtures/v` finds 40 test files).
  - The tests check counts ("12 triangles", "one surface"), not every field. A reader that silently drops a field still passes.
- **Sections are invisible to it.** `formatSectionFixtures` names one section of one format (`R:1415-1423`). Seven `.f3d` kinds and three `.f3dproj` kinds have no bytes (finding 6), and the rule cannot tell, because it does not read the directory. The fix in finding 6 is a rule that parses each binary fixture's directory, as the table in §1 was made.
- **The enum-ordinal rule reads only `.index` and `values[` in five paths** (`formatCodePaths`, `R:1577-1583`). It does not read `.name` on a real Dart `enum`. Only 26 enums remain in `lib/` (`rg '^\s*enum '`, heuristic), so it is small to extend. It also does not see `values[chosen - 1]` in `flutter3d_game/lib/src/config/color_vision_setting.dart:16`, which is outside the five paths (audit 07 #17, §4).
- **No rule sees a wire.** The `.mcp`, `.vm` and `.cli` snapshots have their rules, but nothing under `flutter3d_net`, `flame_multiplayer` or the relay is snapshotted (finding 3).
- **No rule holds an ABI define to its Dart constant** except through each package's own test. Physics has one and wgpu does not (finding 15).
- **`notAVersionedFormat`** (`R:1610-1709`) exempts 19 constants (`rg`, entries counted by their first line), each with a reason. The reasons read correctly, with one exception. The editor dock layout (`flutter3d_editor_widgets/lib/src/dock_layout.dart#formatVersion`) is a per-person file that falls back to the default; it is fine as an exemption but not a file a 1.x build promises.
- The plan's 4.3H row names `flutter3d_editor_core` (`project_format`) (`tasks/1.0-rc1-plan.md:537`). That file does not exist. The project format is `flutter3d_model_core/lib/src/project_format.dart`.

## 6. What is good

- **One envelope, really used.** 11 document types extend `FormatDocument`, 34 `FormatSpec`s are declared in `lib/` (`rg`), and `formatsByPackage` plus `formatsOutOfReach` are held to every spec the repository declares by a test (`flutter3d_build/lib/src/migrate/data.dart:65-119`).
- **Fail closed, everywhere it was checked.** Newer versions are refused by name in every binary reader read (`.f3d`, `.f3dproj`, `.f3dsplat`, lightmap, F3SB, trace, native snapshot).
- **`.f3d` grows like a real container.** It has a directory, a must-understand flag, stride-from-length, a vendor range, writer-minimum versions so 0.8 readers still open bundles, and the wide variant reserved by magic.
- **The native snapshot is the most hostile-input-proof format in the repository.** It is staged, checked for consistency, fuzzed in C under ASan and UBSan in both precisions, and fuzzed again from Dart, with the world unchanged after a refusal.
- **The level keeps nested unknown keys** through write-through, and refuses a level whose plugin components a reader lacks (`requires`).
- **The hub is the model wire.** It has a version, a same-major rule, unknown fields ignored, a typed refusal, a snapshot and a fixture.

## Questions for Dmitrii

1. **`flame_multiplayer` under the reserved key and behind the hello before rc.1?** *Recommended:* yes. Wrap the party, baton and feed messages as `{"f3d":"party"|"baton"|"feed", ...}` and require `PeerRoom`'s hello (protocol 3.1) for a party. *Alternative:* freeze the bare keys and document them as reserved words a game message may not use. That is cheaper now and permanent.
2. **The relay's control messages under `f3d`?** *Recommended:* yes, `{"f3d":"relay","event":"welcome",...}` and `{"f3d":"route","to":n}`. The relay should stamp `from` on everything it forwards, and the client should read the welcome's `protocol`. *Alternative:* keep `relay` and `to` and list them in CONTRACTS as reserved top-level keys.
3. **Snapshot the wire?** *Recommended:* yes. `api/flutter3d_net.wire` lists every message's tag and keys, golden JSON goes under `test/fixtures/wire/v3/`, and a rule fails a removed line within protocol 3. *Alternative:* correct CONTRACTS:316-318 to say network messages are versioned by the protocol hello and are not snapshotted.
4. **Decision 67's pipeline names: version 2 with a lift, or aliases at v1?** *Recommended:* `f3d.pipeline` v2, the v1 fixture kept unchanged, and a migration that renames. Lighting-model words (decision 68) are read through an alias in `LightingModels.named` at the current `.fmat` and `.f3d` versions, held by the v1 fixtures. *Alternative:* aliases at v1 with a second v1 fixture in the old spelling. 4.3A's "fixture rewritten" is then dropped either way.
5. **Should a material file require the plugin whose lighting model it names?** *Recommended:* yes. `.fmat` writes the namespace in `requires`; `.f3d` carries it in the `materialLighting` record; a reader without the plugin refuses with its name. *Alternative:* keep the warning and the default model, and say in CONTRACTS that a missing model is a poorer asset, not a refusal.
6. **`.f3dproj`: keep unknown sections and take `.f3d`'s v2 directory now?** *Recommended:* yes to both, as project v3, written only when a flagged section is present, as `.f3d` does. *Alternative:* keep unknown sections only, and leave must-understand to a version bump in 1.x.
7. **Is F3SB a build artifact only, never something a plugin ships?** *Recommended:* yes. Say in CONTRACTS that a plugin package ships `.f3dmat` sources, the app's build compiles them (decisions 92, 116), and a prebuilt bundle is refused as stale on another Dart SDK. *Alternative:* a source-only bundle (material and kernel sections, no Impeller section), which never goes stale and may be shipped.
8. **Headroom in `.f3dsplat` and the lightmap?** *Recommended:* no change. They are small, regenerable formats where "newer is refused" is enough. *Alternative:* add a reserved u32 flags word to both headers now, as v2, while no 1.0 file exists.
9. **The `.f3d` flag bits.** *Recommended:* define them now. Bit 0 is must-understand. Bit 1 is safe-to-copy: a writer that changed the model's tables drops an unknown section without it. Bits 2–15 are ignorable. Bits 16–31 are must-understand-if-set, so a reader refuses a known section that has an unknown high bit. *Alternative:* leave them undefined and require a version bump for any flag that changes meaning.
10. **Nested unknown keys.** *Recommended:* narrow CONTRACTS:347-348 to "top-level keys, and the nested objects of a level". Extend `FormatDocument` with a nested `unknown` only for pipeline nodes and plugin sections, the two an editor rewrites. *Alternative:* keep the sentence as is and make every document keep nested unknowns before rc.1, which is several days of work across about 10 readers.
11. **Platform channels: move `pad_input` and `flutter3d_pointer_lock` to 1.0 and rename `flutter3d/cloud_saves` to `dev.flutter3d/cloud_saves` now?** *Recommended:* yes to the rename. Keep the two plugins at 0.x with the `^0.5.0` pin, catch `MissingPluginException` on every method call now, and add a native-source test to `pad_input`. *Alternative:* both to 1.0.0, so their channels are under the same promise as the game that pins them.
12. **WebRTC channel layout.** *Recommended:* two data channels (reliable-ordered and unreliable-unordered) plus versioned signalling, before rc.1. *Alternative:* one ordered reliable channel, and document `PeerSend.reliable: false` as best effort over WebRTC.
13. **A committed native snapshot.** *Recommended:* yes. f32 and f64 bytes of a world with a vehicle and a multibody, restored and stepped to a recorded digest, listed in `versionedFormats`, and `sharedSceneHash`'s failure message changed to "do not update". *Alternative:* rely on `since_minor` and the fuzzers, and accept that a field reorder is caught only by review.
14. **Unknown fields inside component rows, now or in 1.x?** *Recommended:* now, while there are no 1.0 saves. Each row keeps the keys its codec did not read and writes them back, through a default member on the codec base that keeps unread keys. *Alternative:* 1.1, accepting that saves written by 1.0.x lose 1.1 fields.
15. **Should a replay refuse on the full `simulationVersion`, and should `InputTapePlayback` check it itself?** *Recommended:* yes to both. Record `simulationVersion` by default, check against it rather than `simulationBase`, have the playback take the `Demo`, and give tests a named raw-tape constructor. *Alternative:* keep the base check, and document that plugin and subsystem bumps are the game's to put in its `buildStamp`.
16. **Should a save without `requires` still restore once 1.0 ships?** *Recommended:* yes. Fix finding 24 before rc.1 and treat a 1.0 save as complete. Saves from rc builds are read as they are, with no migration. *Alternative:* bump `f3d.save` to v2 when the fix lands, and refuse a v1 save holding a non-engine part, naming the part.
