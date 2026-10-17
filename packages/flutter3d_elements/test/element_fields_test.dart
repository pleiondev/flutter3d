import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Fields that say nothing: what a backend written against 1.0 is to a
/// member added later.
final class _Silent extends ElementFields {
  const _Silent();
}

/// Fields that keep heat and water and nothing else.
final class _Damp extends ElementFields {
  double kelvin = 290.0;
  double kilograms = 0.0;
  double joules = 0.0;

  @override
  double temperatureOf(ElementBody body) => kelvin;

  @override
  double waterOf(ElementBody body) => kilograms;

  @override
  void addWater(ElementBody body, double kilograms) =>
      this.kilograms += kilograms;

  @override
  void addHeat(ElementBody body, double joules) => this.joules += joules;
}

void main() {
  const body = ElementBody(1);

  test('a member a backend does not answer is refused by name', () {
    const silent = _Silent();
    expect(
      () => silent.airTemperature,
      throwsA(
        isA<UnsupportedCapabilityException>().having(
          (e) => e.feature.name,
          'feature',
          'ElementFields.airTemperature',
        ),
      ),
    );
    expect(
      () => silent.addForce(body, Vector3.zero()),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
    expect(
      () => silent.quantityOf(body, FieldQuantity.temperature),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
  });

  test('a field is read and added to by quantity, in its unit', () {
    final damp = _Damp();
    final t = damp.quantityOf(body, FieldQuantity.temperature);
    expect(t.unit, Unit.kelvin);
    expect(t.valueIn(Unit.celsius), closeTo(16.85, 1e-9));

    damp
      ..addQuantity(body, FieldQuantity.water, const Quantity(500, Unit.gram))
      ..addQuantity(body, FieldQuantity.heat, const Quantity(2000, Unit.joule));
    expect(damp.kilograms, closeTo(0.5, 1e-12));
    expect(damp.joules, 2000.0);
    expect(
      damp.quantityOf(body, FieldQuantity.water).valueIn(Unit.kilogram),
      closeTo(0.5, 1e-12),
    );
    expect(
      () => damp.addQuantity(
        body,
        FieldQuantity.heat,
        const Quantity(1, Unit.kilogram),
      ),
      throwsA(isA<UnitMismatchException>()),
    );
    expect(
      () =>
          damp.quantityOf(body, const FieldQuantity('humidity', Unit.percent)),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
  });
}
