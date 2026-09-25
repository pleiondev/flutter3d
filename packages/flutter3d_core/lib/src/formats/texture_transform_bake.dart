/// `KHR_texture_transform`, applied where this engine can apply it: to the
/// texture coordinates, once, when a surface is handed to the device.
///
/// **Why the vertices and not the sampler.** The extension is a matrix per
/// texture, and honouring it in full means a matrix per texture slot in the
/// material's uniform block, which four backends have agreed the layout of.
/// What an atlas export actually writes is one transform repeated on every
/// texture of a material, because the atlas moved all of the material's maps by
/// the same amount. That case needs no uniform at all: the same numbers
/// applied to the coordinates give the same picture, and they are applied here.
/// A material whose textures disagree is the case that does need the uniform,
/// and [sharedTextureTransform] says so by returning null; the layered model
/// has one — `C8`, `Material.textureTransforms` — and so does a material whose
/// offset a clip moves, since coordinates fixed at upload cannot follow it.
///
/// **Not in the decoder**, which is the first place anybody would put it. A
/// decoded document keeps both the coordinates the file had and the transform
/// it named, so that writing it out again gives the file back. Coordinates
/// rewritten there would go out beside the transform that had already been
/// applied to them, and the next reader would apply it twice.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../geometry/mesh_data.dart';
import '../geometry/vertex_layout.dart';
import 'surface_material.dart';

/// The one transform every texture of [material] asks for, or null.
///
/// Null when no texture names one, which is every file without the extension,
/// and null when two textures name different ones, since a single set of
/// coordinates cannot satisfy both. A texture that names none beside one that
/// does counts as disagreeing: it asked for the identity.
TextureTransform? sharedTextureTransform(SurfaceMaterial material) {
  final bindings = _texturesOf(material);
  final first = bindings.firstOrNull?.transform;
  if (first == null || first.isIdentity) return null;
  return bindings.every((binding) => binding.transform?.sameAs(first) ?? false)
      ? first
      : null;
}

/// Whether the textures of [material] name transforms that cannot all be
/// honoured by one set of coordinates — the case a caller warns about.
bool hasConflictingTextureTransforms(SurfaceMaterial material) =>
    sharedTextureTransform(material) == null &&
    _texturesOf(
      material,
    ).any((binding) => !(binding.transform?.isIdentity ?? true));

List<TextureBinding> _texturesOf(SurfaceMaterial material) => <TextureBinding>[
  ?material.baseColorTexture,
  ?material.metallicRoughnessTexture,
  ?material.normalTexture,
  ?material.occlusionTexture,
  ?material.emissiveTexture,
];

/// [mesh] with [transform] applied to its texture coordinates.
///
/// The extension's own order, which is the order its sample shader multiplies
/// in: scale, then rotation, then offset. Returns [mesh] itself when it has no
/// coordinates to move.
///
/// **Counter-clockwise as the texture is seen, with `v` running down.** The
/// matrix the extension's text prints turns the other way in that space, and
/// its sample asset marks that reading as wrong; a quarter turn here sends
/// `+u` to `-v`, which is up the image.
///
/// **The tangent turns with the texture.** A tangent is the direction in which
/// `u` increases across the surface, so rotating the coordinates leaves it
/// pointing along an axis the normal map no longer uses, and lighting that was
/// right goes wrong in a way that looks like a bad bake. It is rebuilt from the
/// old tangent and bitangent. That is exact where the texture is stretched
/// evenly both ways and close elsewhere, because a unit tangent has already
/// forgotten how long its axis was. A mirror, which a negative scale on one
/// axis is, flips the handedness in `w`.
MeshData withTextureTransform(MeshData mesh, TextureTransform transform) {
  final layout = mesh.layout;
  final uvOffset = layout.floatOffsetOf(VertexLayout.texcoord.name);
  if (uvOffset < 0) return mesh;

  final stride = layout.floatsPerVertex;
  final cosine = math.cos(transform.rotation);
  final sine = math.sin(transform.rotation);
  final scaleX = transform.scale.x;
  final scaleY = transform.scale.y;
  final out = Float32List.fromList(mesh.vertices);

  for (var o = 0; o < out.length; o += stride) {
    final u = out[o + uvOffset] * scaleX;
    final v = out[o + uvOffset + 1] * scaleY;
    out[o + uvOffset] = transform.offset.x + cosine * u + sine * v;
    out[o + uvOffset + 1] = transform.offset.y - sine * u + cosine * v;
  }

  final tangentOffset = layout.floatOffsetOf(VertexLayout.tangent.name);
  final normalOffset = layout.floatOffsetOf(VertexLayout.normal.name);
  final turnsTangent =
      tangentOffset >= 0 &&
      normalOffset >= 0 &&
      (sine != 0.0 || scaleX < 0.0 || scaleY < 0.0) &&
      scaleX != 0.0 &&
      scaleY != 0.0;
  if (turnsTangent) {
    final mirrored = (scaleX < 0.0) != (scaleY < 0.0);
    for (var o = 0; o < out.length; o += stride) {
      final t = o + tangentOffset;
      final n = o + normalOffset;
      final tx = out[t], ty = out[t + 1], tz = out[t + 2], w = out[t + 3];
      final nx = out[n], ny = out[n + 1], nz = out[n + 2];
      // The bitangent the shader would build: `cross(normal, tangent) * w`.
      final bx = (ny * tz - nz * ty) * w;
      final by = (nz * tx - nx * tz) * w;
      final bz = (nx * ty - ny * tx) * w;
      // Where `u'` increases: the first column of the inverse of the 2x2,
      // `(m11 dP/du - m10 dP/dv) / det`. The bitangent is **minus** dP/dv,
      // because `v` runs down the texture and a normal map's green up it —
      // `withGeneratedTangents` builds it so — which is what turns the
      // `+sine` in `m10` negative here.
      final alongT = cosine / scaleX;
      final alongB = -sine / scaleY;
      final rx = tx * alongT + bx * alongB;
      final ry = ty * alongT + by * alongB;
      final rz = tz * alongT + bz * alongB;
      final length = math.sqrt(rx * rx + ry * ry + rz * rz);
      if (length < 1e-12) continue;
      out[t] = rx / length;
      out[t + 1] = ry / length;
      out[t + 2] = rz / length;
      if (mirrored) out[t + 3] = -w;
    }
  }

  return MeshData(
    layout: layout,
    vertices: out,
    indices: mesh.indices,
    morphTargets: mesh.morphTargets,
    // The positions and the order of the triangles are untouched, so the
    // boxes and cones still describe them — `C9`.
    clusters: mesh.clusters,
  );
}
