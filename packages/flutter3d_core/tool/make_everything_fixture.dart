/// Writes `test/fixtures/v2/everything.f3d`: a `.f3d` holding every section
/// kind the engine writes.
///
///     dart run tool/make_everything_fixture.dart
///
/// `v2/bundle.f3d` plus a clustered mesh with variants, a level with a
/// measured error, an impostor, a pointer track, extras on a node, a
/// material, a clip and the document, the asset's rights, a physical
/// material carried whole and a tool's section flagged safe-to-copy, which
/// makes it a version 2 file. It refuses to write when a kind in
/// `F3dSection.known` is missing.
///
/// **Minted once on 2026-10-15 and never again.** The fixture is what a 1.0
/// converter wrote; running this later writes what that later build writes,
/// which is the wrong file to hold a reader to. Kept to say how it was made.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final bundle = F3dDocument.parse(
    File('test/fixtures/v2/bundle.f3d').readAsBytesSync(),
  );
  final sphere = const SphereShape(radius: 1.0, segments: 8, rings: 4).build();
  final triangles = sphere.triangleCount;
  final firstIndices = Uint32List.fromList(<int>[
    for (var t = 0; t < triangles; t += 16) t * 3,
    triangles * 3,
  ]);
  final clustered = MeshData(
    layout: sphere.layout,
    vertices: sphere.vertices,
    indices: sphere.indices,
    clusters: MeshClusters.measure(
      layout: sphere.layout,
      vertices: sphere.vertices,
      indices: sphere.indices,
      firstIndices: firstIndices,
    ),
  );
  final box = bundle.surfaces.first;
  final surfaces = <ModelSurface>[
    ...bundle.surfaces,
    ModelSurface(
      mesh: clustered,
      materialIndex: 0,
      name: 'ball',
      meshName: 'ball',
      variantMaterials: <int, int>{0: 1, 1: bundle.materials.length},
    ),
    ModelSurface(mesh: box.mesh, materialIndex: 0, name: 'ball.lod1'),
  ];
  final ball = bundle.surfaces.length;
  final materials = <SurfaceMaterial>[
    ...bundle.materials,
    SurfaceMaterial(
      name: 'foam',
      physicalMaterial: 'acme.foam',
      materialVersion: 2,
      extras: <String, Object?>{'note': 'every section'},
    ),
  ];
  final nodes = <ModelNode>[
    for (final node in bundle.nodes)
      ModelNode(
        name: node.name,
        translation: node.translation,
        rotation: node.rotation,
        scale: node.scale,
        children: <int>[
          ...node.children,
          if (identical(node, bundle.nodes.first)) bundle.nodes.length,
        ],
        surfaces: node.surfaces,
        extras: node.extras,
        lightIndex: node.lightIndex,
        cameraIndex: node.cameraIndex,
        lods: node.lods,
      ),
    ModelNode(
      name: 'ball',
      surfaces: <int>[ball],
      extras: <String, Object?>{'tag': 'ball'},
      lods: <ModelLod>[
        ModelLod(
          surfaceIndices: <int>[ball + 1],
          maxScreenFraction: 0.25,
          error: 0.0125,
        ),
        ModelLod.impostor(
          impostor: ModelImpostor(
            albedoImage: 0,
            normalDepthImage: 0,
            grid: 4,
            center: Vector3(0.0, 0.5, 0.0),
            radius: 1.5,
          ),
          maxScreenFraction: 0.05,
        ),
      ],
    ),
  ];
  final document = PlainModelDocument(
    surfaces: surfaces,
    materials: materials,
    images: bundle.images,
    nodes: nodes,
    skins: bundle.skins,
    lights: bundle.lights,
    cameras: bundle.cameras,
    asset: DocumentAsset(
      generator: 'flutter3d fixture',
      copyright: '© 2026 flutter3d',
      author: 'flutter3d',
      license: 'CC0-1.0',
      extras: <String, Object?>{'minted': '2026-10-15'},
    ),
    variants: const <String>['day', 'night'],
    animations: <AnimationClip>[
      ...bundle.animations,
      AnimationClip(
        name: 'glow',
        extras: <String, Object?>{'markers': <Object?>[]},
        tracks: <AnimationTrack>[
          AnimationTrack(
            nodeIndex: -1,
            path: AnimationPath.pointer,
            interpolation: AnimationInterpolation.linear,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(<double>[0.2, 0.8]),
            componentCount: 1,
            pointer: AnimationPointer.parse(
              '/materials/0/pbrMetallicRoughness/roughnessFactor',
            ),
          ),
        ],
      ),
    ],
  );
  final bytes = F3dWriter(
    document,
    programs: bundle.programs,
    prefabs: bundle.prefabs,
    files: bundle.files,
    physicalMaterials: <String, Map<String, Object?>>{
      'acme.foam': <String, Object?>{
        'format': 'f3d.physicalMaterial',
        'version': 2,
        'id': 'acme.foam',
        'name': 'Packing foam',
        'phase': 'solid',
        'mechanical': <String, Object?>{'density': 30.0, 'source': 'a sheet'},
      },
    },
    extraSections: <F3dExtraSection>[
      ...bundle.extraSections,
      F3dExtraSection(
        kind: f3dVendorKindStart + 9,
        bytes: Uint8List.fromList('copy me\u0000'.codeUnits),
        flags: F3dSectionFlags.safeToCopy,
      ),
    ],
  ).write();
  final read = F3dDocument.parse(bytes);
  final view = ByteData.sublistView(bytes);
  final kinds = <int>{
    for (var i = 0; i < view.getUint32(8, Endian.little); i++)
      view.getUint32(
        f3dHeaderBytes + i * view.getUint32(12, Endian.little),
        Endian.little,
      ),
  };
  final missing = F3dSection.known.difference(kinds);
  stdout.writeln('version ${read.version}, kinds $kinds, missing $missing');
  if (missing.isNotEmpty) exit(1);
  File('test/fixtures/v2/everything.f3d').writeAsBytesSync(bytes);
}
