/// `pro-lod-05n`'s own acceptance, measured: "the silhouette at 300 m differs
/// from the mesh by less than 3% of pixels".
///
/// **The row said it was waiting on a scene at three hundred metres. This is
/// that scene.** `flutter3d_model_core` holds the arithmetic and cannot draw;
/// a `CpuDevice` can, headlessly, which is what lets the acceptance be a test
/// rather than a promise. The same dependency direction `render_sheet_test`
/// already runs in.
///
/// **Three percent of the silhouette, not of the frame.** At three hundred
/// metres a two-metre subject is a few dozen pixels however wide the frame
/// is, so "3% of pixels" measured against the whole picture is a number every
/// impostor passes and a mistake nothing catches. What the row is actually
/// about is whether the card reads as the model, so the fraction here is over
/// the union of the two silhouettes.
///
///     dart test test/impostor_card_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart'
    show
        CameraNode,
        MaterialAlphaMode,
        MeshNode,
        PerspectiveProjection,
        RenderSettings,
        RenderView,
        Renderer,
        Scene,
        SurfaceAlphaMode,
        SurfaceMaterial,
        TextureBinding;
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show ParametricCuboid;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// What every frame here is cleared to — a colour nothing in the scene is, so
/// the two silhouettes are measured against the same emptiness. See
/// [coverage] for why that is not the same as keying on this value.
final Vector4 kBackdrop = Vector4(1, 0, 1, 1);

/// How far away the acceptance measures from.
const double kFar = 300;

/// A subject with a silhouette worth matching: a stepped tower, wider at the
/// bottom, so a card that got the scale or the framing wrong is visibly the
/// wrong shape rather than merely the wrong size.
ModelProject subject() {
  var project = const ModelProject();
  const List<(double, double, double)> blocks = <(double, double, double)>[
    (1.4, 0.5, 0.25),
    (1.0, 0.6, 0.85),
    (0.6, 0.9, 1.6),
  ];
  for (final (double wide, double tall, double at) in blocks) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'block$id',
        geometry: ParametricGeometry(
          ParametricCuboid(size: Vector3(wide, tall, wide)),
        ),
        transform: Matrix4.translationValues(0, at, 0),
      ),
    );
  }
  return project;
}

/// The card, as a project of one textured quad standing where [subject] does.
ModelProject cardProject({
  required ImpostorBake bake,
  required ImpostorCard card,
  required double yaw,
  required double centreY,
}) {
  final ImpostorView view = bake.atlas.viewAt(bake.atlas.pick(yaw).view);
  final List<Vector3> corners = card.cornersAt(Vector3(0, centreY, 0), yaw);
  final AtlasCell cell = view.cell;

  // `VertexLayout.standard`, because that is what the mesh vertex shader
  // reads by fixed offset — a layout of position and texcoord alone is a
  // buffer the shader walks off the end of. The normal faces the camera the
  // card faces; it is never shaded, since the material is unlit, but a
  // zero normal would still be a lie in the buffer.
  final Vector3 facing = Vector3(math.sin(yaw), 0, math.cos(yaw));
  final uv = <(double, double)>[
    (cell.x, cell.y + cell.height),
    (cell.x + cell.width, cell.y + cell.height),
    (cell.x + cell.width, cell.y),
    (cell.x, cell.y),
  ];
  final vertices = Float32List.fromList(<double>[
    for (var i = 0; i < 4; i++) ...<double>[
      corners[i].x,
      corners[i].y,
      corners[i].z,
      facing.x,
      facing.y,
      facing.z,
      uv[i].$1,
      uv[i].$2,
      1,
      0,
      0,
      1,
      1,
      1,
      1,
      1,
    ],
  ]);

  final project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'card',
      geometry: ImportedGeometry(
        MeshData(
          vertices: vertices,
          indices: Uint32List.fromList(<int>[0, 1, 2, 0, 2, 3]),
          layout: VertexLayout.standard,
        ),
      ),
      transform: Matrix4.identity(),
      materialSlots: <int>[0],
    ),
  );

  return project.copyWith(
    images: <EncodedImage>[
      EncodedImage(
        bytes: encodePng(bake.rgba, bake.size, bake.size),
        name: 'impostor',
        mimeType: 'image/png',
      ),
    ],
    materials: <ProjectMaterial>[
      ProjectMaterial(
        surface: SurfaceMaterial(
          name: 'impostor',
          baseColorTexture: TextureBinding(imageIndex: 0),
          // The picture was taken lit; lighting it again would shade a flat
          // card by its own normal and turn the silhouette grey.
          unlit: true,
          // A cut-out, not a blend: the card is mostly nothing, and what is
          // being measured is where the something stops.
          alphaMode: SurfaceAlphaMode.mask,
          alphaCutoff: 0.5,
          doubleSided: true,
        ),
      ),
    ],
  );
}

