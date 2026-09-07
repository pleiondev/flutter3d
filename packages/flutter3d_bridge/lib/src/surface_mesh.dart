/// The twenty lines where the simulation's triangles become the engine's.
///
/// **One copy, because there are two producers now.** `BrushSurface` is what
/// `flutter3d_sim` emits for anything it can describe as triangles — the level's
/// brushes since it existed, and terrain since a `Heightfield` learned to build
/// its own — and its own doc says the application interleaves them into
/// whatever layout it draws with. That was true while there was one caller.
/// With two it stops being true: the paragraph below is a note about a GPU
/// failure that produces no error at all, and a second copy of it is a second
/// copy that will not be updated.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

/// Interleaves the level package's plain arrays into the engine's layout.
///
/// The level package deliberately does not know what a vertex layout is, so
/// the two halves meet here and nowhere else.
///
/// It has to be [VertexLayout.standard] and not a shorter one. flutter_gpu
/// takes the layout from the vertex shader's `in` declarations, and
/// `mesh.vert` declares position, normal, texcoord, tangent **and** colour —
/// sixteen floats. Supplying eight does not fail: the GPU keeps reading at
/// the stride the shader expects and assembles each vertex from two of the
/// ones actually written, which draws a convincing field of garbage
/// triangles and no error anywhere.
MeshData meshDataOf(BrushSurface surface) {
  const layout = VertexLayout.standard;
  final stride = layout.floatsPerVertex;
  final vertices = Float32List(surface.vertexCount * stride);

  for (var i = 0; i < surface.vertexCount; i++) {
    final out = i * stride;
    vertices[out] = surface.positions[i * 3];
    vertices[out + 1] = surface.positions[i * 3 + 1];
    vertices[out + 2] = surface.positions[i * 3 + 2];
    vertices[out + 3] = surface.normals[i * 3];
    vertices[out + 4] = surface.normals[i * 3 + 1];
    vertices[out + 5] = surface.normals[i * 3 + 2];
    vertices[out + 6] = surface.texcoords[i * 2];
    vertices[out + 7] = surface.texcoords[i * 2 + 1];
    vertices[out + 8] = surface.tangents[i * 4];
    vertices[out + 9] = surface.tangents[i * 4 + 1];
    vertices[out + 10] = surface.tangents[i * 4 + 2];
    vertices[out + 11] = surface.tangents[i * 4 + 3];
    // Vertex colour multiplies the material's, so white leaves it alone —
    // unless the level has a lightmap, when the lightmapped vertex stage
    // reads the first two channels as the vertex's place in it and holds
    // the tint at white itself. See `mesh_lightmapped.vert`.
    final lightmapUvs = surface.lightmapUvs;
    vertices[out + 12] = lightmapUvs?[i * 2] ?? 1.0;
    vertices[out + 13] = lightmapUvs?[i * 2 + 1] ?? 1.0;
    vertices[out + 14] = 1.0;
    vertices[out + 15] = 1.0;
  }

  return MeshData(layout: layout, vertices: vertices, indices: surface.indices);
}
