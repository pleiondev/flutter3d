---
description: Shapes as values, surfaces of revolution as the base generator, vertex layouts, MeshBuilder, tangents, and what a material actually selects.
---

# Geometry & materials

The CPU-side geometry layer knows nothing about the GPU. That is what lets a shape be built, measured, bounded and tested in a plain unit test, and it is why `MeshNode` holds a `MeshGeometry` instead of a `GpuMesh`.

## Shapes are values

`Shape` is an abstraction, not a bag of static factories. A shape can be stored, passed around, compared, kept in a list the UI offers, and swapped for a caller's own implementation. `Primitives.sphere(...)` can only ever be invoked.

```dart
const Shape shape = SphereShape(radius: 0.5, segments: 32, rings: 16);

final MeshData data = shape.build();                 // CPU, no device
final DeviceMesh mesh = DeviceMesh.upload(device, data);
```

| Shape | Parameters |
|---|---|
| `CuboidShape` | `size` |
| `PlaneShape` | `width`, `depth`, `widthSegments`, `depthSegments` |
| `SphereShape` | `radius`, `segments`, `rings` |
| `CylinderShape` | radii, `height`, `segments` |
| `ConeShape` | a cylinder with a zero top radius |
| `TorusShape` | major and minor radius |
| `CapsuleShape` | `radius`, `height` |
| `DiscShape` | `radius`, `segments` |
| `LatheShape` | an arbitrary profile — everything above the first two derives from it |

### Surfaces of revolution

`LatheShape` sweeps a profile polyline around the Y axis, and every rounded primitive is a `DerivedShape` holding one with friendlier parameters. The relationship is in the type rather than duplicated in the generation code.

```dart
// A vase: any profile in the (radius, height) half-plane.
final vase = LatheShape(
  profile: <Vector2>[
    Vector2(0.00, 0.0), Vector2(0.45, 0.05), Vector2(0.30, 0.35),
    Vector2(0.42, 0.72), Vector2(0.26, 1.00), Vector2(0.00, 1.02),
  ],
  segments: 48,
  name: 'vase',
);
```

Four properties are worth knowing before authoring a profile:

- **Orientation follows the profile direction.** Bottom-to-top gives outward normals and counter-clockwise front faces. Reverse it for an inside-out surface, a skybox — without touching any other flag.
- **Normals are analytic**, derived from the profile tangent rather than by averaging face normals, which keeps cones and poles exact.
- **A repeated profile point is a hard edge.** The duplicated pair has a zero-length delta on one side, so each copy falls back to its own one-sided tangent. That is how a cylinder gets crisp rims where the caps meet the wall.
- **UVs use arc length**, not point index, so texels do not bunch up where the profile is finely subdivided.

<div class="note">
<p>Chord-derived normals are exact for straight segments and first-order wrong at the ends of a curved one: at a sphere pole built from 16 rings the error is about 5.6°. Pass <code>profileNormals</code> when the profile has a known analytic normal — <code>SphereShape</code> and <code>CapsuleShape</code> do.</p>
</div>

## Vertex layouts

A vertex buffer is bound as one opaque blob and the real layout comes from the order of `in` declarations in the vertex shader. Nothing validates that contract for you, so `VertexLayout` at least makes it explicit and keeps it in one place.

```dart
const VertexLayout.standard;             // position, normal, texcoord, tangent, color
const VertexLayout.positionOnly;         // shadow depth
const VertexLayout.positionColor;        // the debug line overlay
const VertexLayout.positionColorTexcoord; // particle quads
```

<div class="warn">
<p><strong>A third layout means a third vertex shader.</strong> A backend reads the layout off the shader's <code>in</code> declarations, which is the same constraint that forced a separate stage for debug lines and for skinning. Adding an attribute is a shader change, not a data change.</p>
</div>

Joint indices are held as **floats**, because the vertex buffer is one interleaved block of them and there are no attribute descriptors to say otherwise. A float32 represents every integer up to 2²⁴ exactly, so a joint index is never approximated.

## MeshBuilder

For geometry no generator covers.

```dart
final builder = MeshBuilder(VertexLayout.standard, reserveVertices: 256);

final a = builder.addVertex(
  position: Vector3(0, 0, 0),
  normal: Vector3(0, 1, 0),
  texcoord: Vector2(0, 0),
);
final b = builder.addVertex(position: Vector3(1, 0, 0), normal: Vector3(0, 1, 0));
final c = builder.addVertex(position: Vector3(0, 0, 1), normal: Vector3(0, 1, 0));
builder.addTriangle(a, b, c);

final MeshData data = builder.build();
```

