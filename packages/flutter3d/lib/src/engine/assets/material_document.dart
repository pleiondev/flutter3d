import 'dart:typed_data';

import '../render/lighting_model.dart';
import 'surface_material.dart';

/// A material as a file of its own, rather than as part of a model.
///
/// **Why a material wants to be a file.** A look — the studio's brushed steel,
/// the water in level three — is authored once and worn by many meshes, and a
/// model format cannot say that: glTF writes the material into every file that
/// uses it, so changing the steel means re-exporting every model made of it. A
/// standalone material is the artist's unit of work and the thing they iterate
/// on between two runs of the game.
///
/// **[surface] rather than a second set of colour fields.** [SurfaceMaterial] is
/// already what every decoder produces and what the renderer converts, so a
/// separate but equal description would be a second thing to keep correct and
/// the first place a new field would be forgotten. What a standalone file adds
/// is the three things a model's material cannot have: images named by path
/// instead of by index into a container, a shader of the application's own, and
/// the parameters that shader reads.
final class MaterialDocument {
  const MaterialDocument({
    required this.surface,
    this.images = const <String>[],
    this.lighting,
    this.parameterBlock = 'MaterialParams',
    this.parameters = const <String, Float32List>{},
    this.extraTextures = const <String, TextureBinding>{},
    this.warnings = const <String>[],
  });

  /// Colours, factors, texture slots and alpha — the vocabulary shared with
  /// every model decoder.
  final SurfaceMaterial surface;

  /// Image paths, indexed by [TextureBinding.imageIndex].
  ///
  /// **Indexed, not named, and that is deliberate.** The rule stated on
  /// [TextureBinding] — always an index, never a path — exists so a consumer can
  /// upload images without knowing which format they came from. A standalone
  /// file has paths and nothing else, so the reader normalises them here: it is
  /// the decoder's job to be the last place a format's addressing shows.
  ///
  /// Paths are relative to the material file, resolved the way a `.gltf`'s
  /// buffers and an `.obj`'s maps already are.
  final List<String> images;

  /// The shader this material asks for, or null to take the scene's.
  ///
  /// A [LightingModel] rather than a name, because the name is only half the
  /// contract: the flags say what the compiled shader actually binds, and
  /// binding a texture a shader has no slot for is a native crash rather than a
  /// warning. A file that names a custom shader must therefore also say what it
  /// reads — which is exactly what the build script's table prints.
  final LightingModel? lighting;

  /// The uniform block an application's own shader reads [parameters] from.
  final String parameterBlock;

  /// Numbers the shader reads, by uniform name.
  final Map<String, Float32List> parameters;

  /// Texture slots beyond the standard five, by sampler name.
  final Map<String, TextureBinding> extraTextures;

  /// Non-fatal findings from reading: unknown keys, a slot that names an image
  /// the file does not list. Surfaced rather than logged, like a model's.
  final List<String> warnings;
}
