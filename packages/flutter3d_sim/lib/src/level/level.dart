import 'dart:convert';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show FormatDocument, FormatMigration, FormatSpec;
import 'package:vector_math/vector_math.dart';

import '../save/state_digest.dart';
import 'brush.dart';
import 'entity_def.dart';
import 'heightfield.dart';
import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';
import 'level_ids.dart';
import 'level_light.dart';
import 'level_material.dart';
import 'level_recipes.dart';
import 'prefab.dart';

export 'brush.dart';
export 'entity_def.dart';
export 'level_format_exception.dart';
export 'level_ids.dart';
export 'level_light.dart';
export 'level_material.dart';
export 'level_recipes.dart';
export 'level_sketch.dart';
export 'prefab.dart';

/// Everything one playable space is made of.
///
/// JSON rather than the engine's binary `.f3d` container. `.f3d` exists because
/// decoding a mesh at load time is measurably expensive and the geometry never
/// changes; a level is the opposite — it is edited constantly, and a level with
/// a thousand brushes parses in a millisecond. Being able to read the diff is
/// worth more than the millisecond.
///
/// ## The document
///
/// Written in the format envelope, `{"format": "f3d.level", "version": 3,
/// "requires": [...], "generator": "flutter3d", ...}` (see [FormatSpec]).
/// Every brush, light and entity carries an `id` (see [LevelIds]), an
/// entity's properties sit under its `props`, and a prefab instance's
/// overrides are keyed by id paths. A document from before format 3 still
/// reads: ids are derived for what has none, properties at the top of a row
/// are taken as properties, and overrides by name or `#<index>` are turned
/// into id paths. It is written back as format 3. A key this build does not
/// know is kept and written back where it was.
final class Level extends FormatDocument {
  Level({
    this.name = 'untitled',
    List<Brush>? brushes,
    List<EntityDef>? entities,
    List<LevelLight>? lights,
    Map<String, LevelMaterial>? materials,
    this.heightfield,
    Vector3? fogColor,
    this.fogDensity = 0.0,
    Map<String, Object?>? world,
    this.music,
    this.next,
    List<LevelRecipe>? recipes,
    Map<String, Map<String, Object?>>? behaviors,
    Map<String, Prefab>? prefabs,
    Map<String, Object?>? renderSettings,
    Map<String, Object?> source = const <String, Object?>{},
  }) : renderSettings = Map<String, Object?>.unmodifiable(
         renderSettings ?? const <String, Object?>{},
       ),
       brushes = LevelIds.unique(
         brushes ?? <Brush>[],
         idOf: (Brush b) => b.id,
         withId: (Brush b, String id) => b.withId(id),
         taken: <String>{},
       ),
       recipes = recipes ?? <LevelRecipe>[],
       behaviors = behaviors ?? <String, Map<String, Object?>>{},
       prefabs = prefabs ?? <String, Prefab>{},
       _source = <String, Object?>{
         for (final MapEntry(:key, :value) in source.entries)
           if (!FormatSpec.envelopeKeys.contains(key)) key: value,
       },
       entities = LevelIds.unique(
         entities ?? <EntityDef>[],
         idOf: (EntityDef e) => e.id,
         withId: (EntityDef e, String id) => e.withId(id),
         taken: <String>{},
       ),
       lights = LevelIds.unique(
         lights ?? <LevelLight>[],
         idOf: (LevelLight l) => l.id,
         withId: (LevelLight l, String id) => l.withId(id),
         taken: <String>{},
       ),
       materials = materials ?? <String, LevelMaterial>{},
       fogColor = fogColor?.clone() ?? _defaultFogColor,
       world = _worldOf(world),
       super(unknown: FormatDocument.unknownIn(source, known: _knownKeys));

