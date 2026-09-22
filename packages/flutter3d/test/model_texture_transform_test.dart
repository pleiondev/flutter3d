/// An atlas-packed model draws its own corner of the atlas.
///
///     flutter test test/model_texture_transform_test.dart
///
/// `KHR_texture_transform` was decoded and read by nothing, so a model whose
/// materials had been packed into one image drew every surface sampling the
/// whole of it. `ModelAsset` honours the common case by moving the texture
/// coordinates of what it uploads, and what these hold is the two ways that
/// could go wrong without anybody seeing: the document being changed under a
/// caller who means to write it out again, and two materials on one mesh
/// getting each other's coordinates.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/model_asset.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_core/src/engine/geometry/device_mesh.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

MeshData _quad() => MeshData(
  layout: VertexLayout.positionNormalTexcoord,
  vertices: Float32List.fromList(<double>[
    // position, normal, texcoord
    0, 0, 0, 0, 0, 1, 0, 0,
    1, 0, 0, 0, 0, 1, 1, 0,
    1, 1, 0, 0, 0, 1, 1, 1,
    0, 1, 0, 0, 0, 1, 0, 1,
  ]),
  indices: Uint32List.fromList(<int>[0, 1, 2, 0, 2, 3]),
);

SurfaceMaterial _packedInto(Vector2 corner) => SurfaceMaterial(
  baseColorTexture: TextureBinding(
    imageIndex: 0,
    transform: TextureTransform(offset: corner, scale: Vector2(0.5, 0.5)),
  ),
);

List<(double, double)> _uvsOf(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final at = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
  return <(double, double)>[
    for (var o = 0; o < mesh.vertices.length; o += stride)
      (mesh.vertices[o + at], mesh.vertices[o + at + 1]),
  ];
}

void main() {
  test(
    'what is uploaded samples its corner, and the document is as it was',
    () async {
      final quad = _quad();
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          ModelSurface(
            mesh: quad,
            transform: Matrix4.identity(),
            materialIndex: 0,
          ),
        ],
        materials: <SurfaceMaterial>[_packedInto(Vector2(0.5, 0.0))],
      );

      final asset = await ModelAsset.fromDocument(
        document,
        device: FakeBackend(),
      );

      expect(_uvsOf(asset.parts.single.mesh.source!), <(double, double)>[
        (0.5, 0.0),
        (1.0, 0.0),
        (1.0, 0.5),
        (0.5, 0.5),
      ]);
      // A caller that writes this document out again writes the coordinates the
      // file had beside the transform it named. Moved coordinates beside that
      // transform would be read back and moved a second time.
      expect(_uvsOf(quad).last, (0.0, 1.0));
      expect(document.surfaces.single.mesh, same(quad));
    },
  );

  test(
    'one mesh under two packed materials is uploaded once for each',
    () async {
      final quad = _quad();
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          for (final material in <int>[0, 1, 0])
            ModelSurface(
              mesh: quad,
              transform: Matrix4.identity(),
              materialIndex: material,
            ),
        ],
        materials: <SurfaceMaterial>[
          _packedInto(Vector2(0.0, 0.0)),
          _packedInto(Vector2(0.5, 0.5)),
        ],
      );

      final asset = await ModelAsset.fromDocument(
        document,
        device: FakeBackend(),
      );
      final meshes = <DeviceMesh>[for (final part in asset.parts) part.mesh];

      expect(_uvsOf(meshes[0].source!).first, (0.0, 0.0));
      expect(_uvsOf(meshes[1].source!).first, (0.5, 0.5));
      expect(meshes[2], same(meshes[0]), reason: 'same mesh, same material');
      expect(meshes[1], isNot(same(meshes[0])));
    },
  );

  test(
    'a model that names no transform shares its upload as it always did',
    () async {
      final quad = _quad();
      final document = PlainModelDocument(
        surfaces: <ModelSurface>[
          for (final material in <int?>[0, 1, null])
            ModelSurface(
              mesh: quad,
              transform: Matrix4.identity(),
              materialIndex: material,
            ),
        ],
        materials: <SurfaceMaterial>[SurfaceMaterial(), SurfaceMaterial()],
      );

      final asset = await ModelAsset.fromDocument(
        document,
        device: FakeBackend(),
      );

      expect(<DeviceMesh>{
        for (final part in asset.parts) part.mesh,
      }, hasLength(1));
      expect(asset.parts.first.mesh.source, same(quad));
    },
  );
}
