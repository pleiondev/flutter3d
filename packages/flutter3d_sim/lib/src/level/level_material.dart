import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';

/// The values a document is allowed to leave unsaid.
///
/// Named rather than written twice: a default that appears in the constructor
/// and again in the writer is two numbers that must agree, and one day will
/// not.
///
/// The base colour's is a mid grey as the document says it, in sRGB.
final LinearColor _defaultBaseColor = LinearColor.fromSrgb(0.5, 0.5, 0.5);

/// How a surface is shaded, named so brushes can share one.
final class LevelMaterial {
  LevelMaterial({
    LinearColor? baseColor,
    this.roughness = 0.85,
    this.metallic = 0.0,
    this.emissive = 0.0,

    /// How many times a texture repeats per metre.
    this.texelsPerMeter = 1.0,
    this.albedo,
    this.normal,
    this.orm,
    this.fmat,
    this.depthLayer = 0,
    this.parameters = const <String, List<double>>{},
    this.materialVersion,
    Map<String, Object?> source = const <String, Object?>{},
  }) : baseColor = baseColor ?? _defaultBaseColor,
       // ignore: prefer_initializing_formals
       _source = source;

  /// The document this material was read from. See [writeThrough].
  final Map<String, Object?> _source;

  /// The surface's colour, in linear light, and its coverage in alpha.
  ///
  /// **The document stores it sRGB-encoded**, the numbers a paint program
  /// shows, as it always has: [LevelMaterial.fromJson] decodes them and
  /// [toJson] encodes them back, so a level reads and writes the same numbers
  /// it did. A colour picked on screen is `LinearColor.fromSrgb(r, g, b)`.
  final LinearColor baseColor;

  /// Perceptual roughness, a 0..1 factor: 0 is a mirror, 1 is chalk.
  final double roughness;

  /// Metalness, a 0..1 factor: 0 is a dielectric, 1 is bare metal.
  final double metallic;

  /// How brightly the surface glows in its own [baseColor]. Zero is not lit.
  ///
  /// A strength rather than a colour, because a surface that emits light in
  /// some other colour than the one it is painted is a thing no level here has
  /// wanted, and a second colour is a second value to keep in step. The bridge
  /// turns it into the renderer's emissive factor and strength.
  final double emissive;

  /// Texture repeats per metre: the UV span one metre of a face covers.
  final double texelsPerMeter;

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
  /// `flutter3d_app`'s level loader is the only place that knows both formats, and
  /// it is where the fork lives.
  final String? fmat;

  /// Which depth layer a surface in this material is drawn on, unless its
  /// brush says another — see `Brush.depthLayer`.
  ///
  /// Nought is the layer everything is on. A decal material, a road's paint,
  /// a poster: one above the surface it lies on, so the two never trade
  /// pixels however far away the camera is. Format version 2; the renderer's
  /// `RenderMaterial.depthLayer` draws it.
  final int depthLayer;

  /// The values this surface gives the parameters of the material it is
  /// drawn with, when that material is written in the engine's material
  /// language: each a parameter's name and its components, as
  /// `RenderMaterial.parameters` takes them.
  ///
  /// Empty is every level written so far, and the material's defaults.
  final Map<String, List<double>> parameters;

  /// The version of that material [parameters] were written for: its
  /// `material Name version N`. Null for a level that predates material
  /// versions, which is read as version 1.
  ///
  /// **The level keeps the version; nothing lifts the values yet.** A
  /// material that renamed or rescaled a parameter since says how, in its
  /// `updates` block, and `MaterialProgram.lift` carries values from an
  /// older version to the material's own. No loader calls it today:
  /// [parameters] reach the material as the document wrote them, under the
  /// names of this version. Lifting on load belongs to the level loader,
  /// which reads both the level and the material, and arrives with it.
  /// This package does not read materials, so it keeps the number exactly
  /// as the document said it.
  final int? materialVersion;

