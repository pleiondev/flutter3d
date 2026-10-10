import 'fluid_medium.dart';

/// One liquid in a vessel: a medium, how much of it, and what is dissolved
/// in it.
///
/// **Liquids that mix are one layer**, and what is dissolved in them is kept
/// as amounts — moles, grams, whatever the caller counts in — so a
/// concentration is an amount over the volume and pouring two together adds
/// both. The mixing is taken as instant: a layer is the same all through.
///
/// **Liquids that do not mix are separate layers**, one per medium, lying
/// by density; see `LiquidBody.layers`.
final class LiquidLayer {
  LiquidLayer({
    required this.medium,
    required this.volume,
    Map<String, double>? amounts,
  }) : amounts = {...?amounts};

  final FluidMedium medium;

  /// Cubic metres.
  double volume;

  /// What is dissolved in it, by name: amounts, not concentrations.
  final Map<String, double> amounts;

  /// The amount of [solute] per cubic metre.
  double concentration(String solute) =>
      volume > 0.0 ? (amounts[solute] ?? 0.0) / volume : 0.0;

  /// Every solute's concentration.
  Map<String, double> get concentrations => {
    for (final entry in amounts.entries)
      entry.key: volume > 0.0 ? entry.value / volume : 0.0,
  };

  /// Takes [amount] cubic metres out, with its share of every solute, and
  /// returns it as a layer of its own.
  LiquidLayer withdraw(double amount) {
    final part = amount.clamp(0.0, volume);
    final share = volume > 0.0 ? part / volume : 0.0;
    final out = LiquidLayer(
      medium: medium,
      volume: part,
      amounts: {
        for (final entry in amounts.entries) entry.key: entry.value * share,
      },
    );
    volume -= part;
    for (final key in amounts.keys.toList()) {
      amounts[key] = amounts[key]! * (1.0 - share);
    }
    return out;
  }

  /// Adds [other], which must be the same medium.
  void add(LiquidLayer other) {
    volume += other.volume;
    other.amounts.forEach((key, value) {
      amounts[key] = (amounts[key] ?? 0.0) + value;
    });
  }

  /// [volume] cubic metres of this medium at [concentrations].
  static LiquidLayer at(
    FluidMedium medium,
    double volume,
    Map<String, double> concentrations,
  ) => LiquidLayer(
    medium: medium,
    volume: volume,
    amounts: {
      for (final entry in concentrations.entries)
        entry.key: entry.value * volume,
    },
  );
}
