/// `.f3dfx`: particle effects written as data — item 4 of
/// `tasks/1.0-scope-additions.md`.
///
/// ```json
/// {
///   "f3dfx": 1,
///   "effects": [
///     {
///       "name": "embers",
///       "count": 40,
///       "lifetime": [0.5, 1.4],
///       "size": [0.05, 0.14],
///       "color": [2.6, 1.1, 0.3, 1.0],
///       "emitter": {"shape": "sphere", "speed": [6.0, 22.0]},
///       "affectors": [
///         {"type": "gravity", "scale": 1.12},
///         {"type": "drag", "perSecond": 1.2},
///         {"type": "fade", "startsAt": 0.5}
///       ],
///       "render": {"drawing": "billboard", "blend": "additive"},
///       "on": [{"event": "elements.exploded", "emit": "burst"}]
///     }
///   ]
/// }
/// ```
///
/// **The particle system's own vocabulary, spelled as JSON**, and nothing
/// beside it: an effect is the [ParticleEffect] a game would have written in
/// Dart — an emitter, a lifetime, a size, a colour and affectors in order —
/// so an effect read from a document and the same effect written in Dart are
/// one simulation, particle for particle. That is what the tests hold the
/// documents of the demos to, rather than a picture somebody judged close.
///
/// What a document adds to the Dart is what the Dart left to the call site:
/// how it is drawn ([EffectRender]), a standing rate, and the bus events it
/// goes off on ([EffectTrigger]). `ParticleEffects` is what installs a
/// document into an engine; `.f3dplugin`'s `effects` names these documents.
///
/// **Versioned as every engine file is** (decision 8 of
/// `tasks/1.0-stability.md`): `f3dfx` carries the version, a 1.x engine reads
/// every 1.x document through [EffectDocument._migrations], a newer one is
/// refused with the version that reads it, and keys this build does not know
/// are kept — on the document and on each effect — and written back.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show FormatDocument, FormatMigration, FormatSpec, Flutter3dFormatException;
import 'package:vector_math/vector_math.dart';

import 'flipbook.dart';
import 'particle.dart';
import 'particle_affector.dart';
import 'particle_collision.dart';
import 'particle_curve.dart';
import 'particle_effect.dart';
import 'particle_emitter.dart';

/// The extension an effect document is saved under.
const String effectDocumentExtension = '.f3dfx';

/// An effect document that cannot be read, with the sentence that says why
/// and where.
final class EffectFormatException extends Flutter3dFormatException {
  const EffectFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'EffectFormatException: $message';
}

/// Reads an emitter of a shape this package does not have, from its JSON.
typedef EffectEmitterReader =
    ParticleEmitter Function(Map<String, Object?> json);

/// Reads an affector of a type this package does not have, from its JSON.
typedef EffectAffectorReader =
    ParticleAffector Function(Map<String, Object?> json);

/// The words a document may use beyond this package's own: emitter shapes,
/// affector types and eases a game or a plugin defines.
///
/// **Open, as the affectors are.** A game that wrote a `vortex` affector in
/// Dart names it here and every document it reads can say
/// `{"type": "vortex"}`; a word nobody defined is refused with the list of
/// the ones that are, because a document whose effect silently lost an
/// affector draws something nobody wrote.
final class EffectVocabulary {
  const EffectVocabulary({
    this.emitters = const <String, EffectEmitterReader>{},
    this.affectors = const <String, EffectAffectorReader>{},
    this.eases = const <KeyEase>[],
  });

  /// This package's own words and no others.
  static const EffectVocabulary standard = EffectVocabulary();

  /// Extra emitter shapes, by the `shape` a document names.
  final Map<String, EffectEmitterReader> emitters;

  /// Extra affector types, by the `type` a document names.
  final Map<String, EffectAffectorReader> affectors;

  /// Extra eases, by their [KeyEase.name].
  final List<KeyEase> eases;
}

/// How an effect's particles are drawn.
///
/// **A class of constants rather than an enum**, as every set a later minor
/// may grow is here: a drawing added in 1.x would break every exhaustive
/// `switch` written against an enum.
final class EffectDrawing {
  const EffectDrawing._(this.word);

