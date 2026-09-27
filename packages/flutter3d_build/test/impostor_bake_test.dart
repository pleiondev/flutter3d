/// `C4`: an octahedral impostor, baked here on the software rasteriser and
/// drawn through the engine's own `ImpostorVertex`/`Impostor` stages on the
/// same device — `impostor-forest` measured against the meshes it stands in
/// for, at the distance the chain switches to it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A tree of three parts — a brown trunk, a green cone of a crown and a red
/// ball hung off one side of it — as a document of one node, the shape a
/// converter hands the bake. The ball is what makes the tree look different
/// from each side: a card that picked its views mirrored, or from the wrong
/// side, puts it on the wrong side of the trunk.
PlainModelDocument tree() {
  final trunk = const CylinderShape(
    radiusTop: 0.12,
    radiusBottom: 0.18,
    height: 1.2,
    segments: 12,
  ).build(layout: VertexLayout.standard);
  final crown = const CylinderShape(
    radiusTop: 0.0,
    radiusBottom: 0.9,
    height: 2.2,
    segments: 16,
  ).build(layout: VertexLayout.standard);
  return PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        mesh: trunk.transformed(Matrix4.translationValues(0, 0.6, 0)),
        materialIndex: 0,
        name: 'trunk',
      ),
      ModelSurface(
        mesh: crown.transformed(Matrix4.translationValues(0, 2.2, 0)),
        materialIndex: 1,
        name: 'crown',
      ),
      ModelSurface(
        mesh: const SphereShape(radius: 0.4, segments: 12, rings: 8)
            .build(layout: VertexLayout.standard)
            .transformed(Matrix4.translationValues(0.95, 1.5, 0)),
        materialIndex: 2,
        name: 'fruit',
      ),
    ],
    materials: <SurfaceMaterial>[
      SurfaceMaterial(name: 'bark', baseColor: Vector4(0.45, 0.3, 0.18, 1)),
      SurfaceMaterial(name: 'leaves', baseColor: Vector4(0.25, 0.6, 0.2, 1)),
      SurfaceMaterial(name: 'fruit', baseColor: Vector4(0.85, 0.15, 0.1, 1)),
    ],
    nodes: <ModelNode>[
      ModelNode(name: 'tree', surfaces: <int>[0, 1, 2]),
    ],
  );
}

CpuDevice cpuDevice(int side) => CpuDevice(
  width: side,
  height: side,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// Where the forest stands: five trees in a loose row, each turned about its
/// own up axis so the atlas is read from five different directions.
const List<(double, double, double)> kForest = <(double, double, double)>[
  (-7.0, 0.0, 0.3),
  (-3.5, 2.0, 1.4),
  (0.0, -1.0, 2.6),
  (3.5, 1.5, 4.0),
  (7.0, -0.5, 5.3),
];

/// The forest from [distance], drawn by [plant], which puts one tree at a
/// placement into the scene.
Future<Uint8List> forest(
  CpuDevice device,
  double distance,
  void Function(Scene scene, Matrix4 placement) plant,
) async {
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      LightNode(type: LightType.directional, castsShadow: false)
        ..intensity = 2.5
        ..setLocalForward(Vector3(-0.4, -1.0, -0.5)),
    );
  for (final (x, z, yaw) in kForest) {
    plant(scene, Matrix4.translationValues(x, 0, z)..rotateY(yaw));
  }
  final camera = CameraNode(
    name: 'forest',
    projection: PerspectiveProjection(
      fovYRadians: 40 * math.pi / 180,
      near: 0.5,
      far: distance * 4,
    ),
  )..setPosition(0, 4, distance);
  camera.lookAt(Vector3(0, 1.6, 0));
  scene.add(camera);
  final result = renderer.render(
    width: device.width,
    height: device.height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.6, 0.7, 0.9, 1)),
    ],
    settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
  );
  final pixels = await device.readPixels(result.frame);
  return Uint8List.fromList(pixels!.buffer.asUint8List());
}

TextureHandle upload(CpuDevice device, EncodedImage image) {
  final decoded = decodePng(image.bytes)!;
  return device.createTextureFromPixels(
    width: decoded.width,
    height: decoded.height,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(decoded.rgba),
  )!;
}