  /// The level as a format: `f3d.level`.
  ///
  /// A document without the envelope — `{"version": 2, ...}`, or no version
  /// at all — is the version it says, or 1.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.level',
    version: formatVersion,
    suffixes: <String>['.level.json'],
    fixture: 'test/fixtures/v<N>/first.level.json',
    migrations: <FormatMigration>[_identity, _identity, _gravityIntoWorld],
  );

  @override
  FormatSpec get spec => format;

  /// The top-level keys this reader takes; anything else is [unknown].
  static const Set<String> _knownKeys = <String>{
    'name',
    'brushes',
    'entities',
    'lights',
    'materials',
    'heightfield',
    'fogColor',
    'fogDensity',
    'gravity',
    'world',
    'music',
    'next',
    'recipes',
    'behaviours',
    'prefabs',
    'renderSettings',
  };

  /// The plugin namespaces this level's entities carry components of, which
  /// a reader has to understand to open it: see [EntityDef.components].
  @override
  List<String> get requires => <String>{
    for (final entity in <EntityDef>[
      ...entities,
      for (final prefab in prefabs.values) ...prefab.entities,
    ])
      ...entity.components.keys,
  }.toList()..sort();

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

  /// Bumped when an existing field changes meaning, **or when an older
  /// reader ignoring a new one would open a different level**. Adding a field
  /// an older reader may safely skip does not need it.
  ///
  /// A bump adds the step from the previous version to [format]'s
  /// migrations and a fixture under `test/fixtures/v<N>/`.
  ///
  /// **Version 2 is [prefabs]**, and with it the depth layer of a brush and
  /// of a material. The second half of the rule above is why: a version-1
  /// reader would keep a prefab instance as one entity of an unknown type
  /// and drop everything the prefab stands for — the hazard [heightfield]
  /// names, where the floor goes missing rather than being drawn slightly
  /// wrong.
  ///
  /// **Version 3 is ids** (decision 9 of `tasks/1.0-api-review.md`): every
  /// brush, light and entity has an `id`, an entity's properties sit under
  /// `props` and a plugin's under `components.<namespace>`, and a prefab
  /// instance's overrides are keyed by id paths. Every level is written at
  /// version 3, since every level has ids.
  ///
  /// **Version 4 is the world** (decision 1 of `tasks/1.0-physics-audit.md`):
  /// a level's gravity, air, wind, medium and step rate under `world`, the
  /// gravity a vector. A version-3 reader would drop a level's sea or its
  /// thin air and play it on the game's own world, a different level, so
  /// the version marks it; a version-3 document's `"gravity": N` is lifted
  /// into `"world": {"gravity": N}`.
  static const int formatVersion = 4;

  /// 3 → 4: the scalar `gravity` moves into `world`, where a reader of
  /// [WorldProperties.fromJson] takes a number as so many m/s² down y.
  static Map<String, Object?> _gravityIntoWorld(Map<String, Object?> document) {
    if (!document.containsKey('gravity')) return document;
    final gravity = document.remove('gravity');
    final world = switch (document['world']) {
      final Map<String, Object?> already => <String, Object?>{...already},
      _ => <String, Object?>{},
    };
    world.putIfAbsent('gravity', () => gravity);
    return document..['world'] = world;
  }

  /// The lift between two versions whose documents read the same.
  ///
  /// **1 → 2** only adds — `prefabs`, an entity of type `prefab`,
  /// `depthLayer` on a brush and on a material — and no level written at
  /// version 1 uses any of those words. **2 → 3** is the identity on the
  /// document too, and the work happens in the reader: ids are derived for
  /// what has none, so the same in every reader ([LevelIds.derive]);
  /// properties at the top of a row are read as properties by
  /// [EntityDef.fromJson]; and overrides addressed by name or `#<index>`
  /// are turned into id paths once the prefabs they walk are read
  /// ([legacyOverridesToIds]).
  static Map<String, Object?> _identity(Map<String, Object?> document) =>
      document;

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

  /// What this level changes of the world it is played in: the keys of a
  /// [WorldProperties]' JSON it names — `gravity` (a vector, or m/s² down),
  /// `airTemperature`, `airPressure`, `airDensity`, `wind`, `medium` — and
  /// nothing it does not, so the game's own world shows through. Empty for a
  /// level that changes nothing. (A `stepRate` here, which a world carried
  /// before 1.0.0-rc.1, is kept with the rest and read by nothing: the rate
  /// is the loop's `WorldTiming`.)
  ///
  /// **The world's, written where the rest of the world is** — beside its
  /// fog — so a level set on the Moon says `"world": {"gravity": 1.62}` once
  /// and every body, runner, spark and stream in it reads that. A level does
  /// not say a whole world because a world's defaults are the game's to
  /// choose — a platformer's run falls at 24 m/s², a laboratory at
  /// [standardGravity] — and a level that does not say must not overrule
  /// them. [worldOver] lays it over the game's.
  ///
  /// Kept as it was written, unknown keys and all, and checked when read: a
  /// value [WorldProperties.fromJson] would refuse is a [LevelFormatException].
  final Map<String, Object?> world;

  /// The world this level is played in: [game]'s — the world a game stages
  /// every level in — with what [world] names laid over it.
  ///
  /// With [materials], the world's medium is looked up there, and a level
  /// filled with a material nobody registered is refused with an
  /// `UnknownMaterialException` naming the plugin it needs — before a
  /// single body falls through it.
  WorldProperties worldOver(
    WorldProperties game, {
    MaterialCatalog? materials,
  }) {
    final properties = WorldProperties.fromJson(world, base: game);
    if (materials != null && properties.medium != 'f3d.air') {
      materials.require(properties.medium);
    }
    return properties;
  }

  static Map<String, Object?> _worldOf(Map<String, Object?>? world) {
    final merged = <String, Object?>{...?world};
    try {
      WorldProperties.fromJson(merged);
    } on WorldPropertiesFormatException catch (error) {
      throw LevelFormatException('"world": ${error.message}');
    }
    return Map<String, Object?>.unmodifiable(merged);
  }

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

  /// Behaviour trees by name, each the document `BehaviorTree.read` takes;
  /// an entity names the one it runs in a `behavior` property.
  ///
  /// **Kept as documents, not as trees.** What a leaf kind means is the
  /// game's — `BehaviorKinds` — and a level is read before any game is
  /// there to ask; whether a tree reads is a `LevelRule` the game brings,
  /// `BehaviorsRead`, with its own kinds.
  final Map<String, Map<String, Object?>> behaviors;

  /// Templates by id, each a tree of entities an instance places as one
  /// thing — see [Prefab] and [PrefabInstance].
  ///
  /// **Kept, not expanded**, as [recipes] are: [entities] holds the instance
  /// rows, and what they stand for appears only in `expandPrefabs(level)`,
  /// which `expandRecipes` calls first. So a change to a template reaches
  /// every instance the next time the level is used, and an editor that
  /// saves the level writes instances back rather than copies.
  final Map<String, Prefab> prefabs;

  /// Render settings this level asks for, each under its settings slot's id
  /// — the JSON `SettingsExtensions.toJson` writes, read back with
  /// `SettingsExtensions.fromJson` against the slots a renderer's plugins
  /// added (`renderer.renderSteps.settings`).
  ///
  /// **Kept as JSON, by id.** A level is read before any renderer, and by a
  /// server that has none; what an id means is the addon's that defined it.
  /// An id no installed addon knows is written back as it was read.
  ///
  /// **Additive**, as [heightfield] was: a reader that does not know it
  /// draws the level with the game's own settings.
  final Map<String, Object?> renderSettings;

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
  ///
  /// **The envelope is not part of it**, the version included. `format`,
  /// `version`, `requires` and `generator` say how the document was written,
  /// not what the level is. A digest that moved when a tool's name did would
  /// refuse every run recorded against the level, and one that held the
  /// version did exactly that on every bump of the format: 3 → 4 moved the
  /// hash of every level, edited or not.
  String get digestHex => contentDigestHex(<String, Object?>{
    for (final MapEntry(:key, :value) in toJson().entries)
      if (!FormatSpec.envelopeKeys.contains(key)) key: value,
  });

  /// Reads a level document, in any format version up to [formatVersion].
  ///
  /// [understands] names the plugin namespaces whose components this reader
  /// can keep — the ones a level's `requires` may name. A level requiring one
  /// it does not name is refused, naming it, rather than opened without
  /// what that plugin put there.
  ///
  /// Throws [LevelFormatException] for a document that is not a level, is
  /// from a newer build, or has a field of the wrong type.
  factory Level.fromJson(
    Map<String, Object?> json, {
    Set<String> understands = const <String>{},
  }) => Level._read(json, understands);

  /// Reads a level from its JSON text, as [Level.fromJson] reads the decoded
  /// map.
  ///
  /// Throws [LevelFormatException] for text that is not JSON or not a JSON
  /// object, as well as for everything [Level.fromJson] refuses.
  factory Level.parse(
    String source, {
    Set<String> understands = const <String>{},
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw LevelFormatException('a level is JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const LevelFormatException('a level is a JSON object');
    }
    return Level.fromJson(decoded, understands: understands);
  }

  factory Level._read(Map<String, Object?> document, Set<String> understands) {
    // The envelope first: another format, a newer version or a requirement
    // nobody here understands is refused before a field is read. The
    // namespaces the caller understands are taken out of `requires` for the
    // check only; the document keeps them.
    final checked = format.open(<String, Object?>{
      ...document,
      if (document['requires'] case final List<Object?> requires)
        'requires': <Object?>[
          for (final name in requires)
            if (!understands.contains(name)) name,
        ],
    }, refuse: LevelFormatException.new);
    final json = <String, Object?>{
      ...checked,
      if (document.containsKey('requires')) 'requires': document['requires'],
    };
    final version = format.versionOf(document);

    final prefabs = json
        .objectMap('prefabs')
        .map(
          (String key, Map<String, Object?> value) =>
              MapEntry<String, Prefab>(key, Prefab.fromJson(value)),
        );
    final entities = json.objects('entities').map(EntityDef.fromJson).toList();
    // Before format 3 an override named the entity it changes by its name or
    // its place in the prefab. Turned into id paths here, once the prefabs
    // they walk are read, so a level read from an old file and saved is a
    // level whose overrides survive a rename.
    EntityDef byIds(EntityDef entity) => switch (PrefabInstance.of(entity)) {
      final PrefabInstance instance when instance.overrides.isNotEmpty =>
        EntityDef(
          type: entity.type,
          id: entity.id,
          position: entity.position,
          yaw: entity.yaw,
          name: entity.name,
          properties: <String, Object?>{
            ...entity.properties,
            'overrides': legacyOverridesToIds(
              instance.overrides,
              instance.prefab,
              prefabs,
            ),
          },
          components: entity.components,
        ),
      _ => entity,
    };

    return Level(
      name: json.textOrNull('name') ?? 'untitled',
      brushes: json.objects('brushes').map(Brush.fromJson).toList(),
      entities: version >= 3 ? entities : entities.map(byIds).toList(),
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
        null => null,
        final Map<String, Object?> section => Heightfield.fromJson(section),
        final other => throw LevelFormatException(
          '"heightfield" must be an object, not $other',
        ),
      },
      fogColor: json.vector3('fogColor', fallback: _defaultFogColor),
      fogDensity: json.numberOr('fogDensity', 0.0),
      world: switch (json['world']) {
        null => null,
        final Map<String, Object?> section => section,
        final other => throw LevelFormatException(
          '"world" must be an object, not $other',
        ),
      },
      music: json.textOrNull('music'),
      next: json.textOrNull('next'),
      recipes: json.objects('recipes').map(LevelRecipe.fromJson).toList(),
      behaviors: Map<String, Map<String, Object?>>.of(
        json.objectMap('behaviours'),
      ),
      prefabs: version >= 3
          ? prefabs
          : prefabs.map(
              (String key, Prefab prefab) => MapEntry<String, Prefab>(
                key,
                Prefab.fromJson(<String, Object?>{
                  ...prefab.toJson(),
                  'entities': <Object?>[
                    for (final entity in prefab.entities)
                      byIds(entity).toJson(),
                  ],
                }),
              ),
            ),
      renderSettings: switch (json['renderSettings']) {
        null => null,
        final Map<String, Object?> section => section,
        _ => throw const LevelFormatException(
          '"renderSettings" must be an object of settings by id',
        ),
      },
      source: json,
    );
  }

  /// The document: the envelope first, then the level, then every key this
  /// build did not know, where it was.
  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(requires: requires),
    ..._body(),
  };

  Map<String, Object?> _body() => writeThrough(_source, <WriteThroughField>[
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
    WriteThroughField('world', world, whenAbsent: world.isNotEmpty),
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
    WriteThroughField('behaviours', <String, Object?>{
      for (final MapEntry(:key, :value) in behaviors.entries) key: value,
    }, whenAbsent: behaviors.isNotEmpty),
    WriteThroughField('prefabs', <String, Object?>{
      for (final MapEntry(:key, :value) in prefabs.entries) key: value.toJson(),
    }, whenAbsent: prefabs.isNotEmpty),
    WriteThroughField(
      'renderSettings',
      renderSettings,
      whenAbsent: renderSettings.isNotEmpty,
    ),
  ]);
}