  /// A camera-facing quad per particle — `ParticleContributor`, with a
  /// sprite or the procedural disc.
  static const EffectDrawing billboard = EffectDrawing._('billboard');

  /// A copy of one mesh per particle — `MeshParticleContributor`.
  static const EffectDrawing mesh = EffectDrawing._('mesh');

  /// A six-way lit sheet — `ParticleContributor` with a `SixWayMaterial`.
  static const EffectDrawing sixWay = EffectDrawing._('sixWay');

  /// Every drawing this build knows.
  static const List<EffectDrawing> values = <EffectDrawing>[
    billboard,
    mesh,
    sixWay,
  ];

  /// What a document calls it.
  final String word;

  @override
  String toString() => word;
}

/// How an effect's particles combine with what is behind them. A class of
/// constants, for [EffectDrawing]'s reason.
final class EffectBlend {
  const EffectBlend._(this.word);

  /// Added: unsorted, one draw, and only ever brighter. Billboards and
  /// meshes.
  static const EffectBlend additive = EffectBlend._('additive');

  /// What is behind times one minus the colour: soot and shadow, unsorted.
  /// Meshes (`MeshParticleContributor.darkening`).
  static const EffectBlend darkening = EffectBlend._('darkening');

  /// Over what is behind, sorted far to near: the six-way sheet's.
  static const EffectBlend over = EffectBlend._('over');

  /// Every blend this build knows.
  static const List<EffectBlend> values = <EffectBlend>[
    additive,
    darkening,
    over,
  ];

  /// What a document calls it.
  final String word;

  @override
  String toString() => word;
}

/// What a document says about drawing an effect: `ParticleContributor`'s
/// and `MeshParticleContributor`'s arguments, as data.
///
/// **Paths and names, not handles.** A texture is a file the application
/// decodes on its device and a mesh is one it already uploaded, so the
/// document names them and whoever builds the contributor resolves the
/// names — relative to the document, as every path a document names is.
final class EffectRender {
  const EffectRender({
    this.drawing = EffectDrawing.billboard,
    this.blend = EffectBlend.additive,
    this.texture,
    this.flipbook,
    this.softness = 0.0,
    this.mesh,
    this.sheet,
  });

  final EffectDrawing drawing;
  final EffectBlend blend;

  /// A billboard's sprite, or null for the procedural disc.
  final String? texture;

  /// The grid [texture] or [sheet] is, or null for a single image.
  final Flipbook? flipbook;

  /// `ParticleContributor.softness`: metres over which a particle fades into
  /// the scene behind it. Nought for none.
  final double softness;

  /// A mesh drawing's mesh, by the name the application gave it.
  final String? mesh;

  /// A six-way drawing's two textures: `positive` and `negative`.
  final ({String positive, String negative})? sheet;

  /// Whether two effects can share one pool and one draw: the same drawing,
  /// blend, images and softness.
  String get key =>
      '${drawing.word}|${blend.word}|${texture ?? ''}|${mesh ?? ''}|'
      '${sheet?.positive ?? ''}|${sheet?.negative ?? ''}|$softness|'
      '${flipbook == null ? '' : '${flipbook!.columns}x${flipbook!.rows}/'
                '${flipbook!.frames}/${flipbook!.loops}'}';
}

/// How a trigger emits. A class of constants, for [EffectDrawing]'s reason.
final class EffectSpawn {
  const EffectSpawn._(this.word);

  /// One burst of the effect's `count`.
  static const EffectSpawn burst = EffectSpawn._('burst');

  /// A rate for a stated time — `ParticleSystem.emitTimed`.
  static const EffectSpawn timed = EffectSpawn._('timed');

  /// Every way of emitting this build knows.
  static const List<EffectSpawn> values = <EffectSpawn>[burst, timed];

  /// What a document calls it.
  final String word;

  @override
  String toString() => word;
}

