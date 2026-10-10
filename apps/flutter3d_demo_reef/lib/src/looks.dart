/// What Wreck Reef reads from files before a dive: the ship, the diver,
/// the finds that were modelled by somebody, the rocks, and the sand and the
/// reef rock the floor is drawn with. `assets/CREDITS.md` says whose each is,
/// and `tool/prepare_models.py` how it was made from what they published.
///
/// Everything under the sea is drawn with the floor's own material, so it is
/// lit through the surface and coloured by the water like the floor is: a
/// model's own material is read for its colour and its picture, and nothing
/// else of it is kept.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:vector_math/vector_math.dart';

/// One piece of a model: geometry, where it sits in the model, and the
/// colour and picture its file gave it.
final class ModelPiece {
  ModelPiece(
    this.name,
    this.mesh,
    this.data,
    this.place,
    this.color,
    this.picture,
  );

  /// The material's name in the file: what a caller recolours by.
  final String name;
  final DeviceMesh mesh;

  /// The vertices as they were read, for a caller that merges copies of a
  /// small model into one mesh rather than drawing each.
  final MeshData data;
  final Matrix4 place;
  final Vector4 color;
  final TextureHandle? picture;
}

/// A model read and uploaded, ready to be dressed in the sea's material as
/// often as it is wanted.
final class ReefModel {
  ReefModel(this.pieces, this.anchors);

  final List<ModelPiece> pieces;

  /// The empty nodes the file carries, by name: where the diver's head,
  /// back and feet are, for the gear hung on them.
  final Map<String, Matrix4> anchors;

  /// A node drawing the model under the sea, each piece in the floor's
  /// material wearing its own picture and its own colour, or the colour
  /// [recolour] gives for it by its name.
  ///
  /// A model seen from inside as well as out, a hull open to the sky, is
  /// [lined]: each piece drawn again turned inside out, uploaded to that
  /// device. Drawing it double-sided instead would light its inner face as
  /// if it faced outwards, away from the sun that shines into it.
  ///
  /// A piece whose colour changes across it is [painted]: each vertex's
  /// colour, by the piece's name and where the vertex is in the model, is
  /// what [painted] says, or left as it was where it says nothing, and the
  /// piece uploaded again to [lined]'s or [device]'s device so painted.
  SceneNode dress(
    SeabedLook floor, {
    required String name,
    Vector4? Function(String piece)? recolour,
    Vector4? Function(String piece, Vector3 at)? painted,
    double roughness = 0.85,
    GraphicsDevice? lined,
    GraphicsDevice? device,
  }) {
    final node = SceneNode(name: name);
    for (final piece in pieces) {
      final material = underWith(
        floor,
        piece.name,
        recolour?.call(piece.name) ?? piece.color,
        picture: piece.picture,
        roughness: roughness,
      );
      final uploadTo = lined ?? device;
      final mesh = painted == null || uploadTo == null
          ? piece.mesh
          : DeviceMesh.upload(uploadTo, _paint(piece, painted));
      node.add(
        MeshNode(mesh, material, name: piece.name)..setLocalMatrix(piece.place),
      );
      if (lined != null) {
        node.add(
          MeshNode(
            DeviceMesh.upload(lined, insideOut(piece.data)),
            material,
            name: '${piece.name} inside',
          )..setLocalMatrix(piece.place),
        );
      }
    }
    return node;
  }

  /// [piece]'s vertices coloured as [painted] says for where each lies in
  /// the model.
  static MeshData _paint(
    ModelPiece piece,
    Vector4? Function(String piece, Vector3 at) painted,
  ) {
    final data = piece.data;
    final stride = data.layout.floatsPerVertex;
    final colorAt = data.layout.floatOffsetOf(VertexLayout.color.name);
    final vertices = Float32List.fromList(data.vertices);
    if (colorAt < 0) return data;
    for (var o = 0; o < vertices.length; o += stride) {
      final color = painted(
        piece.name,
        piece.place.transformed3(
          Vector3(vertices[o], vertices[o + 1], vertices[o + 2]),
        ),
      );
      if (color == null) continue;
      vertices
        ..[o + colorAt] = color.x
        ..[o + colorAt + 1] = color.y
        ..[o + colorAt + 2] = color.z
        ..[o + colorAt + 3] = color.w;
    }
    return MeshData(
      layout: data.layout,
      vertices: vertices,
      indices: data.indices,
    );
  }
}

/// [mesh] turned inside out: every triangle wound the other way round and
/// every normal reversed, so its inner face is a surface of its own.
MeshData insideOut(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final vertices = Float32List.fromList(mesh.vertices);
  for (var o = 0; o < vertices.length; o += stride) {
    // The normal follows the position in every layout.
    for (var k = 3; k < 6; k++) {
      vertices[o + k] = -vertices[o + k];
    }
  }
  final indices = Uint32List.fromList(mesh.indices);
  for (var t = 0; t + 2 < indices.length; t += 3) {
    final second = indices[t + 1];
    indices
      ..[t + 1] = indices[t + 2]
      ..[t + 2] = second;
  }
  return MeshData(layout: mesh.layout, vertices: vertices, indices: indices);
}