/// Which pixels of [png] differ from [empty], the same frame with nothing in
/// it.
///
/// **Against an empty render rather than against [kBackdrop] itself.** The
/// clear colour is not what lands in the file: tonemapping and the rest of
/// the composite chain run over the whole frame, so keying on the literal
/// magenta marks every pixel as covered and the measurement silently becomes
/// "the two pictures are both pictures" — which is exactly what the first
/// version of this file did, and passed.
List<bool> coverage(Uint8List png, Uint8List empty) {
  final DecodedImage image = decodePng(png)!;
  final DecodedImage bare = decodePng(empty)!;
  return <bool>[
    for (var i = 0; i < image.width * image.height; i++)
      (image.rgba[i * 4] - bare.rgba[i * 4]).abs() +
              (image.rgba[i * 4 + 1] - bare.rgba[i * 4 + 1]).abs() +
              (image.rgba[i * 4 + 2] - bare.rgba[i * 4 + 2]).abs() >
          24,
  ];
}

/// [project] drawn from [kFar] metres away at [yaw], with [frame] metres
/// across the picture.
///
/// **Assembled here rather than through `RenderSnapshotJob`, for one
/// reason.** `sceneFromProject`'s own doc comment says it in bold: *no
/// textures* — a headless picture draws the clay the live viewport shows
/// while its material pool is still filling, because decoding a project's
/// images is asynchronous and content-hashed up in the application. An
/// impostor card with no texture on it is an opaque white rectangle, which
/// is what the first version of this test measured and what made it pass.
/// So the scene comes from the same function, and [texture] is bound onto
/// the card's own material afterwards, on the device that is about to draw
/// it.
Future<Uint8List> shot(
  ModelProject project, {
  required double yaw,
  required double centreY,
  required int side,
  required double frame,
  ImpostorBake? texture,
}) async {
  final GraphicsDevice device = cpuDevice(side, side);
  final Renderer renderer = Renderer.create(
    device: device,
    fallbackNormal: device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[128, 128, 255, 255]),
      ),
    )!,
  );
  final Scene scene = sceneFromProject(project, device);

  if (texture != null) {
    final TextureHandle atlas = device.createTextureFromPixels(
      width: texture.size,
      height: texture.size,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(texture.rgba),
    )!;
    for (final MeshNode node in scene.meshes) {
      node.material
        ..albedo = atlas
        // A cut-out, not a blend: the card is mostly nothing, and what is
        // being measured is where the something stops.
        ..alphaMode = MaterialAlphaMode.mask
        ..alphaCutoff = 0.5;
    }
  }

  final camera = CameraNode(
    name: 'impostor',
    // The field of view that makes [frame] metres fill the picture at
    // [kFar] — the subject is a few dozen pixels, which is the size an
    // impostor is actually looked at.
    projection: PerspectiveProjection(
      fovYRadians: 2 * math.atan(frame / (2 * kFar)),
      near: 1,
      far: kFar * 4,
    ),
  )..setPosition(math.sin(yaw) * kFar, centreY, math.cos(yaw) * kFar);
  camera.lookAt(Vector3(0, centreY, 0));
  scene.add(camera);

  final result = renderer.render(
    width: side,
    height: side,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera, clearColor: kBackdrop)],
    settings: const RenderSettings(),
  );
  return encodePng(
    (await device.readPixels(result.frame))!.buffer.asUint8List(),
    side,
    side,
  );
}