/// An effect going off when an event is published on the bus.
final class EffectTrigger {
  const EffectTrigger({
    required this.event,
    this.spawn = EffectSpawn.burst,
    this.perSecond,
    this.seconds,
    this.at,
    this.direction,
  });

  /// The event's name on the bus — `BusEvent.name`.
  final String event;

  final EffectSpawn spawn;

  /// A timed spawn's rate, in particles per second; the effect's own `rate`
  /// when null.
  final double? perSecond;

  /// A timed spawn's duration, in seconds.
  final double? seconds;

  /// Where it goes off, in scene space, whatever the event says; null for
  /// where the event says.
  final Vector3? at;

  /// Which way it leans, whatever the event says; null for the event's, or
  /// the emitter's own.
  final Vector3? direction;
}

/// One effect of a document: the particle effect it builds, and how it is
/// drawn and started.
final class EffectDescription {
  EffectDescription._({
    required this.name,
    required this.description,
    required this.effect,
    required this.rate,
    required this.render,
    required this.triggers,
    required this.unsupported,
    required this._json,
  });

  /// Unique in its document.
  final String name;
  final String? description;

  /// What `ParticleSystem.burst` and `emit` are handed.
  final ParticleEffect effect;

  /// Particles a second for a standing or timed emission, or null for an
  /// effect that only bursts.
  final double? rate;

  final EffectRender render;

  /// The bus events it goes off on, in the order written.
  final List<EffectTrigger> triggers;

  /// What the document asked for that this build reads and does not do —
  /// collision against the scene's depth, which a simulation on the CPU has
  /// no depth to read for. Each entry is a sentence a plugin list can show.
  final List<String> unsupported;

  final Map<String, Object?> _json;

  /// The effect as it was written, unknown keys included.
  Map<String, Object?> toJson() => _json;
}

/// A `.f3dfx` document: the effects it describes.
final class EffectDocument extends FormatDocument {
  EffectDocument._(this.effects, Map<String, Object?> extra)
    : super(unknown: extra);

  /// Bumped when an existing key changes meaning, with a step in
  /// [_migrations] and a fixture under `test/fixtures/v<N>/`.
  ///
  /// **2 is the format envelope** (`"format": "f3d.effect", "version": 2`)
  /// in place of version 1's `"f3dfx": 1`. Nothing an effect says changed;
  /// what changed is the key a build from before looks for its version
  /// under, so it would refuse a version-2 file as having none — the honest
  /// answer, and the reason this is a version and not an added key.
  static const int formatVersion = 2;

  /// Entry `i` lifts a document from version `i + 1` to `i + 2`.
  ///
  /// 1 → 2 is the identity: [FormatSpec.open] has read the version from
  /// `f3dfx` already, and the effects are written the same way in both.
  static const List<FormatMigration> _migrations = <FormatMigration>[_identity];

  static Map<String, Object?> _identity(Map<String, Object?> document) =>
      document;

