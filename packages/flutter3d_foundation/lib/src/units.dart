/// Units of measurement as dimension vectors, and quantities that carry one.
///
/// **One type for every place a number says what it is measured in**: a
/// material's parameter schema, an expression in a data plugin, a probe's
/// reading, a property law's inputs. Each of them used to say its unit in a
/// doc comment or a free string ("kPa", "in metres"), which nothing checked.
/// A [Unit] is a vector of dimension exponents and a scale to the coherent SI
/// unit of that dimension, so two units are the same unit when they measure
/// the same thing at the same size, whatever they are called, and a
/// [Quantity] refuses to become one of another dimension.
///
/// **SI's seven base dimensions and the angle.** SI counts the radian as a
/// derived unit of dimension one. The engine does not, because it has to
/// tell a lumen from a candela (light is photometric since 1.0) and an
/// angular speed from a frequency, and with the angle folded into one both
/// pairs would compare equal. A steradian is a radian squared, so a lumen is
/// cd·sr and a lux is lm/m², and each keeps its own dimension.
///
/// **Open, with wire names.** A dimension is a map from a base's symbol to
/// its exponent, so a base this build does not name (a pixel, a bit) reads,
/// combines and writes back as it came. A unit is written as its symbol when
/// the symbol reads back to it, and as its parts when it does not.
library;

import 'dart:math' as math;

import 'exceptions.dart';

/// What a [Unit] measures: an exponent for each base dimension.
///
/// Compared by the exponents alone, with a zero the same as an absent base.
final class Dimension {
  /// The dimension with these exponents, keyed by the base's symbol (`m`,
  /// `kg`, `s`, `A`, `K`, `mol`, `cd`, `rad`, or one of the caller's own).
  const Dimension(this.exponents);

  /// The exponent of each base, by its symbol. May hold zeros; they count
  /// for nothing.
  final Map<String, int> exponents;

  /// A pure number: every exponent zero.
  static const Dimension none = Dimension(<String, int>{});

  /// Length, whose coherent unit is the meter.
  static const Dimension length = Dimension(<String, int>{'m': 1});

  /// Mass, whose coherent unit is the kilogram.
  static const Dimension mass = Dimension(<String, int>{'kg': 1});

  /// Time, whose coherent unit is the second.
  static const Dimension time = Dimension(<String, int>{'s': 1});

  /// Electric current, whose coherent unit is the ampere.
  static const Dimension current = Dimension(<String, int>{'A': 1});

  /// Thermodynamic temperature, whose coherent unit is the kelvin.
  static const Dimension temperature = Dimension(<String, int>{'K': 1});

  /// Amount of substance, whose coherent unit is the mole.
  static const Dimension amount = Dimension(<String, int>{'mol': 1});

  /// Luminous intensity, whose coherent unit is the candela.
  static const Dimension luminousIntensity = Dimension(<String, int>{'cd': 1});

  /// Plane angle, whose coherent unit is the radian. The engine's own base:
  /// see the library's doc for why.
  static const Dimension angle = Dimension(<String, int>{'rad': 1});

  /// The bases this build names, in the order a dimension is written. A
  /// base outside them is written after them, alphabetically.
  static const List<String> bases = <String>[
    'kg',
    'm',
    's',
    'A',
    'K',
    'mol',
    'cd',
    'rad',
  ];

  /// The exponent of [base]; zero for a base this dimension does not have.
  int operator [](String base) => exponents[base] ?? 0;

  /// Whether this is a pure number.
  bool get isNone => exponents.values.every((int e) => e == 0);

  /// The dimension of a product.
  Dimension operator *(Dimension other) => _combine(other, 1);

  /// The dimension of a quotient.
  Dimension operator /(Dimension other) => _combine(other, -1);

  /// This dimension raised to [power].
  Dimension pow(int power) => Dimension(<String, int>{
    for (final MapEntry(:key, :value) in exponents.entries)
      if (value * power != 0) key: value * power,
  });

  Dimension _combine(Dimension other, int sign) => Dimension(<String, int>{
    for (final base in <String>{...exponents.keys, ...other.exponents.keys})
      if (this[base] + sign * other[base] != 0)
        base: this[base] + sign * other[base],
  });

  /// The bases with a nonzero exponent, in the written order.
  List<String> get _ordered => <String>[
    for (final base in bases)
      if (this[base] != 0) base,
    ...(exponents.keys
        .where((String b) => !bases.contains(b) && this[b] != 0)
        .toList()
      ..sort()),
  ];

