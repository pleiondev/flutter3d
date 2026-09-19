# The asset pipeline — the first tooling track's plan

Compiled 2026-09-11. Grounded in the owner's own 2026-09-11 decisions
following the tooling gap analysis (16 questions, answers in §3) and the
ROADMAP's "Assets that build themselves" section. Everything said about the
code was checked against the tree on the `modeler` branch the same day.

Notation — as in [model-editor-plan.md](model-editor-plan.md): **size** —
how big for one person (S up to a week, M two to three, L a month or more);
**⚙** — an engine change; **⇢ X** — an item absorbs item X from another
plan, whose id stays for reference. Packages: `build` = the new
`flutter3d_build`, `formats` = `flutter3d_formats`, `engine` = `flutter3d`,
`impeller` = `flutter3d_impeller`, `template` = `apps/flutter3d_template_app`.

---

## 1. In short

1. **The goal.** A new project reaches its first frame with a textured model
   through: `flutter create`, `flutter pub add flutter3d`, `dart run
   flutter3d:init`, `flutter run`. Not one manual script — no shader build,
   no converter.
2. **The mechanism is a build hook, not a separate step.** The hook converts
   source models into `.f3d`, compresses textures into KTX2 with mip chains,
   and assembles the shader bundle. The same code is also available as
   `dart run flutter3d:convert`.
3. **There are no data assets on stable.** In Flutter 3.47, hooks are on by
   default on stable, but `dartDataAssets` is only available on master
   (`flutter_tools/lib/src/features.dart`). So the hook writes to a
   generated directory listed in the pubspec; spike ap-00 confirms this on
   four platforms before anything is built on top of it.
4. **A hook is Dart with no Flutter.** Everything it calls lives in packages
   with no Flutter SDK. The decoders are already there (`formats`); the KTX2
   container and the ETC1S transcoder are still in the engine and are moving
   (ap-01).
5. **Timing.** 12 S items and 3 M items. Summed at the upper bound, ≈ 19.5
   weeks for one person. The critical path with parallel tracks is ≈ 10
   weeks (§4.2). The ROADMAP already admits the quarter is overbooked; this
   track is the one that survives a cut.

---

## 2. What exists today

| What | Where | State |
|---|---|---|
| A `.f3d` converter | `packages/flutter3d/tool/convert_asset.dart` | glTF/GLB/OBJ → `.f3d`, one option, `-o`. Lives under `tool/`, so `dart run` from another project can't find it |
| A container writer | `F3dWriter` in `formats` | exists, no Flutter |
| Document comparison | `document_compare.dart` in `formats` | exists — the basis for a "converted equals original" acceptance check |
| Reading KTX2, the ETC1S transcoder | `packages/flutter3d/lib/src/engine/assets/ktx2/` | exists, **in a package with the Flutter SDK** |
| A texture encoder | — | none; a ROADMAP item, `fmt-22` and `mat-30` in the modeler plan |
| The Impeller shader bundle | `dart run flutter3d_impeller:build_shaders` → `tool/build_shaders.sh` | a manual step; it's in the quickstart and once broke a macOS build |
| GLSL for WebGL2/WebGPU | `flutter3d_webgl/tool/generate_shaders.dart` | generated in the repo and committed; not needed in the hook |
| Model loading | `decodeModelInIsolate` + `BundleAssetSource` | by asset path, format by extension or magic bytes |
| The app template | `apps/flutter3d_template_app` | template models and textures declared as `assets/levels/`, `assets/models/` directories |
| A hook bundle assembler | `flutter_gpu_shaders` 0.5.2 on pub.dev | exists, depends on `hooks` ^2.0 and `data_assets` ^0.20 |

---

## 3. The decisions this plan is built on

Made by the owner on 2026-09-11.

| Question | Decision |
|---|---|
| A hook or a CLI | **Both, on the same code**: a hook from `init`, a CLI `flutter3d:convert` |
| Texture compression | **In this track**, KTX2 with full mip chains |
| Hot reload for models and textures | Yes, but **a separate, later track** ("The editors reach the running game") — it builds on this one's output |
| Prefabs | On top of level documents, **outside this track** |
| A scene format | No new one is introduced |
| Cloud conversion | No: encoding happens on the machine doing the build |

---

## 4. Items

### 4.1 Table