  /// The effect format in the registry: `f3d.effect`, read from its own
  /// envelope or from version 1's `"f3dfx": 1`.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.effect',
    version: formatVersion,
    suffixes: <String>['.f3dfx'],
    fixture: 'test/fixtures/v<N>/blast.f3dfx',
    migrations: _migrations,
    legacyVersionKey: 'f3dfx',
  );

  @override
  FormatSpec get spec => format;

  /// Top-level keys this build does not know, kept as they were read — the
  /// same map as [unknown], under the name it had before the envelope.
  Map<String, Object?> get extra => unknown;

  /// In the order written; names are unique.
  final List<EffectDescription> effects;

  /// The effect called [name], or null.
  EffectDescription? operator [](String name) =>
      effects.where((e) => e.name == name).firstOrNull;

  /// Reads [text], or throws an [EffectFormatException]. [from] names the
  /// document in every message.
  factory EffectDocument.parse(
    String text, {
    String from = 'the effect document',
    EffectVocabulary vocabulary = EffectVocabulary.standard,
  }) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      throw EffectFormatException('$from is not JSON: ${error.message}');
    }
    if (json is! Map<String, Object?>) {
      throw EffectFormatException('$from is not a JSON object');
    }
    return EffectDocument.fromJson(json, from: from, vocabulary: vocabulary);
  }

  /// Reads a decoded document, or throws an [EffectFormatException] that
  /// says what is wrong and where.
  factory EffectDocument.fromJson(
    Map<String, Object?> document, {
    String from = 'the effect document',
    EffectVocabulary vocabulary = EffectVocabulary.standard,
  }) {
    final version = document['version'] ?? document['f3dfx'];
    if (version is! int || version < 1) {
      throw EffectFormatException(
        '$from has no version in it — neither "version" nor version 1\'s '
        '"f3dfx"',
      );
    }
    // A newer document, another format's or a `requires` this build does
    // not know is refused by the spec; every older one is lifted before a
    // key is read.
    final json = format.open(
      document,
      refuse: (String message) => EffectFormatException('$from: $message'),
    );
    try {
      final effects = switch (json['effects']) {
        final List<Object?> list => list,
        null => throw const EffectFormatException('it describes no "effects"'),
        _ => throw const EffectFormatException('"effects" is not a list'),
      };
      final read = <EffectDescription>[];
      for (final (index, entry) in effects.indexed) {
        if (entry is! Map<String, Object?>) {
          throw EffectFormatException('effect ${index + 1} is not an object');
        }
        final effect = _EffectReader(vocabulary).effect(entry, index);
        if (read.any((e) => e.name == effect.name)) {
          throw EffectFormatException(
            'two effects are called "${effect.name}"; a name is unique in a '
            'document',
          );
        }
        read.add(effect);
      }
      return EffectDocument._(
        List<EffectDescription>.unmodifiable(read),
        FormatDocument.unknownIn(json, known: _known, spec: format),
      );
    } on EffectFormatException catch (error) {
      throw EffectFormatException('$from: ${error.message}');
    } on FormatException catch (error) {
      // An emitter or affector reader a plugin brought may still throw the
      // SDK's own.
      throw EffectFormatException('$from: ${error.message}');
    }
  }

  static const Set<String> _known = <String>{'effects'};

  /// The document as JSON, in the envelope at [formatVersion], with every
  /// unknown key it was read with.
  Map<String, Object?> toJson() => write(<String, Object?>{
    'effects': <Object?>[for (final effect in effects) effect.toJson()],
  });
}

/// Reads one effect, with the effect's name in every message.
final class _EffectReader {
  _EffectReader(this.vocabulary);

  final EffectVocabulary vocabulary;
  String _where = '';

  EffectDescription effect(Map<String, Object?> json, int index) {
    _where = 'effect ${index + 1}';
    final name = switch (json['name']) {
      final String value when value.isNotEmpty => value,
      _ => throw EffectFormatException('$_where names no "name"'),
    };
    _where = 'effect "$name"';
    final count = switch (json['count'] ?? 1) {
      final int value when value >= 1 => value,
      final Object? other => throw EffectFormatException(
        '$_where: "count" is $other, and a burst is a whole number of '
        'particles, at least 1',
      ),
    };
    final rate = json['rate'] == null ? null : _positive(json['rate'], 'rate');
    final lifetime = _range(_required(json, 'lifetime'), 'lifetime');
    if (lifetime.min <= 0.0) {
      throw EffectFormatException(
        '$_where: a "lifetime" is seconds above nought; ${lifetime.min} is not',
      );
    }
    final size = _range(_required(json, 'size'), 'size');
    final color = _color(_required(json, 'color'), 'color');
    final emitter = _emitter(_object(_required(json, 'emitter'), 'emitter'));

    final unsupported = <String>[];
    final affectors = <ParticleAffector>[
      for (final (i, raw) in _list(json['affectors'], 'affectors').indexed)
        ?_affector(_object(raw, 'affector ${i + 1}'), unsupported),
    ];
    final render = _render(json['render']);
    final triggers = <EffectTrigger>[
      for (final (i, raw) in _list(json['on'], 'on').indexed)
        _trigger(_object(raw, 'trigger ${i + 1}'), rate),
    ];
    return EffectDescription._(
      name: name,
      description: json['description'] is String
          ? json['description']! as String
          : null,
      effect: ParticleEffect(
        count: count,
        emitter: emitter,
        lifetime: lifetime,
        size: size,
        color: color,
        affectors: List<ParticleAffector>.unmodifiable(affectors),
      ),
      rate: rate,
      render: render,
      triggers: List<EffectTrigger>.unmodifiable(triggers),
      unsupported: List<String>.unmodifiable(unsupported),
      json: Map<String, Object?>.unmodifiable(json),
    );
  }