void main() {
  // **Baked from the distance it is shown at.** The perspective is baked
  // into the picture, so a card taken from eight metres and stood at three
  // hundred carries eight metres' worth of convergence into a view that has
  // almost none: measured, that is fourteen percent of the silhouette wrong,
  // against three at the matching distance. What changes with the distance
  // is the field of view, not the range: three metres across the frame is
  // what makes the subject fill the cell.
  const double bakeDistance = kFar;
  const double bakeFrame = 3;
  final double bakeFov = 2 * math.atan(bakeFrame / (2 * bakeDistance));
  const double centreY = 1.1;

  late ImpostorBake bake;
  late ImpostorCard card;

  /// The frame with nothing in it — what `coverage` measures against.
  late Uint8List empty;

  setUpAll(() async {
    bake = await bakeImpostor(
      project: subject(),
      // 192 across three columns is a 64-texel cell, and the card covers
      // about 64 pixels at the distance below — one texel per pixel. **A
      // bigger atlas measures worse here, not better**: minifying 170 texels
      // into 64 pixels through a point sample quantises the silhouette's
      // edge to the atlas grid, which is a pixel of error all the way round
      // an outline that is only a hundred-odd pixels long. An impostor is
      // baked for the size it is shown at.
      atlas: ImpostorAtlas(size: 192),
      centre: Vector3(0, centreY, 0),
      distance: bakeDistance,
      fovYRadians: bakeFov,
      tileDevice: cpuDevice,
    );
    card = ImpostorCard.framing(distance: bakeDistance, fovYRadians: bakeFov);
    empty = await shot(
      const ModelProject(),
      yaw: 0,
      centreY: centreY,
      side: 256,
      frame: 12,
    );
  });

  test('eight angles land in the atlas, each in its own cell', () {
    expect(bake.atlas.angles, 8);
    expect(bake.size, 192);
    expect(bake.rgba.length, 192 * 192 * 4);

    // Every cell holds something: a composite that wrote every view over the
    // same corner would leave seven of them empty and still be the right
    // length.
    for (final ImpostorView view in bake.atlas.views) {
      final int x =
          (view.cell.x * bake.size).round() + bake.atlas.cellSize ~/ 2;
      final int y =
          (view.cell.y * bake.size).round() + bake.atlas.cellSize ~/ 2;
      expect(
        bake.rgba[(y * bake.size + x) * 4 + 3],
        greaterThan(0),
        reason: 'view ${view.index} has nothing in the middle of its cell',
      );
    }
  });

  test(
    'the card at 300 m matches the mesh within 3% of the silhouette',
    () async {
      const int side = 256;
      // Twelve metres across the frame at three hundred: the subject is about
      // forty pixels tall, which is the scale the row is arguing about.
      const double frame = 12;
      const double yaw = 0;

      final List<bool> mesh = coverage(
        await shot(
          subject(),
          yaw: yaw,
          centreY: centreY,
          side: side,
          frame: frame,
        ),
        empty,
      );
      final List<bool> impostor = coverage(
        await shot(
          cardProject(bake: bake, card: card, yaw: yaw, centreY: centreY),
          yaw: yaw,
          centreY: centreY,
          side: side,
          frame: frame,
          texture: bake,
        ),
        empty,
      );

      var union = 0;
      var differ = 0;
      for (var i = 0; i < mesh.length; i++) {
        if (mesh[i] || impostor[i]) union++;
        if (mesh[i] != impostor[i]) differ++;
      }

      // A silhouette worth comparing in the first place: a subject that drew
      // nothing would agree with a card that drew nothing, at zero percent.
      expect(union, greaterThan(400), reason: 'nothing to compare');
      expect(
        differ / union,
        lessThan(0.03),
        reason: '$differ of $union pixels differ',
      );
    },
  );

  test('and a card the size of the model itself is nowhere near', () async {
    // **The mutation, and the mistake `ImpostorCard.framing` exists to
    // stop.** A cell holds the model inside a frame, so a card the size of
    // the model shrinks the picture by whatever fraction of that frame the
    // model subtended. It still looks like the model, which is why it is
    // worth a test rather than an eye: the shape is right and the size is
    // not.
    const int side = 256;
    const double frame = 12;

    final List<bool> mesh = coverage(
      await shot(subject(), yaw: 0, centreY: centreY, side: side, frame: frame),
      empty,
    );
    final List<bool> naive = coverage(
      await shot(
        cardProject(
          bake: bake,
          // The subject's own bounds: 1.4 across at the base, 2.05 tall.
          card: const ImpostorCard(width: 1.4, height: 2.05),
          yaw: 0,
          centreY: centreY,
        ),
        yaw: 0,
        centreY: centreY,
        side: side,
        frame: frame,
        texture: bake,
      ),
      empty,
    );

    var union = 0;
    var differ = 0;
    for (var i = 0; i < mesh.length; i++) {
      if (mesh[i] || naive[i]) union++;
      if (mesh[i] != naive[i]) differ++;
    }
    expect(differ / union, greaterThan(0.3), reason: '$differ of $union');
  });
}
