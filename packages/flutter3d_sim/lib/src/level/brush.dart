import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'json_reader.dart';
import 'json_write_through.dart';
import 'level_format_exception.dart';

/// How a brush takes part in the shadow passes, as a document says it.
///
/// **The engine has had four answers since `ShadowCastingMode` was written and
/// the level format has had two.** A wall recorded from its lit face only
/// leaks light along its seam, and a coarse proxy should cast without being
/// drawn; both were reachable from Dart and unauthorable in a document, so a
/// level that wanted either had to be patched after loading.
///
/// The names are the engine's, deliberately, because they are also the words a
/// document writes — but this package may not import the engine (see the note
/// at the foot of its `pubspec.yaml`), so the two are spelled twice and the
/// bridge maps them case by case rather than by name.
enum ShadowCasting {
  /// Drawn into the shadow maps and into the colour image. The default.
  on,

  /// Drawn into the colour image and into no shadow map. What a fence wants.
  off,

  /// Cast from every face, whatever the renderer's caster-face setting says.
  ///
  /// What a single-thickness wall wants: recorded from its lit side only, a
  /// wall lets light along the seam where it meets the floor.
  doubleSided,

  /// Drawn into the shadow maps and into no colour image.
  shadowsOnly;

  /// Whether a brush in this mode is drawn into the shadow maps at all.
  bool get casts => this != ShadowCasting.off;

  /// Whether `castsShadow` alone cannot say this.
  ///
  /// The two finer modes are exactly the ones the boolean loses, so they are
  /// exactly the ones a document has to spell out. See [Brush.toJson].
  bool get needsWord => this != ShadowCasting.on && this != ShadowCasting.off;
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
    bool castsShadow = true,
    ShadowCasting? shadowCasting,
    String? surface,
    this.layer,
    this.ramp,
    Map<String, Object?> source = const <String, Object?>{},
  }) : centre = centre.clone(),
       size = size.clone(),
       // The boolean is the lossy view, here as everywhere else: it says
       // whether the brush casts, and the mode says how. Given both, the mode
       // wins, because it is the one that can say what the other cannot.
       shadowCasting =
           shadowCasting ??
           (castsShadow ? ShadowCasting.on : ShadowCasting.off),
       // ignore: prefer_initializing_formals
       _source = source,
       // ignore: prefer_initializing_formals
       _surface = surface;

  /// The document this brush was read from, or empty when it was built in code.
  ///
  /// Kept so [toJson] can give a document back the way it arrived. See
  /// [writeThrough].
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

  /// How it takes part in the lighting, as opposed to merely being lit.
  ///
  /// `on` unless the document says otherwise, and the two words worth typing
  /// are `off` for a fence and `doubleSided` for a wall one brush thick. See
  /// [ShadowCasting].
  final ShadowCasting shadowCasting;

  /// Whether it takes part in the lighting, as opposed to merely being lit.
  ///
  /// A two-state view of [shadowCasting], kept because every level document
  /// and every generator in this repository was written against it: reading it
  /// asks only whether the brush casts at all, so a `doubleSided` wall reads
  /// as true. The same relationship the engine's `MeshNode.castsShadow` has to
  /// its mode, said again on this side of the format.
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
  bool get castsShadow => shadowCasting.casts;

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
    material: json.textOrNull('material') ?? 'default',
    solid: json.flagOr('solid', fallback: true),
    // The word where the document has one, and the boolean's answer where it
    // has not — so every level ever authored means what it meant, and a
    // misspelt mode is a refusal with the four words in it rather than a wall
    // that quietly stops casting.
    shadowCasting: json.enumValue(
      'shadowCasting',
      ShadowCasting.values,
      json.flagOr('castsShadow', fallback: true)
          ? ShadowCasting.on
          : ShadowCasting.off,
      describedAs: 'brush shadow mode',
    ),
    surface: json.textOrNull('surface'),
    layer: json.integerOrNull('layer'),
    ramp: _rampFromName(json.textOrNull('ramp')),
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

  static String _rampName(WedgeUphill uphill) => _ramps.entries
      .firstWhere((MapEntry<String, WedgeUphill> e) => e.value == uphill)
      .key;

  Map<String, Object?> toJson() {
    // A document that spelled the mode out goes on spelling it out, and does
    // not grow a boolean beside a word that already says more than it could.
    final spelledOut = _source.containsKey('shadowCasting');
    return writeThrough(_source, <WriteThroughField>[
      WriteThroughField('at', centre.toJson()),
      WriteThroughField('size', size.toJson()),
      WriteThroughField(
        'material',
        material,
        whenAbsent: material != 'default',
      ),
      WriteThroughField('solid', solid, whenAbsent: !solid),
      WriteThroughField(
        'castsShadow',
        castsShadow,
        whenAbsent: !castsShadow && !spelledOut,
      ),
      WriteThroughField(
        'shadowCasting',
        shadowCasting.name,
        whenAbsent: shadowCasting.needsWord,
      ),
      WriteThroughField('surface', _surface, whenAbsent: _surface != null),
      WriteThroughField('layer', layer, whenAbsent: layer != null),
      WriteThroughField(
        'ramp',
        ramp == null ? null : _rampName(ramp!),
        whenAbsent: ramp != null,
      ),
    ]);
  }
}