  // ------------------------------------------------------------ emitters

  ParticleEmitter _emitter(Map<String, Object?> json) {
    final shape = json['shape'];
    final speed = json['speed'];
    switch (shape) {
      case 'sphere':
        return SphereEmitter(
          speed: speed == null ? const Range(2.0, 6.0) : _range(speed, 'speed'),
          radius: json['radius'] == null
              ? const Range.exact(0.0)
              : _range(json['radius'], 'radius'),
        );
      case 'cone':
        return ConeEmitter(
          speed: speed == null ? const Range(3.0, 8.0) : _range(speed, 'speed'),
          // The file keeps its degrees (`halfAngleDegrees`), and the
          // engine takes radians: converted here, at the reader.
          halfAngle:
              (json['halfAngleDegrees'] == null
                  ? 25.0
                  : _number(json['halfAngleDegrees'], 'halfAngleDegrees')) *
              math.pi /
              180.0,
        );
      case 'box':
        return BoxEmitter(
          halfExtents: _vector3(_required(json, 'halfExtents'), 'halfExtents'),
          speed: speed == null ? const Range(0.0, 0.0) : _range(speed, 'speed'),
          along: json['along'] == null
              ? null
              : _vector3(json['along'], 'along'),
        );
      case 'drift':
        return DriftEmitter(
          speed: speed == null ? const Range(0.3, 1.0) : _range(speed, 'speed'),
          spread: json['spread'] == null
              ? const Range(-0.3, 0.3)
              : _range(json['spread'], 'spread'),
        );
    }
    final own = shape is String ? vocabulary.emitters[shape] : null;
    if (own != null) return own(json);
    throw EffectFormatException(
      '$_where: the emitter\'s "shape" is $shape; the shapes are sphere, '
      'cone, box, drift'
      '${vocabulary.emitters.keys.map((k) => ', $k').join()}',
    );
  }

  // ----------------------------------------------------------- affectors

