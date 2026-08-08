# Scene and camera: a review of the models and a proposal

Date: 2026-08-08. Status: the decision has been made and implemented (see §8–9).

---

## 1. What is wrong right now

The current state (after the glTF decoder) is honestly described like this: **there is no
scene**, there is a flat list of draw calls, and the camera is hard-coded inside the renderer.

Specifically:

| Problem | Where | Why it is a dead end |
|---|---|---|
| The camera is computed inside `render()` | `mesh_renderer.dart` | You cannot let the user move it, cannot have two cameras, cannot render into a texture for reflections |
| Model rotation is baked into the renderer | `spinMatrix` in `render()` | Animation is a property of the scene, not of the renderer. Right now you cannot rotate one object out of two |
| `GpuModel` is a flat list | `gpu_model.dart` | No hierarchy: a glTF node that moves a subtree cannot be expressed. Transforms are already "collapsed" at load time |
| No culling and no sorting | — | Everything is drawn in list order. Transparency will not work, and the pipeline switches arbitrarily often |
| Light is a constant in the shader/uniform | `render()` | Light is not a scene object; it cannot be moved and you cannot have two |
| One pass, one target | — | Shadows, post-processing and multi-view require "camera + target + filter" as a separate entity |
| Model = asset = instance | `GpuModel` | You cannot place one model into the scene twice with different transforms without loading it twice |

The last point is particularly telling: the glTF decoder already knows how to reuse a mesh across
nodes, and `GpuModel` throws that advantage away.

---

## 2. How three libraries solve it

### three.js — a single `Object3D`

One base entity with a transform and children; `Mesh`, `Camera` and `Light` are its subclasses.

- Lazy updates through a dirty flag: changing `position` does not recompute matrices, it sets
  `matrixWorldNeedsUpdate`. Once per frame `updateMatrixWorld()` walks the tree, computes `matrix`
  from TRS and `matrixWorld = parent.matrixWorld × matrix`.
- `matrixAutoUpdate` / `matrixWorldAutoUpdate` let you disable the automation for static content.
- `layers` — a bitmask of channels, plus `visible`, `frustumCulled`, `renderOrder`.
- `attach()` — reparenting that preserves the world transform (unlike `add()`).
- Every frame the renderer builds a render list, splits it into opaque/transparent and sorts:
  opaque by (renderOrder, program, material, z), transparent by (renderOrder, descending z).

**What to take:** layer bitmasks, `attach()` preserving the world transform, the
opaque/transparent split, `renderOrder` as a manual override.
**What not to take:** a god object at the base. `Object3D` knows about everything at once, and in
Dart that also means a fat object per node.

### Babylon.js — `Node` → `TransformNode` → `AbstractMesh` → `Mesh`

The hierarchy is split by responsibility: `Node` is name and kinship, `TransformNode` is only the
transform, `AbstractMesh` is bounds, material and culling, `Mesh` is geometry.

- **Cameras and lights are `Node`s too.** That means you can parent a camera to a moving object for
  free, without a special "follow" mechanism.
- `computeWorldMatrix(force)` with caching, `setParent()` preserves the world transform.
- `renderingGroupId` (0..3) is coarse group ordering, `alphaIndex` orders within a group.
- `scene.activeCamera` and `activeCameras`; each camera has its own normalised `viewport` and
  `layerMask` — that is how split-screen and a mini-map are done.

**What to take:** a pure transform node with no render payload (grouping and pivots become free)
and **the camera as a scene node**.

### PlayCanvas — ECS + layers as a contract

`GraphNode` is transform and hierarchy; `Entity` = `GraphNode` + components (render, camera, light,
script, collision). Composition instead of inheritance.

The most interesting part is layers:

- A layer is literally "a list of meshes to draw", and it is **automatically split into Opaque and
  Transparent** sublayers by material.
- A camera has a **priority** and a **list of layers** it draws. The UI camera draws only the UI
  layer.
- Each sublayer has its own **sort mode**: Material/Mesh (minimum state changes — the default for
  opaque), Back-to-Front (the default for transparent), Front-to-Back, Manual (by `drawOrder`),
  None. Plus `drawBucket` (0–255) as a coarse primary key.
- The resulting order: camera priority → layer order → sublayer sort mode.

**What to take:** composition instead of inheritance; layers as an explicit contract between the
scene and the frame; **sort modes as a setting rather than a policy welded into the renderer**.

### Summary

