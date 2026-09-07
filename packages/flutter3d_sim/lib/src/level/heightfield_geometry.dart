/// Triangles for a [Heightfield], in the vocabulary the bridge already reads.
///
/// **A [BrushSurface] and not a new type.** The name is the one its first
/// producer earned and terrain is not a brush, but what the type actually holds
/// is plain arrays — positions, normals, texcoords, tangents, indices — and the
/// twenty lines in `flutter3d_bridge` that interleave them into a vertex layout
/// do not care where the triangles came from. Emitting the same thing means the
/// bridge needs no line of new code to draw ground, which is worth more than a
/// tidier name.
///
/// **The diagonal is the one `Heightfield` fixed**, `(0,0)–(1,1)`. That is not
/// a preference: the field answers "how high is the surface here" by finding
/// the triangle under the point, so a builder that split the quad the other way
/// would draw a surface the field does not describe, and the only symptom would
/// be a body standing slightly off the ground it appears to be on.
///
/// **Shading normals here, face normals there.** `Heightfield.normalAt` returns
/// the triangle's own normal because that is the face a body rests on; this
/// averages across neighbours instead, because ground drawn with face normals
/// is a field of visible facets. The two disagreeing is the point rather than
/// an oversight — one answers "what am I standing on", the other "what does it
/// look like".
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'brush.dart';
import 'brush_surface.dart';
import 'heightfield.dart';

/// Turns a field of heights into the triangles that draw it.
final class HeightfieldGeometry {
  /// Builds the geometry maker.
  const HeightfieldGeometry();

  /// One surface for the whole field.
  ///
  /// [metresPerTexture] is how far the ground goes before its material repeats,
  /// so a map's texture density is a number in metres rather than a guess about
  /// how many samples a field happens to have.
  BrushSurface build(
    Heightfield field, {
    required String material,
    double metresPerTexture = 8.0,
    ShadowCasting shadowCasting = ShadowCasting.on,
  }) {
    final int columns = field.columns;
    final int rows = field.rows;
    final int vertices = columns * rows;

    final positions = Float32List(vertices * 3);
    final normals = Float32List(vertices * 3);
    final texcoords = Float32List(vertices * 2);
    final tangents = Float32List(vertices * 4);

    final double cell = field.cellSize;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final int v = row * columns + column;
        final double x = field.origin.x + column * cell;
        final double z = field.origin.z + row * cell;
        final double y = field.sample(column, row);

        positions[v * 3] = x;
        positions[v * 3 + 1] = y;
        positions[v * 3 + 2] = z;

        // Central differences, clamped at the rim: the slope across a sample
        // is the drop from one neighbour to the other, and at the edge the
        // sample itself stands in for the neighbour that is not there.
        final double dx =
            field.sample(math.min(column + 1, columns - 1), row) -
            field.sample(math.max(column - 1, 0), row);
        final double dz =
            field.sample(column, math.min(row + 1, rows - 1)) -
            field.sample(column, math.max(row - 1, 0));
        final double spanX =
            (math.min(column + 1, columns - 1) - math.max(column - 1, 0)) *
            cell;
        final double spanZ =
            (math.min(row + 1, rows - 1) - math.max(row - 1, 0)) * cell;

        var nx = -dx * spanZ;
        var ny = spanX * spanZ;
        var nz = -dz * spanX;
        final double length = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= length;
        ny /= length;
        nz /= length;
        normals[v * 3] = nx;
        normals[v * 3 + 1] = ny;
        normals[v * 3 + 2] = nz;

        texcoords[v * 2] = x / metresPerTexture;
        texcoords[v * 2 + 1] = z / metresPerTexture;

        // Along +X, laid on the surface: the slope of the ground under the
        // texture's u axis. Handedness is constant because the mapping is.
        var tx = spanX;
        var ty = dx;
        final double tLength = math.sqrt(tx * tx + ty * ty);
        tx /= tLength;
        ty /= tLength;
        tangents[v * 4] = tx;
        tangents[v * 4 + 1] = ty;
        tangents[v * 4 + 2] = 0.0;
        tangents[v * 4 + 3] = 1.0;
      }
    }

    // Two triangles a quad, wound so that the ground faces the sky, and both
    // sharing the diagonal the field splits on.
    final indices = Uint32List((columns - 1) * (rows - 1) * 6);
    var i = 0;
    for (var row = 0; row < rows - 1; row++) {
      for (var column = 0; column < columns - 1; column++) {
        final int v00 = row * columns + column;
        final int v10 = v00 + 1;
        final int v01 = v00 + columns;
        final int v11 = v01 + 1;

        indices[i++] = v00;
        indices[i++] = v11;
        indices[i++] = v10;

        indices[i++] = v00;
        indices[i++] = v01;
        indices[i++] = v11;
      }
    }

    return BrushSurface(
      material: material,
      shadowCasting: shadowCasting,
      positions: positions,
      normals: normals,
      texcoords: texcoords,
      tangents: tangents,
      indices: indices,
    );
  }
}
