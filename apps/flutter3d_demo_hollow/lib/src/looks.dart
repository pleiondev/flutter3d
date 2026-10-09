/// What Cobble Hollow is drawn in: the photographs its ground, huts, car and
/// stones are covered in, and the models of its pines, its rocks and the
/// beast that works the quarry's crane, all loaded once before the valley
/// is built. Where each came from is in `assets/CREDITS.md`.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';

/// Everything the valley's meshes are drawn with besides plain colour.
///
/// A photograph that will not decode is a null map, and what wears it is
/// drawn in its tint alone: a valley with a bare roof is still a valley.
final class HollowLooks {
  HollowLooks._({
    required this.ground,
    required this.groundRelief,
    required this.thatch,
    required this.thatchRelief,
    required this.daub,
    required this.bark,
    required this.wood,
    required this.granite,
    required this.basalt,
    required this.beast,
    required this.pines,
    required this.boulder,
  });

  /// The ground, baked over the whole valley by `tool/bake_ground.dart`,
  /// and the relief of dry earth laid over it a few metres to a repeat.
  final TextureHandle? ground, groundRelief;

  /// Straw for the roofs, and its relief.
  final TextureHandle? thatch, thatchRelief;

  /// Clay over wattle for the huts' walls.
  final TextureHandle? daub;

  /// Pine bark for the logs, weathered wood for the car's rails and barrel.
  final TextureHandle? bark, wood;

  /// Pale granite for the quarry's blocks, the rollers and the idol, and
  /// black basalt for what the volcano throws.
  final TextureHandle? granite, basalt;

  /// The long-necked beast the crane is: a skinned model whose neck is
  /// posed along the crane's neck every frame.
  final ModelAsset beast;

  /// Pines of two shapes, and a boulder the quarry's blocks are cut from.
  final List<ModelAsset> pines;
  final ModelAsset boulder;

  /// Loads and uploads every look onto [device].
  static Future<HollowLooks> load(GraphicsDevice device) async {
    Future<TextureHandle?> picture(String name) async {
      final data = await rootBundle.load('assets/textures/$name.jpg');
      return uploadEncodedImage(
        device,
        Uint8List.sublistView(data),
        decodeImage: defaultImageDecoder,
      );
    }

    Future<ModelAsset> model(String name) async {
      final path = 'assets/models/$name.glb';
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: BundleAssetSource(path)),
      );
      return ModelAsset.fromDocument(document, device: device, name: path);
    }

    return HollowLooks._(
      ground: await picture('ground'),
      groundRelief: await picture('ground_normal'),
      thatch: await picture('thatch'),
      thatchRelief: await picture('thatch_normal'),
      daub: await picture('daub'),
      bark: await picture('bark'),
      wood: await picture('wood'),
      granite: await picture('granite'),
      basalt: await picture('basalt'),
      beast: await model('apatosaurus'),
      pines: <ModelAsset>[await model('pine_a'), await model('pine_c')],
      boulder: await model('rock_d'),
    );
  }
}

/// What a material that repeats its pictures is drawn with: the plain
/// model leaves a map's repeat unread, and draws the picture once across
/// the mesh however many times it was asked for.
final LightingModel repeating = LightingModel.pbr.withLayers(
  null,
  textureTransforms: true,
);

/// A material of its own (so a fire can char it alone) covered in [map],
/// repeating [repeat] times across the mesh's own coordinates, tinted by
/// [tint] (sRGB, as the photograph is), its relief from [relief] if given.
RenderMaterial covered(
  String name,
  TextureHandle? map, {
  Vector4? tint,
  Vector2? repeat,
  TextureHandle? relief,
  double roughness = 0.9,
}) {
  final scale = repeat ?? Vector2(1.0, 1.0);
  return RenderMaterial(
    name: name,
    lighting: repeating,
    albedo: map,
    baseColor: tint == null
        ? LinearColor.white
        : LinearColor.fromSrgb(tint.x, tint.y, tint.z, tint.w),
    normal: relief,
    roughness: roughness,
    textureTransforms: <MaterialMap, TextureTransform>{
      MaterialMap.baseColor: TextureTransform(scale: scale.clone()),
      if (relief != null)
        MaterialMap.normal: TextureTransform(scale: scale.clone()),
    },
  );
}