  /// [baseColor] as the document stores it: sRGB-encoded, in single
  /// precision, which is what a level file has always said.
  Vector4 get storedBaseColor {
    final stored = baseColor.toSrgb();
    return Vector4(stored.r, stored.g, stored.b, stored.a);
  }

  /// Whether anything here has to be loaded from disk.
  bool get hasMaps => albedo != null || normal != null || orm != null;

  factory LevelMaterial.fromJson(Map<String, Object?> json) => LevelMaterial(
    baseColor: switch (json.vector4(
      'baseColor',
      fallback: Vector4(0.5, 0.5, 0.5, 1.0),
    )) {
      final stored => LinearColor.fromSrgb(
        stored.x,
        stored.y,
        stored.z,
        stored.w,
      ),
    },
    roughness: json.numberOr('roughness', 0.85),
    metallic: json.numberOr('metallic', 0.0),
    emissive: json.numberOr('emissive', 0.0),
    // `texelsPerMetre` until format 5; a level's lift renames it.
    texelsPerMeter: json.numberOr('texelsPerMeter', 1.0),
    albedo: json.textOrNull('albedo'),
    normal: json.textOrNull('normal'),
    orm: json.textOrNull('orm'),
    fmat: json.textOrNull('fmat'),
    depthLayer: json.integerOrNull('depthLayer') ?? 0,
    parameters: _parameters(json['parameters']),
    materialVersion: switch (json.integerOrNull('materialVersion')) {
      final int version when version < 1 => throw LevelFormatException(
        'a material version counts from 1, and this one says $version',
      ),
      final version => version,
    },
    source: json,
  );

  /// A document's `parameters`: each name to a number or a list of them.
  static Map<String, List<double>> _parameters(Object? json) => switch (json) {
    null => const <String, List<double>>{},
    final Map<String, Object?> map => <String, List<double>>{
      for (final MapEntry(:key, :value) in map.entries)
        key: switch (value) {
          final num number => <double>[number.toDouble()],
          final List<Object?> list
              when list.isNotEmpty &&
                  list.length <= 4 &&
                  list.every((e) => e is num) =>
            <double>[for (final e in list) (e! as num).toDouble()],
          _ => throw LevelFormatException(
            'material parameter "$key" is a number or a list of one to four, '
            'not $value',
          ),
        },
    },
    _ => throw LevelFormatException(
      'a material\'s "parameters" is a map of names to numbers, not $json',
    ),
  };

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField(
      'baseColor',
      storedBaseColor.toJson(),
      whenAbsent: baseColor != _defaultBaseColor,
    ),
    WriteThroughField('roughness', roughness, whenAbsent: roughness != 0.85),
    WriteThroughField('metallic', metallic, whenAbsent: metallic != 0.0),
    WriteThroughField('emissive', emissive, whenAbsent: emissive != 0.0),
    WriteThroughField(
      'texelsPerMeter',
      texelsPerMeter,
      whenAbsent: texelsPerMeter != 1.0,
    ),
    WriteThroughField('albedo', albedo, whenAbsent: albedo != null),
    WriteThroughField('normal', normal, whenAbsent: normal != null),
    WriteThroughField('orm', orm, whenAbsent: orm != null),
    // Named here as well as parsed, though [writeThrough] would carry the key
    // through untouched either way: a build that does not know a key copies it,
    // and one that does must also be able to *set* it. Listing it is what makes
    // an editor's change to the field reach the document.
    WriteThroughField('fmat', fmat, whenAbsent: fmat != null),
    WriteThroughField('depthLayer', depthLayer, whenAbsent: depthLayer != 0),
    WriteThroughField('parameters', <String, Object?>{
      for (final MapEntry(:key, :value) in parameters.entries)
        key: value.length == 1 ? value.single : value,
    }, whenAbsent: parameters.isNotEmpty),
    WriteThroughField(
      'materialVersion',
      materialVersion,
      whenAbsent: materialVersion != null,
    ),
  ]);
}
