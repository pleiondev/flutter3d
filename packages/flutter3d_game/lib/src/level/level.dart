import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';

/// One key a document may carry, with the value this object would write.
///
/// See [_writeThrough] for what is done with it.
final class _Field {
  const _Field(this.key, this.value, {this.whenAbsent = true});

  final String key;
  final Object? value;

  /// Whether to add this key to a document that did not carry it.
  ///
  /// False for a value equal to its default: a document that has nothing to say
  /// must go on saying nothing, which is what keeps a level a readable diff.
  final bool whenAbsent;
}

/// Writes [fields] into a map, through the document this object came from.
///
/// **The rule that makes a level survive being read and written back**, and it
/// is three lines long:
///
/// * a key the document had, whose value has not changed, is given back
///   **exactly as it arrived** — same position, same `4` rather than `4.0`,
///   even when it happens to equal the default;
/// * a key the document had, whose value has changed, is written canonically
///   **in the place the document put it**;
/// * a key the document did not have is added only when it has something to
///   say, and everything this format does not know is copied through untouched.
///
/// The last of those is why `generatedBy` and the racing document's `track`
/// come back: they are simply not this type's business, and a writer that
/// deletes what it does not recognise is a writer nobody can use. `EntityDef`
/// has held that principle since it was written — «an editor written against a
/// later version must not silently strip the properties it does not recognise»
/// — and this is the rest of the format catching up.
///
/// [source] is empty for an object built in Dart rather than read, and then
/// this degrades exactly to the elide-by-default writer it replaces.
Map<String, Object?> _writeThrough(
  Map<String, Object?> source,
  List<_Field> fields,
) {
  final byKey = <String, _Field>{for (final field in fields) field.key: field};
  final out = <String, Object?>{};

  for (final entry in source.entries) {
    final field = byKey[entry.key];
    if (field == null) {
      out[entry.key] = entry.value;
      continue;
    }
    out[entry.key] =
        _sameValue(entry.value, field.value) ? entry.value : field.value;
  }

  for (final field in fields) {
    if (out.containsKey(field.key) || !field.whenAbsent) continue;
    out[field.key] = field.value;
  }
  return out;
}

/// The values a document is allowed to leave unsaid.
///
/// Named rather than written twice: a default that appears in the constructor
/// and again in the writer is two numbers that must agree, and one day will
/// not.
final Vector4 _defaultBaseColor = Vector4(0.5, 0.5, 0.5, 1.0);
final Vector3 _origin = Vector3.zero();
final Vector3 _white = Vector3(1.0, 1.0, 1.0);

/// One number as it survives a `Vector3`, which is single precision.
final Float32List _narrow = Float32List(1);
double _asFloat32(double value) {
  _narrow[0] = value;
  return _narrow[0];
}