  /// The exponents, nonzero ones only, as a document stores them.
  Map<String, int> toJson() => <String, int>{
    for (final base in _ordered) base: this[base],
  };

  /// The dimension [json] holds, as [toJson] writes it.
  ///
  /// Throws [UnitFormatException] for anything but a map of whole numbers.
  static Dimension fromJson(Object? json) {
    if (json is! Map) {
      throw UnitFormatException('$json', 'a dimension is a map of exponents');
    }
    return Dimension(<String, int>{
      for (final MapEntry(:key, :value) in json.entries)
        '$key': switch (value) {
          final int whole => whole,
          final double d when d == d.truncateToDouble() && d.isFinite =>
            d.toInt(),
          _ => throw UnitFormatException(
            '$json',
            'the exponent of "$key" must be a whole number, not $value',
          ),
        },
    });
  }

  @override
  bool operator ==(Object other) =>
      other is Dimension &&
      <String>{
        ...exponents.keys,
        ...other.exponents.keys,
      }.every((String base) => this[base] == other[base]);

  @override
  int get hashCode => Object.hashAllUnordered(<int>[
    for (final base in _ordered) Object.hash(base, this[base]),
  ]);

  /// The base symbols with their exponents, `kg·m·s⁻²`; `1` for a pure
  /// number.
  @override
  String toString() => isNone
      ? '1'
      : _ordered
            .map(
              (String base) =>
                  this[base] == 1 ? base : '$base${_superscript(this[base])}',
            )
            .join('·');
}

/// A unit of measurement: a [dimension], the [scale] that takes a value in
/// it to the coherent SI unit of that dimension, and the [symbol] it is
/// written with.
///
/// **Equal by dimension, scale and offset, not by symbol**, so `N·m` is a
/// joule and a game's `thou` is a millimeter. Scales compare to twelve
/// significant digits, because a scale built by multiplying prefixes lands a
/// rounding away from the same scale written out.
///
/// **A final class with constants, not an enum**: the engine names the units
/// it uses here, a caller names its own with the constructor, and [parse]
/// reads both.
final class Unit {
  /// A unit written [symbol], of [dimension], [scale] coherent units in
  /// size, with [offset] coherent units between its zero and theirs.
  const Unit(this.symbol, this.dimension, {this.scale = 1, this.offset = 0});

  /// How the unit is written: `kPa`, `m/s²`, `J/(kg·K)`.
  final String symbol;

  /// What it measures.
  final Dimension dimension;

  /// The factor that takes a value in this unit to the coherent SI unit:
  /// 1000 for a kilometer, π/180 for a degree.
  final double scale;

  /// What is added after [scale], in coherent units, to reach the coherent
  /// unit's zero: 273.15 kelvin for a degree Celsius, zero for nearly
  /// everything else.
  ///
  /// **Only a unit by itself keeps it.** A product, a quotient or a power is
  /// of differences, so `J/(kg·°C)` is `J/(kg·K)`.
  final double offset;

  // ------------------------------------------------------------- the bases

  /// A pure number.
  static const Unit one = Unit('1', Dimension.none);

  /// A hundredth.
  static const Unit percent = Unit('%', Dimension.none, scale: 0.01);

  /// The meter, the coherent unit of length.
  static const Unit meter = Unit('m', Dimension.length);

  /// A thousand meters.
  static const Unit kilometer = Unit('km', Dimension.length, scale: 1000);

  /// A hundredth of a meter.
  static const Unit centimeter = Unit('cm', Dimension.length, scale: 0.01);

  /// A thousandth of a meter.
  static const Unit millimeter = Unit('mm', Dimension.length, scale: 1e-3);

  /// The kilogram, the coherent unit of mass.
  static const Unit kilogram = Unit('kg', Dimension.mass);

  /// A thousandth of a kilogram.
  static const Unit gram = Unit('g', Dimension.mass, scale: 1e-3);

  /// The second, the coherent unit of time.
  static const Unit second = Unit('s', Dimension.time);

  /// A thousandth of a second.
  static const Unit millisecond = Unit('ms', Dimension.time, scale: 1e-3);

  /// Sixty seconds.
  static const Unit minute = Unit('min', Dimension.time, scale: 60);

  /// Three thousand six hundred seconds.
  static const Unit hour = Unit('h', Dimension.time, scale: 3600);

