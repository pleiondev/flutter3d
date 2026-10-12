/// The model a new viewer project opens on: a small trophy of three parts,
/// written as a GLB when the project is made.
///
/// **Made here rather than shipped as a file.** This package is read as Dart
/// by `dart run flutter3d_build:create`, with no bundle to carry a binary in,
/// and a model made from the engine's own shapes by the engine's own glTF
/// writer is one a test can hold to the decoder that will read it. It is a
/// stand-in: the project's README says to drop a model of one's own into
/// `assets_src/` and name it in `lib/main.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

/// The viewer's starting model as a `.glb`: a dark base, a gold ring and a
/// red gem, each a named node of its own so a tap can say which part it hit.
Uint8List viewerModelGlb() {
  final parts =
      <
        ({
          String name,
          Shape shape,
          Vector3 at,
          Quaternion turn,
          SurfaceMaterial material,
        })
      >[
        (
          name: 'base',
          shape: const CylinderShape(
            radiusTop: 0.42,
            radiusBottom: 0.5,
            height: 0.24,
          ),
          at: Vector3(0.0, 0.12, 0.0),
          turn: Quaternion.identity(),
          material: SurfaceMaterial(
            name: 'base',
            baseColor: LinearColor.fromSrgb(0.16, 0.17, 0.2),
            roughness: 0.55,
          ),
        ),
        (
          name: 'ring',
          shape: const TorusShape(radius: 0.36, tubeRadius: 0.07),
          at: Vector3(0.0, 0.72, 0.0),
          turn: Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
          material: SurfaceMaterial(
            name: 'gold',
            baseColor: LinearColor.fromSrgb(1.0, 0.77, 0.34),
            metallic: 1.0,
            roughness: 0.25,
          ),
        ),
        (
          name: 'gem',
          shape: const SphereShape(radius: 0.2),
          at: Vector3(0.0, 0.72, 0.0),
          turn: Quaternion.identity(),
          material: SurfaceMaterial(
            name: 'gem',
            baseColor: LinearColor.fromSrgb(0.86, 0.16, 0.2),
            roughness: 0.15,
          ),
        ),
      ];
  final document = PlainModelDocument(
    surfaces: <ModelSurface>[
      for (final (i, part) in parts.indexed)
        ModelSurface(
          mesh: part.shape.build(),
          materialIndex: i,
          name: part.name,
          meshName: part.name,
        ),
    ],
    materials: <SurfaceMaterial>[for (final part in parts) part.material],
    nodes: <ModelNode>[
      for (final (i, part) in parts.indexed)
        ModelNode(
          name: part.name,
          translation: part.at,
          rotation: part.turn,
          surfaces: <int>[i],
        ),
    ],
  );
  return GltfWriter(document).writeGlb();
}