| | three.js | Babylon.js | PlayCanvas |
|---|---|---|---|
| Base | `Object3D` (everything in one) | `Node`→`TransformNode`→`Mesh` | `GraphNode` + components |
| Camera in the graph | yes (a subclass) | yes (a `Node` subclass) | a component on an Entity |
| Matrix updates | dirty flag + one traversal per frame | cache + `computeWorldMatrix` | dirty flags on `GraphNode` |
| Visibility filter | the `layers` bitmask | `layerMask` | layer lists + a mask |
| Draw order | `renderOrder` + sorting in the renderer | `renderingGroupId` + `alphaIndex` | camera priority → layers → sort mode |
| Multi-view | several `render()` calls + scissor | `activeCameras` + `viewport` | cameras with priorities |

---

## 3. What our constraints add

This is not cosmetic — three constraints change the conclusions compared with web engines.

**1. Shaders are compiled AOT, and the pipeline is expensive, coarse state.**
In web engines swapping a shader is cheap, so sorting by material can be treated as an
optimisation. Here the pipeline is created ahead of time, switching it inside a pass costs more,
and there are few permutations and they are large (lighting model × blend mode). So **the pipeline
must be the high-order sort key**, not a nice extra. PlayCanvas's "Material/Mesh" mode is our
primary one.

**2. Dart GC.** Allocations inside a frame are unacceptable. Hence:
- walking the tree every frame to collect draws is a bad idea; we need a **flat registry of
  renderable objects** that the scene maintains on attach/detach;
- the render list is a reusable buffer of mutable records, not a fresh list of objects;
- sort keys are packed into an `int` (64-bit in Dart), and we sort an array of indices rather than
  a list of objects with a closure comparator;
- transforms are read into a supplied `out` vector instead of returning a new one.

**3. There is no compute, so culling is CPU-only.** That means world bounds must be cached and
cheap to invalidate.

---

## 4. The decision taken

**We chose the three.js model: a classic tree with inheritance** — `MeshNode` / `CameraNode` /
`LightNode` extend `SceneNode`.

An important caveat to that choice: inheritance **does not oblige** you to walk the tree every
frame. Babylon keeps a classic hierarchy and, alongside it, flat `scene.meshes` / `lights` /
`cameras` arrays. We did the same: `Scene` maintains registries on attach/detach, so culling is a
linear pass over a contiguous list, and `traverse` remains for user code. This keeps both the
familiar API and the property that matters specifically in Dart.

`SceneNode` stays narrow (only transform, hierarchy, visibility, layer mask), so Babylon's
separation of responsibilities is expressed through inheritance rather than components.

### 4.1 The alternative that was considered: node + components

Neither the pure three.js tree nor a full ECS — something in between:

- `SceneNode` is **only** name, kinship, transform, visibility, layer mask. No geometry, no
  material. This is Babylon's `TransformNode`.
- Renderable geometry, camera and light are **attachments** (components) on a node rather than its
  subclasses. A node could carry both a mesh and a light.
- No ECS machinery: no archetypes, no systems. Components are typed slots.
- **The scene keeps flat registries**: `renderables`, `lights`, `cameras`, updated on
  attach/detach. The renderer iterates them linearly and never walks the tree.

The last point delivers the main ECS benefit (a linear pass over a contiguous list) without its
cost, and answers the GC problem directly.

```dart
final class SceneNode {
  String? name;
  SceneNode? get parent;
  Iterable<SceneNode> get children;

  // TRS changes only through methods: in Dart you cannot intercept mutation of
  // a returned Vector3, and a manual markDirty() is a source of silent bugs.
  void setPosition(double x, double y, double z);
  void setRotation(Quaternion q);
  void setScale(double x, double y, double z);
  void translate(double x, double y, double z);

  // Allocation-free reads.
  Vector3 readPosition([Vector3? out]);

  Matrix4 get worldMatrix;   // always valid, see 4.2
  int get worldVersion;

  bool visible;
  int layerMask;             // a bitmask, like three.js layers

  void add(SceneNode child);
  void remove(SceneNode child);
  void attach(SceneNode child);  // reparenting that preserves the world transform
}
```

### 4.2 Versions instead of dirty flags

three.js and Babylon require a separate update pass (`updateMatrixWorld`) or an explicit
`computeWorldMatrix`. Forgetting it is the classic mistake that costs a frame of latency.

We propose a **version counter**: a node has `_localVersion` and a remembered
`_seenParentVersion`. When accessed, the `worldMatrix` getter compares the parent's version with
the remembered one and recomputes on a mismatch, recursing upwards.

Properties:
- a separate update pass is **not needed at all** — a stale transform is structurally impossible;
- changing a node does not require walking its subtree (unlike a push-down flag);
- the cost of a query is O(depth) in the worst case, and normally O(1) thanks to the cache;
- `worldVersion` gives free invalidation of everything derived from it: world bounds, the camera's
  view matrix, the inverse matrix for normals.

### 4.3 The camera: projection separate from placement

