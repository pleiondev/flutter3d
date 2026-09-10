---
name: flutter3d-formats-reading-models
description: Use when reading or writing a 3D model with flutter3d_formats — glTF/GLB, OBJ, .f3d and .fmat behind one ModelDocument, the sibling-file resolver, and custom decoders.
---

# One document, four readers, no Flutter

Every decoder fills in the same `ModelDocument`: `surfaces` (each a `MeshData`
and a material index), `materials` normalised to metal-rough, `images` still
encoded, `nodes` index-aligned with the file, `skins`, `animations` and
`warnings`. Write against `ModelDocument` and a third format costs a decoder
rather than a branch.

Plain Dart, so a service validating an upload, a tool started with `dart run`,
an isolate and a plain `dart test` all get a glTF reader with no widget.
`flutter3d` exports this package whole.

## Reading

```dart
final document = await decodeModel(ModelLoadRequest(
  source: source,                // an AssetSource
  format: ModelFormat.auto,      // extension first, then the magic bytes
  layout: VertexLayout.standard,
  objNormals: ObjNormals.smooth,
));
```

`decodeModelBytes` is the same decode over bytes somebody else read, which is
the seam the isolate path uses: bytes and a resolver travel across a port, and
an `AssetSource` reaching for Flutter's asset bundle does not.

Individual readers when the format is known: `GltfLoader().load(bytes,
resolveUri: …)`, `ObjLoader().load(…)`, the `.f3d` reader behind
`isF3dFile(bytes)`, and `readFmat` / `writeFmat` for materials alone.

## The resolver is the only way out to a file

`AssetUriResolver` is `Future<Uint8List> Function(AssetRequest)`. A `.gltf`'s
external buffer, a texture, an `.obj`'s `.mtl` all arrive through it. Nothing
here opens a file itself, which is what makes a decode legal on an isolate with
no platform channel.

Run `safeRelativeAssetPath(uri)` on anything a file names before joining it to a
directory. A model is untrusted input and `../../` in a URI is the ordinary case
to defend against.

## Writing

```dart
final bytes = F3dWriter(document).write();
```

`.f3d` stores vertex and index arrays exactly as `MeshData` holds them, every
blob entry 4-byte aligned, so loading builds `Float32List.view`s over the file
instead of copies: the same teapot is 4.54 ms to parse as OBJ text and 1.1 us to
open as `.f3d`. It is larger than its source, and that is the trade — narrowing
indices or deflating the blob puts back the per-load work the format removes. A
section directory rather than fixed header fields, so a reader skips a record
kind it does not know.

## A format the engine does not ship

Implement `ModelDecoder` — `handles(fileName, bytes)` and `decode(bytes,
request, resolveUri)` — and hand it over on the request:

```dart
ModelLoadRequest(source: source, decoders: [MyFormatDecoder()]);
```

Custom decoders are tried before the built-in ones, so a project with its own
glTF reader gets its own. They ride on the request rather than in a registry
**because statics are not shared across isolates**: a registry filled at startup
is empty on the isolate that decodes, which works in a test and fails in the
application. Implementations must be sendable for the same reason.

## What the decoders promise

Non-fatal problems land in `warnings` rather than failing the file. Show them; a
model that loads and looks wrong usually explained itself there.

OBJ is approximated on purpose — `Kd` becomes base colour, the Phong exponent
`Ns` becomes roughness, a bright neutral `Ks` is the only hint of metalness —
and documented in `MtlMaterial`. Its V axis is flipped by default
(`flipTexcoordV`), because OBJ texture space starts at the bottom left; that is
the commonest cause of an upside-down texture.

An absent glTF `NORMAL` produces flat normals as the spec requires, which
de-indexes the mesh. An absent OBJ `vn` produces smooth ones, because the format
prescribes nothing, files routinely omit them, and flat normals on a teapot look
broken.

Refused by name: Draco, meshopt, cameras, `TEXCOORD_1` and up, and KTX2's UASTC
and Zstandard.