| id | What | package | size | depends | acceptance |
|---|---|---|---|---|---|
| ap-00 | **Spike: a hook on stable.** A package hook writes into its own `flutter3d_generated/`, listed in the pubspec; the same output from an app's own hook lands in that app's own tree. Checked on macOS, in-browser, on Android and iOS: did the file land in the bundle, cold and warm build time, behavior after `flutter clean`, a shared pub cache across two projects on different Flutter versions (an engine stamp on the output) | a spike under `tool/` | S | — | a "platform × approach → in bundle / time" table in §5 of this file; the chosen approach is recorded in ap-05 |
| ap-01 ⚙ | **KTX2 below Flutter.** The KTX2 container, format, and ETC1S transcoder move from `engine` to `formats`; `flutter3d` re-exports; outside imports don't change | formats, engine | S | — | `dart test` in `formats` with no Flutter SDK passes on KTX2 fixtures; the layer scanner is green; `flutter3d`'s public API is unchanged |
| ap-02 | **The `flutter3d_build` skeleton.** Flat Dart (`hooks`, `formats`, `geometry`), `resolution: workspace`, a barrel, registered in the workspace, in `flatDartPackages`, in the publishing order and the package table; package counts in README and ARCHITECTURE in the same commit | build | S | — | the scanner and `publish_check.sh` are green with the package; `dart pub get` in the package with no Flutter SDK |
| ap-03 | **`dart run flutter3d:convert`.** Converter code moves from `engine/tool/` into `build/lib`; a thin wrapper at `flutter3d/bin/convert.dart`; options `-o`, a directory as input, `--textures auto\|bc\|etc2\|none`, `--no-mips`. The old `tool/convert_asset.dart` is deleted in the same commit | build, engine | S | ap-02 | from another project, `dart run flutter3d:convert assets_src/Box.glb` writes a `.f3d` that loads with no warnings; `--help` describes every option |
| ap-04 | **A manifest and directory convention.** With no manifest: everything under `assets_src/` → `flutter3d_generated/` at the same relative path. With `flutter3d_assets.yaml`: glob-based rules (textures, mips, OBJ normals, exclusions). A manifest error names a line number | build | S | ap-02 | an empty project builds with no manifest; an unknown key and an invalid glob name the line |
| ap-05 | **The `buildAssets(input, output)` hook.** Walks the sources, converts via ap-03, writes to wherever ap-00 decided, stamps the output with the format and engine version, declares dependencies so Flutter reruns the hook when a source changes; a content-hash cache | build | M | ap-00, ap-03, ap-04 | a second build with no changes converts nothing (a counter in the hook's log); changing one `.glb` rebuilds exactly that file; a stamp from a different engine version triggers a rebuild |
| ap-06 ⚙ | **Shaders from a hook.** A dedicated `hook/build.dart` in `impeller` assembles the bundle during the app build (via `flutter_gpu_shaders` or a direct `impellerc` call — ap-00 decides); `build_shaders` stays as the manual path for engine development | impeller | M | ap-00 | a macOS build of the template with no script call draws a frame; the CI step for manually building the bundle for the examples is removed and stays green |
| ap-07 ⚙ | **A `Ktx2Writer` and BC1/BC3/ETC2 encoders in Dart.** ⇢ fmt-22, mat-30 (one implementation) | formats | M | ap-01 | PSNR ≥ 30 dB on the Khronos set via a test unpacker; a file from the encoder passes read conformance on every backend; time on 2048² is recorded |
| ap-08 | **A mip chain.** Linear space for sRGB textures, a Kaiser filter, renormalizing normal maps at each level; coverage-preserving alpha for alpha-test | formats | S | ap-07 | a golden frame on the CPU backend with a distant model differs from the frame with no mips by less than the noise threshold; normals on mips are unit length |
| ap-09 | **A per-target compression family.** Desktop — BC; Android and iOS — ETC2; web — both sets, chosen at load time from context extensions; PNG as a fallback when the context reads neither | build, engine | S | ap-05, ap-08 | a build for each target contains only the needed family; a web demo on a phone and on a laptop loads different files, and the console says which |
| ap-10 | **`dart run flutter3d:init`.** Writes `hook/build.dart`, the assets line in the pubspec, a `.gitignore` for the generated directory, a dev dependency on `flutter3d_build`; running it again changes nothing; `--check` reports mismatches; a hand-edited hook is not overwritten without `--force` | build, engine | S | ap-05 | a clean `flutter create` + `init` + `flutter run` draws the model; a second `init` is an empty diff |
| ap-11 ⚙ | **Loading by source path.** `loadModelAsset('assets_src/chair.glb')` reads the generated `.f3d`; in debug with no generated file it decodes the source and warns once, in release it errors with a hint about `init` | engine | S | ap-05 | a test with a bundle fixture covers both paths; the warning doesn't repeat every frame |
| ap-12 | **The template and four demos on the pipeline.** Template and game models/textures live as sources under `assets_src/`, generated output is not committed | template, apps | S | ap-09, ap-10, ap-11 | each game's web-build size before and after is recorded in the CHANGELOG; game golden frames are unchanged |
| ap-13 | **CI and measurements.** The template builds via the hook on macOS, in-browser, on Android and iOS; "converted equals original" via `document_compare` on the Khronos set; a second build converts nothing; install-to-first-frame is re-measured with the script from the Measurement section | tool | S | ap-06, ap-12 | four green jobs; the measured number is published alongside the prior one |
| ap-14 | **Documentation.** An "Assets" page on the site (sources, the manifest, families, the CLI, what to do on a hook error); a quickstart with no shader step; package READMEs; the CHANGELOG; test and package counts under the "says N" rule | site, docs | S | ap-13 | `tool/structure.dart` is green; the quickstart works end to end on a clean machine following the page's own text |

### 4.2 Order and the critical path

Two tracks run in parallel and meet at ap-09:

- **Build:** ap-00 → ap-02 → ap-03 → ap-04 → ap-05 — 4 S + M ≈ 6.5 weeks at
  the upper bound; ap-06 branches off right after ap-00.
- **Textures:** ap-01 → ap-07 → ap-08 — 2 S + M ≈ 4.5 weeks; ready before
  ap-05.

Then ap-09 → ap-10 → ap-12 → ap-13 → ap-14 (ap-11 alongside ap-10). The
critical path is **ap-00, 02, 03, 04, 05, 09, 10, 12, 13, 14**: 9 S + M ≈
11.5 weeks at the upper bound, ≈ 10 at a four-day S. The total across every
item for a single person with no parallelism is 12 S + 3 M ≈ 19.5 weeks.

Items that hand off well to agents: ap-01 (a mechanical move under the
scanner), ap-07 and ap-08 (pure arithmetic with a numeric acceptance), and
ap-14; items that don't: ap-00 and ap-06, where the answer depends on
toolchain behavior on real devices.

---

## 5. Spike ap-00's result

Run 2026-09-12 on a real test Flutter application (`ap00_spike`, a full
`flutter create` project, not a flag or an assumption) — a `hook/build.dart`
depending only on `package:hooks` (not `package:data_assets`) writes
`flutter3d_generated/stamp.txt` inside `input.packageRoot` (the root of the
app that owns the hook), and `flutter3d_generated/` is declared as an
ordinary line under this same app's `flutter: assets:` — not one call to an
experimental API.

**The approach is confirmed on all four targets.** The table below shows
whether the file landed in the built bundle (checked by unpacking the actual
artifact, not by reading a log), a cold build (after `flutter clean`), and a
warm one (nothing changed):

| Platform | In the bundle | Cold build | Warm build (untouched) |
|---|---|---|---|
| macOS (`flutter build macos --debug`) | yes — `App.framework/.../flutter_assets/flutter3d_generated/stamp.txt` | 18.3 s (14.4 s right after `flutter clean`) | 7.5–7.8 s |
| Chrome/web (`flutter build web --release`) | yes — `build/web/assets/flutter3d_generated/stamp.txt` | 14.2 s | 13.5 s (the difference drowns in the JS/Wasm compilation itself — the hook's own contribution isn't separately visible) |
| Android (`flutter build apk --debug`, emulator `f3d probe`) | yes — `assets/flutter_assets/flutter3d_generated/stamp.txt` inside the `.apk`, actually checked by running on the emulator (a screenshot: the screen shows exactly what the hook wrote, via a real `rootBundle.loadString`, not just the file's presence) | 29.8 s | 4.2 s |
| iOS (`flutter build ios --debug --simulator`, simulator `iPhone 17`) | yes — `Runner.app/Frameworks/App.framework/flutter_assets/flutter3d_generated/stamp.txt` | 22.1 s | 8.7 s |

**The dependency-based cache works, and this was checked by changing
content, not just by build time.** The hook declares a source
(`output.addDependency`) on a real file (`assets_src/source.txt`, standing
in for a future `.glb`). Three states, all reproduced on macOS: (1) an
unchanged build — the stamp doesn't change at all, neither timestamp nor
content; (2) editing `hook/build.dart` itself with no real text change —
also doesn't rerun (the cache is content-exact, not by mtime or by "the file
was touched"); (3) editing `assets_src/source.txt` — the hook actually
reruns, `stamp.txt` picks up the new source content. Exactly what ap-05's
own acceptance asks for: "a second build with no changes converts nothing;
changing one `.glb` rebuilds exactly that file."

**`flutter clean` leaves no orphans.** It removes `.dart_tool` (where the
hooks_runner state lives) and `build/`; the next build honestly rebuilds
`stamp.txt` from scratch, no stale file, no stale cache.

**§7's shared-pub-cache hypothesis did not hold up, and the reason is the
hooks protocol itself, not luck.** A second, independent project was run on
a different Flutter/Dart version (via `fvm`, Flutter 3.47.2 / Dart 3.13.2 —
the primary one being 3.47.0 / 3.13.0) with the same `hook/build.dart` — it
built cleanly (after a `flutter clean` that cleared an entirely different
kind of artifact — absolute paths in generated Xcode configs that had been
copied along with the already-built project; a finding about the `cp -r`
step of the test methodology itself, not about hooks), produced its own
`stamp.txt`, distinct from the first project's, and didn't touch the other
one. **Why there is no risk in this exact architecture:** in the `hooks`
protocol, `input.packageRoot` always points to the package that OWNS the
running `hook/build.dart` — and `ap-10` writes this file into the
application ITSELF, not into `flutter3d_build`. So the hook's output always
lands in the application's own tree, never in
`~/.pub-cache/hosted/pub.dev/flutter3d_build-x.y.z/`, where it would be
shared across every project depending on that package version — §7's risk
describes a real danger under a different layout (output living inside a
dependency package), but it doesn't materialize under the one this plan
already chose ("Both, on the same code": `flutter3d_build` provides the
`buildAssets()` code, and a thin `hook/build.dart` in the application calls
it and owns its own `packageRoot`). **Consequence: the engine-version stamp
on the output is not a defense against a cache collision (none was needed)
— it's a separate ap-05 question, whether it's needed for FORMAT
compatibility (`.f3d`/KTX2 encoding could change between engine versions),
which ap-05 itself decides, not this spike.**

**A real finding, not anticipated in advance.** `package:data_assets`'s own
documentation (not only `dartDataAssets`'s absence on stable/beta in
`flutter_tools/lib/src/features.dart` — that file has exactly one entry,
`master: FeatureChannelSetting(available: true)`, with no `beta`/`stable`
entries at all) is directly marked "Status: Experimental" and lives under
the `labs.dart.dev` publisher; and the `hooks` package's own "manual assets"
example comments on an alternative path — smuggling arbitrary bytes through
as a `CodeAsset` with `DynamicLoadingBundled()` — with the line `// TODO:
Change to DataAsset once the Dart/Flutter SDK can consume it`. So the
package itself, not just this plan's outside observation, admits there is
no data-asset path on stable. The `CodeAsset` path is rejected for `ap-05`:
it's meant for a dynamic library read through `dart:ffi`, not through
`rootBundle` — a worse fit for a model or texture than an ordinary file in a
declared `assets:` directory, which already works and doesn't drag FFI in
where it has no business being.

**The chosen approach — recorded for `ap-05`:** a hook (`package:hooks`,
no `package:data_assets`) writes ordinary files into `flutter3d_generated/`
inside the application's `input.packageRoot`; that directory is declared as
`flutter: assets:` in the application's `pubspec.yaml` (written by `ap-10`);
rebuild caching goes through `output.addDependency` on each real source
file, not on the hook script itself. Works the same way on all four targets
with no platform-specific code.

**What wasn't checked, honestly:** none of the four simulators/emulators is
"a real phone" (the same caveat `wg-00`/`rp-00` carried through the whole
prior session) — but this is the same environment already used there for
similar measurements, not a lowered effort. The spike's test Flutter app
(`ap00_spike`) isn't left in the tree: its shape — a full `flutter create`
with generated `macos/`/`ios/`/`android/`/`web/` directories — doesn't match
the already-accepted shape of spikes under `tool/` (`webgpu_spike` is a flat
Dart package with no platform directories); the spike's value is in the
result recorded here, not in a one-off harness that will go stale along
with the Flutter SDK version it was generated against. No real `.glb`/KTX2
converter ran here — only a placeholder text file; the real converter's
running time on real assets is a question for `ap-05`/`ap-07`, not this
spike.

---

## 6. Open questions — before ap-02 starts

1. **A separate `flutter3d_build` package, or hook helpers inside
   `formats`.** The plan assumes a separate package: `formats` then doesn't
   drag `hooks` into every app that only needs a decoder. The cost is one
   more package in the set.
2. **`assets_src/` alongside `assets/`, or sources right inside `assets/`.**
   The plan assumes a separate directory: source `.glb` files don't end up
   in the bundle next to their own `.f3d` output.
3. **Web: both families, or Basis ETC1S.** Both sets mean twice as many
   files on the server, but it works now; Basis is one file, but that's
   `fmt-23`, an L-sized item and a "port / FFI / server" decision.
4. **ASTC in this track or later.** iOS and modern Android read ASTC better
   than ETC2 quality-wise, but the encoder is more complex; the plan settles
   on ETC2 and defers ASTC.

---

## 7. Risks

- **A hook on stable behaves differently across platforms.** That's why
  ap-00 runs first, with a table rather than an opinion — resolved: the
  table in §5 is the same across all four targets.
- **Writing into a package directory inside the pub cache.** ~~Works, but
  one cache shared by several projects on different Flutter versions would
  produce someone else's bundle~~ — not confirmed by spike ap-00 (§5): the
  hook's output lands in the `input.packageRoot` of the app that owns
  `hook/build.dart` (written by `ap-10`, into the app itself), not into
  `flutter3d_build`'s own directory inside `~/.pub-cache` — there's simply
  nothing shared to write there. Checked with two projects on different
  Flutter versions (`fvm`) with no cross-influence. The engine stamp on the
  output stays an `ap-05` question, but for a different reason — `.f3d`/KTX2
  format compatibility across engine versions, not cache-collision defense.
- **Dart encoder speed.** If encoding 2048² in BC takes longer than a few
  seconds, a warm build becomes slow; ap-05's cache makes this a one-time
  build cost rather than a per-build one, but the measurement in ap-07
  decides whether an isolate per texture is needed.
- **The quarter is overbooked.** This track was added to *Committed* with
  nothing removed to make room; the September 28 review decides what drops.

---

## 8. What builds on this track next

- **Hot reload for models and textures in a running game** takes ap-05's
  output and ap-11's path: a saved file gets rebuilt by the hook's own code
  and swapped in through the VM service.
- **The models.pleion.dev cloud** can serve an already-compressed `.f3d`
  built by the same `flutter3d_build` on a server — the service already
  reads models package-side with no Flutter today.
- **The modeler** exports into a project's `assets_src/`, and the hook does
  the rest.

---

## 9. Item outcomes

As items close — in the same format `doc/tooling-plan.md` already uses for
its own items: what got built, what was honestly left undone, what the
tests showed.

### ap-02: the `flutter3d_build` skeleton — closed

Closed 2026-09-12. A new flat Dart package
(`packages/flutter3d_build/pubspec.yaml`) — `flutter3d_formats` and
`flutter3d_geometry` (the decoders the `ap-03` converter will use) and
`package:hooks` (the contract `ap-00`'s spike already checked on all four
targets — not `package:data_assets`, which `ap-00` itself rejected as
experimental). The barrel (`lib/flutter3d_build.dart`) exports nothing yet —
that's exactly what "skeleton" means in the item's own wording: the package
exists, resolves, and the next code (`buildAssets()`, the converter) lands
in it via items `ap-03`–`ap-05`.

Registered in the workspace, added to `flatDartPackages`
(`tool/structure/repository.dart`) with a justification (the same reason
class as `flutter3d_sim`/`flutter3d_net`: `hook/build.dart` is a separate
process with no window and no resolvable Flutter SDK, not a heavier hook),
into ARCHITECTURE.md's publishing order (the third tier, right after
`flutter3d_formats`, its only dependency outside the first tier). Package
counts in ARCHITECTURE.md/README.md/the site (38 → 39) were resynced —
`dart run tool/structure.dart` names exactly where, with no guessing.

**A real finding along the way, not part of the item's own wording:
`tool/publish_check.sh` was already red before this task.** Four packages
that appeared earlier in this same session (`flutter3d_net`,
`flutter3d_net_webrtc`, `flutter3d_sim_mcp`, `flutter3d_render_mcp`) carried
no `LICENSE` file of their own — `dart pub publish --dry-run` called this an
error, not a warning, and the script already exited non-zero before
`flutter3d_build` existed. Since a new package is required to keep
`publish_check.sh` green "for itself," it was cheaper and more honest to
close the same class of gap for all five at once than to add a `LICENSE`
copy only to the new package and stay silent about the other four — they
each got one too, along with `README.md`/`CHANGELOG.md`, also missing (the
same `dart pub publish --dry-run` called those out as a separate warning,
which would also have kept the script from being "green"). Also found and
removed: `packages/flutter3d_xr/` — an empty, git-untracked directory
holding a build cache from some earlier, abandoned experiment; it was never
listed in the workspace, but `publish_check.sh`'s `for dir in packages/*/`
picked it up blindly and failed on a missing `pubspec.yaml`, not on an
actual package check.

Checked: `dart pub get` and `dart analyze` in `flutter3d_build` — clean,
with no Flutter on the resolution path (the same sense already given by "a
flat Dart package resolves without the Flutter SDK" — a static dependency-
graph check, not literally removing Flutter from the machine).
`bash tool/publish_check.sh` — `exit 0`, every package `ready`, including
the new one. `dart run tool/structure.dart` — 32/32.

Not done, and not meant to be: the hook's actual logic (`buildAssets()`, the
converter) — `ap-03`–`ap-05`, the next items. Separately, honestly noted —
not something a rule checks, but noticed along the way: the prose numbers
"Thirty-three packages"/"twenty-seven"/"twenty-five" in ARCHITECTURE.md §3
and README.md stay whatever they were before this session (no structural
rule reads them) — already stale before `ap-02`, along with four packages
added earlier in this same session that also never made it in; left
untouched here deliberately, so as not to guess at numbers nothing checks,
not because the task judged them correct.