```dart
sealed class Projection {
  Matrix4 toMatrix(double aspect);
}
final class PerspectiveProjection implements Projection { double fovY, near, far; }
final class OrthographicProjection implements Projection { double height, near, far; }

final class CameraComponent {
  Projection projection;
  // The view matrix comes from the node: worldMatrix.inverted(), cached by worldVersion.
}
```

The camera is a component on a node, so it parents like everything else: a camera in an aircraft
cockpit is just a child node. Controllers (orbit, fly, first-person) drive **a node** rather than a
camera, which is why the same orbit controller is fine for swinging a light source around a model.

`perspectiveZeroToOne` from `projection.dart` becomes the implementation of
`PerspectiveProjection.toMatrix` — the `[0, 1]` depth convention stays in a single place, and the
unit tests keep pinning it down.

### 4.4 RenderView — what makes multi-view free

The entity the renderer accepts instead of "a camera and dimensions":

```dart
final class RenderView {
  CameraComponent camera;
  Rect viewportFraction;   // normalised, as in Babylon
  int layerMask;           // what this camera sees
  int priority;            // ordering between cameras, as in PlayCanvas
  ClearSettings clear;
  RenderTargetSpec target; // size, MSAA, formats
}
```

This gives us for free: split-screen, a mini-map, rendering into a texture for reflections, and
later shadow passes (a light's camera is also a `RenderView`).

### 4.5 The render list and packed sort keys

```dart
// Pooled and reused between frames.
final class DrawItem {
  GpuMesh mesh;
  Material material;
  Matrix4 worldMatrix;
  double viewDepth;
  bool flipWinding;
}
```

The sort key is packed into a single `int` and sorted as an array of indices:

```
opaque:      [ drawBucket:8 | pipelineId:12 | materialId:20 | depth:24 ]  → ascending
transparent: [ drawBucket:8 |        invDepth:24 | pipelineId:12       ]  → farthest first
```

The pipeline as the high-order field is a direct consequence of AOT shaders (§3.1). Depth is
quantised into 24 bits, which is more than enough for draw ordering.

Sort modes are borrowed from PlayCanvas as **a setting**, not as a policy: `stateThenDepth`,
`backToFront`, `frontToBack`, `manual`, `none`.

### 4.6 Layers

Start small: a bitmask on the node (three.js) plus a mask on `RenderView`, and derive the
opaque/transparent split from the material's `AlphaMode` — that is, PlayCanvas sublayers without a
`LayerComposition` object. A full ordered layer list will be needed together with post-processing;
it can be added then.

### 4.7 Asset versus instance

The separation that is missing today and is sorely needed:

- `ModelAsset` — meshes, materials and textures uploaded to the GPU. Immutable, reusable, cached.
- `asset.instantiate(scene, parent)` — builds nodes and attachments. One model can stand in the
  scene as many times as you like, sharing `GpuMesh` and textures.

The glTF decoder already reuses `MeshData` across nodes; this restores that advantage at the GPU
level and, along the way, preserves the glTF hierarchy that `GpuModel` currently loses.

### 4.8 The frame flow

```
for each RenderView in ascending priority:
  1. aspect from the viewport → projection.toMatrix
  2. view = camera.node.worldMatrix.inverted()   (cached by worldVersion)
  3. extract the frustum
  4. a linear pass over scene.renderables:
       visible? layerMask matched? world sphere inside the frustum? → append DrawItem
  5. compute keys, sort indices
  6. walk the sorted order: bindPipeline only on a change, uniforms per draw
  7. present
```

Not a single tree traversal and not a single allocation in steps 4–6.

---

## 5. What will have to be rewritten

| Now | Becomes |
|---|---|
| `GpuModel` / `GpuDraw` | `ModelAsset` + `instantiate()`; `GpuDraw` → `MeshRenderable` (a component) |
| The camera and `spinMatrix` in `render()` | `CameraComponent` on a node + a controller; rotation is scene-node animation |
| `perspectiveZeroToOne` | `PerspectiveProjection.toMatrix` (the same maths, the same tests) |
| Light as a constant in `render()` | `LightComponent` in the scene registry |
| `render(width, height, model, …)` | `render(scene, view)` |
| Fitting the camera to the model bounds | `OrbitController.frameAll(scene)` |

The geometry layer and the glTF decoder are untouched — they already sit below the scene and do
not depend on it. That, in fact, was the point of isolating them.

---

## 6. Order of work

1. `SceneNode` with transform versions + `attach`/`add`/`remove`. Tests without a GPU: transform
   composition, world preservation on reparenting, version-based invalidation, absence of stale
   matrices.
2. `Scene` with flat component registries.
3. `CameraComponent` + `Projection`; move the projection matrix and its tests over.
4. `OrbitController` + the Flutter gesture bridge (P1 from the plan, layer 4).
5. `RenderView` and the switch to `Renderer.render(scene, view)` — the renderer starts accepting a
   scene, still with a single view for now.
6. Frustum culling + world bounds cached by `worldVersion`.
7. The render list with packed keys and sort modes.
8. `LightComponent`, multiple light sources.
9. `ModelAsset.instantiate` and restoration of the glTF hierarchy.

Steps 1–3 are self-contained and immediately remove the hard-coded camera. Step 4 brings
interactivity, after which the demo starts to make sense.

---

## 7. Open questions

- **Layers now or later.** A bitmask costs almost nothing, an ordered layer list is noticeably more
  expensive. The proposal is a mask now, the list together with post-processing.
- **Transform animation.** ~~It arrives in layer 8~~ — done. The version counters turned out to be
  exactly the right hook-up point: the player writes TRS through `setPosition` / `setRotation` /
  `setScale` and everything derived refreshes itself, so there is no update pass to order against
  the animation. Tracks address nodes by index into the decoded model's hierarchy, and
  `ModelInstance` carries the index-to-node map.
- **Multithreading.** Culling and sorting in an isolate is tempting, but then `SceneNode` must not
  be a graph of references. We are not committing to it yet, though flat registries do not close
  that path off.


---

## 8. What has been implemented

Steps 1–7 from §6, except BVH culling and full-blown layers:

- `SceneNode` with version counters instead of dirty flags, `add`/`attach`/`remove`, cycle
  protection, `lookAt` and `setLocalForward`;
- `Scene` with flat `meshes`/`lights`/`cameras` registries;
- `MeshNode` with world bounds and a mirroring flag, both cached by `worldVersion`;
- `CameraNode` + `Projection` (`PerspectiveProjection`, `OrthographicProjection`), with the view
  matrix cached by `worldVersion`;
- `LightNode` (directional / point / spot), direction taken from local -Z;
- `OrbitController` + the Flutter gesture bridge (drag / scroll / pinch / pan);
- `RenderView` with a normalised viewport, a layer mask, a priority and sort modes; the renderer
  accepts a list of views;
- `RenderList` with frustum culling, an opaque/transparent split and sort keys packed into a 64-bit
  int;
- `ModelAsset` + `instantiate()` — the asset/instance separation;
- tonemapping (Khronos PBR Neutral) and exposure — these surfaced as a consequence of the camera
  becoming controllable: a GGX highlight at a grazing angle produced 8375 pixels of pure white, and
  after tonemapping there are none.

Since then, and covered by their own sections above: CPU raycasting, the debug line overlay, and
`ModelAsset.instantiate` rebuilding the decoded hierarchy rather than flattening it — which is
what animation needed, because a track says "move node 7" and node 7 has to carry its subtree.

Not done: ordered layers (only a bitmask so far), multiple light sources in the shader, BVH.

---

## 9. Less static, more abstractions

A separate pass done on request: static methods were replaced with polymorphic types.

| Was | Became | What it buys |
|---|---|---|
| `Primitives` with 8 static methods + a free `revolve()` | `Shape` with `CuboidShape`, `SphereShape`, `LatheShape`, … implementations | A shape became **a value**: it can be stored, passed around, overridden with your own implementation. `ProceduralSource` now holds a `Shape` rather than a closure |
| `perspectiveZeroToOne()` / `orthographicZeroToOne()` | the maths inside `PerspectiveProjection.toMatrix` / `OrthographicProjection.toMatrix` | The depth convention lives in one polymorphic place, with no second copy to drift |
| the free function `projectToNdc()` | a method on `Projection` | Behaviour can be checked through the abstraction itself |
| `GltfAccessorReader._readComponent` / `_readIntComponent` | `GltfComponentType.readDouble` / `readInt` | The rules (size, asymmetric normalisation of signed types) are properties of the component type itself |
| `GltfLoader._toTriangleList(mode, …)` | `GltfPrimitiveMode.toTriangleList()` + `isTriangles` | The switch became exhaustive by construction |
| `checkerboardRgba8()` / `whiteRgba8()` + a static in the widget | `ProceduralTexture` with `CheckerboardTexture`, `SolidColorTexture` | The upload path is written once, pixel generation is testable separately |
| `Material.sortId` with a static counter | `MaterialSortIds`, owned by `RenderList` | Removed global mutable static state — the worst kind of static for tests |

Deliberately left as is: the private `SceneNode._versionCounter` (the version counter must be
global, otherwise reparenting between nodes with matching numbers goes unnoticed — this is covered
by a test) and factory constructors (`ModelAsset.fromMesh`, `Renderer.create`), which are idiomatic
in Dart.

Along the way `BoxShape` was renamed to `CuboidShape`: `flutter/material.dart` exports its own
`BoxShape`, and the name clash would force every application to resolve an import conflict.