/// Whether two decoded JSON values say the same thing.
///
/// **Numerically**, so the `4` a level document wrote and the `4.0` this code
/// holds are the same value and the document keeps its own spelling. Without
/// that, reading and writing `crypt.json` would rewrite a hundred and fifty-six
/// coordinates that nobody touched.
bool _sameValue(Object? a, Object? b) {
  if (a is num && b is num) {
    final x = a.toDouble();
    final y = b.toDouble();
    if (x == y) return true;
    // **And at the precision the value actually survives at.** Every coordinate
    // in this format passes through a `Vector3`, which is single precision, so
    // a document saying `0.034` gets `0.034000001847743988` back — a different
    // double denoting the same stored number. Comparing as doubles would
    // rewrite every vector in every level on the first save.
    return _asFloat32(x) == _asFloat32(y);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameValue(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_sameValue(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Raised when a document is not a level, or is one this build cannot read.
final class LevelFormatException implements Exception {
  const LevelFormatException(this.message);

  final String message;

  @override
  String toString() => 'LevelFormatException: $message';
}

/// One axis-aligned block of level geometry.
///
/// The whole level is these. It is a decision about authoring as much as about
/// physics: a brush is what an editor can drag out in two clicks, what a box
/// sweep handles exactly, and what a grid indexes without thinking. The cost is
/// that there are no slopes, and vertical movement comes from stairs and lifts.
final class Brush {
  Brush({
    required Vector3 centre,
    required Vector3 size,
    this.material = 'default',
    this.solid = true,
    this.castsShadow = true,
    String? surface,
    this.layer,
    this.ramp,
    Map<String, Object?> source = const <String, Object?>{},
  })  : centre = centre.clone(),
        size = size.clone(),
        // ignore: prefer_initializing_formals
        _source = source,
        // ignore: prefer_initializing_formals
        _surface = surface;

  /// The document this brush was read from, or empty when it was built in code.
  ///
  /// Kept so [toJson] can give a document back the way it arrived. See
  /// [_writeThrough].
  final Map<String, Object?> _source;

  final Vector3 centre;
  final Vector3 size;

  /// Name of an entry in [Level.materials]. What this brush **looks** like.
  final String material;

  final String? _surface;

  /// What this brush is **made of**, for physics and for sound.
  ///
  /// Separate from [material], which is how it is shaded, and the separation is
  /// the point: a level wanting stone-looking ice, or a metal grate you can
  /// fall through, could not say so while the only word for a surface was its
  /// paint. The engine never compares this to anything — a game reads it and
  /// decides what `ice` means, exactly as it decides what a `crate` is.
  ///
  /// Falls back to [material], so every level ever authored keeps behaving the
  /// way it does and a document that has nothing to say says nothing.
  String get surface => _surface ?? material;

  /// The collision bit this brush sits on, or null for the world's default.
  ///
  /// [Collider] has always had a layer and the level document has been the one
  /// thing unable to name it. A one-way platform, a grate only monsters walk
  /// through, a wall the AI respects and the player does not — all of them are
  /// a brush on a bit of its own, and all of them were unauthorable.
  final int? layer;

  /// Whether this brush stops anything.
  ///
  /// False for decoration — a moulding, a painted alcove, the lip of a step
  /// that is already inside the block below it. A player who cannot walk
  /// through a purely visual detail is a player fighting the level.
  final bool solid;

  /// Whether it takes part in the lighting, as opposed to merely being lit.
  ///
  /// **True by default, and the one place it is worth saying otherwise is a
  /// fence.** A boundary wall exists so the level cannot be walked out of; it
  /// is not architecture. The teaching level's are sixteen metres tall — raised
  /// from six when an autopilot climbed a chimney and walked off the top of the
  /// world — and at the sun this game uses they lay a hard-edged band of shadow
  /// across a third of a twenty-two metre level. Measured: eight per cent of a
  /// frame, and it reads as a shadow following the player because they walk
  /// along it.
  ///
  /// Steepening the sun removes it and costs more than it saves: the same frame
  /// goes from 23.8% dark to 29.4%, because a sun overhead lights vertical
  /// surfaces edge-on. The wall was never the thing that should have been
  /// lighting the level.
  final bool castsShadow;

  /// Which way this brush climbs, or null for an ordinary block.
  ///
  /// **A ramp is a brush with a corner cut off**, not a new kind of thing in
  /// the document: the same centre, the same size, the same material and the
  /// same surface. Set it and the block fills its box at one end and tapers to
  /// an edge at the other, which is what makes it walkable rather than a step
  /// as tall as itself.
  ///
  /// There is no angle here on purpose. The slope runs corner to corner, so the
  /// steepness is the brush's own proportions — a block twice as long as it is
  /// tall climbs at twenty-six degrees — and an author reads it off the numbers
  /// already typed rather than keeping two of them in agreement.
  final WedgeUphill? ramp;

  /// Whether this brush is a ramp rather than a block.
  bool get isRamp => ramp != null;

  Vector3 get halfExtents => size / 2.0;
  Vector3 get min => centre - halfExtents;
  Vector3 get max => centre + halfExtents;

  /// How much volume this brush shares with [other]. Zero when they only
  /// touch.
  ///
  /// A method on the brush rather than a helper inside the validator, because
  /// it is a fact about two brushes and the editor will want it too.
  double overlapVolumeWith(Brush other) {
    final x = math.min(max.x, other.max.x) - math.max(min.x, other.min.x);
    if (x <= 0.0) return 0.0;
    final y = math.min(max.y, other.max.y) - math.max(min.y, other.min.y);
    if (y <= 0.0) return 0.0;
    final z = math.min(max.z, other.max.z) - math.max(min.z, other.min.z);
    if (z <= 0.0) return 0.0;
    return x * y * z;
  }

  factory Brush.fromJson(Map<String, Object?> json) => Brush(
        centre: json.vector3('at'),
        size: json.vector3('size'),
        material: json.text('material') ?? 'default',
        solid: json.flagOr('solid', fallback: true),
        castsShadow: json.flagOr('castsShadow', fallback: true),
        surface: json.text('surface'),
        layer: json.integer('layer'),
        ramp: _rampFromName(json.text('ramp')),
        source: json,
      );

  /// The four directions a ramp may climb, by the name a document uses.
  ///
  /// Spelled out rather than taken from `WedgeUphill.name`, because the enum's
  /// names belong to the physics package and a level document is a file format:
  /// renaming a Dart identifier must not silently invalidate every level ever
  /// saved.
  static const Map<String, WedgeUphill> _ramps = <String, WedgeUphill>{
    '+x': WedgeUphill.positiveX,
    '-x': WedgeUphill.negativeX,
    '+z': WedgeUphill.positiveZ,
    '-z': WedgeUphill.negativeZ,
  };

  static WedgeUphill? _rampFromName(String? name) {
    if (name == null) return null;
    final found = _ramps[name];
    if (found == null) {
      throw LevelFormatException(
        'brush ramp "$name" is not one of ${_ramps.keys.join(', ')}',
      );
    }
    return found;
  }

  static String _rampName(WedgeUphill uphill) =>
      _ramps.entries.firstWhere((MapEntry<String, WedgeUphill> e) =>
          e.value == uphill).key;

  Map<String, Object?> toJson() => _writeThrough(_source, <_Field>[
        _Field('at', centre.toJson()),
        _Field('size', size.toJson()),
        _Field('material', material, whenAbsent: material != 'default'),
        _Field('solid', solid, whenAbsent: !solid),
        _Field('castsShadow', castsShadow, whenAbsent: !castsShadow),
        _Field('surface', _surface, whenAbsent: _surface != null),
        _Field('layer', layer, whenAbsent: layer != null),
        _Field('ramp', ramp == null ? null : _rampName(ramp!),
            whenAbsent: ramp != null),
      ]);
}

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
  })  : baseColor = baseColor ?? Vector4(0.5, 0.5, 0.5, 1.0),
        // ignore: prefer_initializing_formals
        _source = source;

  /// The document this material was read from. See [_writeThrough].
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
        baseColor: json.vector4(
          'baseColor',
          fallback: Vector4(0.5, 0.5, 0.5, 1.0),
        ),
        roughness: json.numberOr('roughness', 0.85),
        metallic: json.numberOr('metallic', 0.0),
        emissive: json.numberOr('emissive', 0.0),
        texelsPerMetre: json.numberOr('texelsPerMetre', 1.0),
        albedo: json.text('albedo'),
        normal: json.text('normal'),
        orm: json.text('orm'),
        source: json,
      );

  Map<String, Object?> toJson() => _writeThrough(_source, <_Field>[
        _Field('baseColor', baseColor.toJson(),
            whenAbsent: baseColor != _defaultBaseColor),
        _Field('roughness', roughness, whenAbsent: roughness != 0.85),
        _Field('metallic', metallic, whenAbsent: metallic != 0.0),
        _Field('emissive', emissive, whenAbsent: emissive != 0.0),
        _Field('texelsPerMetre', texelsPerMetre,
            whenAbsent: texelsPerMetre != 1.0),
        _Field('albedo', albedo, whenAbsent: albedo != null),
        _Field('normal', normal, whenAbsent: normal != null),
        _Field('orm', orm, whenAbsent: orm != null),
      ]);
}

