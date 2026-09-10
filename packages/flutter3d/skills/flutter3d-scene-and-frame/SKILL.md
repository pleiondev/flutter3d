---
name: flutter3d-scene-and-frame
description: Use when drawing with flutter3d from an application — building a scene, loading a model, render settings, picking, and the extension points that replace a fork.
---

# A device, a renderer, a scene, a view

```dart
final device = await openDevice(width: 1280, height: 720);   // flutter3d_backend
final renderer = Renderer.create(device: device);

final scene = Scene();
final camera = CameraNode(projection: PerspectiveProjection(fovYRadians: 0.9));
scene.root.add(camera);
// A light points where its node points: place it and aim the node.
scene.root.add(LightNode(type: LightType.directional, castsShadow: true)
  ..setPosition(4, 6, 4)
  ..lookAt(Vector3.zero()));
scene.root.add(MeshNode(mesh, material));

final view = RenderView(camera: camera);
```

`Renderer.create` takes a `GraphicsDevice` and never learns which backend it
got. A scene node holds a `MeshGeometry` rather than an uploaded mesh, so
bounds, culling, framing and picking work with no device in the process, and
`CpuMesh` is the implementation for geometry that is queried and never drawn.

## Loading a model

`ModelAsset.fromDocument()` is the one upload path for every decoder — mesh and
image deduplication, material conversion — so a new format is a decoder rather
than a change here. Decoding runs on a background isolate, and **file reads stay
on the UI isolate**: a background isolate has a working message channel and no
`ServicesBinding`, which is what `rootBundle` resolves through. Siblings come
back over a port.

Prefer `.f3d` for anything loaded at run time — 4.54 ms as OBJ text against
1.1 us — since its arrays are stored as `MeshData` holds them and loading builds
views rather than copies:

```bash
dart run tool/convert_asset.dart model.glb -o model.f3d
```

## RenderSettings is per frame

Pass a function returning the settings rather than an object captured earlier;
anything derived from where the camera ended up has to be derived after it got
there. Shadows, bloom, fog, sky, reflections, ambient occlusion, exposure and
auto exposure all live there.

The scene renders into `r16g16b16a16Float` and tone mapping happens in a
composite pass, so a clear colour authored display-referred must be converted to
linear or it goes through the encode twice. `wireframe` is Impeller-only:
neither WebGL2 nor WebGPU has a polygon fill mode.

Eight lights reach any one draw. Inside eight, every draw sees the same eight in
scene order; past that, each object gets the eight that actually reach it,
ranked by the attenuation the shader itself computes and tie-broken by scene
order so the picture does not flicker. Switching a light on or off rebuilds no
pipeline.

## Picking

`Raycaster` casts from widget coordinates over the same BVH culling uses:
ray/AABB, ray/sphere, Möller–Trumbore ray/triangle. A skinned or morphed model
is reached through `MeshNode.skinReach` and `MorphState.reach`, so it is still a
candidate and still culled correctly; only the triangle test underneath answers
about the shape before the stage moved it.

`renderer.pickPixel(u, v)` asks the other question — what the GPU actually drew
there — which differs from a ray whenever geometry is deformed on the device.

## Five extension points, so nothing needs a fork

- a `ModelDecoder` for an unknown format, carried on the load request (**not** a
  registry: statics are not shared across isolates, so one filled at startup is
  empty where the decode happens);
- a decoder for a material format;
- `renderer.addContributor(…)` to draw inside the scene pass —
  `ParticleContributor` is the worked example;
- a system added to somebody else's step, in `flutter3d_sim`;
- your own lighting model, passed as `materials:`, which is consulted before the
  backend's so a stage can be replaced as well as added.

## When a frame comes back black

The causes look identical from the picture: viewport and scissor default to a
zero-sized rect; there is no non-indexed draw; a uniform block a shader declares
and never reads is a segfault on Impeller; a clear colour on an HDR target
encodes twice. The `flutter3d-empty-frame` skill has the full list.
