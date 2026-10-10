/// Units as dimension vectors and a scale, and quantities that refuse to mix
/// them.
///
///     dart test test/units_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('Dimension', () {
    test('derived units carry the exponents of their definition', () {
      // Mutation: make `*` subtract exponents — a newton stops being
      // kg·m·s⁻² and every derived constant below disagrees with its
      // definition.
      expect(
        Unit.newton.dimension,
        Dimension.mass * Dimension.length / Dimension.time.pow(2),
      );
      expect(Unit.joule.dimension, (Unit.newton * Unit.meter).dimension);
      expect(Unit.watt.dimension, (Unit.joule / Unit.second).dimension);
      expect(
        Unit.pascal.dimension,
        (Unit.newton / Unit.meter.pow(2)).dimension,
      );
      expect(Unit.newton.dimension['kg'], 1);
      expect(Unit.newton.dimension['s'], -2);
      expect(Unit.newton.dimension['cd'], 0);
    });

    test('an angle is a dimension of its own, so a lumen is not a candela', () {
      // Mutation: give `radian` Dimension.none — `lumen == candela` and
      // `hertz == radianPerSecond` would both hold, and a light's flux could
      // be passed where its intensity is asked for.
      expect(Unit.radian, isNot(Unit.one));
      expect(Unit.lumen, isNot(Unit.candela));
      expect(Unit.hertz, isNot(Unit.radianPerSecond));
      expect(Unit.candela * Unit.steradian, Unit.lumen);
      expect(Unit.lumen / Unit.meter.pow(2), Unit.lux);
      expect(Unit.candela / Unit.meter.pow(2), Unit.nit);
    });

    test('zero exponents do not count, and a base it does not know '
        'survives', () {
      // Mutation: compare the maps as given — a dimension written with an
      // explicit zero would differ from the same one without it.
      expect(const Dimension(<String, int>{'m': 1, 's': 0}), Dimension.length);
      expect(
        const Dimension(<String, int>{'m': 1, 's': 0}).hashCode,
        Dimension.length.hashCode,
      );
      const pixels = Dimension(<String, int>{'px': 1});
      expect(Dimension.fromJson(pixels.toJson()), pixels);
      expect((pixels / Dimension.length).toString(), 'm⁻¹·px');
      expect(Dimension.none.toString(), '1');
      expect(Unit.newton.dimension.toString(), 'kg·m·s⁻²');
    });
  });

  group('Unit', () {
    test('two units are equal by dimension and scale, whatever their '
        'symbols', () {
      // Mutation: compare symbols in `==` — `N·m` would stop being a joule.
      expect(Unit.parse('N·m'), Unit.joule);
      expect(Unit.parse('N·m').symbol, 'N·m');
      expect(Unit.kilometer, isNot(Unit.meter));
      expect(Unit.kilometer.isCompatibleWith(Unit.meter), isTrue);
      expect(Unit.second.isCompatibleWith(Unit.meter), isFalse);
      expect(
        const Unit('thou', Dimension.length, scale: 1e-3),
        Unit.millimeter,
      );
      expect(
        const Unit('thou', Dimension.length, scale: 1e-3).hashCode,
        Unit.millimeter.hashCode,
      );
    });

    test('parses products, quotients, powers and prefixes', () {
      // Mutation: parse `/` as binding everything after it — `J/kg·K`
      // would become J/(kg·K) instead of (J/kg)·K.
      final acceleration = Unit.meter / Unit.second.pow(2);
      for (final text in <String>[
        'm/s²',
        'm/s^2',
        'm s^-2',
        'm·s⁻²',
        'm*s^-2',
        'm / s / s',
        '(m/s)/s',
      ]) {
        expect(Unit.parse(text), acceleration, reason: text);
      }
      expect(
        Unit.parse('J/(kg·K)'),
        Unit.joule / (Unit.kilogram * Unit.kelvin),
      );
      expect(Unit.parse('J/kg·K'), Unit.joule / Unit.kilogram * Unit.kelvin);
      expect(Unit.parse('kPa'), Unit.kilopascal);
      expect(Unit.parse('kPa').scale, 1000);
      expect(Unit.parse('mm').scale, closeTo(1e-3, 1e-18));
      expect(Unit.parse('mg'), const Unit('mg', Dimension.mass, scale: 1e-6));
      expect(Unit.parse('µs'), Unit.parse('us'));
      expect(Unit.parse('µs').symbol, 'µs');
      expect(Unit.parse('1/s'), Unit.hertz);
      expect(Unit.parse('deg'), Unit.degree);
      expect(Unit.parse('degC'), Unit.celsius);
      expect(Unit.parse('%'), Unit.percent);
      expect(Unit.parse('1'), Unit.one);
    });

    test('a symbol it knows whole wins over a prefix and a symbol', () {
      // Mutation: try prefixes first — `cd` reads as a centi-day, `Pa` as a
      // peta-year, `min` as a milli-inch.
      expect(Unit.parse('cd'), Unit.candela);
      expect(Unit.parse('Pa'), Unit.pascal);
      expect(Unit.parse('min'), Unit.minute);
      expect(Unit.parse('mol').dimension, Dimension.amount);
      expect(Unit.parse('kg'), Unit.kilogram);
      expect(Unit.parse('h'), Unit.hour);
    });

    test('refuses text that is not a unit, saying which text', () {
      // Mutation: answer `one` for an unknown symbol — a typo in a schema
      // would read as a pure number.
      for (final text in <String>[
        '',
        'm/',
        'furlong',
        'm^x',
        '(m',
        'm)',
        'kkg',
      ]) {
        expect(
          () => Unit.parse(text),
          throwsA(
            isA<UnitFormatException>()
                .having((e) => e.text, 'text', text)
                .having((e) => e, 'is', isA<Flutter3dFormatException>()),
          ),
          reason: text,
        );
      }
      expect(Unit.tryParse('furlong'), isNull);
    });

    test('a unit a caller names is parsed beside the built-in ones', () {
      // Mutation: drop `also` from the atom lookup — a game's own unit is
      // unknown inside a compound.
      const foot = Unit('ft', Dimension.length, scale: 0.3048);
      expect(Unit.parse('ft/s', also: const <Unit>[foot]), foot / Unit.second);
      expect(Unit.tryParse('ft/s'), isNull);
    });

    test('every named unit formats as a symbol that parses back to it', () {
      // Mutation: write superscripts the parser does not read — a unit
      // written to a file would not read back.
      for (final unit in Unit.named) {
        final back = Unit.parse(unit.symbol);
        expect(back, unit, reason: unit.symbol);
        expect(back.symbol, unit.symbol, reason: unit.symbol);
      }
      final built = Unit.kilogram * Unit.meter / Unit.second.pow(2);
      expect(built.symbol, 'kg·m/s²');
      expect(Unit.parse(built.symbol), Unit.newton);
      expect((Unit.joule / (Unit.kilogram * Unit.kelvin)).symbol, 'J/(kg·K)');
      expect((Unit.meter / Unit.second).pow(2).symbol, '(m/s)²');
      expect(Unit.second.pow(-1).symbol, 's⁻¹');
    });

    test('an offset lives only on a unit by itself', () {
      // Mutation: keep the offset through `*` — a specific heat per degree
      // Celsius would convert as if 273.15 were added to it.
      expect(Unit.celsius.offset, 273.15);
      expect(
        Unit.parse('J/(kg·°C)'),
        Unit.joule / (Unit.kilogram * Unit.kelvin),
      );
      expect(Unit.celsius, isNot(Unit.kelvin));
    });

    test('writes a symbol where it reads back, and the whole unit '
        'otherwise', () {
      // Mutation: always write the symbol — a unit nobody else knows would
      // not read back.
      expect(Unit.kilopascal.toJson(), 'kPa');
      expect(Unit.fromJson('kPa'), Unit.kilopascal);
      const pixel = Unit('px', Dimension(<String, int>{'px': 1}), scale: 1);
      final json = pixel.toJson();
      expect(json, isA<Map<String, Object?>>());
      final back = Unit.fromJson(json);
      expect(back, pixel);
      expect(back.symbol, 'px');
      expect(Unit.fromJson(Unit.celsius.toJson()), Unit.celsius);
      for (final bad in <Object?>[
        42,
        null,
        <String, Object?>{'symbol': 'x'},
        <String, Object?>{
          'symbol': 'x',
          'dimension': <String, Object?>{'m': 1.5},
        },
      ]) {
        expect(
          () => Unit.fromJson(bad),
          throwsA(isA<UnitFormatException>()),
          reason: '$bad',
        );
      }
    });
  });

  group('Quantity', () {
    test('converts between units of one dimension', () {
      // Mutation: divide by the target's scale before the source's is
      // applied — a kilometre would come out a millimetre.
      expect(const Quantity(1, Unit.kilometer).to(Unit.meter).value, 1000);
      expect(const Quantity(1, Unit.kilometer).to(Unit.meter).unit, Unit.meter);
      expect(
        const Quantity(20, Unit.celsius).valueIn(Unit.kelvin),
        closeTo(293.15, 1e-9),
      );
      expect(
        const Quantity(300, Unit.kelvin).valueIn(Unit.celsius),
        closeTo(26.85, 1e-9),
      );
      expect(
        const Quantity(180, Unit.degree).valueIn(Unit.radian),
        closeTo(math.pi, 1e-12),
      );
      expect(
        const Quantity(101.325, Unit.kilopascal).valueIn(Unit.pascal),
        closeTo(101325, 1e-9),
      );
    });

    test('refuses a conversion across dimensions, naming both units', () {
      // Mutation: convert by scale alone — a metre would become a second.
      expect(
        () => const Quantity(1, Unit.meter).to(Unit.second),
        throwsA(
          isA<UnitMismatchException>()
              .having((e) => e.from, 'from', Unit.meter)
              .having((e) => e.to, 'to', Unit.second)
              .having((e) => e.message, 'message', contains('m'))
              .having((e) => e.message, 'message', contains('s')),
        ),
      );
      expect(
        () => const Quantity(1, Unit.meter) + const Quantity(1, Unit.second),
        throwsA(isA<UnitMismatchException>()),
      );
      expect(
        () => const Quantity(
          1,
          Unit.lumen,
        ).compareTo(const Quantity(1, Unit.candela)),
        throwsA(isA<UnitMismatchException>()),
      );
    });

    test('adds a difference, so a kelvin added to a Celsius reading is one '
        'degree', () {
      // Mutation: convert the other operand as a reading — 5 K would be
      // −268.15 °C, and the sum nonsense.
      final sum =
          const Quantity(1, Unit.kilometer) + const Quantity(500, Unit.meter);
      expect(sum.unit, Unit.kilometer);
      expect(sum.value, closeTo(1.5, 1e-12));
      final warmer =
          const Quantity(20, Unit.celsius) + const Quantity(5, Unit.kelvin);
      expect(warmer.unit, Unit.celsius);
      expect(warmer.value, closeTo(25, 1e-12));
      expect(
        (const Quantity(2, Unit.meter) - const Quantity(50, Unit.centimeter))
            .value,
        closeTo(1.5, 1e-12),
      );
    });

    test('multiplies and divides units with the values', () {
      // Mutation: keep the left unit in `/` — a speed would be in metres.
      final speed =
          const Quantity(100, Unit.meter) / const Quantity(20, Unit.second);
      expect(speed.value, 5);
      expect(speed.unit, Unit.meterPerSecond);
      final work =
          const Quantity(2, Unit.newton) * const Quantity(3, Unit.meter);
      expect(work.valueIn(Unit.joule), 6);
      expect(
        const Quantity(
          1,
          Unit.kilometer,
        ).compareTo(const Quantity(999, Unit.meter)),
        greaterThan(0),
      );
    });

    test('parses and writes a value with its unit', () {
      // Mutation: split at the first space only after the number's exponent
      // — `1e3 m` would lose its exponent.
      final g = Quantity.parse('9.81 m/s²');
      expect(g.value, 9.81);
      expect(g.unit, Unit.meterPerSecondSquared);
      expect(g.toString(), '9.81 m/s²');
      expect(Quantity.parse('1e3 m').value, 1000);
      expect(
        Quantity.parse('-40°C').valueIn(Unit.kelvin),
        closeTo(233.15, 1e-9),
      );
      expect(Quantity.parse('3').unit, Unit.one);
      expect(() => Quantity.parse('m/s'), throwsA(isA<UnitFormatException>()));
      final json = const Quantity(2.5, Unit.kilopascal).toJson();
      expect(json, <String, Object?>{'value': 2.5, 'unit': 'kPa'});
      expect(Quantity.fromJson(json), const Quantity(2.5, Unit.kilopascal));
      expect(
        () => Quantity.fromJson(<String, Object?>{'value': 'x', 'unit': 'm'}),
        throwsA(isA<UnitFormatException>()),
      );
    });
  });
}
