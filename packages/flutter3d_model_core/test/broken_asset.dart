/// The asset `test/fixtures/broken_asset.glb` is written from — a crate and
/// its lid as a careless generator would hand them over.
///
/// **Broken on purpose, one fault per check `AssetAudit` makes**, each with a
/// number a test can hold it to:
///
///   * written in centimetres: the crate is 100 × 180 × 100 and the lid sits
///     10 above it, so the asset is 190 across and reads as 1.90 m in cm;
///   * off its pivot: the base centre is at (100, 20, 0), not the origin;
///   * one material exported twice, as "Material" and "Material.001";
///   * one triangle naming a corner twice through a second, coincident vertex
///     entry — no area once welded;
///   * one fin glued to an edge two faces of the box already share.
///
/// Every other face is wound outward, so the only thing the weld has to turn
/// round is nothing, and a flipped count other than zero is a fault in the
/// fixture rather than in the audit.
///
/// Kept in source for the reason `fixture_project.dart` gives: the file is a
/// blob, and what makes it a test is knowing what should come out of it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

const double _x0 = 50, _x1 = 150, _y0 = 20, _y1 = 200, _z0 = -50, _z1 = 50;

/// [positions] as a position-and-normal buffer, every normal straight up —
/// the audit reads positions only, and a normal the loader would recompute
/// is a normal nothing here depends on.
MeshData _mesh(List<List<double>> positions, List<int> indices) => MeshData(
  layout: VertexLayout.positionNormal,
  vertices: Float32List.fromList(<double>[
    for (final List<double> p in positions) ...<double>[...p, 0, 1, 0],
  ]),
  indices: Uint32List.fromList(indices),
);

MeshData _crate() => _mesh(
  <List<double>>[
    <double>[_x0, _y0, _z0], // 0
    <double>[_x1, _y0, _z0], // 1
    <double>[_x1, _y1, _z0], // 2
    <double>[_x0, _y1, _z0], // 3
    <double>[_x0, _y0, _z1], // 4
    <double>[_x1, _y0, _z1], // 5
    <double>[_x1, _y1, _z1], // 6
    <double>[_x0, _y1, _z1], // 7
    // The fin's third corner, inside the box so the bounds stay the box's.
    <double>[100, 100, 0], // 8
    // Corner 2 again, a second entry at the identical position.
    <double>[_x1, _y1, _z0], // 9
  ],
  <int>[
    0, 3, 2, 0, 2, 1, // -z
    4, 5, 6, 4, 6, 7, // +z
    0, 1, 5, 0, 5, 4, // -y
    3, 7, 6, 3, 6, 2, // +y
    0, 4, 7, 0, 7, 3, // -x
    1, 2, 6, 1, 6, 5, // +x
    0, 1, 8, // the fin: a third face on edge 0–1
    2, 9, 3, // corner 2 twice once welded
  ],
);

MeshData _lid() => _mesh(
  <List<double>>[
    <double>[_x0, 210, _z0],
    <double>[_x1, 210, _z0],
    <double>[_x1, 210, _z1],
    <double>[_x0, 210, _z1],
  ],
  <int>[0, 3, 2, 0, 2, 1],
);

SurfaceMaterial _grey(String name) => SurfaceMaterial(
  name: name,
  baseColor: Vector4(0.5, 0.5, 0.5, 1.0),
  roughness: 0.5,
);

/// The project the fixture is written from.
ModelProject brokenAsset() =>
    ModelProject(
          materials: <ProjectMaterial>[
            ProjectMaterial(surface: _grey('Material')),
            ProjectMaterial(surface: _grey('Material.001')),
          ],
        )
        .added(
          (int id) => ModelObject(
            id: id,
            name: 'crate',
            geometry: ImportedGeometry(_crate()),
            transform: Matrix4.identity(),
            materialSlots: const <int>[0],
          ),
        )
        .added(
          (int id) => ModelObject(
            id: id,
            name: 'lid',
            geometry: ImportedGeometry(_lid()),
            transform: Matrix4.identity(),
            materialSlots: const <int>[1],
          ),
        );
