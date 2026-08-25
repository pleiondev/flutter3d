import 'package:vector_math/vector_math.dart';

import 'brush.dart';
import 'entity_def.dart';
import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';
import 'level_light.dart';
import 'level_material.dart';

export 'brush.dart';
export 'entity_def.dart';
export 'level_format_exception.dart';
export 'level_light.dart';
export 'level_material.dart';

/// Everything one playable space is made of.
///
/// JSON rather than the engine's binary `.f3d` container. `.f3d` exists because
/// decoding a mesh at load time is measurably expensive and the geometry never
/// changes; a level is the opposite — it is edited constantly, and a level with
/// a thousand brushes parses in a millisecond. Being able to read the diff is
/// worth more than the millisecond.
final class Level {
  Level({
    this.name = 'untitled',
    List<Brush>? brushes,
    List<EntityDef>? entities,
    List<LevelLight>? lights,
    Map<String, LevelMaterial>? materials,
    Vector3? fogColor,
    this.fogDensity = 0.0,
    this.music,
    this.next,
    Map<String, Object?> source = const <String, Object?>{},
  })  : brushes = brushes ?? <Brush>[],
        // ignore: prefer_initializing_formals
        _source = source,
        entities = entities ?? <EntityDef>[],
        lights = lights ?? <LevelLight>[],
        materials = materials ?? <String, LevelMaterial>{},
        fogColor = fogColor?.clone() ?? Vector3(0.05, 0.04, 0.06);

  /// The document this level was read from. See [writeThrough].
  ///
  /// **This is where `generatedBy` lives.** Nothing in the format knows that
  /// key; it belongs to whichever tool produced the file, and a writer that
  /// deleted it would quietly erase the answer to "who owns this document" —
  /// the question an editor has to ask before it is allowed to save.
  final Map<String, Object?> _source;

  /// Bumped when an existing field changes meaning. Adding one does not need
  /// it: an older reader ignores what it does not know.
  static const int formatVersion = 1;

  final String name;
  final List<Brush> brushes;
  final List<EntityDef> entities;
  final List<LevelLight> lights;
  final Map<String, LevelMaterial> materials;

  final Vector3 fogColor;

  /// Exponential fog per metre. Zero is no fog.
  final double fogDensity;

  final String? music;

  /// Which level follows this one, if any.
  final String? next;

  Iterable<EntityDef> ofType(String type) =>
      entities.where((EntityDef e) => e.type == type);

  EntityDef? named(String name) {
    for (final entity in entities) {
      if (entity.name == name) return entity;
    }
    return null;
  }

  /// The material a brush names, or a plain grey one so a typo shows up as
  /// wrong-looking geometry rather than a crash. The validator reports it.
  LevelMaterial materialFor(Brush brush) =>
      materials[brush.material] ?? LevelMaterial();

  factory Level.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is num && version > formatVersion) {
      throw LevelFormatException(
        'level format version $version is newer than this build understands '
        '($formatVersion)',
      );
    }

    return Level(
      name: json.textOrNull('name') ?? 'untitled',
      brushes: json.objects('brushes').map(Brush.fromJson).toList(),
      entities: json.objects('entities').map(EntityDef.fromJson).toList(),
      lights: json.objects('lights').map(LevelLight.fromJson).toList(),
      materials: json.objectMap('materials').map(
            (String key, Map<String, Object?> value) =>
                MapEntry<String, LevelMaterial>(
              key,
              LevelMaterial.fromJson(value),
            ),
          ),
      fogColor: json.vector3(
        'fogColor',
        fallback: Vector3(0.05, 0.04, 0.06),
      ),
      fogDensity: json.numberOr('fogDensity', 0.0),
      music: json.textOrNull('music'),
      next: json.textOrNull('next'),
      source: json,
    );
  }

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
        WriteThroughField('version', formatVersion),
        WriteThroughField('name', name),
        WriteThroughField('fogColor', fogColor.toJson()),
        WriteThroughField('fogDensity', fogDensity, whenAbsent: fogDensity != 0.0),
        WriteThroughField('music', music, whenAbsent: music != null),
        WriteThroughField('next', next, whenAbsent: next != null),
        WriteThroughField('materials', <String, Object?>{
          for (final entry in materials.entries) entry.key: entry.value.toJson(),
        }, whenAbsent: materials.isNotEmpty),
        WriteThroughField('brushes', brushes.map((Brush b) => b.toJson()).toList(),
            whenAbsent: brushes.isNotEmpty),
        WriteThroughField('lights', lights.map((LevelLight l) => l.toJson()).toList(),
            whenAbsent: lights.isNotEmpty),
        WriteThroughField(
            'entities', entities.map((EntityDef e) => e.toJson()).toList(),
            whenAbsent: entities.isNotEmpty),
      ]);
}
