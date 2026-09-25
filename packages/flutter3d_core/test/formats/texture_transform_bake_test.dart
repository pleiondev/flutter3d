/// `KHR_texture_transform`, honoured in the coordinates.
///
///     dart test test/formats/texture_transform_bake_test.dart
///
/// The numbers here are the extension's own: a coordinate is scaled, then
/// turned counter-clockwise as the image is seen, with `v` running down it,
/// then moved. Every expectation below is that worked by hand rather than this
/// file's arithmetic run a second time, and the tangent is held to the one
/// `withGeneratedTangents` derives from the moved coordinates.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One vertex at the origin facing +Z, tangent along +X, at [u], [v].
MeshData _vertex(double u, double v) => MeshData(
  layout: VertexLayout.positionNormalTexcoordTangent,
  vertices: Float32List.fromList(<double>[
    0, 0, 0, // position
    0, 0, 1, // normal
    u, v, // texcoord
    1, 0, 0, 1, // tangent, right-handed
  ]),
  indices: Uint32List(0),
);

({double u, double v}) _uvOf(MeshData mesh) {
  final at = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
  return (u: mesh.vertices[at], v: mesh.vertices[at + 1]);
}

Vector4 _tangentOf(MeshData mesh) {
  final at = mesh.layout.floatOffsetOf(VertexLayout.tangent.name);
  final f = mesh.vertices;
  return Vector4(f[at], f[at + 1], f[at + 2], f[at + 3]);
}

TextureBinding _bound([TextureTransform? transform]) =>
    TextureBinding(imageIndex: 0, transform: transform);