### ap-03: `dart run flutter3d:convert` — closed

Closed 2026-09-12. The converter code
(`packages/flutter3d/tool/convert_asset.dart` and
`convert_asset_options.dart`) moved into
`flutter3d_build/lib/src/convert.dart`; a thin wrapper —
`packages/flutter3d/bin/convert.dart` (`import
'package:flutter3d_build/flutter3d_build.dart'; ... exitCode = await
runConvert(arguments);` — exactly what the wording asks for). `flutter3d_build`
was added to `dependencies:` (not `dev_dependencies:`) of `flutter3d`
itself: `dart run flutter3d:convert` is called from another project, not
from inside this repository, so only an ordinary dependency needs to travel
with the published archive. The old
`tool/convert_asset.dart`/`convert_asset_options.dart` were removed in the
same commit; every real mention of the old path in doc comments, README,
the site, and one error message (`f3d_loader.dart`'s "Re-run
tool/convert_asset.dart" — the one place where the text was actually
exercised by a test, `f3d_test.dart` checked exactly that string) were
rewritten to `dart run flutter3d:convert`.

**Options beyond the original `-o`, as the wording asked.** A directory as
input — `ConvertOptions.parse` accepts a file or a directory; for a
directory, a recursive walk over `recognisedExtensions`
(`.obj`/`.gltf`/`.glb`/`.stl`), with `-o` in that case being a destination
directory mirroring the sources' relative paths, and with no `-o`, a `.f3d`
next to each source file, the same rule already used for a single file.
`--textures auto|bc|etc2|none` — `TextureFamily`, a `final class` with
`const` instances, not an `enum`: the plan itself already names a fifth
candidate (ASTC) as deferred rather than rejected, meaning the set grows
rather than closes forever — exactly the distinction the "an enum in a
published package is machinery or is not an enum" rule asks to be made.
`--no-mips` — a boolean flag.

**Honestly, not silently: neither new flag has any effect on the output
today, and the tool says so itself rather than pretending.** There is no
texture encoder yet (`ap-07`), no mip-chain generator yet (`ap-08`) —
`F3dWriter` today writes images as-is, with no re-encoding of any kind,
whatever `--textures` value is given. Every call with `--textures` set to
anything but `none` prints `note: --textures <value> accepted, no encoder
yet (ap-07) — textures pass through unencoded`; `--no-mips` prints a similar
line about `ap-08`. `--textures none` prints nothing, because there's
nothing to warn about — it's the only value whose behavior already honestly
matches what it promises.

