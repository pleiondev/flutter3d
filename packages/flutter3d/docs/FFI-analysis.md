# What is worth moving to native code through FFI

Date: 2026-08-09. Method: measurement, not assumption.
The first two recommendations in §5 are already implemented; the numbers describe
shipped code.

---

## 1. How this was measured

`tool/bench/bench.dart` is compiled with `dart compile exe` — the same AOT pipeline
a release build uses — so the numbers reflect what ships on a device rather than JIT
warm-up. It measures the project's real assets (the Utah teapot, `BoxTextured.glb`)
and the same data structures the renderer uses.

To run it:

```bash
DART="$(dirname "$(command -v flutter)")/cache/dart-sdk/bin/dart"
$DART compile exe tool/bench/bench.dart -o /tmp/bench && /tmp/bench
```

Only the layers free of flutter_gpu can be measured this way, which is most of the
interesting ones: geometry generation, glTF and OBJ decoding, and the maths that
culling, sorting and transform propagation are built from.

Machine: macOS arm64 (Apple Silicon), Dart 3.12.2 AOT.

## 2. Results

### Asset decoding

| Operation | Time | Per unit |
|---|---|---|
| OBJ teapot, full load (smooth normals) | **5.39 ms** | 2387 ns/triangle |
| OBJ teapot, normals disabled | 4.52 ms | 2003 ns/triangle |
| GLB `BoxTextured`, full load | **14.8 µs** | — |

### Geometry generation (a 256×128 sphere: 33,153 vertices, 65,024 triangles)

| Operation | Time | Per unit |
|---|---|---|
| `SphereShape.build` | 888 µs | 26.8 ns/vertex |
| `MeshData.signedVolume` | 611 µs | 9.4 ns/triangle |
| `MeshData.transformed` (positions + normals) | 545 µs | 16.4 ns/vertex |

### Per-frame maths (50,000 objects)

| Operation | Time | Per unit |
|---|---|---|
| Frustum cull, 50k bounding spheres | 728 µs | 14.6 ns/object |
| Sort 50k: closure comparator with indirection (before) | **13.2 ms** | 263 ns |
| Sort 50k: index packed into the key, `Int64List.sort()` | 12.6 ms | 252 ns |
| Sort 50k: **`sortPackedKeys`, the shipped implementation** | **1.26 ms** | 25.1 ns |
| Sort 40 entries (the size a plain scene actually reaches) | 3.4 µs | — |
| Compose 50k world matrices | 778 µs | 15.6 ns/node |
| `invert` + `transpose` on 50k matrices | 1.07 ms | 21.4 ns/matrix |

Frame budget: 16.6 ms at 60 Hz, 8.3 ms at 120 Hz.

---

## 3. What the numbers say

### Finding 1: format matters more than language

GLB loads in 14.8 µs; an OBJ of comparable complexity takes 5.39 ms. That is roughly
**360x**, and it is not about parser speed — one format is binary (plus Dart's native
JSON parser) and the other is text that has to be split by a regular expression and
run through `double.tryParse`.

So rewriting the text parser in C treats the symptom. The right move is the one
already in the plan (layer 9, P2): **our own binary format** with offline
conversion. No amount of FFI delivers 360x.

### Finding 2: the only line over budget was not about language

Sorting 50k draw calls took 13.2 ms — **more than three quarters of a frame at
60 Hz**. It looks like the ideal candidate for "move it to C".

But replacing the closure comparator with a radix sort **in the same Dart** brings it
to 1.26 ms, **10.4x faster**. A naive comparison sort in C would be *slower* than a
radix sort in Dart, because the problem was asymptotics and data layout (a closure
per comparison plus double indirection into an `Int64List`), not the language.

The figure describes shipped code (`sortPackedKeys` in
`lib/src/engine/render/key_sort.dart`), not a prototype. Radix loses on short lists —
eight passes each clear a 256-entry histogram — so below a threshold of 96 entries an
ordinary sort is used; 40 entries take 3.4 µs.

That is the real lesson of the benchmark: before paying for a native build, make sure
the problem is not the algorithm.

### Finding 3: everything else already fits

14.6 ns per culled object, 15.6 ns per node, 26.8 ns per vertex — these are numbers
Dart AOT handles fine: `Float32List` and `Int64List` compile to plain memory access
with no boxing. A realistic gain from rewriting such loops in C is 2–4x through SIMD
and a better auto-vectorizer, not an order of magnitude.

50k objects are culled in 0.73 ms. Even at 200k that is 3 ms — a lot, but the answer
is a hierarchy (BVH), which removes the work rather than making it 3x faster.

---

## 4. What genuinely belongs in native code

The criterion is not "where it is hot" but **"where no reasonable Dart
implementation exists"**.

