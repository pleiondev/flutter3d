# Sources of the test models

Most models in this directory are **not ours**. They are here as test
fixtures, chosen to cover the different loading paths. Each licence below
was read from the model's `metadata.json` in
[KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets)
on 2026-10-12.

| File | Author or owner | Licence |
|---|---|---|
| `Box.glb`, `BoxAnimated.glb`, `BoxTextured.glb`, `RiggedSimple.glb`, `RiggedFigure.glb` | Cesium, 2017 | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); the Cesium logo in `BoxTextured` is a trademark and not licensed |
| `NormalTangentMirrorTest.glb` | Ed Mackey, Analytical Graphics, Inc., 2018 | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `NormalTangentTest.glb` | Ed Mackey, Analytical Graphics, Inc., 2018 | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `BoxVertexColors.glb`, `Triangle.gltf`, `simple_skin/SimpleSkin.gltf` | Marco Hutter | CC0 1.0 |
| `cube/Cube.gltf` + `.bin`, `animated_cube/AnimatedCube.gltf` + `.bin` + `_BaseColor.png` | Norbert Nopper, UX3D, 2017 | CC0 1.0 |
| `InterpolationTest.glb` | Khronos, 2017 | CC0 1.0 |
| `AnimatedMorphCube.glb` | Microsoft, 2017 | CC0 1.0 |
| `RobotExpressive.glb` | [Tomás Laulhé](https://www.patreon.com/quaternius), with facial morph targets added by [Don McCurdy](https://donmccurdy.com/); taken from [three.js examples](https://github.com/mrdoob/three.js/tree/dev/examples/models/gltf/RobotExpressive) | CC0 1.0 |
| `teapot.obj`, `teapot.stl` | The Utah teapot (Martin Newell, 1975), tessellated by `tool/make_teapot.py` in this package from the Bezier patches three.js carries in `TeapotGeometry.js` | the patch table under three.js' MIT licence (its notice is in the script); the tessellation is this repository's, MIT |
| `f3d/*.f3d` | Conversions of the models above by `flutter3d_build:convert` | the licence of the model each was made from |
| `radiance/*`, `ktx2/*` | Written for the fixtures with ImageMagick and `basisu` (`radiance/PROVENANCE.md`) | this repository's, MIT |

The CC BY 4.0 models owe credit: the owner named above and a link to the
licence. This table is that credit, and it ships with the package.

`teapot.stl` is the same triangles as `teapot.obj`, written by the same
script in the form `StlWriter` gives. It is `qa-08`'s own STL fixture:
`fmt-09`'s decoder tested through `fmt-06`'s writer round trip against a
model with real curvature, not only the synthetic edge cases
`flutter3d_formats/test/fixtures/stl/` holds. Until 2026-10-12 both teapot
files came from a repository that declares no licence; the tessellation is
the same classic one (six segments a patch edge, 2256 triangles), so the
shape did not change, only where it comes from.

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

`RobotExpressive` is the only model here that is **rigged and morphing at
once**, and it is not from Khronos because Khronos has no such model: all 150
samples in that collection were read, and every one that carries morph targets
carries no skin. This one has a skeleton, fourteen clips, and a head split
across three primitives that share one set of three expressions — which is also
the case that makes a node's weights reach several meshes at once.

**Its weights channels are all zeros**, and that is the author's doing rather
than a defect: three.js drives these expressions from code, and the clips exist
to leave them alone. So the frame this model is recorded in sets the weights by
hand and lets the clip move the bones — which is the more useful picture
anyway, because it is the one where morphing and skinning have to agree about
the order they happen in.

The two normal-tangent models are the same geometry with and without authored
`TANGENT` data, which makes them the only direct check available on the tangent
generator: the mirror variant's tangents come from a real exporter, so comparing
against them is comparing against the rest of the ecosystem rather than against
our own derivation.

The files in `f3d/` are those same models converted by `dart run flutter3d_build:convert`
into the engine's own container. They are derived works of the sources above and
carry the same licences.

The full texts are at the links in the table; the licence of each Khronos
model is also in its own directory upstream, as `LICENSE.md`.