  ParticleAffector? _affector(
    Map<String, Object?> json,
    List<String> unsupported,
  ) {
    final type = json['type'];
    double or(String key, double fallback) =>
        json[key] == null ? fallback : _number(json[key], key);
    switch (type) {
      case 'gravity':
        // Omitted, or "world": the world's gravity, which the system hands
        // each particle (`ParticleSystem.world`), times "scale" if there is
        // one. A number is a look.
        return switch (json['acceleration']) {
          null || 'world' => ParticleGravity.world(scale: or('scale', 1.0)),
          final Object value => ParticleGravity(_number(value, 'acceleration')),
        };
      case 'drag':
        return ParticleDrag(_number(_required(json, 'perSecond'), 'perSecond'));
      case 'wind':
        return ParticleWind(
          _vector3(_required(json, 'acceleration'), 'acceleration'),
        );
      case 'turbulence':
        return ParticleTurbulence(
          strength: or('strength', 2.0),
          scale: or('scale', 0.6),
          a: or('a', 1.0),
          b: or('b', 1.0),
          c: or('c', 1.0),
        );
      case 'colorOverLife':
        return ParticleColorOverLife(
          _color(_required(json, 'from'), 'from'),
          _color(_required(json, 'to'), 'to'),
        );
      case 'colorGradient':
        final keys = <GradientKey>[
          for (final raw in _keys(json))
            GradientKey(
              _number(_required(raw, 'at'), 'at'),
              _color(_required(raw, 'color'), 'color'),
              ease: _ease(raw['ease']),
            ),
        ];
        return ParticleColorGradient(ParticleGradient(keys));
      case 'fade':
        return ParticleFade(startsAt: or('startsAt', 0.0));
      case 'sizeOverLife':
        return ParticleSizeOverLife(from: or('from', 1.0), to: or('to', 0.0));
      case 'sizeCurve':
        final keys = <CurveKey>[
          for (final raw in _keys(json))
            CurveKey(
              _number(_required(raw, 'at'), 'at'),
              _number(_required(raw, 'value'), 'value'),
              ease: _ease(raw['ease']),
            ),
        ];
        return ParticleSizeCurve(ParticleCurve(keys));
      case 'spin':
        return ParticleSpin(
          turnsPerSecond: _number(
            _required(json, 'turnsPerSecond'),
            'turnsPerSecond',
          ),
          randomizeStart: switch (json['randomizeStart'] ?? true) {
            final bool value => value,
            _ => throw EffectFormatException(
              '$_where: "randomizeStart" is not true or false',
            ),
          },
        );
      case 'collide':
        switch (json['against'] ?? 'plane') {
          case 'plane':
            final bounce = or('bounce', 0.0);
            final friction = or('friction', 0.0);
            if (bounce < 0.0 || friction < 0.0 || friction > 1.0) {
              throw EffectFormatException(
                '$_where: a collision\'s "bounce" is at least 0 and its '
                '"friction" between 0 and 1',
              );
            }
            return ParticlePlaneCollision(
              height: or('height', 0.0),
              bounce: bounce,
              friction: friction,
            );
          case 'depth':
            unsupported.add(
              '$_where collides against the scene\'s depth, which particles '
              'simulated on the CPU have none of to read; it is drawn '
              'without the collision. A floor is "against": "plane"',
            );
            return null;
          case final Object? other:
            throw EffectFormatException(
              '$_where: a collision is "against" plane or depth, not $other',
            );
        }
    }
    final own = type is String ? vocabulary.affectors[type] : null;
    if (own != null) return own(json);
    throw EffectFormatException(
      '$_where: the affector "type" is $type; the types are gravity, drag, '
      'wind, turbulence, colorOverLife, colorGradient, fade, sizeOverLife, '
      'sizeCurve, spin, collide'
      '${vocabulary.affectors.keys.map((k) => ', $k').join()}',
    );
  }

  List<Map<String, Object?>> _keys(Map<String, Object?> json) {
    final keys = <Map<String, Object?>>[
      for (final (i, raw) in _list(_required(json, 'keys'), 'keys').indexed)
        _object(raw, 'key ${i + 1}'),
    ];
    if (keys.isEmpty) throw EffectFormatException('$_where: "keys" is empty');
    for (var i = 1; i < keys.length; i++) {
      if (_number(keys[i]['at'], 'at') < _number(keys[i - 1]['at'], 'at')) {
        throw EffectFormatException(
          '$_where: keys are ordered by "at", and key ${i + 1} comes before '
          'key $i',
        );
      }
    }
    return keys;
  }

  KeyEase _ease(Object? written) {
    if (written == null) return KeyEase.linear;
    for (final ease in <KeyEase>[
      KeyEase.linear,
      KeyEase.step,
      KeyEase.smooth,
      ...vocabulary.eases,
    ]) {
      if (ease.name == written) return ease;
    }
    throw EffectFormatException(
      '$_where: "$written" is not an ease; the eases are linear, step, '
      'smooth${vocabulary.eases.map((e) => ', ${e.name}').join()}',
    );
  }

  // -------------------------------------------------------------- render