void main() {
  group('the coordinates', () {
    test('are scaled and then moved, which is what an atlas does', () {
      final moved = withTextureTransform(
        _vertex(1.0, 1.0),
        TextureTransform(offset: Vector2(0.5, 0.25), scale: Vector2(0.5, 0.25)),
      );
      final uv = _uvOf(moved);
      expect(uv.u, closeTo(1.0, 1e-6));
      expect(uv.v, closeTo(0.5, 1e-6));
    });

    test('turn counter-clockwise as seen: a quarter turn sends +u to -v', () {
      // `v` runs down the image, so -v is up it: +u, to the right, turned a
      // quarter counter-clockwise points up. The matrix the extension's text
      // prints sends it to +v, down, and the extension's own test asset marks
      // that as the wrong way round.
      final moved = withTextureTransform(
        _vertex(1.0, 0.0),
        TextureTransform(rotation: math.pi / 2),
      );
      final uv = _uvOf(moved);
      expect(uv.u, closeTo(0.0, 1e-6));
      expect(uv.v, closeTo(-1.0, 1e-6));
    });

    test('are scaled before they are turned, and moved after both', () {
      // (1, 0) scaled by (2, 3) is (2, 0); a quarter turn makes it (0, -2);
      // the offset makes it (10, 18). Any other order gives a different answer:
      // offset first would turn the offset too.
      final moved = withTextureTransform(
        _vertex(1.0, 0.0),
        TextureTransform(
          offset: Vector2(10.0, 20.0),
          scale: Vector2(2.0, 3.0),
          rotation: math.pi / 2,
        ),
      );
      final uv = _uvOf(moved);
      expect(uv.u, closeTo(10.0, 1e-5));
      expect(uv.v, closeTo(18.0, 1e-5));
    });

    test('leave the source alone', () {
      final source = _vertex(0.25, 0.75);
      withTextureTransform(source, TextureTransform(offset: Vector2(1.0, 1.0)));
      expect(_uvOf(source), (u: 0.25, v: 0.75));
    });

    test('a mesh with none comes back as itself', () {
      final bare = MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List.fromList(<double>[0, 0, 0]),
        indices: Uint32List(0),
      );
      expect(
        withTextureTransform(bare, TextureTransform(offset: Vector2(1.0, 0.0))),
        same(bare),
      );
    });
  });

  group('the tangent', () {
    test('stays where it was when the texture only moves and scales', () {
      final moved = withTextureTransform(
        _vertex(0.5, 0.5),
        TextureTransform(offset: Vector2(0.5, 0.0), scale: Vector2(0.5, 0.5)),
      );
      expect(_tangentOf(moved), Vector4(1.0, 0.0, 0.0, 1.0));
    });

    test('turns with the texture', () {
      // Normal +Z and tangent +X make the bitangent +Y, which is where `v`
      // decreases. After a quarter turn the new `u` is the old `v`, so it
      // increases along -Y on the surface.
      final moved = withTextureTransform(
        _vertex(0.5, 0.5),
        TextureTransform(rotation: math.pi / 2),
      );
      final tangent = _tangentOf(moved);
      expect(tangent.x, closeTo(0.0, 1e-6));
      expect(tangent.y, closeTo(-1.0, 1e-6));
      expect(tangent.z, closeTo(0.0, 1e-6));
      expect(tangent.w, 1.0);
    });

    test('is the one the moved coordinates generate, turned any way', () {
      // A quad facing +Z whose `v` runs down it, as glTF's does, so the
      // generator gives tangent +X and bitangent +Y. Moved at an angle that is
      // not a quarter turn, with the stretch even both ways where the turned
      // unit tangent is exact, the tangent carried through the transform has
      // to be the one the moved coordinates give from scratch.
      final quad = MeshData(
        layout: VertexLayout.positionNormalTexcoordTangent,
        vertices: Float32List.fromList(<double>[
          -1, -1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, //
          1, -1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, //
          1, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, //
          -1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, //
        ]),
        indices: Uint32List.fromList(<int>[0, 1, 2, 0, 2, 3]),
      );
      for (final rotation in <double>[0.7, math.pi / 2, 2.5, -1.2]) {
        final moved = withTextureTransform(
          quad,
          TextureTransform(
            offset: Vector2(0.3, -0.1),
            scale: Vector2(2.0, 2.0),
            rotation: rotation,
          ),
        );
        final carried = _tangentOf(moved);
        final generated = _tangentOf(moved.withGeneratedTangents());
        // Mutation: turning the bitangent term's sign (`alongB = +sine /
        // scaleY`), or the coordinates the other way, puts the carried
        // tangent the rotation's double away from the generated one.
        expect(carried.x, closeTo(generated.x, 1e-5), reason: '$rotation');
        expect(carried.y, closeTo(generated.y, 1e-5), reason: '$rotation');
        expect(carried.z, closeTo(generated.z, 1e-5), reason: '$rotation');
        expect(carried.w, generated.w, reason: '$rotation');
      }
    });

    test('changes hands when the texture is mirrored on one axis', () {
      final moved = withTextureTransform(
        _vertex(0.5, 0.5),
        TextureTransform(scale: Vector2(-1.0, 1.0)),
      );
      final tangent = _tangentOf(moved);
      expect(tangent.x, closeTo(-1.0, 1e-6));
      expect(tangent.w, -1.0);
    });

    test('keeps its hand when the texture is mirrored on both', () {
      final moved = withTextureTransform(
        _vertex(0.5, 0.5),
        TextureTransform(scale: Vector2(-1.0, -1.0)),
      );
      expect(_tangentOf(moved).w, 1.0);
    });
  });

  group('which transform a material shares', () {
    final atlas = TextureTransform(
      offset: Vector2(0.5, 0.0),
      scale: Vector2(0.5, 0.5),
    );
    final sameNumbers = TextureTransform(
      offset: Vector2(0.5, 0.0),
      scale: Vector2(0.5, 0.5),
    );
    final other = TextureTransform(offset: Vector2(0.0, 0.5));

    test('none, for a material whose file never named the extension', () {
      final material = SurfaceMaterial(baseColorTexture: _bound());
      expect(sharedTextureTransform(material), isNull);
      expect(hasConflictingTextureTransforms(material), isFalse);
    });

    test('the one every texture names, compared by its numbers', () {
      final material = SurfaceMaterial(
        baseColorTexture: _bound(atlas),
        normalTexture: _bound(sameNumbers),
      );
      expect(sharedTextureTransform(material), same(atlas));
      expect(hasConflictingTextureTransforms(material), isFalse);
    });

    test('none when two textures name different ones, and that is said', () {
      final material = SurfaceMaterial(
        baseColorTexture: _bound(atlas),
        normalTexture: _bound(other),
      );
      expect(sharedTextureTransform(material), isNull);
      expect(hasConflictingTextureTransforms(material), isTrue);
    });

    test('none when one texture names one and another names nothing', () {
      // The second asked for the identity by saying nothing, and coordinates
      // moved for the first would be wrong for it.
      final material = SurfaceMaterial(
        baseColorTexture: _bound(atlas),
        emissiveTexture: _bound(),
      );
      expect(sharedTextureTransform(material), isNull);
      expect(hasConflictingTextureTransforms(material), isTrue);
    });

    test('an extension given no fields moves nothing and conflicts with '
        'nothing', () {
      final material = SurfaceMaterial(
        baseColorTexture: _bound(TextureTransform()),
        normalTexture: _bound(),
      );
      expect(sharedTextureTransform(material), isNull);
      expect(hasConflictingTextureTransforms(material), isFalse);
    });
  });
}
