# Sources of the test models

The models in this directory are **not ours**. They are here as test fixtures,
chosen to cover the different loading paths.

| File | Source |
|---|---|
| `Box.glb`, `BoxTextured.glb`, `BoxVertexColors.glb`, `Triangle.gltf`, `cube/Cube.gltf` + `cube/Cube.bin` | [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) |
| `teapot.obj` | [mauricelam/Teapot](https://github.com/mauricelam/Teapot) — the Utah teapot |

Why these specifically: between them they cover all three ways glTF can carry its
data (a binary chunk in GLB, an embedded base64 buffer, an external `.bin`), plus
vertex colours, an embedded PNG texture, and an OBJ with no normals and no
materials at all.

**Check the licences in the upstream repositories before redistributing any of
this.** They are not reproduced here because the Khronos files carry different
licences per model, and the teapot's has to be checked separately.
