/// The one hand-built document every writer's test shares.
///
///     dart test test/plain_model_document_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('every field defaults to empty, nodes included', () {
    const document = PlainModelDocument();
    expect(document.surfaces, isEmpty);
    expect(document.materials, isEmpty);
    expect(document.images, isEmpty);
    // Mutation: leave `nodes` off the constructor and it falls back to
    // ModelDocument's own "one node per surface" — zero here either way, so
    // this line alone would not catch it; the round-trip in
    // `document_compare_test.dart` and `obj_writer_test.dart` is what
    // actually depends on an empty default rather than a computed one.
    expect(document.nodes, isEmpty);
    expect(document.animations, isEmpty);
    expect(document.skins, isEmpty);
    expect(document.warnings, isEmpty);
  });

  test('every field keeps exactly what it was given', () {
    final surface = ModelSurface(
      mesh: MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List(0),
        indices: Uint32List(0),
      ),
      transform: Matrix4.identity(),
    );
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[surface],
      warnings: const <String>['one thing skipped'],
    );
    expect(document.surfaces, <ModelSurface>[surface]);
    expect(document.warnings, <String>['one thing skipped']);
  });
}
