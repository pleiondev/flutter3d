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
    Map<String, Object?> source = const <String, Object?>{},
  }) : baseColor = baseColor ?? Vector4(0.5, 0.5, 0.5, 1.0),
       // ignore: prefer_initializing_formals
       _source = source;

  /// The document this material was read from. See [writeThrough].
  final Map<String, Object?> _source;

  final Vector4 baseColor;
  final double roughness;
  final double metallic;
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
  ]);
}
