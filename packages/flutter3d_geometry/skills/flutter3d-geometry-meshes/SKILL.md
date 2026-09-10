---
name: flutter3d-geometry-meshes
description: Use when building, describing or intersecting geometry with flutter3d_geometry — vertex layouts, MeshData, shape generators, tangents and the ray arithmetic, with no GPU.
---

# Geometry, without a device anywhere

Plain Dart: `dart test` runs with no binding, `dart compile exe` builds a tool
out of it, and nothing here has met a graphics device. If the engine is already
a dependency, import `package:flutter3d/flutter3d.dart` — it exports this
package whole, under the same names.

An import of `package:flutter/…` here fails `dart run tool/structure.dart`,
which walks this package's dependencies, direct and transitive.

## A mesh is a layout plus two arrays

```dart
final cube = const CuboidShape(size: Vector3(1, 1, 1)).build();
cube.vertexCount;  // 24: a cube's corners once per face normal
cube.vertices;     // Float32List, interleaved as the layout says
cube.indices;      // Uint32List
```

`VertexLayout` decides what a vertex holds: `standard` (position, normal, UV,
tangent, colour), `positionOnly`, `positionNormal`, `positionNormalTexcoord`,
`positionNormalTexcoordTangent`, `positionColor`, `positionColorTexcoord`,
`skinned`. Build with the layout the consumer reads — a generator asked for a
layout with no tangent channel does not compute tangents.

For geometry no generator describes:

```dart
final builder = MeshBuilder(VertexLayout.positionNormal);
final a = builder.addVertex(position: …, normal: …);
builder.addTriangle(a, b, c);
final mesh = builder.build();
```

## Shapes are values, not static methods

A `Shape` can be stored, compared, sent to an isolate and put in a list.
`CuboidShape` and `PlaneShape` stand alone; `SphereShape`, `CylinderShape`,
`ConeShape`, `TorusShape`, `CapsuleShape` and `DiscShape` are all `DerivedShape`
over `LatheShape`, which revolves a 2D profile — so an arbitrary profile is a
shape too, with no new code:

```dart
const vase = LatheShape(profile: [Vector2(0.1, -1), Vector2(0.6, 0), …],
                        segments: 48);
```

Reach for `LatheShape` before writing a generator. A second copy of the seam and
pole handling is where the bugs live.

## Rays return a distance, and a miss is negative

```dart
final t = rayTriangle(ray, a, b, c);   // < 0 when it misses
rayAabb(ray, box);
raySphere(ray, centre, radius);
```

`TriangleBvh.fromMesh(mesh)` is the accelerator when a mesh is queried
repeatedly, with `forEachInAabb` and `forEachInFrustum` for queries that are not
rays. Build it once: a tree built per query costs more than the scan it
replaces. When vertices move and topology does not, `refit()` moves the boxes.

## Tangents and morph targets

Tangents come from Lengyel's method where a mesh has none and analytically where
the surface knows them. The bitangent sign follows glTF: `cross(normal,
tangent) * w`, with `w` derived from **minus** dP/dv, because texture V grows
downwards. Getting it backwards looks correct everywhere except on mirrored UV
islands.

`MorphTarget` holds position, normal and tangent deltas; `MorphTexture` packs
them into the texture a vertex stage samples; `MorphBlend` is the weight set. Up
to eight blend at once.

## What this package does not do

It does not upload, draw or load. `DeviceMesh` and everything naming a
`GraphicsDevice` are in `flutter3d`; reading a `.glb`, `.obj` or `.f3d` is
`flutter3d_formats`. `CpuMesh` is the `MeshGeometry` for geometry that is
queried and never drawn.
