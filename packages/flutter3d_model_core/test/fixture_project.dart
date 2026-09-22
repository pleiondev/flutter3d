/// The project every format fixture is minted from.
///
/// **One project, named here, so that a fixture from three versions ago can be
/// read against the same expectations as one minted today.** A fixture is a
/// file; what makes it a test is knowing what should come out of it, and that
/// belongs in source rather than in a comment beside a blob.
///
/// It holds one of everything the container has a place for, because a fixture
/// that exercised only the easy half would go on passing while the other half
/// stopped working: a shape that still knows its parameters, a mesh that has
/// been edited, buffers that arrived from a file, a child hanging off a parent,
/// a material shared by two objects, an image one of them samples, and an
/// object added and deleted so that `nextId` is ahead of the count.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

/// Every parameter off the constructor's default, so a field dropped on the way
/// through the file shows up as itself rather than as the number it would have
/// had anyway.
const ParametricCylinder fixtureCylinder = ParametricCylinder(
  radiusTop: 0.25,
  radiusBottom: 0.75,
  height: 2.5,
  segments: 12,
  capped: false,
);

/// Three positions and one triangle: small enough to write down, and distinct
/// in every slot so a float read from the wrong offset is the wrong number
/// rather than a zero that could have been anything.
MeshData fixtureImported() => MeshData(
  layout: VertexLayout.positionNormal,
  vertices: Float32List.fromList(<double>[
    0.5, 1.5, 2.5, 0, 0, 1, //
    3.5, 4.5, 5.5, 0, 1, 0, //
    6.5, 7.5, 8.5, 1, 0, 0, //
  ]),
  indices: Uint32List.fromList(<int>[0, 1, 2]),
);

/// The project the fixtures hold.
ModelProject fixtureProject() {
  final project =
      ModelProject(
            // Pinned rather than left at the constructor's default: the v1
            // fixture was minted when that default was 128, and a later
            // change to the default — `doc-13` lowered it to `Skeleton`'s
            // shader limit of 64 — must not quietly change what this fixture
            // is asserted to hold. The file says 128; so must this.
            profile: const ProjectProfile(maxJoints: 128),
            materials: <ProjectMaterial>[
              ProjectMaterial(
                version: 3,
                surface: SurfaceMaterial(
                  name: 'brass',
                  baseColor: Vector4(0.8, 0.6, 0.2, 1.0),
                  metallic: 0.75,
                  roughness: 0.125,
                  baseColorTexture: const TextureBinding(
                    imageIndex: 0,
                    sampling: TextureSampling(
                      useMipmaps: false,
                      wrapS: TextureWrap.clampToEdge,
                    ),
                  ),
                  alphaMode: SurfaceAlphaMode.mask,
                  alphaCutoff: 0.875,
                  doubleSided: true,
                ),
              ),
            ],
            images: <EncodedImage>[
              EncodedImage(
                bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
                name: 'atlas',
                mimeType: 'image/png',
              ),
            ],
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'body',
              geometry: ParametricGeometry(fixtureCylinder),
              transform: Matrix4.translationValues(1, 2, 3),
              materialSlots: const <int>[0],
            ),
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'lid',
              geometry: EditedGeometry(EditMesh.cuboid(size: Vector3(2, 1, 3))),
              transform: Matrix4.translationValues(0, 4, 0),
              parent: 1,
              materialSlots: const <int>[0],
            ),
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'arrived',
              geometry: ImportedGeometry(fixtureImported()),
              transform: Matrix4.rotationY(0.6),
            ),
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'doomed',
              geometry: ParametricGeometry(const ParametricSphere()),
              transform: Matrix4.identity(),
            ),
          )
          .removed(4);

  // A second version on one object, so a file that wrote 1 everywhere would be
  // caught rather than agreeing with the default.
  return project.withObject(project.objects[1].copyWith(name: 'lid'));
}
