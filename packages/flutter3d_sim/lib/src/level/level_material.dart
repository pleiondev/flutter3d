import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';

/// The values a document is allowed to leave unsaid.
///
/// Named rather than written twice: a default that appears in the constructor
/// and again in the writer is two numbers that must agree, and one day will
/// not.
final Vector4 _defaultBaseColor = Vector4(0.5, 0.5, 0.5, 1.0);

/// How a surface is shaded, named so brushes can share one.
final class LevelMaterial {
  LevelMaterial({
    Vector4? baseColor,
    this.roughness = 0.85,
    this.metallic = 0.0,
    this.emissive = 0.0,

    /// How many times a texture repeats per metre.
    this.texelsPerMetre = 1.0,
    this.albedo,
    this.normal,
    this.orm,
    this.fmat,
    Map<String, Object?> source = const <String, Object?>{},
  }) : baseColor = baseColor ?? Vector4(0.5, 0.5, 0.5, 1.0),
       // ignore: prefer_initializing_formals
       _source = source;

  /// The document this material was read from. See [writeThrough].
  final Map<String, Object?> _source;

  final Vector4 baseColor;
  final double roughness;
  final double metallic;

  /// How brightly the surface glows in its own [baseColor]. Zero is not lit.
  ///
  /// A strength rather than a colour, because a surface that emits light in
  /// some other colour than the one it is painted is a thing no level here has
  /// wanted, and a second colour is a second value to keep in step. The bridge
  /// turns it into the renderer's emissive factor and strength.
  final double emissive;
  final double texelsPerMetre;

  /// Asset path of the base colour map, relative to the game's assets.
  ///
  /// Null means the material is a flat [baseColor], which stays useful: a
  /// blocked-out room wants to be grey before it wants to be stone, and a
  /// level that will not load because an artist has not drawn the wall yet is
  /// a level nobody can play-test.
  final String? albedo;

  /// Tangent-space normal map, OpenGL convention — green points up.
  final String? normal;

  /// glTF's packing: occlusion in red, roughness in green, metallic in blue.
  ///
  /// One file rather than three because it is one sampler rather than three,
  /// and because the three are authored together and would otherwise be three
  /// chances to ship a mismatched set.
  final String? orm;

  /// A standalone material file this surface defers its whole look to.
  ///
  /// **The eight fields above are what a level needs to block a room out, and
  /// they are not what a look is made of.** There is no shader here, no
  /// emissive map, no alpha, no parameters a studio's own shader reads — a
  /// level material is deliberately the small vocabulary a level author works
  /// in, and growing it towards the renderer's would end with two descriptions
  /// of a surface that have to be kept in step. Naming a file instead keeps
  /// them apart: this key says *ask that document*, and the document is the
  /// engine's own `.fmat`, authored once and worn by every level that names it.
  ///
  /// Relative to the game's assets, like [albedo] and the rest. Null is every
  /// level written so far, and those go on being drawn from the fields above.
  ///
  /// This package may not import the engine, so nothing here reads the file;
  /// `flutter3d_bridge`'s loader is the only place that knows both formats, and
  /// it is where the fork lives.
  final String? fmat;

  /// Whether anything here has to be loaded from disk.
  bool get hasMaps => albedo != null || normal != null || orm != null;

  factory LevelMaterial.fromJson(Map<String, Object?> json) => LevelMaterial(
    baseColor: json.vector4('baseColor', fallback: Vector4(0.5, 0.5, 0.5, 1.0)),
    roughness: json.numberOr('roughness', 0.85),
    metallic: json.numberOr('metallic', 0.0),
    emissive: json.numberOr('emissive', 0.0),
    texelsPerMetre: json.numberOr('texelsPerMetre', 1.0),
    albedo: json.textOrNull('albedo'),
    normal: json.textOrNull('normal'),
    orm: json.textOrNull('orm'),
    fmat: json.textOrNull('fmat'),
    source: json,
  );

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField(
      'baseColor',
      baseColor.toJson(),
      whenAbsent: baseColor != _defaultBaseColor,
    ),
    WriteThroughField('roughness', roughness, whenAbsent: roughness != 0.85),
    WriteThroughField('metallic', metallic, whenAbsent: metallic != 0.0),
    WriteThroughField('emissive', emissive, whenAbsent: emissive != 0.0),
    WriteThroughField(
      'texelsPerMetre',
      texelsPerMetre,
      whenAbsent: texelsPerMetre != 1.0,
    ),
    WriteThroughField('albedo', albedo, whenAbsent: albedo != null),
    WriteThroughField('normal', normal, whenAbsent: normal != null),
    WriteThroughField('orm', orm, whenAbsent: orm != null),
    // Named here as well as parsed, though [writeThrough] would carry the key
    // through untouched either way: a build that does not know a key copies it,
    // and one that does must also be able to *set* it. Listing it is what makes
    // an editor's change to the field reach the document.
    WriteThroughField('fmat', fmat, whenAbsent: fmat != null),
  ]);
}