  EffectRender _render(Object? raw) {
    if (raw == null) return const EffectRender();
    final json = _object(raw, 'render');
    final drawing = _word(
      json['drawing'],
      EffectDrawing.values,
      (d) => d.word,
      'drawing',
      EffectDrawing.billboard,
    );
    final allowed = switch (drawing) {
      EffectDrawing.billboard => const <EffectBlend>[EffectBlend.additive],
      EffectDrawing.mesh => const <EffectBlend>[
        EffectBlend.additive,
        EffectBlend.darkening,
      ],
      // `_word` hands back one of `values` and nothing else.
      _ => const <EffectBlend>[EffectBlend.over],
    };
    final blend = _word(
      json['blend'],
      EffectBlend.values,
      (b) => b.word,
      'blend',
      allowed.first,
    );
    if (!allowed.contains(blend)) {
      throw EffectFormatException(
        '$_where: a ${drawing.word} is drawn '
        '${allowed.map((b) => b.word).join(' or ')}, not ${blend.word}',
      );
    }
    final texture = _path(json['texture'], 'texture');
    final mesh = _path(json['mesh'], 'mesh');
    final sheet = switch (json['sheet']) {
      null => null,
      final Map<String, Object?> s => (
        positive:
            _path(s['positive'], 'sheet.positive') ??
            (throw EffectFormatException(
              '$_where: the sheet has no "positive"',
            )),
        negative:
            _path(s['negative'], 'sheet.negative') ??
            (throw EffectFormatException(
              '$_where: the sheet has no "negative"',
            )),
      ),
      _ => throw EffectFormatException('$_where: "sheet" is not an object'),
    };
    final softness = json['softness'] == null
        ? 0.0
        : _number(json['softness'], 'softness');
    if (softness < 0.0) {
      throw EffectFormatException(
        '$_where: "softness" is a distance, never below 0',
      );
    }
    final flipbook = switch (json['flipbook']) {
      null => null,
      final Map<String, Object?> f => _flipbook(f),
      _ => throw EffectFormatException('$_where: "flipbook" is not an object'),
    };
    // Each says what it needs, and what it cannot use, before anything is
    // drawn: a property the contributor would ignore is a document saying
    // something that does not happen.
    switch (drawing) {
      case EffectDrawing.billboard:
        if (mesh != null || sheet != null) {
          throw EffectFormatException(
            '$_where: a billboard takes a "texture", not a mesh or a sheet',
          );
        }
        if (flipbook != null && texture == null) {
          throw EffectFormatException(
            '$_where: a "flipbook" is a grid of a "texture", and there is none',
          );
        }
      case EffectDrawing.mesh:
        if (mesh == null) {
          throw EffectFormatException(
            '$_where: a mesh drawing names its "mesh"',
          );
        }
        if (texture != null || sheet != null || flipbook != null) {
          throw EffectFormatException(
            '$_where: a mesh drawing takes no texture, sheet or flipbook',
          );
        }
        if (softness > 0.0) {
          throw EffectFormatException(
            '$_where: soft particles are billboards and sheets; a mesh '
            'particle has its own depth',
          );
        }
      case EffectDrawing.sixWay:
        if (sheet == null) {
          throw EffectFormatException(
            '$_where: a six-way drawing names its "sheet": positive and '
            'negative',
          );
        }
        if (texture != null || mesh != null) {
          throw EffectFormatException(
            '$_where: a six-way drawing takes its sheet, not a texture or a '
            'mesh',
          );
        }
    }
    return EffectRender(
      drawing: drawing,
      blend: blend,
      texture: texture,
      flipbook: flipbook,
      softness: softness,
      mesh: mesh,
      sheet: sheet,
    );
  }

  Flipbook _flipbook(Map<String, Object?> json) {
    int whole(String key, {required bool required, int fallback = 1}) =>
        switch (json[key]) {
          null when !required => fallback,
          final int value when value >= 1 => value,
          final Object? other => throw EffectFormatException(
            '$_where: the flipbook\'s "$key" is $other, and it is a whole '
            'number, at least 1',
          ),
        };
    return Flipbook(
      columns: whole('columns', required: true),
      rows: whole('rows', required: true),
      frames: json['frames'] == null ? null : whole('frames', required: true),
      loops: whole('loops', required: false),
    );
  }

  // ------------------------------------------------------------ triggers