  /// The ampere, the coherent unit of current.
  static const Unit ampere = Unit('A', Dimension.current);

  /// The kelvin, the coherent unit of temperature.
  static const Unit kelvin = Unit('K', Dimension.temperature);

  /// The degree Celsius: a kelvin in size, its zero at 273.15 K.
  static const Unit celsius = Unit('°C', Dimension.temperature, offset: 273.15);

  /// The mole, the coherent unit of amount of substance.
  static const Unit mole = Unit('mol', Dimension.amount);

  /// The candela, the coherent unit of luminous intensity: a light's
  /// strength in one direction.
  static const Unit candela = Unit('cd', Dimension.luminousIntensity);

  /// The radian, the coherent unit of angle.
  static const Unit radian = Unit('rad', Dimension.angle);

  /// A degree of arc, π/180 radians.
  static const Unit degree = Unit('°', Dimension.angle, scale: math.pi / 180);

  /// The steradian, a radian squared: solid angle.
  static const Unit steradian = Unit('sr', Dimension(<String, int>{'rad': 2}));

  // ----------------------------------------------------------- the derived

  /// The hertz, once a second: a frequency, not an angular speed.
  static const Unit hertz = Unit('Hz', Dimension(<String, int>{'s': -1}));

  /// The newton, kg·m/s²: force.
  static const Unit newton = Unit(
    'N',
    Dimension(<String, int>{'kg': 1, 'm': 1, 's': -2}),
  );

  /// The pascal, N/m²: pressure and stress.
  static const Unit pascal = Unit(
    'Pa',
    Dimension(<String, int>{'kg': 1, 'm': -1, 's': -2}),
  );

  /// A thousand pascals.
  static const Unit kilopascal = Unit(
    'kPa',
    Dimension(<String, int>{'kg': 1, 'm': -1, 's': -2}),
    scale: 1000,
  );

  /// A hundred thousand pascals, about an atmosphere.
  static const Unit bar = Unit(
    'bar',
    Dimension(<String, int>{'kg': 1, 'm': -1, 's': -2}),
    scale: 1e5,
  );

  /// The joule, N·m: energy.
  static const Unit joule = Unit(
    'J',
    Dimension(<String, int>{'kg': 1, 'm': 2, 's': -2}),
  );

  /// The watt, J/s: power.
  static const Unit watt = Unit(
    'W',
    Dimension(<String, int>{'kg': 1, 'm': 2, 's': -3}),
  );

  /// The coulomb, A·s: charge.
  static const Unit coulomb = Unit(
    'C',
    Dimension(<String, int>{'A': 1, 's': 1}),
  );

  /// The volt, W/A: electric potential.
  static const Unit volt = Unit(
    'V',
    Dimension(<String, int>{'kg': 1, 'm': 2, 's': -3, 'A': -1}),
  );

  /// The ohm, V/A: resistance.
  static const Unit ohm = Unit(
    'Ω',
    Dimension(<String, int>{'kg': 1, 'm': 2, 's': -3, 'A': -2}),
  );

  /// The lumen, cd·sr: luminous flux, a light's output in every direction.
  static const Unit lumen = Unit(
    'lm',
    Dimension(<String, int>{'cd': 1, 'rad': 2}),
  );

  /// The lux, lm/m²: illuminance, the light arriving on a surface.
  static const Unit lux = Unit(
    'lx',
    Dimension(<String, int>{'cd': 1, 'rad': 2, 'm': -2}),
  );

  /// The nit, cd/m²: luminance, how bright a surface looks.
  static const Unit nit = Unit(
    'nit',
    Dimension(<String, int>{'cd': 1, 'm': -2}),
  );

  /// The liter, a thousandth of a cubic meter.
  static const Unit liter = Unit(
    'L',
    Dimension(<String, int>{'m': 3}),
    scale: 1e-3,
  );

  /// The square meter: area.
  static const Unit squareMeter = Unit('m²', Dimension(<String, int>{'m': 2}));

  /// The cubic meter: volume.
  static const Unit cubicMeter = Unit('m³', Dimension(<String, int>{'m': 3}));

  /// Meters per second: speed.
  static const Unit meterPerSecond = Unit(
    'm/s',
    Dimension(<String, int>{'m': 1, 's': -1}),
  );

