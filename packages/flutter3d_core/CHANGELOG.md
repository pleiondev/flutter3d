## Unreleased

- **A morph-target warning names its primitive.** The three warnings the glTF
  loader adds when it drops a morph target had their interpolations escaped,
  so each said, literally, `$label has ${targets.length} morph target(s)`.
  Nothing failed because nothing reads a warning but a person.

- **A UASTC KTX2 opens (`gfx-78n`).** What `toktx --uastc`,
  `gltf-transform uastc` and `basisu -uastc` write was refused by name — and
  by guess, since any undefined `vkFormat` outside Basis-LZ was taken to be
  one. `Ktx2Texture.parse` now
  reads the data format descriptor's colour model to learn *which* Basis
  Universal a file holds instead of inferring it from the supercompression
  scheme, and unpacks UASTC LDR 4×4 — all nineteen modes — to RGBA8 in
  `uastc_decoder.dart`, through the same Zstandard and ZLIB unwrapping the plain
  formats use, since a current encoder Zstandard-compresses UASTC unless told
  not to. Unpacked rather than repacked to BC7 or ASTC: every file opens on
  every device, at four bytes a texel. A glTF that ships only a
  `KHR_texture_basisu` UASTC texture keeps it. UASTC HDR and the newer
  intermediate colour models are refused by name. Tables transcribed from the
  Basis Universal reference transcoder, and checked against it the only way
  worth having: files its own encoder wrote, chosen until every mode appears
  in them, compared **byte for byte** with its own RGBA32 output.

- **A Draco-compressed glTF opens (`gfx-82n`).** `KHR_draco_mesh_compression`
  was detected, warned about and skipped, so a compressed file opened as a
  model with holes in it — and since every such file names the extension as
  required, most were refused outright before that. `decodeDraco` now reads
  edgebreaker connectivity, which is what every encoder writes unless told
  otherwise, in both its standard and valence traversals; both attribute walks;
  and every prediction scheme a bitstream 2.2 encoder can choose — difference,
  parallelogram, constrained multi-parallelogram, portable texture coordinates
  and geometric normals. `GltfLoader` decodes the payload and puts its values
  behind the primitive's own accessors through the new
  `GltfAccessorReader.supplyDecoded`, so morph targets, skinning and the writer
  read a compressed primitive as they read any other; joints stay the integers
  they were stored as. A payload that does not decode costs that primitive, and
  the warning carries the decoder's reason. Point clouds, bitstreams before
  2.2, the predictive traversal and the two retired prediction schemes are
  refused by name. Checked against `gltf-transform draco` at its default speed
  and at speed zero — which are nearly disjoint sets of code paths — on a
  thousand-face mesh with UV seams and on a skinned one, triangle for triangle
  against the uncompressed originals. **One bug in what was already there,
  found by that comparison**: the rANS end-of-stream check compared the state
  without first pulling in the bytes the encoder shifted out before its first
  symbol, so a valid stream whose first symbol was rare was refused.
- **`KHR_texture_transform` can be honoured, in the coordinates.**
  `sharedTextureTransform` names the one transform every texture of a material
  asks for, and `withTextureTransform` gives a mesh with that transform applied
  to its texture coordinates, tangents turned and mirrored with them. That is
  the case an atlas export writes, and it needs no matrix at the sampler. The
  decoder still applies nothing, so a document written out again is the file
  that was read. Its warning changes: it no longer fires for every texture that
  names the extension, only for a material whose textures name different
  transforms, which one set of coordinates cannot satisfy. A file that lists
  the extension under `extensionsRequired` is still refused.
- **Accepted `flutter3d_geometry`, `flutter3d_formats` and `flutter3d_fbx`.**
  They are `package:flutter3d_core/geometry.dart` and
  `package:flutter3d_core/formats.dart` now, each importable on its own and
  both exported from `flutter3d_core.dart`; `FbxDecoder` is part of the formats
  library. All three were plain Dart with `vector_math` as their only
  third-party dependency and none was published, so the package boundary gave a
  caller that wanted a mesh or a `.glb` without the renderer nothing a library
  does not. Their tests, tools and skills moved with them; the skills are
  `flutter3d-core-geometry-meshes` and `flutter3d-core-formats-reading-models`.

## 0.1.0

- **The rendering core leaves `flutter3d` (`mcp-03n`).** Scene graph, render
  list, passes, materials and animation move here with no Flutter SDK
  behind them; `flutter3d` re-exports this package and keeps `rootBundle`,
  `dart:ui` and the widgets for its own thin shell.
