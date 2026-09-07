# Sources of the test models

The models in this directory are **not ours**. They are here as test fixtures,
chosen to cover the different loading paths.

| File | Source |
|---|---|
| `Box.glb`, `BoxTextured.glb`, `BoxVertexColors.glb`, `Triangle.gltf`, `cube/Cube.gltf` + `cube/Cube.bin` | [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) |
| `BoxAnimated.glb`, `InterpolationTest.glb`, `animated_cube/AnimatedCube.gltf` + `.bin` + `_BaseColor.png` | [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) |
| `NormalTangentTest.glb`, `NormalTangentMirrorTest.glb` | [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) |
| `RiggedSimple.glb`, `RiggedFigure.glb`, `simple_skin/SimpleSkin.gltf` | [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) |
| `AnimatedMorphCube.glb` | [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets), CC0-1.0 |
| `teapot.obj` | [mauricelam/Teapot](https://github.com/mauricelam/Teapot) — the Utah teapot |

Why these specifically: between them they cover all three ways glTF can carry its
data (a binary chunk in GLB, an embedded base64 buffer, an external `.bin`), plus
vertex colours, an embedded PNG texture, and an OBJ with no normals and no
materials at all.

The animated three were added for the animation layer. `AnimatedCube` is a
single looping rotation, `BoxAnimated` moves a parent node so its child has to
follow, and `InterpolationTest` exists specifically to show `STEP`, `LINEAR` and
`CUBICSPLINE` next to each other — a decoder that treats cubic keys as linear
reads tangents as values, and nothing else in the suite would catch it.

`AnimatedMorphCube` is the morph-target fixture, and it is the smallest thing
that exercises the whole chain: twenty-four vertices, one primitive, **two
targets each carrying POSITION, NORMAL and TANGENT** — so all three rows of the
delta texture are filled rather than two of them being zeros nobody would
notice — default weights on the mesh, and an animation whose only channel is
`weights`. No skin and no textures, so a picture that comes out wrong is wrong
about morphing and not about something else.

The two normal-tangent models are the same geometry with and without authored
`TANGENT` data, which makes them the only direct check available on the tangent
generator: the mirror variant's tangents come from a real exporter, so comparing
against them is comparing against the rest of the ecosystem rather than against
our own derivation.

The files in `f3d/` are those same models converted by `tool/convert_asset.dart`
into the engine's own container. They are derived works of the sources above and
carry the same licences.

**Check the licences in the upstream repositories before redistributing any of
this.** They are not reproduced here because the Khronos files carry different
licences per model, and the teapot's has to be checked separately.