  EffectTrigger _trigger(Map<String, Object?> json, double? rate) {
    final event = switch (json['event']) {
      final String value when value.isNotEmpty => value,
      _ => throw EffectFormatException('$_where: a trigger names no "event"'),
    };
    final spawn = _word(
      json['emit'],
      EffectSpawn.values,
      (s) => s.word,
      'emit',
      EffectSpawn.burst,
    );
    final perSecond = json['perSecond'] == null
        ? null
        : _positive(json['perSecond'], 'perSecond');
    final seconds = json['seconds'] == null
        ? null
        : _positive(json['seconds'], 'seconds');
    if (spawn == EffectSpawn.timed) {
      if (seconds == null) {
        throw EffectFormatException(
          '$_where: a timed trigger on "$event" says for how many "seconds"',
        );
      }
      if (perSecond == null && rate == null) {
        throw EffectFormatException(
          '$_where: a timed trigger on "$event" has no "perSecond", and the '
          'effect no "rate" to fall back on',
        );
      }
    }
    return EffectTrigger(
      event: event,
      spawn: spawn,
      perSecond: perSecond,
      seconds: seconds,
      at: json['at'] == null ? null : _vector3(json['at'], 'at'),
      direction: json['direction'] == null
          ? null
          : _vector3(json['direction'], 'direction'),
    );
  }

  // ------------------------------------------------------------- values

  Object _required(Map<String, Object?> json, String key) =>
      json[key] ?? (throw EffectFormatException('$_where has no "$key"'));

  Map<String, Object?> _object(Object? raw, String what) => switch (raw) {
    final Map<String, Object?> map => map,
    _ => throw EffectFormatException('$_where: $what is not an object'),
  };

  List<Object?> _list(Object? raw, String key) => switch (raw) {
    null => const <Object?>[],
    final List<Object?> list => list,
    _ => throw EffectFormatException('$_where: "$key" is not a list'),
  };

  double _number(Object? raw, String key) => switch (raw) {
    final num value when value.isFinite => value.toDouble(),
    _ => throw EffectFormatException('$_where: "$key" is $raw, not a number'),
  };

  double _positive(Object? raw, String key) {
    final value = _number(raw, key);
    if (value <= 0.0) {
      throw EffectFormatException(
        '$_where: "$key" is $value, and it is above 0',
      );
    }
    return value;
  }

  /// A number for an exact value, or `[min, max]`.
  Range _range(Object? raw, String key) {
    if (raw is num) {
      return Range.exact(_number(raw, key));
    }
    if (raw is List<Object?> && raw.length == 2) {
      final min = _number(raw[0], key);
      final max = _number(raw[1], key);
      if (max < min) {
        throw EffectFormatException(
          '$_where: "$key" runs from $min down to $max; write the smaller '
          'first',
        );
      }
      return Range(min, max);
    }
    throw EffectFormatException(
      '$_where: "$key" is a number or [min, max], not $raw',
    );
  }

  List<double> _numbers(Object? raw, String key, Set<int> lengths) {
    if (raw is List<Object?> && lengths.contains(raw.length)) {
      return <double>[for (final value in raw) _number(value, key)];
    }
    throw EffectFormatException(
      '$_where: "$key" is a list of ${lengths.join(' or ')} numbers, not $raw',
    );
  }

  Vector3 _vector3(Object? raw, String key) {
    final v = _numbers(raw, key, const <int>{3});
    return Vector3(v[0], v[1], v[2]);
  }

  /// Linear RGB with an alpha, or RGB alone for an alpha of 1.
  Vector4 _color(Object? raw, String key) {
    final v = _numbers(raw, key, const <int>{3, 4});
    return Vector4(v[0], v[1], v[2], v.length == 4 ? v[3] : 1.0);
  }

  String? _path(Object? raw, String key) => switch (raw) {
    null => null,
    final String value when value.isNotEmpty => value,
    _ => throw EffectFormatException('$_where: "$key" is not a name'),
  };

  T _word<T>(
    Object? raw,
    List<T> values,
    String Function(T value) word,
    String key,
    T fallback,
  ) {
    if (raw == null) return fallback;
    for (final value in values) {
      if (word(value) == raw) return value;
    }
    throw EffectFormatException(
      '$_where: "$key" is $raw; it is one of ${values.map(word).join(', ')}',
    );
  }
}
