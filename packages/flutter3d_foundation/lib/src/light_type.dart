/// The kinds of light the engine knows, shared by every package that
/// places one.
library;

/// What shape a light is, which decides how its contribution is integrated.
///
/// The first three are *punctual*: light leaves one point, so the direction to
/// it is a single vector and the integral over the surface's hemisphere is one
/// cosine. [area] is not, and that is the whole of what makes it worth a fourth
/// entry — `gfx-77n`. A rectangle has extent, so what reaches a surface is an
/// integral over the rectangle rather than a value at a point, and that is what
/// makes an interior read as lit by a window instead of by a bright dot with a
/// window painted behind it.
///
/// **An open set.** [LightType.custom] names a kind of one's own — a torch a
/// plugin flickers, a lamp a level editor files apart — lit as its [base], a
/// built-in shape the renderer integrates. The engine reads [base] wherever
/// it decides how a light is drawn, so a custom kind is drawn exactly as its
/// base is; whoever made it tells it apart by identity, and a format writes
/// its base.
///
/// **One set for the scene, a level, a project and a model file.** It is
/// here, below every package that places a light, so a level or a modeller
/// project holds an area light or a plugin's kind as the scene does; a
/// format that has no word for a kind (glTF has no area light) says so where
/// it writes.
final class LightType {
  const LightType._(this._index, this.name) : _base = null;

  /// A kind called [name], lit as [_base] — one of [values].
  const LightType.custom(this.name, {required LightType base})
    : _base = base, // ignore: prefer_initializing_formals
      _index = -1;

  static const LightType directional = LightType._(0, 'directional');

  static const LightType point = LightType._(1, 'point');

  static const LightType spot = LightType._(2, 'spot');

  static const LightType area = LightType._(3, 'area');

  /// Every built-in value this version names, in the order of [index].
  static const List<LightType> values = <LightType>[
    directional,
    point,
    spot,
    area,
  ];

  /// The value whose [name] is [wireName], or null when this version names
  /// none (absent) — how a file that names a value is read.
  static LightType? byName(String wireName) {
    for (final value in values) {
      if (value.name == wireName) return value;
    }
    return null;
  }

  /// The position of [base] in [values]: stable within a major, appended
  /// only.
  int get index => _base?.index ?? _index;
  final int _index;

  final LightType? _base;

  /// The built-in shape this kind is lit as: itself for each of [values].
  LightType get base => _base?.base ?? this;

  /// The stable name, and the wire name: what a file, a report or a
  /// snapshot writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'LightType.$name';
}