  /// Meters per second squared: acceleration.
  static const Unit meterPerSecondSquared = Unit(
    'm/s²',
    Dimension(<String, int>{'m': 1, 's': -2}),
  );

  /// Radians per second: angular speed.
  static const Unit radianPerSecond = Unit(
    'rad/s',
    Dimension(<String, int>{'rad': 1, 's': -1}),
  );

  /// Kilograms per cubic meter: density.
  static const Unit kilogramPerCubicMeter = Unit(
    'kg/m³',
    Dimension(<String, int>{'kg': 1, 'm': -3}),
  );

  /// The pascal-second: dynamic viscosity.
  static const Unit pascalSecond = Unit(
    'Pa·s',
    Dimension(<String, int>{'kg': 1, 'm': -1, 's': -1}),
  );

  /// Newtons per meter: surface tension and stiffness.
  static const Unit newtonPerMeter = Unit(
    'N/m',
    Dimension(<String, int>{'kg': 1, 's': -2}),
  );

  /// Every unit named above, for a tool that lists them.
  static const List<Unit> named = <Unit>[
    one,
    percent,
    meter,
    kilometer,
    centimeter,
    millimeter,
    kilogram,
    gram,
    second,
    millisecond,
    minute,
    hour,
    ampere,
    kelvin,
    celsius,
    mole,
    candela,
    radian,
    degree,
    steradian,
    hertz,
    newton,
    pascal,
    kilopascal,
    bar,
    joule,
    watt,
    coulomb,
    volt,
    ohm,
    lumen,
    lux,
    nit,
    liter,
    squareMeter,
    cubicMeter,
    meterPerSecond,
    meterPerSecondSquared,
    radianPerSecond,
    kilogramPerCubicMeter,
    pascalSecond,
    newtonPerMeter,
  ];

  // ------------------------------------------------------------ the algebra

  /// Whether a value in this unit can be converted to [other]: the two
  /// measure the same dimension.
  bool isCompatibleWith(Unit other) => dimension == other.dimension;

  /// The unit of a product, written `a·b`.
  Unit operator *(Unit other) {
    if (other.symbol == '1' && other.scale == 1) return this;
    if (symbol == '1' && scale == 1) return other;
    return Unit(
      '$symbol·${other.symbol}',
      dimension * other.dimension,
      scale: scale * other.scale,
    );
  }

  /// The unit of a quotient, written `a/b`, with `b` in parentheses when it
  /// is itself a product or a quotient.
  Unit operator /(Unit other) {
    if (other.symbol == '1' && other.scale == 1) return this;
    final under = _isCompound(other.symbol)
        ? '(${other.symbol})'
        : other.symbol;
    return Unit(
      '$symbol/$under',
      dimension / other.dimension,
      scale: scale / other.scale,
    );
  }

  /// This unit raised to [power], written `m²` or `(m/s)²`.
  Unit pow(int power) {
    if (power == 1) return this;
    if (power == 0) return one;
    final base = _isAtom(symbol) ? symbol : '($symbol)';
    return Unit(
      '$base${_superscript(power)}',
      dimension.pow(power),
      scale: _power(scale, power),
    );
  }

  // ------------------------------------------------------------- the text

  /// The unit [text] writes.
  ///
  /// Reads symbols with an SI prefix (`kPa`, `mm`, `µs`, also `us`),
  /// products (`·`, `*`, `×` or a space), quotients (`/`, left to right, so
  /// `J/kg·K` is (J/kg)·K), parentheses, and powers (`m²`, `s⁻¹`, `s^-1`).
  /// A symbol known whole wins over a prefix and a symbol: `cd` is a
  /// candela, `min` a minute. [also] adds a caller's own units, looked up
  /// before the built-in ones; they take no prefix.
  ///
  /// Throws [UnitFormatException], naming [text], for anything else.
  static Unit parse(String text, {Iterable<Unit> also = const <Unit>[]}) =>
      _UnitParser(text, also).parse();

  /// The unit [text] writes, or null where [parse] would throw.
  static Unit? tryParse(String text, {Iterable<Unit> also = const <Unit>[]}) {
    try {
      return parse(text, also: also);
    } on UnitFormatException {
      return null;
    }
  }

  /// The unit as a document stores it: the [symbol] when it reads back to
  /// this unit, and the whole unit otherwise, so a unit nobody else knows
  /// survives the trip.
  Object toJson() => tryParse(symbol) == this
      ? symbol
      : <String, Object?>{
          'symbol': symbol,
          'dimension': dimension.toJson(),
          'scale': scale,
          if (offset != 0) 'offset': offset,
        };