void main() {
  late ModelDocument baked;
  late ModelImpostor impostor;
  late double switchFraction;

  setUpAll(() async {
    baked = await bakeImpostors(tree(), cell: 32);
    final lod = baked.nodes.single.lods.single;
    impostor = lod.impostor!;
    switchFraction = lod.maxScreenFraction;
  });

  test('the bake adds two atlases and an impostor level', () {
    expect(baked.images, hasLength(2));
    expect(impostor.grid, kImpostorGrid);
    expect(impostor.radius, greaterThan(1.5));
    expect(impostor.radius, lessThan(2.5));

    final albedo = decodePng(baked.images[impostor.albedoImage].bytes)!;
    final normals = decodePng(baked.images[impostor.normalDepthImage].bytes)!;
    expect(albedo.width, 32 * kImpostorGrid);
    expect(normals.width, 32 * kImpostorGrid);

    // Every view drew the tree, and none of them filled its cell.
    for (var row = 0; row < kImpostorGrid; row++) {
      for (var column = 0; column < kImpostorGrid; column++) {
        var covered = 0;
        for (var y = 0; y < 32; y++) {
          for (var x = 0; x < 32; x++) {
            final at = ((row * 32 + y) * albedo.width + column * 32 + x) * 4;
            if (albedo.rgba[at + 3] > 0) covered++;
          }
        }
        expect(covered, greaterThan(20), reason: 'view $column, $row');
        expect(covered, lessThan(32 * 32 * 0.8), reason: 'view $column, $row');
      }
    }

    // The view nearest the front: its camera stands on +Z, so +X is the
    // right of its picture and the ball hung on +X shows there, and up is up.
    var front = (0, 0);
    var best = -2.0;
    for (var row = 0; row < kImpostorGrid; row++) {
      for (var column = 0; column < kImpostorGrid; column++) {
        final along = impostorViewDirection(column, row).z;
        if (along > best) (best, front) = (along, (column, row));
      }
    }
    var redLeft = 0, redRight = 0, greenTop = 0, greenBottom = 0;
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        final at = ((front.$2 * 32 + y) * albedo.width + front.$1 * 32 + x) * 4;
        if (albedo.rgba[at + 3] == 0) continue;
        final r = albedo.rgba[at], g = albedo.rgba[at + 1];
        if (r > 150 && g < 100) x < 16 ? redLeft++ : redRight++;
        if (g > 120 && r < 120) y < 16 ? greenTop++ : greenBottom++;
      }
    }
    expect(redRight, greaterThan(redLeft), reason: 'the ball is on +X');
    expect(greenTop, greaterThan(greenBottom), reason: 'the crown is on top');
  });

  test('an impostor level survives the .f3d round trip', () {
    final read = F3dDocument.parse(F3dWriter(baked).write());
    final lod = read.nodes.single.lods.single;
    expect(lod.surfaceIndices, isEmpty);
    expect(lod.maxScreenFraction, closeTo(switchFraction, 1e-6));
    final back = lod.impostor!;
    expect(back.albedoImage, impostor.albedoImage);
    expect(back.normalDepthImage, impostor.normalDepthImage);
    expect(back.grid, impostor.grid);
    expect(back.radius, closeTo(impostor.radius, 1e-5));
    expect((back.centre - impostor.centre).length, lessThan(1e-5));
  });

  test('a placed node bakes its card where its surface draws', () async {
    // The shape a glTF scene walk hands the bake: the node carries the
    // placement, the surface carries the same placement baked into its
    // `transform` as a record of where it ends up, and the vertices are in the
    // node's own space — which is where `instantiate` draws them, at identity
    // under the node, and where the card is drawn too. Applying the surface's
    // transform here as well would place the card twice.
    final placement = Matrix4.compose(
      Vector3(4, 0, -3),
      Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2),
      Vector3.all(2),
    );
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3.zero();
    placement.decompose(translation, rotation, scale);
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          mesh: const SphereShape(radius: 0.3, segments: 12, rings: 8)
              .build(layout: VertexLayout.standard)
              .transformed(Matrix4.translationValues(0.5, 1, 0)),
          transform: placement,
          materialIndex: 0,
        ),
      ],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(baseColor: Vector4(0.8, 0.2, 0.2, 1)),
      ],
      nodes: <ModelNode>[
        ModelNode(
          name: 'placed',
          translation: translation,
          rotation: rotation,
          scale: scale,
          surfaces: <int>[0],
        ),
      ],
    );

    final card = (await bakeImpostors(
      document,
      cell: 8,
    )).nodes.single.lods.single.impostor!;
    // Mutation: build the sphere from `surface.transform`-ed vertices. The
    // centre lands at the placement's image of the ball, (4, 2, -4), and the
    // node then carries it there a second time.
    expect((card.centre - Vector3(0.5, 1, 0)).length, lessThan(1e-3));
    expect(card.radius, closeTo(0.3, 1e-3));
    // And in the model's space that is where the surface draws.
    expect(
      (placement.transformed3(card.centre) - Vector3(4, 2, -4)).length,
      lessThan(1e-3),
    );
  });

  test('a skinned or morphed node keeps its meshes and gets no card', () async {
    // A skinned surface's vertices are in the skeleton's bind space, not the
    // node's, so a card the node places would stand where the character is
    // not — here the node is moved and turned while the skin is not. The
    // morphed one rests at a full weight the bake would not draw. Neither is
    // a picture a distant animated character looks like.
    MeshData ball() => const SphereShape(
      radius: 0.3,
      segments: 12,
      rings: 8,
    ).build(layout: VertexLayout.standard);
    final morphed = ball();
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(mesh: ball(), materialIndex: 0),
        ModelSurface(mesh: ball(), materialIndex: 0, skinIndex: 0),
        ModelSurface(
          mesh: morphed.withMorphTargets(<MorphTarget>[
            MorphTarget(
              vertexCount: morphed.vertexCount,
              positions: Float32List(morphed.vertexCount * 3)
                ..fillRange(0, morphed.vertexCount * 3, 0.5),
            ),
          ]),
          materialIndex: 0,
          morphWeights: <double>[1],
        ),
      ],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(baseColor: Vector4(0.8, 0.2, 0.2, 1)),
      ],
      nodes: <ModelNode>[
        ModelNode(name: 'rock', surfaces: <int>[0]),
        ModelNode(
          name: 'walker',
          translation: Vector3(5, 0, -2),
          rotation: Quaternion.axisAngle(Vector3(0, 1, 0), 1),
          surfaces: <int>[1],
        ),
        ModelNode(name: 'face', surfaces: <int>[2]),
        ModelNode(name: 'hip'),
      ],
      skins: <ModelSkin>[
        ModelSkin(joints: <int>[3], inverseBindMatrices: [Matrix4.identity()]),
      ],
    );

    final messages = <String>[];
    final out = await bakeImpostors(document, cell: 8, report: messages.add);
    // Mutation: drop the skip and both nodes get a card, with four more
    // images and no word of why.
    expect(out.nodes[1].lods, isEmpty, reason: 'the skinned node');
    expect(out.nodes[2].lods, isEmpty, reason: 'the morphed node');
    expect(out.nodes[0].lods.single.impostor, isNotNull);
    expect(out.images, hasLength(2));
    expect(messages, contains(contains('walker: no impostor')));
    expect(messages, contains(contains('face: no impostor')));
    expect(
      messages.singleWhere((m) => m.startsWith('walker')),
      contains('skinned'),
    );
    expect(
      messages.singleWhere((m) => m.startsWith('face')),
      contains('morphed'),
    );

    // The still node beside them bakes the same bytes it bakes alone.
    final alone = await bakeImpostors(
      PlainModelDocument(
        surfaces: <ModelSurface>[document.surfaces[0]],
        materials: document.materials,
        nodes: <ModelNode>[
          ModelNode(name: 'rock', surfaces: <int>[0]),
        ],
      ),
      cell: 8,
    );
    for (var i = 0; i < 2; i++) {
      expect(out.images[i].bytes, alone.images[i].bytes);
    }
  });

  test('a bake leaves nothing on the device it drew with', () async {
    // With a bark texture, so the image the bake decodes has to go too.
    final source = tree();
    final textured = PlainModelDocument(
      surfaces: source.surfaces,
      materials: <SurfaceMaterial>[
        SurfaceMaterial(
          name: 'bark',
          baseColor: Vector4(1, 1, 1, 1),
          baseColorTexture: const TextureBinding(imageIndex: 0),
        ),
        ...source.materials.skip(1),
      ],
      images: <EncodedImage>[
        EncodedImage(
          bytes: encodePng(
            Uint8List.fromList(<int>[
              for (var i = 0; i < 16; i++) ...[115, 77, 46, 255],
            ]),
            4,
            4,
          ),
          mimeType: 'image/png',
        ),
      ],
      nodes: source.nodes,
    );
    final device = RecordingDevice(cpuDevice(8));
    await bakeImpostors(textured, cell: 8, device: device);

    final geometry = <int>{};
    final textures = <int>{};
    var uploads = 0;
    for (final event in device.events) {
      switch (event) {
        case TraceUploadGeometry(:final id):
          uploads++;
          geometry.add(id);
        case TraceReleaseGeometry(:final buffer):
          geometry.remove(buffer);
        case TraceCreateTexture(:final id) ||
            TraceCreateTextureFromPixels(:final id) ||
            TraceCreateCubeTextureFromPixels(:final id) ||
            TraceCreateCubeRenderTarget(:final id):
          textures.add(id);
        case TraceReleaseTexture(:final texture):
          textures.remove(texture);
        default:
      }
    }
    // Mutations: drop the release of the node's meshes and twelve buffers
    // stay; skip `Renderer.dispose` and its own two do; upload a depth copy
    // once a view, as the bake first did, and 384 do.
    expect(geometry, isEmpty, reason: 'geometry buffers never released');
    expect(textures, isEmpty, reason: 'textures never released');
    // Two buffers for each of the tree's three surfaces and its three depth
    // copies, plus the few the renderer makes for itself — not a depth copy
    // for each of sixty-four views, even one released straight after.
    expect(uploads, lessThan(3 * 2 * 2 + 16));
  });

  test('impostor-forest matches the meshes at the switch distance', () async {
    const side = 256;
    // Where a tree covers exactly the fraction its chain switches at — the
    // screen fraction `LodGroup.screenFraction` measures, radius over the half
    // height of the view at the tree's distance.
    final distance =
        impostor.radius / (math.tan(20 * math.pi / 180) * switchFraction);

    final meshDevice = cpuDevice(side);
    final meshes = <DeviceMesh>[
      for (final s in baked.surfaces) DeviceMesh.upload(meshDevice, s.mesh),
    ];
    final full = await forest(meshDevice, distance, (scene, placement) {
      final holder = SceneNode()..setLocalMatrix(placement);
      for (var i = 0; i < meshes.length; i++) {
        holder.add(
          MeshNode(
            meshes[i],
            Material(
              lighting: LightingModel.lambert,
              baseColor: baked.materials[i].baseColor.clone(),
            ),
          ),
        );
      }
      scene.add(holder);
    });

    final cardDevice = cpuDevice(side);
    final albedo = upload(cardDevice, baked.images[impostor.albedoImage]);
    final normalDepth = upload(
      cardDevice,
      baked.images[impostor.normalDepthImage],
    );
    final cards = await forest(cardDevice, distance, (scene, placement) {
      scene.add(
        ImpostorNode(
          cardDevice,
          albedo: albedo,
          normalDepth: normalDepth,
          centre: impostor.centre,
          radius: impostor.radius,
        )..setLocalMatrix(placement),
      );
    });

    final empty = await forest(cpuDevice(side), distance, (_, _) {});

    bool drawn(Uint8List frame, int i) =>
        (frame[i * 4] - empty[i * 4]).abs() +
            (frame[i * 4 + 1] - empty[i * 4 + 1]).abs() +
            (frame[i * 4 + 2] - empty[i * 4 + 2]).abs() >
        24;

    var union = 0;
    var differ = 0;
    var both = 0;
    var colourError = 0.0;
    for (var i = 0; i < side * side; i++) {
      final a = drawn(full, i), b = drawn(cards, i);
      if (a || b) union++;
      if (a != b) differ++;
      if (a && b) {
        both++;
        for (var c = 0; c < 3; c++) {
          colourError += (full[i * 4 + c] - cards[i * 4 + c]).abs();
        }
      }
    }

    // Five trees of a few hundred pixels each: something to compare.
    expect(union, greaterThan(500), reason: 'nothing to compare');
    // The silhouette: a card baked from 64 directions and blended between
    // three of them is within a fifth of the meshes' outline, most of it a
    // pixel's rim round a tree a few dozen pixels tall.
    expect(
      differ / union,
      lessThan(0.15),
      reason: '$differ of $union pixels differ',
    );
    // The colour, where both drew: the same albedo and lit by the same sun
    // through baked normals, so within a few steps a channel.
    expect(
      colourError / (both * 3),
      lessThan(16),
      reason: 'mean ${colourError / (both * 3)} a channel over $both pixels',
    );
  });
}
