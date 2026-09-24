/// `C4`: the octahedral impostor a converted model ends its levels of detail
/// in, baked here on the software rasteriser so the atlases are the same bytes
/// on every machine that converts the model.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math.dart';

/// The screen fraction below which a node's impostor takes over: half the
/// coarsest level's own, and never above a tenth of the frame — a card is a
/// picture from one distance, and past a tenth of the screen the eye is close
/// enough to see it does not turn with the parallax the mesh would have.
double impostorScreenFraction(List<ModelLod> lods) =>
    math.min(0.1, (lods.isEmpty ? 0.5 : lods.last.maxScreenFraction) * 0.5);

/// [document] with an impostor at the end of the levels of every node that
/// draws something and has none yet.
///
/// **Four pictures a view**, each an orthographic frame of the node's bounding
/// sphere from [impostorViewDirection], [cell] texels square:
///
///  * the albedo, unlit, twice — against black and against white. A texel is
///    covered where the two agree, which holds for a cut-out leaf as well as a
///    solid trunk, and an agreement is the albedo;
///  * the normal, through the engine's own `Normals` model, in the node's own
///    space because the bake draws it at identity;
///  * the depth, through the same model and a copy of the mesh whose normals
///    are `(t, 1 - t, 0)` — interpolated and normalised by the stage, and read
///    back as `x / (x + y)`, which is `t` again. The model already writes a
///    display colour with no curve on it, so nothing new is drawn to get a
///    number out.
///
/// All four through [RenderSettings.forMeasurement], so no tone curve, bloom
/// or occlusion moves a texel away from what the material wrote.
///
/// **The source's own images must still be decodable** — a converter bakes
/// before it compresses textures. A texture this package cannot decode is
/// baked as its material's base colour alone, and [report] hears which.
///
/// **Everything the bake puts on [device] it takes off again** — meshes,
/// decoded textures and the renderer's own targets — so a converter that bakes
/// a whole directory does not hold every model it has seen. [device] is a
/// [cell]-square software rasteriser made here when null; one passed in is
/// left open for its owner, and is how a test counts what a bake leaves.
Future<ModelDocument> bakeImpostors(
  ModelDocument document, {
  int cell = 64,
  void Function(String message)? report,
  GraphicsDevice? device,
}) async {
  final grid = kImpostorGrid;
  final side = cell * grid;
  final gpu =
      device ??
      CpuDevice(
        width: cell,
        height: cell,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
  final renderer = Renderer.create(device: gpu);
  final settings = const RenderSettings().forMeasurement();
  final normalsMaterial = Material(
    lighting: LightingModel.normals,
    doubleSided: true,
  );

  final textures = <int, TextureHandle?>{};
  TextureHandle? textureFor(int index) => textures.putIfAbsent(index, () {
    if (index < 0 || index >= document.images.length) return null;
    final decoded = img.decodeImage(document.images[index].bytes);
    if (decoded == null) {
      report?.call(
        'images[$index] is not a format the bake decodes; the impostor '
        'takes its material\'s base colour there',
      );
      return null;
    }
    final rgba = decoded.convert(numChannels: 4, format: img.Format.uint8);
    return gpu.createTextureFromPixels(
      width: rgba.width,
      height: rgba.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(rgba.toUint8List()),
    );
  });

  Material albedoMaterial(int? index) {
    final source = index != null && index >= 0
        ? (index < document.materials.length ? document.materials[index] : null)
        : null;
    if (source == null) return Material(lighting: LightingModel.unlit);
    final texture = source.baseColorTexture;
    return Material(
      lighting: LightingModel.unlit,
      baseColor: source.baseColor.clone(),
      albedo: texture == null ? null : textureFor(texture.imageIndex),
      alphaMode: source.alphaMode == SurfaceAlphaMode.mask
          ? MaterialAlphaMode.mask
          : MaterialAlphaMode.opaque,
      alphaCutoff: source.alphaCutoff,
      doubleSided: source.doubleSided,
    );
  }

  final images = <EncodedImage>[...document.images];
  final nodes = <ModelNode>[];
  try {
    for (final node in document.nodes) {
      final surfaces = <ModelSurface>[
        for (final s in node.surfaces)
          if (s >= 0 && s < document.surfaces.length) document.surfaces[s],
      ];
      if (surfaces.isEmpty ||
          node.lods.any((lod) => lod.impostor != null) ||
          surfaces.every((s) => s.mesh.vertexCount == 0)) {
        nodes.add(node);
        continue;
      }

      final (centre, radius) = _boundingSphere(surfaces);
      final drawn = <ModelSurface>[
        for (final s in surfaces)
          if (s.mesh.vertexCount > 0) s,
      ];
      // Once a node, not once a view: sixty-four views draw the same vertices.
      final uploaded = <DeviceMesh>[
        for (final s in drawn) DeviceMesh.upload(gpu, s.mesh),
      ];
      // The depth copies too: a view changes only their normals, which are
      // written over in place rather than uploaded again sixty-four times.
      final depthSources = <MeshData>[
        for (final s in drawn) s.mesh.convertedTo(VertexLayout.standard),
      ];
      final depthMeshes = <DeviceMesh>[
        for (final m in depthSources) DeviceMesh.upload(gpu, m),
      ];
      final albedoAtlas = Uint8List(side * side * 4);
      final normalAtlas = Uint8List(side * side * 4);

      try {
        for (var row = 0; row < grid; row++) {
          for (var column = 0; column < grid; column++) {
            final d = impostorViewDirection(column, row);
            final camera = _cameraFor(d, centre, radius);

            Future<Uint8List> shoot(List<MeshNode> draws, Vector4 clear) async {
              final scene = Scene();
              for (final draw in draws) {
                scene.add(draw);
              }
              scene.add(camera);
              final result = renderer.render(
                width: cell,
                height: cell,
                scene: scene,
                views: <RenderView>[
                  RenderView(camera: camera, clearColor: clear),
                ],
                settings: settings,
              );
              for (final draw in draws) {
                scene.remove(draw);
              }
              scene.remove(camera);
              final pixels = await gpu.readPixels(result.frame);
              return pixels!.buffer.asUint8List(
                pixels.offsetInBytes,
                pixels.lengthInBytes,
              );
            }

            List<MeshNode> drawsOf(
              List<DeviceMesh> meshes,
              Material Function(int surface) materialOf,
            ) => <MeshNode>[
              for (var i = 0; i < drawn.length; i++)
                MeshNode(meshes[i], materialOf(i)),
            ];

            final colour = drawsOf(
              uploaded,
              (i) => albedoMaterial(drawn[i].materialIndex),
            );
            final onBlack = await shoot(colour, Vector4(0, 0, 0, 0));
            final onWhite = await shoot(colour, Vector4(1, 1, 1, 1));
            final normals = await shoot(
              drawsOf(uploaded, (_) => normalsMaterial),
              Vector4(0, 0, 0, 0),
            );
            for (var i = 0; i < drawn.length; i++) {
              depthMeshes[i].overwriteVertices(
                gpu,
                0,
                ByteData.sublistView(
                  _depthCoded(depthSources[i], d, centre, radius),
                ),
              );
            }
            final depths = await shoot(
              drawsOf(depthMeshes, (_) => normalsMaterial),
              Vector4(0, 0, 0, 0),
            );

            for (var y = 0; y < cell; y++) {
              for (var x = 0; x < cell; x++) {
                final from = (y * cell + x) * 4;
                final to = ((row * cell + y) * side + column * cell + x) * 4;
                final gap =
                    (onWhite[from] - onBlack[from]).abs() +
                    (onWhite[from + 1] - onBlack[from + 1]).abs() +
                    (onWhite[from + 2] - onBlack[from + 2]).abs();
                // Nothing drawn reads 255 apart on every channel; a surface
                // reads the same against either. Rounding in the encoder can
                // leave a covered texel a step or two apart.
                final covered = gap < 24;
                if (!covered) continue;
                albedoAtlas[to] = onBlack[from];
                albedoAtlas[to + 1] = onBlack[from + 1];
                albedoAtlas[to + 2] = onBlack[from + 2];
                albedoAtlas[to + 3] = 255;
                normalAtlas[to] = normals[from];
                normalAtlas[to + 1] = normals[from + 1];
                normalAtlas[to + 2] = normals[from + 2];
                final dx = depths[from] / 255 * 2 - 1;
                final dy = depths[from + 1] / 255 * 2 - 1;
                final t = dx + dy > 1e-6
                    ? (dx / (dx + dy)).clamp(0.0, 1.0)
                    : 0.5;
                normalAtlas[to + 3] = (t * 255).round();
              }
            }
          }
        }
      } finally {
        for (final mesh in <DeviceMesh>[...uploaded, ...depthMeshes]) {
          gpu
            ..releaseGeometry(mesh.vertices)
            ..releaseGeometry(mesh.indices);
        }
      }

      _bleed(albedoAtlas, normalAtlas, side: side, cell: cell);

      final albedoIndex = images.length;
      images.add(
        EncodedImage(
          bytes: encodePng(albedoAtlas, side, side),
          name: '${node.name ?? 'node'} impostor albedo',
          mimeType: 'image/png',
        ),
      );
      final normalIndex = images.length;
      images.add(
        EncodedImage(
          bytes: encodePng(normalAtlas, side, side),
          name: '${node.name ?? 'node'} impostor normal-depth',
          mimeType: 'image/png',
        ),
      );

      nodes.add(
        ModelNode(
          name: node.name,
          translation: node.translation,
          rotation: node.rotation,
          scale: node.scale,
          children: node.children,
          surfaces: node.surfaces,
          extras: node.extras,
          lightIndex: node.lightIndex,
          cameraIndex: node.cameraIndex,
          lods: <ModelLod>[
            ...node.lods,
            ModelLod.impostor(
              maxScreenFraction: impostorScreenFraction(node.lods),
              impostor: ModelImpostor(
                albedoImage: albedoIndex,
                normalDepthImage: normalIndex,
                grid: grid,
                centre: centre,
                radius: radius,
              ),
            ),
          ],
        ),
      );
      report?.call(
        '${node.name ?? 'a node'}: impostor ${grid}x$grid views of $cell, '
        'radius ${radius.toStringAsFixed(3)}',
      );
    }
  } finally {
    for (final texture in textures.values) {
      if (texture != null) gpu.releaseTexture(texture);
    }
    renderer.dispose();
    if (device == null) gpu.dispose();
  }

  return PlainModelDocument(
    surfaces: document.surfaces,
    materials: document.materials,
    images: images,
    nodes: nodes,
    animations: document.animations,
    skins: document.skins,
    lights: document.lights,
    cameras: document.cameras,
    warnings: document.warnings,
    asset: document.asset,
  );
}

/// The middle of [surfaces]' box, and the furthest any vertex is from it —
/// in the node's own space, which is where each surface's vertices already
/// are.
///
/// **`ModelSurface.transform` is not applied, on purpose.** It is the node's
/// placement in the model, the same matrix the node's own TRS composes to,
/// kept on the surface for a reader that draws a flat list. `instantiate`
/// draws the mesh at identity under the node and the card beside it, so a
/// centre moved by that matrix would be carried by the node a second time.
(Vector3, double) _boundingSphere(List<ModelSurface> surfaces) {
  final box = Aabb3.copy(surfaces.first.mesh.computeBounds());
  for (final s in surfaces.skip(1)) {
    box.hull(s.mesh.computeBounds());
  }
  final centre = box.center;
  var radius = 0.0;
  for (final s in surfaces) {
    final stride = s.mesh.layout.floatsPerVertex;
    final at = s.mesh.layout.floatOffsetOf(VertexLayout.position.name);
    for (var v = 0; v < s.mesh.vertexCount; v++) {
      final o = v * stride + at;
      radius = math.max(
        radius,
        Vector3(
          s.mesh.vertices[o] - centre.x,
          s.mesh.vertices[o + 1] - centre.y,
          s.mesh.vertices[o + 2] - centre.z,
        ).length,
      );
    }
  }
  return (centre, math.max(radius, 1e-6));
}

/// The camera view [d] was baked from: level with the card's own right-hand
/// axis, looking back along [d] at the sphere, which fills the frame.
CameraNode _cameraFor(Vector3 d, Vector3 centre, double radius) {
  final right = impostorRight(d);
  final up = d.cross(right);
  final eye = centre + d.scaled(radius * 2.0);
  return CameraNode(
    name: 'impostor bake',
    projection: OrthographicProjection(
      height: radius * 2.0,
      near: radius * 0.5,
      far: radius * 4.0,
    ),
  )..setLocalMatrix(
    Matrix4(
      right.x,
      right.y,
      right.z,
      0, //
      up.x,
      up.y,
      up.z,
      0,
      d.x,
      d.y,
      d.z,
      0,
      eye.x,
      eye.y,
      eye.z,
      1,
    ),
  );
}

/// The vertices of [standard], a mesh in [VertexLayout.standard], with each
/// normal replaced by its depth along the view [d] coded as `(t, 1 - t, 0)` —
/// `t` nought at the near side of the sphere, one at the far.
Float32List _depthCoded(
  MeshData standard,
  Vector3 d,
  Vector3 centre,
  double radius,
) {
  final vertices = Float32List.fromList(standard.vertices);
  final stride = VertexLayout.standard.floatsPerVertex;
  final position = VertexLayout.standard.floatOffsetOf(
    VertexLayout.position.name,
  );
  final normal = VertexLayout.standard.floatOffsetOf(VertexLayout.normal.name);
  for (var v = 0; v < standard.vertexCount; v++) {
    final o = v * stride;
    final along =
        (vertices[o + position] - centre.x) * d.x +
        (vertices[o + position + 1] - centre.y) * d.y +
        (vertices[o + position + 2] - centre.z) * d.z;
    final t = (0.5 - along / (2.0 * radius)).clamp(0.0, 1.0);
    vertices[o + normal] = t;
    vertices[o + normal + 1] = 1.0 - t;
    vertices[o + normal + 2] = 0.0;
  }
  return vertices;
}

/// Spreads each covered texel's colour and normal a few texels into the
/// uncovered ones around it, inside its own cell, leaving their coverage at
/// nought.
///
/// **What a filtered read sees at a silhouette.** A bilinear tap on a leaf's
/// edge mixes the leaf with its uncovered neighbour, and an uncovered texel
/// that held black darkens every edge of every card by up to half — a dark
/// outline round the tree that the mesh never had. With the neighbour holding
/// the leaf's own colour the tap reads the leaf, and the coverage it also
/// mixes is what decides the edge. Kept inside the cell, because the texel
/// across a cell's border belongs to another view.
void _bleed(
  Uint8List albedo,
  Uint8List normals, {
  required int side,
  required int cell,
  int passes = 3,
}) {
  final filled = Uint8List(side * side);
  for (var i = 0; i < side * side; i++) {
    if (albedo[i * 4 + 3] > 0) filled[i] = 1;
  }
  for (var pass = 0; pass < passes; pass++) {
    final next = Uint8List.fromList(filled);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final i = y * side + x;
        if (filled[i] != 0) continue;
        final sums = List<int>.filled(7, 0);
        var count = 0;
        for (final (dx, dy) in const <(int, int)>[
          (1, 0),
          (-1, 0),
          (0, 1),
          (0, -1),
        ]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= side || ny >= side) continue;
          if (nx ~/ cell != x ~/ cell || ny ~/ cell != y ~/ cell) continue;
          final n = ny * side + nx;
          if (filled[n] == 0) continue;
          for (var c = 0; c < 3; c++) {
            sums[c] += albedo[n * 4 + c];
            sums[3 + c] += normals[n * 4 + c];
          }
          sums[6] += normals[n * 4 + 3];
          count++;
        }
        if (count == 0) continue;
        for (var c = 0; c < 3; c++) {
          albedo[i * 4 + c] = sums[c] ~/ count;
          normals[i * 4 + c] = sums[3 + c] ~/ count;
        }
        normals[i * 4 + 3] = sums[6] ~/ count;
        next[i] = 1;
      }
    }
    filled.setAll(0, next);
  }
}