Attributes absent from the layout are silently ignored, which lets one piece of generator code build for several layouts. Attributes the layout *declares* but the caller does not supply get a **neutral** value rather than zero, a zero vertex colour multiplies the surface to black and a zero tangent yields a degenerate TBN full of NaN.

## MeshData and the GPU

```dart
final data = shape.build();
data.computeBounds();
final packed = data.packIndices();      // 16-bit where it fits, 32-bit otherwise

final mesh = DeviceMesh.upload(device, data, keepSourceData: true);
```

`keepSourceData` is what lets picking test triangles rather than falling back to bounds. `CpuMesh` is the implementation for geometry that is queried but never drawn.

<div class="warn">
<p>There is <strong>no non-indexed draw</strong>. <code>draw()</code> with only a vertex buffer bound succeeds and renders nothing — the counter goes up and the screen does not change. Bind an index buffer even when the indices are the identity sequence; the debug line overlay keeps one in a device buffer that only grows.</p>
</div>

## Tangents

Generated with Lengyel's method where a mesh has none, taken analytically where the surface knows them, and checked against a real exporter's output on `NormalTangentMirrorTest`.

<div class="why">
<p>The bitangent sign is the part that goes wrong quietly. glTF's bitangent is <code>cross(normal, tangent) * w</code>, and it is <strong>minus</strong> dP/dv — texture V grows downwards while a normal map's green channel points up. Deriving <code>w</code> from <code>+dP/dv</code> gives tangent directions that agree with an exporter to seven digits and signs that are backwards everywhere, which only shows up on mirrored UV islands. The symptom is a normal-mapped surface lighting from the wrong side, on half the model.</p>
</div>

{{golden normal-mapping | A normal map lit from the side, with the tangents the generator emits.}}

## Materials

A `Material` is a pipeline selection plus its parameters. Changing `lighting` changes the shader, and therefore where the draw lands in the sort.

```dart
final material = Material(
  name: 'stone',
  lighting: LightingModel.pbr,
  baseColor: Vector4(1, 1, 1, 1),
  metallic: 0.0,
  roughness: 1.0,
  albedo: albedoTexture,
  normal: normalTexture,
  normalScale: 1.0,
  metallicRoughness: ormTexture,
  occlusion: ormTexture,
  occlusionStrength: 1.0,
  emissiveTexture: emissive,
  emissive: Vector3(0.9, 0.5, 0.2),
  emissiveStrength: 2.0,
  alphaMode: MaterialAlphaMode.mask,
  alphaCutoff: 0.5,
  doubleSided: false,
  drawBucket: 0,
);
```

{{golden lighting-pbr | The same model under the PBR model: Cook-Torrance specular, the flat ambient, one sun.}}

{{golden lighting-toon | And under the toon model, which is one pipeline switch away.}}

### Neutral fallbacks instead of per-map flags

A material with no normal map is bound the engine's flat-normal texture; one with no albedo gets white. So the shader needs **no branch** and the engine no bookkeeping about which maps a material has, which is also why `Renderer.create` demands both fallbacks up front.

### Alpha modes

| Mode | Effect |
|---|---|
| `opaque` | Depth write on, sorted front to back |
| `mask` | Alpha tested at `alphaCutoff`, still an opaque draw |
| `blend` | Sorted back to front, no depth write |

<div class="warn">
<p><code>setDepthWrite(false)</code> did nothing until Flutter 3.47, so additive particles occluded each other on two backends out of three. The software backend mirrored the bug on purpose to stay comparable; the full account is in <a href="/core/backends/#semantics">the backend contract</a>.</p>
</div>

### Procedural textures

```dart
final white = SolidColorTexture.white.upload(device);
final flat  = SolidColorTexture.flatNormal.upload(device);
```

Enough for placeholder materials and for a level whose author has not decided yet. The renderer's own fallbacks are these two and it makes them itself — pass `fallbackAlbedo` or `fallbackNormal` only when neutral is not what you want.

## Next

- [Assets & animation](/core/assets/): geometry that comes from a file
- [The frame](/core/rendering/): what happens to a pipeline once it is selected
- [Tutorial: first scene](/core/tutorial/): all of it, wired up
