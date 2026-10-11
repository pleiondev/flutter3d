/// Which crash breaks a car's fuel cell: one harder than the test it was
/// built to pass, not a number of the game's.
///
///     flutter test test/wrecks/fuel_cell_test.dart
library;

import 'package:flutter3d_game_physics/wrecks.dart';
import 'package:test/test.dart';

void main() {
  test('a racing car\'s cell stands the FIA\'s frontal test, and a road '
      'car\'s FMVSS 301\'s', () {
    // Racing set its own 14 m/s. Mutation: `>=` for `>` — a crash exactly
    // as hard as the test it passed breaks it.
    expect(FuelCell.racing.breaksAt(15.0), isFalse);
    expect(FuelCell.racing.breaksAt(15.5), isTrue);
    expect(FuelCell.road.standsTo, closeTo(13.33, 0.01));
    expect(FuelCell.road.breaksAt(14.0), isTrue);
  });
}