**A real finding along the way: using `flutter3d_samples` as a fixture for
`flutter3d_build`'s own tests would have broken the very thing the package
is meant to solve.** `flutter3d_samples`'s pubspec carries `flutter: sdk:
flutter` for its own `flutter.assets:`; an ordinary `dev_dependency` on it
(the way `flutter3d`/other packages already do) would have dragged the
Flutter SDK right back into `flutter3d_build`'s own dependency graph — the
whole point of this item (and `ap-00`'s spike before it) is to keep that
graph flat. `dart run tool/structure.dart` caught this immediately ("a flat
Dart package resolves without the Flutter SDK", path
`flutter3d_build -> flutter3d_samples`) — the tests use their own,
hand-written minimal OBJ triangle (`test/fixtures/triangle.obj`) instead of
`flutter3d_samples`'s real models.

**A second finding, in the same vein: the converter uses `Stopwatch` to
time itself for the CLI output, and this was the first time that code fell
under the "a step reaches for no clock and no loose dice" rule's scan.** The
old file lived under `tool/` (outside `lib/`) and was never scanned; moving
it into `flutter3d_build/lib/src/` made the code visible to the rule for the
first time. An exception entry was added to `notARepeatableStep` —
`flutter3d_build`: "a build-time tool, not a step," the same reason class
`flutter3d_sim`'s own `step_time_trace.dart` already carries (a profiler
observing a step from outside, not a step itself).

Thirteen tests in `flutter3d_build/test/convert_test.dart`: `--help` and no
arguments print usage rather than crashing; a single file converts and
round-trips against its own source; with no `-o`, the result lands next to
the source; a directory converts everything recognizable recursively and
leaves the unrecognized alone; a directory with `-o` mirrors relative
paths; an unknown `--textures` value is a usage error, not a crash; both
honest warnings print, and don't print, exactly where they should; a
missing file names the path rather than throwing a stack trace; an already-
`.f3d` file refuses to convert again.

**Acceptance checked literally, by a second process from a neighboring
project, not only by a unit test.** From `apps/flutter3d_editor` (a real
project depending on `flutter3d` as an ordinary package, not from inside
`packages/flutter3d`) — `dart run flutter3d:convert /tmp/…triangle.obj -o
/tmp/…triangle.f3d` really resolved by the package's own name, really wrote
the file, `dart run flutter3d:convert --help` really printed the
description of every option. Full test suites for `flutter3d` (995),
`flutter3d_formats` (188), `flutter3d_build` (13) — all green.
`bash tool/publish_check.sh` — `exit 0`. `dart run tool/structure.dart` —
32/32.

Not done, honestly: actually converting textures/mip chains
(`ap-07`/`ap-08`, the next items) — the CLI accepts and validates flags for
them, but doesn't execute them; a call from the hook (`ap-05`) — this is the
same function the hook will call, but the hook itself isn't written yet.

### ap-04: a manifest and directory convention — closed

Closed 2026-09-12. Two new files in `flutter3d_build`:
`lib/src/layout.dart` (`AssetLayout`, the default convention) and
`lib/src/manifest.dart` (`AssetManifest`, the optional
`flutter3d_assets.yaml`) — both tested independently of `ap-05`'s hook,
which doesn't exist yet: planning ("what to convert and where") and actual
execution are two different questions, and this item answers only the
first.

**With no manifest.** `AssetLayout.plan()` walks `assets_src/` (if the
directory doesn't exist at all, an empty plan, no error at all — this is
what "an empty project builds with no manifest" from the acceptance means
— not through `flutter build`, which has nowhere to come from without
`ap-05`, but through the same method the hook will later call) and returns,
for every recognized file, a path in `flutter3d_generated/` at the same
relative path with the extension replaced by `.f3d` — exactly the
convention `ap-00`'s spike already checked on all four platforms for an
`assets:` directory.

**With a manifest.** `flutter3d_assets.yaml` is a list of rules, each a
glob plus what it overrides: `textures` (`TextureFamily` from `ap-03`),
`mips` (bool), `objNormals` (the same `enum ObjNormals` from
`flutter3d_formats` — a closed decoder set, hence an `enum` rather than a
`final class`, unlike `TextureFamily`), `exclude`. The last matching rule
wins, not the first — a broad rule on top, a narrow exclusion below it, the
same reading order as a `.gitignore`-style overlay.

**A manifest error names a line, as the acceptance asked.**
`AssetManifest.parse` reads not a bare `Map` via `loadYaml`, but a node tree
via `loadYamlNode` (`package:yaml`), and keeps each `YamlNode`'s `span` at
every check — an unknown top-level key, an unknown key inside a rule, a
syntactically invalid glob, a rule with no required `glob`, a wrong value
type (`textures: solid` instead of one of `auto|bc|etc2|none`, `mips: "yes"`
instead of a boolean) — each names its line through
`ManifestFormatException.toString()`, formatted as
`flutter3d_assets.yaml:N: message`, which an editor picks up like an
ordinary compiler error.

**A real finding, caught by a test rather than anticipated: `"**/*.obj"`
doesn't match a file at the root of `assets_src/`.** `package:glob`'s own
rule for `**/` requires at least one path segment before the asterisk; a
manifest written by someone with the intuition "just add `**/` to catch
everything" silently fails to do so for a project with no subfolder at all
inside `assets_src/`. Documented in `manifest.dart`'s own doc comment and
pinned down by a dedicated test (`"**.obj"` with no slash matches both the
root and subfolders — also checked, not just claimed).

Twenty tests: eleven in `manifest_test.dart` (an empty file, an empty
`rules: []`, one glob, all four options at once, the last rule wins, the
`**/` finding, and one per error class — an unknown top-level key and an
unknown key inside a rule, a broken glob, an unknown `textures` value, a
rule with no `glob`, `rules` as a non-list, syntactically broken YAML — with
an exact line number in each case except the YAML parser's own inherent
syntax errors); nine in `layout_test.dart` (an empty project;
`assets_src/` with no recognizable files; the default convention for a
top-level and a nested file; a rule-based exclusion; a rule travels with
the plan; a broken manifest surfaces through `AssetLayout` too). The full
`flutter3d_build` suite — 32 tests, all green. `dart run tool/structure.dart`
— 32/32.

Not done, and not meant to be here: calling `AssetLayout.plan()` from the
hook — `ap-05`, the next item; converting the files the plan named —
`ap-03` already does this file-by-file and directory-by-directory, `ap-05`
brings the two together.

### ap-05: the `buildAssets(input, output)` hook — closed

Closed 2026-09-12. `flutter3d_build/lib/src/build_assets.dart` —
`buildAssets(BuildInput input, BuildOutputBuilder output)`, exactly the
signature `package:hooks`'s own `build()` calls (actually checked by
reading the `hooks-2.0.2` sources from `~/.pub-cache`, not assumed from
documentation). The real logic lives in `runAssetBuild(Directory
projectRoot, {IOSink? log})`, which `buildAssets` simply wraps: planning
("what and where" — `ap-04`) and execution ("convert or skip" — this item)
are two separate functions precisely because the first was already testable
with no hook at all by `ap-04`, and the second can be tested the same way,
with no need to construct a `BuildInput` where it isn't needed.

**A content-hash cache, not a modification-time one.** For every file from
`AssetLayout.plan()`: a SHA-256 of the source bytes (`package:crypto`), the
format version (`kF3dVersion` from `flutter3d_formats`, already existing),
and the pipeline version (`kAssetPipelineVersion` — a new constant, the same
hand-written technique already giving `kF3dVersion`, applied to the pipeline
itself rather than the container: two different questions — "will this
build read this format version" and "has the tool that wrote it changed" —
hence two separate stamps, not one for both). The cache is JSON, sitting
next to the output in
`flutter3d_generated/.flutter3d_cache.json`; a broken or missing cache file
reads as empty (converts everything rather than crashing) — the same
conservative decision `AssetManifest`/`AssetLayout` already made for a
missing project.

**Both acceptance lines aren't just claimed — a test shows them with an
actual number.** "A second build with no changes converts nothing, a
counter in the log" — `runAssetBuild` writes `flutter3d_build: N converted,
M unchanged` to the log, and a test on two real sources checks exactly the
string `0 converted, 2 unchanged` after the second call. "Changing one
`.glb` rebuilds exactly that file" — a test with two sources, one actually
rewritten with different vertices (not just a touched mtime), checks that
`converted` contains exactly the changed file's path and `skipped` contains
exactly the other one. "A stamp from a different engine version triggers a
rebuild" — checked twice, separately for `pipelineVersion` and for
`formatVersion`: the cache file is rewritten with a shifted number, and the
next call reconverts even though the source bytes never changed.

**Acceptance checked through real `package:hooks` objects, not stand-ins.**
`BuildInputBuilder().setupShared(packageRoot: ..., ...)` builds a real
`BuildInput` with an explicit `packageRoot` (the library's actual class, not
hand-rolled JSON), `buildAssets` is called directly,
`BuildOutput(output.json)` reads back what `output.dependencies.add(...)`
actually wrote. `package:hooks` itself offers `testBuildHook` for an
end-to-end check through a real `main`/`input.json` on disk — not chosen
here for a found, not anticipated, reason: `testBuildHook` hard-codes
`Directory.current.uri` as `packageRoot`, and swapping the global working
directory for the duration of one test really broke five other tests in
`convert_test.dart`, because `dart test` runs a file's tests in one process
where the current directory is shared across every isolate, not per-
isolate. Found by running the package's full suite, not guessed —
`BuildInputBuilder`'s own explicit `packageRoot` parameter (the same real
class `testBuildHook` itself uses internally) gives the same honesty with
none of that risk.

**A real finding along the way, caught by this same test.**
`input.packageRoot` is a directory `Uri`, so its own path ends in `/`;
`Directory.fromUri(...).path` doesn't strip that slash, and every path built
from it (the cache file, the logged conversion line, a declared dependency)
would carry a doubled slash — harmless for the OS, but not for string
comparison, and not for cache keys staying the same string across calls.
Fixed — `buildAssets` trims `packageRoot`'s trailing slash before building
an `AssetLayout` from it.

Twenty tests: eleven in `build_assets_test.dart` (an empty project; a fresh
source converts once; both acceptance lines verbatim; a vanished conversion
result is rebuilt even when the cache agrees; both version stamps
separately; every planned source is a declared dependency whether it's
converted or skipped; a broken cache file isn't fatal) and one in
`build_hook_test.dart` (real `package:hooks` objects, described above). The
full `flutter3d_build` suite — 42 tests, three runs in a row with no
flakiness. `dart run tool/structure.dart` — 32/32.

Not done, honestly: actually calling `buildAssets` from a real
`hook/build.dart` inside a real `flutter build` — that's `ap-10`, which
doesn't yet write that file into a project; an end-to-end check via
`testBuildHook`/a real `flutter build` on all four platforms — `ap-00`'s
spike already did this for the hook mechanism itself, and repeating the
same thing here for the same mechanism with a different payload would be
duplication, not new evidence — traded for a test that lives safely
alongside the other forty-one in the same package.

### ap-06: the shader hook — closed, except one honestly named line

Closed 2026-09-12. `packages/flutter3d_impeller/hook/build.dart` — a real
hook, calling `impellerc` directly (not `package:flutter_gpu_shaders`, which
depends on the experimental `package:data_assets` already rejected by
`ap-00`). Narrower than `tool/build_shaders.sh` on purpose: no
`--package-include`, no manifest discovery, no binding table for engine
development — only `flutter3d_impeller`'s own canonical bundle, the one
whose names `LightingModel` already knows by heart. The manual script stays
exactly what it was, for the broader needs of engine development.

**The real logic isn't in the hook itself.**
`lib/src/shader_bundle_build.dart`'s `buildShaderBundle(packageRoot: ...)`
is a testable function with no `BuildInput` anywhere in its signature, the
same split `ap-05`'s `runAssetBuild`/`buildAssets` already established.
`hook/build.dart` is a thin wrapper under `package:hooks`'s own `build()`; a
new `bin/build_shader_bundle.dart` is a second caller, for a reason found
along the way, not anticipated in advance (see below).

**Proven on a real build, not on a unit test with stand-ins.** The bundle
was removed from `packages/flutter3d_impeller/assets/shaders/`, `flutter
build macos --debug` for `apps/flutter3d_demo_dungeon` was actually run —
the hook fired on its own, the bundle reappeared (1.1 MB, a fresh
timestamp), the app built. With that same bundle, that same run —
`bash packages/flutter3d_impeller/tool/conformance.sh` (real GPU, real
Impeller/Metal) answers **35 passed, 0 failed, 0 declined**: not just
"it built," but the whole backend contract passing on a bundle the hook
wrote, not a person.

**Real finding #1: `Platform.resolvedExecutable` isn't what it looked
like.** Checked with `flutter build macos -v` on a throwaway project: inside
the hook this is `<flutter_root>/bin/cache/dart-sdk/bin/dart`, and
`$FLUTTER_ROOT` is `null` (hooks don't inherit it, so
`build_shaders.sh`'s own fallback path, `flutter --version --machine`, has
nowhere to run from inside a hook). This function's own test found a second
form: `flutter test` runs code not under this Dart VM at all, but under
`flutter_tester` — a separate headless engine at a neighboring path inside
the same `bin/cache/artifacts/engine/`. Both forms are real, both are
checked, `_flutterSdkRoot()` handles both.

**Real finding #2: `Isolate.resolvePackageUri` is a working trick in
`bin/skills.dart`, but not inside `flutter_test`.** The first version of
`buildShaderBundle` resolved `flutter3d_shaders`'s directory this way — it
worked from a real hook and from `bin/`, but failed with `Unsupported
operation: Isolate.resolvePackageUriSync` specifically in the test
environment. Rewritten to read `.dart_tool/package_config.json` directly —
the same way `tool/package_root.dart` already resolves `flutter3d_shaders`
for `build_shaders.sh` itself — ported into the package rather than reused
directly (a `tool/` script isn't something a package can depend on). Works
in all three contexts at once: hook, `bin/`, test.

**Real finding #3, also the honest limit of one acceptance line.** "The
manual bundle-build CI step is removed" was checked literally: the bundle
was removed, `flutter analyze` in `flutter3d_impeller` returns `exit 1`,
`asset_does_not_exist` on `pubspec.yaml:96`. **`flutter analyze` doesn't run
build hooks at all** — hooks only fire on a real build, and a
`flutter.assets:` entry is required to exist on disk by the time analysis
runs. The only mechanism by which a hook could satisfy analysis with no
physical file — `package:data_assets` — is the very one `ap-00` rejected as
unstable. So "the step is removed, nothing replaces it" is, literally,
unreachable on the current stable toolchain — not an assumption, the result
of a direct check. Done instead: the CI step (`tool/ci.sh`, both halves of
`.github/workflows/ci.yml` — macOS and Android) was switched from
`./tool/build_shaders.sh` to a new, fast `dart run
bin/build_shader_bundle.dart`, calling the exact same function the hook
does — with no full app build, in seconds rather than `flutter build`'s own
time. The Android (Gradle) path was not empirically checked in this
environment the same way macOS was — an honest note was left in `ci.yml`
itself.

Two tests: `shader_bundle_build_test.dart`'s real call through a real
`impellerc` (not a mock) with real assertions on size and on the dependency
list; and (described above) the build + conformance run as a second, unit-
test-external pass. The full `flutter3d_impeller` suite — 161 tests, green.
`dart run tool/structure.dart` — 32/32.

Not done, honestly: literally "the CI step is removed with nothing
replacing it" is unreachable on the stable toolchain, for the reason named
above; the Android CI path isn't confirmed by a real build in this session,
only by the same honest bash-to-Dart move as macOS;
`packages/flutter3d/example`'s own separate bundle
(`example.shaderbundle.json`) is untouched, outside `ap-06`'s scope, which
names only `flutter3d_impeller`'s canonical bundle.

### ap-01: KTX2 below Flutter — closed

Closed 2026-09-12. `packages/flutter3d_formats/lib/src/ktx2/` — the KTX2
container (`ktx2_format.dart`), a loader (`ktx2_loader.dart`), and the ETC1S
transcoder (`basis_universal/`), moved from `flutter3d` verbatim, with one
signature change: `Ktx2Texture` here carries `vkFormat` (`int`, a Khronos
number) instead of `TextureFormat`. `flutter3d`'s own `ktx2/ktx2.dart`
shrank to a thin wrapper — `Ktx2Texture.parse` calls the container's own
parser and maps `vkFormat` to `TextureFormat` once, through `_engineFormat`
(moved unchanged, including the paired sRGB/UNorm handling and the error
message for an unknown `vkFormat`), plus `export ... show` for whatever
doesn't change between the layers (`Ktx2FormatException`, `VkFormat`,
`isKtx2File`, `isBasisUniversalKtx2`, and the byte constants).

**The real reason, not a guess.** `flutter3d_hardware` (where
`TextureFormat` lives) declares `flutter: sdk: flutter` in its own pubspec,
even though `formats.dart` itself doesn't import Flutter in a single line —
this isn't about a file, it's about the package resolution graph: any
package depending on `flutter3d_hardware` for even one enum inherits the
Flutter SDK at `dart pub get`, before a single line of source is read.
Exactly what `the flat Dart package resolves without the Flutter SDK` in
`tool/structure.dart` checks by walking the graph, not by grepping imports.
So the container and the `TextureFormat` mapping couldn't stay one class
without dragging Flutter into `flutter3d_formats` — the split into
`vkFormat`/`TextureFormat` wasn't a stylistic choice, it was the only way to
keep the acceptance criterion true.

**A side fact, found along the way rather than looked for:**
`flutter3d_formats` was already mentioned in `_flatDartResolvesWithoutFlutter`'s
own doc comment as an example package the rule exists for — but it wasn't
actually in the `flatDartPackages` map, so the rule simply never checked it.
Added now, with the justification named by this same plan item — KTX2 under
it is now exactly as guaranteed flat-Dart as `flutter3d_geometry` was from
the start.

**Tests are split along the same line as the code.**
`flutter3d_formats/test/ktx2_test.dart` (18 tests) holds everything about
the container — the header, the level index, key/value refusals,
`isKtx2File`, plus a new test confirming an unknown `vkFormat` is now
*accepted* at this layer (interpretation is the caller's job, alongside
`GraphicsDevice`). `flutter3d_formats/test/ktx2_etc1s_test.dart` (3 tests)
holds transcoding against `basisu`'s own real output — three `.ktx2` files
copied from `flutter3d_samples/assets/ktx2/` alongside the test, not
imported from there: `flutter3d_samples` itself declares `flutter: sdk:
flutter` for its own `flutter: assets:`, and adding it as a
`flutter3d_formats` dependency would have broken the very property this
whole item exists for. `flutter3d/test/ktx2_test.dart` shrank to two tests,
checking not the container but exactly what the wrapper adds: the sRGB/UNorm
pairing and the by-name refusal for an unknown `vkFormat`.
`helpers/build_ktx2.dart` exists in both `test/` folders as two independent
files with identical bodies — one package's `test/` cannot import another's,
and `flutter3d_formats` cannot depend on `flutter3d`, so there is no shared
place for it.

**`flutter3d`'s public API is unchanged** — checked, not just claimed:
`Ktx2Texture.parse`, the `pixelWidth`/`pixelHeight`/`format`/`levels`
fields, `Ktx2FormatException`, `isKtx2File`, `isBasisUniversalKtx2` — same
names, same signature, same import path. What did change is internal:
`flutter3d.dart` and three files that re-exported the whole of
`flutter3d_formats` (`animation.dart`, `material_loader.dart`, and
`flutter3d.dart` itself) now do so with `hide Ktx2Texture`, because
`flutter3d_formats` started naming its own container `Ktx2Texture` under
the same name. Found not by reasoning but by `flutter_analyze`:
`ambiguous_export` on `flutter3d.dart:71`, then again on a new line after
the first fix — both times from a re-export, not from direct use.

`dart test` in `flutter3d_formats` — 208 tests, green, with no Flutter SDK
(`dart pub get` in the package never resolves `flutter:`). `flutter
analyze` and `flutter test` in `flutter3d` — clean, the whole suite green.
`dart run tool/structure.dart` — 32/32, including the updated
`flatDartPackages` map. Test and package counts are synced under the "says
N" rule in `ARCHITECTURE.md`, `README.md`,
`site/content/quickstart.md`, `site/content/reference/testing.md`, and
`packages/flutter3d/README.md` — drift from concurrent sessions (an extra
`flutter3d_cloth` package missing a table row, four counters out of date)
was fixed in the same pass.

Not done, honestly: `flutter3d_model_core/lib/src/texture_info.dart` still
holds its own copy of the KTX2 constants, unrelated to this loader — its
doc comment used to cite the reason this item just eliminated ("that
loader lives in `flutter3d`, which needs the Flutter SDK" — no longer true,
`flutter3d_formats`'s version needs no SDK and this package already depends
on it), so the comment was rewritten to the real reason (the
`flutter3d_formats` loader throws on things the texture panel is required
to show as an icon, not silence), but the code itself wasn't switched to
reuse the other parser — a separate simplification, outside `ap-01`'s
scope.

### ap-07: a `Ktx2Writer` and BC1/BC3/ETC2 encoders in Dart — closed

Closed 2026-09-12. `packages/flutter3d_formats/lib/src/ktx2/encode/` —
`rgba8_image.dart` (`Rgba8Image`, the shared input for every encoder),
`bc1_encoder.dart`, `bc3_encoder.dart`, `etc2_encoder.dart`, and
`ktx2_writer.dart`. Public exports from `flutter3d_formats.dart`:
`Rgba8Image`, `encodeBc1`, `encodeBc3`, `encodeEtc2Rgb8`
(+`encodeEtc2Rgb8Block` for tests), `writeKtx2` — alongside
`Ktx2Texture`/`vkFormat`, which is what makes `writeKtx2 → Ktx2Texture.parse`
a real round trip inside one package, not just an agreement on paper.

**Format coverage, honestly named rather than implied.** BC1 — PCA over the
block's covariance (a power-iteration method, eight iterations), not a
bounding box: the two pixels farthest apart under projection onto the
principal axis become the palette endpoints, not the axis's own extremes
(which need not be the color of any real pixel). BC3 reuses BC1 for the
color half and always writes alpha in the eight-level mode (`a0 > a1`),
never the six-level mode with hard 0/255 — this block is for a soft alpha
edge, not a cutout. ETC2 RGB8 — only the ETC1-compatible subset (individual
and differential modes, per-block choice by error; flip is always 0, T/H/
planar aren't implemented) — real, not full, spec coverage, named in
`encodeEtc2Rgb8Block`'s own doc comment, not hidden. **ETC2 RGBA8 (EAC
alpha) isn't implemented at all** — the EAC format has no ground-truth point
checked against real hardware anywhere in this repository (unlike RGB8,
which `flutter3d_conformance`'s `checkCompressedTextureSamples` already
holds against real Metal/WebGL2), and guessing an 11-bit bit layout with no
such ground truth is exactly the kind of guessing `ktx2_format.dart`'s own
doc comment names as a reason to refuse loudly, not quietly. BC3 already
closes the "compressed format with alpha" case for desktop; ETC2 RGBA8
stays an open item, not a secretly skipped one.

**A real finding, not a guess: `flutter3d_hardware`'s own single-block check
code is not just an acceptance test but a table of ETC modifiers.**
`flutter3d_conformance/lib/src/compressed_checks.dart`'s
`checkCompressedTextureSamples` is the only place in the repository where
BC1's and ETC2's byte layout has already been checked against real Metal
and WebGL2 (its own doc comment: "every number checked against
flutter_gpu's, and not one block ever drawn" — before it existed). Its
`_bc1Solid()`/`_etc2Solid()` gave not just an example of a valid file but a
constant: `(msb=0, lsb=0)` under table 0 decodes to `+2`, which is what
fixed `_modifierTables[0] == [2, 8]` and the code direction `(0,0)→+table[0]`,
`(1,1)→−table[1]` in `etc2_encoder.dart` before a single test on an
arbitrary block was written.

**Three real bugs, each found by a test, not by reasoning.** (1) BC1:
`_orderEndpoints`, on equal packed endpoints, **decremented** `pack0`,
leaving `pack0 < pack1` — exactly the three-color-plus-transparent mode
this encoder is required to avoid; a test, "a solid block is stored as
four-color," caught it immediately, and the fix was `pack0 += 1` (with an
explicit case for `0xFFFF`, where there's nowhere to grow and `pack1` is
decremented instead). (2) ETC2: `_fitIndividual` scored the best modifier
table against the **4-bit** average (`(8, 4, 12)`) rather than the
**expanded 8-bit** base color (`(136, 68, 204)`) — the individual mode's
final error was inflated to 154304 instead of the real 192, which made the
differential mode win every time even where individual was more accurate.
Found not by reading the code but because a solid block stopped matching
`compressed_checks.dart`'s own bytes; the fix was to score the table against
the same expanded color already computed for the block's own bytes. (3) The
"four quadrants" test originally split the block by columns (left/right) —
exactly the cut (`flip = 1`) this encoder deliberately never tries; the test
was reporting not an encoder bug but its own unfitness for that shape —
rewritten to a row-wise split, the one `flip = 0` actually represents.

**PSNR, for real, on a Khronos file, not on homemade synthetics.**
`flutter3d_samples/assets/animated_cube/AnimatedCube_BaseColor.png`
(512×512, a real glTF-Sample-Models texture) was read via `package:image`
(a `dev_dependency`, pure Dart — checked by the same
`dart run tool/structure.dart` pass that checked `flutter3d_formats`
itself) and run through the encoder → a test unpacker
(`test/helpers/bc_test_decoders.dart`, `etc2_test_decoder.dart` — not
production code, none of it is exported). Result: **BC1 32.81 dB, BC3
32.81 dB (color; alpha is a separate synthetic ramp, since the file has no
alpha channel of its own), ETC2 RGB8 34.27 dB** — all three above `ap-07`'s
own 30 dB threshold. Encoding time for 2048×2048 (tiling the same file 4×4,
rather than vendoring a second asset for one number): **BC1 ≈ 510 ms, BC3
≈ 530 ms, ETC2 RGB8 ≈ 2.5 s** — ETC2 is noticeably slower from exhaustively
trying all eight tables for both modes (individual and differential) across
both halves of the block; a build-time tool, not a runtime path, so this
isn't a frame budget.

**Conformance on real hardware — WebGL2, not just the in-house unpacker.**
`packages/flutter3d_webgl/test/formats_encoder_conformance_test.dart`
(`@TestOn('browser')`, `flutter test --platform chrome`) encodes a real
two-block image (not a solid color — already covered by
`checkCompressedTextureSamples`) through
`encodeBc1`/`encodeBc3`/`encodeEtc2Rgb8`, loads it on a `WebGlDevice`, draws
it, and reads both blocks back through two real render passes in real
headless Chrome. The first run failed identically across all three formats
— not a coincidence, a sign the problem wasn't the codec: the test's own
vertex format was built as `pos.xyzw + color.rgba + uv` (10 floats per
vertex), while `ParticleVertex` expects `pos.xyz + color.rgba + uv` (9
floats) — a four-byte vertex-stride mismatch that
`checkCompressedTextureSamples`'s own `1, 1, 1, 0.5, 0.5` triples (nine
numbers, not ten) already showed line by line, had anyone recounted them.
After the fix — three for three, both blocks, all three formats, `flutter
analyze` on the package clean. **Impeller/Metal was not separately
empirically checked** in this session, the same honest gap as `ap-06`'s
Android path: WebGL2 is a real GPU and a real driver, but not the same
backend games actually draw with on desktop.

`dart test` in `flutter3d_formats` — 226 tests, green, with no Flutter SDK.
`flutter analyze`/`flutter test` in `flutter3d_webgl` — clean (plus three
new tests on real Chrome). `dart run tool/structure.dart` — the test-and-
package-count rule is green (6834 tests, 41 packages — the
`site/content/reference/testing.md` table and the numeral list in the rule
itself were updated in the same pass, including the word "forty-one," which
hadn't been in any numeral list before). The three remaining broken rules
(about the "mesh-overlay" golden scene, the publishing order for
`flutter3d_rig`, and `math.acos` in
`flutter3d_rig/lib/src/two_bone_ik.dart`) aren't from this session or this
plan item: `flutter3d_rig` is parallel work, untouched here.

Not done, honestly: ETC2 RGBA8 (EAC alpha) isn't implemented — see above;
ETC2's T/H/planar modes aren't implemented — a real, not imagined, quality
loss on blocks with a sharp single-color spot or a smooth diagonal gradient
that the individual/differential modes don't catch as well; `flip = 1`
(a column-wise cut) is never tried, only `flip = 0`; Impeller/Metal wasn't
empirically checked, only WebGL2.

### ap-08: a mip chain — closed by the letter of its acceptance

Closed 2026-09-13; this record was written on 2026-09-15, when the code and
both of its test files turned out to be in the tree already (since
`80c11976`) with no entry here. `packages/flutter3d_core/lib/src/formats/
ktx2/encode/mip_chain.dart`: `buildMipChain(base, {srgb, isNormalMap,
alphaTestThreshold})` builds the full chain from the base level down to 1×1,
each level a separate pass of a separable (rows, then columns) Kaiser filter
(`beta = 4`, three lobes) rather than a box average.

**Three kinds of channel, three filtering spaces — exactly what the row
asks for.** `srgb`: RGB is decoded to linear before the filter and encoded
back after, which avoids the textbook artefact (bytes 0 and 255 average to
128, where a linear-light average of black and white is about 188).
`isNormalMap`: R/G/B are read as vector components in `-1..1`, filtered as
vectors, and every output texel is renormalised to unit length — "at each
level", as `ap-08` asks, not only the first. `alphaTestThreshold`: alpha is
not filtered naively (which shrinks the share of texels above the threshold
at every level and visibly thins foliage with distance) but scaled by
Castaño's coverage-preserving technique — a binary search for the scale
around the threshold, since "the same coverage as the base level" is an
equation with no closed form.

**The acceptance is checked literally, but not with a scene.** The row asks
for "a golden frame on the CPU backend with a distant model differs from the
frame with no mips by less than the noise threshold";
`packages/flutter3d_cpu/test/mip_chain_quality_test.dart` gives that at the
level of texture sampling rather than a rendered scene, and its own doc
comment says why: a checkerboard (what "a frame with a model" would give)
averages to the same half wherever a sample lands, and would pass with no
real mip chain at all. The test builds a noise image (`Random(42)`) instead
and compares a point sample at `du = dv = 1.0` — the whole texture in one
texel, the furthest view there is — with the image's true average: with the
chain the difference is under 12 of 255 per channel, and without it
(`mipLevels` not handed to `createTextureFromPixels`) it is over the same
threshold on the same image, so the test proves "bad without" as well as
"good with". The second condition — "normals on mips are unit length" — is
`packages/flutter3d_core/test/formats/mip_chain_test.dart`'s `every level's
normals stay unit length`, at every level including 1×1, with `0.02` allowed
for byte rounding.

Not wired into the converter, then or now — and by decision rather than
by omission. The chain the converter writes (`gfx-69n`, `_encodeLevels` in
`packages/flutter3d_build/lib/src/texture_encode.dart`) is a box filter in the
channel's stored values, on purpose: a mip level is the value a bilinear tap
would have found had it read four texels at once, and averaging sRGB bytes as
they stand agrees with what the hardware does between levels, where a
gamma-correct average would disagree with it between levels 0 and 1.
`buildMipChain` stays what this item asked for — a tested function in
`flutter3d_core` — for a caller that wants renormalised normals or preserved
alpha coverage and uploads the levels itself.

### ap-09: a per-target compression family — closed by three other items, and by one flag here

The row was answered twice. On the `edu-track` branch (2026-09-15) by a
`BuildTarget` type and a `--target` flag on the converter, two output files
for the web (`chair.f3d`, `chair.etc2.f3d`), and a `preferredTextureFamily` in
`flutter3d_webgl` that read the context's extensions. In this tree by three
items of `doc/model-editor-plan.md`, which between them leave nothing for
that design to do, so it was not carried over:

- **The hook is told its target (`gfx-69n`).** `buildAssets` reads
  `input.config.code.targetOS` behind `buildCodeAssets`, and
  `familyForTargetOS` maps macOS, Windows and Linux to BC, Android and iOS to
  ETC2, and anything else — the web, or a build that names no target — to
  `auto`. A block format is a fact about the platform, not a guess about a
  device. The branch had concluded a hook *cannot* learn its platform, having
  ruled `package:code_assets` out; its three demos measured larger after
  moving onto the pipeline for exactly that reason (`ap-12`). A project's own
  word still wins, through `textures:` in its hook user defines.
- **One cooked file for every family (`gfx-83n`).** `TextureFamily.universal`
  is a 4×4 block intermediate, not a GPU format; the upload turns it into BC,
  ASTC, ETC2 or RGBA8 against what the device samples. That is the row's
  "web — both sets, chosen at load time" without a second file and without a
  loader that has to pick between two — the part `ap-11` had left open.
- **The question a loader asks is in the HAL.**
  `GraphicsDevice.supportsTextureFormat` answers per format on every backend,
  where `preferredTextureFamily` was a WebGL-only reading of extension names.

A `--target` on the command line would be a second spelling of `--textures
bc` or `--textures etc2`: the machine running the converter is not the one
that loads the texture, only a build knows its target, and a build does not
go through the command line.

**What did come across: `--no-mips` skips something.** The flag was accepted
and answered with a note, because when it was added nothing generated a chain
to skip. `convertOne` and `encodeDocumentTextures` take `mips:`, and with it
false every family — `universal` included, which writes its levels and header
differently from the rest — keeps the base level alone. `convert_test.dart`
asserts the byte sizes of an 8×8 texture's BC1 levels, `[32, 8]` by default
and `[32]` with the flag; `texture_encode_test.dart` holds all three families
to one level.

Not done, honestly: **only a manifest rule's `exclude` reaches the hook.** The
manifest parses `textures`, `mips` and `objNormals`, `AssetLayout.plan`
carries the matching rule with every file it plans, and `runAssetBuild`
converts each one with the build's family and the converter's defaults. The
web build still compresses nothing unless the project says `universal`
itself: a web build names no target, which is also what an asset-only
invocation looks like, and the hook does not invent one. A real phone.

### ap-10: `dart run flutter3d_build:init` — closed

Closed 2026-09-15. **The real name is `flutter3d_build:init`, not
`flutter3d:init`** — the same way `ap-03`'s converter is
`flutter3d_build:convert`. `tool/init/` (`tpl-01`) says in its own words
that this package did not exist when it was written; it does now, and
`tpl-01` has not been moved onto it — it has its own item and its own turn.

**Four steps, each idempotent and checkable on its own.**
`packages/flutter3d_build/lib/src/init.dart`'s `planInit(projectRoot)`
answers "what would change" and writes nothing — the one answer `--check`
prints and a real run carries out, so the two cannot disagree about what
"already set up" means.

1. `hook/build.dart` — written if absent; left alone if it matches; if it
   exists and differs, a blocked step, refused without `--force`, in the
   same words under `--check` and in a real run.
2. `dev_dependencies: flutter3d_build:` — added only if the block holds no
   `flutter3d_build:` line at all; a constraint a person pinned is theirs.
3. `flutter: assets:` — the active key is looked for apart from the
   commented-out example `flutter create` writes, which the tool that reads
   this file never reads and `init` therefore treats as absent.
4. `.gitignore`'s `/flutter3d_generated/`.

**Line-based, not parse-and-re-emit.** `_topLevelKey`/`_blockEnd`/
`_insertAtEndOfBlock` find and edit exactly one block by indentation and
touch nothing outside it; `package:yaml` cannot print a parsed tree back
with its formatting and comments, and a fresh `pubspec.yaml` is mostly
comments.

**Checked end to end at the time**, on the branch this was written on: a
real `flutter create --platforms=web` in a temp directory, a real `dart run
flutter3d_build:init` from inside that project, and a real `flutter build
web` — `flutter3d_generated/.flutter3d_cache.json` appeared, and only
`runAssetBuild` writes that file. A second `init` said "already up to date".
That run has not been repeated since the package merges; the unit tests
have.

**A correction the same day, found by `ap-12`: one `- flutter3d_generated/`
line was not enough.** `flutter_tools`' `_parseAssetsFromFolder` lists a
declared directory with a plain `listSync()`, no `recursive: true`, so one
line bundles what sits directly in it and never a subdirectory.
`AssetLayout.plan` keeps a source's relative directory in its destination
(`assets_src/models/chair.glb` → `flutter3d_generated/models/chair.f3d`), so
every project with sources in a subdirectory got a hook, a `.gitignore` and
a clean `--check`, and a real build that packed the cache file and not one
converted model. The end-to-end check above missed it because its one model
sat directly in `assets_src/`. `_generatedAssetEntries(layout)` now reads
the plan and declares one entry per subdirectory that really holds a
converted file.

New when this was brought onto the merged packages: a test that holds
`kFlutter3dBuildVersionConstraint` to the version this package's own
`pubspec.yaml` names, since a release that bumps one without the other
points every project `init` touches afterwards at the wrong version.

Not done: `tool/init/` still copies a static `hook/build.dart` from the
template rather than calling `planInit`; no real phone.

### ap-11: `loadModelAsset` — closed

Closed 2026-09-15. **The package is the engine (`flutter3d`), not
`flutter3d_build`**: an application calls this at runtime, and
`flutter3d_build` is deliberately no dependency of the engine.
`generatedAssetPathFor` (`packages/flutter3d/lib/src/engine/assets/
load_model_asset.dart`) is the same mapping `AssetLayout.plan` computes,
rewritten in three lines rather than imported.

**Two different answers to a missing file, both explicit.** In `debugMode`
(default `kDebugMode`) a missing `.f3d` decodes the source directly and
warns once per path (`_warnedMissingGenerated` is a set, not a counter).
Outside it, a `StateError` naming `dart run flutter3d_build:init`.
`FlutterError` and `FileSystemException` are caught apart from any other
error: a corrupt but present `.f3d` fails as itself, because "no file" and
"a file that does not read" are different things — its own test.

**An honest boundary: the fallback reads the disk, not the bundle, and so
does not work on the web.** `assets_src/` is deliberately not declared under
`assets:`, so there is nothing bundled at that path; `FileAssetSource`
reaches the checkout, which exists during `flutter run`/`flutter test` from
a source tree and never in a shipped build. On the web (no `dart:io`) a
missing generated file is the release error in every build mode.

**`generatedSource`/`fallbackSource` are a seam for a test, not an
architecture.** The engine's own `pubspec.yaml` declares no assets, and a
fixture added there for one test would ship in every application that
depends on the package. The acceptance says "a test with a bundle fixture";
what is here is a fixture standing where the bundle's answer would be, and
it says so.

**`loadModelByPath`, added when this was brought onto the merged
packages.** A level document names its models by path, and a project partly
on the pipeline has both kinds: `assets_src/…` goes to `loadModelAsset`,
anything else is read from the bundle as it stands — `loadModelAsset` turns
any path into `flutter3d_generated/…`, which for `assets/models/pickup.glb`
is a file nobody asked the hook to write. `FixtureVisuals` and
`ActorVisuals` in `flutter3d_game` both load through it; on the branch this
came from the same prefix test was written once in each.

What the branch left open — choosing `chair.f3d` or `chair.etc2.f3d` on the
web — does not arise here. There is one generated file per source: a build
for one platform carries that platform's family, and a build for several
cooks `universal`, which the upload resolves (`ap-09`).

### ap-12: the template and four demos on the pipeline — tried on a branch, not carried over

On 2026-09-15 the three games with real models — platformer (3), dungeon
(10), racing (5) — were moved onto the pipeline on the `edu-track` branch:
`assets/models/` → `assets_src/models/`, a `hook/build.dart` each, a `path:`
dev dependency on `flutter3d_build`, `flutter3d_generated/` and
`flutter3d_generated/models/` under `assets:`, `hook/**` excluded from
analysis. The template and strategy have no models to move. **That move is
not in this tree**, and what it found is worth more than the move:

- **The measured size went up, not down.** Web builds, before → after:
  platformer 49 720 → 49 972 KiB, dungeon 59 108 → 59 684 KiB, racing
  56 196 → 57 100 KiB. The first day's numbers showed a saving, and the
  saving was the three models that had silently dropped out of the bundle —
  the non-recursive `assets:` finding recorded under `ap-10`. The honest
  reason for no saving was that the branch's hook named no target and so
  compressed nothing. That reason is gone in this tree (`gfx-69n`, under
  `ap-09`), so for a desktop or a phone build the measurement would have to
  be taken again before it says anything; for the web it still stands until
  a project asks for `universal`.
- **Level textures are outside the pipeline by construction.** A level's BSP
  materials name `assets/textures/*.png` directly in the level document,
  read by `LevelLoader` with no `ModelDocument` in between; every stage here
  classifies an image by the model material that references it, and a level
  material references nothing this pipeline reads.
- **`flutter analyze` cannot see a `dev_dependency` from `hook/build.dart`**,
  which sits outside `test/` — hence the `hook/**` exclusion.
- **A hook-providing dependency added after the last build needs `flutter
  clean`**: the incremental cache remembers "no hooks" (`Skipping target:
  build_hooks`).
- **`flutter test` does not run build hooks**, so the games' tests went
  through `ap-11`'s debug fallback, and `flutter analyze` on a fresh
  checkout reports `asset_directory_does_not_exist` for the generated
  directory until a first real build creates it.

What a correct move still needs, none of which the branch had: the level
generators (`levelkit.py`, `cryptkit.py`) and `tool/make_models.py` writing
the new paths, or the "levels" and "models" steps of `tool/ci.sh` regenerate
the old ones and fail; `apps/flutter3d_demo_dungeon/assets/editor.json`,
which names the same models for the editor; a CI step that creates the
generated directories before `flutter analyze`, the way `ap-06` does for the
shader bundle; and re-recording `site/assets/samples/*.f3drun`, whose
`levelHash` changes with every level document that names a model. The
loaders are ready for it — `loadModelByPath`, under `ap-11`.

### ap-13: CI and measurements — the checkable half is closed

2026-09-15. **"Converted equals original" on the Khronos set.**
`packages/flutter3d_build/test/khronos_roundtrip_test.dart`: the eleven
files `flutter3d_samples/assets/ATTRIBUTION.md` credits to
`KhronosGroup/glTF-Sample-Assets` directly (not `RobotExpressive.glb`, a
different source; not the teapot, not glTF at all) — `Box`, `BoxTextured`,
`BoxVertexColors`, `Triangle`, `BoxAnimated`, `InterpolationTest`,
`NormalTangentTest`, `NormalTangentMirrorTest`, `RiggedSimple`,
`RiggedFigure`, `AnimatedMorphCube`. Each goes through `convertOne` — the
hook's own code — both ends are decoded back, and `compareModelDocuments`
finds nothing on all eleven, animation, skinning and morph targets included.
Read by a sibling path, since `flutter3d_samples` needs the Flutter SDK and
this package must stay flat.

**A second build converts nothing** was already proven:
`build_assets_test.dart`'s `the acceptance line: a second build with nothing
changed converts nothing` (`ap-05`).

Not done, and not for want of time: "four green CI jobs" needs real macOS,
browser, Android and iOS runners, and editing `.github/workflows/ci.yml`
with no way to watch the result is a bigger risk than an unfinished item —
the same call `ap-06` made for its Android path. **"Install-to-first-frame
re-measured with the script from the Measurement section" is unreachable as
written: the script does not exist.** That ROADMAP section is a goal, not a
report, and nothing in the tree carries the name.

### ap-14: documentation — closed

2026-09-15. **A new page, `site/content/reference/asset-pipeline.md`** — not
`core/assets.md`, which already existed and covers the runtime side, and now
links across. The page: `assets_src/`, `init`, the manifest, texture
families, `loadModelAsset` and `loadModelByPath`, and a "when the hook
fails" table of four symptoms each really met rather than listed in advance.
**The site builder has no directory scan** — `site/tool/build.mjs` reads an
explicit array, and a page with no entry there is absent from `dist/` with
no error at all, which is how the first build went.

**Quickstart keeps only the shader step still true.** Checked in a detached
worktree at the time: `packages/flutter3d/example` builds without
`flutter3d_impeller`'s `build_shaders.sh`, the canonical bundle appearing
through `ap-06`'s hook, and fails without the example's own separate script
("No file or variants found for asset: assets/shaders/example.f3dshaders") —
the bundle `ap-06` never covered. The three games only ever linked the
canonical one, so for them there is no shader step at all.

`site/content/reference/packages.md`'s entry for `flutter3d_build` names the
command by its real name and links the page. CHANGELOG entries where code
really changed: `flutter3d_build`, `flutter3d`, `flutter3d_game`.

Rewritten where this tree had moved on from the branch the page was written
on: the families section describes the hook taking its family from the
platform it is told it is building for, the user-defines override — under the
project's own package name, since the hook is the project's — and
`universal`, in place of a `--target` table and a warning that the hook
cannot compress. It says only a rule's `exclude` reaches the hook, and that
the three shipped games still bundle their models directly.