/// The floor's material for anything else under the sea, as
/// [SeabedLook.under] makes it, with a [picture] in its base colour slot:
/// the sea's shader reads the base colour as texture times colour times
/// vertex colour, so a model's own picture comes through the water as it
/// does on land.
///
/// A [relief], a normal map read along the same coordinates as the
/// picture, bends the light over it as the engine's own light loop bends it
/// for any lit material: the sea's material is one, its sun handed in by
/// that loop.
RenderMaterial underWith(
  SeabedLook floor,
  String name,
  Vector4 color, {
  TextureHandle? picture,
  TextureHandle? relief,
  double roughness = 0.85,
  bool doubleSided = false,
  MaterialAlphaMode alphaMode = MaterialAlphaMode.opaque,
}) => RenderMaterial(
  name: name,
  lighting: floor.material.lighting,
  parameters: floor.material.parameters,
  baseColor: _fromSrgb(color),
  roughness: roughness,
  albedo: picture,
  albedoSampler: picture == null
      ? null
      : samplerOptionsFor(const TextureSampling()),
  normal: relief,
  normalSampler: relief == null
      ? null
      : samplerOptionsFor(const TextureSampling()),
  doubleSided: doubleSided,
  alphaMode: alphaMode,
);

/// Everything a dive reads from the bundle.
final class ReefLooks {
  ReefLooks._({
    required this.wreck,
    required this.diver,
    required this.bust,
    required this.chest,
    required this.rocks,
    required this.sand,
    required this.reefRock,
    required this.reefRelief,
  });

  /// The ship, cut down to her bottom; keel at nought, bow along +x.
  final ReefModel wreck;

  /// A man posed swimming, lying along +x, back up.
  final ReefModel diver;

  /// The head, cast in bronze — modelled in marble, which the colour sees
  /// to — and the chest.
  final ReefModel bust;
  final ReefModel chest;

  /// Two boulders, each a metre high, to scatter at any size.
  final List<ReefModel> rocks;

  /// The sand, and the rock of the reef, each a picture that repeats; the
  /// rock's alpha is its height, crevice to crest, and [reefRelief] the
  /// same rock's normal map, texel for texel over its picture.
  final TextureHandle sand;
  final TextureHandle reefRock;
  final TextureHandle reefRelief;

  static Future<ReefLooks> load(GraphicsDevice device) async {
    Future<ReefModel> model(String file) =>
        _read(device, 'assets/models/$file');
    Future<TextureHandle> picture(String file) async {
      final bytes = await rootBundle.load('assets/textures/$file');
      final texture = await uploadEncodedImage(
        device,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        decodeImage: defaultImageDecoder,
      );
      if (texture == null) throw StateError('$file would not decode');
      return texture;
    }

    return ReefLooks._(
      wreck: await model('wreck.glb'),
      diver: await model('diver.glb'),
      bust: await model('bust.glb'),
      chest: await model('chest.glb'),
      rocks: <ReefModel>[
        await model('rock_07.glb'),
        await model('rock_09.glb'),
      ],
      sand: await picture('sand.jpg'),
      reefRock: await picture('reef_rock.png'),
      reefRelief: await picture('reef_rock_normal.jpg'),
    );
  }

  static Future<ReefModel> _read(GraphicsDevice device, String file) async {
    final document = await decodeModelInIsolate(
      ModelLoadRequest(source: BundleAssetSource(file)),
    );
    final pictures = <int, TextureHandle?>{};
    Future<TextureHandle?> picture(int index) async =>
        pictures[index] ??= await uploadEncodedImage(
          device,
          document.images[index].bytes,
          decodeImage: defaultImageDecoder,
        );
    final pieces = <ModelPiece>[];
    for (final surface in document.surfaces) {
      final material = surface.materialIndex == null
          ? null
          : document.materials[surface.materialIndex!];
      final texture = material?.baseColorTexture;
      pieces.add(
        ModelPiece(
          material?.name ?? surface.name ?? 'piece',
          DeviceMesh.upload(device, surface.mesh),
          surface.mesh,
          surface.transform,
          material == null
              ? Vector4(1.0, 1.0, 1.0, 1.0)
              : _srgbVector(material.baseColor),
          texture == null ? null : await picture(texture.imageIndex),
        ),
      );
    }
    return ReefModel(pieces, <String, Matrix4>{
      for (final node in document.nodes)
        if (node.surfaces.isEmpty && node.name != null)
          node.name!: Matrix4.compose(
            node.translation,
            node.rotation,
            node.scale,
          ),
    });
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);

/// [color] sRGB-encoded, as the `Vector4` this file paints with.
Vector4 _srgbVector(LinearColor color) {
  final srgb = color.toSrgb();
  return Vector4(srgb.r, srgb.g, srgb.b, srgb.a);
}
