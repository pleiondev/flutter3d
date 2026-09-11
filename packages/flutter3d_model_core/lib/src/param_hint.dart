/// What a control for one of a [ModelCommand]'s [ModelCommand.arguments]
/// should look like, without either of them knowing what the argument means.
///
/// **The same question `MaterialHint` answers for a material's own fields,
/// and a deliberately separate type from it** — decided 2026-09-09 (Г4/Ж2)
/// once a real one was tried: `MaterialHintKind` is `RangeHint`
/// (double only), `ColorHint`, `TextureHint` and `EnumHint`, and a command
/// argument needs two things that hierarchy has no room for — a whole number
/// a fraction cannot honestly describe (`LoopCut.cuts`) and a flag that is
/// neither (`RecalculateNormals.flip`) — plus a unit `MaterialHintKind` never
/// asked for, since a material's numbers are all fractions of one and a
/// command's are metres, radians and counts. Sharing the type would also
/// mean this package importing `LightingModel` for a picker it never shows.
///
/// Sealed, so a switch building a control from one of these is exhaustive —
/// the same reasoning `MaterialHintKind` gives for itself.
sealed class ParamHint {
  const ParamHint();
}

/// A whole number, moving by [step] between [min] and [max] where either is
/// given. `LoopCut.cuts` is one of these.
final class IntHint extends ParamHint {
  const IntHint({this.min, this.max, this.step = 1});

  final int? min;
  final int? max;
  final int step;
}

/// A real number, moving by [step] between [min] and [max] where either is
/// given, labelled with [unit] where the argument counts something — metres,
/// radians — rather than a bare fraction.
final class DoubleHint extends ParamHint {
  const DoubleHint({this.min, this.max, this.step, this.unit});

  final double? min;
  final double? max;
  final double? step;
  final String? unit;
}

/// A flag, on or off. `RecalculateNormals.flip` is one of these.
final class BoolHint extends ParamHint {
  const BoolHint();
}

/// One of [values] and nothing else — a command argument's own enum, read
/// from that enum's `.values` rather than written out by hand, the same way
/// `builtInMaterialHints` reads `SurfaceAlphaMode.values` for its own.
final class EnumHint extends ParamHint {
  const EnumHint(this.values);

  final List<String> values;
}

/// Three numbers moving together — a translation, an axis, a scale — each
/// taking [step] and [unit] the way a single [DoubleHint] would.
final class Vector3Hint extends ParamHint {
  const Vector3Hint({this.step, this.unit});

  final double? step;
  final String? unit;
}
