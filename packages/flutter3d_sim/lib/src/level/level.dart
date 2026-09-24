import 'package:vector_math/vector_math.dart';

import '../save/state_digest.dart';
import 'brush.dart';
import 'entity_def.dart';
import 'heightfield.dart';
import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';
import 'level_light.dart';
import 'level_material.dart';
import 'level_recipes.dart';

export 'brush.dart';
export 'entity_def.dart';
export 'level_format_exception.dart';
export 'level_light.dart';
export 'level_material.dart';
export 'level_recipes.dart';
export 'level_sketch.dart';

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
    this.heightfield,
    Vector3? fogColor,
    this.fogDensity = 0.0,
    this.music,
    this.next,
    List<LevelRecipe>? recipes,
    Map<String, Object?> source = const <String, Object?>{},
  }) : brushes = brushes ?? <Brush>[],
       recipes = recipes ?? <LevelRecipe>[],
       // ignore: prefer_initializing_formals
       _source = source,
       entities = entities ?? <EntityDef>[],
       lights = lights ?? <LevelLight>[],
       materials = materials ?? <String, LevelMaterial>{},
       fogColor = fogColor?.clone() ?? _defaultFogColor;

  /// What [fogColor] is when a document says nothing. A fresh one each time,
  /// because a `Vector3` is mutable and a shared one could be changed in place.
  static Vector3 get _defaultFogColor => Vector3(0.05, 0.04, 0.06);

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

  /// The ground, when the level is played on sampled terrain rather than on
  /// brushes alone.
  ///
  /// **Additive, and the version is deliberately not bumped for it** — the rule
  /// above says a version marks a field whose *meaning* changed, and an older
  /// reader ignoring a section it never knew is the case that rule allows. The
  /// hazard is worth naming even so: what an older reader ignores here is the
  /// ground itself, so a terrain map opened by a build without this field is a
  /// level whose floor is missing rather than one drawn slightly wrong. Nothing
  /// in this repository is such a build — every reader is compiled from the
  /// same tree — and the day one exists, this is the field that decides whether
  /// it may open the document.
  final Heightfield? heightfield;

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

  /// Pieces of the level written as the instruction that builds them.
  ///
  /// **Kept, not expanded.** [brushes], [entities] and [lights] are what the
  /// document spells out and nothing more; what a recipe stands for appears
  /// only in `expandRecipes(level)`, which everything that *uses* a level
  /// calls. So an editor that opens a level and saves it writes the recipe
  /// back as a recipe, rather than baking forty brushes into the file and a
  /// second copy of them on the next load.
  final List<LevelRecipe> recipes;

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

  /// This level's document, as an eight-digit hex digest — [StateDigest] over
  /// [toJson], the same instrument a run's checkpoints use.
  ///
  /// What a `Demo` compares against to know whether the level underneath its
  /// tape is the one it was recorded against or one that has since been
  /// edited — a question a modification time cannot answer, because a level
  /// saved with no change still gets a new one.
  String get digestHex => contentDigestHex(toJson());

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
      materials: json
          .objectMap('materials')
          .map(
            (String key, Map<String, Object?> value) =>
                MapEntry<String, LevelMaterial>(
                  key,
                  LevelMaterial.fromJson(value),
                ),
          ),
      heightfield: switch (json['heightfield']) {
        final Map<String, Object?> section => Heightfield.fromJson(section),
        _ => null,
      },
      fogColor: json.vector3('fogColor', fallback: _defaultFogColor),
      fogDensity: json.numberOr('fogDensity', 0.0),
      music: json.textOrNull('music'),
      next: json.textOrNull('next'),
      recipes: json.objects('recipes').map(LevelRecipe.fromJson).toList(),
      source: json,
    );
  }

  Map<String, Object?> toJson() => writeThrough(_source, <WriteThroughField>[
    WriteThroughField('version', formatVersion),
    WriteThroughField('name', name),
    // Conditional like the fields around it. It used to be written always, so
    // a document that never named a fog came back with the default in it,
    // passed through `Vector3`'s float32 storage on the way: 0.05 read back
    // as 0.05000000074505806. Every generated level names its fog and so
    // never showed it; the two hand-written lesson levels do not, and failed
    // the round trip on exactly this key.
    WriteThroughField(
      'fogColor',
      fogColor.toJson(),
      whenAbsent: fogColor != _defaultFogColor,
    ),
    WriteThroughField('fogDensity', fogDensity, whenAbsent: fogDensity != 0.0),
    WriteThroughField('music', music, whenAbsent: music != null),
    WriteThroughField('next', next, whenAbsent: next != null),
    WriteThroughField('materials', <String, Object?>{
      for (final entry in materials.entries) entry.key: entry.value.toJson(),
    }, whenAbsent: materials.isNotEmpty),
    WriteThroughField(
      'brushes',
      brushes.map((Brush b) => b.toJson()).toList(),
      whenAbsent: brushes.isNotEmpty,
    ),
    WriteThroughField(
      'lights',
      lights.map((LevelLight l) => l.toJson()).toList(),
      whenAbsent: lights.isNotEmpty,
    ),
    WriteThroughField(
      'entities',
      entities.map((EntityDef e) => e.toJson()).toList(),
      whenAbsent: entities.isNotEmpty,
    ),
    WriteThroughField(
      'heightfield',
      heightfield?.toJson(),
      whenAbsent: heightfield != null,
    ),
    WriteThroughField(
      'recipes',
      recipes.map((LevelRecipe r) => r.toJson()).toList(),
      whenAbsent: recipes.isNotEmpty,
    ),
  ]);
}