enum LevelLightType { directional, point, spot }

/// A light placed by the level rather than by the renderer.
final class LevelLight {
  LevelLight({
    this.type = LevelLightType.point,
    Vector3? position,
    Vector3? direction,
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    this.castsShadow = false,
    this.name,
    Map<String, Object?> source = const <String, Object?>{},
  })  : position = position?.clone() ?? Vector3.zero(),
        direction = direction?.clone() ?? Vector3(0.0, -1.0, 0.0),
        // ignore: prefer_initializing_formals
        _source = source,
        color = color?.clone() ?? Vector3(1.0, 1.0, 1.0);

  /// The document this light was read from. See [_writeThrough].
  final Map<String, Object?> _source;

  final LevelLightType type;
  final Vector3 position;
  final Vector3 direction;
  final Vector3 color;
  final double intensity;
  final double range;

  /// Whether this light is a candidate for a shadow map.
  ///
  /// A request, not a promise: shadows cost six passes per light, so the
  /// renderer grants it to the nearest couple and ignores the rest.
  final bool castsShadow;

  final String? name;

  factory LevelLight.fromJson(Map<String, Object?> json) => LevelLight(
        type: json.enumValue(
          'type',
          LevelLightType.values,
          LevelLightType.point,
          describedAs: 'light type',
        ),
        position: json.vector3('at', fallback: Vector3.zero()),
        direction: json.vector3(
          'direction',
          fallback: Vector3(0.0, -1.0, 0.0),
        ),
        color: json.vector3('color', fallback: Vector3(1.0, 1.0, 1.0)),
        intensity: json.numberOr('intensity', 1.0),
        range: json.numberOr('range', 0.0),
        castsShadow: json.flagOr('castsShadow'),
        name: json.text('name'),
        source: json,
      );

