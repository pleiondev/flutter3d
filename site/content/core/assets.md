---
description: glTF 2.0 and GLB, Wavefront OBJ, the .f3d container, isolate decoding and the reference-counted cache, plus clips, skinning and crossfades.
---

# Assets & animation

Three decoders, one abstraction, one upload path. Decoding runs on a background isolate; nothing in the decoding layer names `flutter_gpu`, `dart:io` or `dart:ui`.

## One abstraction, three formats

Both decoders, and the binary container — emit the same `ModelDocument`: a list of `ModelSurface`, a list of `SurfaceMaterial`, a list of `EncodedImage`, and `warnings`.

```mermaid
flowchart LR
  gltf[".gltf / .glb"] --> doc
  obj[".obj + .mtl"] --> doc
  f3d[".f3d"] --> doc
  doc["ModelDocument<br><i>surfaces · materials · images · warnings</i>"]
  doc --> asset["ModelAsset.fromDocument<br><i>mesh + image dedup, material conversion</i>"]
  asset --> instance["asset.instantiate(scene)"]
  instance --> nodes["SceneNode tree · MeshNodes<br>Skeletons · AnimationPlayer"]
```

That is what makes `ModelAsset.fromDocument` the single upload path, and it means adding a fourth format is a matter of writing a decoder rather than touching the loader.

## Loading a model

```dart
final document = await decodeModelInIsolate(
  ModelLoadRequest(source: const BundleAssetSource('assets/models/hero.glb')),
);

final asset = await ModelAsset.fromDocument(
  document,
  device: device,
  name: 'hero',
);

final instance = asset.instantiate(scene, name: 'runner');
final player = instance.player;          // null when the file has no clips
```

| Source | Where the bytes come from |
|---|---|
| `BundleAssetSource` | The Flutter asset bundle |
| `FileAssetSource` | The filesystem. Unavailable on web, which is why it is a separate type instead of a flag |

<div class="warn">
<p><strong>File reads stay on the UI isolate.</strong> <code>BackgroundIsolateBinaryMessenger.ensureInitialized(token)</code> grants a background isolate a working channel but creates no <code>ServicesBinding</code>, and <code>rootBundle</code> resolves through <code>ServicesBinding.instance</code>. Routing <code>flutter/assets</code> by hand fails deeper still — Flutter's own reply handler throws on a cast. So sibling files are requested back over a port, and the decode is what runs on the isolate.</p>
</div>

### Do not await a model before the first frame

```dart
// A box now, the model when it arrives.
final placeholder = _boxRunner(device, scene, runner);
unawaited(_dressRunner(device, scene, runner));   // swaps it in later
```

<div class="warn">
<p>Putting a model in the scene before the renderer has ever built its frame targets is an arrangement that fails to allocate on some machines, every frame, from the first, with an error screen instead of a picture. Load asynchronously and swap. The engine's own <code>FixtureVisuals</code> does exactly this, and it is why a level is playable while its models are still arriving.</p>
</div>

## glTF 2.0 / GLB

| | |
|---|---|
| Containers | `.glb` (chunk parser with padding, unknown chunks ignored) and `.gltf` |
| Buffers | The GLB `BIN` chunk, base64 `data:` URIs, external files through a resolver |
| Accessors | Every `componentType`, `byteStride` (interleaved), `normalized` with the symmetric clamp for signed types, sparse, and accessors with no bufferView |
| Topologies | TRIANGLES; STRIP and FAN are rewritten as lists, so no pipeline permutation per topology |
| Attributes | POSITION, NORMAL, TEXCOORD_0, TANGENT, COLOR_0 — only those the target layout declares are read |
| Normals | An absent NORMAL produces **flat** normals, as the spec requires, which de-indexes the mesh |
| Tangents | TANGENT when present, otherwise generated with Lengyel's method |
| Node graph | `matrix` and TRS, accumulated transforms, meshes reused across nodes, cycle guard |
| Materials | Metal-rough, all texture slots, `alphaMode`/`cutoff`, `doubleSided`, `KHR_materials_unlit`, `KHR_materials_emissive_strength` |
| Mirroring | Detected from the determinant's sign; winding is flipped per instance |
| Skins | `joints`, `inverseBindMatrices`, `skeleton`, JOINTS_0/WEIGHTS_0 |
| Animations | All samplers and channels; STEP, LINEAR, CUBICSPLINE; translation, rotation, scale, and weights |
| Morph targets | POSITION, NORMAL and TANGENT deltas, packed into a texture the vertex stage samples; rest weights from the node or the mesh; eight blended at once |

Not supported: cameras, Draco and meshopt, TEXCOORD_1 and up. All of them are reported in `warnings` rather than failing the file, and the demo surfaces those, a skipped primitive explains a model that looks odd but still loaded.