| Candidate | Why native | Readiness |
|---|---|---|
| **Draco** (`KHR_draco_mesh_compression`) | Google's C++ compressor; a Dart port is months of work, and not the kind of algorithm one writes in an evening | The decoder currently reports it in `warnings`. Needed for importing third-party assets |
| **Basis Universal / KTX2** transcoding | Same: a complex transcoder with no Dart implementation | **Blocked.** flutter_gpu's `PixelFormat` has no compressed formats (see RESEARCH.md §4), so there is nowhere to transcode *to* — the result could not be uploaded. It only becomes meaningful once the engine side supports ASTC/BC |
| **Physics** (Rapier, Jolt, Box2D) | Years of work on numerical stability and broadphase | Layer 11 of the plan, P3. Rapier as a Rust cdylib is the most direct route |
| **Audio** (miniaudio, SoLoud) | Needs real-time work against the OS audio stream | Outside the current plan |
| **ASTC/BC encoding** | Encoders exist only as native code | **No FFI needed**: this is an offline asset-build task. An ordinary CLI tool in the pipeline solves it without a single line of FFI in the app |

Note the pattern: in two of five cases the answer is "native code, yes, but not
through FFI and not now".

### meshopt is its own case

`EXT_meshopt_compression` is simpler than Draco and its decoder is realistically
writable in Dart (mostly varint decoding and deltas). Given the measurements, start
with the Dart version rather than a binding.

---

## 5. What to fix in Dart before considering FFI

In descending order of payoff; every figure measured.

1. ~~**Radix sort in `RenderList`**~~ — **done**: 13.2 ms → 1.26 ms at 50k. The
   single largest win anywhere in the frame.
2. ~~**Cache the normal matrix on the node**~~ — **done**: `worldNormalMatrix` on
   `MeshNode` is cached by `worldVersion`, as the bounds already were. The renderer
   no longer runs `invert` + `transpose` per draw (1.14 ms across 50k, and pure waste
   for anything static).
3. **OBJ parser: read bytes, not strings.** Today the whole file goes through
   `utf8.decode`, then `split('\n')`, then `split(RegExp(r'\s+'))` per line. Parsing
   bytes directly (a hand-written number scanner instead of `double.tryParse`)
   realistically gives 5–10x with no native code. For our own assets, though, the
   better answer is not to parse text at all (finding 1).
4. **Loading on an isolate** (layer 9, P1) — **done**. It does **not** make decoding
   faster, but it removes the jank: 5.39 ms on the UI isolate is a third of a frame,
   and a large model stalls for tens of milliseconds. FFI does not solve this either —
   a native call from the UI isolate blocks it exactly the same way.

Point 4 deserves emphasis: **FFI is not a cure for jank.** Isolates are, and they are
needed regardless of what language the decoder is written in.

---

## 6. What FFI actually costs

The cost is not in the calls; it is in building and operating the thing. For our three
targets:

- **iOS.** Loading arbitrary dylibs from outside the bundle is against App Store
  rules. That means a static library or an embedded `.xcframework`, with device and
  simulator slices, signed, integrated through CocoaPods or SwiftPM.
- **Android.** A separate `.so` per ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`), built
  through CMake/NDK in Gradle. New page-size requirements (16 KB) break older
  binaries, so the library has to be rebuilt for them.
- **macOS.** A dylib inside the bundle, with signing and notarization mandatory —
  Gatekeeper refuses an unsigned app even when it is handed over on a USB stick.
- **Tooling.** Automated native dependency builds mean Native Assets, which are still
  experimental. We already deliberately avoided them for shaders by invoking
  `impellerc` directly; the risk for FFI is the same.
- **Development.** Hot reload does not apply to the native part, debugging spans two
  toolchains, and a crash in C is a `SIGSEGV` with no Dart stack trace. We have
  already met that genre with the phantom uniform block, and it was no fun.
- **Data across the boundary.** `TypedData` does not travel by itself: it needs a
  `Pointer` — either a copy, or `.address` inside a leaf call with no allocation
  between taking the address and the call. Hence the rule: **few calls, large
  payloads.** An architecture that calls into C per vertex loses to plain Dart.

---

## 7. Decision

**Do not add FFI to the project yet.** None of the measured operations justifies it:
everything that did not fit the budget was fixable in Dart, and with a larger win
than a naive port to C would have produced.

Revisit when at least one of these becomes true:

1. Third-party assets compressed with **Draco** have to be imported.
2. flutter_gpu gains compressed pixel formats — at which point **KTX2/Basis** becomes
   meaningful, and also the leading candidate.
3. **Physics** is needed — where the argument is not performance but that writing
   one's own solver is not the job.

Until then the order of work is: ~~radix sort~~ → ~~normal-matrix cache~~ →
~~isolate loading~~ → our own binary asset format. The first three are done; together
the first two removed about 13 ms from a frame in a 50k-object scene.