  Map<String, Object?> toJson() => _writeThrough(_source, <_Field>[
        _Field('type', type.name, whenAbsent: type != LevelLightType.point),
        _Field('at', position.toJson(), whenAbsent: position != _origin),
        _Field('direction', direction.toJson(),
            whenAbsent: type != LevelLightType.point),
        _Field('color', color.toJson(), whenAbsent: color != _white),
        _Field('intensity', intensity, whenAbsent: intensity != 1.0),
        _Field('range', range, whenAbsent: range != 0.0),
        _Field('castsShadow', castsShadow, whenAbsent: castsShadow),
        _Field('name', name, whenAbsent: name != null),
      ]);
}

/// Anything in the level that is not geometry: a spawn, a monster, a pickup, a
/// door, a trigger, a note on the wall.
///
/// One type with a property bag, rather than a class per kind. There will be
/// thirty kinds before the game is finished, the editor has to handle them all
/// the same way, and a class hierarchy buys type safety at exactly the layer
/// that reads them from JSON and therefore cannot have it anyway. The typed
/// accessors below are where the safety actually goes.
final class EntityDef {
  EntityDef({
    required this.type,
    Vector3? position,
    this.yaw = 0.0,
    this.name,
    Map<String, Object?>? properties,
    Map<String, Object?> source = const <String, Object?>{},
  })  : position = position?.clone() ?? Vector3.zero(),
        // ignore: prefer_initializing_formals
        _source = source,
        properties = Map<String, Object?>.unmodifiable(
          properties ?? const <String, Object?>{},
        );

  /// The document this entity was read from. See [_writeThrough].
  final Map<String, Object?> _source;

  final String type;
  final Vector3 position;

  /// Facing, in radians about Y. Nothing in this game tilts.
  final double yaw;

  /// Referred to by other entities — the lift a button calls, the door a key
  /// opens.
  final String? name;

  final Map<String, Object?> properties;

  /// Keys the entity itself owns, which therefore never reach [properties].
  static const Set<String> reservedKeys = <String>{
    'type',
    'at',
    'yaw',
    'name',
  };

  String? string(String key) => properties[key] as String?;

  double? number(String key) {
    final value = properties[key];
    if (value is num) return value.toDouble();
    return null;
  }

  int? integer(String key) {
    final value = properties[key];
    if (value is num) return value.toInt();
    return null;
  }

  bool flag(String key, {bool orElse = false}) =>
      properties[key] as bool? ?? orElse;

  Vector3? vector(String key) {
    final value = properties[key];
    if (value is! List || value.length < 3) return null;
    return Vector3(
      (value[0] as num).toDouble(),
      (value[1] as num).toDouble(),
      (value[2] as num).toDouble(),
    );
  }

  factory EntityDef.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw const LevelFormatException('an entity has no "type"');
    }
    // Everything not reserved is a property, so the format grows by writing
    // new keys rather than by changing the reader.
    final properties = <String, Object?>{
      for (final entry in json.entries)
        if (!reservedKeys.contains(entry.key)) entry.key: entry.value,
    };
    return EntityDef(
      type: type,
      position: json.vector3('at', fallback: Vector3.zero()),
      yaw: json.numberOr('yaw', 0.0),
      name: json.text('name'),
      properties: properties,
      source: json,
    );
  }

  Map<String, Object?> toJson() => _writeThrough(_source, <_Field>[
        _Field('type', type),
        _Field('at', position.toJson()),
        _Field('yaw', yaw, whenAbsent: yaw != 0.0),
        _Field('name', name, whenAbsent: name != null),
        for (final entry in properties.entries) _Field(entry.key, entry.value),
      ]);
}

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

  /// The document this level was read from. See [_writeThrough].
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
      name: json.text('name') ?? 'untitled',
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
      music: json.text('music'),
      next: json.text('next'),
      source: json,
    );
  }

  Map<String, Object?> toJson() => _writeThrough(_source, <_Field>[
        _Field('version', formatVersion),
        _Field('name', name),
        _Field('fogColor', fogColor.toJson()),
        _Field('fogDensity', fogDensity, whenAbsent: fogDensity != 0.0),
        _Field('music', music, whenAbsent: music != null),
        _Field('next', next, whenAbsent: next != null),
        _Field('materials', <String, Object?>{
          for (final entry in materials.entries) entry.key: entry.value.toJson(),
        }, whenAbsent: materials.isNotEmpty),
        _Field('brushes', brushes.map((Brush b) => b.toJson()).toList(),
            whenAbsent: brushes.isNotEmpty),
        _Field('lights', lights.map((LevelLight l) => l.toJson()).toList(),
            whenAbsent: lights.isNotEmpty),
        _Field('entities', entities.map((EntityDef e) => e.toJson()).toList(),
            whenAbsent: entities.isNotEmpty),
      ]);
}