## KTX2 and compressed textures

A texture can arrive as a KTX2 container, sniffed before `dart:ui` ever sees the bytes, and two kinds of file come out of it. A Basis Universal ETC1S file is transcoded to RGBA8 in Dart, on an isolate where there is one, with its mip chain and its alpha slice; it costs what a PNG of the same size costs on the device and downloads at a fraction of it. A file carrying its own BC, ETC2 or ASTC blocks is uploaded as those blocks, levels and all, which is the upload that shrinks device memory: a 2048² BC7 texture is 5.6 MB where RGBA8 with a chain is 22.

The device is asked first. `GraphicsDevice.supportsTextureFormat` answers per format, from flutter_gpu's own per-family capability on Impeller, from the extensions the context handed back on WebGL2, and with a constant no for anything compressed on the software rasteriser, which samples raw texels. A no is a texture left out with a sentence in `warnings` naming the format, never a guess at a decoder the engine does not have. In glTF, `KHR_texture_basisu` is read: a core `source` wins while it exists, since a PNG always decodes, and the extension's KTX2 is what a file that ships only that falls back to.

Still refused by name: UASTC, Zstandard and ZLIB supercompression, texture arrays, cube maps and 3D textures. The key/value section is read for the same reason and refuses three more — a bottom-up `KTXorientation`, a `KTXswizzle` that is not `rgba`, and `KTXpremultipliedAlpha` — because those three describe the pixels rather than where they came from, and honouring none of them silently draws a texture upside down, channel-shuffled or twice darkened, which reads to an artist as their own mistake. Nothing in this repository produces a KTX2 either; the reader exists for other tools' output until the asset converter grows an encoder step.

<div class="note">
<p>The node hierarchy is kept <strong>index-aligned with the file</strong>, transform-only nodes included, because animation channels address nodes by index. Rebuilding the hierarchy on instantiation is what lets an animated parent carry its subtree.</p>
</div>

## Wavefront OBJ

| | |
|---|---|
| Faces | `v`, `v/vt`, `v//vn`, `v/vt/vn`; negative indices; polygons fanned into triangles |
| Vertices | Deduplicated by the (position, UV, normal) triple — the unit OBJ actually addresses |
| Normals | With no `vn`, **smooth** (area-weighted) normals are generated. `flat` and `none` are also available |
| UVs | V is flipped by default — OBJ texture space has its origin at the bottom left |
| Groups | `g`, `o` and `usemtl` start a new surface, so a multi-material file yields several draws |
| Materials | `.mtl` through a resolver: `newmtl`, `Kd`, `Ks`, `Ns`, `d`, `Tr`, `map_Kd` |
| Robustness | Unknown directives, malformed faces and missing libraries go to `warnings` |

OBJ predates PBR, so its parameters are **explicitly approximated**: `Kd` becomes base colour, the Phong exponent `Ns` becomes roughness, and a bright neutral `Ks` is the only hint of metalness available. The approximation is documented in `MtlMaterial` rather than hidden.

<div class="note">
<p>Flipped V is the single most common cause of upside-down textures on OBJ imports, and generating smooth normals rather than flat ones matters more than it sounds: the format prescribes nothing, files routinely omit them, and the geometry they omit them for is curved. Flat normals on a teapot look broken.</p>
</div>

## The `.f3d` container

The format matters far more than the language. The same geometry is about **360× slower** to load as OBJ text than as a binary buffer, and native code does not close that gap — measured in `ARCHITECTURE.md` §14. So `.f3d` moves the parse off the device entirely.

```bash
dart run tool/convert_asset.dart ../flutter3d_samples/assets/teapot.obj \
  -o ../flutter3d_samples/assets/f3d/teapot.f3d
```

| teapot | load |
|---|---|
| OBJ — parse, dedup, smooth normals | 4.54 ms |
| `.f3d`, every array touched | 1.1 µs |

Vertex and index arrays are stored exactly as `MeshData` holds them, so loading builds `Float32List.view`s over the file rather than copies, every blob entry is 4-byte aligned precisely so those views are legal. A **section directory** rather than fixed header fields, so a reader skips a kind it does not know and the version only changes when an existing record does.

`F3dDocument` is a `ModelDocument`, so `ModelAsset.fromDocument`, the cache and instancing are all unchanged. The converter re-reads what it wrote and compares it against the source before reporting success.

<div class="note">
<p>The file is <em>larger</em> than its source — 102 KB against 69 KB for the teapot, because indices stay 32-bit and nothing is compressed. That is the trade: narrowing indices or deflating the blob would reintroduce the per-load work the format exists to remove.</p>
</div>

## The resource cache

`ResourceCache` is reference-counted, so a mesh shared by forty torches is uploaded once and freed when the last one lets go.

