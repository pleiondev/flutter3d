import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor, MaterialParameters, SrgbColor;
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
    this.emissive,
    this.emissiveStrength = 0.0,

    /// How many times a texture repeats per metre.
    this.texelsPerMeter = 1.0,
    this.albedo,
    this.normal,
    this.orm,
    this.fmat,
    this.depthLayer = 0,
    MaterialParameters? parameters,
    this.materialVersion,
    this.physicalMaterial,
    Map<String, Object?> source = const <String, Object?>{},
  }) : baseColor = baseColor ?? _defaultBaseColor,
       parameters = parameters ?? MaterialParameters(),
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

  /// The colour the surface glows in, linear, or null for the colour it is
  /// painted ([baseColor]), which is what every level written before 1.0
  /// glows in. The document's `emissiveColor`, written only when set.
  ///
  /// **A `LinearColor`, as every material's emissive is** (since 1.0): the
  /// renderer's `RenderMaterial.emissive` and `Material3D.emissive` are
  /// colours too, and how bright it shines is [emissiveStrength].
  final LinearColor? emissive;

  /// How brightly the surface glows, a ratio: a plain multiple of
  /// `RenderMaterial.defaultEmissiveStrength`, as a level has always stored
  /// it. Zero is not lit. The document's `emissive` key, unchanged, so a
  /// level reads and writes the number it did.
  ///
  /// Named `emissive` before 1.0, when it was the only emissive value a
  /// level had.
  final double emissiveStrength;

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
  /// language: each a parameter's name and its components.
  ///
  /// **A [MaterialParameters], the one shape a material's parameters have**
  /// (since 1.0; it was a map of names to numbers): the loader writes these
  /// into the `RenderMaterial.parameters` it draws with, by name. Held
  /// without a schema, because this package does not read materials; the
  /// material checks them when the loader writes them.
  ///
  /// Empty is every level written so far, and the material's defaults.
  final MaterialParameters parameters;

  /// The version of that material [parameters] were written for: its
  /// `material Name version N`. Null for a level that predates material
  /// versions, which is read as version 1.
  ///
  /// **The level keeps the version; the loader lifts the values.** A
  /// material that renamed or rescaled a parameter since says how, in its
  /// `updates` block, and `MaterialProgram.lift` carries values from an
  /// older version to the material's own. `flutter3d_app`'s level loader,
  /// which reads both the level and the material, calls it on load
  /// (`LevelLoader.build(programs:)`), so [parameters] reach the material
  /// under the names and scales of the version it is at. This package does
  /// not read materials, so it keeps the number exactly as the document
  /// said it.
  final int? materialVersion;

  /// The substance a surface in this material is made of, as a body and a
  /// sound feel it: the id of a material in the engine's `MaterialCatalog`
  /// (`f3d.concrete`, `<pluginId>.basalt`), or null for none named. A level
  /// naming one no installed plugin declares is refused
  /// (`Level.requireMaterials`).
  final String? physicalMaterial;

  /// [baseColor] as the document stores it: sRGB-encoded, rounded to single
  /// precision, which is what a level file has always said.
  ///
  /// An [SrgbColor] since 1.0, where it was a `Vector4`: a colour, typed as
  /// the encoding it is in.
  SrgbColor get storedBaseColor {
    final stored = baseColor.toSrgb();
    final single = Vector4(stored.r, stored.g, stored.b, stored.a);
    return SrgbColor(single.x, single.y, single.z, single.w);
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
    emissive: json.containsKey('emissiveColor')
        ? json.linearColor('emissiveColor', fallback: LinearColor.black)
        : null,
    emissiveStrength: json.numberOr('emissive', 0.0),
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
    physicalMaterial: readPhysicalMaterial(json, 'a material'),
    source: json,
  );

  /// A document's `parameters`: each name to a number or a list of them.
  static MaterialParameters _parameters(Object? json) => switch (json) {
    null => MaterialParameters(),
    final Map<String, Object?> map => MaterialParameters.of(
      <String, List<double>>{
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
    ),
    _ => throw LevelFormatException(
      'a material\'s "parameters" is a map of names to numbers, not $json',
    ),
  };

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField('baseColor', switch (storedBaseColor) {
      SrgbColor(:final r, :final g, :final b, :final a) => <double>[r, g, b, a],
    }, whenAbsent: baseColor != _defaultBaseColor),
    WriteThroughField('roughness', roughness, whenAbsent: roughness != 0.85),
    WriteThroughField('metallic', metallic, whenAbsent: metallic != 0.0),
    WriteThroughField(
      'emissive',
      emissiveStrength,
      whenAbsent: emissiveStrength != 0.0,
    ),
    WriteThroughField(
      'emissiveColor',
      emissive?.toJson(),
      whenAbsent: emissive != null,
    ),
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
      for (final MapEntry(:key, :value) in parameters.uniforms.entries)
        key: value.length == 1 ? value.single : <double>[...value],
    }, whenAbsent: parameters.isNotEmpty),
    WriteThroughField(
      'materialVersion',
      materialVersion,
      whenAbsent: materialVersion != null,
    ),
    WriteThroughField(
      'physicalMaterial',
      physicalMaterial,
      whenAbsent: physicalMaterial != null,
    ),
  ]);
}

/// A level document's `physicalMaterial` on [what]: a material's id, or
/// null where it says none.
String? readPhysicalMaterial(Map<String, Object?> json, String what) =>
    switch (json['physicalMaterial']) {
      null => null,
      final String id when id.isNotEmpty => id,
      final other => throw LevelFormatException(
        '$what\'s "physicalMaterial" must be a material\'s id, not $other',
      ),
    };
