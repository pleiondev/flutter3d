/// A body's material state: what it holds, what it keeps that it does not
/// know, and how it compares.
///
///     dart test test/material_state_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:test/test.dart';

void main() {
  test('an empty state is the standard world: 20 °C and one atmosphere', () {
    const empty = MaterialState();
    expect(empty.temperature, standardAirTemperature);
    expect(empty.pressure, standardAtmosphere);
    expect(MaterialState.standard.temperature, standardAirTemperature);
    expect(MaterialState.standard.pressure, standardAtmosphere);
    expect(empty.phase, isNull);
  });

  test('temperature and pressure read in their SI units from any unit', () {
    final state = const MaterialState()
        .withQuantity(
          MaterialState.temperatureId,
          const Quantity(100.0, Unit.celsius),
        )
        .withQuantity(MaterialState.pressureId, const Quantity(2.0, Unit.bar));
    expect(state.temperature, closeTo(373.15, 1e-9));
    expect(state.pressure, closeTo(2e5, 1e-6));
  });

  test("a plugin's quantity survives the document untouched", () {
    final state = MaterialState.at(
      temperature: 600.0,
      phase: MaterialPhase.solid,
      also: <String, Quantity>{
        'forge.charring': const Quantity(0.25, Unit.one),
        MaterialState.wetnessId: const Quantity(0.5, Unit.percent),
      },
    );
    final text = jsonEncode(state.toJson());
    final read = MaterialState.fromJson(
      jsonDecode(text) as Map<String, Object?>,
    );
    expect(read, state);
    expect(read['forge.charring'], const Quantity(0.25, Unit.one));
    expect(read[MaterialState.wetnessId]!.unit, Unit.percent);
    expect(read.phase, MaterialPhase.solid);
    expect(jsonEncode(read.toJson()), text);
  });

  test('equal states are equal, whatever order they were built in', () {
    final a = const MaterialState()
        .withQuantity('a.x', const Quantity(1.0, Unit.meter))
        .withQuantity('b.y', const Quantity(2.0, Unit.second));
    final b = const MaterialState()
        .withQuantity('b.y', const Quantity(2.0, Unit.second))
        .withQuantity('a.x', const Quantity(1.0, Unit.meter));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.without('a.x'), isNot(b));
    expect(a.inPhase(MaterialPhase.gas), isNot(a));
  });

  test('a document with a bad id or quantity is refused, saying which', () {
    expect(
      () => MaterialState.fromJson(<String, Object?>{
        'quantities': <String, Object?>{
          'temperature': <String, Object?>{'value': 300.0, 'unit': 'K'},
        },
      }),
      throwsA(
        isA<MaterialFormatException>().having(
          (e) => e.message,
          'message',
          contains('<namespace>.<name>'),
        ),
      ),
    );
    expect(
      () => MaterialState.fromJson(<String, Object?>{
        'quantities': <String, Object?>{'f3d.temperature': 'hot'},
      }),
      throwsA(
        isA<MaterialFormatException>().having(
          (e) => e.message,
          'message',
          contains('f3d.temperature'),
        ),
      ),
    );
  });
}