  /// The unit [json] holds, as [toJson] writes it; [also] as for [parse].
  ///
  /// Throws [UnitFormatException] for anything else.
  static Unit fromJson(Object? json, {Iterable<Unit> also = const <Unit>[]}) =>
      switch (json) {
        final String text => parse(text, also: also),
        {'symbol': final String symbol, 'dimension': final Object dimension} =>
          Unit(
            symbol,
            Dimension.fromJson(dimension),
            scale: _number(json, 'scale', 1),
            offset: _number(json, 'offset', 0),
          ),
        _ => throw UnitFormatException(
          '$json',
          'a unit is its symbol, or a map with "symbol" and "dimension"',
        ),
      };

  static double _number(Map<Object?, Object?> json, String key, double or) =>
      switch (json[key]) {
        null => or,
        final num n when n.isFinite => n.toDouble(),
        final other => throw UnitFormatException(
          '$json',
          '"$key" must be a finite number, not $other',
        ),
      };

  @override
  bool operator ==(Object other) =>
      other is Unit &&
      dimension == other.dimension &&
      _close(scale, other.scale) &&
      (offset - other.offset).abs() <= 1e-9 * math.max(1, offset.abs());

  @override
  int get hashCode => dimension.hashCode;

  /// The [symbol].
  @override
  String toString() => symbol;
}

/// A value in a unit: `9.81 m/s²`.
///
/// **It refuses to cross dimensions.** [to], [valueIn], `+`, `-` and
/// [compareTo] throw [UnitMismatchException] when the other unit measures
/// something else; `*` and `/` make the unit of the result.
final class Quantity implements Comparable<Quantity> {
  /// [value] in [unit].
  const Quantity(this.value, this.unit);

  /// The number, in [unit].
  final double value;

  /// What [value] is measured in.
  final Unit unit;

  /// This quantity in [target], which must measure the same dimension.
  Quantity to(Unit target) => Quantity(valueIn(target), target);

  /// The number this quantity is in [target], offsets included: 20 °C is
  /// 293.15 in kelvin.
  double valueIn(Unit target) {
    _require(target);
    return (value * unit.scale + unit.offset - target.offset) / target.scale;
  }

  /// The sum, in this quantity's unit. [other] is added as a difference,
  /// through its scale and not its offset: 20 °C and 5 K are 25 °C.
  Quantity operator +(Quantity other) =>
      Quantity(value + _difference(other), unit);

  /// The difference, in this quantity's unit; [other] as for `+`.
  Quantity operator -(Quantity other) =>
      Quantity(value - _difference(other), unit);

  /// The product, in the product of the units.
  Quantity operator *(Quantity other) =>
      Quantity(value * other.value, unit * other.unit);

  /// The quotient, in the quotient of the units.
  Quantity operator /(Quantity other) =>
      Quantity(value / other.value, unit / other.unit);

  @override
  int compareTo(Quantity other) => value.compareTo(other.valueIn(unit));

  double _difference(Quantity other) {
    _require(other.unit);
    return other.value * other.unit.scale / unit.scale;
  }

  void _require(Unit other) {
    if (!unit.isCompatibleWith(other)) {
      throw UnitMismatchException(unit, other);
    }
  }

  /// The quantity [text] writes: a number, then a unit as [Unit.parse]
  /// reads it (none for a pure number). `9.81 m/s²`, `-40°C`, `1e3 m`.
  ///
  /// Throws [UnitFormatException], naming [text], for anything else.
  static Quantity parse(String text, {Iterable<Unit> also = const <Unit>[]}) {
    final match = RegExp(
      r'^\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*(.*?)\s*$',
    ).firstMatch(text);
    if (match == null) {
      throw UnitFormatException(text, 'a quantity starts with a number');
    }
    final rest = match.group(2)!;
    return Quantity(
      double.parse(match.group(1)!),
      rest.isEmpty ? Unit.one : Unit.parse(rest, also: also),
    );
  }