```dart
final handle = await cache.acquire('assets/models/torch.glb');
final asset = handle.value;
// ...
handle.release();

cache.evictUnused();
```

A cache belongs to whoever built it — normally one level load. A GPU resource that outlives the level owning it is a leak nobody notices.

## Animation

```dart
final player = instance.player;
if (player != null) {
  player.playNamed('run');
  player.crossFadeToNamed('jump', duration: 0.06);
  player
    ..speed = 1.4
    ..update(dt);
}
```

| | |
|---|---|
| Interpolations | STEP, LINEAR and CUBICSPLINE with authored tangents |
| Rotations | Slerped |
| Modes | Once, loop, ping-pong |
| Transport | `play`, `pause`, `stop`, `seek(seconds)`, `speed` |
| Blending | `crossFadeTo(index)` and `crossFadeToNamed(name)` |
| Layers | `playLayer(index, mask: ...)` — a clip over the joints a mask names while the base keeps running |

<div class="why">
<p>A crossfade duration is not one number. A quarter of a second blending into a take-off is a quarter of a second of the character still standing there while the body is already in the air, so a jump gets 0.06 s and a walk-to-run gets 0.14 s. The rule is that the fade must be shorter than the event it is covering.</p>
</div>

### Animation is presentation, not simulation

Advance the player **once a frame**, not once a step. The simulation runs at a fixed 60 Hz and the animation should run at whatever the display does. Which clip to play is a pure function of the simulation's state, which makes it testable on its own:

```dart
// A pure function, tested as one.
final wanted = RunnerClips.forRunner(runner);
if (wanted != current) {
  player.crossFadeToNamed(wanted, duration: wanted == RunnerClips.jump ? 0.06 : 0.14);
  current = wanted;
}
player
  ..speed = RunnerClips.rateFor(wanted, groundSpeed)
  ..update(dt);
```

## Skinning

A glTF skin decodes into a `Skeleton` of ordinary scene nodes. 64 joint matrices in a uniform array, four weights a vertex, a separate skinned vertex stage, because a second layout is a second shader, and bounds taken from the **posed** skeleton rather than the bind pose.

{{golden skinned-figure | A skinned figure frozen at a stated second of its clip, so the frame is the same every time it is drawn.}}

## Morph targets

A face is a mesh blended towards the shapes its file carries. The deltas go into an `r32g32b32a32Float` texture — one column a vertex, three rows a target: positions, normals, tangents — uploaded once with the mesh and sampled **in the vertex stage**. The weights live on the node, so two copies of a model wear different expressions from one upload, exactly as two copies of a rigged model pose from their own skeletons.

```dart
// From a clip, or by hand.
node.morphWeights[0] = 0.6;              // one mesh
batch.setMorphWeights(7, [0.6, 0.0]);    // one copy in a batch
```

| | |
|---|---|
| Streams | POSITION, NORMAL and TANGENT deltas; a target with only positions leaves the rest alone |
| At once | Eight. A file with more loads with a warning naming what was left out |
| Rest weights | Read from the node, or the mesh when the node says nothing |
| From a clip | A `weights` channel, mixed by a crossfade and **added** by a layer |
| Per instance | `InstancedMeshNode.setMorphWeights`, read by instance id from a second texture |
| Passes | The colour, shadow and id passes all morph — a shadow of the base shape is a bug that hides |

{{golden morph-skinned | Rigged and morphing at once, which is the combination the two features can get wrong about each other: the deltas are added in the mesh's rest pose and the joints come after.}}

<div class="why">
<p>A texture rather than vertex attributes, because the vertex layout here is <em>structural</em> — the <code>in</code> declarations of <code>mesh.vert</code> are the layout, and one layout serves every model. Deltas as attributes would mean a second layout and with it a second vertex shader for each of six lighting models. A texture costs one sampler and no layout, which was only an option because a vertex stage can sample one — measured on all three backends by a conformance check rather than assumed.</p>
</div>

<div class="warn">
<p>Two of the three backends could not upload a full-float texture at all, and neither said so: the software rasteriser measured every format at four bytes a texel and refused sixteen as the wrong size, and WebGL filled <code>RGBA32F</code> storage through <code>RGBA</code>/<code>UNSIGNED_BYTE</code>, which is an <code>INVALID_OPERATION</code> no API reports and a texture that samples as zeros. Both drew the base shape with no error anywhere. What found it was the golden frame above, showing the same cube weighted and unweighted and identical byte for byte; what keeps it found is the <code>a float texture uploads as floats</code> conformance check.</p>
</div>

## Next

- [Simulation layer](/core/simulation/): the fixed step the animation is not tied to
- [Scene graph](/core/scene/), where an instantiated model lands
- [Tutorial: first scene](/core/tutorial/): loading a model end to end
