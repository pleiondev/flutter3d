/// What a control for one of a [ModelCommand]'s [ModelCommand.arguments]
/// should look like, without either of them knowing what the argument means.
///
/// **The same question `MaterialHint` answers for a material's own fields,
/// and a deliberately separate type from it** — decided 2026-09-09 (Г4/Ж2)
/// once a real one was tried: `MaterialHintKind` is `RangeHint`
/// (double only), `ColorHint`, `TextureHint` and `ChoiceHint`, and a command
/// argument needs two things that hierarchy has no room for — a whole number
/// a fraction cannot honestly describe (`LoopCut.cuts`) and a flag that is
/// neither (`RecalculateNormals.flip`) — plus a unit `MaterialHintKind` never
/// asked for, since a material's numbers are all fractions of one and a
/// command's are metres, radians and counts. Sharing the type would also
/// mean this package importing `LightingModel` for a picker it never shows.
///
/// An open set grown only here, for the reason `MaterialHintKind` gives for
/// itself: a switch building a control from one ends with a wildcard.
abstract final class ParamHint {
  const ParamHint();
}

/// A whole number, moving by [step] between [min] and [max] where either is
/// given. `LoopCut.cuts` is one of these.
final class IntHint extends ParamHint {
  /// A whole-number hint between [min] and [max], moving by [step]: one unless
  /// given.
  const IntHint({this.min, this.max, this.step = 1});

  /// The smallest value the argument takes, or null when it has no floor.
  final int? min;

  /// The largest value the argument takes, or null when it has no ceiling.
  final int? max;

  /// How far one nudge of the control moves the value, one by default.
  final int step;
}

/// A real number, moving by [step] between [min] and [max] where either is
/// given, labelled with [unit] where the argument counts something — metres,
/// radians — rather than a bare fraction.
final class DoubleHint extends ParamHint {
  /// A real-number hint between [min] and [max], moving by [step], labelled
  /// with [unit]; each is null when the argument has none.
  const DoubleHint({this.min, this.max, this.step, this.unit});

  /// In [unit] when one is given, otherwise a unitless number.
  final double? min;

  /// In [unit] when one is given, otherwise a unitless number.
  final double? max;

  /// In [unit] when one is given, otherwise a unitless number.
  final double? step;

  /// The unit a control labels the value with, such as `m`, or null for a bare
  /// fraction or factor.
  final String? unit;
}

/// A flag, on or off. `RecalculateNormals.flip` is one of these.
final class BoolHint extends ParamHint {
  /// A hint for a flag; it carries nothing more.
  const BoolHint();
}

/// One of [values] and nothing else — a command argument's own enum, read
/// from that enum's `.values` rather than written out by hand, the same way
/// `builtInMaterialHints` reads `SurfaceAlphaMode.values` for its own.
final class ChoiceHint extends ParamHint {
  /// A hint allowing exactly [values].
  const ChoiceHint(this.values);

  /// The words the argument accepts, in the order a control lists them.
  final List<String> values;
}

/// Three numbers moving together — a translation, an axis, a scale — each
/// taking [step] and [unit] the way a single [DoubleHint] would.
final class Vector3Hint extends ParamHint {
  /// A hint for three numbers moving by [step], labelled with [unit]; either is
  /// null when the argument has none.
  const Vector3Hint({this.step, this.unit});

  /// In [unit] when one is given, otherwise a unitless number.
  final double? step;

  /// The unit a control labels the three numbers with, such as `m`, or null for
  /// unitless numbers.
  final String? unit;
}