  /// The quantity as a document stores it: `{"value": 2.5, "unit": "kPa"}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'unit': unit.toJson(),
  };

  /// The quantity [json] holds, as [toJson] writes it; [also] as for
  /// [Unit.parse].
  ///
  /// Throws [UnitFormatException] for anything else.
  static Quantity fromJson(
    Object? json, {
    Iterable<Unit> also = const <Unit>[],
  }) => switch (json) {
    {'value': final num value, 'unit': final Object unit} => Quantity(
      value.toDouble(),
      Unit.fromJson(unit, also: also),
    ),
    _ => throw UnitFormatException(
      '$json',
      'a quantity is a map with a numeric "value" and a "unit"',
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  /// The value and the unit's symbol, `9.81 m/s²`; the value alone for a
  /// pure number.
  @override
  String toString() {
    final number = value == value.truncateToDouble() && value.abs() < 1e15
        ? value.toInt().toString()
        : value.toString();
    return unit.symbol == '1' ? number : '$number ${unit.symbol}';
  }
}

/// Text that is not a unit, or a document's unit or quantity that is not
/// one.
final class UnitFormatException extends Flutter3dFormatException {
  const UnitFormatException(this.text, this.reason);

  /// What was read, as it was given.
  final String text;

  /// What is wrong with it.
  final String reason;

  @override
  String get message => '"$text" is not a unit: $reason';

  @override
  String toString() => 'UnitFormatException: $message';
}

/// A conversion between units of different dimensions: a length asked for in
/// seconds, a luminous flux compared with an intensity.
///
/// **A format exception**, because the units a correct program meets come
/// from its documents: a schema says pascals and the value says meters.
final class UnitMismatchException extends Flutter3dFormatException {
  const UnitMismatchException(this.from, this.to);

  /// The unit the value is in.
  final Unit from;

  /// The unit it was asked for in.
  final Unit to;

  @override
  String get message =>
      'cannot convert $from (${from.dimension}) to $to (${to.dimension})';

  @override
  String toString() => 'UnitMismatchException: $message';
}

// ------------------------------------------------------------------ private

/// [base] to the whole [power], by multiplication, so a scale is the same
/// number on every platform, which the libm's power function does not
/// promise.
double _power(double base, int power) {
  final whole = List<double>.filled(
    power.abs(),
    base,
  ).fold(1.0, (a, b) => a * b);
  return power < 0 ? 1 / whole : whole;
}

bool _close(double a, double b) =>
    a == b || (a - b).abs() <= 1e-12 * math.max(a.abs(), b.abs());

const String _superscriptDigits = '⁰¹²³⁴⁵⁶⁷⁸⁹';

String _superscript(int power) => <String>[
  if (power < 0) '⁻',
  for (final digit in '${power.abs()}'.codeUnits)
    _superscriptDigits[digit - 0x30],
].join();

/// Whether [symbol] has an operator outside parentheses.
bool _isCompound(String symbol) {
  var depth = 0;
  for (final char in symbol.split('')) {
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (depth == 0 && (char == '·' || char == '/')) return true;
  }
  return false;
}

/// Whether [symbol] is one symbol with no operator, power or parenthesis.
bool _isAtom(String symbol) => !symbol
    .split('')
    .any((String c) => '·/()^ ⁻'.contains(c) || _superscriptDigits.contains(c));

/// The SI prefixes, longest first so `da` is not read as a deci-`a`.
const List<(String, double)> _prefixes = <(String, double)>[
  ('da', 1e1),
  ('Q', 1e30),
  ('R', 1e27),
  ('Y', 1e24),
  ('Z', 1e21),
  ('E', 1e18),
  ('P', 1e15),
  ('T', 1e12),
  ('G', 1e9),
  ('M', 1e6),
  ('k', 1e3),
  ('h', 1e2),
  ('d', 1e-1),
  ('c', 1e-2),
  ('m', 1e-3),
  ('µ', 1e-6),
  ('n', 1e-9),
  ('p', 1e-12),
  ('f', 1e-15),
  ('a', 1e-18),
  ('z', 1e-21),
  ('y', 1e-24),
  ('r', 1e-27),
  ('q', 1e-30),
];

/// The units a prefix may stand before: the SI ones, and the liter.
final Map<String, Unit> _prefixable = <String, Unit>{
  for (final unit in const <Unit>[
    Unit.meter,
    Unit.gram,
    Unit.second,
    Unit.ampere,
    Unit.kelvin,
    Unit.mole,
    Unit.candela,
    Unit.radian,
    Unit.steradian,
    Unit.hertz,
    Unit.newton,
    Unit.pascal,
    Unit.joule,
    Unit.watt,
    Unit.coulomb,
    Unit.volt,
    Unit.ohm,
    Unit.lumen,
    Unit.lux,
    Unit.liter,
  ])
    unit.symbol: unit,
};

/// Every named unit written as one symbol, by that symbol, with the
/// spellings a keyboard has.
final Map<String, Unit> _atoms = <String, Unit>{
  for (final unit in Unit.named)
    if (_isAtom(unit.symbol)) unit.symbol: unit,
  'deg': Unit.degree,
  'degC': Unit.celsius,
  'l': Unit.liter,
  'ohm': Unit.ohm,
};

final class _UnitParser {
  _UnitParser(this.text, Iterable<Unit> also)
    : also = <String, Unit>{for (final unit in also) unit.symbol: unit};

  final String text;
  final Map<String, Unit> also;
  int at = 0;

  Unit parse() {
    final unit = _expression();
    _skipSpace();
    if (at < text.length) throw _refuse('unexpected "${text[at]}"');
    return unit;
  }

  UnitFormatException _refuse(String why) => UnitFormatException(text, why);

  bool _skipSpace() {
    final from = at;
    while (at < text.length && text[at].trim().isEmpty) {
      at++;
    }
    return at > from;
  }

  Unit _expression() {
    var unit = _term();
    while (true) {
      final spaced = _skipSpace();
      if (at >= text.length) return unit;
      final char = text[at];
      if (char == '/') {
        at++;
        unit = unit / _term();
      } else if (char == '·' || char == '*' || char == '×') {
        at++;
        unit = unit * _term();
      } else if (spaced && char != ')') {
        unit = unit * _term();
      } else {
        return unit;
      }
    }
  }

  Unit _term() {
    final base = _primary();
    if (at < text.length && text[at] == '^') {
      at++;
      final from = at;
      if (at < text.length && (text[at] == '-' || text[at] == '+')) at++;
      while (at < text.length && _isDigit(text[at])) {
        at++;
      }
      final power = int.tryParse(text.substring(from, at));
      if (power == null) throw _refuse('"^" takes a whole number');
      return base.pow(power);
    }
    final from = at;
    if (at < text.length && text[at] == '⁻') at++;
    while (at < text.length && _superscriptDigits.contains(text[at])) {
      at++;
    }
    if (at == from) return base;
    final written = text.substring(from, at);
    final digits = written.replaceAll('⁻', '');
    if (digits.isEmpty) throw _refuse('"⁻" takes a power');
    final power = int.parse(
      digits.split('').map(_superscriptDigits.indexOf).join(),
    );
    return base.pow(written.startsWith('⁻') ? -power : power);
  }

  Unit _primary() {
    _skipSpace();
    if (at >= text.length) throw _refuse('a unit is missing at the end');
    final char = text[at];
    if (char == '(') {
      at++;
      final inner = _expression();
      _skipSpace();
      if (at >= text.length || text[at] != ')') throw _refuse('")" missing');
      at++;
      return inner;
    }
    if (_isDigit(char)) {
      final from = at;
      while (at < text.length && _isDigit(text[at])) {
        at++;
      }
      if (text.substring(from, at) != '1') {
        throw _refuse('the only number a unit holds is 1');
      }
      return Unit.one;
    }
    final from = at;
    while (at < text.length && _isSymbolChar(text[at])) {
      at++;
    }
    if (at == from) throw _refuse('unexpected "$char"');
    return _symbol(text.substring(from, at));
  }

  Unit _symbol(String written) {
    // The Greek mu and a keyboard's `u` both mean the micro sign.
    final symbol = written.replaceAll('μ', 'µ');
    if (also[symbol] case final Unit own) return own;
    if (_atoms[symbol] case final Unit known) return known;
    for (final (prefix, factor) in _prefixes) {
      final spelled = prefix == 'µ' && symbol.startsWith('u') ? 'u' : prefix;
      if (symbol.length <= spelled.length || !symbol.startsWith(spelled)) {
        continue;
      }
      final rest = symbol.substring(spelled.length);
      if (_prefixable[rest] case final Unit base) {
        return Unit('$prefix$rest', base.dimension, scale: base.scale * factor);
      }
    }
    throw _refuse('no unit "$written"');
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  static bool _isSymbolChar(String c) =>
      c.trim().isNotEmpty &&
      !_isDigit(c) &&
      !'()/·*×^⁻'.contains(c) &&
      !_superscriptDigits.contains(c);
}
